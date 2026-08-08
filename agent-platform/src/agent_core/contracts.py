"""The wire contract. Pure and serializable — no I/O, no framework, no app knowledge.

This module is the single source of truth for what crosses between a client and the server. The
Swift (later Dart) SDK conforms to the JSON schema generated from these models, and one
cross-language conformance suite checks both sides against it (ARCHITECTURE.md §11).

Two rules govern everything here, and both come out of the adversarial review (§5):

1. **Authority is never carried in a request.** `app_id`, `principal_id`, `installation_id` and
   entitlement are derived server-side from the authenticated session. A client cannot name who it
   is, which app it belongs to, or what it has paid for. That is why `Principal` has no inbound
   request model — it is constructed by the server and only ever appears on the way out.
2. **Everything a client sends is untrusted content.** Not "untrusted unless the tool says
   otherwise" — untrusted, full stop, because a patched binary can put anything in any field. So no
   safety, entitlement, completion or budget decision may read a client-supplied value except as an
   explicitly advisory hint (`ClientHints`).

Plain-language version: the phone can describe itself and hand over data, but it can never *claim*
permission. The server decides, every time, from facts it computed itself.
"""

from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

#: Bumped on any breaking change to the models below. Pinned on every run; the server rejects an
#: incompatible client before doing any work rather than failing halfway through a paid turn.
PROTOCOL_VERSION = 1

#: Hard ceiling on a context envelope, enforced before parsing rather than after. An oversized
#: payload is an abuse vector (§9) and a cost vector — a client can otherwise inflate a prompt.
MAX_ENVELOPE_BYTES = 64 * 1024

_Slug = Annotated[str, StringConstraints(pattern=r"^[a-z0-9][a-z0-9._-]{0,63}$")]


class Base(BaseModel):
    """Reject unknown fields everywhere. A client sending a field we do not know about is either a
    version mismatch or an attempt to smuggle state past validation; both should fail loudly."""

    model_config = ConfigDict(extra="forbid", frozen=True)


# --------------------------------------------------------------------------------------------
# Identity — server-constructed, outbound only
# --------------------------------------------------------------------------------------------


class Entitlement(StrEnum):
    FREE = "free"
    PRO = "pro"


class Principal(Base):
    """Who the server believes it is acting for. Every field is derived from the authenticated
    session, never from request JSON (§6).

    The IDs are deliberately separate rather than one `user_id`: `installation_id` changes on
    reinstall, `principal_id` is what survives a subscription restore, and `data_subject_id` is
    whose personal data is being processed. Collapsing them now makes account-linking and deletion
    unimplementable later.
    """

    app_id: _Slug
    tenant_id: _Slug | None = None
    principal_id: str
    installation_id: str
    data_subject_id: str
    #: Coarse free-vs-paid, for the tool registry's `min_entitlement` gate.
    entitlement: Entitlement
    #: The plan actually held — "taster", "trial", "pro_monthly", "pro_yearly", "free".
    #:
    #: `entitlement` cannot answer this: it is a two-case enum, so everything paid collapses to
    #: "pro" and every per-plan limit looked up by it resolved to the FREE plan (unknown ids
    #: degrade to base). That silently truncated every response to 512 output tokens regardless of
    #: what someone paid for. The enum stays for the coarse tool gate; the plan id is what money
    #: and limits are measured against.
    plan_id: str = ""


# --------------------------------------------------------------------------------------------
# Client-supplied input — untrusted by construction
# --------------------------------------------------------------------------------------------


class ClientHints(Base):
    """Advisory only. The server may use these to *narrow* what it offers or to skip work it would
    otherwise do — never to widen capability, unlock a paid path, or lower a safety tier (§7).

    `available_capabilities` is subtractive: the effective set is the server's allowlist intersected
    with entitlements intersected with this. A client claiming a capability it does not have gains
    nothing; a client omitting one it does have simply loses it.
    """

    platform: Literal["ios", "android", "test"]
    os_version: str = ""
    app_build: str = ""
    available_capabilities: frozenset[str] = frozenset()


class Consent(Base):
    """What the user agreed to, for this envelope. Recorded with the purpose and the exact policy
    version, because consent to an older policy is not consent to a new one (§10).

    `crosses_border` is explicit rather than inferred: Oman's PDPL requires explicit consent before
    personal data leaves the country, and the model provider is outside Oman.
    """

    purpose: _Slug
    policy_version: str
    granted_at: datetime
    crosses_border: bool


