"""OpenAI-compatible adapter — LM Studio, vLLM, Ollama, or the OpenAI API itself.

This is the second implementation behind `ModelAdapter`, and it is the proof that the boundary is
real: the loop, the dispatcher, the ledger and the safety layer all run unchanged against a local
model on this machine. Nothing above this file learned that the provider changed
(CLAUDE.md §AR).

It is also the cheap testing path. A local model costs nothing per token, so the whole agent loop —
multi-step tool calling, parallel dispatch, terminals — can be exercised against a real model
rather than a script, for free, offline.

**How this format differs from Anthropic's, all of it absorbed here:**

* tools: Anthropic takes top-level `tools` with `input_schema`; this takes
  `tools[].function.parameters`.
* asking for a tool: Anthropic emits a `tool_use` block inside assistant content; this puts
  `message.tool_calls[]` beside the content.
* returning results: Anthropic wants `tool_result` blocks in a **user** message; this wants one
  `role: "tool"` message **per call**.
* arguments: an object there, a JSON **string** here, which must be parsed.
* why it stopped: `stop_reason` there, `finish_reason` here.

That last one on arguments is the trap: `arguments` arrives as text, and a local model will
occasionally emit something that is not valid JSON at all. Parsing it defensively here — and
failing the call rather than the turn — keeps a malformed argument from taking down the whole run.
"""

from __future__ import annotations

import json
import urllib.request
from typing import Any

import httpx

from agent_core.contracts import Usage
from agent_core.conversation import Message, ModelTurn, Role, StopReason
from agent_core.dispatch import ToolCall
from agent_core.tools import ToolSpec
from agent_server.adapters.llm.base import Capability, ModelAdapter, ProviderRefusal


def discover_loaded_model(base_url: str, *, timeout_seconds: float = 5.0) -> str:
    """Ask the server which model is ALREADY RESIDENT, rather than naming one.

    This exists because of a real and expensive mistake. LM Studio defaults to
    `justInTimeModelLoading: true`, so requesting a model by name does not fail when that model is
    not loaded — it **loads it**, evicting whatever the machine's owner had resident. A config file
    naming a model is therefore not a passive preference; it is an instruction to swap the GPU's
    contents on every deployment. Pinning a stale name in `.env` did exactly that, repeatedly, to
    someone who had deliberately loaded something else.

    So: blank `LLM_MODEL` means "use whatever is loaded". Only a model reporting `state == "loaded"`
    is eligible, and embedding and reranker models are excluded because their ids do not advertise
    what they are (the LM Studio notes are explicit that `type` tags lie).

    Falls back to raising rather than guessing a name — guessing is what caused the problem.
    """
    request = urllib.request.Request(base_url.rstrip("/").removesuffix("/v1") + "/api/v0/models")
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        body = json.load(response)

    loaded = [
        entry
        for entry in body.get("data", [])
        if entry.get("state") == "loaded"
        and "embed" not in str(entry.get("id", "")).lower()
        and "rerank" not in str(entry.get("id", "")).lower()
    ]
    if not loaded:
        raise RuntimeError(
            f"no chat model is loaded at {base_url}. Load one, or set LLM_MODEL explicitly "
            "(which will JIT-load it and evict whatever is resident)."
        )
    # Largest resident model, as a proxy for "the one deliberately loaded" — a tiny draft or
    # utility model sitting alongside a working model should not win.
    loaded.sort(key=lambda e: int(e.get("max_context_length") or 0), reverse=True)
    return str(loaded[0]["id"])


_FINISH_REASONS = {
    "stop": StopReason.END_TURN,
    "tool_calls": StopReason.TOOL_USE,
    "function_call": StopReason.TOOL_USE,
    "length": StopReason.MAX_TOKENS,
    "content_filter": StopReason.REFUSAL,
}


