#!/usr/bin/env python3
"""Thin planned ./dev CI adapter. No alternate build or test implementation."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from policy import LANES, validate_report


def sanitize(text):
    text = re.sub(r'(?i)(token|password|secret|authorization)(\s*[:=]\s*)\S+', r'\1\2[REDACTED]', text)
    text = re.sub(r'(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)', '[REDACTED]', text)
    text = re.sub(r'/Users/[^/\s]+', '/Users/REDACTED', text)
    return text


def stage(source, destination, sha, lane):
    """Allowlisted, explicitly synthetic results only; never upload an entire workspace."""
    report = json.loads((source / 'report.json').read_text())
    if report.get('synthetic') is not True or report.get('sha') != sha or report.get('lane') != lane:
        raise ValueError('artifact provenance absent or mismatched')
    published = destination
    destination = destination.with_name(destination.name + '-staging')
    destination.mkdir(parents=True, exist_ok=False)
    manifest = []
    for path in sorted(source.rglob('*')):
        if path.is_symlink() or any(p.is_symlink() for p in path.parents if p != source and source in p.parents):
            raise ValueError('symlink artifact rejected')
        if not path.is_file():
            continue
        rel = path.relative_to(source)
        if any(part.startswith('.') for part in rel.parts):
            continue
        if not (path.suffix in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips', '.png') or
                any(part.endswith('.xcresult') for part in rel.parts)):
            continue
        target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        data = path.read_bytes()
        if path.suffix in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips'):
            data = sanitize(data.decode('utf-8')).encode()
        target.write_bytes(data)
        manifest.append({'path': str(rel), 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    (destination / 'manifest.json').write_text(json.dumps({'sha': sha, 'lane': lane, 'synthetic': True,
                                                          'files': manifest}, indent=2) + '\n')
    destination.rename(published)


def main():
    lane = sys.argv[1]
    if lane not in LANES:
        raise ValueError('unknown lane')
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if sha != os.environ['GITHUB_SHA']:
        raise ValueError('checkout does not match integrated GITHUB_SHA')
    output = Path(os.environ['RUNNER_TEMP']) / ('today-' + lane)
    output.mkdir(exist_ok=False)
    selection = output / 'selection.json'
    subprocess.run([sys.executable, 'scripts/ci/policy.py', 'select', '--output', str(selection)], check=True)
    # Integration owns this future adapter. Unknown commands must fail, not become a no-op.
    command = ['./dev', 'ci', lane, '--selection', str(selection), '--output', str(output),
               '--sha', sha, '--synthetic', '--no-distribute']
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log = sanitize(completed.stdout)
    print(log)
    (output / 'command.log').write_text(log)
    try:
        report = json.loads((output / 'report.json').read_text())
        # A stopped failed run may still have useful synthetic diffs/crashes.
        stage(output, Path(os.environ['RUNNER_TEMP']) / ('today-artifacts-' + lane), sha, lane)
        validate_report(report, sha, lane)
    except (OSError, ValueError) as error:
        print('::error::CI adapter report rejected: ' + str(error) +
              '. Integration must implement ./dev ci and emit nonzero authoritative results; see docs/engineering/ci.md.')
        return 1
    return completed.returncode


if __name__ == '__main__':
    sys.exit(main())
