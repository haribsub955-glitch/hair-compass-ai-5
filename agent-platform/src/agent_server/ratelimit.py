"""Request rate limiting — the cap the token ledger does not provide.

The ledger bounds **spend**. It does not bound **requests**, and the two come apart precisely where
it matters: an unauthenticated flood costs zero tokens (the scope gate refuses before any model
call) while still consuming connections, database round trips and an SSE slot each. On a LAN that
is academic. Behind a public hostname it is the first thing anyone tries.

Two limiters, because they answer different questions:

* **per principal** — "is this user being unreasonable?" Survives an IP change, so a mobile client
  roaming between wifi and cellular is not punished, and a single account cannot be multiplied by
  rotating addresses.
* **per client address** — "is this source being unreasonable?" Catches the case *before* a
  principal exists, which is exactly the unauthenticated flood.

Sliding-window counters in memory, deliberately. A token-bucket in Redis would be more precise and
would survive a restart; neither matters yet, and a limiter is worthless if it is the thing that
breaks. When there are two processes this moves to the same Postgres the ledger uses — the
interface below is what that has to satisfy.
"""

from __future__ import annotations

import asyncio
import time
from collections import deque
from dataclasses import dataclass, field

from agent_core.contracts import ErrorCode
from agent_server.core.errors import PlatformError


class RateLimited(PlatformError):
    code = ErrorCode.QUOTA_EXHAUSTED
    status = 429
    message = "That's a lot of requests. Give it a moment and try again."


@dataclass(frozen=True, slots=True)
class Limit:
    """`count` requests per `seconds`."""

    count: int
    seconds: int

    def __post_init__(self) -> None:
        if self.count < 1 or self.seconds < 1:
            raise ValueError("a limit needs a positive count and window")


#: Deliberately generous for a real user and tight for a script. A person opening the app, starting
#: a turn and answering four tool calls is well inside this; a loop is not.
DEFAULT_PRINCIPAL_LIMIT = Limit(count=60, seconds=60)
#: Wider, because one address can legitimately carry several devices — a household, an office, a
#: carrier NAT. Too tight here and a shared connection locks out innocent users, which is the
#: failure mode people actually hit.
DEFAULT_ADDRESS_LIMIT = Limit(count=240, seconds=60)


@dataclass
class SlidingWindow:
    """One key's recent request timestamps.

    A sliding window rather than a fixed one: a fixed window resets on a boundary, so 60/minute
    permits 120 requests across the two seconds either side of it. That burst is exactly what the
    limit was for.
    """

    limit: Limit
    hits: deque[float] = field(default_factory=deque)

    def allow(self, now: float) -> bool:
        cutoff = now - self.limit.seconds
        while self.hits and self.hits[0] <= cutoff:
            self.hits.popleft()
        if len(self.hits) >= self.limit.count:
            return False
        self.hits.append(now)
        return True

    @property
    def idle_since(self) -> float:
        return self.hits[-1] if self.hits else 0.0


class RateLimiter:
    """Sliding-window limiter over arbitrary keys.

    Keys expire when idle so the map cannot grow without bound — the memory leak an
    unauthenticated endpoint would otherwise hand an attacker for free.
    """

    __slots__ = ("_last_sweep", "_limit", "_lock", "_windows")

    def __init__(self, limit: Limit) -> None:
        self._limit = limit
        self._windows: dict[str, SlidingWindow] = {}
        self._lock = asyncio.Lock()
        self._last_sweep = 0.0

    async def check(self, key: str) -> None:
        """Record a request. Raises `RateLimited` when the key is over its limit."""
        async with self._lock:
            # Clock read inside the lock so a hit is stamped when it is RECORDED, not when the
            # request began queuing. A review flagged the outside-the-lock read as an ordering bug
            # (stale timestamps landing out of order, jamming the expiry loop). Tested: it is not
            # one — `asyncio.Lock` wakes waiters FIFO and nothing yields between the clock read and
            # `acquire()`, so the deque stays sorted either way. Kept anyway because the invariant
            # then holds by construction rather than by a property of the lock, and a future swap
            # to a non-FIFO primitive would otherwise reintroduce a real bug silently.
            now = time.monotonic()
            self._sweep(now)
            window = self._windows.get(key)
            if window is None:
                window = SlidingWindow(self._limit)
                self._windows[key] = window
            if not window.allow(now):
                raise RateLimited(f"key={key} limit={self._limit.count}/{self._limit.seconds}s")

    def _sweep(self, now: float) -> None:
        """Drop keys idle for two full windows. Amortised — running it on every request would make
        the limiter's own cost scale with the number of keys, which is backwards."""
        if now - self._last_sweep < self._limit.seconds:
            return
        self._last_sweep = now
        stale = now - (self._limit.seconds * 2)
        for key in [k for k, w in self._windows.items() if w.idle_since < stale]:
            del self._windows[key]

    @property
    def tracked_keys(self) -> int:
        return len(self._windows)


class RequestGuard:
    """Both limiters, applied in the order that fails cheapest.

    Address first: it is the only one available before authentication, and rejecting an
    unauthenticated flood must not require deriving a principal for every request in it.
    """

    __slots__ = ("by_address", "by_principal")

    def __init__(
        self,
        *,
        principal_limit: Limit = DEFAULT_PRINCIPAL_LIMIT,
        address_limit: Limit = DEFAULT_ADDRESS_LIMIT,
    ) -> None:
        self.by_principal = RateLimiter(principal_limit)
        self.by_address = RateLimiter(address_limit)

    async def check_address(self, address: str | None) -> None:
        if address:
            await self.by_address.check(address)

    async def check_principal(self, principal_id: str) -> None:
        await self.by_principal.check(principal_id)
