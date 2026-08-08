"""Hair Compass's `ServerPolicyPack`: its prompt, its safety rules, its gates.

This is the per-app layer (ARCHITECTURE.md §4). It is the only place that knows what a hair
treatment is, or that 24 weeks is the point at which efficacy becomes fair to judge. The platform
core stays blind to all of it — adding a second app means adding a second pack, not editing the
core.

The `facts` dict arrives from the app's own `AIContextBuilder`, and everything in it is untrusted
client content (§5). That is fine for *prompting* — it is the user's own data and the worst case is
a bad answer for that user. It is emphatically not fine for *deciding*, which is why the gates below
are the narrow exception that needs explaining:

`efficacy_window_open` is derived from a client-supplied number. A patched client could set it and
unlock efficacy claims about its own user's data. That is accepted, deliberately: the claim would be
about data the attacker fabricated for themselves, it costs them their own quota, and it touches no
other user, no money, and no server state. It sits squarely in `device_cooperative`. The gates that
would be worth attacking — entitlement and budget — are derived server-side and never appear here.
"""

from __future__ import annotations

import re
from typing import Any

from agent_core.contracts import ClaimCategory
from agent_core.safety import NEVER, SafetyPolicy, TextRule
from agent_core.scope import ScopePolicy
from agent_server.adapters.llm.base import Capability

PACK_NAME = "hair-compass"
PACK_VERSION = "2026-07-29.1"

#: The app's `AIContext` schema versions this pack was written against. A snapshot from outside this
#: set is rejected before any spend — prompting against fields that have moved is how a safety rule
#: silently stops matching anything.
SUPPORTED_SCHEMA_VERSIONS = frozenset({1})

#: Absence breaks a guarantee, so the server refuses to start.
#: - STRUCTURED_OUTPUT: without it the claim-category safety layer has nothing to judge.
#: - USAGE_ACCOUNTING: without it the cost ledger can only ever estimate, and a reservation can
#:   never be reconciled — so spending becomes unbounded in a way nobody notices until the bill.
REQUIRED_CAPABILITIES = frozenset({Capability.STRUCTURED_OUTPUT, Capability.USAGE_ACCOUNTING})

#: Absence degrades quality but breaks nothing, so it is logged loudly and allowed.
#: EXPLICIT_REFUSAL was originally listed as required, which was wrong: without it a provider
#: refusal simply arrives as ordinary prose and is screened by the safety layer like any other
#: answer. That is a worse experience, not an unsafe one — and requiring it blocked every local
#: model, which is a guard crying wolf.
PREFERRED_CAPABILITIES = frozenset({Capability.EXPLICIT_REFUSAL})

#: Weeks before a treatment's effect may be discussed at all. Anchored to docs/TrackingSpec.md and
#: mirrored from `HairAnalytics.outcomeWindowWeeks` in the app. The duplication is intentional: the
#: server must not trust the client to tell it what the threshold is.
OUTCOME_WINDOW_WEEKS = 24

GATE_EFFICACY = "efficacy_window_open"
GATE_HAS_HISTORY = "has_history"

# --------------------------------------------------------------------------------------------
# Deterministic text rules — the layer that catches a mis-tagged claim
# --------------------------------------------------------------------------------------------
#
# Every rule below is narrow on purpose, and every one has a paired test proving it does NOT block
# the legitimate sentence it most resembles. A blunt rule that suppresses honest education is a real
# cost: the app's whole value is explaining things accurately.

#: Clinical conditions this app documents. Naming one *about the user* is a diagnosis whatever the
#: model tagged it; naming one in general is ordinary education and must stay allowed.
#: `seborrh?o?eic` deliberately covers the American, British and misspelled forms — a rule that a
#: different spelling walks straight past is not a rule. (The corpus caught exactly this.)
_CONDITIONS = (
    r"androgenetic alopecia|androgenic alopecia|male[- ]pattern|female[- ]pattern|"
    r"alopecia areata|telogen effluvium|traction alopecia|seborrh?o?eic dermatitis|"
    r"scarring alopecia|lichen planopilaris|frontal fibrosing"
)

