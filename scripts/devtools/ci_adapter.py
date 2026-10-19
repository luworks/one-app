"""Bounded CI execution using the dev process and shared test-result authority."""
import contextlib
import io
import shutil
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from scripts.ci.policy import LANES, MANUAL, validate_report
from scripts.testing import contract
from . import commands
from .core import atomic_json, canonical_root, derived_data, fingerprint, probe
from .process import Redactor

# These lanes lack an executable acceptance authority in the current dev contract.
# Do not substitute screenshot attachments, a Debug build, or discovery for them.
UNSUPPORTED = {
    'sanitizer': 'Supported sanitizer execution and result authority is not implemented',
    'performance': 'Stable benchmark and budget acceptance authority is not implemented',
    'protected-release': 'Guarded unsigned archive acceptance authority is not implemented',
}
CORE_EXTRA = (
    'SinglePresentationTests/testLongPressOnAnEventShowsOnlyItsMenu',
    'SinglePresentationTests/testDraggingATaskDoesNotMakeAnEvent',
    'ShareImportTests/testPersistedShareIsVisibleAndReplayDoesNotDuplicate',
)


def selection_data(path):
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict) or type(data.get('version')) is not int or data['version'] != 1:
        raise ValueError('Unsupported selection version')
    if data.get('mode') not in ('wide', 'affected') or not isinstance(data.get('reason'), str):
        raise ValueError('Invalid selection mode/reason')
    for key in ('changed', 'targets'):
        if not isinstance(data.get(key), list) or any(not isinstance(x, str) or not x for x in data[key]):
            raise ValueError('Invalid selection ' + key)
    for key in ('all_targets', 'snapshots'):
        if type(data.get(key)) is not bool:
            raise ValueError('Invalid selection ' + key)
    if data['all_targets'] != (data['mode'] == 'wide'):
        raise ValueError('Inconsistent selection mode')
    # This bounded adapter conservatively runs whole authoritative groups. Targets
    # are graph nodes, never XCTest selectors; do not guess tests from module names.
    return data


def source_state(root, sha):
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or probe(['git', 'rev-parse', 'HEAD'], root) != sha:
        raise ValueError('Checkout must match the full integrated SHA')
    if probe(['git', 'status', '--porcelain', '--untracked-files=normal'], root):
        raise ValueError('CI requires a clean checkout, including untracked source')
    return fingerprint(root, tools={})['sha256']


def safe_artifacts(source, destination, *, sha, lane):
    """Use the shared closed-receipt publisher; never discover workspace files."""
    from scripts.ci.run import stage
    stage(source, destination, sha, lane)


def test_plan(root, lane):
    source = contract.inventory(root)
    group = {'business': 'unit', 'integration': 'integration', 'snapshots': 'snapshot', 'core-ui': 'core', 'extended': 'ui'}[lane]
    plan = contract.plan([group], source=source)
    if lane == 'core-ui':
        plan['selectors']['ui'] += contract.expand(CORE_EXTRA, source, 'ui')
        plan['selectors']['ui'] = list(dict.fromkeys(plan['selectors']['ui']))
    if plan['pending']:
        raise ValueError('Test authority has pending coverage: ' + '; '.join(plan['pending']))
    kind = {'business': 'logic', 'integration': 'integration', 'snapshots': 'snapshot'}.get(lane, 'ui')
    expected = plan['selectors'][kind]
    if not expected:
        raise ValueError('Selected test authority contains zero tests')
    return kind, expected


