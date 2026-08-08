"""Attachment intake — bytes in, id out, and gone again as soon as they are used.

The privacy position first, because it drives every other decision here: **the server must never
become a photo library.** A scalp photo is health data and biometric-adjacent, the phone already
keeps it permanently in its own store, and the copy here exists only to be handed to a model once.
So it is deleted the moment the turn that used it finishes, and anything orphaned is swept. Nothing
accumulates, which means nothing leaks later and erasure has almost nothing left to reach.

**Sniffed, never trusted.** A client says `image/jpeg`; the first bytes say what it really is. A
file that lies about its type is how a stored payload ends up somewhere that renders it, and an
allowlist of magic numbers costs four comparisons. The declared type is discarded — the sniffed one
is what gets stored and sent.

**Scoped by principal, always.** An attachment resolves only for the principal that uploaded it.
Ids are random, but "unguessable" is not an access control, and the failure it prevents — one
user's photo reaching another user's turn — is the worst thing this module could do.
"""

from __future__ import annotations

import hashlib
import logging
import secrets

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError

log = logging.getLogger("agent_server.attachments")

#: Above a phone photo, below a denial-of-wallet. An image also costs real tokens, so the ledger's
#: budget is the second bound and this is the first.
MAX_BYTES = 8 * 1024 * 1024

#: How long an unused upload survives. Long enough to attach a photo and then take a while typing;
#: short enough that a forgotten one is not still there tomorrow.
ORPHAN_AFTER_SECONDS = 30 * 60

#: Magic numbers, and the media type each one really is. An allowlist: anything not matching here
#: is refused rather than passed through with a guess.
_SIGNATURES: tuple[tuple[bytes, str], ...] = (
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
)


class AttachmentRejected(PlatformError):
    """Too big, wrong type, or not what it claims. The message is deliberately actionable — unlike
    an auth failure there is nothing to withhold, and a user who picked a 20 MB RAW file deserves
    to be told that rather than left guessing."""

    code = ErrorCode.ENVELOPE_TOO_LARGE
    status = 413
    message = "That file could not be attached. Photos only, up to 8 MB."


def sniff(data: bytes) -> str:
    """The media type the bytes actually are. Raises `AttachmentRejected` for anything else.

    WEBP and HEIC are deliberately absent for now: both need more than a prefix check to identify
    safely, and every iOS camera roll can produce JPEG. Adding them is a signature and a test, not
    a redesign — but shipping a loose check to cover them would be the wrong trade.
    """
    for signature, media_type in _SIGNATURES:
        if data.startswith(signature):
            return media_type
    raise AttachmentRejected("unrecognised file type")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def new_id() -> str:
    return f"att_{secrets.token_urlsafe(18)}"


class AttachmentStore:
    """Postgres-backed, because an in-process dict loses uploads on the deploy between the upload
    and the turn — a small window that a user hits by taking a photo and then thinking."""

    def __init__(self, sessions) -> None:
        self._sessions = sessions

    async def put(self, *, principal_id: str, data: bytes) -> dict[str, object]:
        """Store bytes and return what the client needs to reference them.

        Size is checked against what was actually READ, not against a declared length — a
        `Content-Length` header is a claim, and the oldest trick is for it to be a lie.
        """
        if not data:
            raise AttachmentRejected("empty file")
        if len(data) > MAX_BYTES:
            raise AttachmentRejected(f"{len(data)} bytes exceeds the {MAX_BYTES} limit")

        media_type = sniff(data)
        attachment_id = new_id()
        sha = digest(data)

        from sqlalchemy import text

        async with self._sessions() as session, session.begin():
            await session.execute(
                text(
                    """
                    INSERT INTO attachments
                        (attachment_id, principal_id, media_type, sha256, byte_size, data)
                    VALUES (:aid, :pid, :mt, :sha, :size, :data)
                    """
                ),
                {
                    "aid": attachment_id,
                    "pid": principal_id,
                    "mt": media_type,
                    "sha": sha,
                    "size": len(data),
                    "data": data,
                },
            )
        log.info("attachment %s stored (%s, %d bytes)", attachment_id, media_type, len(data))
        return {
            "attachment_id": attachment_id,
            "media_type": media_type,
            "sha256": sha,
            "bytes": len(data),
        }

    async def take(self, *, principal_id: str, ids: list[str]) -> list[tuple[str, bytes]]:
        """Fetch and DELETE in one statement — an attachment is used exactly once.

        Deleting as part of the same statement is what makes "the server is not a photo library"
        true rather than aspirational: there is no window in which a used attachment is still
        sitting there waiting for a cleanup job that might not run.

        Scoped by `principal_id`. An id belonging to someone else simply does not match, and the
        caller cannot tell that apart from an id that never existed.
        """
        if not ids:
            return []

        from sqlalchemy import text

        async with self._sessions() as session, session.begin():
            rows = (
                await session.execute(
                    text(
                        """
                        DELETE FROM attachments
                         WHERE principal_id = :pid AND attachment_id = ANY(:ids)
                        RETURNING media_type, data
                        """
                    ),
                    {"pid": principal_id, "ids": ids},
                )
            ).all()

        if len(rows) != len(ids):
            # Expired, already used, or another principal's. All one answer — telling a caller
            # which would confirm that an id they guessed exists.
            raise AttachmentRejected("an attachment is no longer available")
        return [(row.media_type, bytes(row.data)) for row in rows]

    async def reap(self) -> int:
        """Delete uploads nobody used. Returns how many.

        Without this the "transient" claim quietly becomes false: every photo attached to a turn
        that was abandoned, refused on consent, or killed mid-flight stays forever. The ledger's
        equivalent sat written-and-uncalled for weeks, which is exactly why this one is scheduled
        in `lifespan` and has a test asserting it runs.
        """
        from sqlalchemy import text

        async with self._sessions() as session, session.begin():
            rows = (
                await session.execute(
                    text(
                        f"""
                        DELETE FROM attachments
                         WHERE created_at < now() - interval '{ORPHAN_AFTER_SECONDS} seconds'
                        RETURNING attachment_id
                        """
                    )
                )
            ).all()
        if rows:
            log.info("reaped %d orphaned attachments", len(rows))
        return len(rows)
