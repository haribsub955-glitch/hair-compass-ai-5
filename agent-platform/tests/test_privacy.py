"""Consent, access and erasure.

The store had `grant`, `withdraw`, `has_consent` and `forget` from the day the schema landed and
none of them was reachable over HTTP — the same shape of defect as an audit table nobody writes to.
These tests are about whether a user can actually exercise the rights the architecture claims.
"""

from __future__ import annotations

import pytest

from agent_core.consent import DEFAULT_PURPOSES
from agent_core.contracts import Entitlement, Principal
from agent_server.audit import AuditEventName, NullAuditLog
from agent_server.core.errors import ConsentRequired
from agent_server.privacy import ConsentDecision, PrivacyService, require_consent

P = Principal(
    app_id="hair-compass",
    principal_id="p_privacy",
    installation_id="dev_privacy",
    data_subject_id="d_privacy",
    entitlement=Entitlement.PRO,
)


class FakeIdentity:
    """Records grants the way the real store does — append-only, terms included."""

    def __init__(self) -> None:
        self.grants: list[tuple[str, str, bool]] = []
        self.withdrawn: set[str] = set()
        self.forgotten: list[str] = []
        self.bindings: dict[str, object] = {}

    async def grant(self, principal_id, *, purpose, policy_version, crosses_border) -> None:
        self.withdrawn.discard(purpose)
        self.grants.append((purpose, policy_version, crosses_border))

    async def withdraw(self, principal_id, *, purpose) -> int:
        self.withdrawn.add(purpose)
        return 1

    async def has_consent(
        self, principal_id, *, purpose, policy_version=None, crosses_border=None
    ) -> bool:
        if purpose in self.withdrawn:
            return False
        return any(
            g[0] == purpose and (crosses_border is None or g[2] == crosses_border)
            for g in self.grants
        )

    # --- device binding, so the HTTP tests can drive /v1/session ---------------------------

    async def bound_device(self, installation_id):
        return self.bindings.get(installation_id)

    async def bind_device(self, installation_id, *, public_key: bytes, attested: bool = False):
        from agent_server.devicebind import BoundDevice

        if installation_id in self.bindings:
            return False
        self.bindings[installation_id] = BoundDevice(
            installation_id=installation_id,
            public_key_der=public_key,
            attested=attested,
            counter=0,
        )
        return True

    async def record_proof(self, installation_id, *, counter=None) -> None: ...

    async def forget(self, principal_id) -> dict[str, int]:
        self.forgotten.append(principal_id)
        return {"consent_records": 2, "devices": 1, "principals": 1}


def _service(identity: FakeIdentity, audit: NullAuditLog) -> PrivacyService:
    return PrivacyService(identity, purposes=DEFAULT_PURPOSES, audit=audit)


def _decision(**kw) -> ConsentDecision:
    return ConsentDecision(
        **{"purpose": "agent-analysis", "granted": True, "policy_version": "1.0", **kw}
    )


# --------------------------------------------------------------------------------------------
# Consent
# --------------------------------------------------------------------------------------------


async def test_consent_can_be_withdrawn_as_easily_as_it_is_given() -> None:
    """Consent that is harder to take back than to give is not freely given — one endpoint, both
    directions, so the withdrawal path cannot ship a release later than the grant path."""
    identity, audit = FakeIdentity(), NullAuditLog()
    service = _service(identity, audit)

    await service.apply(P, _decision(granted=True))
    assert await identity.has_consent(P.principal_id, purpose="agent-analysis")

    await service.apply(P, _decision(granted=False))
    assert not await identity.has_consent(P.principal_id, purpose="agent-analysis")

    events = [name for name, _ in audit.events]
    assert AuditEventName.CONSENT_GRANTED in events
    assert AuditEventName.CONSENT_WITHDRAWN in events


async def test_a_purpose_the_server_cannot_explain_is_refused_rather_than_stored() -> None:
    """A consent row naming an unknown purpose cannot be honoured, explained or audited. It is a
    row that only looks like compliance."""
    service = _service(FakeIdentity(), NullAuditLog())
    with pytest.raises(ConsentRequired):
        await service.apply(P, _decision(purpose="sell-to-advertisers"))


async def test_the_recorded_terms_include_the_policy_version_and_the_transfer() -> None:
    """Consent to an older policy is not consent to a new one, and PDPL treats the cross-border
    transfer as a separately consentable act — so neither can be inferred later."""
    identity = FakeIdentity()
    await _service(identity, NullAuditLog()).apply(
        P, _decision(policy_version="2.1", crosses_border=True)
    )
    assert identity.grants == [("agent-analysis", "2.1", True)]


async def test_the_state_view_lists_every_purpose_including_the_ungranted_ones() -> None:
    """A screen that shows only what was agreed cannot be used to check that a withdrawal worked."""
    identity = FakeIdentity()
    await _service(identity, NullAuditLog()).apply(P, _decision())
    state = await _service(identity, NullAuditLog()).state(P)

    by_id = {p["id"]: p for p in state.purposes}
    assert by_id["agent-analysis"]["granted"] is True
    assert by_id["model-improvement"]["granted"] is False
    # Every purpose carries the text the user was shown, or they cannot make an informed decision.
    assert all(p["description"] for p in state.purposes)


