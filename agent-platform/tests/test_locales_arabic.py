"""The Arabic locale pack, and the thing it exists to prevent.

An Arabic answer run past the English guards passes every one of them. So a model answering in
Arabic would be completely ungoverned while the logs recorded a safety verdict of ALLOW — the
worst possible shape for a safety failure, because nothing looks wrong.

These tests are written against real sentences, not against the patterns. A test that asserts a
regex matches its own pattern proves nothing.
"""

from __future__ import annotations

import re

import pytest

from agent_core.locales import LocaleCatalogue, LocaleError, LocalePack
from agent_server.packs.hair_compass_locales import ARABIC, LOCALES, REQUIRED_RULES


def _fires(rule: str, text: str, *, locale: LocalePack = ARABIC) -> bool:
    """Does this rule fire on this sentence, honouring its stand-down pattern?"""
    fire, unless = locale.compiled_rules()[rule]
    return bool(fire.search(text)) and not (unless and unless.search(text))


# --------------------------------------------------------------------------------------------
# The gap this closes
# --------------------------------------------------------------------------------------------


def test_the_english_rules_do_not_govern_arabic_at_all() -> None:
    """The premise, stated as a test. Without a per-locale rule set, this sentence — 'you have
    alopecia areata' — sails past every English guard."""
    diagnosis = "من الواضح أن لديك ثعلبة بقعية في فروة الرأس"
    english = LOCALES.resolve("en")
    assert not any(fire.search(diagnosis) for fire, _ in english.compiled_rules().values()), (
        "an English guard matched Arabic text, which would make this test meaningless"
    )
    assert _fires("personal_diagnosis", diagnosis)


def test_a_locale_missing_a_rule_cannot_be_loaded() -> None:
    """What stops 'we added Arabic' from also meaning 'Arabic is ungoverned'."""
    half_done = LocalePack(code="ar", text_rules={"personal_diagnosis": "لديك"})
    with pytest.raises(LocaleError, match="missing safety rules"):
        LocaleCatalogue([LOCALES.resolve("en"), half_done], required_rules=REQUIRED_RULES)


def test_every_shipped_locale_defines_every_required_rule() -> None:
    for pack in LOCALES:
        assert set(pack.text_rules) >= REQUIRED_RULES, pack.code


# --------------------------------------------------------------------------------------------
# The rules, on real sentences
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "sentence",
    [
        "من الواضح أن لديك ثعلبة بقعية",
        "عندك صلع وراثي في المنطقة الأمامية",
        "أنت تعاني من تساقط الشعر الكربي",
        "هذه حالة من سعفة الرأس",
    ],
)
def test_a_personal_diagnosis_is_caught(sentence) -> None:
    assert _fires("personal_diagnosis", sentence)


def test_refusing_to_diagnose_is_not_itself_a_diagnosis() -> None:
    """The stand-down that matters most: the correct answer names the condition while declining to
    apply it. A guard that redacts its own refusal makes the product unusable in Arabic."""
    assert not _fires(
        "personal_diagnosis", "لا أستطيع تشخيص ما إذا كان لديك ثعلبة — راجع طبيب جلدية"
    )


@pytest.mark.parametrize(
    "sentence",
    [
        "أنصحك بالفيناستيريد لوقف التساقط",
        "ابدأ المينوكسيديل مرتين يومياً",
        "عليك بتناول الدوتاستيريد",
    ],
)
def test_recommending_a_prescription_start_is_caught(sentence) -> None:
    assert _fires("recommends_starting_rx", sentence)


def test_discussing_a_medicine_someone_already_takes_is_allowed() -> None:
    """Continuing or discussing a prescription is fine. The harm is INITIATING one without a
    prescriber, and a rule that blocks discussion blocks the app's actual job."""
    assert not _fires("recommends_starting_rx", "المينوكسيديل الذي تستخدمه يحتاج عدة أشهر")


def test_a_myth_asserted_as_fact_is_caught() -> None:
    assert _fires("myth_asserted_as_fact", "البيوتين يعالج تساقط الشعر ويزيد كثافته")


