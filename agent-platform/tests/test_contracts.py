"""Contract invariants. These are merge gates, not documentation (ARCHITECTURE.md §9).

Every test here asserts something a *patched client* must not be able to do. They are written as
"prove this is blocked", never "prove this works" — a review that only checks the happy path would
pass on a contract that hands authority to the caller.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from agent_core.contracts import (
    PROTOCOL_VERSION,
    AnalysisRequest,
    ClientHints,
    Consent,
    ContextEnvelope,
    Entitlement,
    Principal,
)


def _envelope() -> ContextEnvelope:
    return ContextEnvelope(
        kind="hair-context",
        schema_version=1,
        generated_at=datetime.now(UTC),
        facts={"entry_count": 12},
    )


def _consent() -> Consent:
    return Consent(
        purpose="deep-analysis",
        policy_version="2026-07-29",
        granted_at=datetime.now(UTC),
        crosses_border=True,
    )


def _hints() -> ClientHints:
    return ClientHints(platform="test")


def _request(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "idempotency_key": "abcd1234efgh",
        "pack": "hair-compass",
        "envelope": _envelope(),
        "consent": _consent(),
        "hints": _hints(),
    }
    return base | overrides


def test_request_cannot_carry_a_principal() -> None:
    """The headline invariant: a client cannot name who it is.

    If `AnalysisRequest` ever grows a principal-shaped field, every downstream authorization
    becomes advisory — the server would be authorizing whoever the caller claimed to be.
    """
    with pytest.raises(ValidationError):
        AnalysisRequest(**_request(principal_id="someone-else"))  # type: ignore[arg-type]


def test_request_cannot_carry_an_entitlement() -> None:
    """Paid access is read from StoreKit/Play server records, never from the request body (§7)."""
    with pytest.raises(ValidationError):
        AnalysisRequest(**_request(entitlement="pro"))  # type: ignore[arg-type]


def test_unknown_fields_are_rejected_not_ignored() -> None:
    """`extra="forbid"` is the mechanism behind both tests above; assert it directly so a future
    config change that flips it to "ignore" fails here rather than silently reopening the hole."""
    with pytest.raises(ValidationError):
        AnalysisRequest(**_request(tenant_id="other-tenant"))  # type: ignore[arg-type]


def test_client_hints_capabilities_are_a_plain_set_with_no_authority_fields() -> None:
    """Hints may describe availability. They may not carry a tier, a quota, or an entitlement —
    those would be exactly the "client claims permission" shape §7 forbids."""
    hints = ClientHints(platform="ios", available_capabilities=frozenset({"ocr"}))
    assert "ocr" in hints.available_capabilities
    for forbidden in ("entitlement", "quota", "tier", "budget"):
        assert forbidden not in ClientHints.model_fields


def test_principal_is_frozen_so_authority_cannot_be_mutated_after_construction() -> None:
    """The server builds a `Principal` once, from the authenticated session. Anything downstream
    that could reassign a field could quietly re-target an action at another subject."""
    principal = Principal(
        app_id="hair-compass",
        principal_id="p_1",
        installation_id="i_1",
        data_subject_id="d_1",
        entitlement=Entitlement.PRO,
    )
    with pytest.raises(ValidationError):
        principal.entitlement = Entitlement.FREE  # type: ignore[misc]


def test_user_text_is_bounded() -> None:
    """Unbounded free text is a cost vector and an injection surface (§9)."""
    with pytest.raises(ValidationError):
        AnalysisRequest(**_request(user_text="x" * 4001))


def test_protocol_version_defaults_but_is_explicit_on_the_wire() -> None:
    request = AnalysisRequest(**_request())
    assert request.protocol_version == PROTOCOL_VERSION
    assert "protocol_version" in request.model_dump()
