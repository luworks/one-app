#!/usr/bin/env python3
"""Thin planned ./dev CI adapter. No alternate build or test implementation."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

try:
    from .policy import LANES, validate_report
except ImportError:  # Direct workflow entry point.
    from policy import LANES, validate_report


def sanitize(text):
    text = re.sub(r'(?i)(token|password|passwd|secret|authorization|api[_-]?key|credential)'
                  r'([ \t]*[:=][ \t]*)("[^"]*"|\'[^\']*\'|[^\s,;]+)', r'\1\2[REDACTED]', text)
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
    # Swift manglings can contain gHr_; Objective-C selectors end in Token: or
    # Authorization:. Neither embeds a credential value on the same line.
    return re.search(
        rb'(?i)(?:\bgh[pousr]_[a-z0-9_]+|\bgithub_pat_[a-z0-9_]+|'
        rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
        rb"(?:token|password|passwd|secret|authorization|api[_-]?key|credential)[\"']?[ \t]*[:=][ \t]*[^\s]+|"
        rb'Bearer\s+[^\s]+)', data) is not None


def secret_candidate(data):
    # Redacted logs are expected; placeholders carry no credential. Everything
    # else matching the blocking scanner rejects closure without showing bytes.
    data = re.sub(rb"(?i)(?:token|password|passwd|secret|authorization|api[_-]?key|credential)"
                  rb"[\"']?[ \t]*[:=][ \t]*[\"']?\[REDACTED\]", b'', data)
    data = re.sub(rb'(?i)Bearer\s+\[REDACTED\]', b'', data)
    return bundle_secret(data)


def producer_boundary(sha, lane, output, env=None):
    """Trust the fixed no-secrets workflow, never a caller's synthetic flag.

    GitHub context identifies the configured boundary; it is not authentication.
    The workflow owner must keep secrets unavailable to checkout/test code.
    """
    env = os.environ if env is None else env
    if any(p.is_symlink() for p in [Path(output), *Path(output).parents]):
        raise ValueError('symlink producer output rejected')
    if any(value and (re.search(r'secret|token|password|passwd|api[_-]?key|authorization|credential', key, re.I)
                      or bundle_secret(value.encode())) for key, value in env.items()):
        raise ValueError('secret-bearing environment rejected')
    if (env.get('GITHUB_ACTIONS') != 'true' or env.get('GITHUB_WORKFLOW') != 'Today CI'
            or env.get('TODAY_CI_SYNTHETIC') != '1'
            or env.get('GITHUB_EVENT_NAME') not in ('pull_request', 'merge_group', 'push', 'workflow_dispatch')
            or env.get('GITHUB_SHA') != sha or not re.fullmatch(r'[0-9a-f]{40}', sha)
            or lane not in LANES
            or not env.get('RUNNER_TEMP')
            or Path(output).absolute() != Path(env['RUNNER_TEMP']).absolute() / ('today-' + lane)):
        raise ValueError('trusted synthetic workflow boundary required')


def close_producer(output, report, *, roots):
    """Seal explicit generated roots only after their synchronous writers return.

    The adapter owns a fresh output directory; roots never come from CLI input.
    Bundles are immutable. External logs are redacted before their final hashes.
    """
    from scripts.devtools.core import atomic_json
    output = Path(output)
    producer_boundary(report['sha'], report['lane'], output)
    if output.is_symlink() or report.get('synthetic') is not True:
        raise ValueError('unsafe producer output')
    files, bundles = [], []
    for relative in roots:
        path = artifact_path(output, relative)
        if not path.exists():
            continue
        paths = [path]
        if path.is_dir():
            paths += sorted(path.rglob('*'))
        for candidate in paths:
            rel = candidate.relative_to(output).as_posix()
            artifact_path(output, rel)
            if candidate.is_dir():
                if candidate.suffix == '.xcresult':
                    bundles.append(rel)
                continue
            if not candidate.is_file():
                raise ValueError('unsupported producer entry')
            in_bundle = any(part.endswith('.xcresult') for part in candidate.relative_to(output).parts)
            if not in_bundle and (candidate.suffix not in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips', '.png', '.map')
                                  or any(part.startswith('.') for part in Path(rel).parts)):
                raise ValueError('unexpected generated artifact')
            data = candidate.read_bytes()
            # Reject candidates before redaction; do not manufacture a no-secret
            # receipt from contaminated runner evidence.
            if bundle_secret(data) if in_bundle else secret_candidate(data):
                raise ValueError('blocking secret candidate in producer evidence')
            if not in_bundle and candidate.suffix != '.png':
                data = sanitize(data.decode('utf-8')).encode()
                candidate.write_bytes(data)
            files.append({'path': rel, **artifact_digest(data)})
    if len({entry['path'] for entry in files}) != len(files):
        raise ValueError('overlapping producer roots')
    for bundle in bundles:
        if not any(entry['path'].startswith(bundle + '/') for entry in files):
            raise ValueError('empty producer bundle')
    report['artifact_provenance'] = {
        'version': 1, 'owner': 'today-ci', 'run_id': output.name,
        'sha': report['sha'], 'lane': report['lane'], 'closed': True,
        'synthetic': True, 'secrets_available': False,
        'bundles': sorted(bundles), 'files': sorted(files, key=lambda entry: entry['path'])}
    atomic_json(output / 'report.json', report)


def close_wrapper(output, sha, lane, text):
    """Append only the wrapper's closed log without rehashing producer evidence."""
    from scripts.devtools.core import atomic_json
    output = Path(output)
    producer_boundary(sha, lane, output)
    data = sanitize(text).encode()
    path = output / 'wrapper-command.log'
    with path.open('xb') as stream:
        stream.write(data)
    if secret_candidate(text.encode()):
        raise ValueError('blocking secret candidate in wrapper output')
    report = json.loads(artifact_path(output, 'report.json').read_bytes())
    if not isinstance(report, dict):
        raise ValueError('invalid producer report')
    receipt = report.get('artifact_provenance', {})
    if (not isinstance(receipt, dict) or receipt.get('version') != 1
            or report.get('synthetic') is not True or report.get('sha') != sha or report.get('lane') != lane
            or receipt.get('owner') != 'today-ci' or receipt.get('run_id') != output.name
            or receipt.get('sha') != sha or receipt.get('lane') != lane
            or receipt.get('closed') is not True or receipt.get('synthetic') is not True
            or receipt.get('secrets_available') is not False):
        raise ValueError('closed producer receipt required')
    for entry in receipt['files']:
        if artifact_digest(artifact_path(output, entry['path']).read_bytes()) != {
                key: entry[key] for key in ('bytes', 'sha256')}:
            raise ValueError('closed producer bytes changed before wrapper exit')
    receipt['files'].append({'path': path.name, **artifact_digest(data)})
    atomic_json(output / 'report.json', report)
    return report


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
                              or path.suffix not in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips', '.png', '.map')):
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
        if not in_bundle and path.suffix in ('.log', '.txt', '.json', '.jsonl', '.crash', '.ips', '.map'):
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


