"""Environment separation — the checks that stop a staging process from being a production one.

Two failures are in scope and they are different. The first is a config that is *fit for dev and
unfit for real users* reaching a live deployment. The second is a correctly-configured staging
process pointed at the **production database**, which is a copied `.env` away and which nothing
else in the system would notice, because every table is shaped identically.
"""

from __future__ import annotations

import pytest

from agent_server.core.config import Settings

LIVE_OK = {
    "database_url": "postgresql+asyncpg://agent:pw@db:5432/agent_platform",
    "secret_key": "k" * 32,
    "apple_bundle_id": "harib.Hair-Compass-AI-5",
    "apple_root_cert_dir": "/certs/apple",
    "llm_provider": "anthropic",
    "llm_model": "claude-sonnet-5",  # anthropic needs a named model; empty boots then fails live
    "require_device_binding": True,
    "access_keys": "partner=" + "k" * 32,
}


def _settings(**kw) -> Settings:
    return Settings(**{**LIVE_OK, **kw})


# --------------------------------------------------------------------------------------------
# Configuration fitness
# --------------------------------------------------------------------------------------------


def test_a_dev_config_is_never_blocked() -> None:
    """Dev has to be able to run with nothing configured, or nobody runs it."""
    assert (
        _settings(
            app_env="dev", apple_bundle_id="", apple_root_cert_dir=""
        ).validate_for_environment()
        == []
    )


def test_a_fully_configured_live_environment_passes() -> None:
    assert _settings(app_env="prod").validate_for_environment() == []
    assert _settings(app_env="staging").validate_for_environment() == []


@pytest.mark.parametrize(
    ("override", "expected"),
    [
        ({"llm_provider": "fake"}, "fake"),
        ({"llm_model": ""}, "LLM_MODEL"),  # anthropic (the default) with no model boots then fails
        ({"apple_bundle_id": ""}, "APPLE_BUNDLE_ID"),
        ({"apple_root_cert_dir": ""}, "APPLE_ROOT_CERT_DIR"),
        ({"secret_key": "short"}, "SECRET_KEY"),
        ({"database_url": "sqlite+aiosqlite:///./local.db"}, "DATABASE_URL"),
        ({"require_device_binding": False}, "REQUIRE_DEVICE_BINDING"),
        ({"access_keys": ""}, "ACCESS_KEYS"),
    ],
)
def test_each_unsafe_setting_is_named_not_merely_rejected(override, expected) -> None:
    """A startup failure reading "invalid config" costs an hour that a specific message does not."""
    problems = _settings(app_env="prod", **override).validate_for_environment()
    assert any(expected in p for p in problems), problems


def test_staging_is_held_to_the_same_bar_as_production() -> None:
    """A staging box that grants Pro to everyone tests nothing that matters — and staging is the
    environment an outside tester reaches first."""
    assert _settings(app_env="staging", llm_provider="fake").validate_for_environment()


def test_a_weak_secret_is_rejected_because_it_is_the_identity_key() -> None:
    """The principal id is an HMAC under this key. A guessable key means a client can compute
    anyone's principal id from their installation id."""
    problems = _settings(app_env="prod", secret_key="k" * 31).validate_for_environment()
    assert problems and "SECRET_KEY" in problems[0]


# --------------------------------------------------------------------------------------------
# Apple environment — sandbox receipts must not be honoured in production
# --------------------------------------------------------------------------------------------


def test_production_accepts_only_production_receipts() -> None:
    """Accepting a sandbox receipt in production is free Pro for anyone with a sandbox Apple ID."""
    assert _settings(app_env="prod").apple_environment == "production"


def test_every_other_environment_uses_sandbox() -> None:
    for env in ("dev", "test", "staging"):
        assert _settings(app_env=env).apple_environment == "sandbox"


def test_the_apple_environment_is_derived_rather_than_configured() -> None:
    """Two knobs that must agree eventually will not, so there is only one."""
    assert "apple_environment" not in Settings.model_fields


def test_a_live_environment_cannot_skip_device_binding() -> None:
    """Without it, an installation id alone opens a session for any account — the exact takeover
    that session tokens were mistakenly believed to have closed."""
    problems = _settings(app_env="prod", require_device_binding=False).validate_for_environment()
    assert any("REQUIRE_DEVICE_BINDING" in p for p in problems)