class OpenAICompatAdapter(ModelAdapter):
    """Any endpoint speaking the OpenAI chat-completions shape.

    `base_url` points at the server; for LM Studio on this machine that is
    `http://127.0.0.1:1234/v1`. `api_key` is optional because a local server does not need one —
    which is exactly why this adapter must never be the prod default: `require_key` guards that.
    """

    def __init__(
        self,
        *,
        base_url: str,
        model: str,
        api_key: str = "",
        name: str = "openai-compat",
        price_version: str = "local",
        timeout_seconds: float = 180.0,
        supports_tools: bool = True,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.name = name
        self.model = model
        self.price_version = price_version
        self._url = base_url.rstrip("/") + "/chat/completions"
        self._key = api_key
        self._supports_tools = supports_tools
        # Local models are slow enough that the default httpx timeout fires mid-generation and looks
        # like a provider outage. 180s is generous on purpose.
        self._client = client or httpx.AsyncClient(timeout=timeout_seconds)

    def capabilities(self) -> frozenset[Capability]:
        caps = {Capability.STREAMING, Capability.USAGE_ACCOUNTING}
        if self._supports_tools:
            # Structured output rides on the same tool-calling machinery here.
            caps |= {Capability.STRUCTURED_OUTPUT}
        return frozenset(caps)

    # --- wire ---------------------------------------------------------------------------------

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        headers = {"content-type": "application/json"}
        if self._key:
            headers["authorization"] = f"Bearer {self._key}"
        response = await self._client.post(self._url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()

    def _usage(self, body: dict[str, Any]) -> Usage:
        raw = body.get("usage") or {}
        return Usage(
            input_tokens=int(raw.get("prompt_tokens", 0)),
            output_tokens=int(raw.get("completion_tokens", 0)),
            provider=self.name,
            model=self.model,
            price_version=self.price_version,
        )

    # --- translation --------------------------------------------------------------------------

    @staticmethod
    def _tool_schema(spec: ToolSpec) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": spec.name,
                "description": spec.description,
                "parameters": spec.schema,
            },
        }

    @staticmethod
    def _to_wire(system: str, messages: tuple[Message, ...]) -> list[dict[str, Any]]:
        wire: list[dict[str, Any]] = [{"role": "system", "content": system}]
        for message in messages:
            if message.tool_results:
                # One `tool` message per result — not one message containing all of them.
                for result in message.tool_results:
                    wire.append(
                        {
                            "role": "tool",
                            "tool_call_id": result.call_id,
                            "content": json.dumps(result.payload or {"error": result.error}),
                        }
                    )
                continue
            if message.role is Role.ASSISTANT and message.tool_calls:
                wire.append(
                    {
                        "role": "assistant",
                        "content": message.text or None,
                        "tool_calls": [
                            {
                                "id": call.id,
                                "type": "function",
                                "function": {
                                    "name": call.tool,
                                    # Arguments go back out as a STRING, as they arrived.
                                    "arguments": json.dumps(call.arguments),
                                },
                            }
                            for call in message.tool_calls
                        ],
                    }
                )
                continue
            if message.images:
                # The OpenAI content-block shape, which LM Studio and every compatible server
                # accept for vision models: text first, then one `image_url` per image, each a
                # `data:` URI. Text first because a trailing question reads as being about the
                # images above it.
                blocks: list[dict[str, Any]] = []
                if message.text:
                    blocks.append({"type": "text", "text": message.text})
                blocks.extend(
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{media_type};base64,{payload}"},
                    }
                    for media_type, payload in message.images
                )
                wire.append({"role": message.role.value, "content": blocks})
            elif message.text:
                wire.append({"role": message.role.value, "content": message.text})
        return wire

    @staticmethod
    def _parse_arguments(raw: Any) -> dict[str, Any] | None:
        """`arguments` is a JSON *string*. A local model sometimes emits something that is not JSON.

        Returns None on anything unparseable, so the caller can fail that one call instead of
        letting a malformed argument take down the turn.
        """
        if isinstance(raw, dict):
            return raw
        if not isinstance(raw, str) or not raw.strip():
            return {}
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None

    def _from_wire(self, body: dict[str, Any]) -> ModelTurn:
        choices = body.get("choices") or []
        if not choices:
            return ModelTurn(text="")
        choice = choices[0]
        message = choice.get("message") or {}
        finish = _FINISH_REASONS.get(
            str(choice.get("finish_reason") or "stop"), StopReason.END_TURN
        )
        if finish is StopReason.REFUSAL:
            return ModelTurn(stop_reason=StopReason.REFUSAL)

        calls: list[ToolCall] = []
        for raw_call in message.get("tool_calls") or []:
            if not isinstance(raw_call, dict):
                continue
            function = raw_call.get("function") or {}
            arguments = self._parse_arguments(function.get("arguments"))
            if arguments is None:
                # Skip the malformed call rather than guessing at what it meant. The model sees the
                # remaining results next turn and can ask again.
                continue
            call_id = str(raw_call.get("id") or "").strip() or f"call_{len(calls):04d}"
            calls.append(
                ToolCall(
                    id=call_id.ljust(8, "0")[:64],
                    tool=str(function.get("name", "")),
                    arguments=arguments,
                )
            )

        # Some servers report `stop` even when they emitted tool calls. Trust the calls.
        if calls and finish is StopReason.END_TURN:
            finish = StopReason.TOOL_USE

        content = message.get("content")
        text = content if isinstance(content, str) else ""
        if not text.strip():
            # Reasoning models (gemma-4, several qwen fine-tunes) put their working in a separate
            # field and can leave `content` empty. Falling back keeps a usable answer rather than
            # reporting an empty turn — see the lmstudio skill's note on this.
            reasoning = message.get("reasoning_content")
            if isinstance(reasoning, str):
                text = reasoning
        return ModelTurn(text=text.strip(), tool_calls=tuple(calls), stop_reason=finish)

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
            "messages": self._to_wire(system, messages),
            "max_tokens": max_output_tokens,
            # Deterministic: an agent whose tool choices vary run to run cannot be debugged.
            "temperature": 0.0,
        }
        if tools and self._supports_tools:
            payload["tools"] = [self._tool_schema(t) for t in tools]
            payload["tool_choice"] = "auto"
        body = await self._post(payload)
        return self._from_wire(body), self._usage(body)

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_output_tokens: int,
    ) -> tuple[dict[str, Any], Usage]:
        """Structured output via the server's JSON-schema mode, which LM Studio enforces with
        constrained decoding — so the result is schema-valid by construction."""
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "max_tokens": max_output_tokens,
            "temperature": 0.0,
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "out", "strict": True, "schema": schema},
            },
        }
        body = await self._post(payload)
        choices = body.get("choices") or []
        message = (choices[0].get("message") if choices else {}) or {}
        for field in ("content", "reasoning_content"):
            raw = message.get(field)
            if not isinstance(raw, str) or not raw.strip():
                continue
            parsed = self._parse_arguments(raw)
            if parsed is not None:
                return parsed, self._usage(body)
            # A reasoning model wraps the object in prose. Take the outermost braces.
            start, end = raw.find("{"), raw.rfind("}")
            if start != -1 and end > start:
                recovered = self._parse_arguments(raw[start : end + 1])
                if recovered is not None:
                    return recovered, self._usage(body)
        raise ProviderRefusal("no parseable structured output")