def _native_results(root, lane, output, report):
    """Consume the same completed authority as ./dev, never console-only counts."""
    from . import xcode_tests
    kind, expected = test_plan(root, lane)
    report['missing'] = len(expected)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        code = commands.test(root, kind, timeout=600)
    receipts = [json.loads(line) for line in captured.getvalue().splitlines() if line.startswith('{')]
    if len(receipts) != 1 or set(receipts[0]) != {'report', 'status'}:
        raise ValueError('Missing or ambiguous native test receipt')
    scheme = xcode_tests.SCHEMES[kind]
    path = Path(receipts[0]['report'])
    evidence_root = canonical_root(root) / 'tests/results/devtools/logs'
    if (not path.is_absolute() or not path.resolve().is_relative_to(evidence_root.resolve())
            or path.parent.parent.resolve() != evidence_root.resolve()
            or path.name != scheme + '.report.json' or not path.parent.name.endswith('-xcode')):
        raise ValueError('Native evidence outside owned result directory')
    paths = [path.parent, *path.parent.rglob('*')]
    if any(p.is_symlink() for p in paths):
        raise ValueError('Symlink native evidence rejected')
    bundle = path.parent / (scheme + '.xcresult')
    if not bundle.is_dir() or not any(p.is_file() for p in bundle.rglob('*')):
        raise ValueError('Missing completed native xcresult bundle')
    native = json.loads(path.read_text())
    # The dev adapter parsed the full completed tree with process/log/summary
    # diagnostics. Revalidate every retained attempt, including earlier failures.
    authority = contract.report(expected, native['attempts'], exit_code=native['exit_code'])
    if native.get('expected_count') != len(expected):
        report['errors'].append('native_selection_mismatch')
    report['errors'].extend(native['errors'])
    report['errors'].extend(authority['errors'])
    if (native.get('status') != 'passed' or native.get('coverage_status') != 'complete'
            or receipts[0]['status'] != native.get('status')):
        report['errors'].append('native_incomplete')
    if any(a.get('source') != 'xcresult' for a in native['attempts']):
        report['errors'].append('native_non_leaf_authority')
    if code:
        report['errors'].append('native_command_exit:' + str(code))
        report['cancelled'] += int(code in (130, -2, -15))
    report['executed'] = authority['executed_count']
    report['failed'] = sum(a['status'] == 'failed' for a in authority['attempts'])
    report['missing'] = len(authority['missing']) + len(authority['unexpected_skips'])
    # Adapter returns only after shutdown and evidence closure. Preserve the whole
    # result directory, including binary xcresult store files, without rewriting it.
    shutil.copytree(path.parent, output / 'native')
    atomic_json(output / 'test-report.json', authority)


def _test_results(root, lane, output, run, report):
    kind, expected = test_plan(root, lane)
    report['missing'] = len(expected)
    if kind == 'logic':
        # Identical swift test authority to commands.test(unit), with no guessed filter.
        argv = ['swift', 'test', '--package-path', 'ios', '--jobs', '2']
    else:
        # The same serial runner as commands.test; output is explicit and fresh so
        # evidence cannot be confused with a previous run in the canonical journal.
        argv = [sys.executable, 'ios/Eval/run-e2e.py']
        for value in expected:
            argv += ['--only', value]
        argv += ['--simulator-name', 'Today-Dev-' + derived_data(root).name[:8],
                 '--derived-data', str(derived_data(root)), '--output', str(output / 'runner')]
    if kind == 'ui':
        report['artifact_writers_closed'] = False
    result = run(root, argv, timeout=600, heavy=True)
    raw = Path(result.log).read_text()
    (output / 'command.log').write_text(Redactor()(raw))
    report['cancelled'] += int(result.reason == 'cancelled' or result.returncode in (130, -2, -15))
    attempts = contract.log_attempts(raw, kind)
    report['failed'] = sum(a['status'] == 'failed' for a in attempts)
    if result.reason != 'exited':
        report['errors'].append('process_' + result.reason)
    if kind == 'ui':
        summary = json.loads((output / 'runner/summary.json').read_text())
        if not isinstance(summary, dict):
            raise ValueError('Malformed runner summary')
        if summary.get('head') != report['sha']:
            raise ValueError('Runner SHA mismatch')
        if summary.get('selection') != expected:
            raise ValueError('Runner selection mismatch')
        if summary.get('status') != 'passed' or summary.get('journal_errors') or summary.get('shutdown_error'):
            report['errors'].append('runner_incomplete')
        stages = summary.get('stages', {})
        report['artifact_writers_closed'] = (
            result.reason == 'exited' and isinstance(stages, dict)
            and stages.get('shutdown') == 0 and not summary.get('shutdown_error'))
        if not isinstance(stages, dict) or stages.get('ui') != 0 or stages.get('shutdown') != 0 or any(
                value != 0 for value in stages.values()):
            report['errors'].append('runner_stage_failure')
        # Reparse the retained xcresult tree, rather than trusting copied counters.
        tree = json.loads((output / 'runner/xcresult-tests.json').read_text())
        attempts = contract.xcresult_attempts(tree, kind)
    authority = contract.report(expected, attempts, result.returncode, raw_log=raw)
    atomic_json(output / 'test-report.json', authority)
    report['executed'] += authority['executed_count']
    report['failed'] = max(report['failed'], sum(a['status'] == 'failed' for a in authority['attempts']))
    report['missing'] = len(authority['missing']) + len(authority['unexpected_skips'])
    report['errors'].extend(authority['errors'])
    if any(a['test'] not in expected for a in authority['attempts']):
        report['errors'].append('unexpected_test')
    if result.returncode:
        report['errors'].append('command_exit:' + str(result.returncode))


