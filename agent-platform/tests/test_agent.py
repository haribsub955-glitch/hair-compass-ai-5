"""The agent runner, end to end against a fake provider and a fake phone.

No network, no API key, no macOS — the whole multi-step loop runs on Windows in milliseconds
(ARCHITECTURE.md §12).
"""

from __future__ import annotations

import pytest

from agent_core.contracts import Entitlement, Principal
from agent_core.conversation import Message, ModelTurn, Role, StopReason
from agent_core.dispatch import CallStatus, DispatchStep, ToolCall, ToolResult
from agent_core.loop import Decision
from agent_server.adapters.llm.fake import FakeAdapter
from agent_server.agent import Agent
from agent_server.ledger import InMemoryLedger
from agent_server.packs.hair_compass_tools import TOOLS

P1 = Principal(
    app_id="hair-compass",
    principal_id="p1",
    installation_id="i1",
    data_subject_id="d1",
    entitlement=Entitlement.PRO,
)
P2 = Principal(
    app_id="hair-compass",
    principal_id="p2",
    installation_id="i2",
    data_subject_id="d2",
    entitlement=Entitlement.PRO,
)

ALL_TOOLS = (
    "recall_memory",
    "read_recent_entries",
    "read_lab_results",
    "search_evidence",
    "add_calendar_event",
)


class Phone:
    """Answers every call. `statuses` overrides the outcome for a named tool."""

    def __init__(self, statuses: dict[str, CallStatus] | None = None) -> None:
        self.waves: list[tuple[bool, list[str]]] = []
        self._statuses = statuses or {}

    async def execute(self, step: DispatchStep) -> tuple[ToolResult, ...]:
        self.waves.append((step.parallel, [c.tool for c in step.calls]))
        return tuple(
            ToolResult(
                call_id=c.id,
                status=self._statuses.get(c.tool, CallStatus.SUCCEEDED),
                payload={"ok": True},
            )
            for c in step.calls
        )


async def _server_tool(call: ToolCall) -> ToolResult:
    return ToolResult(call_id=call.id, status=CallStatus.SUCCEEDED, payload={"entries": []})


def _agent(adapter: FakeAdapter, *, budget: int = 500_000, ledger=None, **kw) -> Agent:
    return Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=ledger or InMemoryLedger(daily_budget=budget),
        server_tools={"search_evidence": _server_tool},
        system_prompt="be careful",
        max_output_tokens=256,
        **kw,
    )


def _call(cid: str, tool: str, **kw) -> ToolCall:
    return ToolCall(id=cid, tool=tool, arguments={}, **kw)


# --------------------------------------------------------------------------------------------
# The happy path
# --------------------------------------------------------------------------------------------


async def test_a_multi_step_turn_runs_to_an_answer() -> None:
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE,
                tool_calls=(
                    _call("c_00000001", "recall_memory"),
                    _call("c_00000002", "read_recent_entries"),
                ),
            ),
            ModelTurn(text="Here is how you're doing.", stop_reason=StopReason.END_TURN),
        ]
    )
    phone = Phone()
    result = await _agent(adapter).run(
        device=phone, principal=P1, user_text="how am I doing?", allowed_tools=ALL_TOOLS
    )
    assert result.served
    assert result.text == "Here is how you're doing."
    assert result.iterations == 2
    assert result.decision.decision is Decision.FINALIZE


async def test_reads_go_out_together_and_writes_alone() -> None:
    """The latency decision, observed from the phone's side."""
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE,
                tool_calls=(
                    _call("c_00000001", "recall_memory"),
                    _call("c_00000002", "read_recent_entries"),
                    _call("c_00000003", "add_calendar_event", idempotency_key="k1"),
                ),
            ),
            ModelTurn(text="done", stop_reason=StopReason.END_TURN),
        ]
    )
    phone = Phone()
    await _agent(adapter).run(device=phone, principal=P1, user_text="x", allowed_tools=ALL_TOOLS)
    assert phone.waves[0] == (True, ["recall_memory", "read_recent_entries"])
    assert phone.waves[1] == (False, ["add_calendar_event"])


