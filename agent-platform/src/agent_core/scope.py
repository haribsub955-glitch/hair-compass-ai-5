"""The scope gate — refuse off-product questions before spending a token on them.

This runs **before** the ledger reservation and before the first model call, so an off-topic message
costs nothing. That is the whole point: a subscription agent that cheerfully writes Python, plans
holidays and translates menus is paying a provider to be a general assistant, and the bill arrives
regardless of whether the user ever comes back.

**It is a cost control, not a safety control.** That distinction decides how it fails:

* A safety control fails **closed** — when unsure, refuse, because the cost of a wrong answer is
  high.
* A cost control fails **open** — when unsure, allow, because the cost of wrongly refusing a real
  user's real question is a broken product, and the cost of answering one stray question is a
  fraction of a cent.

So this blocks only on a **positive** signal of another domain, never on the absence of a domain
word. "How am I doing?" contains nothing about hair and is exactly what a user asks. A gate that
demanded the word "hair" would reject the most common question in the app.

Everything the model actually *says* is still judged afterwards by the safety layer, which does fail
closed. This gate only decides whether it was worth asking at all.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ScopeVerdict:
    in_scope: bool
    #: Shown to the user when refused, so keep it kind and specific.
    reason: str = ""


class ScopePolicy:
    """Per-app scope rules. Like everything else app-specific, this lives in a pack.

    `domain` and `self_reference` are the two ways a message can be recognised as ours;
    `off_domain` is the only way it can be rejected. All three are compiled patterns so a pack can
    express whatever it needs without this module knowing the subject.
    """

    __slots__ = ("domain", "off_domain", "refusal", "self_reference")

    def __init__(
        self,
        *,
        domain: re.Pattern[str],
        self_reference: re.Pattern[str],
        off_domain: re.Pattern[str],
        refusal: str,
    ) -> None:
        self.domain = domain
        self.self_reference = self_reference
        self.off_domain = off_domain
        self.refusal = refusal


def check(text: str, *, policy: ScopePolicy) -> ScopeVerdict:
    """Decide whether a message is worth sending to the model.

    Order matters and is deliberately asymmetric. A message showing *any* sign of belonging here —
    a domain word, or the user talking about themselves — is allowed even if it also trips an
    off-domain pattern, because mixed messages ("I've been coding late, is stress making me shed?")
    are real and the domain half is the part that matters.
    """
    stripped = text.strip()
    if not stripped:
        # Nothing to answer, nothing to charge for.
        return ScopeVerdict(False, policy.refusal)

    if policy.domain.search(stripped) or policy.self_reference.search(stripped):
        return ScopeVerdict(True)

    if policy.off_domain.search(stripped):
        return ScopeVerdict(False, policy.refusal)

    # Neither signal. Fail open — see the module docstring.
    return ScopeVerdict(True)