@pytest.mark.parametrize(
    "sentence",
    [
        "لا يوجد دليل على أن البيوتين يعالج تساقط الشعر",
        "هذه خرافة شائعة: الزنك ينبت الشعر",
        "لم يثبت أن زيت الخروع يوقف التساقط",
    ],
)
def test_debunking_a_myth_survives_in_arabic(sentence) -> None:
    """The product's whole stance is naming-and-excluding myths. If the Arabic guard redacts the
    debunking, the app cannot do in Arabic the one thing it exists to do."""
    assert not _fires("myth_asserted_as_fact", sentence)


def test_an_efficacy_number_the_model_invented_is_caught() -> None:
    assert _fires("unverified_claim", "أثبتت الدراسات نتائج مضمونة بنسبة 90%")


def test_arabic_indic_digits_are_caught_too() -> None:
    """٩٠٪ and 90% are the same claim. A pattern that only knows ASCII digits misses half of what
    an Arabic keyboard produces."""
    assert _fires("unverified_claim", "مؤكد بنسبة ٩٠٪")


# --------------------------------------------------------------------------------------------
# Orthography — the reason a literal match would not survive contact with real typing
# --------------------------------------------------------------------------------------------


@pytest.mark.parametrize("alef", ["ا", "أ", "إ", "آ"])
def test_every_alef_form_is_matched(alef) -> None:
    """People type these interchangeably. A pattern demanding one form misses the rest."""
    assert _fires("recommends_starting_rx", f"{alef}بدأ المينوكسيديل الآن")


def test_diacritics_do_not_defeat_a_rule() -> None:
    """Rare in ordinary typing, routine in text pasted from a formal source."""
    assert _fires("personal_diagnosis", "لَدَيْكَ ثعلبة بقعية")


def test_ta_marbuta_and_ha_are_interchangeable() -> None:
    assert _fires("personal_diagnosis", "لديك ثعلبه بقعية")


# --------------------------------------------------------------------------------------------
# Resolution and direction
# --------------------------------------------------------------------------------------------


def test_a_regional_variant_degrades_to_its_language_not_to_english() -> None:
    """Someone asking for ar-SA should get Arabic, not English."""
    assert LOCALES.resolve("ar-SA").code == "ar"
    assert LOCALES.resolve("ar-OM").code == "ar-OM"
    assert LOCALES.resolve("zz-ZZ").code == "en"
    assert LOCALES.resolve(None).code == "en"


def test_arabic_is_flagged_right_to_left_and_english_is_not() -> None:
    """The client needs this to lay out; it is not something to infer from the string content."""
    assert LOCALES.resolve("ar").is_rtl
    assert LOCALES.resolve("ar-OM").is_rtl
    assert not LOCALES.resolve("en").is_rtl


def test_the_oman_variant_only_overrides_what_it_changes() -> None:
    """A guard that differs by country is a guard nobody can reason about."""
    oman, arabic = LOCALES.resolve("ar-OM"), LOCALES.resolve("ar")
    assert oman.text_rules == arabic.text_rules
    assert oman.strings["consent_required"] != arabic.strings["consent_required"]
    assert oman.strings["scope_refusal"] == arabic.strings["scope_refusal"]


def test_every_server_string_exists_in_every_locale() -> None:
    """A missing key surfaces as an empty message at the worst moment — a quota refusal that says
    nothing looks like the app is broken."""
    english_keys = set(LOCALES.resolve("en").strings)
    for pack in LOCALES:
        assert english_keys <= set(pack.strings), (
            f"{pack.code} is missing {english_keys - set(pack.strings)}"
        )


def test_every_pattern_compiles() -> None:
    """Enforced at load too; asserted here so a broken pattern names itself in a test run."""
    for pack in LOCALES:
        for name, pattern in pack.text_rules.items():
            re.compile(pattern)
            assert pattern.strip(), f"{pack.code}/{name} is empty"