async def test_server_tools_run_in_process_and_never_reach_the_phone() -> None:
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE,
                tool_calls=(
                    _call("c_00000001", "search_evidence"),
                    _call("c_00000002", "recall_memory"),
                ),
            ),
            ModelTurn(text="done", stop_reason=StopReason.END_TURN),
        ]
    )
    phone = Phone()
    await _agent(adapter).run(device=phone, principal=P1, user_text="x", allowed_tools=ALL_TOOLS)
    assert phone.waves == [(True, ["recall_memory"])]


async def test_tool_results_are_fed_back_to_the_model() -> None:
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE, tool_calls=(_call("c_00000001", "recall_memory"),)
            ),
            ModelTurn(text="done", stop_reason=StopReason.END_TURN),
        ]
    )
    result = await _agent(adapter).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=ALL_TOOLS
    )
    fed_back = [m for m in result.messages if m.tool_results]
    assert len(fed_back) == 1
    assert fed_back[0].role is Role.USER


# --------------------------------------------------------------------------------------------
# Terminals
# --------------------------------------------------------------------------------------------


async def test_an_unknown_device_outcome_stops_before_paying_for_another_model_call() -> None:
    """The model's next turn was scripted to say "I've booked it". It must never be asked."""
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE,
                tool_calls=(_call("c_00000001", "add_calendar_event", idempotency_key="k1"),),
            ),
            ModelTurn(text="I've booked it for you.", stop_reason=StopReason.END_TURN),
        ]
    )
    phone = Phone({"add_calendar_event": CallStatus.UNKNOWN})
    result = await _agent(adapter).run(
        device=phone, principal=P1, user_text="book it", allowed_tools=ALL_TOOLS
    )
    assert result.decision.decision is Decision.HARD_STOP
    assert not result.served
    assert result.text == ""
    assert len(adapter.conversations) == 1, "paid for a model call whose answer was unusable"


async def test_a_refusal_serves_nothing_and_falls_back() -> None:
    result = await _agent(FakeAdapter(refuse=True)).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=ALL_TOOLS
    )
    assert result.decision.decision is Decision.HARD_STOP
    assert not result.served


async def test_exhausting_the_budget_stops_and_still_serves() -> None:
    """STOP, not HARD_STOP — the user gets what was already paid for."""
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE, tool_calls=(_call("c_00000001", "recall_memory"),)
            )
        ]
    )
    result = await _agent(adapter, budget=400).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=ALL_TOOLS
    )
    assert result.decision.decision is Decision.STOP
    assert result.served


async def test_a_looping_model_is_capped() -> None:
    """A model that only ever asks for tools must not run forever."""
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE, tool_calls=(_call("c_00000001", "recall_memory"),)
            )
        ]
    )
    result = await _agent(adapter, max_iterations=3).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=ALL_TOOLS
    )
    assert result.iterations == 3
    assert result.decision.decision is Decision.STOP


# --------------------------------------------------------------------------------------------
# Spend
# --------------------------------------------------------------------------------------------


async def test_every_model_call_is_metered() -> None:
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE, tool_calls=(_call("c_00000001", "recall_memory"),)
            ),
            ModelTurn(text="done", stop_reason=StopReason.END_TURN),
        ]
    )
    ledger = InMemoryLedger(daily_budget=500_000)
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=ledger,
        server_tools={},
        system_prompt="s",
        max_output_tokens=256,
    )
    result = await agent.run(device=phone_, principal=P1, user_text="x", allowed_tools=ALL_TOOLS)
    # The fake bills 100in/50out per call; two calls, both settled.
    assert result.usage.input_tokens == 200
    assert await ledger.spent_today("p1") == 300


async def test_only_the_allowed_tools_are_offered_to_the_model() -> None:
    adapter = FakeAdapter().script([ModelTurn(text="done", stop_reason=StopReason.END_TURN)])
    await _agent(adapter).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=("recall_memory",)
    )
    assert adapter.conversations[0]["tools"] == ("recall_memory",)


