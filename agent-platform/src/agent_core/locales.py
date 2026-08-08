"""Language as data, served from the server — including the safety rules.

The easy half is obvious: prompts and user-facing strings per locale, delivered by the server so
adding Arabic does not need an App Store release.

**The half that is easy to miss and expensive to discover: the safety layer is language-specific.**
Every deterministic text rule protecting this product is an English regex. Ask the model a question
in Arabic, get an Arabic answer, and `personal_diagnosis` matches nothing — the guard silently
stops existing while every test stays green, because every test is in English.

That is not a localisation task. It is a safety regression that ships the day a second language
does. So a locale carries its own rules, and a locale without them is refused rather than served
unguarded.

Nothing here knows what language it is holding. A locale is a bundle of strings and patterns; the
core stays blind to which one is active, so a third and fourth language are rows, not branches.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

DEFAULT_LOCALE = "en"

#: Scripts written right-to-left. The client needs this to lay out an answer correctly, and it is
#: server-supplied so adding Hebrew or Urdu is a row rather than a client update.
RTL_LANGUAGES = frozenset({"ar", "he", "fa", "ur"})


class LocaleError(RuntimeError):
    """A locale that cannot be served safely. Always fatal at load — never degrade to serving a
    language whose guards are missing."""


class LocalePack(BaseModel):
    """Everything language-specific for one locale."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    #: BCP-47-ish tag: "en", "ar", "ar-OM".
    code: str
    display_name: str = ""

    #: Appended to the system prompt. Not a translation of it — an instruction about which language
    #: to answer in. Translating the whole prompt per locale doubles the surface that has to stay
    #: in step with the safety rules.
    instruction: str = ""

    #: User-facing strings the SERVER produces: scope refusals, quota messages, fallbacks. The
    #: client has its own catalogue for its own strings; these are the ones only the server knows.
    strings: dict[str, str] = Field(default_factory=dict)

    #: Deny patterns for THIS language. Same intent as the English rules, expressed natively —
    #: never machine-translated, because a mistranslated guard reads as a working one.
    text_rules: dict[str, str] = Field(default_factory=dict)
    #: Stand-down patterns, keyed to the rule they soften. Debunking a myth must survive in every
    #: language, not just English.
    text_rule_exceptions: dict[str, str] = Field(default_factory=dict)

    #: Domain and off-domain vocabulary for the scope gate, in this language.
    scope_domain: str = ""
    scope_self_reference: str = ""
    scope_off_domain: str = ""

    @property
    def is_rtl(self) -> bool:
        return self.code.split("-")[0].lower() in RTL_LANGUAGES

    def string(self, key: str, fallback: str = "") -> str:
        return self.strings.get(key, fallback)

    def compiled_rules(self) -> dict[str, tuple[re.Pattern[str], re.Pattern[str] | None]]:
        """Compile this locale's rules, pairing each with its stand-down pattern.

        Compiled once at load so a malformed pattern fails at startup rather than mid-turn — a
        regex error inside a safety check would otherwise surface as an exception on a user's
        question, and the safe response to that is not obvious at 3am.
        """
        compiled: dict[str, tuple[re.Pattern[str], re.Pattern[str] | None]] = {}
        for name, pattern in self.text_rules.items():
            try:
                fire = re.compile(pattern, re.IGNORECASE)
            except re.error as exc:
                raise LocaleError(f"{self.code}/{name}: bad pattern — {exc}") from None
            unless_source = self.text_rule_exceptions.get(name)
            unless: re.Pattern[str] | None = None
            if unless_source:
                try:
                    unless = re.compile(unless_source, re.IGNORECASE)
                except re.error as exc:
                    raise LocaleError(f"{self.code}/{name}: bad exception — {exc}") from None
            compiled[name] = (fire, unless)
        return compiled


class LocaleCatalogue:
    """Every locale a deployment can serve.

    `resolve` degrades along the language chain — "ar-OM" to "ar" to the default — rather than
    failing, because a client asking for a regional variant should get the language, not English.
    """

    __slots__ = ("_default", "_packs")

    def __init__(self, packs: Iterable[LocalePack], *, required_rules: frozenset[str]) -> None:
        self._packs: dict[str, LocalePack] = {}
        for pack in packs:
            code = pack.code.lower()
            if code in self._packs:
                raise LocaleError(f"duplicate locale {code!r}")
            # THE check that stops a language shipping without its guards. A locale missing a rule
            # the product depends on is refused at load, loudly, rather than serving unguarded
            # answers that every English test says are fine.
            missing = required_rules - set(pack.text_rules)
            if missing:
                raise LocaleError(
                    f"locale {code!r} is missing safety rules: {', '.join(sorted(missing))}. "
                    "A language served without its own rules has no safety layer at all."
                )
            pack.compiled_rules()  # fail fast on a bad pattern
            self._packs[code] = pack

        if DEFAULT_LOCALE not in self._packs:
            raise LocaleError(f"a catalogue must define {DEFAULT_LOCALE!r}")
        self._default = self._packs[DEFAULT_LOCALE]

    def __iter__(self):
        return iter(self._packs.values())

    def __len__(self) -> int:
        return len(self._packs)

    @property
    def default(self) -> LocalePack:
        return self._default

    @property
    def codes(self) -> tuple[str, ...]:
        return tuple(sorted(self._packs))

    def resolve(self, requested: str | None) -> LocalePack:
        """Best available match. "ar-OM" -> "ar" -> default. Never raises."""
        if not requested:
            return self._default
        wanted = requested.lower().replace("_", "-")
        if wanted in self._packs:
            return self._packs[wanted]
        base = wanted.split("-")[0]
        return self._packs.get(base, self._default)

    @classmethod
    def from_config(
        cls, raw: Iterable[Mapping[str, Any]], *, required_rules: frozenset[str]
    ) -> LocaleCatalogue:
        return cls(
            (LocalePack.model_validate(dict(entry)) for entry in raw),
            required_rules=required_rules,
        )
