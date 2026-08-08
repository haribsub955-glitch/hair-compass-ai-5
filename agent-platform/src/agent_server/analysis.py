"""The G1 turn, start to finish.

One envelope in, one safety-checked structured analysis out. No tools, no loop, no approvals — those
arrive when a user story needs them (ARCHITECTURE.md §3).

The order of the steps is the design. Every cheap rejection happens before any expensive or
irreversible one:

    protocol -> schema -> size -> entitlement -> consent -> RESERVE -> provider -> safety -> SETTLE

Nothing that costs money runs until everything free has passed, and the money is reserved *before*
the provider call rather than counted after, so two concurrent turns cannot both slip through.
"""

from __future__ import annotations

import json
from typing import Any
from uuid import uuid4

from agent_core.contracts import (
    PROTOCOL_VERSION,
    AnalysisRequest,
    AnalysisResponse,
    Claim,
    ClaimCategory,
    Entitlement,
    Principal,
    Usage,
)
from agent_core.safety import evaluate
from agent_server.adapters.llm.base import ModelAdapter, ProviderRefusal
from agent_server.core.errors import (
    NotEntitled,
    ProtocolUnsupported,
    ProviderUnavailable,
    SchemaUnsupported,
)
from agent_server.ledger import CostLedger
from agent_server.packs import hair_compass as pack
from agent_server.privacy import require_consent

#: The purpose an analysis turn runs under. A server-side constant, because the alternative — the
#: client naming it — means the client picks which of its own grants to be measured against.
ANALYSIS_PURPOSE = "agent-analysis"

#: What the model must return. Kept next to the turn rather than in the pack because the *shape* is
#: platform-wide — every pack produces claims; only the categories' meaning is app-specific.
CLAIMS_SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["claims"],
    "additionalProperties": False,
    "properties": {
        "claims": {
            "type": "array",
            "maxItems": 12,
            "items": {
                "type": "object",
                "required": ["text", "category"],
                "additionalProperties": False,
                "properties": {
                    "text": {"type": "string", "maxLength": 600},
                    "category": {"type": "string", "enum": [c.value for c in ClaimCategory]},
                    "evidence": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
                    "uncertain": {"type": "boolean"},
                },
            },
        }
    },
}


def _parse_claims(payload: dict[str, Any]) -> tuple[Claim, ...]:
    """Turn the provider's object into claims, dropping anything malformed.

    A claim whose category is unrecognised is discarded rather than defaulted. Defaulting it to a
    permissive category would let a model invent its way past the safety policy simply by emitting
    a category name we do not know — the exact failure the tagging scheme exists to prevent.
    """
    claims: list[Claim] = []
    for raw in payload.get("claims", []):
        if not isinstance(raw, dict):
            continue
        text = raw.get("text")
        category = raw.get("category")
        if not isinstance(text, str) or not text.strip():
            continue
        if category not in ClaimCategory.__members__.values() and category not in {
            c.value for c in ClaimCategory
        }:
            continue
        evidence = raw.get("evidence")
        claims.append(
            Claim(
                text=text.strip(),
                category=ClaimCategory(category),
                evidence=tuple(e for e in evidence if isinstance(e, str))
                if isinstance(evidence, list)
                else (),
                uncertain=bool(raw.get("uncertain", False)),
            )
        )
    return tuple(claims)


async def run_analysis(
    request: AnalysisRequest,
    *,
    principal: Principal,
    adapter: ModelAdapter,
    ledger: CostLedger,
    max_output_tokens: int,
    identity=None,
    audit=None,
) -> AnalysisResponse:
    """Execute one turn.

    `principal` is passed in, never derived from `request` — the caller has already authenticated it
    (§6). Nothing in this function reads identity or entitlement off the wire.
    """
    if request.protocol_version != PROTOCOL_VERSION:
        raise ProtocolUnsupported(
            f"client sent v{request.protocol_version}, server is v{PROTOCOL_VERSION}"
        )

    if request.envelope.schema_version not in pack.SUPPORTED_SCHEMA_VERSIONS:
        raise SchemaUnsupported(
            f"envelope schema v{request.envelope.schema_version} not in "
            f"{sorted(pack.SUPPORTED_SCHEMA_VERSIONS)}"
        )

    # Entitlement is read from the authenticated principal, never from the request (§7).
    if principal.entitlement is not Entitlement.PRO:
        raise NotEntitled(f"principal={principal.principal_id} entitlement={principal.entitlement}")

    # The provider is outside Oman, so this turn is a cross-border transfer of personal data.
    # Oman's PDPL wants explicit consent for that, and we have no way to run it without one.
    #
    # Checked against the STORED grant, not against `request.consent`. That field is filled in by
    # the client, so the old check — `if not request.consent.crosses_border` — was satisfied by a
    # modified build sending `true`. The client's copy is passed as `claimed` purely so a
    # disagreement between what the app believes and what the server recorded gets audited.
    #
    # The PURPOSE is named by the server, not taken from `request.consent.purpose`. It was the
    # client's to choose, and every purpose in the default registry allows a cross-border transfer
    # — so a grant for `model-improvement` satisfied the gate for running an analysis. Consent was
    # stored server-side and purpose-limitation was still client-driven, which is most of the point
    # of purpose-limitation gone.
    await require_consent(
        identity,
        principal,
        purpose=ANALYSIS_PURPOSE,
        crosses_border=True,
        claimed=request.consent.crosses_border,
        audit=audit,
    )

    gates = pack.gates_for(request.envelope.facts)
    user_message = json.dumps(request.envelope.facts, sort_keys=True, default=str)
    if request.user_text:
        # The user's own words go in a labelled section, never spliced into the instructions. This
        # is data in a typed slot, not a control — see §5 on why the label alone is not the defence.
        user_message = f"{user_message}\n\n[user question]\n{request.user_text}"

    # Worst case, in tokens: everything we might spend on this turn. Reserved up front so a
    # concurrent turn sees it as gone.
    worst_case = len(user_message) // 4 + len(pack.SYSTEM_PROMPT) // 4 + max_output_tokens
    reservation = await ledger.reserve(principal.principal_id, worst_case)

    try:
        payload, usage = await adapter.complete_structured(
            system=pack.SYSTEM_PROMPT,
            user=user_message,
            schema=CLAIMS_SCHEMA,
            max_output_tokens=max_output_tokens,
        )
    except ProviderRefusal:
        # A refusal cost tokens, so it settles rather than releases — but it produces no claims, and
        # the app falls back to its deterministic path.
        await ledger.settle(reservation, Usage(input_tokens=worst_case // 2, output_tokens=0))
        raise
    except Exception:
        # Nothing reached the provider, or the transport died before it billed us. Give the whole
        # reservation back rather than charging for a call that produced nothing.
        await ledger.release(reservation)
        raise ProviderUnavailable("provider call failed") from None

    await ledger.settle(reservation, usage)

    kept, verdict = evaluate(_parse_claims(payload), policy=pack.SAFETY_POLICY, gates=gates)

    return AnalysisResponse(
        turn_id=uuid4().hex,
        pack_version=pack.PACK_VERSION,
        claims=kept,
        safety=verdict,
        usage=usage,
    )
