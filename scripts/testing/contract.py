"""Shared source inventory, selection plans and fail-closed execution reports.

Standard library only. Source discovery is deliberately not execution evidence.
"""
from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'tests/testing/groups.json'
SETTINGS = json.loads(MANIFEST.read_text())['execution']
TARGET = SETTINGS['ui_target']


def discover(directory, root=ROOT):
    suites = []
    xctest_suites = set()
    for path in sorted(Path(directory).rglob('*.swift')):
        text = path.read_text()
        # Mask strings AND comments: JSON braces, URLs and quoted declarations
        # must not change Swift scope or manufacture tests. Preserve line offsets.
        text = re.sub(r'""".*?"""|"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*',
                      lambda m: ''.join('\n' if ch == '\n' else ' ' for ch in m[0]), text, flags=re.S)
        current, depth, scopes, annotated = None, 0, [], False
        for number, line in enumerate(text.splitlines(), 1):
            declaration = re.search(r'\b(class|struct|enum|extension)\s+(\w+)', line)
            if declaration:
                name = declaration[2]
                if re.search(r':\s*XCTestCase\b', line):
                    xctest_suites.add(name)
                scope = {'suite': name, 'path': str(path.relative_to(root)), 'methods': []}
                scopes.append((depth, scope, current))
                current = scope
            if re.search(r'@Test\b', line):
                annotated = True
            method = re.search(r'\bfunc\s+(`?\w+`?)\s*\(', line)
            if method and current is None and annotated:
                suites.append({'suite': '', 'path': str(path.relative_to(root)), 'methods': [
                    {'name': method[1].strip('`'), 'line': number, 'framework': 'SwiftTesting'}]})
                annotated = False
            elif method and current is not None:
                name = method[1].strip('`')
                if annotated or (name.startswith('test') and depth == scopes[-1][0] + 1):
                    current['methods'].append({'name': name, 'line': number,
                                               'framework': 'SwiftTesting' if annotated else 'XCTest'})
                annotated = False
            depth += line.count('{') - line.count('}')
            if depth < 0:
                raise ValueError('Unbalanced Swift source: ' + str(path))
            while scopes and depth <= scopes[-1][0]:
                _, finished, current = scopes.pop()
                if finished['methods']:
                    suites.append(finished)
        if depth or annotated:
            raise ValueError('Incomplete Swift test source: ' + str(path))
    for suite in suites:
        suite['methods'] = [m for m in suite['methods']
                            if m['framework'] == 'SwiftTesting' or suite['suite'] in xctest_suites]
    suites = [s for s in suites if s['methods']]
    # Extensions contribute to the original suite instead of replacing it.
    merged = {}
    for suite in suites:
        key = suite['suite']
        if key not in merged:
            merged[key] = suite
        else:
            merged[key]['methods'].extend(suite['methods'])
    return list(merged.values())


def load_manifest():
    return json.loads(MANIFEST.read_text())


def lane_settings(lane):
    try:
        return SETTINGS['lanes'][lane]
    except KeyError:
        raise ValueError('Unknown test lane: ' + lane) from None


def inventory(root=ROOT):
    result = {}
    for lane, config in SETTINGS['lanes'].items():
        result[lane] = []
        for directory in config['sources']:
            path = root / directory
            if not path.is_dir():
                raise ValueError('Missing test source directory: ' + directory)
            suites = discover(path, root)
            if not suites:
                raise ValueError('Zero discovered tests: ' + directory)
            for suite in suites:
                suite['target'] = config.get('source_targets', {}).get(directory, config['target'])
            result[lane].extend(suites)
    return result


def canonical(value, lane='ui'):
    config = lane_settings(lane)
    value = value.strip()
    objc = re.fullmatch(r'-\[(?:\w+\.)?(\w+) (\w+)\]', value)
    if objc:
        value = '/'.join(objc.groups())
    value = re.sub(r'\([^)]*\)', '', value).replace('.', '/')
    parts = value.split('/')
    aliases = {'OneUITests': TARGET, 'OneLogicTests': SETTINGS['logic_target']}
    targets = {c['target'] for c in SETTINGS['lanes'].values()}
    targets.update(t for c in SETTINGS['lanes'].values() for t in c.get('source_targets', {}).values())
    if parts[0] in aliases:
        parts[0] = aliases[parts[0]]
    host_targets = set(config.get('source_targets', {}).values())
    if len(parts) == 2 and parts[0] in host_targets:
        parts.insert(0, parts[0])
    if parts[0] not in targets:
        parts.insert(0, config['target'])
    if any(not re.fullmatch(r'\w+', part) for part in parts):
        raise ValueError('Invalid test selector: ' + value)
    return '/'.join(parts)


