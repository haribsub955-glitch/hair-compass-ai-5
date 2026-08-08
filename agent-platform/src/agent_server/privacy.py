"""Consent, access and erasure — the endpoints that make the data-protection story real.

`IdentityStore` has had `grant`, `withdraw`, `has_consent` and `forget` since the schema landed and
none of them was reachable over HTTP. That is the same defect as an audit table nobody writes to:
the capability exists, the review sees it, and the user has no way to use it.

**Three obligations, and why each is its own endpoint.**

*Consent must be withdrawable.* Consent that cannot be taken back is not consent — under both
Oman's PDPL and the GDPR it has to be as easy to withdraw as to give. So withdrawal is a first-class
operation, not a support ticket.

*"Stop collecting" and "erase what you have" are different requests.* Someone may want the sync to
stop while keeping what is already there, or want everything gone. Collapsing them into one button
forces a choice nobody asked for, so `withdraw` and `forget` stay separate.

*Access is what makes the other two checkable.* A user who cannot see what was recorded cannot tell
whether a withdrawal worked. `GET /v1/privacy` returns the live grants and the recent audit trail —
metadata, which is all the server keeps.

**Consent is checked server-side, or it is not checked.** `AnalysisRequest` carries a
client-supplied `Consent` block and the cross-border gate trusted its boolean, so a modified client
asserted consent by sending `true`. The stored grant is the authority now; the envelope's copy is
what the client
*believes*, and a disagreement is worth recording.
"""

from __future__ import annotations

import logging
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from agent_core.consent import PurposeRegistry
from agent_core.contracts import Principal
from agent_server.audit import AuditEventName, AuditLog
from agent_server.core.errors import ConsentRequired
from agent_server.db.identity import IdentityStore

log = logging.getLogger("agent_server.privacy")


class ConsentDecision(BaseModel):
    """One purpose, granted or withdrawn."""

    model_config = ConfigDict(extra="forbid")

    purpose: str
    granted: bool
    #: Which version of the policy text the user was shown. Consent to an older policy is not
    #: consent to a new one, so this is recorded rather than assumed.
    policy_version: str = Field(min_length=1, max_length=32)
    #: Whether the user agreed to their data leaving the country. PDPL treats the transfer as a
    #: separately consentable act, so it is its own answer and not a consequence of the purpose.
    crosses_border: bool = False


class PrivacyState(BaseModel):
    """What the server holds, as the user's privacy screen shows it."""

    model_config = ConfigDict(extra="forbid")

    purposes: list[dict[str, Any]]
    recent_events: list[dict[str, Any]]


class PrivacyService:
    """Consent and erasure, over the same `IdentityStore` the rest of the server uses.

    A service rather than logic in the route handlers because these three operations are the ones
    most likely to be needed from somewhere else — a support tool, a scheduled retention job, an
    App Store deletion webhook — and the rule they enforce must not be duplicated.
    """

    def __init__(
        self,
        identity: IdentityStore,
        *,
        purposes: PurposeRegistry,
        audit: AuditLog,
    ) -> None:
        self._identity = identity
        self._purposes = purposes
        self._audit = audit

    async def apply(self, principal: Principal, decision: ConsentDecision) -> None:
        """Record a grant or a withdrawal.

        An unknown purpose is refused rather than stored. A consent record naming a purpose the
        server has no definition for cannot be honoured, cannot be explained to the user, and
        cannot be audited — it is a row that only looks like compliance.
        """
        purpose = self._purposes.get(decision.purpose)
        if purpose is None:
            raise ConsentRequired(f"unknown purpose {decision.purpose!r}")

        if decision.granted:
            await self._identity.grant(
                principal.principal_id,
                purpose=decision.purpose,
                policy_version=decision.policy_version,
                crosses_border=decision.crosses_border,
            )
        else:
            await self._identity.withdraw(principal.principal_id, purpose=decision.purpose)

        self._audit.record(
            AuditEventName.CONSENT_GRANTED
            if decision.granted
            else AuditEventName.CONSENT_WITHDRAWN,
            principal_id=principal.principal_id,
            device_id=principal.installation_id,
            detail={
                "purpose": decision.purpose,
                "policy_version": decision.policy_version,
                "crosses_border": decision.crosses_border,
                "necessary": purpose.necessary,
            },
        )

    async def state(self, principal: Principal) -> PrivacyState:
        """Everything the user is entitled to see: their live grants and the recent audit trail."""
        purposes: list[dict[str, Any]] = []
        for purpose in self._purposes:
            purposes.append(
                {
                    "id": purpose.id,
                    "description": purpose.description,
                    "necessary": purpose.necessary,
                    "crosses_border": purpose.crosses_border,
                    "granted": await self._identity.has_consent(
                        principal.principal_id, purpose=purpose.id
                    ),
                }
            )
        events: list[dict[str, Any]] = []
        recent = getattr(self._audit, "recent", None)
        if recent is not None:
            events = await recent(principal.principal_id, limit=50)
        return PrivacyState(purposes=purposes, recent_events=events)

    async def forget(self, principal: Principal) -> dict[str, int]:
        """Erase everything. Audited BEFORE the delete, not after.

        The audit row names a principal that is about to stop existing, so writing it afterwards
        risks losing the only evidence the deletion happened — the audit queue is asynchronous and
        a process that dies in between would take the record with it. Audit events survive the
        erasure deliberately: they hold ids, decisions and costs, never payloads, and deleting the
        record that a deletion occurred defeats the purpose of having a trail.
        """
        self._audit.record(
            AuditEventName.DATA_DELETED,
            principal_id=principal.principal_id,
            device_id=principal.installation_id,
            detail={"requested": True},
        )
        removed = await self._identity.forget(principal.principal_id)
        log.info("erased principal %s: %s", principal.principal_id, removed)
        return removed


async def require_consent(
    identity: IdentityStore | None,
    principal: Principal,
    *,
    purpose: str,
    crosses_border: bool,
    claimed: bool | None = None,
    audit: AuditLog | None = None,
) -> None:
    """The runtime gate. Raises `ConsentRequired` unless a live grant covers these exact terms.

    **This replaces trusting the client.** The cross-border check read
    `request.consent.crosses_border` — a field the client fills in — so a modified build asserted
    consent by sending `true`, and the corrected database query added in the previous pass was
    never consulted at runtime.

    `claimed` is the client's own copy, passed only so a disagreement can be recorded. It never
    decides anything. A client claiming consent the server has no record of is either a stale app
    or a tampered one, and both are worth seeing in the audit log before they become a complaint.

    With no identity store there is nothing to check against, so this FAILS CLOSED. Degrading to
    "allow" would mean a dev box exposed through a tunnel — which is exactly the plan for remote
    testing — silently has no consent gate at all, and PDPL is unambiguous that an unverified
    transfer is an unconsented one. A server that cannot verify consent must not transfer.
    """
    if identity is None:
        raise ConsentRequired("consent cannot be verified without a durable store")

    granted = await identity.has_consent(
        principal.principal_id, purpose=purpose, crosses_border=crosses_border or None
    )
    if granted:
        return

    if claimed and audit is not None:
        # The interesting case: the app believes it has consent and the server does not.
        audit.record(
            AuditEventName.CONSENT_WITHDRAWN,
            principal_id=principal.principal_id,
            device_id=principal.installation_id,
            detail={"purpose": purpose, "client_claimed": True, "server_has": False},
        )
    raise ConsentRequired(f"no live grant for {purpose!r}")
