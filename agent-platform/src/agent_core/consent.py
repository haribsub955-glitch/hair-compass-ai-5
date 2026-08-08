"""Consent purposes as data — and the distinction that keeps them lawful.

**Read this before changing anything here.** The tempting design is "free users must agree to let us
use their data; paid users get a choice". That is invalid consent under Oman's PDPL and under GDPR,
and it is the specific pattern both regimes cite as the example of what not to do. Consent must be
**freely given**; conditioning a service on consent to processing that is not necessary for that
service voids it. A void consent is worse than no consent, because you relied on it.

The legitimate distinction is not free-versus-paid. It is **necessary-versus-optional**:

* **Necessary** — without this processing the feature cannot exist. Sending a question to a
  server-side model in order to receive an answer is not a favour the user grants; it *is* the
  feature. Declining means the feature is unavailable, which is honest and lawful. Legally this
  usually rests on contractual necessity rather than consent at all, but it is still disclosed and
  still recorded.
* **Optional** — model improvement, analytics, marketing. These must be genuinely optional **for
  everyone**, free and paid alike. They cannot be the price of admission for either.

Where the tiers *do* legitimately differ is in what they process at all. A free tier with no cloud
AI sends nothing, so there is nothing to consent to. A paid tier whose product is a cloud agent
necessarily transfers data to deliver it. The difference falls out of what each plan does, not out
of who is paying — which is why `min_plan` exists below and `required_for_free_users` does not.

Everything here is data, so adding a purpose or changing which plans it applies to is config.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict


class ConsentError(RuntimeError):
    """A consent configuration that would be unlawful or unenforceable. Fatal at load."""


class Purpose(BaseModel):
    """One thing you might process personal data for.

    Separate purposes are separately consentable — that is the whole point. Bundling "deliver the
    service" with "train our models" into one checkbox is how a lawful consent becomes an unlawful
    one, because the user cannot accept the first without the second.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    #: Shown to the user. Plain language, specific. "Improve our AI" is not a purpose; "use your
    #: anonymised questions to improve future answers" is.
    description: str = ""

    #: True when the feature genuinely cannot work without this processing. Declining makes the
    #: FEATURE unavailable — never the app, and never another feature.
    #:
    #: Marking something necessary that is not is exactly the abuse this whole module exists to
    #: prevent, so the honesty test is concrete: if you can imagine shipping the feature with this
    #: switched off, it is not necessary.
    necessary: bool = False

    #: Personal data leaves the country. Under PDPL this needs its own explicit consent, separate
    #: from the consent to process at all — so it is a separate flag, never folded into `necessary`.
    crosses_border: bool = False

    #: Which plans this purpose is even asked of. A free tier that never calls a server has nothing
    #: to ask about, so the difference between tiers falls out of what they DO.
    min_plan: str | None = None

    #: Bumped when the wording or the scope changes. A grant against an older version does not
    #: carry — see `IdentityStore.has_consent`.
    policy_version: str = "1"

    #: Optional purposes are always withdrawable. A necessary one is withdrawable too, but
    #: withdrawing it turns the feature off rather than doing nothing.
    @property
    def withdrawal_disables_feature(self) -> bool:
        return self.necessary


