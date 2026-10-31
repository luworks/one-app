"""Linux Node dependency/import observations; never an iOS benchmark."""
import json
from pathlib import Path
import platform
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path('/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/pi')
CORE = ROOT / 'scripts/ai/architecture_lab/pi'
FULL = EVIDENCE / 'full-coding-agent'
PROGRAM = """
const start = performance.now();
try {
  await import(process.argv[1]);
  const import_ms = performance.now() - start;
  const rss_bytes = process.memoryUsage().rss;
  await new Promise(resolve => setTimeout(resolve, 100));
  console.log(JSON.stringify({ok:true, import_ms, rss_bytes, idle_rss_bytes:process.memoryUsage().rss,
    max_rss_kib:process.resourceUsage().maxRSS}));
} catch(error) {
  console.log(JSON.stringify({ok:false, import_ms:performance.now()-start, error:error.message}));
  process.exitCode=1;
}
"""


def footprint(directory):
    paths = [p for p in (directory / 'node_modules').rglob('*') if p.is_file()]
    lock = json.loads((directory / 'package-lock.json').read_text())
    return {'file_bytes': sum(p.stat().st_size for p in paths), 'files': len(paths),
            'lock_packages_excluding_root': len(lock['packages']) - 1,
            'install_scripts': 'disabled (--ignore-scripts)', 'lockfile': str(directory / 'package-lock.json')}


def main():
    result = {'evidence_kind': 'linux_node_observation', 'platform': platform.platform(),
              'node': subprocess.check_output(['node', '--version'], text=True).strip(),
              'source_sha': '35dfa757378bd7a8570670e99c2687bdd1039a06', 'samples': {}}
    for name, directory, module in [('empty', CORE, 'node:path'),
                                    ('ai', CORE, '@earendil-works/pi-ai'),
                                    ('agent_core', CORE, '@earendil-works/pi-agent-core'),
                                    ('coding_agent', FULL, '@earendil-works/pi-coding-agent')]:
        samples = []
        for _ in range(5):
            start = time.perf_counter()
            p = subprocess.run(['node', '--input-type=module', '-e', PROGRAM, module], cwd=directory,
                               capture_output=True, text=True, timeout=30)
            sample = json.loads(p.stdout)
            sample.update(exit_code=p.returncode, wall_ms=(time.perf_counter()-start)*1000, stderr=p.stderr)
            samples.append(sample)
        result['samples'][name] = samples
    result['footprint'] = {'core_with_ai': footprint(CORE), 'full_coding_agent': footprint(FULL)}
    result['summary'] = {name: {'successful_imports': sum(s['ok'] for s in samples),
                              'median_import_ms': statistics.median(s['import_ms'] for s in samples),
                              'median_rss_bytes': statistics.median(s.get('rss_bytes', 0) for s in samples)}
                         for name, samples in result['samples'].items()}
    (EVIDENCE / 'measurements.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({'summary': result['summary'], 'footprint': result['footprint']}, indent=2))


if __name__ == '__main__':
    main()
