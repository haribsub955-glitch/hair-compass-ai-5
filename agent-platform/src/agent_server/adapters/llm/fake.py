"""A deterministic adapter for tests and Windows development.

This is what makes the whole server testable end-to-end with no network, no API key, and no macOS
(ARCHITECTURE.md §12). It is a test double, not a fallback: it is never selected by configuration in
prod, only injected explicitly.
"""

from __future__ import annotations

from typing import Any

from agent_core.contracts import Usage
from agent_core.conversation import ModelTurn, Role
from agent_server.adapters.llm.base import Capability, ModelAdapter, ProviderRefusal


class FakeAdapter(ModelAdapter):
    """Replays a scripted response. `refuse=True` exercises the refusal path, which is otherwise
    hard to trigger on demand against a real provider."""

    def __init__(
        self,
        payload: dict[str, Any] | None = None,
        *,
        usage: Usage | None = None,
        refuse: bool = False,
        caps: frozenset[Capability] | None = None,
    ) -> None:
        self.name = "fake"
        self.model = "fake-1"
        self.price_version = "fake"
        self._payload = payload if payload is not None else {"claims": []}
        self._usage = usage or Usage(
            input_tokens=100,
            output_tokens=50,
            provider="fake",
            model="fake-1",
            price_version="fake",
        )
        self._refuse = refuse
        self._caps = caps if caps is not None else frozenset(Capability)
        self._turns: list[ModelTurn] = []
        self.calls: list[dict[str, Any]] = []
        self.conversations: list[dict[str, Any]] = []

    def capabilities(self) -> frozenset[Capability]:
        return self._caps

    def script(self, turns: list[ModelTurn]) -> FakeAdapter:
        """Queue a sequence of model turns for `converse` to replay.

        This is what makes a multi-step agent turn testable with no network: script "ask for two
        tools", then "answer", and the loop runs exactly as it would against a real provider. The
        last turn repeats if the loop asks for more, so a test that loops further than expected
        terminates instead of hanging.
        """
        self._turns = list(turns)
        return self

    async def converse(
        self,
        *,
        system: str,
        messages: tuple[Any, ...],
        tools: tuple[Any, ...],
        max_output_tokens: int,
    ) -> tuple[ModelTurn, Usage]:
        self.conversations.append(
            {"system": system, "messages": messages, "tools": tuple(t.name for t in tools)}
        )
        if self._refuse:
            raise ProviderRefusal("scripted refusal")
        if not self._turns:
            return ModelTurn(text="(nothing scripted)"), self._usage
        # How many times this conversation has already been answered.
        answered = sum(1 for m in messages if getattr(m, "role", None) == Role.ASSISTANT)
        return self._turns[min(answered, len(self._turns) - 1)], self._usage

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_output_tokens: int,
    ) -> tuple[dict[str, Any], Usage]:
        self.calls.append(
            {"system": system, "user": user, "schema": schema, "max": max_output_tokens}
        )
        if self._refuse:
            raise ProviderRefusal("scripted refusal")
        return self._payload, self._usage
