"""Gateway safety tests. Fake transports never open a provider socket."""
import concurrent.futures
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

from scripts.ai.architecture_lab.gateway import (
    Account, DEADLINE, Gateway, MODEL, Rejected, ReplayGateway, server, validate,
)

PAYLOAD = {"model": MODEL, "input": "Synthetic planner fixture", "max_output_tokens": 64}


def response(usage=True):
    result = {"id": "resp-synthetic", "model": MODEL, "service_tier": "default", "status": "completed", "output": []}
    if usage:
        result["usage"] = {"input_tokens": 10, "output_tokens": 3, "total_tokens": 13}
    return result


class FakeGateway(Gateway):
    def __init__(self, account, result=None, **kwargs):
        super().__init__(account, **kwargs)
        self.result = result
        self.calls = 0

    def _key(self):
        return "synthetic-secret-never-a-real-key"

    def _dispatch(self, raw, key, timeout):
        self.calls += 1
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "budget.sqlite"
        self.now = [DEADLINE - 100]

    def tearDown(self):
        self.temp.cleanup()

    def account(self, cap=20_000_000_000):
        return Account(self.path, cap=cap, clock=lambda: self.now[0])

    def test_concurrent_cap_across_independent_connections(self):
        _, raw, bound, reserve = validate(PAYLOAD)
        account = self.account(cap=reserve * 3)
        def attempt(_):
            other = Account(self.path, cap=reserve * 3, clock=lambda: self.now[0])
            try:
                return other.reserve(raw, bound, 64, reserve)
            except Rejected:
                return None
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            results = list(pool.map(attempt, range(50)))
        self.assertEqual(sum(r is not None for r in results), 3)
        self.assertEqual(account.snapshot()["charged_nusd"], reserve * 3)

    def test_deadline_before_reserve_and_between_reserve_dispatch(self):
        account = self.account()
        self.now[0] = DEADLINE
        gateway = FakeGateway(account, response())
        with self.assertRaises(Rejected):
            gateway.handle(PAYLOAD, synthetic=True)
        self.assertEqual(gateway.calls, 0)
        self.assertEqual(account.snapshot()["requests"], [])
        self.now[0] = DEADLINE - 1
        original = account.reserve
        def reserve_then_expire(*args):
            rid = original(*args)
            self.now[0] = DEADLINE
            return rid
        account.reserve = reserve_then_expire
        with self.assertRaises(Rejected):
            gateway.handle(PAYLOAD, synthetic=True)
        self.assertEqual(gateway.calls, 0)
        self.assertEqual(account.snapshot()["requests"][0]["status"], "unknown")

    def test_failed_missing_invalid_usage_and_restart_keep_reservations(self):
        for result in (TimeoutError("synthetic-secret-never-a-real-key"), response(False),
                       dict(response(), usage={"input_tokens": -1, "output_tokens": 1, "total_tokens": 0})):
            account = self.account()
            before = account.snapshot()["charged_nusd"]
            gateway = FakeGateway(account, result)
            try:
                gateway.handle(PAYLOAD, synthetic=True)
            except Rejected as exc:
                self.assertNotIn("secret", str(exc))
            after = self.account().snapshot()
            self.assertGreater(after["charged_nusd"], before)
            self.assertEqual(after["requests"][-1]["status"], "unknown")
            # Invalid provider usage latches the account, unlike a transport error.
            with account.connect() as db:
                db.execute("UPDATE policy SET halted=0 WHERE id=1")

    def test_restart_reserved_survives_and_policy_cannot_expand(self):
        account = self.account()
        _, raw, bound, reserve = validate(PAYLOAD)
        rid = account.reserve(raw, bound, 64, reserve)
        self.assertEqual(self.account().snapshot()["charged_nusd"], reserve)
        self.assertEqual(self.account().snapshot()["requests"][0]["request_id"], rid)
        with self.assertRaises(Rejected):
            Account(self.path, cap=1)

    def test_valid_usage_settles_conservatively_and_retries_count(self):
        gateway = FakeGateway(self.account(), response())
        ids = [gateway.handle(PAYLOAD, synthetic=True)["_gateway"]["request_id"] for _ in range(3)]
        self.assertEqual(len(set(ids)), 3)
        self.assertEqual(gateway.calls, 3)
        self.assertEqual(gateway.account.snapshot()["charged_nusd"], 3 * (10 * 125 + 3 * 500))

    def test_model_tier_tools_remote_payload_and_no_unpaid_bypass(self):
        gateway = FakeGateway(self.account(), response())
        for patch in ({"model": "gpt-other"}, {"service_tier": "priority"},
                      {"tools": [{"type": "web_search"}]}, {"previous_response_id": "resp-other"},
                      {"input": [{"type": "input_image", "image_url": "https://example.invalid"}]},
                      {"max_output_tokens": 4097}, {"input": "x" * 262145}):
            with self.assertRaises(Rejected):
                gateway.handle(dict(PAYLOAD, **patch), synthetic=True)
        with self.assertRaises(Rejected):
            gateway.handle(PAYLOAD)
        with self.assertRaisesRegex(Rejected, "paid_evaluation_pending"):
            Gateway(self.account()).handle(PAYLOAD, synthetic=True)
        self.assertEqual(gateway.calls, 0)
        self.assertEqual(self.account().snapshot()["requests"], [])

    def test_secret_echo_never_logged_or_returned(self):
        gateway = FakeGateway(self.account(), dict(response(), output=[{"text": "synthetic-secret-never-a-real-key"}]))
        with self.assertRaises(Rejected) as caught:
            gateway.handle(PAYLOAD, synthetic=True)
        self.assertNotIn("secret", str(caught.exception))
        with gateway.account.connect() as db:
            raw = repr(db.execute("SELECT * FROM requests").fetchall())
        self.assertNotIn("synthetic-secret-never-a-real-key", raw)

    def test_key_file_requires_explicit_review_and_safe_permissions(self):
        path = Path(self.temp.name) / "synthetic-key"
        path.write_text("synthetic-file-key")
        path.chmod(0o644)
        gateway = Gateway(self.account(), authorized_key_file=path, paid_reviewed=True)
        with self.assertRaises(Rejected):
            gateway._key()
        path.chmod(0o600)
        self.assertEqual(gateway._key(), "synthetic-file-key")
        gateway.paid_reviewed = False
        with self.assertRaises(Rejected):
            gateway._key()

    def test_http_capability_and_synthetic_header_no_network_replay(self):
        replay = ReplayGateway([response()])
        http = server(replay, "local-capability")
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{http.server_port}/v1/responses"
        try:
            for headers in ({}, {"Authorization": "Bearer local-capability"}):
                with self.assertRaises(urllib.error.HTTPError):
                    urllib.request.urlopen(urllib.request.Request(url, data=json.dumps(PAYLOAD).encode(), headers=headers))
            headers = {"Authorization": "Bearer local-capability", "X-Lab-Synthetic": "true"}
            with urllib.request.urlopen(urllib.request.Request(url, data=json.dumps(PAYLOAD).encode(), headers=headers)) as res:
                result = json.load(res)
            self.assertEqual(result["_gateway"]["status"], "offline_scripted")
            self.assertEqual(result["_gateway"]["metrics"]["network_attempts"], 0)
            self.assertEqual(len(replay.requests), 1)
        finally:
            http.shutdown()
            http.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
