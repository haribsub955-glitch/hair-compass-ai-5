"""Subscription verification — what a purchase actually entitles someone to.

Until now `DevPrincipalSource` handed Pro to everyone. That is fine for a LAN and is the single
biggest hole between here and taking money.

**The failure this closes, precisely.** A StoreKit signed transaction (JWS) is a *bearer* artefact:
it is signed by Apple, it does not change until the subscription expires, and it says nothing about
who is presenting it. Treat the JWS itself as the credential and one extracted token is replayable
for the rest of the billing period, shareable, and worth unlimited spend on your provider key.

So the JWS is exchanged, not trusted-in-place: verify it once, bind the result to a principal, and
meter that principal. What the client holds afterwards is a session bound to them, not a token
anyone could use.

**Verification is Apple's library's job, not ours** (CLAUDE.md §OSF — adopt before building).
Certificate-chain validation against Apple's root, revocation, environment checks: all subtle, all
already solved in `app-store-server-library`. Hand-rolling it is how a verifier ends up accepting
a self-signed token because someone skipped the chain check to make a test pass.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any, Protocol, runtime_checkable

from pydantic import BaseModel, ConfigDict

from agent_core.plans import FREE_PLAN_ID, PlanCatalogue

log = logging.getLogger("agent_server.billing")


class VerificationError(RuntimeError):
    """A token that could not be verified. Never distinguishes *why* to the client — a caller
    learning "signature bad" vs "expired" learns how to probe."""


class VerifiedSubscription(BaseModel):
    """The facts a verified receipt establishes. Nothing here comes from the client."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    product_id: str
    #: Apple's opaque, app-scoped account identifier. Stable across reinstalls on the same Apple ID,
    #: which is what makes "restore purchases" work and what stops a reinstall minting a new trial.
    original_transaction_id: str
    expires_at: datetime | None = None
    #: True while Apple reports the subscription inside its introductory offer.
    in_trial: bool = False
    environment: str = "Production"
    #: Set when Apple has REVOKED the purchase — a refund, or a Family Sharing member losing access.
    #: A revoked transaction keeps its expiry date, so expiry alone says the subscription is fine.
    revoked_at: datetime | None = None
    #: Apple marks a transaction superseded when the user moves to another tier in the same group.
    #: The old one is still signed and still unexpired, so replaying it must not grant anything.
    is_upgraded: bool = False

    @property
    def is_active(self) -> bool:
        """Whether this purchase entitles anything, right now.

        Expiry alone was the check, and it is the weakest of the three. A refunded subscription
        keeps its `expiresDate` — Apple communicates the refund through `revocationDate` — so a
        user could refund and keep paid access until the period they no longer paid for ran out.
        `isUpgraded` is the same shape: the superseded transaction stays signed and unexpired.

        Every clock here is Apple's. A subscription with no expiry is a non-renewing purchase,
        which stays valid.
        """
        if self.revoked_at is not None or self.is_upgraded:
            return False
        return self.expires_at is None or self.expires_at > datetime.now(UTC)


@runtime_checkable
class SubscriptionVerifier(Protocol):
    async def verify(self, token: str) -> VerifiedSubscription: ...


class FakeVerifier(SubscriptionVerifier):
    """Dev and tests. Accepts a `product_id:transaction_id` string and refuses to run in prod.

    A verifier that can be told what to return must never be reachable from production — that is
    not a lint rule, it is the difference between a paywall and a suggestion.
    """

    def __init__(self, *, is_prod: bool = False, in_trial: bool = False) -> None:
        if is_prod:
            raise RuntimeError("FakeVerifier cannot run in prod — it grants whatever it is asked")
        self._in_trial = in_trial

    async def verify(self, token: str) -> VerifiedSubscription:
        if not token or ":" not in token:
            raise VerificationError("malformed token")
        product_id, _, transaction_id = token.partition(":")
        return VerifiedSubscription(
            product_id=product_id,
            original_transaction_id=transaction_id or "fake-txn",
            in_trial=self._in_trial,
            environment="Sandbox",
        )


