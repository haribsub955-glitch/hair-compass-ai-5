"""Forced upgrade — the lever that lets one build be switched off without an outage.

`protocol_version` existed from the first contract and nothing acted on it, which is fine until the
day a shipped build has a safety defect and the only available response is taking the whole service
down.
"""

from __future__ import annotations

import pytest

from agent_server.upgrade import UpgradePolicy, UpgradeRequired, UpgradeState, compare_builds


def _policy(**kw) -> UpgradePolicy:
    return UpgradePolicy(**{"protocol_version": 1, **kw})


# --------------------------------------------------------------------------------------------
# Build comparison — a client can send anything at all
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("build", "minimum", "ok"),
    [
        ("1.2.3", "1.2.3", True),
        ("1.2.4", "1.2.3", True),
        ("1.2.2", "1.2.3", False),
        ("2.0", "1.9.9", True),
        # Missing components count as zero, so 1.2 is older than 1.2.1 rather than equal to it.
        ("1.2", "1.2.1", False),
        ("1.2.1", "1.2", True),
        ("42", "41", True),
        ("1.2.3-beta", "1.2.3", True),
        ("10.0.0", "9.99.99", True),
    ],
)
def test_builds_compare_numerically_not_lexically(build, minimum, ok) -> None:
    """`"10" < "9"` as strings, and that is exactly the bug that lets an old client through."""
    assert compare_builds(build, minimum) is ok


@pytest.mark.parametrize("junk", ["", "   ", "not-a-build", "🙂", "v", None])
def test_an_unparseable_build_is_treated_as_ancient_rather_than_crashing(junk) -> None:
    """A build string arrives from a client, so it can be anything. The worst it should do is
    compare as older — which fails toward telling the user to update, not toward a 500."""
    assert compare_builds(junk or "", "1.0.0") is False


# --------------------------------------------------------------------------------------------
# The policy
# --------------------------------------------------------------------------------------------


def test_a_current_build_is_told_nothing() -> None:
    policy = _policy(minimum_build="1.0.0", latest_build="1.4.0")
    assert policy.check(client_protocol=1, app_build="1.4.0") is UpgradeState.CURRENT


def test_a_stale_build_is_nagged_and_still_served() -> None:
    """Cutting someone off mid-question to make a point about a version is its own harm. The app
    gets the state and can prompt at a moment that is not the middle of a task."""
    policy = _policy(minimum_build="1.2.0")
    assert policy.check(client_protocol=1, app_build="1.1.0") is UpgradeState.REQUIRED


def test_an_older_build_that_is_merely_behind_gets_the_soft_signal() -> None:
    policy = _policy(minimum_build="1.0.0", latest_build="1.4.0")
    assert policy.check(client_protocol=1, app_build="1.2.0") is UpgradeState.ENCOURAGED


def test_a_protocol_mismatch_is_refused_because_nothing_useful_can_happen() -> None:
    """Not a matter of taste — the wire format changed and there is nothing to negotiate with."""
    with pytest.raises(UpgradeRequired):
        _policy().check(client_protocol=2, app_build="9.9.9")


def test_a_known_dangerous_build_is_refused_even_on_the_right_protocol() -> None:
    """The reason this exists: a shipped build with a safety defect must be stoppable without
    taking the service down for everyone else."""
    policy = _policy(blocked_below="1.3.0")
    with pytest.raises(UpgradeRequired):
        policy.check(client_protocol=1, app_build="1.2.9")
    assert policy.check(client_protocol=1, app_build="1.3.0") is UpgradeState.CURRENT


def test_blocking_and_nagging_are_separate_levers() -> None:
    """Conflating them means either the nag becomes an outage, or an incompatible client gets a
    banner and a broken experience."""
    policy = _policy(minimum_build="2.0.0", blocked_below="1.0.0")
    assert policy.check(client_protocol=1, app_build="1.5.0") is UpgradeState.REQUIRED
    with pytest.raises(UpgradeRequired):
        policy.check(client_protocol=1, app_build="0.9.0")


def test_an_unconfigured_policy_never_blocks_anyone() -> None:
    """The default has to be inert. A lever that is on by default is an outage waiting for a
    deploy that forgets to set it."""
    policy = _policy()
    assert policy.check(client_protocol=1, app_build="0.0.1") is UpgradeState.CURRENT


def test_the_refusal_carries_a_status_a_client_can_act_on() -> None:
    """426 rather than 400, so the app can tell "update me" apart from "you sent nonsense"."""
    with pytest.raises(UpgradeRequired) as caught:
        _policy(blocked_below="2.0").check(client_protocol=1, app_build="1.0")
    assert caught.value.status == 426
