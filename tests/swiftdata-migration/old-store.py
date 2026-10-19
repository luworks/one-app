#!/usr/bin/env python3
"""Build/run the exact baseline model writer; never modifies or removes a prior store."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = 'e022a7a46a4aa0d0a604886c139a7dd2c050fed1'
RESULTS = Path('/Users/yuanlu/code/one-app/tests/results/reconstruction/swiftdata-old')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def baseline(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def extract():
    package = baseline('ios/Package.swift')
    # Strictly match both production pure-source targets, never the test target.
    targets = re.findall(r'name: "(OneLogic|OneShared)",\s*path: "(One|Shared)",\s*sources: \[([^]]+)\]', package.decode())
    if [t[0] for t in targets] != ['OneLogic', 'OneShared']:
        raise ValueError('Baseline Package.swift source-list boundary changed')
    outputs = {}
    inputs = {'ios/Package.swift': sha(package)}
    boundaries = {}
    for _, folder, sources in targets:
        names = re.findall(r'"([^"]+\.swift)"', sources)
        if not names:
            raise ValueError('Empty baseline pure-source list')
        for name in names:
            path = f'ios/{folder}/{name}'
            data = baseline(path)
            inputs[path] = sha(data)
            outputs[f'{folder}/{name}'] = data
    for name in ['Models.swift', 'OneAlarm.swift', 'OneList.swift', 'Habits.swift', 'ChatThread.swift', 'Ledger.swift']:
        path = f'ios/One/{name}'
        data = baseline(path)
        inputs[path] = sha(data)
        text = data.decode()
        if name == 'Models.swift':
            start = '\nextension Capture {\n'
            end = '\n/// Committed with a Share reminder.'
            if text.count(start) != 1 or text.count(end) != 1:
                raise ValueError('Models.swift extraction boundary mismatch')
            a, b = text.index(start), text.index(end)
            if b <= a or text[a:b].count('\n@Model\n') != 0:
                raise ValueError('Capture exclusion includes a model')
            segments = [(0, a), (b, len(text))]
        elif name == 'Ledger.swift':
            end = '\n/// Records changes in the ledger. Called from the write paths'
            if text.count(end) != 1 or '\n@MainActor\nenum Ledger {' not in text:
                raise ValueError('Ledger.swift extraction boundary mismatch')
            segments = [(0, text.index(end))]
        else:
            segments = [(0, len(text))]
        output = ''.join(text[a:b] for a, b in segments).encode()
        expected = {'Models.swift': ['OneTask', 'OneEvent', 'ShareImportReceipt'], 'OneAlarm.swift': ['OneAlarm'], 'OneList.swift': ['OneList'], 'Habits.swift': ['Habit'], 'ChatThread.swift': ['ChatThread'], 'Ledger.swift': ['LedgerEntry', 'AIGrant']}[name]
        if re.findall(r'@Model\s+final class (\w+)', output.decode()) != expected:
            raise ValueError(f'Model declaration mismatch: {name}')
        outputs[f'Models/{name}'] = output
        boundaries[path] = {'segments': [{'firstLine': text[:a].count('\n') + 1, 'lastLine': text[:b].count('\n'), 'sha256': sha(text[a:b].encode())} for a, b in segments], 'outputSha256': sha(output), 'models': expected}
    return outputs, {'baseline': BASE, 'module': 'One', 'inputSha256': inputs, 'modelExtraction': boundaries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-name', help='New immutable evidence directory name; defaults to UTC timestamp')
    args = parser.parse_args()
    sources, manifest = extract()
    lock = json.loads((HERE / 'source-lock.json').read_text())
    if manifest != lock:
        raise ValueError('Baseline source hashes/boundaries do not match versioned source-lock.json')
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
    name = args.run_name or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise ValueError('Unsafe run name')
    run = RESULTS / name
    run.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('qa_journal', ROOT / 'tests/qa/journal.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    journal = module.Journal(RESULTS.parents[1] / 'activity.sqlite')
    session = f'swiftdata-old-{name}'
    journal.record(session, 'qa.development', f'Exact baseline {BASE} old-writer disk characterization; module One; source-lock checked; no app build')
    status = 'failed'
    try:
        paths = []
        for relative, data in sources.items():
            dest = run / 'sources' / relative
            dest.parent.mkdir(parents=True, exist_ok=True); dest.write_bytes(data); paths.append(str(dest))
        driver = run / 'OldWriter.swift'; driver.write_bytes((HERE / 'OldWriter.swift').read_bytes())
        manifest['driverSha256'] = sha(driver.read_bytes())
        manifest['harnessSha256'] = sha(Path(__file__).read_bytes())
        manifest['checkoutHead'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        (run / 'source-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        executable = run / 'old-writer'
        commands = [
            ['xcrun', 'swiftc', '-module-name', 'One', '-parse-as-library', '-j', '1', '-Onone', '-lsqlite3', *paths, str(driver), '-o', str(executable)],
            [str(executable), 'write', str(run / 'old.store'), str(run / 'expected.json')],
            [str(executable), 'verify', str(run / 'old.store'), str(run / 'expected.json')],
        ]
        (run / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        for label, command in zip(['compile', 'write', 'reopen'], commands):
            journal.record(session, 'qa.command.started', json.dumps(command), status='running')
            with (run / f'{label}.log').open('w') as log:
                completed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            journal.record(session, 'qa.command.result', f'{label}: exit {completed.returncode}', status='passed' if completed.returncode == 0 else 'failed')
            print(f'{label}: exit {completed.returncode}; {run / (label + ".log")}', flush=True)
            if completed.returncode:
                raise RuntimeError(f'{label} failed; all files retained at {run}')
        status = 'passed'
    finally:
        # Processes have exited. Index every raw file, including the binary, store and sidecars.
        artifacts = []
        for file in sorted(run.rglob('*')):
            if file.is_file():
                artifacts.append({'path': str(file.relative_to(run)), 'bytes': file.stat().st_size, 'sha256': journal.artifact(session, file)})
        summary = {'status': status, 'baseline': BASE, 'module': 'One', 'run': str(run), 'qaSession': session, 'artifacts': artifacts}
        summary_path = run / 'result.json'; summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
        journal.artifact(session, summary_path)
        journal.record(session, 'qa.run.result', str(run), status=status)
        journal.close()
        print(json.dumps({'status': status, 'run': str(run), 'qaSession': session}), flush=True)


if __name__ == '__main__':
    main()
