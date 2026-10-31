"""Fail-closed Responses gateway and durable experiment account (stdlib only).

Money is integer nano-USD. Unknown outcomes never release reservations. The HTTP
surface has no remote URL, credentials, built-in tools, or automatic retry API.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
from contextlib import contextmanager
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import sqlite3
import stat
import threading
import time
import urllib.request
import uuid

MODEL = "gpt-6-luna"
DEADLINE = datetime(2026, 10, 31, 18, 37, 40, tzinfo=timezone.utc).timestamp()
CAP_NUSD = 20_000_000_000
MAX_BYTES = 262_144
MAX_OUTPUT = 4096
MAX_RESPONSE_BYTES = 4_194_304
EVIDENCE = Path("/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/harness")
# Upper rate for all input, including cache writes; no cache discount is assumed.
INPUT_RATE = 125
OUTPUT_RATE = 500
ALLOWED_KEYS = {"model", "input", "instructions", "tools", "tool_choice", "parallel_tool_calls",
                "max_output_tokens", "reasoning", "text", "service_tier", "store", "stream",
                "include", "metadata", "truncation"}


class Rejected(ValueError):
    """Public errors carry no provider exception or credential material."""


def encode(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")


def validate(payload, allowed_tools=()):
    if not isinstance(payload, dict) or set(payload) - ALLOWED_KEYS:
        raise Rejected("unsupported_request_fields")
    body = copy.deepcopy(payload)
    if body.get("model") != MODEL:
        raise Rejected("invalid_model")
    if body.get("service_tier", "default") != "default":
        raise Rejected("invalid_service_tier")
    if body.get("store", False) is not False or body.get("stream", False) is not False:
        raise Rejected("store_and_stream_must_be_false")
    limit = body.get("max_output_tokens", 2048)
    if type(limit) is not int or not 1 <= limit <= MAX_OUTPUT:
        raise Rejected("invalid_output_limit")
    if body.get("reasoning", {"effort": "medium"}) != {"effort": "medium"}:
        raise Rejected("invalid_reasoning")
    if "input" not in body or not isinstance(body["input"], (str, list)):
        raise Rejected("invalid_input")
    # No remotely dereferenced images, files, URLs or previous-response state.
    def inspect(value):
        if isinstance(value, dict):
            if "type" in value and value["type"] not in {"message", "input_text", "output_text", "function_call", "function_call_output", "reasoning", "refusal", "summary_text"}:
                raise Rejected("non_text_input")
            if any(k in value for k in ("image_url", "file_url", "file_id", "server_url")):
                raise Rejected("remote_content_forbidden")
            for child in value.values():
                inspect(child)
        elif isinstance(value, list):
            for child in value:
                inspect(child)
    inspect(body.get("input"))
    tools = body.get("tools", [])
    if not isinstance(tools, list) or len(tools) > 16:
        raise Rejected("invalid_tools")
    for tool in tools:
        if not isinstance(tool, dict) or tool.get("type") != "function" or tool.get("name") not in allowed_tools:
            raise Rejected("unapproved_tool")
    body.update(max_output_tokens=limit, service_tier="default", store=False, stream=False,
                reasoning={"effort": "medium"})
    raw = encode(body)
    if len(raw) > MAX_BYTES:
        raise Rejected("payload_too_large")
    # Byte bound covers every transmitted field and tool schema; a deliberately
    # large framing allowance also covers SDK serialization and hidden framing.
    # Paid admission still requires review against the provider's model contract.
    input_bound = len(raw) * 4 + 1_048_576 + len(tools) * 4096
    return body, raw, input_bound, input_bound * INPUT_RATE + limit * OUTPUT_RATE


class Account:
    def __init__(self, path, *, cap=CAP_NUSD, deadline=DEADLINE, clock=time.time):
        if type(cap) is not int or not 0 < cap <= CAP_NUSD or deadline > DEADLINE:
            raise Rejected("invalid_account_limits")
        self.path, self.cap, self.deadline, self.clock = Path(path), cap, deadline, clock
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS policy (id INTEGER PRIMARY KEY CHECK(id=1), cap INTEGER,
                    deadline REAL, halted INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, created REAL,
                    reserve INTEGER NOT NULL, charge INTEGER NOT NULL, status TEXT NOT NULL,
                    input_bound INTEGER, output_bound INTEGER, request BLOB NOT NULL,
                    response BLOB, metrics TEXT);
            """)
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT cap, deadline FROM policy WHERE id=1").fetchone()
            if row is None:
                db.execute("INSERT INTO policy(id,cap,deadline) VALUES (1,?,?)", (cap, deadline))
            elif tuple(row) != (cap, deadline):
                raise Rejected("account_policy_mismatch")
        os.chmod(self.path, 0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=30)
        db.execute("PRAGMA busy_timeout=30000")
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=FULL")
        try:
            with db:
                yield db
        finally:
            db.close()

    def reserve(self, raw, input_bound, output_bound, reserve):
        if (type(input_bound) is not int or input_bound < 1 or type(output_bound) is not int
                or not 1 <= output_bound <= MAX_OUTPUT or type(reserve) is not int
                or reserve != input_bound * INPUT_RATE + output_bound * OUTPUT_RATE):
            raise Rejected("invalid_reservation")
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            halted = db.execute("SELECT halted FROM policy WHERE id=1").fetchone()[0]
            if halted or self.clock() >= self.deadline:
                raise Rejected("halted_or_deadline")
            charged = db.execute("SELECT COALESCE(SUM(charge),0) FROM requests").fetchone()[0]
            if charged + reserve > self.cap:
                raise Rejected("budget_exhausted")
            rid = "lab-" + uuid.uuid4().hex
            db.execute("INSERT INTO requests VALUES (?,?,?,?,?,?,?,?,?,?)",
                       (rid, self.clock(), reserve, reserve, "reserved", input_bound, output_bound, raw, None, None))
        return rid

    def finish(self, rid, response, metrics):
        raw = encode(response)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT reserve,input_bound,output_bound,status FROM requests WHERE id=?", (rid,)).fetchone()
            if row is None or row[3] != "reserved":
                raise Rejected("invalid_settlement")
            valid = False
            try:
                usage = response["usage"]
                i, o = usage["input_tokens"], usage["output_tokens"]
                total = usage["total_tokens"]
                valid = all(type(v) is int and v >= 0 for v in (i, o, total)) and total == i + o
                valid = valid and i <= row[1] and o <= row[2]
                for field, bound in (("input_tokens_details", i), ("output_tokens_details", o)):
                    details = usage.get(field, {})
                    valid = valid and isinstance(details, dict)
                    if isinstance(details, dict):
                        valid = valid and all(type(v) is int and 0 <= v <= bound for v in details.values())
                valid = valid and response.get("service_tier") == "default" and response.get("model") == MODEL
                valid = valid and response.get("status") in ("completed", "incomplete") and not response.get("error")
            except (KeyError, TypeError):
                valid = False
            charge = i * INPUT_RATE + o * OUTPUT_RATE if valid else row[0]
            # Charge input at cache-write rate even when actual usage is ordinary
            # input. This deliberately overstates spend and cannot release too much.
            status = "settled_conservative" if valid else "unknown"
            db.execute("UPDATE requests SET charge=?,status=?,response=?,metrics=? WHERE id=?",
                       (charge, status, raw, json.dumps(metrics), rid))
            if not valid:
                db.execute("UPDATE policy SET halted=1 WHERE id=1")
        return status, charge

    def unknown(self, rid, metrics):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("UPDATE requests SET status='unknown',metrics=? WHERE id=? AND status='reserved'",
                       (json.dumps(metrics), rid))
            # Unknown results retain their full reservation; other bounded calls
            # remain admissible until the remaining cap is consumed.

    def snapshot(self):
        with self.connect() as db:
            rows = db.execute("SELECT id,reserve,charge,status,metrics FROM requests ORDER BY created").fetchall()
            halted = bool(db.execute("SELECT halted FROM policy WHERE id=1").fetchone()[0])
        return {"cap_nusd": self.cap, "charged_nusd": sum(r[2] for r in rows), "halted": halted,
                "requests": [{"request_id": r[0], "reserved_nusd": r[1], "charged_nusd": r[2],
                              "status": r[3], "metrics": json.loads(r[4]) if r[4] else {}} for r in rows]}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Rejected("provider_redirect_forbidden")


