/** Linux-only portability probes of installed Pi packages; no network/model calls. */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
const out = '/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/ios-feasibility';
const require = createRequire(path.join(out, 'package.json'));
const { getQuickJS } = require('quickjs-emscripten');
const pi = await import(path.join(out, 'node_modules/@earendil-works/pi-agent-core/dist/index.js'));
const aiDist = path.join(out, 'node_modules/@earendil-works/pi-ai/dist');
await import(path.join(aiDist, 'index.js'));
const result = { host: { node: process.version, platform: process.platform }, import: { Agent: typeof pi.Agent, agentLoop: typeof pi.agentLoop }, bundles: {}, packageVersions: {core:'1.4.0',ai:'1.4.0',quickjsEmscripten:'0.32.0',esbuild:'0.27.4'},modelCalls: 0 };
const probe = `import { Agent } from '@earendil-works/pi-agent-core';
import { AssistantMessageEventStream, Type } from '@earendil-works/pi-ai';
export async function runProbe() {
 const events = []; let calls = 0; let toolExecutions = 0;
 const model = { id: 'offline-synthetic', api: 'offline', provider: 'offline', cost: {input:0,output:0,cacheRead:0,cacheWrite:0}, contextWindow:1000, maxTokens:1000 };
 const streamFn = () => {
  calls++;
  const message = {role:'assistant', api:'offline',provider:'offline',model:model.id,timestamp:0,
    content: calls === 1 ? [{type:'toolCall', id:'call-1', name:'read_state', arguments:{}}] : [{type:'text',text:'A draft is ready.'}],
    stopReason: calls === 1 ? 'toolUse' : 'stop',
    usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
  const stream = new AssistantMessageEventStream();
  stream.push({type:'start',partial:{...message,content:[]}});
  stream.push({type:'done',reason:message.stopReason,message}); stream.end(message); return stream;
 };
 const agent = new Agent({initialState:{model,tools:[{name:'read_state',label:'Read state',description:'Read synthetic state',parameters:Type.Object({}),execute:async()=>{ toolExecutions++;return {content:[{type:'text',text:'{"revision":1}'}],details:{revision:1}}; }}]},streamFn});
 agent.subscribe(event=>events.push(event.type));
 await agent.prompt('Inspect the synthetic planner.');
 const checkpoint = JSON.parse(JSON.stringify(agent.state.messages));
 const restarted = new Agent({initialState:{model,messages:checkpoint},streamFn});
 return {calls,toolExecutions,events,errors:checkpoint.filter(m=>m.errorMessage || m.isError).map(m=>m.errorMessage||m.content),messageCount:checkpoint.length,restartedMessageCount:restarted.state.messages.length,hasProcess:typeof process,hasFetch:typeof fetch};
}
`;
fs.writeFileSync(path.join(out,'probe-entry.mjs'),probe);
for (const mode of ['stock']) {
 try {
  const args = ['probe-entry.mjs','--bundle','--platform=browser','--format=iife','--global-name=PiProbe','--target=es2022','--minify', '--outfile='+mode+'.bundle.js','--metafile='+mode+'.metafile.json'];
  execFileSync(path.join(out,'node_modules/@esbuild/linux-x64/bin/esbuild'),args,{cwd:out,stdio:['ignore','pipe','pipe']});
  const code=fs.readFileSync(path.join(out,mode+'.bundle.js'),'utf8');
  const metafile=JSON.parse(fs.readFileSync(path.join(out,mode+'.metafile.json'),'utf8'));
  const record=result.bundles[mode]={built:true,bytes:Buffer.byteLength(code),inputs:Object.keys(metafile.inputs).length,dynamicImports:(code.match(/import\(/g)||[]).length};
  try {
   const context=vm.createContext({structuredClone,AbortController,TextEncoder,TextDecoder,performance,console:{log(){},error(){}},setTimeout,clearTimeout});
   vm.runInContext(code,context,{timeout:10000}); record.vm=await context.PiProbe.runProbe();
  }catch(e){record.vmError=String(e);}
 }catch(e){result.bundles[mode]={built:false,errors:[e.stderr?.toString()||String(e)]};}
}
fs.writeFileSync(path.join(out,'bundle-results.json'),JSON.stringify(result,null,2));
const QuickJS=await getQuickJS(); const runtime=QuickJS.newRuntime();
runtime.setMemoryLimit(64*1024*1024);runtime.setMaxStackSize(1024*1024);
let ticks=0;runtime.setInterruptHandler(()=>++ticks>100000); const ctx=runtime.newContext();
const capabilities=ctx.evalCode('JSON.stringify({Promise:typeof Promise,fetch:typeof fetch,AbortController:typeof AbortController,TextEncoder:typeof TextEncoder,structuredClone:typeof structuredClone,WebAssembly:typeof WebAssembly,process:typeof process,setTimeout:typeof setTimeout})');
result.quickjs={capabilities:JSON.parse(ctx.getString(capabilities.value))};capabilities.value.dispose();
const code=fs.readFileSync(path.join(out,'stock.bundle.js'),'utf8');
for (const mode of ['bare','synthetic-host-bridges']) {
 const bridge = mode==='bare' ? '' : `
 globalThis.performance = {now:()=>0};
 globalThis.structuredClone = value => JSON.parse(JSON.stringify(value));
 globalThis.TextEncoder = class { encode(value='') { const s=unescape(encodeURIComponent(value));return Uint8Array.from(s,c=>c.charCodeAt(0)); }};
 globalThis.TextDecoder = class { decode(value=new Uint8Array()) {return decodeURIComponent(escape(String.fromCharCode(...value))); }};
 globalThis.AbortController = class { constructor(){this.signal={aborted:false,addEventListener(){},removeEventListener(){}}} abort(){this.signal.aborted=true;} };
 `;
 const evaluation=ctx.evalCode(bridge+code+'; PiProbe.runProbe()');
 const observed=result.quickjs[mode]={};
 if(evaluation.error){observed.error=ctx.dump(evaluation.error);evaluation.error.dispose();}
 else{
  const promise=evaluation.value;
  for(let i=0;i<100;i++) {
   const jobs=runtime.executePendingJobs();if(jobs.error){observed.jobError=ctx.dump(jobs.error);jobs.error.dispose();break;}
   const state=ctx.getPromiseState(promise);
   if(state.type==='fulfilled'){observed.result=ctx.dump(state.value);state.value.dispose();break;}
   if(state.type==='rejected'){observed.rejection=ctx.dump(state.error);state.error.dispose();break;}
  }
  promise.dispose();
 }
}
ctx.dispose();runtime.dispose();
fs.writeFileSync(path.join(out,'portability-results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));

for (const observed of [result.bundles.stock.vm,result.quickjs['synthetic-host-bridges'].result]) { if(observed?.calls!==2 || observed?.toolExecutions!==1 || observed?.messageCount!==4 || observed?.restartedMessageCount!==4 || observed?.errors.length) throw new Error('Offline Pi loop did not complete the expected synthetic journey'); }