class PurposeRegistry:
    """Every purpose a deployment asks about."""

    __slots__ = ("_by_id",)

    def __init__(self, purposes: Iterable[Purpose]) -> None:
        self._by_id: dict[str, Purpose] = {}
        for purpose in purposes:
            if purpose.id in self._by_id:
                raise ConsentError(f"duplicate purpose {purpose.id!r}")
            if purpose.necessary and not purpose.description:
                # A purpose the user cannot decline without losing a feature must at least be
                # explained. An unexplained mandatory purpose is not informed consent.
                raise ConsentError(f"{purpose.id!r} is necessary but has no description")
            self._by_id[purpose.id] = purpose

    def __iter__(self):
        return iter(self._by_id.values())

    def __len__(self) -> int:
        return len(self._by_id)

    def get(self, purpose_id: str) -> Purpose | None:
        return self._by_id.get(purpose_id)

    def applicable_to(self, plan_id: str, *, meets) -> tuple[Purpose, ...]:
        """Purposes worth asking this plan about.

        `meets` is the plan catalogue's comparison, injected so this module never learns what a
        plan is. A free tier that does nothing remote is simply asked less — never asked
        *differently*.
        """
        return tuple(
            purpose
            for purpose in self._by_id.values()
            if purpose.min_plan is None or meets(plan_id, minimum=purpose.min_plan)
        )

    def required_for(self, plan_id: str, *, meets) -> tuple[Purpose, ...]:
        """The purposes this plan cannot use its features without."""
        return tuple(p for p in self.applicable_to(plan_id, meets=meets) if p.necessary)

    def optional_for(self, plan_id: str, *, meets) -> tuple[Purpose, ...]:
        """The genuinely optional ones. **Identical in kind for every plan** — a paid user and a
        free user are asked the same way and may decline the same way. Only the set differs, and
        only because their features differ."""
        return tuple(p for p in self.applicable_to(plan_id, meets=meets) if not p.necessary)

    @classmethod
    def from_config(cls, raw: Iterable[Mapping[str, Any]]) -> PurposeRegistry:
        return cls(Purpose.model_validate(dict(entry)) for entry in raw)


#: The default set, for a **subscription-only** product.
#:
#: Subscription-only is the strongest consent position available, and it is worth understanding
#: why: with no free tier, there is no tier where agreeing to share data could become the price of
#: entry. Everyone pays the same money for the same features, and every optional purpose is
#: declinable by everyone. The pay-or-okay problem cannot arise, because nothing is being traded
#: for consent.
#:
#: `min_plan` names the LOWEST plan the purpose applies to, and it is the taster rather than the
#: trial: a 3-day user has to be able to consent to the analysis, or the free period grants access
#: to a product they cannot lawfully be shown. It still matters for the lapsed state — someone
#: whose subscription ended is asked about nothing
#: they cannot use.
DEFAULT_PURPOSES = PurposeRegistry.from_config(
    [
        {
            "id": "agent-analysis",
            "description": (
                "Send the facts your app has already calculated to our AI service so it can "
                "explain them. Without this the AI features cannot run."
            ),
            "necessary": True,
            "crosses_border": True,
            # Only asked of plans that actually have cloud AI. A free user is never shown this
            # because nothing of theirs is ever sent.
            "min_plan": "taster",
            "policy_version": "2026-07-31",
        },
        {
            "id": "memory-sync",
            "description": (
                "Keep your saved notes on our servers so the assistant remembers them across "
                "your devices and can work while your phone is asleep."
            ),
            # Optional: the assistant works without it, reading memories from the device instead.
            "necessary": False,
            "crosses_border": True,
            # Trial users get the same features, so they face the same questions — a trial that
            # asked less would mean the paywall silently changed what was being processed.
            "min_plan": "taster",
            "policy_version": "2026-07-31",
        },
        {
            # A photograph of someone's scalp is health data and biometric-adjacent, and sending it
            # to a provider outside Oman is a materially different act from sending derived
            # numbers. `agent-analysis` does not cover it and must not be stretched to.
            "id": "photo-analysis",
            "description": (
                "Send a photo you choose to the analysis service so it can comment on it. "
                "The photo is deleted as soon as the answer is ready."
            ),
            "necessary": False,
            "crosses_border": True,
            "min_plan": "taster",
        },
        {
            "id": "model-improvement",
            "description": (
                "Let us review anonymised questions and answers to improve future responses."
            ),
            # Optional for EVERY plan. This is the one that must never become the price of
            # admission — for free users or paid ones.
            "necessary": False,
            "crosses_border": True,
            "min_plan": None,
            "policy_version": "2026-07-31",
        },
    ]
)
