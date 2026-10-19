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
    text = re.sub(r'(?i)(token|password|passwd|secret|authorization|api[_-]?key|credential)'
                  r'(\s*[:=]\s*)("[^"]*"|\'[^\']*\'|[^\s,;]+)', r'\1\2[REDACTED]', text)
    text = re.sub(r'(?i)(Bearer\s+)\S+', r'\1[REDACTED]', text)
    text = re.sub(r'(https?://)[^\s/@]+:[^\s/@]+@', r'\1[REDACTED]@', text)
    text = re.sub(r'(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)', '[REDACTED]', text)
    text = re.sub(r'/Users/[^/\s]+', '/Users/REDACTED', text)
    return text


def artifact_path(source, relative):
    """Resolve an explicit owned artifact without following links or walking parents."""
    if (not isinstance(relative, str) or not relative or '\\' in relative
            or Path(relative).is_absolute() or any(p in ('', '.', '..') for p in relative.split('/'))):
        raise ValueError('unsafe artifact path')
    current = source
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink():
            raise ValueError('symlink artifact rejected')
    return current


def artifact_digest(data):
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def bundle_secret(data):
    """Blocking heuristic only; synthetic/no-secret runner provenance is mandatory."""
    return re.search(
        rb'(?i)(?:gh[pousr]_[a-z0-9_]+|github_pat_[a-z0-9_]+|'
        rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
        rb"(?:token|password|passwd|secret|authorization|api[_-]?key|credential)[\"']?\s*[:=]\s*[^\s]+|"
        rb'Bearer\s+[^\s]+)', data) is not None


def stage(source, destination, sha, lane):
    """Publish only closed, explicitly inventoried synthetic runner evidence."""
    source, published = Path(source), Path(destination)
    if source.is_symlink():
        raise ValueError('symlink artifact source rejected')
    source = source.resolve()
    if (published.exists() or published.is_symlink()
            or published.resolve().is_relative_to(source.resolve())
            or source.resolve().is_relative_to(published.resolve())):
        raise ValueError('unsafe artifact destination')
    report_path = artifact_path(source, 'report.json')
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    if (not isinstance(report, dict) or report.get('synthetic') is not True or report.get('sha') != sha
            or report.get('lane') != lane or not re.fullmatch(r'[0-9a-f]{40}', sha)):
        raise ValueError('artifact provenance absent or mismatched')
    receipt = report.get('artifact_provenance', {})
    if (not isinstance(receipt, dict) or type(receipt.get('version')) is not int or receipt.get('version') != 1
            or receipt.get('owner') != 'today-ci' or receipt.get('run_id') != source.name
            or receipt.get('sha') != sha or receipt.get('lane') != lane
            or receipt.get('closed') is not True or receipt.get('synthetic') is not True
            or receipt.get('secrets_available') is not False):
        raise ValueError('closed artifact ownership/provenance absent or mismatched')
    entries, bundles = receipt.get('files'), receipt.get('bundles')
    if not isinstance(entries, list) or not isinstance(bundles, list):
        raise ValueError('explicit artifact inventory required')
    bundle_paths = set()
    directories = set()
    for relative in bundles:
        bundle = artifact_path(source, relative)
        if not relative.endswith('.xcresult') or not bundle.is_dir():
            raise ValueError('invalid closed bundle')
        if any(bundle == p or bundle.is_relative_to(p) or p.is_relative_to(bundle) for p in bundle_paths):
            raise ValueError('overlapping bundle inventory')
        bundle_paths.add(bundle)
        directories.add(bundle.relative_to(source).as_posix())
    paths = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError('invalid artifact inventory entry')
        relative = entry.get('path')
        path = artifact_path(source, relative)
        if relative in paths or relative in ('report.json', 'manifest.json') or not path.is_file():
            raise ValueError('invalid or duplicate artifact inventory entry')
        in_bundle = any(path.is_relative_to(bundle) for bundle in bundle_paths)
        if not in_bundle and (any(p.endswith('.xcresult') or p.startswith('.') for p in Path(relative).parts)
                              or path.suffix not in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips', '.png')):
            raise ValueError('artifact outside allowed generated evidence')
        if (type(entry.get('bytes')) is not int or entry['bytes'] < 0
                or not isinstance(entry.get('sha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', entry['sha256'])):
            raise ValueError('invalid artifact digest')
        paths[relative] = (path, entry, in_bundle)
    # Only walk declared bundles, never a workspace or unrelated/private paths.
    for bundle in bundle_paths:
        found = set()
        for path in bundle.rglob('*'):
            if path.is_symlink():
                raise ValueError('symlink artifact rejected')
            if path.is_dir():
                directories.add(path.relative_to(source).as_posix())
            elif path.is_file():
                found.add(path.relative_to(source).as_posix())
            else:
                raise ValueError('unsupported bundle entry')
        expected = {rel for rel, (path, _, _) in paths.items() if path.is_relative_to(bundle)}
        if not found or found != expected:
            raise ValueError('incomplete closed bundle inventory')
    destination = published.with_name(published.name + '-staging')
    destination.mkdir(parents=True, exist_ok=False)
    manifest = []
    # A failed test report is still useful evidence; acceptance is validated later.
    paths['report.json'] = (report_path, artifact_digest(report_bytes), False)
    for relative, (path, expected, in_bundle) in sorted(paths.items()):
        data = path.read_bytes()
        original = artifact_digest(data)
        if original != {key: expected.get(key) for key in ('sha256', 'bytes')}:
            raise ValueError('closed artifact bytes changed')
        if in_bundle and bundle_secret(data):
            raise ValueError('blocking secret in closed bundle; publication rejected')
        transformation = 'identity'
        if not in_bundle and path.suffix in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips'):
            data = sanitize(data.decode('utf-8')).encode('utf-8')
            transformation = 'sanitize-v1' if artifact_digest(data) != original else 'identity'
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest.append({'path': relative, **artifact_digest(data), 'source': original,
                         'transformation': transformation})
    for relative in sorted(directories):
        (destination / relative).mkdir(parents=True, exist_ok=True)
    # Refuse to publish if the closed producer contract was violated during staging.
    for relative, (path, expected, _) in paths.items():
        artifact_path(source, relative)
        if path.is_symlink() or artifact_digest(path.read_bytes()) != {
                key: expected.get(key) for key in ('sha256', 'bytes')}:
            raise ValueError('closed artifact changed during staging')
    for bundle in bundle_paths:
        current_paths = list(bundle.rglob('*'))
        if any(p.is_symlink() for p in [bundle, *current_paths]):
            raise ValueError('symlink artifact rejected during staging')
        current = {p.relative_to(source).as_posix() for p in current_paths}
        expected = {rel for rel, (path, _, _) in paths.items() if path.is_relative_to(bundle)}
        expected |= {rel for rel in directories if (source / rel).is_relative_to(bundle) and source / rel != bundle}
        if current != expected:
            raise ValueError('closed bundle tree changed during staging')
    (destination / 'manifest.json').write_text(json.dumps({
        'sha': sha, 'lane': lane, 'run_id': receipt['run_id'], 'synthetic': True,
        'directories': sorted(directories), 'files': manifest}, indent=2) + '\n')
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
