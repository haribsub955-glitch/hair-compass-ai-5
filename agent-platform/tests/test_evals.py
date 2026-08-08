"""Runs the adversarial corpus as a merge gate.

The single most important assertion in the repo is `test_corpus_has_zero_false_accepts`. Everything
else here guards the harness itself — a corpus that silently fails to load, or a case that silently
does not run, reads as coverage that does not exist.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from agent_server.evals import CORPUS_ROOT, CorpusError, load, run
from agent_server.packs.hair_compass import PACK_NAME, SAFETY_POLICY, gates_for

CORPUS_PATH = CORPUS_ROOT / "hair_compass" / "cases.yaml"


@pytest.fixture(scope="module")
def corpus():
    return load(CORPUS_PATH)


def test_corpus_loads_and_is_for_this_pack(corpus) -> None:
    assert corpus.pack == PACK_NAME
    assert len(corpus.cases) >= 40, "the corpus should be substantial enough to mean something"


def test_corpus_has_zero_false_accepts(corpus) -> None:
    """THE gate. A false accept is a claim the product must never make, shipped.

    There is no budget for these and there never should be. If this fails, either the safety layer
    regressed or someone changed an expectation in the corpus — both are things a human must look
    at before the change merges.
    """
    report = run(corpus, policy=SAFETY_POLICY, gates_for=gates_for)
    assert not report.false_accepts, "\n" + report.summary()


def test_corpus_stays_within_its_false_reject_budget(corpus) -> None:
    """Over-blocking is a real cost — the app's value is explaining things accurately — but it is a
    recoverable one, so it gets a budget rather than a hard zero."""
    report = run(corpus, policy=SAFETY_POLICY, gates_for=gates_for)
    assert len(report.false_rejects) <= corpus.false_reject_budget, "\n" + report.summary()


def test_corpus_decisions_match(corpus) -> None:
    report = run(corpus, policy=SAFETY_POLICY, gates_for=gates_for)
    assert not report.wrong_decisions, "\n" + report.summary()


def test_the_whole_report_is_green(corpus) -> None:
    report = run(corpus, policy=SAFETY_POLICY, gates_for=gates_for)
    assert report.ok, "\n" + report.summary()


def test_every_case_actually_ran(corpus) -> None:
    """Guards the silent-skip failure mode: a corpus can only be trusted if every claim in it was
    judged."""
    report = run(corpus, policy=SAFETY_POLICY, gates_for=gates_for)
    expected = sum(len(case.claims) for case in corpus.cases)
    assert report.total_claims == expected


def test_the_corpus_covers_every_rule_family(corpus) -> None:
    """A corpus that lost a whole category of adversarial case would still pass everything above."""
    tags = {tag for case in corpus.cases for tag in case.tags}
    for required in (
        "diagnosis",
        "efficacy",
        "myth",
        "unverified",
        "rx",
        "escalation",
        "injection",
    ):
        assert required in tags, f"corpus lost its {required!r} cases"


def test_the_corpus_guards_against_over_blocking(corpus) -> None:
    """Half the corpus must be claims that MUST survive. Without them the safety layer could pass
    by refusing everything."""
    guards = [c for c in corpus.cases if "false-reject-guard" in c.tags]
    assert len(guards) >= 15, "not enough must-survive cases to detect over-blocking"


# --------------------------------------------------------------------------------------------
# The harness must fail loud on a malformed corpus, never skip
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "body",
    [
        "cases: []",
        "cases:\n  - id: a\n    facts: nope\n    claims: []",
        "cases:\n  - id: a\n    facts: {}\n    claims:\n"
        "      - {text: x, category: bogus, allow: true}",
        "cases:\n  - id: a\n    facts: {}\n    claims:\n      - {text: x, category: observation}",
        "cases:\n  - id: a\n    facts: {}\n    claims: []\n"
        "  - id: a\n    facts: {}\n    claims: []",
        "cases:\n  - id: a\n    facts: {}\n    claims: []\n    expect_decision: maybe",
        "just-a-string",
    ],
    ids=[
        "empty",
        "bad-fixture",
        "bad-category",
        "missing-allow",
        "duplicate-id",
        "bad-decision",
        "not-a-mapping",
    ],
)
def test_a_malformed_corpus_raises_rather_than_skipping(tmp_path: Path, body: str) -> None:
    path = tmp_path / "bad.yaml"
    path.write_text(body, encoding="utf-8")
    with pytest.raises(CorpusError):
        load(path)


def test_invalid_yaml_raises_corpus_error(tmp_path: Path) -> None:
    path = tmp_path / "bad.yaml"
    path.write_text("cases: [\n  - unclosed", encoding="utf-8")
    with pytest.raises(CorpusError):
        load(path)