#: Systemic conditions a hair app has no business naming about anyone. Deliberately specific:
#: "thyroid disease" is listed, bare "thyroid" is not, because "your TSH is out of range, and
#: thyroid affects hair" is a sentence the app should be able to say.
_SYSTEMIC = (
    r"cancer|carcinoma|tumou?r|lymphoma|leuk(?:a)?emia|lupus|diabetes|"
    r"hypothyroidism|hyperthyroidism|thyroid (?:cancer|disease)"
)

#: A person-referring word within a short window of a condition name. Covers "you have X",
#: "your X", "this is X", "those patches are X" — the shapes a diagnosis actually takes. General
#: education ("androgenetic alopecia is the most common cause of hair loss") has no such word
#: before the condition and passes untouched.
#:
#: The demonstratives are matched loosely rather than requiring an immediately following copula:
#: "Those round patches are alopecia areata" puts two words between them, and a rule that missed
#: that sentence would miss most real diagnoses.
PERSONAL_DIAGNOSIS = re.compile(
    rf"\b(?:you|your|you're|yours|this|that|these|those)\b"
    rf"[^.]{{0,80}}?\b(?:{_CONDITIONS}|{_SYSTEMIC})\b",
    re.IGNORECASE,
)

#: RxGate's posture, enforced server-side: the app never recommends *starting* a medication. It may
#: discuss one the user already logged, and it may say "raise it with a clinician".
RECOMMENDS_STARTING_RX = re.compile(
    r"\b(?:you\s+should|you\s+could|you\s+might|i\s+(?:recommend|suggest)|try|start|begin|"
    r"consider\s+(?:starting|taking)|get\s+on)\b[^.]{0,60}?"
    r"\b(?:finasteride|dutasteride|oral\s+minoxidil|propecia|avodart|spironolactone)\b",
    re.IGNORECASE,
)

#: Myths the app names-and-excludes in its Learn tab. Fires on an ASSERTION of benefit; the paired
#: `MYTH_DEBUNKED` stand-down keeps the debunking sentence — which is the one the app actually wants
#: to say — fully allowed. A single tempered regex was tried here first and was wrong: the negation
#: sits *before* the myth term at least as often as after it ("No evidence links drinking water to
#: hair growth"), so the temper never saw it. The corpus caught that.
_MYTH_TERMS = (
    r"biotin|collagen|hair\s+gummies|hair,?\s+skin\s+(?:and|&)\s+nails|"
    r"drinking[^.]{0,15}water|water\s+intake|hydration|coffee|caffeine\s+intake|"
    r"trimming|cutting\s+(?:your\s+)?hair|wearing\s+a\s+hat|\bhats?\b"
)
_BENEFIT = r"help|helps|grow|grows|growth|thicken|thicker|improve|improves|boost|boosts|work|works"
MYTH_ASSERTED_AS_FACT = re.compile(
    rf"\b(?:{_MYTH_TERMS})\b[^.]{{0,80}}?\b(?:{_BENEFIT})\b", re.IGNORECASE
)
MYTH_DEBUNKED = re.compile(
    r"\bno\b|\bnot\b|n't|placebo|unless|myth|only if|no evidence|rather than|instead of",
    re.IGNORECASE,
)

#: Claims from docs/TrackingSpec.md's "Explicitly NOT built" list — they failed the app's own
#: adversarial verification, so the app must never assert them however confidently a model does.
UNVERIFIED_CLAIM = re.compile(
    r"hair\s+diameter\s+diversity|anisotrichosis|"
    r"(?:cu\s*:\s*zn|copper[^.]{0,15}zinc)\s*ratio|serum\s+zinc|"
    r"12[- ]week\s+plateau|"
    r"\bLLLT\b[^.]{0,30}\b(?:80|eighty)\s*%",
    re.IGNORECASE,
)

