"""The HTTP surface for an agent turn — the part a real phone talks to.

Three moving pieces, because a turn is not a request/response:

    POST /v1/turn                     open a turn; the response is an SSE stream
      <- event: tool_request          "run these, here are the call ids"
      -> POST /v1/turn/{id}/result    one per call, idempotent, authorized
      <- event: tool_request          (more waves, if the model asks)
      <- event: answer                the final text
      <- event: done

The stream carries *requests down*; results come back as ordinary POSTs rather than over the same
socket. That split is deliberate: a dropped SSE connection then loses only the notification, not the
work. The turn keeps running server-side, results still land, and a reconnecting client can be told
where things got to. Pushing results up the same socket would make the connection load-bearing, and
mobile connections are the least load-bearing thing there is.

**Known limit, stated rather than hidden:** if the stream drops mid-turn, this implementation has no
resume — the client cannot re-attach and collect the remaining events. That needs the durable run
state from ARCHITECTURE.md §0 finding 4, which is deliberately not built yet. Today a dropped stream
means a lost turn (the user retries); it does not mean a corrupted one, because every mutating call
is already idempotency-keyed.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from agent_core.contracts import PROTOCOL_VERSION, Principal
from agent_core.dispatch import CallStatus, DispatchStep, ToolResult
from agent_core.plans import PHOTO_FEATURE
from agent_core.tools import Platform
from agent_server.agent import Agent
from agent_server.analysis import ANALYSIS_PURPOSE
from agent_server.billing import resolve_plan_limits
from agent_server.core.errors import NotEntitled
from agent_server.packs.hair_compass_tools import TOOLS
from agent_server.privacy import require_consent
from agent_server.runs import RemoteDeviceExecutor, Run, RunRegistry

log = logging.getLogger("agent_server.turns")

#: Sending a photograph is not the same act as sending derived numbers, so it is its own purpose.
PHOTO_PURPOSE = "photo-analysis"

#: How long a phone has to answer one dispatch wave. Beyond this the step expires — reads become
#: retryable, mutations become UNKNOWN (docs/DISPATCH.md).
DEVICE_DEADLINE_SECONDS = 30.0

#: Emitted while a turn is thinking, so an idle SSE connection is not culled by a proxy that sees
#: no bytes. Purely a keep-alive; carries no meaning.
HEARTBEAT_SECONDS = 15.0


class TurnRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    #: Issued by `/v1/session`. Replaces the installation id, which the client picks and which
    #: therefore authenticated nothing.
    session_token: str
    user_text: str = Field(max_length=4000)
    #: Attachment ids from `POST /v1/attachments`. **Ids, never bytes.**
    #:
    #: Inline base64 was the smaller change and the wrong one: a 5 MB photo becomes ~6.7 MB of JSON
    #: on a phone, and a turn that then fails on consent or quota makes the user send it all again.
    #: Uploading separately also means an oversized or wrong-typed file is refused before any model
    #: spend.
    #:
    #: Capped here as well as at upload — three is more than a hair question needs, and more than
    #: that is someone using the turn as an upload channel.
    attachments: list[str] = Field(default_factory=list, max_length=3)
    platform: Platform = Platform.IOS
    #: Device tools this build actually implements. Subtractive only — see ToolRegistry.resolve.
    available_capabilities: list[str] = Field(default_factory=list)


class ResultSubmission(BaseModel):
    """One tool result from the phone.

    No principal, no run id, no tool name — the server already knows all three from the `call_id`
    it issued. Anything the client could state here would be a claim the server has to verify, so
    the field simply does not exist (ARCHITECTURE.md §5).
    """

    model_config = ConfigDict(extra="forbid")

    session_token: str
    result: ToolResult


def _sse(event: str, data: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(data, default=str)}\n\n"


def _step_payload(step: DispatchStep) -> dict[str, Any]:
    return {
        "parallel": step.parallel,
        "deadline_seconds": int(DEVICE_DEADLINE_SECONDS),
        "calls": [
            {
                "id": call.id,
                "tool": call.tool,
                "arguments": call.arguments,
                "idempotency_key": call.idempotency_key,
            }
            for call in step.calls
        ],
    }


class TurnService:
    """Runs one turn and yields SSE events for it.

    The turn executes as its own task while the generator below drains an event queue. That
    separation is what lets a tool request reach the phone *while* the agent is still blocked
    waiting for it — a single coroutine doing both would deadlock on itself.
    """

    def __init__(
        self,
        *,
        agent: Agent,
        runs: RunRegistry,
        identity=None,
        audit=None,
        plans=None,
        attachments=None,
    ) -> None:
        self._agent = agent
        self._runs = runs
        #: Needed to check a STORED consent grant. `/v1/analyze` has always done this; the
        #: streaming path never did, so the most expensive endpoint in the system sent health data
        #: across the border with nothing verified.
        self._identity = identity
        self._audit = audit
        self._plans = plans
        self._attachments = attachments

    async def authorize(self, principal: Principal, *, attachments: int = 0) -> None:
        """Every refusal for a turn, BEFORE a byte of the response is written.

        Deliberately not inside `stream`. That is an async generator handed to
        `StreamingResponse`, so by the time it runs the status line is already sent and raising
        produces "response already started" — the client gets a broken stream instead of a clean
        402 or 403. A refusal has to be a refusal, not a truncated success.

        Cheapest first, and both before a run is opened or a token is reserved.
        """
        if self._plans is not None and not self._plans.get(principal.plan_id).is_paid:
            raise NotEntitled(f"principal={principal.principal_id} plan={principal.plan_id}")

        # `/v1/analyze` has always checked this and the streaming path never did, so the same
        # personal data reached the same provider by whichever route the client picked — and under
        # PDPL the streaming route was an unconsented cross-border transfer.
        await require_consent(
            self._identity,
            principal,
            purpose=ANALYSIS_PURPOSE,
            crosses_border=True,
            audit=self._audit,
        )

        if attachments:
            # Checked BEFORE consent, because "your plan does not include this" is a different and
            # more useful answer than "you have not agreed to it" — telling someone to grant
            # consent for something they still could not use would be a dead end.
            if self._plans is not None and not self._plans.get(principal.plan_id).allows_feature(
                PHOTO_FEATURE
            ):
                raise NotEntitled(
                    f"principal={principal.principal_id} plan={principal.plan_id} feature=photos"
                )

            # A SECOND grant, and checked here rather than only at upload. The upload and the use
            # are separate moments, and consent can be withdrawn between them — a photo agreed to
            # an hour ago is not a photo agreed to now.
            await require_consent(
                self._identity,
                principal,
                purpose=PHOTO_PURPOSE,
                crosses_border=True,
                audit=self._audit,
            )

    async def _images(self, principal: Principal, ids: list[str]) -> tuple[tuple[str, str], ...]:
        """Resolve attachment ids to `(media_type, base64)`, deleting them as they are read.

        Scoped to this principal, so an id belonging to someone else does not resolve — and cannot
        be distinguished from one that never existed.
        """
        if not ids or self._attachments is None:
            return ()
        import base64

        taken = await self._attachments.take(principal_id=principal.principal_id, ids=ids)
        return tuple((media_type, base64.b64encode(data).decode()) for media_type, data in taken)

    async def stream(self, *, principal: Principal, request: TurnRequest) -> AsyncIterator[str]:
        # Resolved BEFORE the run opens: taking them deletes them, so a failure here must happen
        # before any work is done rather than halfway through a stream.
        images = await self._images(principal, request.attachments)

        run = await self._runs.open(principal)
        events: asyncio.Queue[tuple[str, dict[str, Any]]] = asyncio.Queue()

        async def on_dispatch(step: DispatchStep) -> None:
            await events.put(("tool_request", _step_payload(step)))

        tools = TOOLS.resolve(
            platform=request.platform,
            entitlement=principal.entitlement,
            protocol_version=PROTOCOL_VERSION,
            client_advertised=frozenset(request.available_capabilities) or None,
        )
        device = RemoteDeviceExecutor(
            run=run,
            runs=self._runs,
            tools=TOOLS,
            timeout_seconds=DEVICE_DEADLINE_SECONDS,
            on_dispatch=on_dispatch,
        )

        async def drive() -> None:
            try:
                # Per-plan caps, not the one process-wide number. The Agent is shared by every
                # concurrent turn, so the limits travel with the CALL rather than the instance —
                # otherwise a plan's max_output_tokens and max_iterations_per_turn are data that
                # nothing reads.
                limits = resolve_plan_limits(self._plans, principal.plan_id) if self._plans else {}
                result = await self._agent.run(
                    principal=principal,
                    device=device,
                    user_text=request.user_text,
                    images=images,
                    allowed_tools=tuple(t.name for t in tools),
                    max_output_tokens=limits.get("max_output_tokens"),
                    max_iterations=limits.get("max_iterations"),
                )
                await events.put(
                    (
                        "answer",
                        {
                            "text": result.text,
                            "served": result.served,
                            "safety": result.safety.decision.value if result.safety else "allow",
                            "iterations": result.iterations,
                            "usage": result.usage.model_dump(),
                            # The trace carries shapes and statuses only, never payloads (§9).
                            "trace": str(result.trace).splitlines(),
                        },
                    )
                )
            except Exception as exc:
                log.warning("turn %s failed: %s", run.id, type(exc).__name__)
                await events.put(
                    ("error", {"message": "That turn couldn't be completed.", "run_id": run.id})
                )
            finally:
                await events.put(("done", {"run_id": run.id}))

        task = asyncio.create_task(drive())
        yield _sse("open", {"run_id": run.id, "protocol_version": PROTOCOL_VERSION})
        try:
            while True:
                try:
                    name, payload = await asyncio.wait_for(events.get(), HEARTBEAT_SECONDS)
                except TimeoutError:
                    yield ": keep-alive\n\n"
                    continue
                yield _sse(name, payload)
                if name == "done":
                    break
        finally:
            # A client that disconnects must not leave the turn running and burning tokens.
            if not task.done():
                task.cancel()
            await self._runs.close(run)

    async def submit(self, *, principal: Principal, submission: ResultSubmission) -> dict[str, Any]:
        accepted = await self._runs.submit(principal=principal, result=submission.result)
        return {"accepted": accepted, "call_id": submission.result.call_id}


def result_from_device(
    call_id: str, payload: dict[str, Any] | None, *, ok: bool = True
) -> ToolResult:
    """Helper for clients and tests. The server never builds these — the phone does."""
    return ToolResult(
        call_id=call_id,
        status=CallStatus.SUCCEEDED if ok else CallStatus.FAILED,
        payload=payload,
    )


__all__ = [
    "DEVICE_DEADLINE_SECONDS",
    "ResultSubmission",
    "Run",
    "TurnRequest",
    "TurnService",
    "result_from_device",
]
