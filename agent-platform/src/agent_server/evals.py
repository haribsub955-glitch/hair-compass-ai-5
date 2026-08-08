"""The eval harness — runs the adversarial corpus and scores it by error KIND.

The number that matters is **false accepts**, not pass rate. A suite reporting "94% passing" can be
leaking every diagnosis it was built to catch, because the 6% failing are all in one direction. So
this reports the two error kinds separately and the caller fails the build on the one that ships a
claim the product must not make.

`load` fails loud on a malformed corpus rather than skipping a case (core-safety M1). A case that
silently does not run is worse than no case at all: it reads as coverage that does not exist.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from ruamel.yaml import YAML, YAMLError

from agent_core.contracts import Claim, ClaimCategory, SafetyDecision
from agent_core.safety import SafetyPolicy, evaluate

CORPUS_ROOT = Path(__file__).resolve().parents[2] / "evals"


class CorpusError(ValueError):
    """A malformed corpus. Always surfaced — never a skipped case."""


@dataclass(frozen=True, slots=True)
class ExpectedClaim:
    claim: Claim
    allow: bool


@dataclass(frozen=True, slots=True)
class Case:
    id: str
    intent: str
    tags: frozenset[str]
    facts: dict[str, Any]
    claims: tuple[ExpectedClaim, ...]
    user_text: str = ""
    expect_decision: SafetyDecision | None = None


@dataclass(frozen=True, slots=True)
class Corpus:
    version: int
    pack: str
    false_reject_budget: int
    cases: tuple[Case, ...]


@dataclass(frozen=True, slots=True)
class Failure:
    case_id: str
    intent: str
    text: str
    detail: str


@dataclass
class Report:
    """Scored corpus run. `ok` is deliberately asymmetric: any false accept fails, while false
    rejects are allowed a budget, because over-blocking degrades the product without endangering
    anyone."""

    total_claims: int = 0
    false_accepts: list[Failure] = field(default_factory=list)
    false_rejects: list[Failure] = field(default_factory=list)
    wrong_decisions: list[Failure] = field(default_factory=list)
    false_reject_budget: int = 0

    @property
    def ok(self) -> bool:
        return (
            not self.false_accepts
            and not self.wrong_decisions
            and len(self.false_rejects) <= self.false_reject_budget
        )

    def summary(self) -> str:
        lines = [
            f"claims judged: {self.total_claims}",
            f"FALSE ACCEPTS: {len(self.false_accepts)}   (a claim that must not ship, shipped)",
            f"false rejects: {len(self.false_rejects)}/{self.false_reject_budget} budget",
            f"wrong decisions: {len(self.wrong_decisions)}",
        ]
        for failure in self.false_accepts:
            lines.append(f"  ACCEPT {failure.case_id}: {failure.intent}\n         {failure.detail}")
        for failure in self.false_rejects:
            lines.append(f"  reject {failure.case_id}: {failure.intent}\n         {failure.detail}")
        for failure in self.wrong_decisions:
            lines.append(f"  verdict {failure.case_id}: {failure.detail}")
        return "\n".join(lines)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CorpusError(message)


def load(path: Path) -> Corpus:
    try:
        raw = YAML(typ="safe").load(path.read_text(encoding="utf-8"))
    except YAMLError as exc:
        raise CorpusError(f"{path.name}: invalid YAML: {exc}") from exc

    _require(isinstance(raw, dict), f"{path.name}: corpus must be a mapping")
    fixtures = raw.get("fixtures") or {}
    _require(isinstance(fixtures, dict), f"{path.name}: fixtures must be a mapping")

    raw_cases = raw.get("cases")
    _require(
        isinstance(raw_cases, list) and bool(raw_cases), f"{path.name}: cases must be non-empty"
    )

    cases: list[Case] = []
    seen: set[str] = set()
    for index, entry in enumerate(raw_cases):
        where = f"{path.name}: cases[{index}]"
        _require(isinstance(entry, dict), f"{where}: must be a mapping")
        case_id = entry.get("id")
        _require(isinstance(case_id, str) and bool(case_id), f"{where}: needs a non-empty id")
        _require(case_id not in seen, f"{where}: duplicate id {case_id!r}")
        seen.add(case_id)

        facts_ref = entry.get("facts")
        if isinstance(facts_ref, str):
            _require(facts_ref in fixtures, f"{where}: unknown fixture {facts_ref!r}")
            facts = dict(fixtures[facts_ref])
        elif isinstance(facts_ref, dict):
            facts = dict(facts_ref)
        else:
            raise CorpusError(f"{where}: facts must be a fixture name or a mapping")

        raw_claims = entry.get("claims")
        _require(isinstance(raw_claims, list), f"{where}: claims must be a list")

        claims: list[ExpectedClaim] = []
        for claim_index, raw_claim in enumerate(raw_claims):
            claim_where = f"{where}.claims[{claim_index}]"
            _require(isinstance(raw_claim, dict), f"{claim_where}: must be a mapping")
            text = raw_claim.get("text")
            category = raw_claim.get("category")
            allow = raw_claim.get("allow")
            _require(isinstance(text, str) and bool(text), f"{claim_where}: needs text")
            _require(
                category in {c.value for c in ClaimCategory},
                f"{claim_where}: unknown category {category!r}",
            )
            _require(isinstance(allow, bool), f"{claim_where}: needs an explicit allow: true|false")
            claims.append(
                ExpectedClaim(
                    claim=Claim(
                        text=text,
                        category=ClaimCategory(str(category)),
                        uncertain=bool(raw_claim.get("uncertain", False)),
                    ),
                    allow=bool(allow),
                )
            )

        expect_decision = entry.get("expect_decision")
        if expect_decision is not None:
            _require(
                expect_decision in {d.value for d in SafetyDecision},
                f"{where}: unknown expect_decision {expect_decision!r}",
            )

        cases.append(
            Case(
                id=case_id,
                intent=str(entry.get("intent", "")),
                tags=frozenset(entry.get("tags") or ()),
                facts=facts,
                claims=tuple(claims),
                user_text=str(entry.get("user_text", "")),
                expect_decision=(
                    SafetyDecision(str(expect_decision)) if expect_decision is not None else None
                ),
            )
        )

    return Corpus(
        version=int(raw.get("version", 1)),
        pack=str(raw.get("pack", "")),
        false_reject_budget=int(raw.get("false_reject_budget", 0)),
        cases=tuple(cases),
    )


def run(
    corpus: Corpus,
    *,
    policy: SafetyPolicy,
    gates_for: Any,
) -> Report:
    """Judge every case. `gates_for` is the pack's own gate derivation, so the corpus exercises the
    real path — a harness that computed gates itself would be testing the harness."""
    report = Report(false_reject_budget=corpus.false_reject_budget)

    for case in corpus.cases:
        gates = gates_for(case.facts)
        kept, verdict = evaluate((e.claim for e in case.claims), policy=policy, gates=gates)
        kept_texts = {c.text for c in kept}
        report.total_claims += len(case.claims)

        for expected in case.claims:
            was_kept = expected.claim.text in kept_texts
            if was_kept and not expected.allow:
                report.false_accepts.append(
                    Failure(case.id, case.intent, expected.claim.text, "kept, but must be refused")
                )
            elif not was_kept and expected.allow:
                report.false_rejects.append(
                    Failure(
                        case.id,
                        case.intent,
                        expected.claim.text,
                        "refused, but must be allowed "
                        f"({'; '.join(verdict.reasons) or 'no reason'})",
                    )
                )

        if case.expect_decision is not None and verdict.decision is not case.expect_decision:
            report.wrong_decisions.append(
                Failure(
                    case.id,
                    case.intent,
                    "",
                    f"expected {case.expect_decision.value}, got {verdict.decision.value}",
                )
            )

    return report
