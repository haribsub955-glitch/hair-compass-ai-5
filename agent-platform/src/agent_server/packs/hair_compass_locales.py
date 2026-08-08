"""Locales for the hair-compass pack — English and Arabic.

**A locale carries its own safety rules, and that is the whole point.** The English guards match
English text; run an Arabic answer past them and every one of them passes, so a model answering in
Arabic would be completely ungoverned while the logs showed a safety verdict of ALLOW. The
catalogue refuses to load a locale that is missing a required rule, so adding a language cannot
silently add an ungoverned one.

**The Arabic patterns are written, not translated.** A machine-translated guard reads as a working
guard and is not one: it misses the words people actually use, and it is impossible to review
because the reviewer sees plausible Arabic either way. These follow the same *intent* as the
English rules, in the terms an Arabic speaker would actually write.

Arabic orthography makes a literal match unreliable, so the patterns account for the three things
that vary in ordinary typing:

* **Alef forms** — `أ إ آ ا` are typed interchangeably, so every alef is a character class.
* **Ta marbuta** — `ة` and `ه` are freely swapped at the end of a word.
* **Diacritics** — optional, and almost always absent, but a copy-paste from a formal source
  carries them; the patterns tolerate them between letters rather than requiring their absence.

`ar-OM` exists as its own entry because Oman is the launch market and the *strings* differ in
register even where the rules do not — it inherits by resolution (`ar-OM` → `ar` → `en`), so it
only has to state what it changes.
"""

from __future__ import annotations

import re

from agent_core.locales import LocaleCatalogue, LocalePack
from agent_server.packs.hair_compass import (
    MYTH_ASSERTED_AS_FACT,
    MYTH_DEBUNKED,
    PERSONAL_DIAGNOSIS,
    RECOMMENDS_STARTING_RX,
    UNVERIFIED_CLAIM,
)

#: Optional Arabic diacritics. Almost always absent in ordinary typing, routine in text pasted
#: from a formal source — so every position between letters has to tolerate them.
_HARAKAT = r"[ً-ْٰ]*"


def _ar(word: str) -> str:
    """Turn a plainly-written Arabic word into a pattern that survives real typing.

    Hand-writing these was a mistake and the tests caught it three times over: a misspelt
    مينوكسيديل, diacritics tolerated only at the END of a word rather than between letters, and an
    alef class on the second letter but a literal alef on the first. The source stayed unreadable
    the whole time, which is exactly why the errors were invisible.

    So the patterns are written as words a reader can check, and the orthography is applied here,
    once:

    * every alef form (`ا أ إ آ`) matches any other — people type them interchangeably
    * `ة` and `ه` match each other at the end of a word
    * `ي` and `ى` match each other, likewise freely swapped
    * diacritics may appear between any two letters
    """
    out: list[str] = []
    for char in word:
        if char in "اأإآ":
            out.append(r"[اأإآ]")
        elif char in "ةه":
            out.append(r"[ةه]")
        elif char in "يى":
            out.append(r"[يى]")
        elif char == " ":
            out.append(r"\s+")
            continue
        else:
            out.append(re.escape(char))
        out.append(_HARAKAT)
    return "".join(out)


def _any(*words: str) -> str:
    """Alternation over `_ar`-normalised words."""
    return "(" + "|".join(_ar(w) for w in words) + ")"


#: Anything up to the next sentence break — Arabic uses ، and ؛ as well as the Latin stop.
_GAP = r"[^.،؛]{0,40}"

ENGLISH = LocalePack(
    code="en",
    display_name="English",
    instruction="Answer in English.",
    strings={
        "scope_refusal": (
            "I only cover hair and scalp health, and your own tracking record. Ask me about your "
            "entries, treatments, labs or routine and I'll dig in."
        ),
        "quota_exhausted": "You've used this period's AI allowance. It refreshes soon.",
        "provider_unavailable": (
            "I couldn't reach the analysis service. Your data is safe — try again shortly."
        ),
        "consent_required": (
            "This needs your permission first. You can grant it in Privacy settings."
        ),
        "upgrade_required": "Please update the app to continue.",
    },
    # `.pattern` because the pack holds them compiled. Referenced, never restated: two copies of a
    # guard drift, and the copy that drifts is the one nobody is testing.
    text_rules={
        "personal_diagnosis": PERSONAL_DIAGNOSIS.pattern,
        "recommends_starting_rx": RECOMMENDS_STARTING_RX.pattern,
        "myth_asserted_as_fact": MYTH_ASSERTED_AS_FACT.pattern,
        "unverified_claim": UNVERIFIED_CLAIM.pattern,
    },
    text_rule_exceptions={"myth_asserted_as_fact": MYTH_DEBUNKED.pattern},
    scope_domain=r"(hair|scalp|shed|shedding|follicle|minoxidil|finasteride|ferritin|dandruff)",
    scope_self_reference=r"(i|my|me|mine)",
    scope_off_domain=r"(capital of|weather|football|write me (code|a poem)|translate)",
)

