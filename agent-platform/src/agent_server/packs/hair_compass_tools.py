"""Hair Compass's tool manifest — the app-specific half of its pack.

Split out from the policy pack because these two things change for different reasons and are edited
by different people: safety rules move when the product's stance moves, tools move when the app
grows a capability.

**Every tool here works on iOS and Android.** Where the underlying framework differs the tool does
not: `read_health_signals` is HealthKit on one and Health Connect on the other, `scan_label_text` is
Vision on one and ML Kit on the other. The agent sees one name and one schema. That is the point —
a tool whose *name* leaked the platform would force the loop to branch, and the loop must never
know which phone it is talking to.
"""

from __future__ import annotations

from agent_core.contracts import Entitlement
from agent_core.tools import Platform, Runtime, ToolRegistry, ToolSpec

_DAYS = {
    "type": "object",
    "additionalProperties": False,
    "properties": {"days": {"type": "integer", "minimum": 1, "maximum": 365}},
    "required": ["days"],
}

TOOLS = ToolRegistry(
    [
        # --- device: the user's own data, which never leaves except as a query result ----------
        ToolSpec(
            name="recall_memory",
            description="Search the user's own saved notes and past conversations on their device.",
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "scope": {"type": "string", "maxLength": 64},
                    "query": {"type": "string", "maxLength": 200},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 20},
                },
                "required": ["query"],
            },
            runtime=Runtime.DEVICE,
            effects=("read_personal",),
            taints=True,
        ),
        ToolSpec(
            name="read_recent_entries",
            description="Read the user's recent daily check-ins from their device.",
            schema=_DAYS,
            runtime=Runtime.DEVICE,
            effects=("read_personal",),
            taints=True,
        ),
        ToolSpec(
            name="read_lab_results",
            description="Read lab results the user has recorded, with reference-range flags.",
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 50}},
            },
            runtime=Runtime.DEVICE,
            effects=("read_personal", "read_health"),
            # Lab values are OCR'd from documents the user photographed. That makes this the single
            # most likely injection path in the app — a PDF can contain any sentence at all.
            taints=True,
        ),
        ToolSpec(
            name="read_health_signals",
            description="Read lifestyle signals (sleep, activity, weight) the user has shared.",
            schema=_DAYS,
            runtime=Runtime.DEVICE,
            effects=("read_personal", "read_health"),
            taints=True,
            # HealthKit on iOS, Health Connect on Android. One tool, one schema, two adapters.
            platforms=frozenset({Platform.IOS, Platform.ANDROID, Platform.TEST}),
        ),
        ToolSpec(
            name="scan_label_text",
            description="Read the text off a product label the user photographed.",
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {"image_ref": {"type": "string", "maxLength": 128}},
                "required": ["image_ref"],
            },
            runtime=Runtime.DEVICE,
            effects=("read_personal",),
            # Vision on iOS, ML Kit on Android. OCR output is arbitrary text off a photograph.
            taints=True,
        ),
        # --- device, mutating: both require a key, because a lost ACK means a retry -------------
        ToolSpec(
            name="log_entry",
            description="Record a daily check-in on the user's device.",
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "date": {"type": "string", "maxLength": 10},
                    "shed_count": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "note": {"type": "string", "maxLength": 500},
                },
                "required": ["date"],
            },
            runtime=Runtime.DEVICE,
            effects=("write_personal",),
            mutates=True,
            requires_idempotency_key=True,
        ),
        ToolSpec(
            name="add_calendar_event",
            description="Add a booked procedure to the user's calendar.",
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "title": {"type": "string", "maxLength": 120},
                    "starts_at": {"type": "string", "maxLength": 32},
                    "duration_minutes": {"type": "integer", "minimum": 5, "maximum": 480},
                },
                "required": ["title", "starts_at"],
            },
            runtime=Runtime.DEVICE,
            # EventKit on iOS, CalendarContract on Android. Writes outside the app's own store, so
            # it carries a heavier effect than an in-app write — and a duplicate here is a calendar
            # entry the user has to delete by hand, which is exactly why the key is mandatory.
            effects=("write_external", "calendar"),
            mutates=True,
            requires_idempotency_key=True,
        ),
        # --- server: our catalogue, our IP ------------------------------------------------------
        ToolSpec(
            name="search_evidence",
            description=(
                "Search the curated evidence library for treatments, ingredients and conditions. "
                "Returns tiered entries; myths are returned as myths."
            ),
            schema={
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "query": {"type": "string", "maxLength": 200},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 10},
                },
                "required": ["query"],
            },
            runtime=Runtime.SERVER,
            effects=("read_catalog",),
            min_entitlement=Entitlement.PRO,
        ),
    ]
)
