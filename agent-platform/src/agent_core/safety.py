"""The medical-claims boundary, as code.

Why this exists: the Action Gate governs *effects* — it has nothing to say about whether a sentence
the model produced is a diagnosis. Hair Compass's whole product stance is "a documentation and
education instrument, not a diagnosis engine", and App Store review scrutinises diagnostic claims.
A stance enforced only by a sentence in a prompt is enforced by nothing: one prompt edit silently
removes it and no test fails.

**Two layers, and the second exists because the first has a hole.**

*Category rules* are the primary layer: the model returns its answer as tagged claims, and each tag
is checked against gates the app computed for itself. The hole is that **the model tags its own
claims**. A diagnosis labelled `education` sails straight through — not hypothetically, it is the
obvious failure mode of any self-tagging scheme.

*Text rules* close that. They are deterministic patterns applied to the claim's words regardless of
its tag, so a mis-tagged claim is caught by what it says rather than by what it calls itself. They
are cheap, they are level 1 on the complexity ladder, and they run first. They are also blunt, so
they are written narrowly and every one carries a test proving it does not over-block the legitimate
sentence it most resembles.

Neither layer knows anything about hair. Both are supplied per app by its `ServerPolicyPack`
(ARCHITECTURE.md §4), so a second app brings its own rules without touching this file.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass

from agent_core.contracts import Claim, ClaimCategory, SafetyDecision, SafetyVerdict

#: A gate name no pack may ever emit. Mapping a category to this makes it unconditionally
#: impossible — the rule cannot be satisfied by any envelope, however the app computes its gates.
#: Used for claims that are never permissible rather than merely conditional.
NEVER = "__never__"


@dataclass(frozen=True, slots=True)
class TextRule:
    """A deterministic deny rule over a claim's text.

    `applies_to` narrows the rule to certain categories; `None` means every category, which is the
    normal case — a rule that only fired on the tag the model chose would be defeated by choosing a
    different tag, which is the whole reason this layer exists.

    `reason` is recorded on the verdict and must name the rule, not quote the claim. The claim text
    is model output derived from user data; it does not belong in an audit reason (§9).

    `unless` is the stand-down clause, and it is the difference between a usable rule and an
    unusable one. "Biotin helps hair grow" must be denied; "biotin does not help unless you have a
    rare deficiency" is a sentence the app actively wants to say. Expressing that as one clever
    regex was tried and was wrong — the negation sits *before* the term as often as after it. Two
    plain patterns, one to fire and one to stand down, are correct and readable.
    """

    name: str
    pattern: re.Pattern[str]
    reason: str
    applies_to: frozenset[ClaimCategory] | None = None
    unless: re.Pattern[str] | None = None

    def denies(self, claim: Claim) -> bool:
        if self.applies_to is not None and claim.category not in self.applies_to:
            return False
        if self.pattern.search(claim.text) is None:
            return False
        return self.unless is None or self.unless.search(claim.text) is None


class SafetyPolicy:
    """Which claim categories are permitted, what each one requires, and what text is never allowed.

    `requires` maps a category to the gate names that must ALL be present for a claim of that
    category to survive. A category absent from `requires` is unconditionally allowed; a category
    mapped to a set containing `NEVER` is unconditionally denied.

    `version` is recorded on every verdict. Changing the rules without changing the version makes
    two differently-judged responses indistinguishable in the audit log.
    """

    __slots__ = ("_requires", "text_rules", "version")

    def __init__(
        self,
        version: str,
        requires: Mapping[ClaimCategory, frozenset[str]],
        text_rules: Sequence[TextRule] = (),
    ) -> None:
        if not version:
            raise ValueError("a safety policy must carry a version")
        self.version = version
        self._requires = dict(requires)
        self.text_rules = tuple(text_rules)

    def requirements(self, category: ClaimCategory) -> frozenset[str]:
        return self._requires.get(category, frozenset())

    def permits(self, category: ClaimCategory, gates: frozenset[str]) -> bool:
        required = self.requirements(category)
        if NEVER in required:
            return False
        return required <= gates

    def denied_by_text(self, claim: Claim) -> TextRule | None:
        for rule in self.text_rules:
            if rule.denies(claim):
                return rule
        return None


#: Sentence boundary. Deliberately simple — over-splitting is harmless here (each fragment is
#: judged on its own), while under-splitting would let a forbidden clause ride along inside a
#: sentence that survives.
_SENTENCE = re.compile(r"(?<=[.!?])\s+|\n+")


def screen_text(text: str, *, policy: SafetyPolicy) -> tuple[str, SafetyVerdict]:
    """Judge free prose — a chat answer rather than a structured claim list.

    The agent loop produces paragraphs, not tagged claims, so the category rules have nothing to
    grip. The **text rules** still do: they judge what a sentence says, which is exactly what is
    needed here.

    Judged sentence by sentence so one forbidden clause costs one sentence rather than the whole
    answer — the user still gets the observations, the trend and the escalation, minus the
    diagnosis. If everything is stripped, the result is FALLBACK and the app renders its own
    deterministic summary instead.

    This is weaker than `evaluate`: it cannot enforce the 24-week efficacy gate, because that needs
    a claim's *category* and prose does not carry one. A pack that must gate efficacy in chat has to
    make the model emit claims. Stated plainly rather than papered over.
    """
    kept: list[str] = []
    reasons: list[str] = []

    for sentence in _SENTENCE.split(text):
        candidate = sentence.strip()
        if not candidate:
            continue
        probe = Claim(text=candidate, category=ClaimCategory.OBSERVATION)
        denying = policy.denied_by_text(probe)
        if denying is not None:
            reasons.append(f"{denying.name}: {denying.reason}")
            continue
        kept.append(candidate)

    if not kept:
        return "", SafetyVerdict(
            decision=SafetyDecision.FALLBACK,
            verifier_version=policy.version,
            reasons=tuple(reasons) or ("nothing to serve",),
        )
    joined = " ".join(kept)
    if reasons:
        return joined, SafetyVerdict(
            decision=SafetyDecision.REDACT,
            verifier_version=policy.version,
            reasons=tuple(reasons),
        )
    return joined, SafetyVerdict(decision=SafetyDecision.ALLOW, verifier_version=policy.version)


def evaluate(
    claims: Iterable[Claim],
    *,
    policy: SafetyPolicy,
    gates: frozenset[str],
) -> tuple[tuple[Claim, ...], SafetyVerdict]:
    """Judge a model response. Returns the claims that may be shown, plus why.

    Three outcomes, and the choice between them is deliberately conservative:

    * **ALLOW** — every claim passed. Serve it.
    * **REDACT** — some claims failed, some survived. Serve only the survivors. This is honest: the
      user still gets the observations and trends, just not the impermissible efficacy or diagnosis
      statement.
    * **FALLBACK** — nothing survived, or the model returned nothing at all. The app renders its own
      deterministic result instead.

    FALLBACK is not an error. The app already has a good deterministic path that works offline, so
    falling back to it is always safe — which is exactly why an uncertain result must choose it
    rather than guess (core-safety M1: fail visibly, never silently degrade). A claim the model
    itself marked `uncertain` is treated as failing, on the same reasoning: the cost of withholding
    a hedged sentence is trivial next to the cost of publishing a wrong medical one.

    Order matters. Text rules run before category rules, so a claim that is forbidden by what it
    says is refused whatever it calls itself.
    """
    kept: list[Claim] = []
    reasons: list[str] = []

    for claim in claims:
        denying = policy.denied_by_text(claim)
        if denying is not None:
            reasons.append(f"{denying.name}: {denying.reason}")
            continue
        if claim.uncertain:
            reasons.append(f"{claim.category.value}: model flagged it uncertain")
            continue
        if not policy.permits(claim.category, gates):
            missing = sorted(policy.requirements(claim.category) - gates)
            if NEVER in missing:
                reasons.append(f"{claim.category.value}: never permitted")
            else:
                reasons.append(f"{claim.category.value}: missing {', '.join(missing)}")
            continue
        kept.append(claim)

    if not kept:
        return (), SafetyVerdict(
            decision=SafetyDecision.FALLBACK,
            verifier_version=policy.version,
            reasons=tuple(reasons) or ("model returned no claims",),
        )
    if reasons:
        return tuple(kept), SafetyVerdict(
            decision=SafetyDecision.REDACT,
            verifier_version=policy.version,
            reasons=tuple(reasons),
        )
    return tuple(kept), SafetyVerdict(
        decision=SafetyDecision.ALLOW,
        verifier_version=policy.version,
    )
