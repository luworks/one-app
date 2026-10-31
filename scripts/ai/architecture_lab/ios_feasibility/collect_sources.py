"""Retain bounded public primary-source snapshots; never call model providers."""
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import urllib.request

OUT = Path('/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/ios-feasibility')
SOURCES = {
 'apple-review': 'https://developer.apple.com/app-store/review/guidelines/',
 'apple-security': 'https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web',
 'apple-background': 'https://developer.apple.com/tutorials/data/documentation/backgroundtasks/choosing-background-strategies-for-your-app.json',
 'apple-continued': 'https://developer.apple.com/tutorials/data/documentation/backgroundtasks/bgcontinuedprocessingtask.json',
 'apple-javascriptcore': 'https://developer.apple.com/tutorials/data/documentation/javascriptcore.json',
 'apple-jscontext': 'https://developer.apple.com/tutorials/data/documentation/javascriptcore/jscontext.json',
 'apple-eventkit': 'https://developer.apple.com/tutorials/data/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui.json',
 'apple-alarmkit': 'https://developer.apple.com/tutorials/data/documentation/alarmkit.json',
 'apple-alarmmanager': 'https://developer.apple.com/tutorials/data/documentation/alarmkit/alarmmanager.json',
 'apple-fm-tool': 'https://developer.apple.com/tutorials/data/documentation/foundationmodels/tool.json',
 'apple-fm-stream': 'https://developer.apple.com/tutorials/data/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.json',
 'cpython-ios': 'https://docs.python.org/3.14/using/ios.html',
 'cpython-wasi': 'https://docs.python.org/3.14/library/intro.html',
 'quickjs': 'https://bellard.org/quickjs/quickjs.html',
 'wasmtime-platforms': 'https://docs.wasmtime.dev/stability-platform-support.html',
 'wasmtime-pulley': 'https://docs.wasmtime.dev/pulley.html',
 'pi-ai-registry': 'https://registry.npmjs.org/@mariozechner/pi-ai/latest',
 'pi-core-registry': 'https://registry.npmjs.org/@mariozechner/pi-agent-core/latest',
 'swift-openai-head': 'https://api.github.com/repos/MacPaw/OpenAI/commits/main',
 'swift-anylanguage-head': 'https://api.github.com/repos/mattt/AnyLanguageModel/commits/main',
 'swift-agents-head': 'https://api.github.com/repos/1amageek/SwiftAgents/commits/main',
 'quickjs-emscripten-registry': 'https://registry.npmjs.org/quickjs-emscripten/latest',
}

def fetch(item):
 name, url = item
 entry = dict(name=name, url=url, retrieved_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 try:
  request = urllib.request.Request(url, headers={'User-Agent':'Today-Luna-Architecture-Research/1.0','Accept':'application/json,text/html,*/*'})
  with urllib.request.urlopen(request, timeout=45) as response:
   data = response.read(12_000_000)
   entry.update(status=response.status, final_url=response.url, bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
   (OUT / 'sources' / (name + ('.json' if url.endswith(('.json','latest','main')) else '.html'))).write_bytes(data)
 except Exception as error:
  entry['error'] = str(error)
 return entry

if __name__ == '__main__':
 (OUT / 'sources').mkdir(parents=True, exist_ok=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  entries = list(pool.map(fetch, SOURCES.items()))
 (OUT / 'source-manifest.json').write_text(json.dumps(entries, indent=2)+'\n')
 for entry in entries:
  print(entry['name'], entry.get('status', entry.get('error')), entry.get('bytes',''))
