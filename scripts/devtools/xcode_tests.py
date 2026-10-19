"""Serial Xcode test authorities with completed leaf evidence and no build cache bypass."""
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import tempfile
import uuid

from .core import ResourceLock, atomic_json, dd_lock, derived_data, host_lock
from .process import Evidence, Redactor, run_process

SCHEMES = {'unit': 'TodayTests', 'integration': 'TodayTests', 'snapshot': 'TodaySnapshotTests'}
DEVICE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'


def simulator_name(root):
    return 'Today-Dev-' + derived_data(root).name[:8]


def selected(contract, root, groups, only=()):
    source = contract.inventory(root)
    plan = contract.plan(list(groups), source)
    lanes = {lane: values for lane, values in plan['selectors'].items() if values}
    if not lanes or set(lanes) - set(SCHEMES):
        raise ValueError('Xcode adapter requires only iOS unit, integration or snapshot lanes')
    if only:
        narrowed = {lane: [] for lane in lanes}
        for value in only:
            matches = {}
            for lane in lanes:
                try:
                    matches[lane] = contract.expand([value], source, lane)
                except ValueError:
                    continue
            if not matches:
                raise ValueError('Unknown selection: ' + value)
            for lane, ids in matches.items():
                if set(ids) - set(lanes[lane]):
                    raise ValueError('Selection outside requested group: ' + value)
                narrowed[lane].extend(ids)
        lanes = {lane: list(dict.fromkeys(ids)) for lane, ids in narrowed.items() if ids}
    return lanes


def completed_report(contract, expected, lane, data, exit_code, raw_log, parser_error=None):
    attempts = []
    try:
        if parser_error:
            raise ValueError(parser_error)
        attempts = contract.xcresult_attempts(data, lane)
    except (ValueError, TypeError, KeyError) as error:
        parser_error = str(error)
    report = contract.report(expected, attempts, exit_code=exit_code, raw_log=raw_log)
    if parser_error:
        report['status'] = 'failed'
        report['coverage_status'] = 'incomplete'
        report['errors'] = list(dict.fromkeys([*report['errors'], 'parser_error']))
        report['parser_detail'] = parser_error
    return report


def run(root, contract, groups, *, only=(), timeout=600, locked=False):
    """Caller may hold the shared host/DD locks across a final serial collection."""
    lanes = selected(contract, root, groups, only)
    batches = {}
    for lane, ids in lanes.items():
        batch = batches.setdefault(SCHEMES[lane], {'lane': lane, 'expected': []})
        batch['expected'].extend(ids)
    first_failure = 0
    with ExitStack() as stack:
        if not locked:
            stack.enter_context(host_lock(root))
            stack.enter_context(dd_lock(root))
        # Share the existing UI runner's name/cache lock protocol.
        for key in sorted(['name:' + simulator_name(root), 'cache:' + str(derived_data(root).resolve())]):
            path = Path(tempfile.gettempdir()) / ('today-qa-lock-' + hashlib.sha256(key.encode()).hexdigest())
            stack.enter_context(ResourceLock(path, str(root)))
        evidence = Evidence(root, 'dev-xcode-' + uuid.uuid4().hex, Redactor())
        stack.callback(evidence.close)
        output = evidence.path.parent / (evidence.path.stem + '-xcode')
        output.mkdir()

        def invoke(command):
            # Each process owns a unique raw log, indexed by the existing QA helper.
            evidence.path = output / (uuid.uuid4().hex + '.log')
            return run_process(command, cwd=root, evidence=evidence, timeout=timeout)

        def capture(command):
            result = invoke(command)
            if result.returncode:
                raise ValueError('Command failed: ' + str(command) + '; log=' + str(result.log))
            return result.log.read_text()

        simulator = None
        owned = False
        try:
            devices = json.loads(capture(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
            matches = [dict(device, runtime=runtime) for runtime, values in devices['devices'].items()
                       for device in values if device['name'] == simulator_name(root)]
            if len(matches) > 1:
                raise ValueError('Ambiguous owned simulator name')
            if matches:
                device = matches[0]
                if (device.get('deviceTypeIdentifier') != DEVICE or device['runtime'] != RUNTIME
                        or device['state'] != 'Shutdown'):
                    raise ValueError('Owned simulator must be shutdown with the canonical model/runtime')
                simulator = device['udid']
            else:
                simulator = capture(['xcrun', 'simctl', 'create', simulator_name(root), DEVICE, RUNTIME]).strip()
            # Validate before passing a captured identifier back into platform commands.
            uuid.UUID(simulator)
            owned = True
            capture(['xcrun', 'simctl', 'boot', simulator])
            capture(['xcrun', 'simctl', 'bootstatus', simulator, '-b'])
            for scheme, batch in batches.items():
                bundle = output / (scheme + '.xcresult')
                expected = list(dict.fromkeys(batch['expected']))
                from .resolve import locked_arguments
                flags = locked_arguments(root)
                result = invoke(['xcodebuild', 'test', '-project', 'ios/Today.xcodeproj', '-scheme', scheme,
                                 '-configuration', 'Debug', '-sdk', 'iphonesimulator',
                                 '-destination', 'platform=iOS Simulator,id=' + simulator,
                                 '-derivedDataPath', str(derived_data(root)), '-resultBundlePath', str(bundle),
                                 '-jobs', '2', '-parallel-testing-enabled', 'NO',
                                 '-maximum-concurrent-test-simulator-destinations', '1',
                                 '-maximum-parallel-testing-workers', '1',
                                 *flags, *['-only-testing:' + value for value in expected]])
                raw = result.log.read_text()
                data, error, summary = None, None, None
                try:
                    if not bundle.is_dir():
                        raise ValueError('Missing completed xcresult bundle')
                    summary = json.loads(capture(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                                  '--path', str(bundle), '--format', 'json']))
                    if not isinstance(summary, dict):
                        raise ValueError('Malformed xcresult summary')
                    data = json.loads(capture(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                                               '--path', str(bundle), '--format', 'json']))
                except (OSError, ValueError, TypeError) as exc:
                    error = str(exc)
                report = completed_report(contract, expected, batch['lane'], data, result.returncode, raw, error)
                if summary and summary.get('failedTests', 0) and not any(
                        attempt['status'] == 'failed' for attempt in report['attempts']):
                    report['status'] = 'failed'
                    report['coverage_status'] = 'incomplete'
                    report['errors'].append('xcresult_summary_failure')
                path = output / (scheme + '.report.json')
                atomic_json(path, report)
                evidence.journal.artifact(evidence.session, path)
                # Only index a completed bundle after the owned xcodebuild has exited.
                if bundle.is_dir():
                    for artifact in sorted(bundle.rglob('*')):
                        if artifact.is_file() and not artifact.is_symlink():
                            evidence.journal.artifact(evidence.session, artifact)
                evidence.record(json.dumps({'scheme': scheme, 'report': str(path), 'status': report['status']}),
                                report['status'])
                print(json.dumps({'report': str(path), 'status': report['status']}))
                first_failure = first_failure or result.returncode or (report['status'] != 'passed')
        finally:
            if owned:
                shutdown = invoke(['xcrun', 'simctl', 'shutdown', simulator])
                first_failure = first_failure or shutdown.returncode
    return int(first_failure)