async def test_an_unknown_tool_name_is_rejected_before_the_turn_starts() -> None:
    adapter = FakeAdapter().script([ModelTurn(text="done")])
    with pytest.raises(Exception, match="not in the catalog"):
        await _agent(adapter).run(
            device=Phone(), principal=P1, user_text="x", allowed_tools=("nonexistent",)
        )


async def test_the_trace_records_shapes_not_payloads() -> None:
    """Traces get logged. Tool results are the user's personal data (ARCHITECTURE.md §9)."""
    adapter = FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE, tool_calls=(_call("c_00000001", "recall_memory"),)
            ),
            ModelTurn(text="secret answer text", stop_reason=StopReason.END_TURN),
        ]
    )
    result = await _agent(adapter).run(
        device=Phone(), principal=P1, user_text="x", allowed_tools=ALL_TOOLS
    )
    trace = str(result.trace)
    assert "recall_memory" in trace
    assert "secret answer text" not in trace
    assert "ok" not in trace.replace("tool_calls", "")


# --------------------------------------------------------------------------------------------
# Guardrails wired into the loop — scope before spend, safety on the answer
# --------------------------------------------------------------------------------------------


async def test_an_off_scope_question_costs_nothing_at_all() -> None:
    """No model call, no ledger reservation, no device round trip."""
    from agent_server.packs.hair_compass import SCOPE_POLICY

    adapter = FakeAdapter().script(
        [ModelTurn(text="here is your python", stop_reason=StopReason.END_TURN)]
    )
    ledger = InMemoryLedger(daily_budget=500_000)
    phone = Phone()
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=ledger,
        server_tools={},
        system_prompt="s",
        scope_policy=SCOPE_POLICY,
    )
    result = await agent.run(
        device=phone_, principal=P1, user_text="write me a python script", allowed_tools=ALL_TOOLS
    )
    assert adapter.conversations == []
    assert phone.waves == []
    assert await ledger.spent_today("p1") == 0
    assert result.usage.input_tokens == 0
    assert "hair" in result.text.lower()


async def test_an_in_scope_question_proceeds_normally() -> None:
    from agent_server.packs.hair_compass import SCOPE_POLICY

    adapter = FakeAdapter().script(
        [ModelTurn(text="You're doing well.", stop_reason=StopReason.END_TURN)]
    )
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=InMemoryLedger(daily_budget=500_000),
        server_tools={},
        system_prompt="s",
        scope_policy=SCOPE_POLICY,
    )
    result = await agent.run(
        device=phone_, principal=P1, user_text="how am I doing?", allowed_tools=ALL_TOOLS
    )
    assert len(adapter.conversations) == 1
    assert result.text == "You're doing well."


async def test_a_diagnosis_in_the_answer_is_stripped_before_it_reaches_the_user() -> None:
    """The system prompt asks the model not to diagnose. This is what makes it so."""
    from agent_server.packs.hair_compass import SAFETY_POLICY

    adapter = FakeAdapter().script(
        [
            ModelTurn(
                text="You've logged 187 entries. Your thinning is androgenetic alopecia. "
                "Your ferritin is below range — worth raising with a clinician.",
                stop_reason=StopReason.END_TURN,
            )
        ]
    )
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=InMemoryLedger(daily_budget=500_000),
        server_tools={},
        system_prompt="s",
        safety_policy=SAFETY_POLICY,
    )
    result = await agent.run(
        device=phone_, principal=P1, user_text="how am I doing?", allowed_tools=ALL_TOOLS
    )
    assert "alopecia" not in result.text
    assert "187 entries" in result.text
    assert "ferritin" in result.text
    assert result.safety is not None
    assert result.safety.decision.value == "redact"
    assert result.served


