"""Simulate N phones against a running agent server.

This is the closest thing to the real client that exists before Swift does. Each simulated phone:

  1. opens a turn (`POST /v1/turn`, SSE),
  2. reads `tool_request` events off the stream,
  3. executes the calls locally against its OWN data,
  4. POSTs each result back keyed by `call_id`,
  5. reads the final `answer`.

Every phone's data is stamped with its own id, so a crossed result is loud rather than subtle.

    python scripts/simulate_phones.py --base http://127.0.0.1:8100 --phones 5

Point `--base` at the server to test the same thing over a real network.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time

import httpx


#: Each phone's device data, keyed by owner so a mix-up is visible in the answer itself.
def device_data(owner: int, tool: str) -> dict[str, object]:
    return {
        "recall_memory": {"owner": owner, "hits": [f"phone-{owner} started minoxidil"]},
        "read_recent_entries": {
            "owner": owner,
            "entry_count": 100 + owner,
            "streak_days": owner + 1,
            "shed_count_avg_14d": 40 + owner,
            "direction": "improving",
        },
        "read_lab_results": {
            "owner": owner,
            "results": [{"name": "Ferritin", "value": 10 + owner, "ref_low": 30, "flag": "below"}],
        },
        "read_health_signals": {"owner": owner, "sleep_hours_avg_14d": 6.0 + owner * 0.1},
    }.get(tool, {"owner": owner, "ok": True})


class Phone:
    def __init__(self, owner: int, base: str) -> None:
        self.owner = owner
        self.base = base.rstrip("/")
        self.installation_id = f"sim-phone-{owner:02d}"
        self.tools_run: list[str] = []
        self.owners_seen: set[int] = set()
        self.answer = ""
        self.error = ""
        self.waves = 0

    async def _submit(self, client: httpx.AsyncClient, call: dict) -> None:
        payload = device_data(self.owner, call["tool"])
        self.tools_run.append(call["tool"])
        response = await client.post(
            f"{self.base}/v1/turn/result",
            json={
                "installation_id": self.installation_id,
                "result": {
                    "call_id": call["id"],
                    "status": "succeeded",
                    "payload": payload,
                },
            },
            timeout=30,
        )
        response.raise_for_status()

    async def run(self, question: str) -> None:
        async with httpx.AsyncClient(timeout=httpx.Timeout(180.0)) as client:
            body = {
                "installation_id": self.installation_id,
                "user_text": question,
                "platform": "ios",
                "available_capabilities": [
                    "recall_memory",
                    "read_recent_entries",
                    "read_lab_results",
                    "read_health_signals",
                ],
            }
            async with client.stream("POST", f"{self.base}/v1/turn", json=body) as stream:
                event = ""
                async for line in stream.aiter_lines():
                    if line.startswith("event: "):
                        event = line[7:].strip()
                    elif line.startswith("data: "):
                        data = json.loads(line[6:])
                        if event == "tool_request":
                            self.waves += 1
                            # Parallel waves are answered concurrently, exactly as a real client
                            # should — a fast read must not wait behind a slow one.
                            await asyncio.gather(*(self._submit(client, c) for c in data["calls"]))
                        elif event == "answer":
                            self.answer = data["text"]
                        elif event == "error":
                            self.error = data["message"]
                        elif event == "done":
                            break

    def check(self) -> str:
        """Did this phone see only its own data? Reads the owner stamp back out of the answer."""
        if self.error:
            return f"ERROR {self.error}"
        others = [n for n in range(20) if n != self.owner and f"phone-{n}" in self.answer]
        if others:
            return f"CROSSED — saw phone-{others}"
        return "ok"


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8100")
    parser.add_argument("--phones", type=int, default=5)
    parser.add_argument("--question", default="How am I doing? Anything I should watch?")
    args = parser.parse_args()

    phones = [Phone(n, args.base) for n in range(args.phones)]
    print(f"{args.phones} phones -> {args.base}")
    start = time.time()
    await asyncio.gather(*(p.run(args.question) for p in phones))
    elapsed = time.time() - start

    print(f"\nall turns finished in {elapsed:.1f}s\n")
    print(f"{'phone':<10}{'waves':<7}{'tools run':<46}{'verdict'}")
    print("-" * 82)
    for p in phones:
        print(f"{p.installation_id:<10}{p.waves:<7}{', '.join(p.tools_run)[:44]:<46}{p.check()}")

    print("\nanswers (first 120 chars, each should reference only its own numbers):")
    for p in phones:
        print(f"  {p.installation_id}: {p.answer[:120].strip() or '(none)'}")

    crossed = [p for p in phones if p.check() != "ok"]
    print(
        "\n" + ("FAILED — " + str(len(crossed)) + " crossed" if crossed else "PASS — no crossover")
    )


if __name__ == "__main__":
    asyncio.run(main())
