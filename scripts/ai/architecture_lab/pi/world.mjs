import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
export class WorldBinding {
  constructor(snapshot = null, python = process.env.LAB_PYTHON ?? 'python3') {
    this.value = snapshot; this.python = python;
  }
  request(request) {
    const child = spawnSync(this.python, ['-m', 'scripts.ai.architecture_lab.world'], {
      cwd: root, input: JSON.stringify({...request, state: this.value}) + '\n',
      encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
    });
    if (child.status !== 0) throw new Error(`Canonical world process failed: ${child.stderr}`);
    const output = JSON.parse(child.stdout);
    if (output.error) throw new Error(`${output.error}: ${output.message}`);
    this.value = output.state;
    return output.result;
  }
  tools() {
    return this.request({control: 'schemas'}).map(schema => ({
      name: schema.name, label: schema.name, description: schema.description,
      parameters: schema.parameters,
      execute: async (_id, parameters) => {
        const result = this.request({tool: schema.name, arguments: parameters});
        return {content: [{type: 'text', text: JSON.stringify(result)}], details: result};
      },
    }));
  }
  restore(snapshot) {if (snapshot) this.value = snapshot;}
  snapshot() {return this.value;}
  state() {return this.value ?? {};}
  proposals() {return Object.values(this.value?.proposals ?? {});}
  receipts() {return this.value?.receipts ?? [];}
  control(type, args) {
    if (!['apply', 'undo', 'external_update'].includes(type)) throw new Error('Unknown harness control');
    return this.request({control: type, arguments: args});
  }
}