class Gateway:
    def __init__(self, account, *, allowed_tools=(), authorized_key_file=None, paid_reviewed=False):
        self.account, self.allowed_tools = account, tuple(allowed_tools)
        self.key_file, self.paid_reviewed = authorized_key_file, paid_reviewed

    def _key(self):
        if not self.paid_reviewed or self.key_file is None:
            raise Rejected("paid_evaluation_pending")
        # No environment fallback; symlinks and group/world-readable keys fail.
        fd = os.open(self.key_file, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise Rejected("unsafe_key_file")
            key = os.read(fd, 4097).decode().strip()
            if not key or len(key) > 4096 or any(c.isspace() for c in key):
                raise Rejected("invalid_key_file")
            return key
        finally:
            os.close(fd)

    def _dispatch(self, raw, key, timeout):
        # Fixed origin, no proxy environment, no redirects, no SDK retries.
        request = urllib.request.Request("https://api.openai.com/v1/responses", data=raw,
                    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"}, method="POST")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(request, timeout=timeout) as response:
            result = response.read(MAX_RESPONSE_BYTES + 1)
        if len(result) > MAX_RESPONSE_BYTES:
            raise Rejected("provider_response_too_large")
        return json.loads(result)

    def handle(self, payload, *, synthetic=False):
        if synthetic is not True:
            raise Rejected("synthetic_only")
        body, raw, input_bound, reserve = validate(payload, self.allowed_tools)
        key = self._key()  # Absent credentials never dispatch or create false spend.
        if key.encode() in raw:
            raise Rejected("credential_in_payload")
        rid = self.account.reserve(raw, input_bound, body["max_output_tokens"], reserve)
        started = time.perf_counter()
        metrics = {"transmitted_bytes": len(raw), "reserved_nusd": reserve, "network_attempts": 0}
        try:
            remaining = self.account.deadline - self.account.clock()
            if remaining <= 0:
                raise Rejected("deadline_before_dispatch")
            metrics["network_attempts"] = 1
            result = self._dispatch(raw, key, min(60, remaining))
            # Provider output is untrusted; never forward echoed credentials.
            if key.encode() in encode(result):
                raise Rejected("provider_secret_echo")
            metrics["latency_ms"] = (time.perf_counter() - started) * 1000
            status, charge = self.account.finish(rid, result, metrics)
            metrics["charged_nusd"] = charge
            result["_gateway"] = {"request_id": rid, "status": status, "metrics": metrics}
            return result
        except Exception:
            metrics["latency_ms"] = (time.perf_counter() - started) * 1000
            self.account.unknown(rid, metrics)
            raise Rejected("unknown_provider_outcome:" + rid) from None


class ReplayGateway:
    """Scripted wire responses only: no credentials, account or network path."""
    def __init__(self, responses, *, allowed_tools=()):
        self.responses = iter(copy.deepcopy(responses))
        self.allowed_tools = tuple(allowed_tools)
        self.requests = []
        self.lock = threading.Lock()

    def handle(self, payload, *, synthetic=False):
        if synthetic is not True:
            raise Rejected("synthetic_only")
        _, raw, _, _ = validate(payload, self.allowed_tools)
        with self.lock:
            result = next(self.responses)
            self.requests.append(json.loads(raw))
            rid = "offline-" + str(len(self.requests))
        result["_gateway"] = {"request_id": rid, "status": "offline_scripted",
                              "metrics": {"transmitted_bytes": len(raw), "network_attempts": 0}}
        return result


def server(gateway, capability, *, port=0):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            try:
                if self.path != "/v1/responses":
                    raise Rejected("invalid_route")
                if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + capability):
                    raise Rejected("invalid_local_capability")
                if self.headers.get("X-Lab-Synthetic") != "true":
                    raise Rejected("synthetic_only")
                length = int(self.headers.get("Content-Length", "-1"))
                if not 0 < length <= MAX_BYTES:
                    raise Rejected("invalid_content_length")
                self.connection.settimeout(5)
                payload = json.loads(self.rfile.read(length))
                result = gateway.handle(payload, synthetic=True)
                raw = encode(result)
                self.send_response(200)
                self.send_header("x-request-id", result["_gateway"]["request_id"])
            except Exception as exc:
                code = str(exc) if isinstance(exc, Rejected) else "invalid_request"
                raw = encode({"error": {"message": code, "type": "lab_gateway_rejected"}})
                self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay", type=Path, required=True, help="JSON array of scripted Responses; offline only")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--capability-file", type=Path, required=True)
    args = parser.parse_args()
    from .schemas import TOOL_SCHEMAS
    names = [tool["name"] for tool in TOOL_SCHEMAS]
    capability = secrets.token_urlsafe(32)
    fd = os.open(args.capability_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(capability)
    instance = server(ReplayGateway(json.loads(args.replay.read_text()), allowed_tools=names), capability, port=args.port)
    print(json.dumps({"base_url": f"http://127.0.0.1:{instance.server_port}/v1", "evidence_kind": "offline_scripted"}), flush=True)
    try:
        instance.serve_forever()
    finally:
        instance.server_close()


if __name__ == "__main__":
    main()
