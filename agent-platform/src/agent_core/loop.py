"""The agent loop — one pure function that decides what happens next.

This is the smallest important file in the repo. Everything else exists to serve it.

An agent turn is: ask the model → it either answers or asks for tools → run the tools → ask again →
eventually it answers. The question at every step is "what now?", and that question has exactly one
right answer given the state. So it is a **pure function** over a frozen state: no I/O, no clock, no
network, no randomness. That is what makes it testable exhaustively, and what makes it portable —
today it is called by a FastAPI handler on a laptop, later by one in a datacenter, and it cannot
tell the difference.

**Safety terminals dominate.** They are checked first and in a fixed order, before anything about
what the model wants. An agent that is out of money, cancelled, or standing on an unknown tool
result does not get to argue for another iteration.

The one that deserves explaining is `unknown_result`. If a mutating device tool timed out, we do
not know whether it ran (see docs/DISPATCH.md). Continuing would mean reasoning from a state we
cannot observe — the model would happily narrate what "probably" happened and act on it. So an
unknown result is a hard stop: the turn ends, the user is told plainly, and nothing is retried.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

#: How many model calls one turn may make before we stop. Not a safety limit — a runaway limit.
#: A well-behaved turn uses two or three; anything approaching this is looping on itself.
DEFAULT_MAX_ITERATIONS = 8

#: How many times a truncated response may be continued. Bounded because a model that keeps hitting
#: the ceiling is producing something too long to be useful, and each continuation costs money.
MAX_RESUMES = 2

#: Consecutive empty responses before we give up. One is a hiccup; two is a pattern.
MAX_EMPTY = 2


class Frame(StrEnum):
    """What the model's last response was — the only thing the loop reads about it.

    Deliberately not "what the model said". The loop never inspects prose; it reads the shape of the
    response. Parsing meaning out of text is how a loop starts believing a model's claim that it is
    finished when it is not.
    """

    #: Text, no tool calls. The model considers itself done.
    FINAL = "final"
    #: The model wants tools run before it can answer.
    TOOL_CALLS = "tool_calls"
    #: Nothing usable came back.
    EMPTY = "empty"
    #: Hit the output ceiling mid-sentence.
    TRUNCATED = "truncated"
    #: The provider explicitly declined.
    REFUSED = "refused"


class Decision(StrEnum):
    DISPATCH = "dispatch"
    CONTINUE = "continue"
    FINALIZE = "finalize"
    #: Stop cleanly and serve whatever we have.
    STOP = "stop"
    #: Stop and serve nothing — the app falls back to its deterministic path.
    HARD_STOP = "hard_stop"


@dataclass(frozen=True, slots=True)
class LoopState:
    """Everything the decision depends on. All of it computed by the caller, none by the model.

    Every field is a fact the host established — a token count it measured, a cancellation it
    observed, a tool status it recorded. Nothing here is derived from a model-supplied string,
    because a model that could set `pending_work=False` could talk its way out of its own
    completion gate.
    """

    frame: Frame
    iteration: int = 0
    cancelled: bool = False
    budget_breached: bool = False
    #: A mutating tool whose outcome we cannot determine. See the module docstring.
    unknown_result: bool = False
    #: The completion gate's verdict. False means the turn has not achieved what it set out to.
    gate_passed: bool = True
    resume_count: int = 0
    consecutive_empty: int = 0
    max_iterations: int = DEFAULT_MAX_ITERATIONS

    @property
    def iterations_exhausted(self) -> bool:
        return self.iteration >= self.max_iterations


@dataclass(frozen=True, slots=True)
class LoopDecision:
    decision: Decision
    #: One short line, safe to log and to show a user. Never contains model output.
    reason: str


def decide(state: LoopState) -> LoopDecision:
    """What happens next. Pure — same state in, same decision out, always.

    Order is the design. Safety terminals first, in descending severity; only then what the model
    asked for. Re-ordering these is how a loop ends up spending money after a cancellation or
    reasoning past an effect it cannot see.
    """
    # --- terminals: nothing below this block gets to override them ---------------------------
    if state.cancelled:
        return LoopDecision(Decision.HARD_STOP, "cancelled")
    if state.unknown_result:
        return LoopDecision(
            Decision.HARD_STOP,
            "a device action's outcome is unknown — stopping rather than guessing",
        )
    if state.frame is Frame.REFUSED:
        return LoopDecision(Decision.HARD_STOP, "the provider declined this request")
    if state.budget_breached:
        # STOP, not HARD_STOP: we have already paid for whatever we have, so serve it.
        return LoopDecision(Decision.STOP, "out of budget for today")
    if state.iterations_exhausted:
        return LoopDecision(Decision.STOP, f"reached the {state.max_iterations}-step limit")

    # --- what the model actually wants --------------------------------------------------------
    if state.frame is Frame.TOOL_CALLS:
        return LoopDecision(Decision.DISPATCH, "running the requested tools")

    if state.frame is Frame.TRUNCATED:
        if state.resume_count >= MAX_RESUMES:
            return LoopDecision(Decision.STOP, "response kept overrunning; serving what we have")
        return LoopDecision(Decision.CONTINUE, "response was cut off — continuing")

    if state.frame is Frame.EMPTY:
        if state.consecutive_empty >= MAX_EMPTY:
            return LoopDecision(Decision.HARD_STOP, "the model returned nothing, repeatedly")
        return LoopDecision(Decision.CONTINUE, "empty response — retrying once")

    # FINAL. The model thinks it is done; the completion gate decides whether it is.
    if not state.gate_passed:
        if state.iteration + 1 >= state.max_iterations:
            # Out of room to fix it. Stop rather than serve something the gate rejected.
            return LoopDecision(Decision.STOP, "could not satisfy the completion check in time")
        return LoopDecision(Decision.CONTINUE, "the completion check has not been met yet")

    return LoopDecision(Decision.FINALIZE, "done")