def available(source, lane):
    lane_settings(lane)
    if lane not in source:
        raise ValueError('Missing source lane: ' + lane)
    return [canonical('/'.join(filter(None, [s.get('target', ''), s['suite'], m['name']])), lane)
            for s in source[lane] for m in s['methods']]


def expand(values, source, lane):
    known = available(source, lane)
    result = []
    for value in values:
        if value == '*':
            matches = known
        else:
            selected = canonical(value, lane)
            # An unqualified suite may belong to another host SwiftPM target.
            if '/' not in value and value not in {k.split('/')[0] for k in known}:
                matches = [k for k in known if len(k.split('/')) > 2 and k.split('/')[1] == value]
            else:
                matches = [k for k in known if k == selected or k.startswith(selected + '/')]
        if not matches:
            raise ValueError('Unknown selection: ' + value)
        result.extend(matches)
    return list(dict.fromkeys(result))


def plan(groups, source=None, manifest=None):
    source = inventory() if source is None else source
    manifest = load_manifest() if manifest is None else manifest
    selected = {lane: [] for lane in SETTINGS['lanes']}
    pending, seen, visiting = [], set(), set()
    def visit(name):
        if name in visiting:
            raise ValueError('Cyclic test group: ' + name)
        if name in seen:
            return
        if name not in manifest['groups']:
            raise ValueError('Unknown test group: ' + name)
        visiting.add(name)
        group = manifest['groups'][name]
        unknown = set(group) - set(selected) - {'includes', 'pending'}
        if unknown:
            raise ValueError('Unknown group lanes: ' + ', '.join(sorted(unknown)))
        for include in group.get('includes', []):
            visit(include)
        for lane in selected:
            values = group.get(lane, [])
            matches = expand(values, source, lane) if values else []
            if values and not matches:
                raise ValueError('Zero selected tests: ' + name + '/' + lane)
            selected[lane].extend(matches)
        pending.extend(group.get('pending', []))
        visiting.remove(name)
        seen.add(name)
    if not groups:
        raise ValueError('No test groups selected')
    for group in groups:
        visit(group)
    selected = {k: list(dict.fromkeys(v)) for k, v in selected.items()}
    if not any(selected.values()):
        raise ValueError('Zero selected tests')
    by_target = {}
    for lane, selectors in selected.items():
        by_target[lane] = {}
        for selector in selectors:
            by_target[lane].setdefault(selector.split('/')[0], []).append(selector)
    return {'schema_version': 1, 'groups': groups, 'project': SETTINGS['project'],
            'scheme': SETTINGS['scheme'], 'target': TARGET, 'selectors': selected,
            'expected_by_target': by_target, 'lanes': SETTINGS['lanes'],
            'pending': list(dict.fromkeys(pending)), 'inventory_is_execution': False}


def unwrap(value):
    """Legacy xcresult typed JSON and modern test-results JSON."""
    if isinstance(value, dict):
        if '_value' in value:
            return value['_value']
        if '_values' in value:
            return [unwrap(v) for v in value['_values']]
        return {k: unwrap(v) for k, v in value.items() if k != '_type'}
    if isinstance(value, list):
        return [unwrap(v) for v in value]
    return value


def xcresult_attempts(data, lane='ui'):
    """Read leaf executions, never aggregate suite/plan success counts."""
    data = unwrap(data)
    attempts = []
    statuses = {'passed': 'passed', 'success': 'passed', 'failed': 'failed',
                'failure': 'failed', 'skipped': 'skipped', 'expected failure': 'failed'}
    def walk(node):
        if isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, dict):
            status = node.get('result', node.get('testStatus'))
            kind = node.get('nodeType', '')
            identifier = node.get('testIdentifier', node.get('nodeIdentifier', node.get('identifier')))
            # Modern nodes explicitly distinguish Test Case from suites. Legacy leaves
            # have identifier + testStatus; suite totals never supply testStatus.
            if status is not None and (kind in ('Test Case', 'Test Case Run') or 'testStatus' in node):
                normalized = statuses.get(str(status).lower())
                if not identifier or normalized is None:
                    raise ValueError('Unrecognized xcresult test execution: ' + repr(node))
                attempts.append({'test': canonical(identifier, lane), 'status': normalized,
                                 'reason': node.get('skipReason', node.get('failureText', '')),
                                 'source': 'xcresult', 'result_id': identifier})
            for key, value in node.items():
                if isinstance(value, (dict, list)):
                    walk(value)
    walk(data)
    if not attempts:
        raise ValueError('xcresult contains zero recognized test executions')
    return attempts


