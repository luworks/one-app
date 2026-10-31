import { createInterface } from 'node:readline';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { PiSession } from './session.mjs';
import { WorldBinding } from './world.mjs';
import { httpGateway } from './transport.mjs';

export async function main() {
  const {values} = parseArgs({options: {
    'gateway-url': {type: 'string'}, 'capability-file': {type: 'string'},
    'session-dir': {type: 'string', default: '/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/pi/sessions'},
    'stream-events': {type: 'boolean', default: false},
  }});
  if (!values['gateway-url'] || !values['capability-file']) throw new Error('--gateway-url and --capability-file are required');
  const gateway = httpGateway(values['gateway-url'], readFileSync(values['capability-file'], 'utf8').trim());
  for await (const line of createInterface({input: process.stdin, crlfDelay: Infinity})) {
    let request; let session;
    try {
      request = JSON.parse(line);
      if (!/^[a-zA-Z0-9_-]{1,100}$/.test(request.session_id)) throw new Error('Invalid session_id');
      const file = join(values['session-dir'], `${request.session_id}.json`);
      const snapshot = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
      const world = new WorldBinding(snapshot.world);
      session = new PiSession({sessionId: request.session_id, directory: values['session-dir'], gateway,
        tools: world.tools(), world, emit: values['stream-events'] ? event => console.log(JSON.stringify(event)) : undefined});
      const event = request.event;
      let output;
      if (event?.type === 'user') output = await session.prompt(event.text);
      else {
        const result = world.control(event?.type, event?.arguments ?? {});
        session.agent.state.messages.push({role: 'user', timestamp: Date.now(),
          content: `Harness action result (authoritative): ${JSON.stringify({type: event.type, result})}`});
        session.persist(false);
        output = {session_id: request.session_id, reply: '', proposals: world.proposals(), state: world.state(),
          receipts: world.receipts(), events: [{type: 'harness_control', control: event.type, result}],
          gateway_request_ids: [], metrics: {}, evidence_kind: session.evidenceKind};
      }
      console.log(JSON.stringify(output));
    } catch (error) {
      console.log(JSON.stringify({session_id: request?.session_id ?? null, reply: '', proposals: [], state: {},
        receipts: [], events: [], gateway_request_ids: [], metrics: {}, evidence_kind: 'offline_scripted', error: error.message}));
    } finally {session?.close();}
  }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch(error => {console.error(error.message); process.exitCode = 1;});
