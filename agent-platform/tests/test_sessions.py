"""Session tokens — the thing that was missing entirely.

Identity was derived from `installation_id`, a value the client sends and picks, and nothing else
authenticated anything. Anyone who learned another user's installation id could read their consent
record and audit trail, or erase their account. A store receipt could not help: it selects a *plan*,
never a person.

Every test here is written as the attack.
"""

from __future__ import annotations

import time

import pytest

from agent_core.contracts import Entitlement, Principal
from agent_server.sessions import InvalidSession, SessionTokens

SECRET = "s" * 40


def _principal(pid: str = "p_alice", **kw) -> Principal:
    return Principal(
        **{
            "app_id": "hair-compass",
            "principal_id": pid,
            "installation_id": f"dev-{pid}",
            "data_subject_id": f"d-{pid}",
            "entitlement": Entitlement.PRO,
            **kw,
        }
    )


def test_a_token_round_trips_to_the_same_principal() -> None:
    tokens = SessionTokens(SECRET)
    restored = tokens.verify(tokens.issue(_principal()))
    assert restored.principal_id == "p_alice"
    assert restored.entitlement is Entitlement.PRO


def test_a_token_signed_with_another_secret_is_refused() -> None:
    """The whole security property. Without it the token is a suggestion."""
    forged = SessionTokens("x" * 40).issue(_principal("p_bob"))
    with pytest.raises(InvalidSession):
        SessionTokens(SECRET).verify(forged)


def test_editing_the_payload_invalidates_the_token() -> None:
    """The attack that matters: take your own token, change the principal to someone else's."""
    import base64
    import json

    tokens = SessionTokens(SECRET)
    body, _, signature = tokens.issue(_principal("p_alice")).rpartition(".")
    payload = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    payload["p"] = "p_victim"
    tampered = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")

    with pytest.raises(InvalidSession):
        tokens.verify(f"{tampered}.{signature}")


def test_escalating_the_entitlement_inside_the_token_is_refused() -> None:
    """A signed token is only as good as what it protects. The plan travels inside it."""
    import base64
    import json

    tokens = SessionTokens(SECRET)
    body, _, signature = tokens.issue(_principal(entitlement=Entitlement.FREE)).rpartition(".")
    payload = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    payload["e"] = "pro"
    tampered = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")

    with pytest.raises(InvalidSession):
        tokens.verify(f"{tampered}.{signature}")


def test_an_expired_token_is_refused() -> None:
    tokens = SessionTokens(SECRET, ttl_seconds=-1)
    with pytest.raises(InvalidSession):
        tokens.verify(tokens.issue(_principal()))


def test_a_token_that_has_not_expired_is_accepted() -> None:
    tokens = SessionTokens(SECRET, ttl_seconds=60)
    assert tokens.verify(tokens.issue(_principal())).principal_id == "p_alice"
    assert time.time() > 0  # sanity: the clock is real, not mocked away


@pytest.mark.parametrize("junk", ["", "   ", "no-dot", "a.b", ".", "..", "x" * 5000])
def test_junk_is_refused_rather_than_crashing(junk) -> None:
    """An unauthenticated endpoint takes whatever the internet sends it."""
    with pytest.raises(InvalidSession):
        SessionTokens(SECRET).verify(junk)


def test_a_weak_secret_is_refused_at_construction() -> None:
    """The same key derives principal ids. A guessable one lets a client both compute anyone's
    principal id and mint a token for it."""
    with pytest.raises(RuntimeError, match="32 characters"):
        SessionTokens("short")


def test_the_error_never_says_why() -> None:
    """A caller who can tell 'expired' from 'bad signature' has a probing oracle."""
    tokens = SessionTokens(SECRET)
    messages = set()
    for bad in ["not-a-token", SessionTokens("y" * 40).issue(_principal())]:
        try:
            tokens.verify(bad)
        except InvalidSession as exc:
            messages.add(exc.message)
    assert len(messages) == 1


@pytest.mark.parametrize("junk", ["é.x", "\x80\x81.zz", "café.signature", "ünïcode.x"])
def test_a_non_ascii_token_is_refused_rather_than_crashing(junk) -> None:
    """`hmac.compare_digest` raises TypeError on str inputs containing non-ASCII, so a token with
    one stray high byte was an unhandled 500 — a crash any anonymous caller could trigger, and a
    signal separating "malformed" from "wrong" that this class exists to withhold."""
    with pytest.raises(InvalidSession):
        SessionTokens(SECRET).verify(junk)
