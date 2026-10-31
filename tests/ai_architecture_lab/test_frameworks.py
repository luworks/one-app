"""SDK integration checks with synthetic Responses, not model-quality tests."""
import asyncio
import copy
import json
from pathlib import Path
import tempfile
import unittest
from scripts.ai.architecture_lab.frameworks.adapters import ADAPTERS


TOOL = {"type": "function", "name": "read_state", "description": "Read synthetic state",
        "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False}}


def response(output, index=1):
    return {"id": f"resp_{index}", "object": "response", "created_at": 1,
            "model": "gpt-6-luna", "status": "completed", "output": output,
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15},
            "parallel_tool_calls": False, "tool_choice": "auto", "tools": [],
            "_gateway": {"request_id": f"offline-{index}", "status": "offline"}}


def message(text):
    return {"type": "message", "role": "assistant", "id": "msg_1", "status": "completed",
            "content": [{"type": "output_text", "text": text, "annotations": []}]}


class ScriptGateway:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.requests = []

    def handle(self, payload, *, synthetic):
        assert synthetic is True
        self.requests.append(copy.deepcopy(payload))
        return copy.deepcopy(next(self.responses))


class FrameworkTests(unittest.TestCase):
    def test_real_sdk_tool_feedback_and_restart(self):
        for name, cls in ADAPTERS.items():
            with self.subTest(framework=name), tempfile.TemporaryDirectory() as directory:
                call = {"type": "function_call", "id": "fc_1", "call_id": "call_1",
                        "name": "read_state", "arguments": "{}", "status": "completed"}
                from scripts.ai.architecture_lab.gateway import ReplayGateway
                gateway = ReplayGateway([response([call]), response([message("Preview only")], 2),
                                         response([message("Still preview only")], 3)], allowed_tools=["read_state"])
                calls = []
                def dispatch(tool, arguments):
                    calls.append((tool, arguments))
                    return {"revision": 7, "receipt": None, "task_id": "stable-task-1"}
                first = cls(gateway, [TOOL], dispatch, Path(directory))
                self.assertEqual(asyncio.run(first.run("durable-session", "Inspect task")), "Preview only")
                self.assertEqual(calls, [("read_state", {})])
                self.assertIn("stable-task-1", json.dumps(gateway.requests[1]))
                self.assertIn("function_call_output", json.dumps(gateway.requests[1]))
                second = cls(gateway, [TOOL], dispatch, Path(directory))
                self.assertEqual(asyncio.run(second.run("durable-session", "What about it?")), "Still preview only")
                self.assertIn("stable-task-1", json.dumps(gateway.requests[2]))
                self.assertEqual(first.gateway_request_ids, ["offline-1", "offline-2"])
                for request in gateway.requests:
                    self.assertEqual(request["model"], "gpt-6-luna")
                    self.assertEqual(request["reasoning"], {"effort": "medium"})
                    self.assertFalse(request["store"])

    def test_common_world_receipts_controls_and_restart(self):
        from scripts.ai.architecture_lab.frameworks.runner import CandidateRunner
        from scripts.ai.architecture_lab.gateway import ReplayGateway
        from scripts.ai.architecture_lab.schemas import TOOLS
        from scripts.ai.architecture_lab.world import values
        arguments = {"base_revision": 1, "proposal_id": None,
                     "changes": [{"op": "update", "target_id": "r-report", "expected_version": 1,
                                  "values": values(title="Report", due="2026-11-03T17:00:00-08:00", calendar="work")}],
                     "reason": "User requested Tuesday"}
        call = {"type": "function_call", "id": "fc_1", "call_id": "call_1",
                "name": "propose_changes", "arguments": json.dumps(arguments), "status": "completed"}
        for name in ADAPTERS:
            with self.subTest(framework=name), tempfile.TemporaryDirectory() as directory:
                gateway = ReplayGateway([response([call]), response([message("Review Tuesday")]),
                                         response([message("Applied with receipt")])],
                                        allowed_tools=[tool["name"] for tool in TOOLS])
                runner = CandidateRunner(name, gateway, directory)
                def event(kind, **fields):
                    return {"session_id": "planner-session", "event": {"type": kind, **fields}}
                preview = asyncio.run(runner.handle(event("user", text="Move Report to Tuesday")))
                self.assertIsNone(preview["error"])
                self.assertEqual(preview["state"]["revision"], 1)
                self.assertEqual(preview["proposals"][0]["status"], "pending")
                applied = asyncio.run(runner.handle(event("apply", arguments={"proposal_id": "p-0001", "version": 1, "approval_id": "tap-1"})))
                self.assertEqual(applied["receipts"][0]["status"], "applied")
                restarted = CandidateRunner(name, gateway, directory)
                asyncio.run(restarted.handle(event("restart")))
                answer = asyncio.run(restarted.handle(event("user", text="Did it save?")))
                self.assertIsNone(answer["error"])
                self.assertIn("receipt-0001", json.dumps(gateway.requests[-1]))
                for payload in gateway.requests:
                    self.assertEqual(payload["tools"], TOOLS)
                undone = asyncio.run(restarted.handle(event("undo", arguments={"receipt_id": "receipt-0001", "approval_id": "tap-undo"})))
                self.assertEqual(undone["receipts"][0]["status"], "undone")
                self.assertEqual(undone["state"]["entities"]["r-report"]["due"], "2026-11-02T17:00:00-08:00")

    def test_revised_cards_outside_changes_and_unknown_apply(self):
        from scripts.ai.architecture_lab.frameworks.runner import CandidateRunner
        from scripts.ai.architecture_lab.gateway import ReplayGateway
        from scripts.ai.architecture_lab.schemas import TOOLS
        from scripts.ai.architecture_lab.world import values
        arguments = {"base_revision": 1, "proposal_id": None,
                     "changes": [{"op": "update", "target_id": "r-report", "expected_version": 1,
                                  "values": values(title="Report", due="2026-11-03", calendar="work")}],
                     "reason": "User requested Tuesday"}
        call = {"type": "function_call", "id": "fc_1", "call_id": "call_1",
                "name": "propose_changes", "arguments": json.dumps(arguments), "status": "completed"}
        for name in ADAPTERS:
            for outcome in ("external_update", "unknown"):
                with self.subTest(framework=name, outcome=outcome), tempfile.TemporaryDirectory() as directory:
                    gateway = ReplayGateway([response([call]), response([message("Review")])], allowed_tools=[t["name"] for t in TOOLS])
                    runner = CandidateRunner(name, gateway, directory)
                    def run(kind, **fields):
                        return asyncio.run(runner.handle({"session_id": "s", "event": {"type": kind, **fields}}))
                    self.assertIsNone(run("user", text="Move Report")["error"])
                    revised = copy.deepcopy(arguments)
                    revised["proposal_id"] = "p-0001"
                    revised["changes"][0]["values"]["due"] = "2026-11-04"
                    self.assertEqual(run("card_edit", arguments=revised)["proposals"][0]["version"], 2)
                    stale = run("apply", arguments={"proposal_id": "p-0001", "version": 1, "approval_id": "old-tap"})
                    self.assertIsNotNone(stale["error"])
                    if outcome == "external_update":
                        run("external_update", arguments={"entity_id": "r-report", "values": values(title="Report", due="2026-11-05", calendar="work")})
                    else:
                        run("failure_mode", mode="unknown")
                    result = run("apply", arguments={"proposal_id": "p-0001", "version": 2, "approval_id": "new-tap"})
                    self.assertFalse(result["state"]["receipts"])
                    if outcome == "unknown":
                        self.assertEqual(result["receipts"][0]["status"], "unknown")
                        self.assertEqual(run("restart")["proposals"][0]["status"], "unknown")
                    else:
                        self.assertIsNotNone(result["error"])
                        self.assertEqual(result["state"]["entities"]["r-report"]["due"], "2026-11-05")

    def test_invalid_tool_output_is_model_feedback(self):
        from scripts.ai.architecture_lab.gateway import ReplayGateway
        for name, cls in ADAPTERS.items():
            with self.subTest(framework=name), tempfile.TemporaryDirectory() as directory:
                call = {"type": "function_call", "id": "fc_1", "call_id": "call_1",
                        "name": "read_state", "arguments": "{}", "status": "completed"}
                gateway = ReplayGateway([response([call]), response([message("Need a fresh revision")])], allowed_tools=["read_state"])
                def dispatch(*args):
                    raise ValueError("Stale world revision")
                adapter = cls(gateway, [TOOL], dispatch, Path(directory))
                self.assertEqual(asyncio.run(adapter.run("s", "inspect")), "Need a fresh revision")
                self.assertIn("Stale world revision", json.dumps(gateway.requests[1]))

    def test_no_automatic_retry_on_gateway_failure(self):
        for name, cls in ADAPTERS.items():
            with self.subTest(framework=name), tempfile.TemporaryDirectory() as directory:
                class FailingGateway:
                    calls = 0
                    def handle(self, payload, *, synthetic):
                        self.calls += 1
                        raise RuntimeError("Unknown outcome; retain reservation")
                gateway = FailingGateway()
                adapter = cls(gateway, [TOOL], lambda *args: {}, Path(directory))
                with self.assertRaises(Exception):
                    asyncio.run(adapter.run("session", "Hello"))
                self.assertEqual(gateway.calls, 1)


if __name__ == "__main__":
    unittest.main()
