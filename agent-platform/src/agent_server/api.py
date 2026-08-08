"""The HTTP surface a phone talks to.

Three endpoints, which is all G1 needs:

* `GET  /health`      — is it up, and what is it wired to
* `POST /v1/session`  — capability negotiation; returns the principal and the effective tool set
* `POST /v1/analyze`  — one turn

Run it on the dev box and point the phone at `http://<lan-ip>:8000`. That is the same architecture
as production; only the URL differs, which is the whole point of the placement work
(ARCHITECTURE.md §12).

Every error a client sees is an `ErrorEnvelope`: a code, a safe message, a correlation id. Detail
goes to the log against the same id. A client never receives a traceback, a provider message, or a
database error.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, File, Form, Request, UploadFile
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict

from agent_core.consent import DEFAULT_PURPOSES
from agent_core.contracts import (
    PROTOCOL_VERSION,
    AnalysisRequest,
    AnalysisResponse,
    ClientHints,
    Entitlement,
    ErrorCode,
    ErrorEnvelope,
    Principal,
)
from agent_core.conversation import ModelTurn, StopReason
from agent_core.dispatch import ToolCall
from agent_core.plans import DEFAULT_PLANS, PHOTO_FEATURE
from agent_core.tools import Platform
from agent_server.adapters.llm.anthropic import AnthropicAdapter
from agent_server.adapters.llm.base import (
    ModelAdapter,
    ProviderRefusal,
    require,
    warn_missing,
)
from agent_server.adapters.llm.fake import FakeAdapter
from agent_server.adapters.llm.openai_compat import (
    OpenAICompatAdapter,
    discover_loaded_model,
)
from agent_server.agent import Agent
from agent_server.analysis import run_analysis
from agent_server.attachments import MAX_BYTES as MAX_ATTACHMENT_BYTES
from agent_server.attachments import AttachmentStore
from agent_server.audit import AuditEventName, AuditLog, NullAuditLog, PostgresAuditLog
from agent_server.auth import (
    DevPrincipalSource,
    PrincipalSource,
    VerifyingPrincipalSource,
)
from agent_server.billing import (
    FakeVerifier,
    PlanResolver,
    SubscriptionVerifier,
    resolve_plan_limits,
)
from agent_server.core.config import Settings, settings
from agent_server.core.errors import NotEntitled, PlatformError
from agent_server.db.identity import IdentityStore, StoredPrincipalSource
from agent_server.db.ledger import PostgresLedger
from agent_server.db.session import (
    claim_database,
    create_schema,
    make_engine,
    make_sessions,
    verify_schema,
)
from agent_server.devicebind import DeviceProofRequired, load_public_key, verify_proof
from agent_server.gatekey import ACCESS_KEY_HEADER, AccessDenied, GateKeys
from agent_server.ledger import CostLedger, InMemoryLedger
from agent_server.packs import hair_compass as pack
from agent_server.packs.hair_compass_tools import TOOLS
from agent_server.privacy import ConsentDecision, PrivacyService, PrivacyState, require_consent
from agent_server.ratelimit import RateLimited, RequestGuard
from agent_server.runs import RunError, RunRegistry
from agent_server.sessions import SessionTokens
from agent_server.turns import PHOTO_PURPOSE, ResultSubmission, TurnRequest, TurnService
from agent_server.upgrade import UpgradePolicy

log = logging.getLogger("agent_server")


class Wiring:
    """What this process resolved at startup. Held on `app.state` so tests can substitute it."""

    def __init__(
        self,
        *,
        config: Settings,
        adapter: ModelAdapter,
        ledger: CostLedger,
        principals: PrincipalSource,
        agent: Agent,
        runs: RunRegistry,
        identity: IdentityStore | None = None,
        sessions=None,
        plans: PlanResolver | None = None,
        guard: RequestGuard | None = None,
        audit: AuditLog | None = None,
        tokens: SessionTokens | None = None,
    ) -> None:
        self.config = config
        self.adapter = adapter
        self.ledger = ledger
        self.principals = principals
        self.agent = agent
        self.runs = runs
        self.identity = identity
        self.plans = plans
        #: Bounds REQUESTS. The ledger bounds spend, and the two come apart exactly where it
        #: matters: an unauthenticated flood costs no tokens but still consumes connections.
        self.guard = guard or RequestGuard()
        #: Never None. A call site that has to ask whether auditing is on is a call site that will
        #: eventually forget to, and the events that go missing are the ones on failure paths.
        self.audit = audit or NullAuditLog()
        #: Proves a caller is the principal they claim. Before this, an installation id was both
        #: the username and the whole credential.
        self.tokens = tokens or SessionTokens(config.secret_key.get_secret_value())
        #: Columns/constraints `create_all` could not add. Empty is healthy; anything here means a
        #: control is silently unenforced, which is what a health check exists to surface.
        self.schema_drift: list[str] = []
        #: The front door. Empty means open, which is only correct off the internet.
        self.gate = GateKeys(config.access_keys)
        #: Only with a database. Without one an upload would succeed and then vanish on the next
        #: deploy, which is worse than refusing it.
        self.attachments = AttachmentStore(sessions) if sessions is not None else None
        #: The lever that lets a build be switched off without taking the service down.
        #: `protocol_version` existed from the first contract and nothing ever acted on it.
        self.upgrades = UpgradePolicy(
            protocol_version=PROTOCOL_VERSION,
            minimum_build=config.minimum_client_build,
            blocked_below=config.blocked_client_build,
            latest_build=config.latest_client_build,
        )
        #: Only exists with a durable store. Consent that cannot be recorded cannot be honoured,
        #: so the endpoints return 503 rather than pretending to accept a decision.
        self.privacy = (
            PrivacyService(identity, purposes=DEFAULT_PURPOSES, audit=self.audit)
            if identity is not None
            else None
        )
        self.turns = TurnService(
            agent=agent,
            runs=runs,
            # The streaming path needs all three or its consent gate, entitlement check and
            # per-plan caps are decoration — which is exactly what they were.
            identity=identity,
            audit=self.audit,
            plans=DEFAULT_PLANS,
            attachments=self.attachments,
        )


def _build_adapter(config: Settings) -> ModelAdapter:
    """Pick the provider from config. One place, one decision — nothing else in the server ever
    learns which one it got (CLAUDE.md §AR).

    The fake is scripted with a **tool-calling** turn rather than a bare answer. An unscripted fake
    makes every integration test vacuously green: the agent never asks for a tool, so nothing about
    dispatch, result routing or ownership is exercised, and five phones "passing" proves only that
    five HTTP connections opened.
    """
    provider = config.llm_provider.lower()
    key = config.llm_api_key.get_secret_value()

    if provider == "anthropic":
        return AnthropicAdapter(api_key=key, model=config.llm_model)

    if provider in {"openai-compat", "lmstudio", "openai"}:
        base_url = config.llm_base_url or "http://127.0.0.1:1234/v1"
        # Blank LLM_MODEL means "use whatever is already loaded". Naming one is not a preference —
        # with just-in-time loading on, it evicts whatever the machine's owner had resident.
        model = config.llm_model or discover_loaded_model(base_url)
        log.info("provider %s using model %r", provider, model)
        return OpenAICompatAdapter(
            base_url=base_url,
            model=model,
            api_key=key,
            name=provider,
        )

    if config.is_prod:
        raise RuntimeError("the fake adapter must never serve production traffic")
    return FakeAdapter().script(
        [
            ModelTurn(
                stop_reason=StopReason.TOOL_USE,
                tool_calls=(
                    ToolCall(
                        id="c_read_entries", tool="read_recent_entries", arguments={"days": 30}
                    ),
                    ToolCall(id="c_read_labs", tool="read_lab_results", arguments={}),
                ),
            ),
            ModelTurn(
                text=(
                    "Your shedding is easing and your ferritin is below range — "
                    "worth raising with a clinician."
                ),
                stop_reason=StopReason.END_TURN,
            ),
        ]
    )


async def build_wiring(config: Settings) -> Wiring:
    """Resolve every capability once, and fail at startup if the provider cannot do what the pack
    requires — a missing capability discovered mid-turn has already charged someone.

    The ledger is durable when a database is reachable and in-memory when it is not. That fallback
    is DISCLOSED, never silent (core-safety M1): an in-memory ledger forgets every budget on
    restart, so a deployment running on one needs to say so rather than look healthy while a user
    who spent their daily quota gets a fresh one on the next deploy.
    """
    problems = config.validate_for_environment()
    if problems:
        # Live environments refuse; dev says it out loud and continues. The list names each
        # setting and why it matters — a startup failure reading "invalid config" costs an hour
        # that a specific message does not.
        message = f"APP_ENV={config.app_env} configuration is unsafe: " + "; ".join(problems)
        if config.is_live:
            raise RuntimeError(message)
        log.warning(message)

    adapter = _build_adapter(config)
    require(adapter, pack.REQUIRED_CAPABILITIES)
    degraded = warn_missing(adapter, pack.PREFERRED_CAPABILITIES)
    if degraded:
        # Allowed, but never silent — an operator must be able to see the reduced mode (M1).
        log.warning(
            "provider %r is missing preferred capabilities: %s", adapter.name, ", ".join(degraded)
        )
    ledger: CostLedger = InMemoryLedger(daily_budget=config.daily_token_budget_per_principal)
    identity: IdentityStore | None = None
    # Without a database the audit log is a no-op that still counts calls, so the server runs and
    # the tests can assert on the call sites. A deployment on this is DEGRADED, and `/health` says
    # so — an audit log nobody can read is not a control.
    audit: AuditLog = NullAuditLog()
    schema_drift: list[str] = []
    sessions = None
    durable = False
    try:
        engine = make_engine(config.database_url)
        # Before anything writes: is this database ours? claim_database bootstraps its own one-row
        # table and runs FIRST, so a staging process pointed at production is rejected before
        # create_all can add any table to it (it would otherwise meter, write and erase real data).
        await claim_database(engine, config.app_env)
        await create_schema(engine)
        schema_drift = await verify_schema(engine)
        if config.is_live and schema_drift:
            # In a live environment a missing required column/constraint is not a warning: without
            # uq_principal_subscription, for instance, one StoreKit receipt entitles many principals.
            # Fail the boot closed rather than serve with the control silently unenforced. Dev still
            # only warns (create_schema logs it). A fresh Supabase database has no drift, so the move
            # itself is never blocked — only a drifted upgrade is.
            raise RuntimeError(
                "schema drift in a live environment — missing: "
                + ", ".join(schema_drift)
                + ". Migrate before starting (create_all does not ALTER an existing table)."
            )
        sessions = make_sessions(engine)
        ledger = PostgresLedger(
            sessions,
            daily_budget=config.daily_token_budget_per_principal,
            # The reason the trial's weekly and lifetime caps now exist at runtime and not only in
            # the tests: limits are looked up per principal, from the plan they actually hold.
            limits_for=lambda plan_id: resolve_plan_limits(DEFAULT_PLANS, plan_id),
        )
        identity = IdentityStore(sessions)
        audit = PostgresAuditLog(sessions)
        durable = True
    except Exception as exc:
        if config.is_live:
            # Never in a live environment (prod OR staging). A "live" server that silently falls
            # back to an in-memory ledger and null audit log — budgets reset on restart, audit
            # events lost — while /health still reports OK is worse than a failed boot. Staging is
            # exactly where a real Supabase / TLS / wrong-database failure must surface, not hide.
            raise
        log.warning(
            "no database (%s) — using an IN-MEMORY ledger. Budgets reset on restart and are NOT "
            "shared across processes.",
            type(exc).__name__,
        )
    if durable:
        log.info("durable ledger + identity store ready")
    # ONE agent for the whole process. It holds no per-user state, so every concurrent turn shares
    # it safely — see the Agent docstring on why `device` is a run() argument and not a field.
    agent = Agent(
        adapter=adapter,
        registry=TOOLS,
        ledger=ledger,
        server_tools={},
        system_prompt=pack.AGENT_SYSTEM_PROMPT,
        safety_policy=pack.SAFETY_POLICY,
        scope_policy=pack.SCOPE_POLICY,
        audit=audit,
        max_output_tokens=config.max_output_tokens_per_turn,
    )
    plans = PlanResolver(DEFAULT_PLANS, _build_verifier(config))
    wiring = Wiring(
        config=config,
        adapter=adapter,
        ledger=ledger,
        principals=_principal_source(config, identity, plans, audit),
        agent=agent,
        runs=RunRegistry(),
        identity=identity,
        sessions=sessions if durable else None,
        plans=plans,
        guard=RequestGuard(),
        audit=audit,
        tokens=SessionTokens(config.secret_key.get_secret_value()),
    )
    wiring.schema_drift = schema_drift
    return wiring


def _build_verifier(config: Settings) -> SubscriptionVerifier:
    """Real StoreKit verification when a bundle id is configured; the fake otherwise.

    The fake refuses to construct in prod, so a production deployment that forgot to configure
    Apple fails at startup rather than quietly granting everyone a paid plan.
    """
    if config.apple_bundle_id and config.is_live:
        from agent_server.billing import AppleVerifier

        # Loaded from disk, not passed empty. `AppleVerifier` refuses an empty list — correctly,
        # since a verifier with no chain to validate against is worse than none — so this used to
        # make `APP_ENV=prod` fail at startup. Nothing caught it because nothing ran in prod.
        roots = _apple_roots(config.apple_root_cert_dir)
        return AppleVerifier(
            bundle_id=config.apple_bundle_id,
            app_apple_id=int(config.apple_app_apple_id) if config.apple_app_apple_id else None,
            environment=config.apple_environment,
            root_certificates=roots,
        )
    if config.is_live:
        # A live environment with no bundle id would silently fall through to the fake verifier,
        # which refuses to construct in prod — a confusing crash rather than a clear one. Say what
        # is missing instead.
        raise RuntimeError(
            f"APP_ENV={config.app_env} requires APPLE_BUNDLE_ID and APPLE_ROOT_CERT_DIR — "
            "refusing to start without a way to verify a receipt"
        )
    return FakeVerifier(is_prod=config.is_prod)


def _apple_roots(directory: str) -> list[bytes]:
    """Apple's root certificates, as DER bytes.

    Read at startup so a missing or empty directory fails loudly here rather than on the first
    purchase — the difference between a deploy that does not come up and a paywall that silently
    rejects every paying customer.
    """
    from pathlib import Path

    if not directory:
        raise RuntimeError("APPLE_ROOT_CERT_DIR is required in production")
    root = Path(directory)
    certs = [p.read_bytes() for p in sorted(root.glob("*.cer"))] if root.is_dir() else []
    if not certs:
        raise RuntimeError(f"no Apple root certificates (*.cer) found in {directory!r}")
    return certs


def _principal_source(
    config: Settings,
    identity: IdentityStore | None,
    plans: PlanResolver,
    audit: AuditLog,
) -> PrincipalSource:
    """Verify the subscription in prod; grant a configured entitlement only in dev.

    Verification is the DEFAULT everywhere, and a live environment cannot opt out of it at all.
    `trust_client_without_receipt` is the dev-only escape hatch, and it is off unless somebody sets
    it — a paywall that has to be switched on is a paywall that ships off, which is precisely what
    happened: a dev box reachable through a tunnel granted PRO to every anonymous caller.
    """
    if config.is_live or not config.trust_client_without_receipt:
        return VerifyingPrincipalSource(
            secret=config.secret_key.get_secret_value(),
            plans=plans,
            catalogue=DEFAULT_PLANS,
            identity=identity,
            audit=audit,
            testers=config.testers,
        )
    log.warning(
        "TRUST_CLIENT_WITHOUT_RECEIPT is set — every caller is granted %r without a receipt. "
        "Never expose this process to a network you do not control.",
        config.dev_entitlement,
    )
    source: PrincipalSource = DevPrincipalSource(
        secret=config.secret_key.get_secret_value(),
        entitlement=Entitlement(config.dev_entitlement),
        is_prod=config.is_prod,
    )
    return StoredPrincipalSource(source, identity) if identity else source


#: How often to release reservations whose turn died before settling.
RECLAIM_INTERVAL_SECONDS = 5 * 60


async def _reclaim_loop(wiring: Wiring) -> None:
    """Give back quota held by turns that never settled.

    `reclaim_orphans` existed and was called from nowhere, so a turn that died between reserving
    and settling held its worst-case estimate against the user's budget **forever** — they lost
    quota to an outage that was never their fault, and no amount of waiting gave it back.

    Failures are logged and the loop continues: a background janitor must not be able to take the
    server down.
    """
    if not isinstance(wiring.ledger, PostgresLedger) and wiring.attachments is None:
        return
    while True:
        await asyncio.sleep(RECLAIM_INTERVAL_SECONDS)
        try:
            freed = await wiring.ledger.reclaim_orphans()
            if freed:
                log.info("reclaimed %d orphaned reservations", freed)
            if wiring.attachments is not None:
                # Photos uploaded and never used — a turn abandoned, refused on consent, or killed
                # mid-flight. Without this the "transient" claim quietly stops being true.
                reaped = await wiring.attachments.reap()
                if reaped:
                    log.info("reaped %d orphaned attachments", reaped)
        except Exception:
            log.exception("orphan reclamation failed; will retry")


@asynccontextmanager
async def lifespan(app: FastAPI):
    config = getattr(app.state, "config", None) or settings()
    app.state.wiring = getattr(app.state, "wiring", None) or await build_wiring(config)
    audit = app.state.wiring.audit
    if isinstance(audit, PostgresAuditLog):
        # Started here rather than in the constructor: creating a task needs a running loop, and
        # `build_wiring` is also called from tests that never start one.
        audit.start()
    reclaimer = asyncio.create_task(_reclaim_loop(app.state.wiring), name="ledger-reclaim")
    log.info("agent-server up: protocol=v%s pack=%s", PROTOCOL_VERSION, pack.PACK_VERSION)
    try:
        yield
    finally:
        reclaimer.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await reclaimer
        if isinstance(audit, PostgresAuditLog):
            # Flush on the way out. Events accepted but not yet written are the ones most likely to
            # explain why the process is going down.
            await audit.stop()


app = FastAPI(title="agent-platform", version="0.1.0", lifespan=lifespan)


def _client_address(wiring: Wiring, request: Request) -> str | None:
    """The caller's real address, which is not the socket address when behind a proxy.

    Behind a Cloudflare Tunnel every request arrives from the connector's own local address, so
    without this the per-address limit is ONE bucket shared by everyone: a single noisy client
    locks out the world, and per-attacker isolation is nil.

    The header is read ONLY when configured, because a header a client can set is a rate limit a
    client can evade — it is trustworthy exactly when a proxy is known to overwrite it.
    """
    header = wiring.config.client_ip_header
    if header:
        value = request.headers.get(header, "")
        if value:
            # `X-Forwarded-For` is a chain; the left-most entry is the original client.
            return value.split(",")[0].strip()
    return request.client.host if request.client else None


@app.middleware("http")
async def _rate_limit(request: Request, call_next):
    """Per-address limiting on every request, before the route runs.

    `RequestGuard` was constructed in `Wiring` and called from nowhere — a limiter that is never
    consulted is a comment. Middleware rather than a per-route dependency precisely because of how
    that happened: a dependency has to be remembered on each new endpoint, and the one someone
    forgets is the one that gets flooded.

    Address only here. The principal is not known until a route has derived it, and deriving one
    for every request in a flood is the work the address limit exists to avoid — the per-principal
    check happens in the routes that have a principal.

    `/health` is exempt so a monitor cannot lock itself out of the thing it monitors.
    """
    wiring: Wiring | None = getattr(request.app.state, "wiring", None)
    if wiring is not None and wiring.gate and request.url.path != "/livez":
        # BEFORE the rate limiter and before routing, and unlike the limiter this covers /health
        # too — that endpoint reports the provider, the model, the plan ids and whether the paywall
        # is enforced, which is a map of the deployment for anyone who asks. `/livez` is the one
        # exemption: it is metadata-free, so the container healthcheck can prove liveness without a key.
        try:
            holder = wiring.gate.holder(request.headers.get(ACCESS_KEY_HEADER))
        except AccessDenied as exc:
            return await _platform_error(request, exc)
        request.state.gate_holder = holder

    if wiring is not None and request.url.path not in ("/health", "/livez"):
        try:
            await wiring.guard.check_address(_client_address(wiring, request))
        except RateLimited as exc:
            wiring.audit.record(
                AuditEventName.RATE_LIMITED,
                principal_id="",
                detail={"scope": "address", "path": request.url.path},
            )
            return await _platform_error(request, exc)
    return await call_next(request)


@app.exception_handler(PlatformError)
async def _platform_error(request: Request, exc: PlatformError) -> JSONResponse:
    correlation_id = uuid4().hex
    # Detail is for us; the client gets the safe message and the id to quote.
    log.warning("%s [%s] %s", exc.code.value, correlation_id, exc.detail or "-")
    return JSONResponse(
        status_code=exc.status,
        content=ErrorEnvelope(
            error_code=exc.code, message=exc.message, correlation_id=correlation_id
        ).model_dump(),
    )


@app.exception_handler(ProviderRefusal)
async def _refusal(request: Request, exc: ProviderRefusal) -> JSONResponse:
    correlation_id = uuid4().hex
    log.warning("provider_refusal [%s]", correlation_id)
    return JSONResponse(
        status_code=422,
        content=ErrorEnvelope(
            error_code=ErrorCode.PROVIDER_UNAVAILABLE,
            message="That request couldn't be analysed. Your app's own summary is still available.",
            correlation_id=correlation_id,
        ).model_dump(),
    )


class SessionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    installation_id: str
    #: The StoreKit / Play receipt. Ignored in dev; verified server-side in prod.
    subscription_token: str = ""
    #: What the client believes the wire format is. A mismatch is refused rather than negotiated —
    #: the shapes differ, so there is nothing to negotiate with.
    protocol_version: int = PROTOCOL_VERSION

    #: The device's public key, base64 DER. Sent on first contact to CLAIM this installation id.
    #: Ignored once the id is bound — rebinding is the takeover this exists to stop.
    device_key: str = ""
    #: Base64 signature over "<installation_id>:<timestamp>" with the bound private key, and the
    #: timestamp it was made at. Required once the installation is bound.
    device_proof: str = ""
    device_proof_at: int = 0
    hints: ClientHints

    # `app_id` deliberately ABSENT. It used to default to the pack name and be overridable by the
    # body, and the principal id is an HMAC over `f"{app_id}:{installation_id}"` — so a client that
    # varied the app id minted a new principal on demand, with its own budget, its own consent
    # record and its own audit trail. It did not even need malice: `/v1/session` read the body
    # while `/v1/turn` used the pack name, so `hair_compass` and `hair-compass` gave one device two
    # identities and two token budgets. One process serves one pack; the app id is a SERVER fact.


class ToolDescriptor(BaseModel):
    name: str
    description: str
    runtime: str
    schema_: dict[str, Any]
    mutates: bool
    requires_idempotency_key: bool


class SessionResponse(BaseModel):
    protocol_version: int
    pack: str
    pack_version: str
    principal: Principal
    #: What this plan unlocks — e.g. `photo_analysis`. Sent so the client can HIDE an attachment
    #: button rather than let someone choose a photo and then be refused, which reads as a bug.
    features: list[str]
    #: Whether this device's key is backed by an App Attest attestation.
    device_attested: bool = False
    #: current / encouraged / required — so an app can nag for two weeks before anyone is cut off.
    #: A forced upgrade that arrives as a sudden error is a support ticket.
    upgrade: str
    #: What the paywall should render: the products on sale, in order, plus the trial length.
    #: Sent from the SERVER so pricing structure is a config change rather than an App Store
    #: review — the client displays what it is told, and never decides what someone is entitled to.
    offer: dict[str, Any]
    #: Proof of who this caller is, for every subsequent request. An installation id is at best a
    #: username — before this existed, anyone who learned another user's could read their consent
    #: record and audit trail, or erase their account.
    session_token: str
    #: The effective tool set for THIS device — server allowlist ∩ entitlement ∩ platform ∩
    #: protocol ∩ what the client advertised. The client term only ever removes.
    tools: list[ToolDescriptor]
    envelope_schema_versions: list[int]


async def _caller(wiring: Wiring, token: str, *, path: str) -> Principal:
    """The principal behind a session token, rate-limited.

    Every endpoint except `/v1/session` goes through here. Deriving identity from a body field the
    client picks — which is what `installation_id` is — meant the only thing standing between a
    stranger and someone else's account was knowing a string the app itself generates.
    """
    principal = wiring.tokens.verify(token)
    await _check_principal(wiring, principal, path=path)
    return principal


async def _check_principal(wiring: Wiring, principal, *, path: str) -> None:
    """The per-account half of the limit. Survives an IP change, so a phone roaming from wifi to
    cellular is not punished and one account cannot be multiplied by rotating addresses."""
    try:
        await wiring.guard.check_principal(principal.principal_id)
    except RateLimited:
        wiring.audit.record(
            AuditEventName.RATE_LIMITED,
            principal_id=principal.principal_id,
            device_id=principal.installation_id,
            detail={"scope": "principal", "path": path},
        )
        raise


@app.get("/health")
async def health(request: Request) -> dict[str, Any]:
    wiring: Wiring = request.app.state.wiring
    return {
        "status": "ok",
        "protocol_version": PROTOCOL_VERSION,
        "pack": f"{pack.PACK_NAME}@{pack.PACK_VERSION}",
        "safety_policy": pack.SAFETY_POLICY.version,
        "text_rules": [rule.name for rule in pack.SAFETY_POLICY.text_rules],
        "provider": f"{wiring.adapter.name}:{wiring.adapter.model}",
        # Surfaced so an operator can see the reduced mode rather than discovering it from a bill.
        "ledger": "postgres" if isinstance(wiring.ledger, PostgresLedger) else "in-memory",
        # A quiet audit log and a broken one look identical without this. `dropped` rising is the
        # signal that the database is refusing writes while every request still returns 200.
        "audit": (
            {
                "backend": "postgres",
                "written": wiring.audit.written,
                "dropped": wiring.audit.dropped,
            }
            if isinstance(wiring.audit, PostgresAuditLog)
            else {"backend": "none"}
        ),
        "plans": [p.id for p in DEFAULT_PLANS],
        "subscription_only": DEFAULT_PLANS.subscription_only,
        "degraded": warn_missing(wiring.adapter, pack.PREFERRED_CAPABILITIES),
        "env": wiring.config.app_env,
        # Empty is the healthy state. Anything here means a control that depends on a missing
        # column or constraint is NOT being enforced, and a monitor could not see that before.
        "schema_drift": wiring.schema_drift,
        # Whether the paywall and the consent gate are actually enforced here. An operator looking
        # at a staging box needs to tell it apart from a dev box at a glance, and "env: staging" on
        # its own does not say whether receipts are being verified.
        "enforcing": {
            "subscriptions": (
                wiring.config.is_live or not wiring.config.trust_client_without_receipt
            ),
            "consent": wiring.identity is not None,
            "apple_environment": wiring.config.apple_environment,
        },
    }


@app.get("/livez")
async def livez() -> dict[str, str]:
    """Liveness only: the process is up and serving HTTP. No deployment detail, so it is safe to
    leave outside the access-key gate — which is why the container healthcheck probes THIS, not
    `/health` (that one is gated precisely because it maps the deployment). A live server that lost
    its database never *starts*: startup fails closed, so the container exits and restarts. (This is
    liveness, not readiness — a database that dies AFTER boot still returns 200 here, by design.)
    """
    return {"status": "ok"}


async def _prove_device(wiring: Wiring, body: SessionRequest) -> bool:
    """Establish that this caller holds the key bound to this installation id.

    Returns whether the binding is attestation-backed. Raises `DeviceProofRequired` when the
    installation is claimed and the caller cannot sign for it.

    Trust on first use: an unclaimed id is bound to whatever key is presented. Racing to claim an
    id nobody uses wins an empty account, so that is not the attack worth defending against — the
    one that matters is taking over a BOUND id, and that is refused.

    With no store, or with no key ever presented, this degrades to allowing. That is a real gap and
    it is bounded to development: `require_device_binding` makes the proof mandatory, and a live
    environment that skips it is a live environment where an installation id is still a password.
    """
    identity = wiring.identity
    if identity is None:
        return False

    bound = await identity.bound_device(body.installation_id)

    if bound is not None:
        verify_proof(bound, signature_b64=body.device_proof, timestamp=body.device_proof_at)
        await identity.record_proof(body.installation_id)
        wiring.audit.record(
            "device.proved",
            principal_id="",
            device_id=body.installation_id,
            detail={"attested": bound.attested},
        )
        return bound.attested

    if body.device_key:
        await identity.bind_device(
            body.installation_id, public_key=load_public_key(body.device_key)
        )
        wiring.audit.record(
            "device.bound", principal_id="", device_id=body.installation_id, detail={}
        )
        return False

    if wiring.config.require_device_binding:
        # No key offered and none on file. Allowed in development so a curl can still open a
        # session; refused anywhere the id would otherwise be a password.
        raise DeviceProofRequired("this deployment requires a device key")
    return False


def _offer() -> dict[str, Any]:
    """The subscription offer, as the client should show it.

    Prices are NOT here. They live in App Store Connect, which is the only place that knows what a
    given user in a given country actually pays after Apple's tiering — duplicating them server-side
    creates a second source of truth and one of them is wrong, usually the one on the screen.
    """
    group = DEFAULT_PLANS.group("pro")
    trial = DEFAULT_PLANS.trial_for(group[0].id) if group else None
    taster = DEFAULT_PLANS.taster
    return {
        # The default selection. Monthly, because that is what the trial converts to and a paywall
        # that pre-selects the bigger commitment reads as a trick.
        "default_product": group[0].product_id if group else "",
        "products": [
            {"id": p.product_id, "plan": p.id, "display_name": p.display_name} for p in group
        ],
        "trial_days": trial.trial_days if trial else 0,
        "free_days": taster.available_for_days if taster else 0,
    }


@app.post("/v1/session", response_model=SessionResponse)
async def start_session(body: SessionRequest, request: Request) -> SessionResponse:
    wiring: Wiring = request.app.state.wiring
    # BEFORE deriving a principal. An installation id is a username; this is the password half,
    # and without it this endpoint mints a valid session for whatever id it is handed — which is
    # exactly the account takeover session tokens were mistakenly believed to have closed.
    device_attested = await _prove_device(wiring, body)
    principal = await wiring.principals.principal_for(
        app_id=pack.PACK_NAME,
        installation_id=body.installation_id,
        subscription_token=body.subscription_token,
    )
    await _check_principal(wiring, principal, path="/v1/session")
    # Raises only for BLOCKED — an incompatible or known-dangerous build. A merely stale one is
    # served and told.
    upgrade = wiring.upgrades.check(
        client_protocol=body.protocol_version, app_build=body.hints.app_build
    )
    wiring.audit.record(
        AuditEventName.SESSION_STARTED,
        principal_id=principal.principal_id,
        device_id=body.installation_id,
        detail={
            "app_id": pack.PACK_NAME,
            "plan": principal.entitlement.value,
            "platform": body.hints.platform,
            # Whether a subscription token was PRESENTED, never the token. Distinguishes "the app
            # never sent one" from "it sent one and we rejected it", which are different bugs.
            "token_presented": bool(body.subscription_token),
        },
    )
    platform = Platform(body.hints.platform)
    tools = TOOLS.resolve(
        platform=platform,
        entitlement=principal.entitlement,
        protocol_version=PROTOCOL_VERSION,
        client_advertised=body.hints.available_capabilities or None,
    )
    return SessionResponse(
        upgrade=upgrade.value,
        offer=_offer(),
        # Surfaced so the app can tell a hardware-backed binding from a plain one, and so an
        # operator can see how many real devices are attesting before making it mandatory.
        device_attested=device_attested,
        features=sorted(DEFAULT_PLANS.get(principal.plan_id).features),
        session_token=wiring.tokens.issue(principal),
        protocol_version=PROTOCOL_VERSION,
        pack=pack.PACK_NAME,
        pack_version=pack.PACK_VERSION,
        principal=principal,
        tools=[
            ToolDescriptor(
                name=t.name,
                description=t.description,
                runtime=t.runtime.value,
                schema_=t.schema,
                mutates=t.mutates,
                requires_idempotency_key=t.requires_idempotency_key,
            )
            for t in tools
        ],
        envelope_schema_versions=sorted(pack.SUPPORTED_SCHEMA_VERSIONS),
    )


@app.post("/v1/attachments")
async def upload_attachment(
    request: Request,
    session_token: str = Form(...),
    file: UploadFile = File(...),
) -> dict[str, object]:
    """Take a photo, return an id. The turn references the id and never the bytes.

    Consent is checked HERE as well as at turn time. The two are different moments — a photo can be
    uploaded and the turn abandoned — and refusing the upload means the bytes never exist on this
    machine at all, which is a better outcome than storing them and deciding later.

    Read with a hard cap rather than trusting `Content-Length`: the header is a claim, and reading
    one byte past the limit is enough to know it was a lie without buffering the rest.
    """
    wiring: Wiring = request.app.state.wiring
    principal = await _caller(wiring, session_token, path="/v1/attachments")
    if wiring.attachments is None:
        raise PlatformError("attachments need a durable store")

    if not DEFAULT_PLANS.get(principal.plan_id).allows_feature(PHOTO_FEATURE):
        # Refused before consent and before a single byte is read. A plan that cannot use photos
        # should never have them uploaded "just in case".
        raise NotEntitled(f"principal={principal.principal_id} plan={principal.plan_id}")

    await require_consent(
        wiring.identity,
        principal,
        purpose=PHOTO_PURPOSE,
        crosses_border=True,
        audit=wiring.audit,
    )

    data = await file.read(MAX_ATTACHMENT_BYTES + 1)
    stored = await wiring.attachments.put(principal_id=principal.principal_id, data=data)
    wiring.audit.record(
        "attachment.stored",
        principal_id=principal.principal_id,
        device_id=principal.installation_id,
        # Metadata only, which is the same rule the rest of the audit log follows: size and type
        # say what happened, and the bytes are the thing that must never be recorded.
        detail={"media_type": stored["media_type"], "bytes": stored["bytes"]},
    )
    return stored


class PrivacyRequest(BaseModel):
    """Identify the caller by their session token.

    No installation id and no principal id. Both are things a client picks or can learn, and these
    endpoints read and erase personal data — the credential has to be something only the server
    could have issued.
    """

    model_config = ConfigDict(extra="forbid")

    session_token: str


class ConsentRequest(PrivacyRequest):
    decision: ConsentDecision


def _privacy(wiring: Wiring) -> PrivacyService:
    if wiring.privacy is None:
        raise PlatformError("privacy operations need a durable store")
    return wiring.privacy


@app.post("/v1/privacy/consent")
async def set_consent(body: ConsentRequest, request: Request) -> dict[str, str]:
    """Grant or withdraw one purpose.

    One endpoint for both directions on purpose. Withdrawal has to be exactly as reachable as
    granting — under PDPL and the GDPR alike, consent that is harder to take back than to give is
    not freely given — and a separate `DELETE` route is how the withdrawal path ends up shipped a
    release later than the grant path.
    """
    wiring: Wiring = request.app.state.wiring
    principal = await _caller(wiring, body.session_token, path="/v1/privacy/consent")
    await _privacy(wiring).apply(principal, body.decision)
    return {"status": "recorded"}


@app.post("/v1/privacy/state", response_model=PrivacyState)
async def privacy_state(body: PrivacyRequest, request: Request) -> PrivacyState:
    """What the server holds about the caller: live grants, and the recent metadata trail.

    A POST rather than a GET because the installation id identifies a person, and identifiers in a
    query string end up in access logs, proxy logs and browser history.
    """
    wiring: Wiring = request.app.state.wiring
    principal = await _caller(wiring, body.session_token, path="/v1/privacy/state")
    wiring.audit.record(
        AuditEventName.DATA_EXPORTED,
        principal_id=principal.principal_id,
        device_id=principal.installation_id,
    )
    return await _privacy(wiring).state(principal)


@app.post("/v1/privacy/forget")
async def forget_me(body: PrivacyRequest, request: Request) -> dict[str, Any]:
    """Erase everything the server holds for the caller.

    Apple requires in-app account deletion and Google requires a web path too, so this is not
    optional. Deliberately separate from withdrawing consent: "stop collecting" and "erase what you
    have" are different requests, and collapsing them forces a choice nobody asked for.
    """
    wiring: Wiring = request.app.state.wiring
    principal = await _caller(wiring, body.session_token, path="/v1/privacy/forget")
    removed = await _privacy(wiring).forget(principal)
    return {"status": "erased", "removed": removed}


class AnalyzeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    session_token: str
    request: AnalysisRequest


@app.post("/v1/analyze", response_model=AnalysisResponse)
async def analyze(body: AnalyzeRequest, request: Request) -> AnalysisResponse:
    wiring: Wiring = request.app.state.wiring
    # The principal comes from the signed session token — never from the body, and never from the
    # envelope's `pack` field, which the client also fills in.
    principal = await _caller(wiring, body.session_token, path="/v1/analyze")
    return await run_analysis(
        body.request,
        principal=principal,
        adapter=wiring.adapter,
        ledger=wiring.ledger,
        # Per-plan, not per-process. `resolve_plan_limits` already computed this and it was
        # being discarded in favour of one global config value, so a plan's output cap did nothing.
        max_output_tokens=resolve_plan_limits(DEFAULT_PLANS, principal.plan_id)[
            "max_output_tokens"
        ],
        identity=wiring.identity,
        audit=wiring.audit,
    )


@app.exception_handler(RunError)
async def _run_error(request: Request, exc: RunError) -> JSONResponse:
    """A result for a call that is unknown, finished, or belongs to someone else.

    All three collapse to one 404 with one message. Distinguishing them would tell a prober whether
    a guessed call id exists, and that is the only thing they would learn from probing.
    """
    return JSONResponse(
        status_code=404,
        content=ErrorEnvelope(
            error_code=ErrorCode.INTERNAL,
            message="That tool call is no longer open.",
            correlation_id=uuid4().hex,
        ).model_dump(),
    )


@app.post("/v1/turn")
async def start_turn(body: TurnRequest, request: Request) -> StreamingResponse:
    """Run one agent turn. The response is an SSE stream of tool requests, then the answer."""
    wiring: Wiring = request.app.state.wiring
    # `_caller` rather than a bare token verify: the per-principal limiter was written, tested and
    # NOT applied to the most expensive endpoint in the system.
    principal = await _caller(wiring, body.session_token, path="/v1/turn")
    # Before the StreamingResponse exists, so a refusal is a status code rather than a broken body.
    await wiring.turns.authorize(principal, attachments=len(body.attachments))
    return StreamingResponse(
        wiring.turns.stream(principal=principal, request=body),
        media_type="text/event-stream",
        headers={"cache-control": "no-store", "x-accel-buffering": "no"},
    )


@app.post("/v1/turn/result")
async def submit_result(body: ResultSubmission, request: Request) -> dict[str, Any]:
    """A phone returning one tool result. Idempotent: a resend returns accepted=false, not an error.

    The principal is derived from the authenticated session and checked against the run that issued
    the call. A phone cannot answer a call it was not asked to run.
    """
    wiring: Wiring = request.app.state.wiring
    principal = await _caller(wiring, body.session_token, path="/v1/turn/result")
    return await wiring.turns.submit(principal=principal, submission=body)
