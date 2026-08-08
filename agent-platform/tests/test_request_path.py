"""Is the control ON the request path — not merely written and tested in isolation?

This file exists because of a specific miss. StoreKit verification and the rate limiter were both
built, unit-tested and green, and neither was reachable: `PlanResolver` was constructed into
`Wiring` and never consulted, `RequestGuard` likewise, and `DevPrincipalSource` was still the only
source of identity. Every unit test passed. The paywall did not exist.

So these assert reachability, which is a different claim from correctness and needs its own tests.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from agent_core.contracts import Entitlement, Principal
from agent_core.conversation import ModelTurn, StopReason
from agent_core.plans import DEFAULT_PLANS, FREE_PLAN_ID
from agent_server.audit import AuditEventName, NullAuditLog
from agent_server.auth import DevPrincipalSource, VerifyingPrincipalSource
from agent_server.billing import FakeVerifier, PlanResolver
from agent_server.ratelimit import Limit, RequestGuard

PRO_PRODUCT = "harib.haircompass.pro.monthly"


def _source(**kw) -> VerifyingPrincipalSource:
    return VerifyingPrincipalSource(
        secret="test-secret",
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier(**kw.pop("verifier", {}))),
        catalogue=DEFAULT_PLANS,
        **kw,
    )


# --------------------------------------------------------------------------------------------
# The paywall
# --------------------------------------------------------------------------------------------


async def test_no_receipt_means_no_paid_entitlement() -> None:
    """The hole, stated plainly: without this the server handed Pro to anyone who asked."""
    principal = await _source().principal_for(
        app_id="hair_compass", installation_id="dev-1", subscription_token=""
    )
    assert principal.entitlement is Entitlement.FREE


async def test_a_verified_receipt_grants_the_paid_entitlement() -> None:
    principal = await _source().principal_for(
        app_id="hair_compass", installation_id="dev-2", subscription_token=f"{PRO_PRODUCT}:txn-1"
    )
    assert principal.entitlement is Entitlement.PRO


async def test_a_junk_receipt_degrades_rather_than_erroring() -> None:
    """Someone whose card just failed must land on the paywall, not on a 500 with no way out."""
    principal = await _source().principal_for(
        app_id="hair_compass", installation_id="dev-3", subscription_token="garbage"
    )
    assert principal.entitlement is Entitlement.FREE


async def test_identity_is_stable_and_does_not_depend_on_paying() -> None:
    """A lapsed subscriber must come back to their own data, not to a fresh principal."""
    source = _source()
    paid = await source.principal_for(
        app_id="hair_compass", installation_id="dev-4", subscription_token=f"{PRO_PRODUCT}:txn-2"
    )
    lapsed = await source.principal_for(
        app_id="hair_compass", installation_id="dev-4", subscription_token=""
    )
    assert paid.principal_id == lapsed.principal_id
    assert paid.entitlement is Entitlement.PRO
    assert lapsed.entitlement is Entitlement.FREE


async def test_the_principal_id_is_not_computable_by_a_client() -> None:
    """HMAC, not a hash of the installation id — otherwise anyone who guesses an installation id
    can name someone else's principal."""
    a = await _source().principal_for(
        app_id="hair_compass", installation_id="dev-5", subscription_token=""
    )
    other_secret = VerifyingPrincipalSource(
        secret="a-different-secret",
        plans=PlanResolver(DEFAULT_PLANS, FakeVerifier()),
        catalogue=DEFAULT_PLANS,
    )
    b = await other_secret.principal_for(
        app_id="hair_compass", installation_id="dev-5", subscription_token=""
    )
    assert a.principal_id != b.principal_id
    assert "dev-5" not in a.principal_id


async def test_a_receipt_claimed_by_someone_else_drops_to_the_base_plan() -> None:
    """Not a hard error: the person may be on a shared device and can still use the app unpaid.
    But they do not get the plan."""

    class _RefusingIdentity:
        async def register(self, principal) -> None: ...
        async def set_plan(self, principal_id, *, plan_id, subscription_txn_id=None) -> bool:
            return False

    audit = NullAuditLog()
    principal = await _source(identity=_RefusingIdentity(), audit=audit).principal_for(
        app_id="hair_compass", installation_id="dev-6", subscription_token=f"{PRO_PRODUCT}:stolen"
    )
    assert principal.entitlement is Entitlement.FREE
    assert dict(audit.events)[AuditEventName.SUBSCRIPTION_VERIFIED]["plan"] == FREE_PLAN_ID