def log_attempts(text, lane='logic'):
    attempts = []
    for line in text.splitlines():
        match = re.search(r"Test Case '(.*?)' (passed|failed|skipped)", line)
        if not match:
            match = re.search(r'Test (?:"([^"\n]+)"|([^\s]+)) (passed|failed|skipped)(?: after|:|\s|$)', line)
            if match:
                match = (match[1] or match[2], match[3])
        else:
            match = (match[1], match[2])
        if match:
            attempts.append({'test': canonical(match[0], lane), 'status': match[1],
                             'reason': '', 'source': 'log'})
    return attempts


def report(expected, attempts, exit_code=0, allowed_skips=(), skip_rules=(), raw_log='', pending=()):
    errors, allowed, unexpected = [], [], []
    if exit_code:
        errors.append('process_exit:' + str(exit_code))
    if re.search(r'no tests? (?:were )?(?:found|executed)|no matching test|badselector|parsererror|error:.*(?:selector|parse)', raw_log, re.I):
        errors.append('log_diagnostic')
    # Swift Testing's console sometimes omits the suite. Resolve only a unique
    # expected method; ambiguity remains missing rather than inventing coverage.
    attempts = [dict(a) for a in attempts]
    for attempt in attempts:
        if not isinstance(attempt.get('test'), str) or attempt.get('status') not in ('passed', 'failed', 'skipped'):
            errors.append('parser_error')
            attempt['parser_detail'] = repr(attempt)
            if not isinstance(attempt.get('test'), str):
                attempt['test'] = ''
            if attempt.get('status') not in ('passed', 'failed', 'skipped'):
                attempt['status'] = 'unknown'
        if attempt['test'] not in expected and len(attempt['test'].split('/')) == 2:
            method = attempt['test'].split('/')[-1]
            candidates = [test for test in expected if test.split('/')[-1] == method
                          and test.split('/')[0] == attempt['test'].split('/')[0]]
            if len(candidates) == 1:
                attempt['test'] = candidates[0]
    if any(a['status'] == 'failed' for a in log_attempts(raw_log)):
        errors.append('log_failure')
    if not expected:
        errors.append('zero_expected')
    observed = {a['test'] for a in attempts}
    extras = sorted(observed - set(expected))
    if extras:
        errors.append('unexpected_tests')
    missing = sorted(set(expected) - observed)
    if missing:
        errors.append('missing_tests')
    if not any(a['status'] in ('passed', 'failed') for a in attempts):
        errors.append('zero_executed')
    def skip_matches(rule, attempt):
        target = attempt['test'].split('/')[0]
        lane = next((name for name, config in SETTINGS['lanes'].items()
                     if target == config['target'] or target in config.get('source_targets', {}).values()), 'ui')
        return (rule['category'] in allowed_skips
                and canonical(rule['test'], lane) == attempt['test']
                and re.search(rule['reason'], str(attempt.get('reason', '')), re.I))

    for attempt in attempts:
        if attempt['status'] == 'failed':
            errors.append('test_failure')
        elif attempt['status'] == 'skipped':
            matches = [rule for rule in skip_rules if skip_matches(rule, attempt)]
            (allowed if matches else unexpected).append(attempt)
        elif attempt['status'] != 'passed':
            errors.append('parser_error')
    if unexpected:
        errors.append('unexpected_skip')
    return {'schema_version': 1, 'status': 'failed' if errors else 'passed',
            'errors': list(dict.fromkeys(errors)), 'exit_code': exit_code,
            'expected_count': len(set(expected)), 'executed_count': sum(a['status'] in ('passed', 'failed') for a in attempts),
            'missing': missing, 'unexpected': extras, 'counts': dict(Counter(a['status'] for a in attempts)),
            'allowed_skips': allowed, 'unexpected_skips': unexpected,
            'attempts': attempts, 'pending': list(pending),
            'coverage_status': 'pending' if pending else ('incomplete' if errors or allowed or unexpected else 'complete')}
