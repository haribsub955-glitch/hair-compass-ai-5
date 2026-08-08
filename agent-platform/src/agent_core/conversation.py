"""The message shapes the loop passes around — ours, not any provider's.

Every provider spells a conversation differently: Anthropic nests `tool_use` blocks in assistant
content, OpenAI puts `tool_calls` beside it, others do something else again. If the loop spoke any
one of those dialects, swapping providers would mean editing the loop — exactly the coupling the
adapter boundary exists to prevent (CLAUDE.md §AR).

So the loop speaks this, and each adapter translates at its own edge.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, ConfigDict

from agent_core.dispatch import ToolCall, ToolResult


class Role(StrEnum):
    USER = "user"
    ASSISTANT = "assistant"


class Base(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Message(Base):
    """One conversational turn.

    A message carries at most one kind of payload beyond its text: either the tool calls the
    assistant made, or the results the host is handing back. Keeping both on one type (rather than
    a union) keeps the transcript a flat, serialisable list — which is what a resumable run needs.
    """

    role: Role
    text: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    tool_results: tuple[ToolResult, ...] = ()
    #: Attached images as `(media_type, base64_bytes)`. Only meaningful on a USER message.
    #:
    #: Carried as data beside the text, never spliced into it — an image is an input in a typed
    #: slot, exactly like the user's own words, and text inside a picture is still text the model
    #: reads. The output safety screen remains the backstop, since it does not care what prompted
    #: a claim.
    images: tuple[tuple[str, str], ...] = ()


class StopReason(StrEnum):
    END_TURN = "end_turn"
    TOOL_USE = "tool_use"
    MAX_TOKENS = "max_tokens"
    REFUSAL = "refusal"


class ModelTurn(Base):
    """What one model call produced, normalised.

    `text` is prose for the user. `tool_calls` is what it wants run. `stop_reason` is why it
    stopped — and it is read from the provider's own signal, never inferred from the text, because
    "it looks finished" and "it said it was finished" are different claims.
    """

    text: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    stop_reason: StopReason = StopReason.END_TURN
