"""Placement invariants — the tests that keep migration a table edit.

The failure these prevent is silent. A capability quietly marked `EITHER` that turns out to hold an
API key ships that key in a binary, and nothing about the code looks wrong at the call site. So the
declaration carries the facts and the tests carry the rules.
"""

from __future__ import annotations

import pytest

from agent_core.placement import (
    PLATFORM_PLACEMENT,
    Capability,
    Placement,
    PlacementError,
    PlacementMap,
    Side,
)


def test_no_secret_bearing_capability_can_live_on_a_device() -> None:
    """A secret on a phone is a published secret. Obfuscation changes how long it takes, not
    whether it happens."""
    for capability in PLATFORM_PLACEMENT:
        if capability.handles_secret:
            assert capability.placement is Placement.SERVER, capability.name


def test_no_authority_decision_can_live_on_a_device() -> None:
    """A patched client controls anything it computes, so anything that grants or denies must be
    computed where the client cannot reach it."""
    for capability in PLATFORM_PLACEMENT:
        if capability.decides_authority:
            assert capability.placement is Placement.SERVER, capability.name


def test_declaring_a_secret_on_the_device_is_rejected_at_construction() -> None:
    with pytest.raises(PlacementError, match="handles a secret"):
        Capability(name="leaky", placement=Placement.DEVICE, reason="test", handles_secret=True)


def test_declaring_an_authority_decision_as_relocatable_is_rejected() -> None:
    """`EITHER` is the dangerous one — it looks harmless and silently permits the device."""
    with pytest.raises(PlacementError, match="decides authority"):
        Capability(name="leaky", placement=Placement.EITHER, reason="test", decides_authority=True)


def test_every_placement_states_a_reason() -> None:
    """The reason is what a future reader needs to decide whether a move is safe."""
    for capability in PLATFORM_PLACEMENT:
        assert capability.reason, capability.name
    with pytest.raises(PlacementError, match="stated reason"):
        Capability(name="bare", placement=Placement.SERVER, reason="")


def test_requiring_a_server_capability_on_the_device_raises() -> None:
    with pytest.raises(PlacementError, match="cannot run on the device"):
        PLATFORM_PLACEMENT.require("model_adapter", Side.DEVICE)


def test_requiring_a_device_capability_on_the_server_raises() -> None:
    with pytest.raises(PlacementError, match="cannot run on the server"):
        PLATFORM_PLACEMENT.require("secure_storage", Side.SERVER)


def test_a_relocatable_capability_is_allowed_on_both_sides() -> None:
    """This is the property that makes migration cheap: the wiring changes, the code does not."""
    for side in Side:
        assert PLATFORM_PLACEMENT.require("feature_flags", side)


def test_an_undeclared_capability_raises_rather_than_defaulting() -> None:
    """Defaulting an unknown capability to either side is how something ends up in the wrong
    process without anyone deciding it should."""
    with pytest.raises(PlacementError, match="no placement declared"):
        PLATFORM_PLACEMENT.get("something_nobody_declared")


def test_duplicate_declarations_are_rejected() -> None:
    with pytest.raises(PlacementError, match="declared twice"):
        PlacementMap(
            [
                Capability(name="dup", placement=Placement.SERVER, reason="a"),
                Capability(name="dup", placement=Placement.DEVICE, reason="b"),
            ]
        )


def test_the_agent_loop_and_prompts_are_server_side() -> None:
    """The anti-decompilation requirement, asserted rather than assumed."""
    for name in ("agent_loop", "prompt_pack", "skills", "playbooks", "safety_verifier"):
        assert PLATFORM_PLACEMENT.get(name).placement is Placement.SERVER, name


def test_personal_data_defaults_to_the_device() -> None:
    """Anything holding personal data belongs on the device unless there is a stated reason it
    cannot — and the one exception says so in its reason."""
    server_side_personal = [
        c for c in PLATFORM_PLACEMENT if c.holds_personal_data and c.placement is Placement.SERVER
    ]
    assert [c.name for c in server_side_personal] == ["run_state"]
    assert "discarded" in PLATFORM_PLACEMENT.get("run_state").reason


def test_the_two_sides_partition_sensibly() -> None:
    device = {c.name for c in PLATFORM_PLACEMENT.on(Side.DEVICE)}
    server = {c.name for c in PLATFORM_PLACEMENT.on(Side.SERVER)}
    assert "memory_store" in device and "memory_store" not in server
    assert "model_adapter" in server and "model_adapter" not in device
    # Relocatable capabilities appear on both — that is what relocatable means.
    assert device & server == {"consent_record", "feature_flags"}