async def test_an_answer_that_is_entirely_impermissible_falls_back() -> None:
    from agent_server.packs.hair_compass import SAFETY_POLICY

    adapter = FakeAdapter().script(
        [
            ModelTurn(
                text="Your hair loss is androgenetic alopecia.", stop_reason=StopReason.END_TURN
            )
        ]
    )
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=InMemoryLedger(daily_budget=500_000),
        server_tools={},
        system_prompt="s",
        safety_policy=SAFETY_POLICY,
    )
    result = await agent.run(
        device=phone_, principal=P1, user_text="what is this?", allowed_tools=ALL_TOOLS
    )
    assert result.text == ""
    assert not result.served, "the app must render its own deterministic summary instead"


async def test_a_clean_answer_passes_through_untouched() -> None:
    from agent_server.packs.hair_compass import SAFETY_POLICY

    clean = "Shedding has eased from 58 to 42 over two weeks."
    adapter = FakeAdapter().script([ModelTurn(text=clean, stop_reason=StopReason.END_TURN)])
    phone_ = Phone()
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=InMemoryLedger(daily_budget=500_000),
        server_tools={},
        system_prompt="s",
        safety_policy=SAFETY_POLICY,
    )
    result = await agent.run(
        device=phone_, principal=P1, user_text="how am I doing?", allowed_tools=ALL_TOOLS
    )
    assert result.text == clean
    assert result.safety is not None and result.safety.decision.value == "allow"


# --------------------------------------------------------------------------------------------
# Vision. Verified end to end against a real vision model, not only asserted here.
# --------------------------------------------------------------------------------------------


def test_an_image_renders_as_content_blocks_with_the_text_first() -> None:
    """The shape a vision server actually accepts: text block, then one `image_url` per image as a
    `data:` URI. Text first because a trailing question reads as being about the images above it.

    Confirmed against LM Studio with a vision model: a synthetic image with a known answer (red
    square, blue circle) came back correctly described, which is what proves the model SAW it —
    a hair photo would have proved nothing, since plausible hair prose can be produced from the
    text prompt alone.
    """
    from agent_server.adapters.llm.openai_compat import OpenAICompatAdapter

    message = Message(
        role=Role.USER,
        text="what is this?",
        images=(("image/jpeg", "QUJD"),),
    )
    wire = OpenAICompatAdapter._to_wire("sys", (message,))
    blocks = wire[-1]["content"]

    assert [b["type"] for b in blocks] == ["text", "image_url"]
    assert blocks[0]["text"] == "what is this?"
    assert blocks[1]["image_url"]["url"] == "data:image/jpeg;base64,QUJD"


def test_a_message_with_no_image_keeps_the_plain_string_shape() -> None:
    """Content blocks only when there is something to put in them — a text-only turn must not
    change shape for every deployment that has no vision model."""
    from agent_server.adapters.llm.openai_compat import OpenAICompatAdapter

    wire = OpenAICompatAdapter._to_wire("sys", (Message(role=Role.USER, text="hello"),))
    assert wire[-1]["content"] == "hello"


def test_several_images_all_reach_the_wire() -> None:
    from agent_server.adapters.llm.openai_compat import OpenAICompatAdapter

    message = Message(
        role=Role.USER,
        text="compare these",
        images=(("image/jpeg", "AAA"), ("image/png", "BBB")),
    )
    blocks = OpenAICompatAdapter._to_wire("sys", (message,))[-1]["content"]
    assert [b["type"] for b in blocks] == ["text", "image_url", "image_url"]
    assert blocks[2]["image_url"]["url"].startswith("data:image/png;base64,")


def test_a_file_that_lies_about_its_type_is_refused() -> None:
    """Sniffed, never trusted. A `.jpg` that is really HTML is how a stored payload reaches
    whatever renders it later."""
    from agent_server.attachments import AttachmentRejected, sniff

    assert sniff(b"\xff\xd8\xff\x00") == "image/jpeg"
    assert sniff(b"\x89PNG\r\n\x1a\n rest") == "image/png"
    for hostile in (b"<html><script>", b"%PDF-1.4", b"GIF89a", b""):
        with pytest.raises(AttachmentRejected):
            sniff(hostile)