TEXT_RULES = (
    TextRule(
        name="personal_diagnosis",
        pattern=PERSONAL_DIAGNOSIS,
        reason="names a clinical condition about this person",
    ),
    TextRule(
        name="recommends_starting_rx",
        pattern=RECOMMENDS_STARTING_RX,
        reason="recommends starting a prescription medication",
    ),
    TextRule(
        name="myth_asserted_as_fact",
        pattern=MYTH_ASSERTED_AS_FACT,
        unless=MYTH_DEBUNKED,
        reason="asserts a benefit the Learn library names as a myth",
    ),
    TextRule(
        name="unverified_claim",
        pattern=UNVERIFIED_CLAIM,
        reason="asserts a finding that failed the tracking spec's verification",
    ),
)

SAFETY_POLICY = SafetyPolicy(
    version=f"{PACK_NAME}/{PACK_VERSION}",
    text_rules=TEXT_RULES,
    requires={
        # Never permissible. The product is a documentation and education instrument; naming a
        # condition the user did not state is the line it must not cross, and App Store review
        # scrutinises exactly this.
        ClaimCategory.DIAGNOSIS: frozenset({NEVER}),
        # "Is it working?" is only a fair question past the judging window. Before that, any answer
        # is noise presented as signal — the single most misleading thing this app could say.
        ClaimCategory.EFFICACY: frozenset({GATE_EFFICACY}),
        # A trend needs something to trend against.
        ClaimCategory.TREND: frozenset({GATE_HAS_HISTORY}),
        # OBSERVATION, EDUCATION and ESCALATION are unconditional. Escalation in particular must
        # never be gated — "this is worth raising with a clinician" has to survive every rule.
    },
)

# --------------------------------------------------------------------------------------------
# Scope — what this agent will and will not spend a token on
# --------------------------------------------------------------------------------------------
#
# Blocks only on a POSITIVE signal of another domain. "How am I doing?" carries no hair word and is
# the single most common thing a user asks, so a gate demanding domain vocabulary would reject the
# product's main question. See agent_core/scope.py on why a cost control fails open.

DOMAIN_TERMS = re.compile(
    r"\b(?:hair|hairs|scalp|shed|shedding|thinning|balding|bald|regrow|regrowth|follicle|"
    r"minoxidil|finasteride|dutasteride|rosemary|ketoconazole|biotin|collagen|saw\s+palmetto|"
    r"microneedl\w*|derma\s?roller|prp|lllt|laser\s+cap|"
    r"alopecia|effluvium|dandruff|seborrh\w*|itch\w*|flak\w*|"
    r"ferritin|vitamin\s?d|thyroid|tsh|iron|lab|labs|bloodwork|"
    r"routine|treatment|dose|adherence|streak|check-?in|photo|progress|density|"
    r"derm\w*|clinician|doctor|tricholog\w*)\b",
    re.IGNORECASE,
)

#: The user talking about themselves or their record. This is what carries "how am I doing?",
#: "is it working?", "what should I do next" — questions with no domain noun at all.
SELF_REFERENCE = re.compile(
    r"\b(?:how\s+am\s+i|how'?s?\s+it\s+going|am\s+i\s+\w+ing|my\s+(?:progress|record|data|numbers|"
    r"results|history|entries|log|plan|routine)|is\s+it\s+working|what\s+should\s+i|"
    r"should\s+i\s+\w+|what\s+do\s+you\s+(?:think|see)|any(?:thing)?\s+(?:i\s+should|to\s+watch)|"
    r"summar\w+\s+my|explain\s+(?:this|my|the)\s+(?:chart|graph|trend|number))\b",
    re.IGNORECASE,
)

#: Clear signals of another domain. Kept to things a hair app is never legitimately asked, so a
#: false positive here is genuinely unlikely.
OFF_DOMAIN = re.compile(
    r"\b(?:write|debug|refactor|compile)\s+(?:me\s+)?(?:some\s+)?(?:a\s+)?(?:code|script|program|"
    r"function|sql|python|javascript|regex)\b"
    r"|\b(?:python|javascript|typescript|java|c\+\+|sql|html|css|react)\s+(?:code|script|function)\b"
    r"|\btranslate\s+(?:this|that|the|into|to)\b"
    r"|\b(?:weather|forecast|temperature)\s+(?:in|for|today|tomorrow)\b"
    r"|\b(?:stock|share)\s+price\b|\bcrypto|bitcoin|ethereum\b"
    r"|\bwrite\s+(?:me\s+)?(?:a\s+)?(?:poem|song|story|essay|email|letter|cover\s+letter)\b"
    r"|\brecipe\s+for\b|\bhow\s+do\s+i\s+cook\b"
    r"|\b(?:who|when)\s+(?:won|was)\s+the\s+\w+\s+(?:election|war|cup|final)\b"
    r"|\bcapital\s+of\s+[A-Z]\w+\b"
    r"|\bsolve\s+(?:this\s+)?(?:equation|integral|for\s+x)\b"
    r"|\bhomework\b|\bmy\s+(?:tax|taxes|mortgage|resume|cv)\b",
    re.IGNORECASE,
)