# --------------------------------------------------------------------------------------------
# The runtime gate — the client no longer decides
# --------------------------------------------------------------------------------------------


async def test_a_client_claiming_consent_the_server_never_recorded_is_refused() -> None:
    """The defect this closes: the cross-border check read a boolean the client filled in, so a
    modified build asserted consent by sending `true`."""
    identity, audit = FakeIdentity(), NullAuditLog()
    with pytest.raises(ConsentRequired):
        await require_consent(
            identity,
            P,
            purpose="agent-analysis",
            crosses_border=True,
            claimed=True,
            audit=audit,
        )


async def test_the_disagreement_between_client_and_server_is_audited() -> None:
    """An app that believes it has consent the server has no record of is either stale or tampered
    with, and both are worth seeing before they arrive as a complaint."""
    identity, audit = FakeIdentity(), NullAuditLog()
    with pytest.raises(ConsentRequired):
        await require_consent(
            identity, P, purpose="agent-analysis", crosses_border=True, claimed=True, audit=audit
        )
    recorded = dict(audit.events)[AuditEventName.CONSENT_WITHDRAWN]
    assert recorded["client_claimed"] is True
    assert recorded["server_has"] is False


async def test_a_local_only_grant_does_not_authorise_a_transfer() -> None:
    """The terms are part of the check, not just the purpose."""
    identity = FakeIdentity()
    await identity.grant(
        P.principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=False
    )
    with pytest.raises(ConsentRequired):
        await require_consent(identity, P, purpose="agent-analysis", crosses_border=True)

    await identity.grant(
        P.principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=True
    )
    await require_consent(identity, P, purpose="agent-analysis", crosses_border=True)


async def test_no_store_fails_closed() -> None:
    """A dev box reachable through a tunnel must not silently have no gate at all. PDPL is
    unambiguous that an unverified transfer is an unconsented one."""
    with pytest.raises(ConsentRequired):
        await require_consent(None, P, purpose="agent-analysis", crosses_border=True)


# --------------------------------------------------------------------------------------------
# Erasure
# --------------------------------------------------------------------------------------------


async def test_erasure_is_audited_before_the_rows_disappear() -> None:
    """The audit row names a principal that is about to stop existing. Written afterwards, a
    process that dies in between takes the only evidence of the deletion with it."""
    identity, audit = FakeIdentity(), NullAuditLog()

    order: list[str] = []
    original_record = audit.record

    def _record(event, **kw):
        order.append(f"audit:{event}")
        original_record(event, **kw)

    audit.record = _record  # type: ignore[method-assign]
    original_forget = identity.forget

    async def _forget(principal_id):
        order.append("forget")
        return await original_forget(principal_id)

    identity.forget = _forget  # type: ignore[method-assign]

    await _service(identity, audit).forget(P)
    assert order == [f"audit:{AuditEventName.DATA_DELETED}", "forget"]


async def test_erasure_reports_what_it_removed() -> None:
    """A deletion that reports nothing cannot be shown to the user or to a regulator."""
    identity = FakeIdentity()
    removed = await _service(identity, NullAuditLog()).forget(P)
    assert removed["principals"] == 1
    assert identity.forgotten == [P.principal_id]


# --------------------------------------------------------------------------------------------
# Photos are their own consent, not a corner of agent-analysis.
# --------------------------------------------------------------------------------------------


def test_sending_a_photo_is_a_separate_purpose_from_sending_numbers() -> None:
    """A photograph of someone's scalp is health data and biometric-adjacent. Stretching
    `agent-analysis` to cover it would mean one tap consented to two materially different acts."""
    photo = DEFAULT_PURPOSES.get("photo-analysis")
    assert photo is not None
    assert photo.crosses_border
    # Optional: the product works fully without ever sending a photo.
    assert not photo.necessary
    assert photo.description


async def test_a_turn_with_attachments_needs_the_photo_grant_too() -> None:
    """Checked at TURN time, not only at upload — the two are separate moments and consent can be
    withdrawn in between. A photo agreed to an hour ago is not a photo agreed to now."""
    from agent_core.plans import DEFAULT_PLANS
    from agent_server.runs import RunRegistry
    from agent_server.turns import TurnService

    principal = Principal(
        app_id="hair-compass",
        principal_id="p_photo",
        installation_id="dev_photo",
        data_subject_id="d_photo",
        entitlement=Entitlement.PRO,
        plan_id="pro_monthly",
    )
    identity = FakeIdentity()
    # Text analysis is agreed; photos are NOT.
    await identity.grant(
        principal.principal_id,
        purpose="agent-analysis",
        policy_version="1.0",
        crosses_border=True,
    )
    service = TurnService(agent=None, runs=RunRegistry(), identity=identity, plans=DEFAULT_PLANS)

    # A text-only turn is fine.
    await service.authorize(principal)

    # The same turn carrying a photo is not.
    with pytest.raises(ConsentRequired):
        await service.authorize(principal, attachments=1)

    # Once the photo grant exists, it passes.
    await identity.grant(
        principal.principal_id,
        purpose="photo-analysis",
        policy_version="1.0",
        crosses_border=True,
    )
    await service.authorize(principal, attachments=1)
