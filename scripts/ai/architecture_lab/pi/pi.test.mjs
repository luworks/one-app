import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Type } from 'typebox';
import { PiSession } from './session.mjs';
import { httpGateway } from './transport.mjs';

const evidence = '/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/pi';
function directory() { return mkdtempSync(join(evidence, 'test-session-')); }
function result(output, id = 'offline-1') {
  return {status: 'completed', output, _gateway: {request_id: id, status: 'offline_scripted', metrics: {}}};
}
const text = value => ({type: 'message', role: 'assistant', content: [{type: 'output_text', text: value}]});

test('actual Pi loop validates tools, feeds results back, streams events, persists and restarts', async () => {
  const path = directory(); let calls = 0; const requests = [];
  const tools = [{name: 'read_state', label: 'Read synthetic state', description: 'Test-only state reader',
    parameters: Type.Object({}), execute: async () => {calls++; return {content: [{type: 'text', text: '{"revision":7}'}], details: {revision: 7}};}}];
  let step = 0;
  const gateway = async payload => {
    requests.push(payload); step++;
    if (step === 1) return result([{type: 'function_call', call_id: 'call_state', name: 'read_state', arguments: '{}'}]);
    if (step === 2) {
      assert.ok(payload.input.some(item => item.type === 'function_call_output' && item.output.includes('7')));
      return result([text('Revision is 7.')], 'offline-2');
    }
    assert.ok(payload.input.some(item => item.role === 'assistant'));
    return result([text('The earlier state was revision 7.')], 'offline-3');
  };
  let session = new PiSession({sessionId: 'restart', directory: path, gateway, tools});
  try {
    const output = await session.prompt('Read state');
    assert.equal(calls, 1); assert.equal(output.reply, 'Revision is 7.');
    assert.ok(output.events.some(e => e.type === 'tool_execution_end'));
    assert.ok(output.events.some(e => e.native.assistantMessageEvent?.type === 'text_delta'));
    assert.deepEqual(output.gateway_request_ids, ['offline-1', 'offline-2']);
    assert.equal(requests[0].model, 'gpt-6-luna');
    assert.deepEqual(requests[0].reasoning, {effort: 'medium'});
    assert.equal(requests[0].store, false);
    assert.throws(() => new PiSession({sessionId: 'restart', directory: path, gateway, tools}));
  } finally {session.close();}
  session = new PiSession({sessionId: 'restart', directory: path, gateway, tools});
  try {
    const output = await session.prompt('What was the earlier revision?');
    assert.match(output.reply, /revision 7/);
    assert.equal(calls, 1);
    assert.equal(JSON.parse(readFileSync(join(path, 'restart.json'))).inFlight, false);
  } finally {session.close();}
});

test('actual Pi rejects unknown tools and gives errors back to provider', async () => {
  let n = 0; const gateway = async payload => {
    if (++n === 1) return result([{type: 'function_call', call_id: 'bad', name: 'bash', arguments: '{"command":"true"}'}]);
    assert.ok(payload.input.some(item => item.type === 'function_call_output' && /not found/i.test(item.output)));
    return result([text('Tool unavailable.')]);
  };
  const session = new PiSession({sessionId: 'denied', directory: directory(), gateway, tools: []});
  try {assert.equal((await session.prompt('Try a forbidden tool')).reply, 'Tool unavailable.');}
  finally {session.close();}
});

test('incomplete or malformed gateway responses fail without tool execution', async () => {
  for (const response of [{status: 'incomplete', output: []}, result([{type: 'function_call', call_id: 'broken', name: 'read_state', arguments: '{'}])]) {
    const session = new PiSession({sessionId: 'failure', directory: directory(), gateway: async () => response, tools: []});
    try {assert.ok((await session.prompt('test')).error);}
    finally {session.close();}
  }
});

test('gateway transport rejects remote endpoints and absent capability', () => {
  assert.throws(() => httpGateway('https://api.openai.com/v1/responses', 'dummy'));
  assert.throws(() => httpGateway('http://localhost:8080/v1/responses', 'dummy'));
  assert.throws(() => httpGateway('http://127.0.0.1:8080/v1/responses', ''));
});

test('actual Pi schema validation returns malformed tool arguments as feedback', async () => {
  let calls = 0; let n = 0;
  const tools = [{name: 'entity_detail', label: 'Detail', description: 'Test-only reader',
    parameters: Type.Object({entity_id: Type.String()}),
    execute: async () => {calls++; return {content: [], details: {}};}}];
  const gateway = async payload => {
    if (++n === 1) return result([{type: 'function_call', call_id: 'invalid', name: 'entity_detail', arguments: '{}'}]);
    assert.ok(payload.input.some(item => item.type === 'function_call_output' && /entity_id/.test(item.output)));
    return result([text('Please supply the stable entity ID.')]);
  };
  const session = new PiSession({sessionId: 'validation', directory: directory(), gateway, tools});
  try {assert.match((await session.prompt('Get details')).reply, /stable entity ID/); assert.equal(calls, 0);}
  finally {session.close();}
});

test('repeated native Pi tool continuation stops at the adapter call bound', async () => {
  let n = 0;
  const gateway = async () => result([{type: 'function_call', call_id: `again${++n}`, name: 'unknown', arguments: '{}'}]);
  const session = new PiSession({sessionId: 'bounded', directory: directory(), gateway, tools: []});
  try {assert.match((await session.prompt('Loop')).error, /call limit/); assert.equal(n, 12);}
  finally {session.close();}
});
