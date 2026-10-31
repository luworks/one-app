"""JSONL shim for actual SDK candidates. CLI is offline-only until paid review.

python -m scripts.ai.architecture_lab.frameworks.runner --framework agents \
    --storage /persistent/results/session --replay /persistent/results/responses.json

Request: {"session_id":"stable-key","event":{"type":"user","text":"..."}}
Controls: {"type":"apply|undo|external_update|card_edit","arguments":{...}},
{"type":"restart"}, {"type":"failure_mode","mode":"offline|429|timeout|unknown"}.
Controls are trusted synthetic harness events, never model tools.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
from pathlib import Path
import resource
import sys
import time

from .adapters import ADAPTERS
from .state import PlannerState
from ..schemas import TOOLS
from ..world import PlannerWorld


class CandidateRunner:
    def __init__(self, framework, gateway, storage, evidence_kind="offline_scripted"):
        self.framework = framework
        self.gateway = gateway
        self.storage = Path(storage)
        self.storage.mkdir(parents=True, exist_ok=True)
        self.evidence_kind = evidence_kind

    async def handle(self, request):
        started = time.perf_counter()
        session_id = request["session_id"]
        if not isinstance(session_id, str) or not session_id or len(session_id) > 512:
            raise ValueError("A bounded durable session key is required")
        directory = self.storage / hashlib.sha256(session_id.encode()).hexdigest()
        directory.mkdir(parents=True, exist_ok=True)
        snapshot_path = directory / "world.json"
        world = PlannerWorld.from_snapshot(json.loads(snapshot_path.read_text())) if snapshot_path.exists() else PlannerWorld()
        pending_path = directory / "control-feedback.json"
        pending = json.loads(pending_path.read_text()) if pending_path.exists() else []
        event = request["event"]
        before = PlannerState.model_validate(world.snapshot()).model_dump()
        receipts = []
        adapter = ADAPTERS[self.framework](self.gateway, TOOLS, world.dispatch, directory)
        reply = ""
        error = None
        try:
            kind = event["type"]
            if kind == "user":
                feedback = "\nTrusted harness control outcomes: " + json.dumps(pending) if pending else ""
                reply = await adapter.run(session_id, event["text"] + feedback)
                pending = []
            elif kind in ("apply", "undo", "external_update"):
                result = getattr(world, kind)(**event["arguments"])
                pending.append({"type": kind, "result": result})
                if kind in ("apply", "undo"):
                    receipts.append(result)
            elif kind == "card_edit":
                result = world.dispatch("propose_changes", event["arguments"])
                pending.append({"type": kind, "result": result})
            elif kind == "restart":
                pending.append({"type": "restart", "status": "restored"})
            elif kind == "failure_mode":
                state = world.snapshot()
                mode = event.get("mode")
                if mode not in (None, "offline", "429", "timeout", "unknown"):
                    raise ValueError("Unknown failure mode")
                state["failure_mode"] = mode
                world = PlannerWorld.from_snapshot(state)
            else:
                raise ValueError("Unknown harness event")
        except Exception as exception:
            error = {"type": type(exception).__name__, "message": str(exception)}
        finally:
            state = PlannerState.model_validate(world.snapshot()).model_dump()
            for path, value in ((snapshot_path, state), (pending_path, pending)):
                temporary = path.with_suffix(".tmp")
                temporary.write_text(json.dumps(value, ensure_ascii=False))
                temporary.replace(path)
        events = adapter.events + state["events"][len(before["events"]):]
        if error:
            events.append({"type": "candidate_error", **error})
        return {"session_id": session_id, "reply": reply,
                "proposals": list(state["proposals"].values()), "state": state,
                "receipts": receipts, "events": events,
                "gateway_request_ids": adapter.gateway_request_ids,
                "metrics": {"model_calls": len(adapter.requests),
                            "tool_calls": sum(e["type"] == "tool_started" for e in adapter.events),
                            "elapsed_seconds": time.perf_counter() - started,
                            "request_json_bytes": sum(len(json.dumps(p).encode()) for p in adapter.requests),
                            "process_peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss},
                "evidence_kind": self.evidence_kind, "error": error}


async def main_async():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework", required=True, choices=ADAPTERS)
    parser.add_argument("--storage", type=Path, required=True)
    parser.add_argument("--replay", type=Path, required=True, help="Scripted Responses JSON array; no paid CLI")
    parser.add_argument("--transcript", type=Path, help="Retain synthetic gateway request JSONL")
    args = parser.parse_args()
    from ..gateway import ReplayGateway
    gateway = ReplayGateway(json.loads(args.replay.read_text()), allowed_tools=[tool["name"] for tool in TOOLS])
    runner = CandidateRunner(args.framework, gateway, args.storage)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            result = await runner.handle(request)
        except Exception as error:
            result = {"error": {"type": type(error).__name__, "message": str(error)},
                      "evidence_kind": "offline_scripted"}
        print(json.dumps(result, ensure_ascii=False), flush=True)
        if args.transcript:
            args.transcript.parent.mkdir(parents=True, exist_ok=True)
            args.transcript.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in gateway.requests))


def main():
    os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
