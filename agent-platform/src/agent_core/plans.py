"""Subscription plans as DATA, not as an enum.

`Entitlement` was a two-case enum — `FREE` and `PRO` — with a hardcoded ordering dict beside it.
That shape decides your pricing for you: adding a tier means editing the enum, the ordering, every
comparison, the client, and shipping an app update through review to sell something new. Changing a
limit means a deploy.

So a plan is a **row**, not a case. Adding "plus", running a promotion, raising a cap, or gating a
feature is a config change the server picks up — no code, no App Store review, no client update.
The client is told what it has; it never decides.

**Ordering is `rank`, never alphabetical and never enum-declaration order.** A comparison like
"does this plan meet the minimum for that tool" has to work for tiers that did not exist when the
comparison was written, which is the entire point.

Everything here is pure data with no I/O, so a plan set can come from a table, a pack file, or a
test fixture without this module knowing which.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

#: The plan every unauthenticated, unrecognised, or LAPSED principal falls back to. Never `None` —
#: a missing plan must degrade to the least-privileged one, not to "no limits".
#:
#: The name is historical and slightly misleading in a subscription-only product: there, this plan
#: is not a free *tier*, it is the "no active subscription" state — someone whose trial ended or
#: whose card failed. It still has to exist, because a lapsed user must land somewhere defined
#: rather than nowhere.
FREE_PLAN_ID = "free"

#: Sending a photo to the model. A feature id rather than a hardcoded plan check, so which tiers
#: include it is a config decision — the whole reason plans are data.
PHOTO_FEATURE = "photo_analysis"


class Plan(BaseModel):
    """One subscription tier.

    Limits live here rather than in scattered config because they are the product: what a plan
    *is*, commercially, is the set of numbers below.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    #: Higher wins. Gaps are deliberate — leaving room between tiers means inserting one later
    #: does not renumber the others, and renumbering is how a `min_plan` check silently inverts.
    rank: int

    #: Display only. The real price lives in App Store Connect / Play Console; duplicating it here
    #: would create two sources of truth and one of them would be wrong.
    display_name: str = ""
    #: The store product identifier this plan is granted by. The join between a verified purchase
    #: and what it unlocks.
    product_id: str = ""

    # --- the limits that cost money -------------------------------------------------------
    #: Tokens per principal per day. This is the business model, not a safety valve: uncapped AI
    #: on a flat subscription is how a product with good retention loses money per user.
    daily_token_budget: int = Field(default=0, ge=0)

    #: How many days the recurring budget above covers. `1` is a daily cap; `7` is weekly.
    #:
    #: Weekly usually fits a tracking app better than daily. People use these in BURSTS — after a
    #: wash, when a lab result arrives, after a bad week — and a daily ration punishes exactly that
    #: pattern while a weekly one absorbs it.
    #:
    #: The trade, stated because it is real: a window longer than a day cannot be enforced by the
    #: single atomic statement a per-day row allows, so it is checked read-then-write. Overshooting
    #: a weekly cap by one turn at a race boundary costs pennies and the TOTAL cap below is what
    #: actually bounds the money. Spend the atomicity where the exposure is.
    budget_window_days: int = Field(default=1, ge=1, le=31)

    #: Tokens for the WHOLE plan period, across all days. `0` means no lifetime ceiling.
    #:
    #: A daily cap alone does not bound a long trial: 2 turns/day over 90 days is still 180 turns.
    #: This is what actually caps exposure, and it is better product design too — people explore
    #: heavily in week one and taper, so an allowance they spend however they like beats a daily
    #: ration that punishes the exploration you want.
    #:
    #: Only meaningful on a time-limited plan. A paid subscription renews, so its lifetime is not a
    #: thing to budget.
    total_token_budget: int = Field(default=0, ge=0)
    max_output_tokens: int = Field(default=1024, gt=0)
    #: Model calls per turn. Caps a runaway loop's cost, separately from the daily budget.
    max_iterations_per_turn: int = Field(default=6, gt=0)

    # --- what the plan unlocks ------------------------------------------------------------
    #: `None` means "everything the pack offers". A set narrows it. Never widens — the pack's
    #: catalogue is still the outer bound.
    tools: frozenset[str] | None = None
    #: Cognitive strategies this plan may reach. `orchestrator_workers` and friends fan out to
    #: several model calls, so strategy tier IS a price tier.
    max_strategy: str = "direct"
    #: Free-form capability flags — "photo_analysis", "weekly_report", whatever a pack invents.
    features: frozenset[str] = frozenset()

    #: Length of the introductory free period, for display and for server-side sanity checks.
    #:
    #: **Eligibility is Apple's or Google's to decide, never ours.** StoreKit introductory offers
    #: are tracked per Apple ID and survive reinstall; a homegrown trial clock keyed to an
    #: installation grants a fresh month to anyone who deletes and reinstalls the app. So this
    #: number exists to render "1 month free" and to reject an obviously wrong claim — it is not
    #: the source of truth for whether a given person is still in trial.
    #:
    #: The trial is also the LAWFUL shape of "let them try it before deciding". A time-limited
    #: taste of the paid tier involves no consent bargain at all: at the end the user pays or drops
    #: to a free tier that still does everything deterministic. "Consent to data use or pay" is the
    #: shape to avoid — see agent_core/consent.py.
    trial_days: int = Field(default=0, ge=0)

    #: Which paid plans this trial leads to. Only meaningful on a plan with `trial_days`.
    #:
    #: A SET, because one Apple introductory offer covers a whole subscription group: the 14-day
    #: trial converts to monthly by default and the same person may switch to yearly, and both are
    #: the same offer as far as Apple is concerned. A single destination could not express that.
    trial_of: frozenset[str] = frozenset()

    #: Apple subscription group. Plans sharing one are alternatives a user switches BETWEEN
    #: (monthly/yearly), not tiers they upgrade THROUGH — Apple handles the crossgrade, and the
    #: server sees a new product id under the same original transaction id.
    subscription_group: str = ""

    #: Granted with no receipt at all, for `available_for_days` after the principal first appears.
    #:
    #: This is the "3 days free" period, and it is OURS — not Apple's. StoreKit allows exactly one
    #: introductory offer per subscription group per Apple ID, and the 14-day trial is it. So this
    #: runs on the server's clock, before any payment method exists.
    #:
    #: **It is farmable and that is priced in.** The principal id derives from the installation id,
    #: which changes on reinstall, so deleting and reinstalling yields a fresh taster. There is
    #: nothing stable to key it to before a receipt exists — an Apple ID is exactly what the app
    #: does not have yet. The mitigation is the budget, not a clever identifier: keep the total
    #: small enough that farming it is not worth the effort.
    granted_without_receipt: bool = False
    #: How long a `granted_without_receipt` plan lasts, measured from the principal's creation.
    available_for_days: int = Field(default=0, ge=0)

    @property
    def offers_trial(self) -> bool:
        return self.trial_days > 0

    @property
    def has_total_cap(self) -> bool:
        return self.total_token_budget > 0

    def approximate_turns(self, *, tokens_per_turn: int = 18_000, total: bool = True) -> int:
        """Roughly how many turns a budget buys. For copy and for sanity-checking a config.

        18k is a measured-ish default: 2-3 model calls at roughly 15k in / 3k out. It is an
        estimate and is documented as one — the ledger meters real tokens, never this.
        """
        budget = (self.total_token_budget if total else 0) or self.daily_token_budget
        return budget // tokens_per_turn if budget else 0

    def allows_feature(self, feature: str) -> bool:
        return feature in self.features

    def allows_tool(self, tool: str) -> bool:
        return self.tools is None or tool in self.tools

    @property
    def is_paid(self) -> bool:
        return self.daily_token_budget > 0


