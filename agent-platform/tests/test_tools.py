"""Tool registry invariants.

Two families here. The first is the subtractive rule — a client may narrow the tool set and may
never widen it. The second is idempotency, which exists because a mobile connection drops mid-call
routinely and "add this to the calendar" must not run twice.
"""

from __future__ import annotations

import pytest

from agent_core.contracts import Entitlement
from agent_core.tools import (
    ALL_PLATFORMS,
    Platform,
    Runtime,
    ToolError,
    ToolRegistry,
    ToolSpec,
)
from agent_server.packs.hair_compass_tools import TOOLS


def _spec(name: str, **kw) -> ToolSpec:
    base = {
        "description": "d",
        "schema": {"type": "object"},
        "runtime": Runtime.DEVICE,
    }
    return ToolSpec(name=name, **(base | kw))


def _resolve(**kw):
    defaults = {
        "platform": Platform.IOS,
        "entitlement": Entitlement.PRO,
        "protocol_version": 1,
    }
    return TOOLS.resolve(**(defaults | kw))


# --------------------------------------------------------------------------------------------
# The client may only subtract
# --------------------------------------------------------------------------------------------


def test_a_client_cannot_add_a_tool_that_is_not_in_the_catalog() -> None:
    """The headline rule. A patched client advertising 'admin_tool' gets nothing."""
    names = {t.name for t in _resolve(client_advertised=frozenset({"admin_tool", "recall_memory"}))}
    assert "admin_tool" not in names
    assert "recall_memory" in names


def test_a_client_that_omits_a_device_tool_loses_it() -> None:
    """Truthful narrowing works: an old build that cannot do OCR says so and is not asked to."""
    names = {t.name for t in _resolve(client_advertised=frozenset({"recall_memory"}))}
    assert names == {"recall_memory", "search_evidence"}  # server tools are never withheld


def test_a_client_cannot_withhold_a_server_tool() -> None:
    """Server tools are ours. A client claiming not to support one must not be able to disable a
    capability that never runs on it."""
    names = {t.name for t in _resolve(client_advertised=frozenset())}
    assert "search_evidence" in names


def test_a_silent_client_loses_nothing() -> None:
    """`None` means the client said nothing, which must not be read as "supports nothing"."""
    assert len(_resolve(client_advertised=None)) == len(TOOLS)


def test_entitlement_gates_paid_tools() -> None:
    free = {t.name for t in _resolve(entitlement=Entitlement.FREE)}
    pro = {t.name for t in _resolve(entitlement=Entitlement.PRO)}
    assert "search_evidence" not in free
    assert "search_evidence" in pro


def test_a_pack_allowlist_narrows_further() -> None:
    names = {t.name for t in _resolve(pack_allowlist=frozenset({"recall_memory"}))}
    assert names == {"recall_memory"}


def test_an_old_protocol_loses_newer_tools() -> None:
    registry = ToolRegistry([_spec("old"), _spec("new", min_protocol=2)])
    names = {
        t.name
        for t in registry.resolve(
            platform=Platform.IOS, entitlement=Entitlement.PRO, protocol_version=1
        )
    }
    assert names == {"old"}


# --------------------------------------------------------------------------------------------
# Cross-platform — the constraint, asserted
# --------------------------------------------------------------------------------------------


def test_every_hair_compass_tool_works_on_both_platforms() -> None:
    """If this ever fails it prints exactly what an Android client would lose, which is the point:
    the gap becomes visible now rather than during a port."""
    ios = {t.name for t in _resolve(platform=Platform.IOS)}
    android = {t.name for t in _resolve(platform=Platform.ANDROID)}
    assert ios == android, f"Android would lose: {sorted(ios - android)}"


def test_a_platform_specific_tool_is_correctly_withheld() -> None:
    """The mechanism works even though nothing uses it yet."""
    registry = ToolRegistry([_spec("ios_only", platforms=frozenset({Platform.IOS}))])
    assert (
        len(
            registry.resolve(
                platform=Platform.IOS, entitlement=Entitlement.FREE, protocol_version=1
            )
        )
        == 1
    )
    assert (
        len(
            registry.resolve(
                platform=Platform.ANDROID, entitlement=Entitlement.FREE, protocol_version=1
            )
        )
        == 0
    )


def test_tools_default_to_every_platform() -> None:
    assert _spec("x").platforms == ALL_PLATFORMS


# --------------------------------------------------------------------------------------------
# Idempotency — a dropped acknowledgement must not duplicate an effect
# --------------------------------------------------------------------------------------------


def test_a_mutating_tool_must_be_idempotent_or_keyed() -> None:
    with pytest.raises(ToolError, match="repeat the effect"):
        _spec("careless", mutates=True)


def test_a_mutating_tool_that_is_naturally_idempotent_is_accepted() -> None:
    assert _spec("set_flag", mutates=True, idempotent=True)


def test_every_mutating_hair_compass_tool_carries_a_key() -> None:
    """`add_calendar_event` is the concrete case: a duplicate is a calendar entry the user has to
    delete by hand."""
    for tool in TOOLS:
        if tool.mutates:
            assert tool.requires_idempotency_key or tool.idempotent, tool.name


# --------------------------------------------------------------------------------------------
# Taint and effects
# --------------------------------------------------------------------------------------------


def test_every_device_tool_returning_user_content_is_tainted() -> None:
    """Anything carrying user- or document-supplied text into a prompt is an instruction channel.
    `read_lab_results` and `scan_label_text` are OCR paths — a photographed PDF can say anything."""
    for name in ("recall_memory", "read_recent_entries", "read_lab_results", "scan_label_text"):
        assert TOOLS.get(name).taints, name


def test_a_server_tool_marked_tainted_needs_an_explicit_decision() -> None:
    """Server output is trusted by default; anything breaking that assumption must be deliberate."""
    with pytest.raises(ToolError, match="explicit review"):
        _spec("odd", runtime=Runtime.SERVER, taints=True)


def test_effects_describe_what_happens_not_what_it_is_called() -> None:
    """The desktop agent learned this expensively: tiering by tool name under-protects anything
    named innocuously. `add_calendar_event` writes outside the app's own store and says so."""
    assert "write_external" in TOOLS.get("add_calendar_event").effects
    assert "write_personal" in TOOLS.get("log_entry").effects
    for tool in TOOLS:
        assert tool.effects, f"{tool.name}: needs an effects vector for the gate to tier on"


# --------------------------------------------------------------------------------------------
# Registry hygiene
# --------------------------------------------------------------------------------------------


def test_duplicate_tool_names_are_rejected() -> None:
    with pytest.raises(ToolError, match="declared twice"):
        ToolRegistry([_spec("dup"), _spec("dup")])


def test_an_unknown_tool_raises_rather_than_returning_none() -> None:
    with pytest.raises(ToolError, match="not in the catalog"):
        TOOLS.get("nope")


def test_a_tool_needs_a_description_the_model_can_read() -> None:
    with pytest.raises(ToolError, match="needs a name and a description"):
        ToolSpec(name="x", description="", schema={}, runtime=Runtime.DEVICE)


def test_resolution_is_deterministically_ordered() -> None:
    """Prompt bytes must not vary between identical turns, or caching and diffing both break."""
    assert [t.name for t in _resolve()] == sorted(t.name for t in _resolve())
