"""The Anthropic adapter — the only file in the repo that knows this provider exists.

Raw HTTPS rather than the SDK: one dependency fewer, and the wire format is small enough that the
translation is clearer written out than hidden behind a client library. Swapping providers means
adding a sibling file and changing one line of wiring (CLAUDE.md §AR).

**Quirks handled here, learned from the app's own integration:**

* Sending `thinking` or `temperature` to some models is a 400. Neither is sent.
* A refusal arrives as `stop_reason == "refusal"`, and the content block may still look like prose.
  Check the stop reason *before* reading content, or you serve a refusal as an answer.
* Tool calls come back as `tool_use` blocks inside assistant content, and results go back as
  `tool_result` blocks inside a *user* message. That asymmetry is the provider's, not ours, and it
  stops at this file.
"""

from __future__ import annotations

import json
from typing import Any

import httpx

from agent_core.contracts import Usage
from agent_core.conversation import Message, ModelTurn, StopReason
from agent_core.dispatch import ToolCall
from agent_core.tools import ToolSpec
from agent_server.adapters.llm.base import Capability, ModelAdapter, ProviderRefusal

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"

_STOP_REASONS = {
    "end_turn": StopReason.END_TURN,
    "tool_use": StopReason.TOOL_USE,
    "max_tokens": StopReason.MAX_TOKENS,
    "refusal": StopReason.REFUSAL,
    "stop_sequence": StopReason.END_TURN,
}


class AnthropicAdapter(ModelAdapter):
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        price_version: str = "2026-07",
        timeout_seconds: float = 60.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        if not api_key:
            raise RuntimeError("AnthropicAdapter needs an API key; it never ships in a client")
        self.name = "anthropic"
        self.model = model
        self.price_version = price_version
        self._key = api_key
        self._client = client or httpx.AsyncClient(timeout=timeout_seconds)

    def capabilities(self) -> frozenset[Capability]:
        return frozenset(
            {
                Capability.STRUCTURED_OUTPUT,
                Capability.STREAMING,
                Capability.IMAGE_INPUT,
                Capability.USAGE_ACCOUNTING,
                Capability.EXPLICIT_REFUSAL,
            }
        )

    # --- wire ---------------------------------------------------------------------------------

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self._client.post(
            API_URL,
            json=payload,
            headers={
                "x-api-key": self._key,
                "anthropic-version": API_VERSION,
                "content-type": "application/json",
            },
        )
        response.raise_for_status()
        return response.json()

    @staticmethod
    def _usage(body: dict[str, Any], model: str, price_version: str) -> Usage:
        raw = body.get("usage") or {}
        return Usage(
            input_tokens=int(raw.get("input_tokens", 0)),
            output_tokens=int(raw.get("output_tokens", 0)),
            cached_input_tokens=int(raw.get("cache_read_input_tokens", 0)),
            provider="anthropic",
            model=model,
            price_version=price_version,
        )

    # --- translation --------------------------------------------------------------------------

    @staticmethod
    def _tool_schema(spec: ToolSpec) -> dict[str, Any]:
        return {"name": spec.name, "description": spec.description, "input_schema": spec.schema}

    @staticmethod
    def _to_wire(messages: tuple[Message, ...]) -> list[dict[str, Any]]:
        """Our flat transcript into Anthropic's content-block shape."""
        wire: list[dict[str, Any]] = []
        for message in messages:
            blocks: list[dict[str, Any]] = []
            if message.tool_results:
                # Results go back as a USER message, which is the provider's convention.
                for result in message.tool_results:
                    blocks.append(
                        {
                            "type": "tool_result",
                            "tool_use_id": result.call_id,
                            "content": json.dumps(result.payload or {"error": result.error}),
                            "is_error": result.status.value != "succeeded",
                        }
                    )
                wire.append({"role": "user", "content": blocks})
                continue
            if message.text:
                blocks.append({"type": "text", "text": message.text})
            for call in message.tool_calls:
                blocks.append(
                    {
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.tool,
                        "input": call.arguments,
                    }
                )
            if blocks:
                wire.append({"role": message.role.value, "content": blocks})
        return wire

    @staticmethod
    def _from_wire(body: dict[str, Any]) -> ModelTurn:
        stop = _STOP_REASONS.get(str(body.get("stop_reason") or "end_turn"), StopReason.END_TURN)
        # Checked before reading content: a refusal's content block can read like a
        # perfectly ordinary answer.
        if stop is StopReason.REFUSAL:
            return ModelTurn(stop_reason=StopReason.REFUSAL)
        text_parts: list[str] = []
        calls: list[ToolCall] = []
        for block in body.get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                text_parts.append(str(block.get("text", "")))
            elif block.get("type") == "tool_use":
                arguments = block.get("input")
                calls.append(
                    ToolCall(
                        id=str(block.get("id", "")).ljust(8, "0")[:64],
                        tool=str(block.get("name", "")),
                        arguments=arguments if isinstance(arguments, dict) else {},
                    )
                )
        return ModelTurn(
            text="\n".join(p for p in text_parts if p).strip(),
            tool_calls=tuple(calls),
            stop_reason=stop,
        )

    # --- the interface ------------------------------------------------------------------------

    async def converse(
        self,
        *,
        system: str,
        messages: tuple[Message, ...],
        tools: tuple[ToolSpec, ...],
        max_output_tokens: int,
    ) -> tuple[ModelTurn, Usage]:
        payload: dict[str, Any] = {
            "model": self.model,
            "max_tokens": max_output_tokens,
            "system": system,
            "messages": self._to_wire(messages),
        }
        if tools:
            payload["tools"] = [self._tool_schema(t) for t in tools]
        # No `temperature`, no `thinking` — both 400 on some models in this family.
        body = await self._post(payload)
        return self._from_wire(body), self._usage(body, self.model, self.price_version)

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_output_tokens: int,
    ) -> tuple[dict[str, Any], Usage]:
        """Structured output via a single forced tool call — the provider's own constrained-decoding
        path, so the result is schema-valid by construction rather than by parsing and hoping."""
        payload = {
            "model": self.model,
            "max_tokens": max_output_tokens,
            "system": system,
            "messages": [{"role": "user", "content": user}],
            "tools": [
                {"name": "emit", "description": "Return the result.", "input_schema": schema}
            ],
            "tool_choice": {"type": "tool", "name": "emit"},
        }
        body = await self._post(payload)
        if str(body.get("stop_reason")) == "refusal":
            raise ProviderRefusal("provider declined")
        for block in body.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                result = block.get("input")
                if isinstance(result, dict):
                    return result, self._usage(body, self.model, self.price_version)
        # Forced tool choice returned no tool call. Fail loud rather than inventing an empty result,
        # which would look to the safety layer like "the model had nothing to say".
        raise ProviderRefusal("forced tool call produced no structured output")
