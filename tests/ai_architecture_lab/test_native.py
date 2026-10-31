import json
from pathlib import Path
import tempfile
import unittest

from scripts.ai.architecture_lab.gateway import MODEL, ReplayGateway
from scripts.ai.architecture_lab.native.runner import CANDIDATES, CandidateRunner, SessionStore
from scripts.ai.architecture_lab.schemas import TOOL_SCHEMAS
from scripts.ai.architecture_lab.scheduling import schedule
from scripts.ai.architecture_lab.world import values


def wire(output):
    return {"id": "resp-test", "status": "completed", "model": MODEL, "service_tier": "default", "output": output}


def message(text):
    return {"type": "message", "id": "msg-test", "role": "assistant", "status": "completed",
            "content": [{"type": "output_text", "text": text, "annotations": []}]}


def call(name, args, cid):
    return {"type": "function_call", "id": "fc-" + cid, "call_id": cid, "name": name,
            "arguments": json.dumps(args), "status": "completed"}


def responses(candidate):
    proposal = {"base_revision": 1, "proposal_id": None, "reason": "Synthetic preview",
                "changes": [{"op": "create", "target_id": None, "expected_version": None,
                             "values": values(title="Synthetic task", due="2026-11-02T14:00:00-08:00")}]}
    if candidate == "responses":
        return [wire([{"type": "reasoning", "id": "reason-1", "summary": [], "encrypted_content": "synthetic-encrypted"}, call("read_state", {}, "c1")]),
                wire([call("propose_changes", proposal, "c2")]), wire([message("Preview ready.")])]
    return [wire([message(json.dumps({"reply": "", "memory": "Keep task at 14:00", "calls": [{"name": name, "arguments_json": json.dumps(args)}]}))])
            for name, args in (("read_state", {}), ("propose_changes", proposal))] + [wire([message(json.dumps({"reply": "Preview ready.", "memory": "Keep task at 14:00", "calls": []}))])]


class NativeTests(unittest.TestCase):
    def test_same_tools_propose_apply_restart_undo_for_all(self):
        with tempfile.TemporaryDirectory() as directory:
            for candidate in CANDIDATES:
                with self.subTest(candidate=candidate):
                    gateway = ReplayGateway(responses(candidate), allowed_tools=[t["name"] for t in TOOL_SCHEMAS])
                    path = Path(directory) / (candidate + ".sqlite")
                    runner = CandidateRunner(candidate, gateway, path)
                    output = runner.handle({"session_id": "s", "event": {"type": "user", "text": "Prepare synthetic task at 14:00 on Nov 2."}})
                    self.assertEqual(output["reply"], "Preview ready.")
                    self.assertEqual(len(output["state"]["entities"]), 5)
                    self.assertEqual(output["metrics"]["model_calls"], 3)
                    self.assertEqual(output["metrics"]["tool_calls"], 2)
                    self.assertFalse(output["metrics"]["usage_complete"])
                    applied = runner.handle({"session_id": "s", "event": {"type": "apply", "arguments": {"proposal_id": "p-0001", "version": 1, "approval_id": "tap-1"}}})
                    self.assertEqual(len(applied["state"]["entities"]), 6)
                    restored = CandidateRunner(candidate, gateway, path)
                    readback = restored.handle({"session_id": "s", "event": {"type": "restart"}})
                    self.assertEqual(readback["state"], applied["state"])
                    undone = restored.handle({"session_id": "s", "event": {"type": "undo", "arguments": {"receipt_id": "receipt-0001", "approval_id": "tap-2"}}})
                    self.assertEqual(len(undone["state"]["entities"]), 5)
                    if candidate == "responses":
                        history = gateway.requests[1]["input"]
                        self.assertEqual(history[1]["type"], "reasoning")
                        self.assertEqual(history[1]["encrypted_content"], "synthetic-encrypted")
                        self.assertEqual(history[-1]["call_id"], "c1")
                    elif candidate == "structured":
                        state = json.loads(gateway.requests[1]["input"][0]["content"])
                        self.assertEqual(state["retained_memory"], "Keep task at 14:00")
                        self.assertIn("Prepare synthetic task", state["latest_user"]["content"])

    def test_text_history_bound_and_process_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            gateway = ReplayGateway([wire([message(json.dumps({"reply": "ok", "memory": "", "calls": []}))])] * 10)
            path = Path(directory) / "sessions.sqlite"
            for i in range(10):
                runner = CandidateRunner("text8", gateway, path)
                runner.handle({"session_id": "s", "event": {"type": "user", "text": "synthetic " + str(i)}})
            self.assertEqual(len(gateway.requests[-1]["input"]), 8)
            self.assertNotIn("synthetic 0", json.dumps(gateway.requests[-1]["input"]))

    def test_inflight_failure_cannot_silently_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sessions.sqlite"
            gateway = ReplayGateway([], allowed_tools=[t["name"] for t in TOOL_SCHEMAS])
            runner = CandidateRunner("responses", gateway, path)
            request = {"session_id": "s", "event": {"type": "user", "text": "Synthetic"}}
            with self.assertRaises(StopIteration):
                runner.handle(request)
            with self.assertRaisesRegex(ValueError, "unresolved"):
                CandidateRunner("responses", gateway, path).handle(request)

    def test_independent_reproducible_balanced_order(self):
        candidates = list(CANDIDATES)
        tasks = schedule(["dev-a", "dev-b"], candidates, seed=123, repetitions=3)
        self.assertEqual(tasks, schedule(["dev-a", "dev-b"], candidates, seed=123, repetitions=3))
        self.assertNotEqual(tasks, schedule(["dev-a", "dev-b"], candidates, seed=124, repetitions=3))
        for case in ("dev-a", "dev-b"):
            for candidate in candidates:
                self.assertEqual(sorted(t["position"] for t in tasks if t["case_id"] == case and t["candidate"] == candidate), [0, 1, 2])


if __name__ == "__main__":
    unittest.main()