class PlanCatalogue:
    """Every plan this deployment knows about.

    Built from config at startup and treated as read-only. A plan that vanishes between deploys
    must not strand the principals holding it, so `get` falls back to the base plan rather than
    raising — a user whose tier was renamed should lose privileges, never lose access.

    `subscription_only` says whether the base plan is a real free tier or merely the lapsed state.
    It changes nothing about how limits are enforced; it exists so the client can render the right
    paywall and so `has_free_tier` is a question with an answer rather than an inference from
    whether the base plan happens to have a budget.
    """

    __slots__ = ("_by_id", "_by_product", "subscription_only")

    def __init__(self, plans: Iterable[Plan], *, subscription_only: bool = False) -> None:
        self.subscription_only = subscription_only
        self._by_id: dict[str, Plan] = {}
        self._by_product: dict[str, Plan] = {}
        for plan in plans:
            if plan.id in self._by_id:
                raise ValueError(f"duplicate plan id {plan.id!r}")
            self._by_id[plan.id] = plan
            if plan.product_id:
                if plan.product_id in self._by_product:
                    raise ValueError(f"two plans claim product {plan.product_id!r}")
                self._by_product[plan.product_id] = plan
        if FREE_PLAN_ID not in self._by_id:
            raise ValueError(f"a catalogue must define a {FREE_PLAN_ID!r} plan to fall back to")

    def __iter__(self):
        return iter(sorted(self._by_id.values(), key=lambda p: p.rank))

    def __len__(self) -> int:
        return len(self._by_id)

    @property
    def free(self) -> Plan:
        """The base plan: a genuine free tier, or the lapsed state in a subscription-only app."""
        return self._by_id[FREE_PLAN_ID]

    @property
    def has_free_tier(self) -> bool:
        """Is there anything a non-subscriber can actually do?

        In a subscription-only product this is False, and that is the strongest consent position
        available: with no free tier there is no tier where agreeing to share data could become the
        price of entry. Every user pays, and every user decides on optional purposes separately.
        """
        return not self.subscription_only

    def get(self, plan_id: str | None) -> Plan:
        """Resolve a plan id. Unknown or missing degrades to free, deliberately."""
        if not plan_id:
            return self.free
        return self._by_id.get(plan_id, self.free)

    def for_product(self, product_id: str) -> Plan | None:
        """Which plan a verified store purchase grants. `None` means we do not sell that product —
        which is a real case worth surfacing rather than silently granting something."""
        return self._by_product.get(product_id)

    def trial_for(self, plan_id: str) -> Plan | None:
        """The trial plan that leads to `plan_id`.

        `trial_of` on the trial names its destinations, so a catalogue with two paid products each
        having their own introductory tier resolves correctly, and one trial can serve every plan
        in a subscription group. Falling back to "the first plan that offers a trial" works only
        while there is exactly one and then fails silently - granting whichever tier happens to
        sort first, which surfaces as a support ticket about the wrong allowance, not as an error.

        The unnamed fallback is kept for a single-trial catalogue, where the answer is unambiguous.
        """
        named = [p for p in self._by_id.values() if p.offers_trial and plan_id in p.trial_of]
        if named:
            return named[0]
        unnamed = [p for p in self._by_id.values() if p.offers_trial and not p.trial_of]
        return unnamed[0] if len(unnamed) == 1 else None

    @property
    def taster(self) -> Plan | None:
        """The plan granted with no receipt, if this deployment offers one.

        Returns `None` rather than raising, so a deployment that sells straight from the paywall
        needs no special case anywhere — the caller simply falls through to the base plan.
        """
        return next((p for p in self._by_id.values() if p.granted_without_receipt), None)

    def group(self, name: str) -> tuple[Plan, ...]:
        """Every plan in one Apple subscription group, cheapest first.

        What the paywall renders: the alternatives a user picks between, in the order they should
        be shown.
        """
        members = [p for p in self._by_id.values() if p.subscription_group == name and name]
        return tuple(sorted(members, key=lambda p: p.rank))

    def meets(self, held: str | None, *, minimum: str) -> bool:
        """Does the held plan reach the required tier? Compares `rank`, so a tier inserted later
        sorts correctly against checks written before it existed."""
        return self.get(held).rank >= self.get(minimum).rank

    @classmethod
    def from_config(
        cls, raw: Iterable[Mapping[str, Any]], *, subscription_only: bool = False
    ) -> PlanCatalogue:
        """Build from plain dicts — a pack file, a database rows result, a test fixture."""
        return cls(
            (Plan.model_validate(dict(entry)) for entry in raw),
            subscription_only=subscription_only,
        )


