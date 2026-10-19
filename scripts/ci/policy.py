#!/usr/bin/env python3
"""Fail-closed CI selection, report and required-check policy; standard library only."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

LANES = ('format', 'lint', 'business', 'integration', 'build', 'core-ui', 'snapshots',
         'release', 'extended', 'sanitizer', 'performance', 'protected-release')
MANUAL = ('extended', 'sanitizer', 'performance', 'protected-release')


def read_json(path):
    return json.loads(Path(path).read_text())


def capture(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.PIPE).strip()


def graph(root):
    """Read XcodeGen YAML and evaluated SPM manifests, never regex Swift source.

    Any unsupported/ambiguous edge triggers wide selection at the caller.
    Package ownership is deliberately package-wide (including resources).
    """
    spec = root / 'ios/project.yml'
    if not spec.exists():
        raise ValueError('ios/project.yml absent: graph incomplete')
    project = json.loads(capture(['ruby', '-ryaml', '-rjson', '-e',
        'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: false))', str(spec)]))
    if project.get('include') or project.get('targetTemplates'):
        raise ValueError('XcodeGen includes/templates require expanded graph')
    nodes = {}
    products = {}
    manifests = [p for p in root.rglob('Package.swift')
                 if not any(x in p.parts for x in ('.build', '.git', 'checkouts', 'node_modules'))]
    for manifest in manifests:
        rel = manifest.parent.relative_to(root).as_posix()
        package = json.loads(capture(['swift', 'package', '--package-path', str(manifest.parent), 'dump-package']))
        # Package changes select all package targets; downstream edges stay target-specific.
        for target in package['targets']:
            key = rel + ':' + target['name']
            deps = []
            for dep in target.get('dependencies', []):
                if 'target' in dep:
                    deps.append(rel + ':' + dep['target'][0])
                elif 'byName' in dep:
                    deps.append(rel + ':' + dep['byName'][0])
                else:
                    raise ValueError('external/product dependency requires wide selection')
            nodes[key] = {'paths': [rel], 'dependencies': deps}
        for product in package.get('products', []):
            if product['name'] in products:
                raise ValueError('ambiguous product name')
            products[product['name']] = [rel + ':' + t for t in product['targets']]
    for name, target in project['targets'].items():
        paths = []
        for source in target.get('sources', []):
            value = source if isinstance(source, str) else source['path']
            if '$' in value or '..' in Path(value).parts:
                raise ValueError('unresolved source path')
            paths.append('ios/' + value.strip('/'))
        deps = []
        for dep in target.get('dependencies', []):
            if 'target' in dep:
                deps.append('xcode:' + dep['target'])
            elif 'package' in dep:
                deps.extend(products[dep.get('product', dep['package'])])
            elif 'sdk' not in dep:
                raise ValueError('unresolved Xcode dependency')
        nodes['xcode:' + name] = {'paths': paths, 'dependencies': deps}
    if not nodes or any(d not in nodes for n in nodes.values() for d in n['dependencies']):
        raise ValueError('missing graph node')
    return nodes


def select(paths, nodes, reason=None):
    wide = reason
    if not paths:
        wide = wide or 'empty diff: conservative full selection'
    for path in paths:
        if path.startswith(('ios/Shared/', '.github/', 'scripts/', 'tests/fixtures/')) or path.endswith(('.plist', '.entitlements')) or any(
            word in path.lower() for word in ('shared', 'schema', 'model', 'config', 'package.swift',
                                              'package.resolved', 'project.yml', 'project.pbxproj')) or path == 'dev':
            wide = 'shared/config/schema/tooling change'
    selected = set()
    for path in paths:
        owners = {name for name, n in nodes.items() if any(
            path == p or path.startswith(p.rstrip('/') + '/') for p in n['paths'])}
        if not owners and not path.startswith(('docs/',)) and path not in ('README.md', 'CLAUDE.md', 'AGENTS.md'):
            wide = 'unmapped path: ' + path
        selected.update(owners)
    while True:
        consumers = {name for name, n in nodes.items() if set(n['dependencies']) & selected}
        if consumers <= selected:
            break
        selected.update(consumers)
    return {'version': 1, 'mode': 'wide' if wide else 'affected',
            'reason': wide or 'reverse dependency closure', 'changed': paths,
            'targets': sorted(nodes if wide else selected),
            'all_targets': bool(wide), 'snapshots': bool(wide or selected)}


def expected(event, ref, lane):
    if lane == 'release':
        return event == 'push' and ref == 'refs/heads/main'
    if lane in MANUAL:
        return event == 'workflow_dispatch' and lane == os.environ.get('MANUAL_LANE')
    return True


def aggregate(needs, event, ref):
    required = {'helpers', 'prerequisite', *LANES}
    errors = []
    if set(needs) != required:
        errors.append('missing or unexpected jobs: ' + str(sorted(set(needs) ^ required)))
    for name in required:
        result = needs.get(name, {}).get('result')
        allowed_skip = name in LANES and not expected(event, ref, name)
        if result != 'success' and not (result == 'skipped' and allowed_skip):
            errors.append(f'{name}: {result!r}; expected success' + (' or event-exempt skip' if allowed_skip else ''))
    return errors


def validate_report(report, sha, lane):
    if report.get('sha') != sha or report.get('lane') != lane or report.get('status') != 'passed':
        raise ValueError('report must match integrated SHA, lane and passed status')
    for field in ('executed', 'failed', 'cancelled', 'missing'):
        value = report.get(field)
        if type(value) is not int or value < 0:
            raise ValueError('invalid report counter: ' + field)
    if report['executed'] == 0 or any(report[x] for x in ('failed', 'cancelled', 'missing')):
        raise ValueError('zero results, failures, cancellations or missing results')
    if report.get('synthetic') is not True:
        raise ValueError('only synthetic CI datasets are allowed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    s = sub.add_parser('select')
    s.add_argument('--changed-json')
    s.add_argument('--graph-json')
    s.add_argument('--output', required=True)
    a = sub.add_parser('aggregate')
    a.add_argument('--needs-json', required=True)
    args = parser.parse_args()
    if args.command == 'aggregate':
        errors = aggregate(json.loads(args.needs_json), os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_REF'])
        print('\n'.join(errors) if errors else 'All required jobs passed; only event-defined skips accepted.')
        return bool(errors)
    reason = None
    try:
        nodes = read_json(args.graph_json) if args.graph_json else graph(Path.cwd())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        nodes, reason = {}, 'graph unavailable: ' + str(error)
    if args.changed_json:
        paths = read_json(args.changed_json)
    else:
        try:
            event = read_json(os.environ['GITHUB_EVENT_PATH'])
            base = (event.get('pull_request', {}).get('base', {}).get('sha') or
                    event.get('merge_group', {}).get('base_sha') or event.get('before'))
            if not base or set(base) == {'0'}:
                raise ValueError('base unavailable')
            # NUL-delimited names preserve spaces/newlines and deleted paths.
            paths = subprocess.check_output(['git', 'diff', '--name-only', '-z', base, 'HEAD']).decode().rstrip('\0').split('\0')
        except (OSError, ValueError, subprocess.SubprocessError):
            paths, reason = [], 'diff unavailable: full selection'
    Path(args.output).write_text(json.dumps(select(paths, nodes, reason), indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