async def test_the_principal_row_exists_before_the_plan_is_set() -> None:
    """Order matters: the UPDATE needs a row, and the ledger's `SELECT ... FOR UPDATE` locks
    nothing at all when the principal does not exist — the cap silently stops being a cap."""
    calls: list[str] = []

    class _Recording:
        async def register(self, principal) -> None:
            calls.append("register")

        async def set_plan(self, principal_id, *, plan_id, subscription_txn_id=None) -> bool:
            calls.append("set_plan")
            return True

    await _source(identity=_Recording()).principal_for(
        app_id="hair_compass", installation_id="dev-7", subscription_token=f"{PRO_PRODUCT}:t"
    )
    assert calls == ["register", "set_plan"]


def test_the_dev_source_still_refuses_production() -> None:
    with pytest.raises(RuntimeError, match="cannot run in prod"):
        DevPrincipalSource(secret="s", entitlement=Entitlement.PRO, is_prod=True)


# --------------------------------------------------------------------------------------------
# The rate limiter, reachable
# --------------------------------------------------------------------------------------------


def _app(guard: RequestGuard):
    """The real FastAPI app with a fake provider behind it.

    `lifespan` takes `app.state.wiring` when one is already set, which is exactly so a test can
    exercise the HTTP layer — middleware, error envelopes, routing — without a provider or a
    database. This is the first test to use it; the API had never been driven over HTTP at all,
    which is part of why two controls could sit unreachable and green.
    """
    from tests.test_agent import TOOLS, FakeAdapter
    from tests.test_privacy import FakeIdentity

    from agent_core.tools import ToolRegistry
    from agent_server.agent import Agent
    from agent_server.api import Wiring, app
    from agent_server.core.config import Settings
    from agent_server.ledger import InMemoryLedger
    from agent_server.runs import RunRegistry

    adapter = FakeAdapter().script([ModelTurn(text="ok", stop_reason=StopReason.END_TURN)] * 50)
    config = Settings(app_env="test", secret_key="x" * 32)
    ledger = InMemoryLedger(daily_budget=1_000_000)
    registry: ToolRegistry = TOOLS
    app.state.config = config
    app.state.wiring = Wiring(
        config=config,
        adapter=adapter,
        ledger=ledger,
        principals=DevPrincipalSource(
            secret="test-secret", entitlement=Entitlement.PRO, is_prod=False
        ),
        agent=Agent(
            adapter=adapter,
            registry=registry,
            ledger=ledger,
            server_tools={},
            system_prompt="be careful",
        ),
        runs=RunRegistry(),
        guard=guard,
        audit=NullAuditLog(),
        # A store, so the privacy endpoints are reachable and these tests exercise AUTH rather
        # than the "no database configured" path.
        identity=FakeIdentity(),
    )
    return app


def test_a_flood_is_refused_by_the_middleware_not_by_the_route() -> None:
    """Reachability, over HTTP. The limiter has to fire before the route body runs — a per-route
    dependency is one someone forgets to add to the next endpoint, and that one gets flooded."""
    app = _app(RequestGuard(address_limit=Limit(count=3, seconds=60)))
    body = {
        "installation_id": "dev-flood",
        "hints": {"platform": "ios", "available_capabilities": []},
    }
    with TestClient(app) as client:
        codes = [client.post("/v1/session", json=body).status_code for _ in range(6)]
    assert 429 in codes, f"the limiter never fired: {codes}"
    assert codes.count(429) == 3


def test_health_stays_reachable_while_the_limiter_is_tripped() -> None:
    """A monitor that can lock itself out of the endpoint it monitors turns a load spike into a
    false outage alert."""
    app = _app(RequestGuard(address_limit=Limit(count=1, seconds=60)))
    with TestClient(app) as client:
        for _ in range(5):
            client.get("/health")
        assert client.get("/health").status_code == 200


def test_a_rate_limited_request_returns_the_error_envelope_the_client_expects() -> None:
    """429 with the standard envelope, not a bare FastAPI error — the client parses one shape."""
    app = _app(RequestGuard(address_limit=Limit(count=1, seconds=60)))
    body = {
        "installation_id": "dev-env",
        "hints": {"platform": "ios", "available_capabilities": []},
    }
    with TestClient(app) as client:
        client.post("/v1/session", json=body)
        refused = client.post("/v1/session", json=body)
    assert refused.status_code == 429
    payload = refused.json()
    assert payload["error_code"] and payload["correlation_id"]


