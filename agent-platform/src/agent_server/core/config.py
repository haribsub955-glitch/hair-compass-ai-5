"""Typed settings, loaded once at startup.

The one rule worth stating: a missing required value **crashes the process at boot**, it does not
fall back to a default (SAF4). A server that silently starts without an API key or a database URL
looks healthy and fails on the first real request, which is the worst possible time to find out.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="forbid",
        frozen=True,
    )

    #: Which deployment this process is. `staging` exists because "prod-like but not prod" is
    #: where subscription verification, the real database and the real provider get exercised
    #: before real money and real people are involved — and running that against a `dev` config
    #: proves nothing about production.
    app_env: Literal["dev", "test", "staging", "prod"] = "dev"
    log_level: str = "INFO"

    database_url: str
    secret_key: SecretStr

    # Provider credentials live here and only here. They are never sent to a client, never logged,
    # and never embedded in a build (ARCHITECTURE.md §5, core-safety A3).
    #: "anthropic" | "openai-compat" / "lmstudio" (any OpenAI-shaped endpoint) | "fake" (dev only)
    llm_provider: str = "anthropic"
    #: Only read by the OpenAI-compatible provider. Defaults to LM Studio on this machine.
    llm_base_url: str = ""
    #: Blank means "use whatever the provider already has loaded". Naming a model is not a
    #: passive preference on a just-in-time server — it EVICTS whatever is resident.
    llm_model: str = ""
    llm_api_key: SecretStr = SecretStr("")

    apple_bundle_id: str = ""
    # Blank is legitimate: Apple's own guidance is that sandbox/TestFlight verification works
    # without the numeric App Store id, which only exists once the app record does.
    apple_app_apple_id: str = ""

    #: Skip StoreKit verification and grant `dev_entitlement` to every caller. **Dev only.**
    #:
    #: Defaults to OFF, and that default is the point. It was the other way round — verification
    #: opt-IN — which meant a dev box reachable through a tunnel, which is exactly the
    #: remote-testing plan, handed PRO to every anonymous caller on a server-held provider key.
    #: A control you have to switch on is a control that ships off.
    #:
    #: `_principal_source` ignores this entirely when the environment is live, so there is no value
    #: of it that disables the paywall on staging or production.
    trust_client_without_receipt: bool = False
    #: What `trust_client_without_receipt` grants. Only read in dev.
    dev_entitlement: Literal["free", "pro"] = "pro"

    #: Named testers granted a plan without a purchase, as `installation_id=plan_id` pairs.
    #:
    #: The narrow tool for the job `trust_client_without_receipt` was being used for. That flag
    #: grants the paid tier to EVERY caller, which is fine on a laptop and indefensible the moment
    #: the server is reachable from the internet — which is exactly when you need a tester to have
    #: access. This names them instead: bounded, expiring, and audited per grant.
    #:
    #: Example: `TESTER_GRANTS=dev-abc123=pro_monthly,dev-def456=trial`
    tester_grants: str = ""
    #: ISO date after which every tester grant stops. Blank means they never expire, which is how a
    #: temporary arrangement becomes permanent — set it.
    tester_grants_until: str = ""

    #: Refuse a session unless the caller proves it holds the key bound to its installation id.
    #:
    #: Off in development so a curl can open a session. ON everywhere else — `validate_for_
    #: environment` refuses a live deployment without it, because an installation id that needs no
    #: proof is a password anyone can read off a support ticket.
    require_device_binding: bool = False

    #: Pre-shared front-door keys, as `name=secret` pairs, e.g. `partner=<48 random chars>`.
    #:
    #: Every request must carry one in `X-Access-Key`. Empty disables it, which is right for a
    #: laptop and wrong for anything reachable from the internet — `validate_for_environment`
    #: refuses a live deployment without one.
    #:
    #: Named rather than a single anonymous secret so a key can be identified in the audit log and
    #: withdrawn for one holder without changing everyone else's.
    access_keys: str = ""

    #: Header naming the real client address when the server sits behind a reverse proxy.
    #:
    #: Behind a Cloudflare Tunnel every request arrives from the connector's own local address, so
    #: the per-address rate limit becomes ONE bucket shared by every user: one noisy client locks
    #: out everybody, and per-attacker isolation is zero.
    #:
    #: Blank means "use the socket address", which is right for a direct LAN deployment and wrong
    #: behind a proxy. Set it only when the proxy is trusted to OVERWRITE the header — a header a
    #: client can forge is a rate limit a client can evade.
    client_ip_header: str = ""

    #: Builds below this are told to update, but are still served — cutting someone off mid-task to
    #: make a point about a version is its own harm. Blank disables the nag.
    minimum_client_build: str = ""
    #: Builds below this are REFUSED. For a client with a safety defect or an incompatible wire
    #: format, where there is nothing useful left to do. Blank disables it.
    blocked_client_build: str = ""
    #: The newest build, so a current client can be told it is current. Display only.
    latest_client_build: str = ""

    #: Directory holding Apple's root certificates (the `AppleIncRootCertificate.cer` family).
    #:
    #: Required in production and deliberately not defaulted to a bundled copy: pinning Apple's
    #: roots inside the image means a root rotation ships as an app release. Mounted, so it can be
    #: refreshed without a rebuild.
    apple_root_cert_dir: str = ""

    daily_token_budget_per_principal: int = Field(default=200_000, gt=0)
    max_output_tokens_per_turn: int = Field(default=4096, gt=0)

    @property
    def testers(self) -> dict[str, str]:
        """Parsed `installation_id -> plan_id`, empty once the expiry has passed.

        Parsing is forgiving of whitespace and silently drops malformed pairs rather than refusing
        to start: a typo in a tester list should cost that tester their access, not the deployment.
        """
        if not self.tester_grants:
            return {}
        if self.tester_grants_until:
            from datetime import date

            try:
                if date.fromisoformat(self.tester_grants_until) < date.today():
                    return {}
            except ValueError:
                # An unparseable expiry is treated as EXPIRED, not as absent. Failing the other way
                # would turn a typo into an unbounded grant.
                return {}
        pairs = (item.split("=", 1) for item in self.tester_grants.split(",") if "=" in item)
        return {k.strip(): v.strip() for k, v in pairs if k.strip() and v.strip()}

    @property
    def is_prod(self) -> bool:
        return self.app_env == "prod"

    @property
    def is_live(self) -> bool:
        """Prod OR staging — anywhere a real receipt, a real database and real money can appear.

        Most of the "must not be fake" checks belong here rather than on `is_prod`. A staging box
        that quietly grants Pro to everyone tests nothing that matters, and staging is the
        environment that gets exposed to an outside tester first.
        """
        return self.app_env in {"prod", "staging"}

    @property
    def apple_environment(self) -> str:
        """Which App Store environment issues the receipts this deployment should accept.

        Sandbox and production receipts are signed for different environments, and accepting a
        sandbox receipt in production is free Pro for anyone with a sandbox Apple ID. Derived from
        `app_env` rather than configured separately, because two knobs that must agree eventually
        will not.
        """
        return "production" if self.app_env == "prod" else "sandbox"

    def validate_for_environment(self) -> list[str]:
        """Configuration that is unsafe for THIS environment. Empty means it is fit to start.

        Returned rather than raised so the caller decides the consequence — dev warns, live
        refuses. Each entry names the setting and why it matters, because a startup failure that
        says "invalid config" costs an hour that a specific message does not.
        """
        problems: list[str] = []
        if not self.is_live:
            return problems
        if self.llm_provider.lower() == "fake":
            problems.append("LLM_PROVIDER=fake cannot serve a live environment")
        if self.llm_provider.lower() == "anthropic" and not self.llm_model:
            # An empty model is legitimate for the openai-compat provider ("use whatever is loaded"),
            # but the Anthropic API requires a named model. The adapter validates only the key at
            # boot, so an empty model passes startup and /livez looks healthy — then the first real
            # request sends model="" and fails. Catch it here instead.
            problems.append(
                "LLM_MODEL must be set for the anthropic provider — an empty model boots healthy "
                "but fails on the first request"
            )
        if not self.apple_bundle_id:
            problems.append("APPLE_BUNDLE_ID is required to verify a receipt")
        if not self.apple_root_cert_dir:
            problems.append("APPLE_ROOT_CERT_DIR is required to validate Apple's signature chain")
        if len(self.secret_key.get_secret_value()) < 32:
            # The principal id is an HMAC under this key. A short key means a client that guesses
            # it can compute anyone's principal id from their installation id.
            problems.append("SECRET_KEY must be at least 32 characters")
        if not self.access_keys:
            problems.append(
                "ACCESS_KEYS must be set in a live environment — an internet-reachable server "
                "with no front door is the state that flag exists to prevent"
            )
        if not self.require_device_binding:
            problems.append(
                "REQUIRE_DEVICE_BINDING must be on in a live environment — without it an "
                "installation id alone opens a session for any account"
            )
        if self.trust_client_without_receipt:
            problems.append("TRUST_CLIENT_WITHOUT_RECEIPT cannot be set in a live environment")
        if self.app_env == "prod" and self.tester_grants:
            # Staging is where testers belong. Production selling to real customers must not also
            # be handing out free plans by installation id.
            problems.append("TESTER_GRANTS cannot be set in production")
        if "sqlite" in self.database_url or "memory" in self.database_url:
            problems.append("DATABASE_URL must be a real Postgres in a live environment")
        return problems


@lru_cache(maxsize=1)
def settings() -> Settings:
    """Cached so the env is read once. Tests construct `Settings(...)` directly instead of calling
    this, so they never depend on a developer's local `.env`."""
    return Settings()  # type: ignore[call-arg]
