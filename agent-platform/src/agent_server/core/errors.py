"""One error type, one client-facing shape.

Clients receive a code, a safe message, and a correlation id — never a traceback, a provider
message, or a database error (SAF7 / SD). Full detail goes to the server log against the same
correlation id, so support can find it from what the user quotes.
"""

from __future__ import annotations

from agent_core.contracts import ErrorCode


class PlatformError(Exception):
    """Base for every error that has a defined client shape.

    `detail` is for the server log only. Anything placed there is assumed to be unsafe to show a
    user — it may contain provider text, SQL, or personal data.
    """

    code: ErrorCode = ErrorCode.INTERNAL
    status: int = 500
    message = "Something went wrong."

    def __init__(self, detail: str = "") -> None:
        super().__init__(detail or self.message)
        self.detail = detail


class ProtocolUnsupported(PlatformError):
    code = ErrorCode.PROTOCOL_UNSUPPORTED
    status = 400
    message = "This app version is no longer supported. Please update."


class SchemaUnsupported(PlatformError):
    code = ErrorCode.SCHEMA_UNSUPPORTED
    status = 400
    message = "This app version sends data in a format the service no longer accepts."


class EnvelopeTooLarge(PlatformError):
    code = ErrorCode.ENVELOPE_TOO_LARGE
    status = 413
    message = "There's too much data in this request."


class NotEntitled(PlatformError):
    code = ErrorCode.NOT_ENTITLED
    status = 402
    message = "This is a Pro feature. If you just subscribed, try Restore Purchases."


class QuotaExhausted(PlatformError):
    code = ErrorCode.QUOTA_EXHAUSTED
    status = 429
    message = "You've reached today's limit. It resets tomorrow."


class ConsentRequired(PlatformError):
    code = ErrorCode.CONSENT_REQUIRED
    status = 403
    message = "This needs your consent before it can run."


class ProviderUnavailable(PlatformError):
    code = ErrorCode.PROVIDER_UNAVAILABLE
    status = 503
    message = "The analysis service is busy. Please try again shortly."