def _checks(root, lane, output, run, report):
    if lane in ('build', 'release'):
        # Extend the shared dev build recipe only with explicit no-signing flags.
        argv = ['xcodebuild', 'build', '-project', 'ios/Today.xcodeproj', '-scheme', 'Today',
                '-configuration', 'Release' if lane == 'release' else 'Debug', '-destination', 'generic/platform=iOS Simulator',
                '-derivedDataPath', str(derived_data(root)), '-jobs', '2', 'ARCHS=arm64',
                'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']
        if lane == 'release':
            maps = output / 'release-maps'
            maps.mkdir()
            argv += ['LD_GENERATE_MAP_FILE=YES', 'LD_MAP_FILE_PATH=' + str(maps / '$(TARGET_NAME)-$(PRODUCT_NAME).map')]
        result = run(root, argv, timeout=600, heavy=True)
        (output / 'command.log').write_text(Redactor()(Path(result.log).read_text()))
        report['cancelled'] += int(result.reason == 'cancelled')
        if result.returncode or result.reason != 'exited':
            report['errors'].append('command_exit:' + str(result.returncode))
            return
        configuration = 'Release' if lane == 'release' else 'Debug'
        products = derived_data(root) / ('Build/Products/' + configuration + '-iphonesimulator/One.app')
        for relative in ('One', 'PlugIns/TodayWidgets.appex/TodayWidgets', 'PlugIns/ShareExtension.appex/ShareExtension'):
            path = products / relative
            if not path.is_file() or path.is_symlink() or not path.stat().st_size:
                report['missing'] += 1
                report['errors'].append('missing_product:' + relative)
            else:
                report['executed'] += 1
        if lane == 'release' and not report['missing']:
            from scripts.release import graph

            graph_logs = output / 'release-graph'
            graph_logs.mkdir()

            def graph_run(argv, cwd):
                result = run(cwd, argv, timeout=60, heavy=False)
                raw = Path(result.log).read_text()
                (graph_logs / (str(len(list(graph_logs.iterdir()))) + '.log')).write_text(Redactor()(raw))
                if result.returncode or result.reason != 'exited':
                    raise ValueError('Release graph command failed')
                return raw

            def require(ok, code):
                if not ok:
                    raise ValueError(code)

            atomic_json(output / 'release-graph.json', graph.check(root, graph_run, require))
            from scripts.release import release
            try:
                release.validate_resources(root, products)
                release.bind_product_link_maps(root, products, maps, result.log)
                release.validate_product_link_maps(root, products, maps, target_names=True)
            except release.Blocked as error:
                raise ValueError('Release artifact resources rejected: ' + str(error)) from None
            # Actual Release simulator resources and executable-bound linker inputs
            # are accepted here. Archive/signing/distribution retain separate gates.
        return
    # Keep pinned tool resolution, exact flags and path scope in commands.py.
    # Its execute() prints JSON receipts carrying the real retained log paths.
    import contextlib
    import io
    if lane == 'format' and not format_inputs(root):
        raise ValueError('Zero Swift format inputs')
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        code = commands.format_sources(root, check=True) if lane == 'format' else commands.lint(root)
    receipts = [json.loads(line) for line in captured.getvalue().splitlines() if line.startswith('{')]
    logs = [Path(r['log']).read_text() for r in receipts if 'log' in r]
    (output / 'command.log').write_text(Redactor()('\n'.join(logs)))
    if not receipts or not logs:
        raise ValueError('Dev command did not retain execution receipts')
    report['cancelled'] += sum(r.get('reason') == 'cancelled' for r in receipts)
    if code or any(r.get('exit') != 0 or r.get('reason') != 'exited' for r in receipts):
        report['errors'].append('dev_check_failure')
        return
    # swift-format receives this explicit file set in commands.format_sources.
    if lane == 'format':
        report['executed'] += len(format_inputs(root))
    else:
        # Count actual successful tool invariants, not an invented count of files
        # that SwiftLint may have excluded through its configuration.
        expected = 3 if (root / '.github/workflows').is_dir() else 2
        if len(receipts) != expected:
            raise ValueError('Missing lint tool receipts')
        if not any(re.search(r'in [1-9][0-9]* files?', log) for log in logs):
            raise ValueError('SwiftLint did not confirm a positive checked-file count')
        report['executed'] += expected