class ContextEnvelope(Base):
    """One versioned snapshot of app-computed facts — the entire input the model gets about a user.

    `schema_version` belongs to the *app*, not the platform: Hair Compass's `AIContext` evolves on
    its own schedule, and the server must be able to reject a snapshot its prompt pack was not
    written against instead of silently prompting on fields that moved.

    `facts` is opaque to the platform on purpose. The platform never interprets it, never branches
    on its contents, and never promotes any app's shape to a universal subject API (§4).
    """

    kind: _Slug
    schema_version: int
    generated_at: datetime
    facts: dict[str, Any]


class AnalysisRequest(Base):
    """A G1 turn: one envelope in, one structured analysis out. No tools, no loop, no approvals.

    `idempotency_key` is client-generated and is the *only* client value with authority-like effect
    — and only in the safe direction: replaying it returns the first result rather than spending
    money twice. A mobile client retrying after a dropped connection is normal, not exceptional.
    """

    protocol_version: int = PROTOCOL_VERSION
    idempotency_key: str = Field(min_length=8, max_length=128)
    pack: _Slug
    envelope: ContextEnvelope
    consent: Consent
    hints: ClientHints
    user_text: str = Field(default="", max_length=4000)


# --------------------------------------------------------------------------------------------
# Server output
# --------------------------------------------------------------------------------------------


class ClaimCategory(StrEnum):
    """What kind of statement the model made. The safety layer decides per category rather than
    trying to judge free text as a whole (§9) — "this treatment is working" is only permissible
    once a treatment is past its judging window, whereas a diagnosis is never permissible.
    """

    OBSERVATION = "observation"
    TREND = "trend"
    EDUCATION = "education"
    EFFICACY = "efficacy"
    DIAGNOSIS = "diagnosis"
    ESCALATION = "escalation"


class Claim(Base):
    text: str
    category: ClaimCategory
    evidence: tuple[str, ...] = ()
    uncertain: bool = False


class SafetyDecision(StrEnum):
    ALLOW = "allow"
    REDACT = "redact"
    FALLBACK = "fallback"


class SafetyVerdict(Base):
    """Why the response is being served, redacted, or thrown away.

    `FALLBACK` is not an error path: it means the app should render its own deterministic result
    instead. Failing to the deterministic path is always safe here, because that path exists and is
    already good — which is exactly why an uncertain safety result must choose it rather than
    guessing (core-safety M1: fail visibly, never silently degrade).
    """

    decision: SafetyDecision
    verifier_version: str
    reasons: tuple[str, ...] = ()


class Usage(Base):
    """What the turn actually cost. Recorded per turn against the principal's ledger, and reconciled
    against the pre-call reservation — a pre-call estimate alone is raceable across concurrent turns
    (§6)."""

    input_tokens: int = 0
    output_tokens: int = 0
    cached_input_tokens: int = 0
    provider: str = ""
    model: str = ""
    price_version: str = ""


class AnalysisResponse(Base):
    protocol_version: int = PROTOCOL_VERSION
    turn_id: str
    pack_version: str
    claims: tuple[Claim, ...]
    safety: SafetyVerdict
    usage: Usage
    served_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class ErrorCode(StrEnum):
    PROTOCOL_UNSUPPORTED = "protocol_unsupported"
    SCHEMA_UNSUPPORTED = "schema_unsupported"
    ENVELOPE_TOO_LARGE = "envelope_too_large"
    #: The caller presented no session token, or one that is missing, expired, forged or stale.
    #: Distinct from NOT_ENTITLED, which means "we know who you are and you have not paid".
    UNAUTHENTICATED = "unauthenticated"
    NOT_ENTITLED = "not_entitled"
    QUOTA_EXHAUSTED = "quota_exhausted"
    CONSENT_REQUIRED = "consent_required"
    PROVIDER_UNAVAILABLE = "provider_unavailable"
    INTERNAL = "internal"


class ErrorEnvelope(Base):
    """The only error shape a client ever sees. Full detail is logged server-side against the
    correlation id; the client gets a code, a safe message, and the id to quote in support
    (SAF7) — never a traceback, a provider message, or a SQL error."""

    error_code: ErrorCode
    message: str
    correlation_id: str
