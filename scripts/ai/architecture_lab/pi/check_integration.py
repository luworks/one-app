"""Offline integration evidence using the real Pi process, canonical world and shared ReplayGateway."""
import json
from pathlib import Path
import subprocess
import threading
import unittest
import uuid

from scripts.ai.architecture_lab.gateway import ReplayGateway, server
from scripts.ai.architecture_lab.schemas import TOOLS
from scripts.ai.architecture_lab.world import values

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path('/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/pi')


def message(text):
    return {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': text}]}


def response(*output):
    return {'id': 'offline-response', 'status': 'completed', 'output': list(output),
            'usage': {'input_tokens': 0, 'output_tokens': 0, 'total_tokens': 0}}


def call(name, arguments, cid):
    return {'type': 'function_call', 'call_id': cid, 'name': name, 'arguments': json.dumps(arguments)}


class PiIntegration(unittest.TestCase):
    def test_real_core_shared_gateway_world_restart_apply_undo(self):
        directory = EVIDENCE / ('integration-' + uuid.uuid4().hex)
        directory.mkdir(parents=True)
        capability_file = directory / 'capability'
        capability_file.write_text('offline-local-capability')
        capability_file.chmod(0o600)
        proposal = dict(base_revision=1, proposal_id=None, reason='Explicit synthetic reminder request',
                        changes=[dict(op='create', target_id=None, expected_version=None,
                                      values=values(title='Read architecture report', due='2026-11-02T18:00:00-08:00'))])
        responses = [
            response(call('read_state', {}, 'read-1')),
            response(call('propose_changes', proposal, 'propose-1')),
            response(message('Preview ready. Apply when you choose.')),
            response(message('The harness applied the reminder.')),
        ]
        (directory / 'scripted-responses.json').write_text(json.dumps(responses, indent=2))
        gateway = ReplayGateway(responses, allowed_tools=[t['name'] for t in TOOLS])
        http = server(gateway, 'offline-local-capability', port=0)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()

        def run(events):
            command = ['node', str(ROOT / 'scripts/ai/architecture_lab/pi/adapter.mjs'),
                       '--gateway-url', f'http://127.0.0.1:{http.server_port}/v1/responses',
                       '--capability-file', str(capability_file), '--session-dir', str(directory)]
            result = subprocess.run(command, cwd=ROOT, input=''.join(json.dumps({'session_id': 'journey', 'event': e}) + '\n' for e in events),
                                    text=True, capture_output=True, timeout=30, check=True)
            with (directory / 'stdout.jsonl').open('a') as stream:
                stream.write(result.stdout)
            with (directory / 'stderr.log').open('a') as stream:
                stream.write(result.stderr)
            outputs = [json.loads(line) for line in result.stdout.splitlines()]
            for output in outputs:
                self.assertFalse(output.get('error'), output.get('error'))
            return outputs
        try:
            first, = run([{'type': 'user', 'text': 'Prepare a reminder to read the architecture report on November 2 at 6 PM.'}])
            self.assertEqual(first['state']['revision'], 1)
            self.assertEqual(len(first['state']['entities']), 5)
            self.assertEqual(first['proposals'][0]['status'], 'pending')
            self.assertEqual(len(first['gateway_request_ids']), 3)
            self.assertTrue(any(event['type'] == 'tool_execution_end' for event in first['events']))
            applied, followup = run([
                {'type': 'apply', 'arguments': {'proposal_id': 'p-0001', 'version': 1, 'approval_id': 'ui-apply-1'}},
                {'type': 'user', 'text': 'What happened?'}])
            self.assertEqual(applied['state']['revision'], 2)
            self.assertEqual(len(applied['state']['entities']), 6)
            self.assertEqual(followup['receipts'][0]['status'], 'applied')
            self.assertTrue(any('Harness action result' in json.dumps(item) for item in gateway.requests[-1]['input']))
            undone, = run([{'type': 'undo', 'arguments': {'receipt_id': 'receipt-0001', 'approval_id': 'ui-undo-1'}}])
            self.assertEqual(undone['state']['revision'], 3)
            self.assertEqual(len(undone['state']['entities']), 5)
            self.assertTrue(undone['receipts'][0]['undone'])
            (directory / 'gateway-requests.json').write_text(json.dumps(gateway.requests, indent=2))
            (directory / 'summary.json').write_text(json.dumps({'evidence_kind': 'offline_scripted',
                'checks': ['real_core', 'canonical_tools', 'tool_feedback', 'restart', 'proposal_no_write',
                           'apply_receipt', 'receipt_feedback', 'undo'], 'model_calls': len(gateway.requests),
                'paid_calls': 0, 'directory': str(directory)}, indent=2))
            print('Retained integration evidence:', directory)
        finally:
            http.shutdown()
            http.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