async def test_one_device_gets_exactly_one_principal_across_every_endpoint() -> None:
    """Found by running it, not by reading it.

    `/v1/session` read the app id from the request body while `/v1/turn` used the pack name, so the
    same phone came back as `hair_compass` on one endpoint and `hair-compass` on the other — and the
    principal id is an HMAC over `f"{app_id}:{installation_id}"`. One device, two principals, two
    token budgets, two consent records, two audit trails, and a deletion request that erases half.
    """
    from agent_server.packs import hair_compass as pack

    source = _source()
    ids = {
        (
            await source.principal_for(
                app_id=app_id, installation_id="same-phone", subscription_token=""
            )
        ).principal_id
        for app_id in (pack.PACK_NAME,) * 3
    }
    assert len(ids) == 1

    # And the id must genuinely depend on the app, or two packs on one deployment would share
    # budgets. The fix is that clients cannot CHOOSE it, not that it stopped mattering.
    other = await source.principal_for(
        app_id="a-different-pack", installation_id="same-phone", subscription_token=""
    )
    assert other.principal_id not in ids


# --------------------------------------------------------------------------------------------
# Authentication, over HTTP.
#
# Identity used to come from `installation_id` — a value the client sends and picks — so anyone who
# learned another user's could read their consent record and audit trail, or erase their account.
# --------------------------------------------------------------------------------------------


def _session(client, installation_id: str) -> str:
    response = client.post(
        "/v1/session",
        json={
            "installation_id": installation_id,
            "hints": {"platform": "ios", "available_capabilities": []},
        },
    )
    assert response.status_code == 200, response.text
    return response.json()["session_token"]


def test_the_privacy_endpoints_refuse_a_caller_with_no_token() -> None:
    app = _app(RequestGuard())
    with TestClient(app) as client:
        for path in ("/v1/privacy/state", "/v1/privacy/forget"):
            assert client.post(path, json={}).status_code == 422, path


def test_knowing_someone_elses_installation_id_grants_nothing() -> None:
    """The attack, end to end. Mallory knows Alice's installation id — which the app generates and
    which appears in logs, backups and support tickets — and it now buys her nothing."""
    app = _app(RequestGuard())
    with TestClient(app) as client:
        mallory = _session(client, "dev-mallory")
        # Mallory's own token works.
        assert client.post("/v1/privacy/state", json={"session_token": mallory}).status_code == 200
        # Alice's installation id is not a credential, and there is nowhere left to put it.
        refused = client.post(
            "/v1/privacy/forget", json={"session_token": "", "installation_id": "dev-alice"}
        )
        assert refused.status_code == 422


def test_a_forged_token_is_refused_by_the_endpoint_not_just_the_verifier() -> None:
    """Reachability again: the check has to be on the path, not merely implemented."""
    from agent_server.sessions import SessionTokens

    app = _app(RequestGuard())
    forged = SessionTokens("z" * 40).issue(
        Principal(
            app_id="hair-compass",
            principal_id="p_victim",
            installation_id="dev-victim",
            data_subject_id="d_victim",
            entitlement=Entitlement.PRO,
        )
    )
    with TestClient(app) as client:
        response = client.post("/v1/privacy/state", json={"session_token": forged})
    assert response.status_code == 401
    assert response.json()["error_code"] == "unauthenticated"


def test_a_session_token_is_bound_to_the_principal_that_asked_for_it() -> None:
    app = _app(RequestGuard())
    with TestClient(app) as client:
        alice = _session(client, "dev-alice")
        bob = _session(client, "dev-bob")
    assert alice != bob


# --------------------------------------------------------------------------------------------
# /v1/turn — the gates that were only ever on /v1/analyze.
#
# The streaming endpoint is the expensive one and it had neither a consent check nor an
# entitlement check, so the same health data reached the same provider by whichever route the
# client chose. Under PDPL the streaming route was an unconsented cross-border transfer.
# --------------------------------------------------------------------------------------------


def _turn(client, token: str):
    return client.post(
        "/v1/turn", json={"session_token": token, "user_text": "is my shedding normal?"}
    )


def test_a_turn_without_a_consent_record_is_refused() -> None:
    app = _app(RequestGuard())
    with TestClient(app) as client:
        token = _session(client, "dev-noconsent")
        response = _turn(client, token)
    assert response.status_code == 403
    assert response.json()["error_code"] == "consent_required"