def execute(argv, *, timeout=600, grace=30):
    """Reuse the owned process runner so nested adapters can close on cancellation."""
    from scripts.devtools.process import Evidence, Redactor, run_process

    root = Path(__file__).resolve().parents[2]
    raw = bytearray()
    evidence = Evidence(root, 'ci-wrapper', Redactor())
    try:
        result = run_process(argv, cwd=root, evidence=evidence, timeout=timeout, grace=grace,
                             output_observer=raw.extend)
        completed = subprocess.CompletedProcess(argv, result.returncode, result.log.read_text())
        completed.secret_found = secret_candidate(bytes(raw))
        return completed
    finally:
        evidence.close()


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    lane = sys.argv[1]
    if lane not in LANES:
        raise ValueError('unknown lane')
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, timeout=5).strip()
    if sha != os.environ['GITHUB_SHA']:
        raise ValueError('checkout does not match integrated GITHUB_SHA')
    output = Path(os.environ['RUNNER_TEMP']) / ('today-' + lane)
    producer_boundary(sha, lane, output)
    output.mkdir(exist_ok=False)
    selection = output / 'selection.json'
    # Use the existing checksummed tool selector, not the full local environment:
    # none of these lanes invokes mise, Ruby, Bundler or Fastlane. The wrapper and
    # helpers already use the hosted system Python; dev adapters use stdlib only.
    tools = {
        'format': ('swift-format',),
        'lint': ('swiftlint', 'ruff', 'actionlint'),
        'business': (),
    }.get(lane, ('xcodegen',))
    setup = []
    if tools:
        setup.append(['./dev', 'bootstrap', *[arg for name in tools for arg in ('--tool', name)]])
    if lane not in ('format', 'lint', 'business'):
        setup.extend([['./dev', 'generate'], ['./dev', 'resolve']])
    setup.append([sys.executable, 'scripts/ci/policy.py', 'select', '--output', str(selection)])
    command = ['./dev', 'ci', lane, '--selection', str(selection), '--output', str(output),
               '--sha', sha, '--synthetic', '--no-distribute']
    transcript = []
    setup_failed = False
    secret_found = False
    for argv in [*setup, command]:
        transcript.append('$ ' + ' '.join(argv) + '\n')
        started = time.monotonic()
        try:
            # The adapter may build and test serially before closing its receipt.
            completed = execute(argv, timeout=2100 if argv == command else 600, grace=30)
        except OSError as error:
            # Exception text may include private paths; retain only its type.
            completed = subprocess.CompletedProcess(argv, 1, type(error).__name__ + '\n')
        transcript.append(json.dumps({'command_seconds': round(time.monotonic() - started, 3),
                                      'exit': completed.returncode}) + '\n')
        transcript.append(completed.stdout or '')
        secret_found |= getattr(completed, 'secret_found', False)
        if completed.returncode:
            setup_failed = argv != command
            break
    text = ''.join(transcript)
    try:
        if setup_failed:
            # No adapter ran, so the wrapper owns this failed producer receipt.
            # Zero executed results can never satisfy the existing lane gate.
            report = {'sha': sha, 'lane': lane, 'synthetic': True, 'status': 'failed',
                      'executed': 0, 'failed': 1, 'cancelled': 0, 'missing': 0,
                      'errors': ['setup_exit:' + str(completed.returncode)]}
            close_producer(output, report, roots=('selection.json',))
        # Adapter receipts remain authoritative; never synthesize one for a
        # missing, malformed or unsuccessful adapter report.
        started = time.monotonic()
        report = close_wrapper(output, sha, lane, text)
        print(json.dumps({'close_wrapper_seconds': round(time.monotonic() - started, 3)}))
        if secret_found:
            raise ValueError('blocking secret candidate in wrapper output')
        print(sanitize(text))
        # A stopped failed run may still have useful synthetic diffs/crashes.
        started = time.monotonic()
        stage(output, Path(os.environ['RUNNER_TEMP']) / ('today-artifacts-' + lane), sha, lane)
        print(json.dumps({'stage_seconds': round(time.monotonic() - started, 3)}))
        validate_report(report, sha, lane)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('::error::CI adapter report rejected (' + type(error).__name__ +
              '); retained closed evidence requires a valid producer receipt. See docs/engineering/ci-artifact-producer.md.')
        # Single-line redacted diagnostics remain useful even when report
        # validation fails after successfully publishing a failed receipt.
        print(sanitize(str(error)).replace('\n', ' ')[:1200])
        if 'report' in locals() and isinstance(report, dict):
            print(sanitize(json.dumps({key: report.get(key) for key in (
                'lane', 'status', 'executed', 'failed', 'cancelled', 'missing', 'errors')}))[:4000])
        return completed.returncode or 1
    return completed.returncode


if __name__ == '__main__':
    sys.exit(main())
