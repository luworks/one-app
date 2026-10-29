#!/usr/bin/env python3
"""Bounded, synthetic Responses API comparison; no retries or product writes."""
import concurrent.futures, json, pathlib, re, statistics, sys, time, urllib.request
import run_open as prompts
import score_open as scoring
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tests.qa.journal import Journal, results_root
OUT = results_root() / 'luna-effort-20261029'
OUT.mkdir(parents=True, exist_ok=True)
if (OUT / 'raw.jsonl').exists():
    raise SystemExit('Existing paid run found; refusing another run under this budget.')
# Reserve $0.003 per request: input UTF-8 bytes upper-bound tokens plus 4096 output tokens.
# 61 cases x 2 repeats x 4 efforts = 488 requests, so select 16+8 cases for 192 requests.
# Use $0.0025 reservation with <=4000 input bytes and 4096 output tokens: <=$0.002448.
RESERVE = .0025
LIMIT = .49
MAX_OUTPUT = 4096
KEYFILE = pathlib.Path('/Users/yuanlu/code/one-app/.env')
KEY = re.search(r'sk-[A-Za-z0-9_-]+', KEYFILE.read_text()).group(0)
cases=[]
for name,mode,count in [('r4','full',16),('edit4','edit',8)]:
 suite=json.loads(prompts.FILES[name].read_text())
 # Evenly spaced deterministic sample, frozen before any calls.
 for i in [j*len(suite['cases'])//count for j in range(count)]:
  cases.append({'set':name,'mode':mode,'index':i,'case':suite['cases'][i]})
fixture=ROOT/'tests/fixtures/ai/luna-effort-20261029.json'
fixture.write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n')
rows=[]
journal=Journal(); session='luna-effort-20261029'
journal.record(session,'dev.eval.started','GPT-6 Luna four-effort synthetic eval; ceiling USD 0.49; no retries',status='started')
def call(job):
 effort,repeat,c=job
 system,schema=(prompts.full_instructions(),prompts.FULL_SCHEMA) if c['mode']=='full' else (prompts.edit_instructions(),prompts.EDIT_SCHEMA)
 schema=dict(schema,additionalProperties=False)
 body={'model':'gpt-6-luna','reasoning':{'effort':effort},'store':False,'max_output_tokens':MAX_OUTPUT,'instructions':system,'input':c['case']['input'],'text':{'format':{'type':'json_schema','name':'planner','strict':True,'schema':schema}}}
 # Conservative bound before dispatch; no tools, caching writes or long context.
 assert len((system+c['case']['input']+json.dumps(schema)).encode())<4000
 req=urllib.request.Request('https://api.openai.com/v1/responses',data=json.dumps(body).encode(),headers={'Authorization':'Bearer '+KEY,'Content-Type':'application/json'})
 t=time.monotonic(); row=dict(c,effort=effort,repeat=repeat)
 try:
  with urllib.request.urlopen(req,timeout=150) as response: raw=json.load(response)
  row['raw']=raw
  content=''.join(p.get('text','') for o in raw.get('output',[]) for p in o.get('content',[]) if p.get('type')=='output_text')
  parsed=json.loads(content); row['out']=parsed
  row['score']=scoring.score(c['case'],scoring.from_full(parsed)) if c['mode']=='full' else scoring.edit_score(c['case'],parsed,[])
 except Exception as e:
  row['error']=type(e).__name__; row['score']={'all':False}
 row['seconds']=time.monotonic()-t
 return row
jobs=[(effort,repeat,c) for repeat in range(2) for c in cases for effort in ['low','medium','high','xhigh']]
assert len(jobs)*RESERVE<=LIMIT
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for row in pool.map(call,jobs):
  rows.append(row)
  with (OUT/'raw.jsonl').open('a') as f: f.write(json.dumps(row,ensure_ascii=False)+'\n')
  if len(rows)%16==0: print('completed',len(rows),flush=True)
summary=[]
for effort in ['low','medium','high','xhigh']:
 r=[x for x in rows if x['effort']==effort]; usage=[x.get('raw',{}).get('usage',{}) for x in r]
 cost=sum(u.get('input_tokens',0)*.1/1e6+u.get('output_tokens',0)*.5/1e6 for u in usage)
 summary.append(dict(effort=effort,n=len(r),passed=sum(x['score']['all'] for x in r),errors=sum('error' in x for x in r),p50_seconds=statistics.median(x['seconds'] for x in r),input_tokens=sum(u.get('input_tokens',0) for u in usage),output_tokens=sum(u.get('output_tokens',0) for u in usage),reasoning_tokens=sum(u.get('output_tokens_details',{}).get('reasoning_tokens',0) for u in usage),usd=cost,usd_100_users_10_calls=cost/len(r)*1000))
(OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
journal.record(session,'dev.eval.completed',str(OUT),status='completed',props={'calls':len(rows),'reserved_usd':len(rows)*RESERVE,'usage_usd':sum(x['usd'] for x in summary)})
for artifact in [OUT/'raw.jsonl', OUT/'summary.json', fixture]:
 journal.artifact(session,artifact)
journal.close()
print(json.dumps(summary,indent=2))
