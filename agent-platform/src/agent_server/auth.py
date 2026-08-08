"""Who the server thinks it is acting for.

`VerifyingPrincipalSource` is the one that ships. `DevPrincipalSource` derives the same stable id
but grants a configured entitlement, which is fine on a LAN and is the whole paywall on the
internet — so it refuses to construct itself in prod.

The `PrincipalSource` seam exists so that swapping dev identity for real StoreKit/Play verification
touches one file (CLAUDE.md §AR). Everything downstream takes a `Principal` and never asks where it
came from.

`DevPrincipalSource` is for LAN testing only and refuses to construct itself in prod. It derives a
stable `principal_id` by HMAC-ing the installation id with the server secret — stable across
restarts, not guessable by a client, and requiring no database. It grants whatever entitlement the
config says, which is the part that must never ship.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from datetime import UTC, datetime, timedelta
from typing import Protocol, runtime_checkable

from agent_core.contracts import Entitlement, Principal
from agent_core.plans import FREE_PLAN_ID, PlanCatalogue

log = logging.getLogger("agent_server.auth")


def _derive(secret: bytes, app_id: str, installation_id: str) -> tuple[str, str]:
    """Stable, non-guessable ids from an installation. One implementation, two callers.

    HMAC rather than a plain hash so a client cannot compute another installation's principal id
    from a guessed installation id — it would need the server secret.
    """
    digest = hmac.new(secret, f"{app_id}:{installation_id}".encode(), hashlib.sha256).hexdigest()
    return f"p_{digest[:24]}", f"d_{digest[24:48]}"


@runtime_checkable
class PrincipalSource(Protocol):
    async def principal_for(
        self, *, app_id: str, installation_id: str, subscription_token: str
    ) -> Principal: ...


class DevPrincipalSource(PrincipalSource):
    """Dev-only identity. Trusts the installation id and grants a configured entitlement."""

    def __init__(self, *, secret: str, entitlement: Entitlement, is_prod: bool) -> None:
        if is_prod:
            raise RuntimeError(
                "DevPrincipalSource cannot run in prod — it grants entitlement without verifying "
                "a store receipt"
            )
        if not secret:
            raise RuntimeError("DevPrincipalSource needs a secret to derive stable principal ids")
        self._secret = secret.encode()
        self._entitlement = entitlement
        self._plan_id = "pro_monthly" if entitlement is Entitlement.PRO else FREE_PLAN_ID

    async def principal_for(
        self, *, app_id: str, installation_id: str, subscription_token: str
    ) -> Principal:
        # The client picks its installation id, so it could pick someone else's — irrelevant in dev,
        # and the reason this class refuses to run in prod. Real verification binds the principal to
        # a store transaction the client cannot forge.
        principal_id, data_subject_id = _derive(self._secret, app_id, installation_id)
        return Principal(
            app_id=app_id,
            principal_id=principal_id,
            installation_id=installation_id,
            data_subject_id=data_subject_id,
            entitlement=self._entitlement,
            # A REAL plan id, not the enum's value. "pro" is not in the catalogue, so it degraded
            # to the free plan and made every dev turn look unentitled — the same lossy bridge
            # that truncated responses to 512 tokens, showing up a second way.
            plan_id=self._plan_id,
        )


class VerifyingPrincipalSource(PrincipalSource):
    """Identity plus a verified subscription. The production source.

    **This is the piece that was missing.** `PlanResolver` and `AppleVerifier` were written, tested
    and then wired to nothing — `DevPrincipalSource` was still the only source, so every request got
    its configured entitlement and the paywall existed only in the tests. Verification that is not
    on the request path is documentation.

    What it does, in order: derive the ids (identity does not depend on paying), resolve the plan
    from the store token, then persist the plan so the ledger's `plan_started_at` window and the
    receipt's uniqueness constraint both have something to work with.

    Failures degrade to the base plan and never raise. Someone whose card just failed must land on
    the paywall, not on a 500 with no way to fix it.
    """

    def __init__(
        self,
        *,
        secret: str,
        plans,
        catalogue: PlanCatalogue,
        identity=None,
        audit=None,
        testers: dict[str, str] | None = None,
    ) -> None:
        if not secret:
            raise RuntimeError("VerifyingPrincipalSource needs a secret to derive principal ids")
        self._secret = secret.encode()
        self._plans = plans
        self._catalogue = catalogue
        self._identity = identity
        self._audit = audit
        #: `installation_id -> plan_id`, for named testers with no purchase. Empty in production.
        self._testers = testers or {}

    async def principal_for(
        self, *, app_id: str, installation_id: str, subscription_token: str
    ) -> Principal:
        principal_id, data_subject_id = _derive(self._secret, app_id, installation_id)
        plan_id, subscription = await self._plans.resolve(subscription_token or None)
        if subscription is None:
            granted = self._testers.get(installation_id)
            if granted:
                # A named tester. Deliberately checked BEFORE the taster so a tester is not quietly
                # cut off after three days, and audited on every session rather than once — the
                # record of who was given free access, and for how long, is the point.
                plan_id = granted
                if self._audit is not None:
                    self._audit.record(
                        "subscription.tester_grant",
                        principal_id=principal_id,
                        device_id=installation_id,
                        detail={"plan": plan_id},
                    )
            else:
                # No usable receipt. Before falling through to the paywall, check whether this
                # person is still inside the free-for-3-days window.
                plan_id = await self._taster_or(plan_id, principal_id)

        if self._identity is not None:
            # Register BEFORE set_plan: the UPDATE needs a row, and `SELECT ... FOR UPDATE` in the
            # ledger locks nothing at all if the principal does not exist.
            await self._identity.register(
                Principal(
                    app_id=app_id,
                    principal_id=principal_id,
                    installation_id=installation_id,
                    data_subject_id=data_subject_id,
                    entitlement=_as_entitlement(plan_id),
                )
            )
            claimed = await self._identity.set_plan(
                principal_id,
                plan_id=plan_id,
                subscription_txn_id=(
                    subscription.original_transaction_id if subscription else None
                ),
            )
            if not claimed:
                # The receipt belongs to another principal. Fall back to the base plan rather than
                # refusing the request: the person may simply be on a shared device, and a hard
                # error here would lock them out of an app they can still use unpaid.
                log.warning("subscription claim refused for %s", principal_id)
                plan_id = FREE_PLAN_ID

        if self._audit is not None:
            self._audit.record(
                "subscription.verified" if subscription else "subscription.rejected",
                principal_id=principal_id,
                device_id=installation_id,
                detail={
                    "plan": plan_id,
                    "presented": bool(subscription_token),
                    "in_trial": bool(subscription and subscription.in_trial),
                },
            )

        return Principal(
            app_id=app_id,
            principal_id=principal_id,
            installation_id=installation_id,
            data_subject_id=data_subject_id,
            entitlement=_as_entitlement(plan_id),
            plan_id=plan_id,
        )

    async def _taster_or(self, fallback: str, principal_id: str) -> str:
        """The taster plan if this principal is still eligible, else `fallback`.

        Two conditions, and the second is the one that is easy to forget: they must be inside the
        window AND must never have subscribed. Without the second, a lapsed subscriber whose card
        failed would be handed the introductory freebie again on every session — and, because the
        window is measured from when the principal was CREATED, they would keep getting it forever
        once their account was older than three days had it been measured the other way round.

        Reaching here with no store at all (dev, no database) grants nothing: a taster that cannot
        be timed is a taster that never expires.
        """
        taster = self._catalogue.taster
        if taster is None or self._identity is None:
            return fallback

        created_at, has_subscribed = await self._identity.standing(principal_id)
        if created_at is None:
            # First contact. The row is written a moment later by `register`, and `created_at`
            # defaults to now, so they are inside the window by definition.
            return taster.id
        if has_subscribed:
            return fallback
        age = datetime.now(UTC) - created_at
        return taster.id if age <= timedelta(days=taster.available_for_days) else fallback


def _as_entitlement(plan_id: str) -> Entitlement:
    """Bridge a plan id onto the two-case enum the tool registry still gates on.

    A temporary seam, and marked as one. `Entitlement` is what `plans.py` replaces — a plan is a row
    so a new tier is config, while this enum makes it a code change. Until the tool registry gates
    on `rank`, anything that is not the base plan reads as PRO, which is right for a catalogue whose
    every paid tier currently unlocks the same tools and wrong the day one does not.
    """
    return Entitlement.FREE if plan_id == FREE_PLAN_ID else Entitlement.PRO
