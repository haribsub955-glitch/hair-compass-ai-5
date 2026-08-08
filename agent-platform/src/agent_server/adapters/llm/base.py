"""The LLM boundary — the one interface we own.

Nothing outside `adapters/llm/` may import a provider SDK, name a model string, or know a provider's
payload shape. Swapping Anthropic for anyone else must touch exactly one file in this package
(CLAUDE.md §AR, ARCHITECTURE.md §4).

The capability matrix exists because "model agnostic" is not a shared function signature. Providers
differ on structured output, tool semantics, streaming, refusals, token accounting and cancellation.
A one-line provider swap can compile perfectly and quietly drop a guarantee the safety layer depends
on — so a pack *declares* what it needs, and an adapter that cannot supply it is rejected at startup
rather than discovered in production.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any, Protocol, runtime_checkable

from agent_core.contracts import Usage


class Capability(StrEnum):
    #: Can be made to return output conforming to a supplied JSON schema. The safety layer is built
    #: on claim categories, so without this there is nothing to verify — it is not optional for us.
    STRUCTURED_OUTPUT = "structured_output"
    STREAMING = "streaming"
    IMAGE_INPUT = "image_input"
    #: Reports token counts we can bill against. Without it the cost ledger can only ever estimate,
    #: and reservations can never be reconciled.
    USAGE_ACCOUNTING = "usage_accounting"
    #: Signals a refusal distinguishably, rather than returning prose that merely reads like one.
    EXPLICIT_REFUSAL = "explicit_refusal"


class ProviderRefusal(Exception):
    """The provider declined. Distinct from a transport failure: a refusal must not be retried, and
    must not be shown to the user as provider text (SD — end users get generic errors)."""


@runtime_checkable
class ModelAdapter(Protocol):
    """What the platform needs from any provider."""

    name: str
    model: str
    price_version: str

    def capabilities(self) -> frozenset[Capability]: ...

    async def complete_structured(
        self,
        *,
        system: str,
        user: str,
        schema: dict[str, Any],
        max_output_tokens: int,
    ) -> tuple[dict[str, Any], Usage]:
        """Return the parsed object plus what it cost.

        Raises `ProviderRefusal` on an explicit refusal, and `ProviderUnavailable` on transport or
        rate-limit failure — never a provider exception type, which would leak the vendor into
        calling code and break the one-file swap rule.
        """
        ...

    async def converse(
        self,
        *,
        system: str,
        messages: tuple[Any, ...],
        tools: tuple[Any, ...],
        max_output_tokens: int,
    ) -> tuple[Any, Usage]:
        """One agent step: the conversation so far in, a `ModelTurn` out.

        The adapter owns translation in both directions — our neutral `Message`/`ToolCall` shapes
        into whatever this provider wants, and its response back into a `ModelTurn`. That
        translation is the entire reason this boundary exists: the loop must never learn that one
        provider nests tool calls inside assistant content while another puts them alongside it.

        `stop_reason` must come from the provider's own signal. Inferring "it sounds finished" from
        the text is how a loop stops a turn the model was still in the middle of.
        """
        ...


def require(adapter: ModelAdapter, needed: frozenset[Capability]) -> None:
    """Fail at startup if the configured provider cannot supply what a pack requires.

    Deliberately not a silent downgrade: dropping `STRUCTURED_OUTPUT` would make the safety verifier
    unenforceable while everything still appeared to work.

    Reserve this for capabilities whose absence breaks a *guarantee*. A capability that merely
    degrades quality belongs in `warn_missing` — listing it here makes the guard cry wolf, and a
    guard that blocks working configurations is one someone eventually deletes.
    """
    missing = needed - adapter.capabilities()
    if missing:
        raise RuntimeError(
            f"provider {adapter.name!r} lacks required capabilities: "
            f"{', '.join(sorted(m.value for m in missing))}"
        )


def warn_missing(adapter: ModelAdapter, preferred: frozenset[Capability]) -> tuple[str, ...]:
    """Report capabilities whose absence degrades quality without breaking a guarantee.

    Returned rather than swallowed so the caller logs it and `/health` can show it. Degrading is
    allowed; degrading *silently* is not (core-safety M1) — an operator must be able to see that
    this deployment is running in a reduced mode.
    """
    return tuple(sorted(m.value for m in preferred - adapter.capabilities()))