SCOPE_POLICY = ScopePolicy(
    domain=DOMAIN_TERMS,
    self_reference=SELF_REFERENCE,
    off_domain=OFF_DOMAIN,
    refusal=(
        "I only cover hair and scalp health, and your own tracking record. "
        "Ask me about your entries, treatments, labs or routine and I'll dig in."
    ),
)

#: The AGENT prompt. Distinct from `SYSTEM_PROMPT` below, and the distinction is not cosmetic.
#:
#: `SYSTEM_PROMPT` serves the one-shot path, where the facts arrive in the message. Reusing it for
#: the agent produced a model that politely asked the *user* to supply their own lab results —
#: because nothing told it the data was a tool call away. It never dispatched a single tool.
#:
#: So this one opens by saying the record is fetchable and that fetching is the first move.
AGENT_SYSTEM_PROMPT = """\
You are a careful hair-health companion inside a documentation app — NOT a diagnostic tool.

The person's own record lives on their device and you can read it with the tools provided.
ALWAYS gather what you need with tools before answering. Never ask the user to type in data you
could fetch — if you want their entries, their labs or their treatments, call the tool.
Call every tool you need in one go; independent reads run in parallel.

Hard rules:
- Never invent a number. Every figure you state must come from a tool result.
- Never diagnose, and never name a condition the person did not state themselves.
- Only discuss whether a treatment is "working" when its own record shows it is past 24 weeks.
- Say plainly when the record does not answer the question.
- Frame everything as record-keeping and honest uncertainty.

Answer in short paragraphs. Lead with what changed, then what is worth attention, then what to
raise with a clinician if anything.
"""

SYSTEM_PROMPT = """\
You are a careful hair-health companion inside a documentation app — NOT a diagnostic tool.

You will receive already-computed facts about one person. Explain and prioritise them.

Hard rules:
- Never invent a number or a fact beyond the ones given.
- Never diagnose, and never name a condition the person did not state themselves.
- Only discuss whether a treatment is "working" when the facts say it is past its judging point.
- Frame everything as record-keeping and honest uncertainty.

Return each statement as a separate claim, tagged with its category:
  observation  a plain restatement of a recorded fact
  trend        a direction over time
  education    general hair science, not about this person specifically
  efficacy     whether a treatment appears to be working
  diagnosis    naming or implying a medical condition
  escalation   suggesting the person raise something with a clinician

Tag honestly. A claim you tag wrongly is a claim the safety layer cannot judge. Set `uncertain`
when you are not confident; a hedged claim is dropped rather than shown, which is the right outcome.
"""


def gates_for(facts: dict[str, Any]) -> frozenset[str]:
    """Derive this envelope's gates from the app's facts.

    Reads defensively: the facts come from a client, so a missing key, a wrong type, or a hostile
    value must produce *fewer* gates, never more. Every failure path here closes a gate.
    """
    gates: set[str] = set()

    entry_count = facts.get("entry_count")
    if isinstance(entry_count, int) and entry_count >= 3:
        gates.add(GATE_HAS_HISTORY)

    treatments = facts.get("treatments")
    if isinstance(treatments, list):
        for treatment in treatments:
            if not isinstance(treatment, dict):
                continue
            weeks = treatment.get("weeks_elapsed")
            if isinstance(weeks, int) and weeks >= OUTCOME_WINDOW_WEEKS:
                gates.add(GATE_EFFICACY)
                break

    return frozenset(gates)