class AppleVerifier(SubscriptionVerifier):
    """Real StoreKit verification through Apple's own library.

    Imported lazily so the dependency is only needed where it is used — a dev box running the fake
    verifier should not have to install Apple's certificate tooling to start the server.
    """

    def __init__(
        self,
        *,
        bundle_id: str,
        app_apple_id: int | None,
        environment: str,
        root_certificates: list[bytes],
        enable_online_checks: bool = True,
    ) -> None:
        try:
            from appstoreserverlibrary.models.Environment import Environment
            from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier
        except ImportError as exc:  # pragma: no cover - depends on optional install
            raise RuntimeError(
                "app-store-server-library is required for real StoreKit verification"
            ) from exc

        if not root_certificates:
            # Without Apple's roots there is no chain to validate against, and a verifier that
            # validates nothing is worse than none: it looks like a control.
            raise RuntimeError("Apple root certificates are required; refusing to verify blindly")

        self._environment = (
            Environment.PRODUCTION if environment.lower() == "production" else Environment.SANDBOX
        )
        self._verifier = SignedDataVerifier(
            root_certificates,
            enable_online_checks,
            self._environment,
            bundle_id,
            app_apple_id,
        )
        self._bundle_id = bundle_id

    async def verify(self, token: str) -> VerifiedSubscription:
        try:
            payload = self._verifier.verify_and_decode_signed_transaction(token)
        except Exception as exc:
            log.warning("storekit verification failed: %s", type(exc).__name__)
            raise VerificationError("could not verify") from None

        # Apple's own library checks the chain, the bundle id and the environment. This is the
        # defence-in-depth re-check: a library upgrade that loosened one of those would otherwise
        # be silent.
        if getattr(payload, "bundleId", None) != self._bundle_id:
            raise VerificationError("could not verify")

        expires_ms = getattr(payload, "expiresDate", None)
        offer_type = getattr(payload, "offerType", None)
        revoked_ms = getattr(payload, "revocationDate", None)
        return VerifiedSubscription(
            product_id=str(getattr(payload, "productId", "")),
            original_transaction_id=str(getattr(payload, "originalTransactionId", "")),
            expires_at=(datetime.fromtimestamp(expires_ms / 1000, tz=UTC) if expires_ms else None),
            # offerType 1 is Apple's introductory offer — the free trial. Trial state comes from
            # Apple because Apple owns eligibility; a local clock would hand a fresh trial to
            # anyone who reinstalls.
            in_trial=offer_type == 1,
            revoked_at=(datetime.fromtimestamp(revoked_ms / 1000, tz=UTC) if revoked_ms else None),
            # `isUpgraded` marks the transaction the user moved OFF. Apple's field is optional and
            # absent means False, so the default matters as much as the read.
            is_upgraded=bool(getattr(payload, "isUpgraded", False)),
            environment=self._environment.value,
        )


class PlanResolver:
    """Turns a verified purchase into the plan it grants.

    The whole point of `product_id` living on the plan: this is one dictionary lookup, so adding a
    tier or changing which product grants it is config. Nothing here knows what "pro" means.
    """

    def __init__(self, catalogue: PlanCatalogue, verifier: SubscriptionVerifier) -> None:
        self._catalogue = catalogue
        self._verifier = verifier

    async def resolve(self, token: str | None) -> tuple[str, VerifiedSubscription | None]:
        """Plan id for a subscription token. Returns the base plan for anything unverifiable.

        Every failure path lands on the base plan rather than raising: no token, bad token, expired,
        or a product we do not sell. A billing hiccup must degrade someone to the paywall, never
        into an error state where the app is unusable and they cannot even see how to fix it.
        """
        if not token:
            return FREE_PLAN_ID, None
        try:
            subscription = await self._verifier.verify(token)
        except VerificationError:
            return FREE_PLAN_ID, None

        if not subscription.is_active:
            # Covers expiry, refund/revocation and a superseded upgrade — all three are "this
            # receipt entitles nothing now", and all three used to read as active.
            log.info("subscription inactive for txn %s", subscription.original_transaction_id)
            return FREE_PLAN_ID, subscription

        plan = self._catalogue.for_product(subscription.product_id)
        if plan is None:
            # A verified purchase for something we do not sell. Genuinely worth logging: it means
            # a product exists in App Store Connect that no plan claims.
            log.warning("verified purchase for unknown product %r", subscription.product_id)
            return FREE_PLAN_ID, subscription

        # Apple says this is an introductory offer, so grant the trial plan rather than the paid
        # one — different budget, and it is Apple's answer to "are they still in trial", not ours.
        #
        # `trial_for` is asked for the trial belonging to THIS product. Taking the first plan that
        # happens to offer a trial works only while there is exactly one, and fails silently the
        # day a second product ships with its own - granting whichever tier sorts first.
        if subscription.in_trial:
            trial = self._catalogue.trial_for(plan.id)
            if trial is not None:
                return trial.id, subscription

        return plan.id, subscription


def resolve_plan_limits(catalogue: PlanCatalogue, plan_id: str) -> dict[str, Any]:
    """The limits a ledger and an agent need, from one place.

    Exists so no caller reconstructs a plan's numbers by hand — the bug that pattern produces is a
    budget enforced in one place and forgotten in another.
    """
    plan = catalogue.get(plan_id)
    return {
        "daily_budget": plan.daily_token_budget,
        "total_budget": plan.total_token_budget,
        "window_days": plan.budget_window_days,
        "max_output_tokens": plan.max_output_tokens,
        "max_iterations": plan.max_iterations_per_turn,
    }
