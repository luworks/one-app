import { Agent } from '@earendil-works/pi-agent-core';
import { mkdirSync, readFileSync, existsSync, writeFileSync, renameSync, openSync, fsyncSync, closeSync, appendFileSync, rmdirSync } from 'node:fs';
import { join } from 'node:path';
import { MODEL, gatewayStream } from './transport.mjs';

export class PiSession {
  constructor({sessionId, directory, gateway, tools, world, evidenceKind = 'offline_scripted', emit = () => {}}) {
    if (!/^[a-zA-Z0-9_-]{1,100}$/.test(sessionId)) throw new Error('Invalid session_id');
    mkdirSync(directory, {recursive: true});
    this.id = sessionId; this.file = join(directory, `${sessionId}.json`);
    this.log = join(directory, `${sessionId}.events.jsonl`); this.lock = `${this.file}.lock`;
    mkdirSync(this.lock); // Fail closed on concurrent writer or uncertain crashed owner.
    try {
      this.saved = existsSync(this.file) ? JSON.parse(readFileSync(this.file, 'utf8')) : {};
      if (this.saved.version && this.saved.version !== 1) throw new Error('Unknown snapshot version');
      if (this.saved.inFlight) throw new Error('Interrupted run requires harness recovery; no silent replay');
      this.world = world; this.world?.restore?.(this.saved.world);
      this.evidenceKind = this.saved.evidence_kind ?? evidenceKind; this.callCount = 0; this.events = []; this.ids = [];
      this.gatewayMetrics = []; this.emit = emit;
      this.agent = new Agent({sessionId, toolExecution: 'sequential',
        initialState: {model: MODEL, thinkingLevel: 'medium',
          systemPrompt: 'You are a synthetic Today planner. Read canonical tools for facts. Changes are proposals only. Never claim applied without a harness receipt. Keep meetings fixed unless explicitly requested. Ask when ambiguous.',
          messages: this.saved.messages ?? [], tools},
        streamFn: gatewayStream(async (payload, signal) => {
          if (++this.callCount > 12) throw new Error('Per-prompt gateway call limit reached');
          return gateway(payload, signal);
        }, response => {
          if (response._gateway?.status !== 'offline_scripted') this.evidenceKind = 'paid';
          if (response._gateway?.request_id) this.ids.push(response._gateway.request_id);
          this.gatewayMetrics.push({...response._gateway?.metrics, usage_known: Boolean(response.usage)});
        }),
      });
      this.agent.subscribe(event => {
        const normalized = {type: event.type, native: structuredClone(event)};
        this.events.push(normalized); appendFileSync(this.log, JSON.stringify(normalized) + '\n');
        this.emit({session_id: this.id, event: normalized});
        if (event.type === 'message_end' || event.type === 'agent_end') this.persist(true);
      });
    } catch (error) {rmdirSync(this.lock); throw error;}
  }
  persist(inFlight) {
    const snapshot = {version: 1, session_id: this.id, messages: this.agent.state.messages,
      world: this.world?.snapshot?.() ?? null, evidence_kind: this.evidenceKind, inFlight};
    const temporary = `${this.file}.tmp`;
    writeFileSync(temporary, JSON.stringify(snapshot));
    const fd = openSync(temporary, 'r'); try {fsyncSync(fd);} finally {closeSync(fd);}
    renameSync(temporary, this.file);
    if (existsSync(this.log)) {
      const log = openSync(this.log, 'r'); try {fsyncSync(log);} finally {closeSync(log);}
    }
    const dir = openSync(join(this.file, '..'), 'r'); try {fsyncSync(dir);} finally {closeSync(dir);}
  }
  async prompt(text) {
    this.events = []; this.ids = []; this.gatewayMetrics = []; this.callCount = 0; this.persist(true);
    const start = performance.now(); await this.agent.prompt(text); this.persist(false);
    const messages = this.agent.state.messages;
    const last = messages.findLast(m => m.role === 'assistant');
    return {session_id: this.id,
      reply: last?.content.filter(c => c.type === 'text').map(c => c.text).join('\n') ?? '',
      proposals: this.world?.proposals?.() ?? [], state: this.world?.state?.() ?? {},
      receipts: this.world?.receipts?.() ?? [], events: this.events,
      gateway_request_ids: this.ids,
      metrics: {latency_ms: performance.now() - start, gateway: this.gatewayMetrics,
        context_bytes: Buffer.byteLength(JSON.stringify(messages)), rss_bytes: process.memoryUsage().rss},
      evidence_kind: this.evidenceKind, error: last?.errorMessage ?? null};
  }
  close() {rmdirSync(this.lock);}
}
