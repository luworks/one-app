#!/usr/bin/env python3
"""Loopback-only GPT-6 Luna medium relay for owned-simulator evaluation.

Not a public production gateway. Keeps the OpenAI key on the Mac, fixes model and
reasoning, disables response storage/tools/retries, and persists a dollar cap.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.request
import uuid

MODEL = 'gpt-6-luna'
MAX_BYTES = 24000
MAX_OUTPUT = 4096
PRIOR_USD = 0.0181991


class Budget:
    def __init__(self, path, limit=0.50):
        self.path, self.limit = path, limit
        self.lock = threading.Lock()
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS calls (id TEXT PRIMARY KEY, stage TEXT, started REAL, '
                       'status TEXT, reserved REAL, cost REAL, input_tokens INTEGER, output_tokens INTEGER, '
                       'reasoning_tokens INTEGER, seconds REAL, input_hash TEXT)')

    def connect(self):
        return sqlite3.connect(self.path, timeout=10)

    def reserve(self, stage, payload):
        # UTF-8 bytes conservatively bound token count, including request/schema overhead.
        reserve = (len(payload) * 0.10 + MAX_OUTPUT * 0.50) / 1e6
        with self.lock, self.connect() as db:
            used = db.execute('SELECT COALESCE(SUM(COALESCE(cost,reserved)),0) FROM calls').fetchone()[0]
            if PRIOR_USD + used + reserve > self.limit:
                raise ValueError('evaluation_budget_exhausted')
            ident = str(uuid.uuid4())
            db.execute('INSERT INTO calls (id,stage,started,status,reserved,input_hash) VALUES (?,?,?,?,?,?)',
                       (ident, stage[:160], time.time(), 'pending', reserve, hashlib.sha256(payload).hexdigest()))
            return ident

    def finish(self, ident, status, seconds, usage=None):
        usage = usage or {}
        inp, out = usage.get('input_tokens'), usage.get('output_tokens')
        cost = (inp * .10 + out * .50) / 1e6 if inp is not None and out is not None else None
        reasoning = usage.get('output_tokens_details', {}).get('reasoning_tokens')
        # Unknown/failed calls retain the reservation, including after a restart.
        with self.lock, self.connect() as db:
            db.execute('UPDATE calls SET status=?,cost=?,input_tokens=?,output_tokens=?,reasoning_tokens=?,seconds=? '
                       'WHERE id=?', (status, cost, inp, out, reasoning, seconds, ident))


def prepare(body):
    if not isinstance(body, dict) or not isinstance(body.get('instructions'), str):
        raise ValueError('invalid_instructions')
    if not isinstance(body.get('input'), str) or not body['input'].strip():
        raise ValueError('invalid_input')
    fmt = body.get('text', {}).get('format', {})
    if fmt.get('type') != 'json_schema' or fmt.get('strict') is not True:
        raise ValueError('strict_schema_required')
    if not isinstance(fmt.get('schema'), dict):
        raise ValueError('invalid_schema')
    return {'model': MODEL, 'reasoning': {'effort': 'medium'}, 'store': False,
            'max_output_tokens': MAX_OUTPUT, 'instructions': body['instructions'],
            'input': body['input'], 'text': {'format': fmt}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request bodies, credentials, or user text.

    def reply(self, code, body):
        data = json.dumps(body).encode()
        try:
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        self.reply(200 if self.path == '/health' else 404,
                   {'model': MODEL, 'effort': 'medium', 'scope': 'loopback-simulator-only'})

    def do_POST(self):
        if self.path != '/v1/responses':
            return self.reply(404, {'error': 'not_found'})
        if self.headers.get('X-Today-Development') != 'simulator':
            return self.reply(403, {'error': 'simulator_only'})
        try:
            count = int(self.headers.get('Content-Length', '0'))
            if not 0 < count <= MAX_BYTES:
                raise ValueError('request_size')
            body = prepare(json.loads(self.rfile.read(count)))
            payload = json.dumps(body, ensure_ascii=False).encode()
            if len(payload) > MAX_BYTES:
                raise ValueError('request_size')
            ident = self.server.budget.reserve(self.headers.get('X-Today-Stage', 'unknown') + ':' + self.headers.get('X-Today-Request-ID', ''), payload)
        except (ValueError, TypeError, AttributeError):
            return self.reply(400, {'error': 'invalid_request_or_budget_exhausted'})
        start = time.monotonic()
        request = urllib.request.Request('https://api.openai.com/v1/responses', data=payload,
                                        headers={'Authorization': 'Bearer ' + self.server.api_key,
                                                 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                result = json.load(response)
            self.server.budget.finish(ident, result.get('status', 'unknown'), time.monotonic()-start,
                                      result.get('usage'))
            self.reply(200, result)
        except Exception as error:
            outcome = f'upstream_http_{error.code}' if isinstance(error, urllib.error.HTTPError) else 'upstream_error'
            self.server.budget.finish(ident, outcome, time.monotonic()-start)
            self.reply(502, {'error': 'upstream_error', 'request_id': ident})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', required=True, type=Path)
    parser.add_argument('--results', required=True, type=Path)
    parser.add_argument('--port', default=8789, type=int)
    args = parser.parse_args()
    match = re.search(r'^OPENAI_API_KEY\s*=\s*[\"\']?(sk-[A-Za-z0-9_-]+)', args.key_file.read_text(), re.MULTILINE)
    if not match:
        raise SystemExit('No API key in the selected file')
    args.results.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.api_key = match.group(1)
    server.budget = Budget(args.results / 'usage.sqlite')
    print(f'Loopback GPT relay ready on 127.0.0.1:{args.port}; fixed {MODEL}/medium; cumulative cap USD 0.50', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