#: The default catalogue: **subscription-only, with a trial.**
#:
#: This is the simplest lawful shape there is. With no free tier, there is no tier where consenting
#: to share data could become the price of admission — every user pays, and the optional purposes
#: stay optional for all of them. Nothing to argue about with a regulator.
#:
#: Three plans: lapsed, trial, pro. The trial is a real plan with its own budget rather than a
#: flag, because a trial that costs money per turn is a different commercial object from one that
#: does not.
#: Roughly what one turn costs, in tokens. 2-3 model calls at ~15k in / 3k out. Every budget below
#: is expressed as a turn count first and converted here, because "10 turns a week" is a product
#: decision anyone can argue with and "180,000 tokens" is not.
TOKENS_PER_TURN = 18_000

DEFAULT_PLANS = PlanCatalogue.from_config(
    [
        {
            "id": FREE_PLAN_ID,
            "rank": 0,
            "display_name": "No subscription",
            # Not a free tier — the lapsed state. Taster expired, trial ended, card failed, never
            # subscribed. Everything is zero and the client shows the paywall.
            "daily_token_budget": 0,
            "max_output_tokens": 512,
            "max_iterations_per_turn": 1,
            "tools": [],
            "max_strategy": "direct",
            "features": [],
        },
        {
            # THREE DAYS, NO PAYMENT METHOD. Ours, not Apple's.
            #
            # StoreKit allows one introductory offer per subscription group per Apple ID, and the
            # 14-day trial below is it — so this cannot be a second Apple free period. It runs on
            # the server's clock, before the user has committed anything at all.
            #
            # Its whole job is to let someone answer "is this for me?" without reaching for a card.
            # That means it must feel like the real product, not a demo: full tools, full features,
            # just fewer turns.
            #
            # **Deliberately small, because it is farmable.** The principal id derives from the
            # installation id, which changes on reinstall, and before a receipt exists there is
            # nothing stable to key it to. So the defence is the size of the prize: 5 turns is
            # about $0.45 of API spend, which is not worth anyone's reinstall cycle, and the rate
            # limiter bounds how fast it could be attempted anyway.
            "id": "taster",
            "rank": 10,
            "display_name": "Free for 3 days",
            "granted_without_receipt": True,
            "available_for_days": 3,
            # 2 turns a day, 5 across the three days — so it can be spent in one sitting on day
            # one, which is what a curious new user actually does.
            "daily_token_budget": 2 * TOKENS_PER_TURN,
            "total_token_budget": 5 * TOKENS_PER_TURN,
            "max_output_tokens": 2048,
            "max_iterations_per_turn": 6,
            "tools": None,
            "max_strategy": "self_review",
            # NO photo_analysis. Images are by far the most expensive thing a turn can
            # carry, and this is the only tier with no payment method behind it — the taster
            # shows the product works, and photos are a reason to subscribe rather than a
            # free sample.
            "features": ["deep_analysis", "weekly_report"],
        },
        {
            # FOURTEEN DAYS, APPLE'S INTRODUCTORY OFFER, converting to monthly automatically.
            #
            # A separate plan rather than a flag on the paid tier, because a trial turn costs real
            # money the moment it runs and therefore needs its own budget. Apple owns eligibility
            # (offerType == 1), which is what makes this one reinstall-proof where the taster is
            # not: introductory offers are tracked per Apple ID.
            #
            # The card is already on file here, so the constraint is conversion rather than abuse.
            # More generous than the taster by design.
            #
            # **The honest limit, stated because it does not go away:** the app's own efficacy gate
            # is 24 weeks. Nobody will see a treatment outcome inside 17 days. What a trial this
            # length can show is the tracking loop — shed trend, scalp direction, a photo pair, a
            # lab flag — which is the daily experience someone is actually subscribing to. The
            # outcome question is answered later, as a subscriber. Tune from conversion data.
            "id": "trial",
            "rank": 50,
            "display_name": "14-day free trial",
            "trial_days": 14,
            # One offer, both destinations: converts to monthly and the same person may switch to
            # yearly. Apple treats them as one group, so this must too.
            "trial_of": ["pro_monthly", "pro_yearly"],
            # ~14 turns a week. Weekly rather than daily because a tracking app is used in bursts
            # — after a wash, when a lab result lands — and a daily ration fights exactly the
            # exploration a trial is supposed to encourage.
            "daily_token_budget": 14 * TOKENS_PER_TURN,
            "budget_window_days": 7,
            # ~19 turns across the whole 14 days. THIS is the number that bounds the cost: worst
            # case about $1.70 per trial user, so a thousand trials is $1,700 before revenue.
            "total_token_budget": 19 * TOKENS_PER_TURN,
            "max_output_tokens": 2048,
            "max_iterations_per_turn": 6,
            "tools": None,
            "max_strategy": "self_review",
            "features": ["deep_analysis", "photo_analysis", "weekly_report"],
        },
        {
            # What the trial converts to, and the default the paywall selects.
            "id": "pro_monthly",
            "rank": 100,
            "display_name": "Monthly",
            "product_id": "harib.haircompass.pro.monthly",
            "subscription_group": "pro",
            # ~11 turns/day. Sized from real cost: a heavy month lands near $2.70 against ~$5.94
            # net after Apple's 15% Small Business rate on a $6.99 subscription.
            "daily_token_budget": 11 * TOKENS_PER_TURN,
            "max_output_tokens": 2048,
            "max_iterations_per_turn": 6,
            "tools": None,
            "max_strategy": "self_review",
            "features": ["deep_analysis", "photo_analysis", "weekly_report"],
        },
        {
            # The same product, paid annually. **Identical limits, deliberately.**
            #
            # A yearly plan that also bought more capability would be two changes at once, and the
            # one people actually want is the discount. Charging less per month for the same thing
            # is an honest offer; metering it differently would mean a monthly subscriber is being
            # short-changed for paying in smaller pieces.
            #
            # Same subscription group as monthly, so switching is an Apple crossgrade: the server
            # sees a new product id under the SAME original transaction id, which is why the
            # uniqueness constraint uses that id and not the product.
            "id": "pro_yearly",
            "rank": 110,
            "display_name": "Yearly",
            "product_id": "harib.haircompass.pro.yearly",
            "subscription_group": "pro",
            "daily_token_budget": 11 * TOKENS_PER_TURN,
            "max_output_tokens": 2048,
            "max_iterations_per_turn": 6,
            "tools": None,
            "max_strategy": "self_review",
            "features": ["deep_analysis", "photo_analysis", "weekly_report"],
        },
    ],
    subscription_only=True,
)