async def test_a_turn_on_an_unpaid_plan_is_refused_before_consent_is_even_considered() -> None:
    """Cheapest refusal first, and both before a run is opened or a token is reserved.

    Driven through `authorize` directly rather than over HTTP, because the dev principal source
    only ever issues a paid plan — there is no unpaid caller to produce from that end.
    """
    from tests.test_privacy import FakeIdentity

    from agent_core.plans import DEFAULT_PLANS
    from agent_server.core.errors import NotEntitled
    from agent_server.runs import RunRegistry
    from agent_server.turns import TurnService

    lapsed = Principal(
        app_id="hair-compass",
        principal_id="p_lapsed",
        installation_id="dev-lapsed",
        data_subject_id="d_lapsed",
        entitlement=Entitlement.FREE,
        plan_id="free",
    )
    # Consent IS on file, so the plan is the only thing left to refuse on.
    identity = FakeIdentity()
    await identity.grant(
        lapsed.principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=True
    )
    service = TurnService(agent=None, runs=RunRegistry(), identity=identity, plans=DEFAULT_PLANS)
    with pytest.raises(NotEntitled):
        await service.authorize(lapsed)


async def test_a_paid_plan_with_consent_passes_both_gates() -> None:
    """A gate that refuses everything is as useless as one that refuses nothing."""
    from tests.test_privacy import FakeIdentity

    from agent_core.plans import DEFAULT_PLANS
    from agent_server.runs import RunRegistry
    from agent_server.turns import TurnService

    paid = Principal(
        app_id="hair-compass",
        principal_id="p_paid",
        installation_id="dev-paid",
        data_subject_id="d_paid",
        entitlement=Entitlement.PRO,
        plan_id="pro_monthly",
    )
    identity = FakeIdentity()
    await identity.grant(
        paid.principal_id, purpose="agent-analysis", policy_version="1.0", crosses_border=True
    )
    await TurnService(
        agent=None, runs=RunRegistry(), identity=identity, plans=DEFAULT_PLANS
    ).authorize(paid)


def test_the_per_plan_output_cap_is_the_plans_own_number() -> None:
    """`entitlement.value` is "free"/"pro"; plan ids are free/taster/trial/pro_monthly/pro_yearly.
    Looking limits up by the enum resolved every caller to the FREE plan, truncating every
    response to 512 output tokens no matter what they paid."""
    from agent_core.plans import DEFAULT_PLANS
    from agent_server.billing import resolve_plan_limits

    assert resolve_plan_limits(DEFAULT_PLANS, "pro")["max_output_tokens"] == 512
    assert resolve_plan_limits(DEFAULT_PLANS, "pro_monthly")["max_output_tokens"] == 2048
    assert resolve_plan_limits(DEFAULT_PLANS, "pro_monthly")["max_iterations"] == 6


def test_the_session_token_carries_the_plan_not_just_the_coarse_tier() -> None:
    app = _app(RequestGuard())
    with TestClient(app) as client:
        token = _session(client, "dev-planid")
        principal = app.state.wiring.tokens.verify(token)
    assert principal.plan_id
    assert principal.plan_id != principal.entitlement.value or principal.plan_id in {"free", "pro"}


# --------------------------------------------------------------------------------------------
# The front door. Everything, including /health.
# --------------------------------------------------------------------------------------------


def test_a_short_secret_is_refused_rather_than_accepted() -> None:
    """A guessable front door is worse than none: it looks like a control while inviting exactly
    one brute-force loop."""
    from agent_server.gatekey import GateKeys

    assert not GateKeys("partner=short")
    assert not GateKeys("=" + "k" * 32)
    assert GateKeys("partner=" + "k" * 32).names == ("partner",)


def test_the_wrong_key_and_no_key_are_indistinguishable() -> None:
    """A caller who can tell them apart has learnt that keys are what this wants."""
    from agent_server.gatekey import AccessDenied, GateKeys

    gate = GateKeys("partner=" + "k" * 32)
    messages = set()
    for presented in (None, "", "x" * 32):
        try:
            gate.holder(presented)
        except AccessDenied as exc:
            messages.add(exc.message)
    assert len(messages) == 1


def test_a_key_identifies_its_holder_so_one_can_be_withdrawn() -> None:
    from agent_server.gatekey import GateKeys

    gate = GateKeys(f"partner={'a' * 32},ci={'b' * 32}")
    assert gate.holder("a" * 32) == "partner"
    assert gate.holder("b" * 32) == "ci"


def test_an_empty_gate_lets_everything_through() -> None:
    """Off by default, so a laptop and the test suite are untouched."""
    from agent_server.gatekey import GateKeys

    assert GateKeys("").holder(None) == ""