def format_inputs(root):
    return [p for folder in ('ios/Sources', 'ios/One', 'ios/Development', 'ios/TodayWidgets',
            'ios/ShareExtension', 'ios/OneUITests', 'ios/Eval/Tests')
            for p in (root / folder).rglob('*.swift') if p.is_file()]


def _main(root, lane, *, selection, output, sha, synthetic, no_distribute, runner=None):
    """Runner injection is for host regressions, never a CI simulation/success mode."""
    root, output = Path(root).resolve(), Path(output).absolute()
    report = {'sha': sha, 'lane': lane, 'status': 'failed', 'executed': 0, 'failed': 0,
              'cancelled': 0, 'missing': 0, 'synthetic': synthetic is True, 'errors': []}
    # Never replace a previous report or accept pre-seeded results. The CI wrapper
    # creates the output directory and selection.json before invoking this API.
    try:
        if output.is_symlink() or (output.exists() and any(
                p.name != 'selection.json' or p.is_symlink() for p in output.iterdir())):
            raise ValueError('output must be fresh (only selection.json is allowed)')
        output.mkdir(parents=True, exist_ok=True)
    except (OSError, ValueError) as error:
        print('ci: ' + Redactor()(str(error)), file=sys.stderr)
        return 1
    try:
        if lane not in LANES:
            raise ValueError('Unknown CI lane')
        if synthetic is not True or no_distribute is not True:
            raise ValueError('CI requires synthetic=True and no_distribute=True')
        from scripts.ci.run import producer_boundary
        producer_boundary(sha, lane, output)
        if output.resolve().is_relative_to(root):
            raise ValueError('CI output must be outside the source workspace')
        selected = selection_data(selection)
        atomic_json(output / 'accepted-selection.json', selected)
        before = source_state(root, sha)
        report['source_sha256'] = before
        if lane in MANUAL and (os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
                               or os.environ.get('MANUAL_LANE') != lane):
            raise ValueError('Manual lane requires explicit matching workflow dispatch')
        if lane in UNSUPPORTED:
            raise ValueError(UNSUPPORTED[lane])
        run = runner or commands.execute
        if lane in ('integration', 'snapshots'):
            _native_results(root, lane, output, report)
        elif lane in ('business', 'core-ui', 'extended'):
            _test_results(root, lane, output, run, report)
        else:
            _checks(root, lane, output, run, report)
        if source_state(root, sha) != before:
            raise ValueError('Source changed during CI execution')
        if not report['errors'] and report['executed'] > 0 and not any(report[k] for k in ('failed', 'cancelled', 'missing')):
            validate_report(dict(report, status='passed'), sha, lane)
            report['status'] = 'passed'
    except KeyboardInterrupt:
        report['cancelled'] += 1
        report['errors'].append('cancelled')
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        report['errors'].append(Redactor()(type(error).__name__ + ': ' + str(error)))
    finally:
        if report['status'] != 'passed' and not report['failed'] and not report['cancelled'] and not report['missing']:
            report['failed'] = 1
        report['errors'] = list(dict.fromkeys(report['errors']))
        try:
            from scripts.ci.run import close_producer
            if report.get('artifact_writers_closed') is False:
                raise ValueError('runner writers or owned simulator shutdown not closed')
            close_producer(output, report, roots=(
                'selection.json', 'accepted-selection.json', 'command.log',
                'test-report.json', 'native', 'runner', 'release-graph.json', 'release-graph', 'release-maps'))
        except (OSError, ValueError, KeyError, TypeError) as error:
            report.pop('artifact_provenance', None)
            report['status'] = 'failed'
            report['failed'] = max(1, report['failed'])
            report['errors'].append('producer_close_rejected:' + type(error).__name__)
            atomic_json(output / 'report.json', report)
    return 0 if report['status'] == 'passed' else 1


def main(root, lane, *, selection, output, sha, synthetic, no_distribute):
    """Run one CI lane. CLI wiring is owned by integration."""
    return _main(root, lane, selection=selection, output=output, sha=sha,
                 synthetic=synthetic, no_distribute=no_distribute)
