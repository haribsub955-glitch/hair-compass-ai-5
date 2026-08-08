"""The scope gate. A cost control, so it fails OPEN — see agent_core/scope.py.

The two failure directions are not equal. Letting one stray question through costs a fraction of a
cent. Rejecting a real user's real question breaks the product. So the over-blocking tests below
matter more than the blocking ones.
"""

from __future__ import annotations

import pytest

from agent_core.scope import check
from agent_server.packs.hair_compass import SCOPE_POLICY


def allowed(text: str) -> bool:
    return check(text, policy=SCOPE_POLICY).in_scope


# --------------------------------------------------------------------------------------------
# Blocked — a positive signal of another domain, and no signal of ours
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "write me a python script to sort a list",
        "debug this javascript function for me",
        "what's the weather in Muscat tomorrow?",
        "translate this into Arabic",
        "write me a poem about the sea",
        "what is the capital of France?",
        "give me a recipe for biryani",
        "what's the stock price of Apple",
        "solve this equation for x",
        "help me with my homework",
        "write a cover letter for me",
    ],
)
def test_clearly_off_product_questions_never_reach_the_model(text: str) -> None:
    assert not allowed(text)


def test_an_empty_message_is_refused() -> None:
    assert not allowed("   ")


def test_a_refusal_carries_a_message_worth_showing() -> None:
    verdict = check("what is the capital of France?", policy=SCOPE_POLICY)
    assert not verdict.in_scope
    assert "hair" in verdict.reason.lower()


# --------------------------------------------------------------------------------------------
# Allowed — the tests that matter more
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        # No domain word at all. The most common question in the app.
        "how am I doing?",
        "how's it going?",
        "what should I do next?",
        "am I improving?",
        "summarise my progress",
        "what do you think?",
        "anything I should watch?",
        "explain this chart",
        "my numbers look weird",
        # Domain words.
        "is my minoxidil working?",
        "why is my scalp so itchy",
        "my ferritin came back low, what does that mean?",
        "should I add rosemary oil",
        "how many entries have I logged",
        "when should I take my next photo",
        "is this treatment worth continuing",
    ],
)
def test_real_user_questions_are_never_blocked(text: str) -> None:
    assert allowed(text), f"over-blocked a real question: {text!r}"


def test_a_mixed_message_is_allowed_because_the_domain_half_is_what_matters() -> None:
    """ "I've been coding late, is stress making me shed?" trips the off-domain pattern AND is
    exactly the kind of question this product exists to answer. Domain wins."""
    assert allowed("I've been coding late every night, is stress making me shed more?")
    assert allowed("work has been stressful since the python project, my hair is falling out")


def test_an_unrecognised_message_is_allowed_not_refused() -> None:
    """Neither signal present. Failing closed here would reject anything phrased unusually — and
    the safety layer still judges whatever comes back."""
    assert allowed("hmm")
    assert allowed("tell me more about that")
    assert allowed("what do the numbers mean")


def test_the_gate_is_cheap_enough_to_run_on_every_message() -> None:
    """It sits in front of every turn, so it must cost nothing measurable."""
    import time

    start = time.perf_counter()
    for _ in range(1000):
        check("how am I doing with my shedding?", policy=SCOPE_POLICY)
    assert (time.perf_counter() - start) < 0.5