ARABIC = LocalePack(
    code="ar",
    display_name="العربية",
    instruction="أجب باللغة العربية الفصحى، بلغة واضحة ومباشرة.",
    strings={
        "scope_refusal": (
            "أنا مخصص لصحة الشعر وفروة الرأس ولسجل متابعتك الشخصي فقط. اسألني عن تسجيلاتك أو "
            "علاجاتك أو تحاليلك أو روتينك وسأساعدك."
        ),
        "quota_exhausted": "لقد استهلكت حصتك من التحليل لهذه الفترة. ستتجدد قريباً.",
        "provider_unavailable": "تعذّر الوصول إلى خدمة التحليل. بياناتك آمنة — حاول بعد قليل.",
        "consent_required": "نحتاج إذنك أولاً. يمكنك منحه من إعدادات الخصوصية.",
        "upgrade_required": "يرجى تحديث التطبيق للمتابعة.",
    },
    text_rules={
        # A personal diagnosis: "you have / this is / you suffer from <condition>".
        "personal_diagnosis": (
            _any(
                "لديك",
                "عندك",
                "تعاني من",
                "إصابة ب",
                "مصاب ب",
                "هذه حالة من",
                "هذا نوع من",
            )
            + _GAP
            + _any(
                "ثعلبة",
                "صلع",
                "حاصة",
                "سعفة",
                "قوباء",
                "تساقط الشعر",
                "الغدة الدرقية",
                "الثعلبة البقعية",
            )
        ),
        # Telling someone to START a prescription medicine. Continuing or discussing one is fine —
        # the harm is initiating without a prescriber, which is what these verbs capture.
        "recommends_starting_rx": (
            _any("ابدأ", "يجب أن تبدأ", "أنصحك ب", "أنصح ب", "عليك بتناول", "خذ")
            + _GAP
            + _any("فيناستيريد", "مينوكسيديل", "دوتاستيريد", "سبيرونولاكتون", "إيزوتريتينوين")
        ),
        # A myth stated as fact. The same named-and-excluded stance as the English catalogue: a
        # myth may be DISCUSSED, never asserted.
        "myth_asserted_as_fact": (
            _any("البيوتين", "الكولاجين", "الزنك", "زيت الخروع", "البصل", "زيت جوز الهند")
            + _GAP
            + _any("يعالج", "ينبت", "يوقف التساقط", "يزيد كثافة", "يعيد إنبات")
        ),
        # An efficacy claim with a number attached, which must come from the deterministic core
        # rather than from the model.
        "unverified_claim": (
            _any("أثبتت", "مؤكد", "بنسبة", "يضمن", "نتائج مضمونة")
            + r"[^.،؛]{0,30}"
            # Arabic-Indic digits are what an Arabic keyboard produces, and ٪ is the percent sign.
            + r"([0-9٠-٩]{1,3}\s*(%|٪|"
            + _ar("بالمئة")
            + r"))"
        ),
    },
    text_rule_exceptions={
        # Debunking has to survive in every language, or the app cannot do the one thing it exists
        # to do — name a myth and exclude it. Without this, "there is no evidence that biotin
        # treats hair loss" trips the myth rule and is redacted.
        "myth_asserted_as_fact": _any(
            "لا يوجد دليل", "لا تدعم", "خرافة", "شائعة خاطئة", "ليس هناك دليل", "لم يثبت"
        ),
        "personal_diagnosis": _any(
            "لا أستطيع تشخيص", "لا يمكنني تشخيص", "راجع طبيب", "يحتاج إلى تشخيص", "لا أشخص"
        ),
    },
    scope_domain=_any(
        "شعر",
        "شعري",
        "فروة الرأس",
        "تساقط",
        "قشرة",
        "صلع",
        "ثعلبة",
        "مينوكسيديل",
        "فيناستيريد",
        "فيريتين",
        "حديد",
        "فيتامين",
        "تحليل",
        "علاج",
        "روتين",
        "شامبو",
    ),
    scope_self_reference=_any("أنا", "عندي", "لدي", "شعري", "حالتي", "نتائجي", "تسجيلاتي"),
    scope_off_domain=_any(
        "عاصمة", "الطقس", "كرة القدم", "سياسة", "برمجة", "رياضيات", "وصفة طبخ", "ترجم لي"
    ),
)

ARABIC_OMAN = ARABIC.model_copy(
    update={
        "code": "ar-OM",
        "display_name": "العربية (عُمان)",
        "strings": {
            **ARABIC.strings,
            "consent_required": "نحتاج موافقتك أولاً. يمكنك منحها من إعدادات الخصوصية.",
        },
    }
)

#: Every rule name a locale MUST define. The catalogue refuses to load one that is missing any of
#: them, which is what stops "we added Arabic" from also meaning "Arabic is ungoverned".
REQUIRED_RULES = frozenset(
    {"personal_diagnosis", "recommends_starting_rx", "myth_asserted_as_fact", "unverified_claim"}
)

LOCALES = LocaleCatalogue([ENGLISH, ARABIC, ARABIC_OMAN], required_rules=REQUIRED_RULES)
