#!/usr/bin/env python3
"""One bounded first-PID conversation profile; caller owns the visible simulator.

No build, boot, manual install, settings changes or target-app termination. The
existing n3 method relaunches the app: only its first PID is profiled, for
diagnosis, never speed acceptance. The caller shuts down/releases the device.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


from simulator_policy import ACTIVE_NAME, ACTIVE_UDID

SIMULATOR = ACTIVE_UDID
ROOT = Path('/Users/yuanlu/code/one-app/tests/results/runs')
PAGES = ROOT / 'performance-pages-ai-20261018'
DD = ROOT / 'performance-climb-20261018/derived-optimized'
PROJECT = PAGES / 'build-source/ios/One.xcodeproj'
REFERENCE = PAGES / 'layout-attribution-v3-products/One.app'
PRODUCT = DD / 'Build/Products/Debug-iphonesimulator/One.app'
TEST_BUNDLE = DD / 'Build/Products/Debug-iphonesimulator/OneUITests-Runner.app/PlugIns/OneUITests.xctest'
SELECTOR = 'OneUITests/AIResponsePerformanceTests/testConversationFreshLaunchN3'
METHOD_START = "Test Case '-[OneUITests.AIResponsePerformanceTests testConversationFreshLaunchN3]' started."


def exact_processes(text):
    """Return PID/path pairs, excluding runner names and unrelated devices."""
    found = []
    for line in text.splitlines():
        parts = line.strip().split(maxsplit=1)
        if (len(parts) == 2 and parts[0].isdigit()
                and f'/Devices/{SIMULATOR}/' in parts[1]
                and parts[1].endswith('/One.app/One')):
            found.append((int(parts[0]), parts[1]))
    return found


def owned_booted_device(inventory):
    matches = [(runtime, dev) for runtime, group in inventory['devices'].items()
               for dev in group if dev.get('udid') == SIMULATOR]
    if len(matches) != 1:
        raise RuntimeError('Exactly one owned simulator required')
    runtime, dev = matches[0]
    if (not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
            or dev.get('name') != ACTIVE_NAME
            or dev.get('state') != 'Booted' or dev.get('isAvailable') is not True):
        raise RuntimeError('Available Booted active performance simulator required; caller must show it')
    return dev


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def verify_app(app):
    result = {}
    for name in ('One', 'One.debug.dylib'):
        expected, actual = REFERENCE / name, app / name
        if name == 'One.debug.dylib' and not expected.exists() and not actual.exists():
            result[name] = {'presence': 'absent_in_both; no separate debug dylib'}
            continue
        if not expected.is_file() or not actual.is_file():
            raise RuntimeError(f'{name}: reference/product presence mismatch')
        hashes = {'reference_sha256': digest(expected), 'actual_sha256': digest(actual)}
        if hashes['reference_sha256'] != hashes['actual_sha256']:
            raise RuntimeError(f'{name}: executable hash mismatch; no build/install fallback')
        result[name] = hashes
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--wall-limit', type=float, default=150)
    args = parser.parse_args(argv)
    if not 30 <= args.wall_limit <= 150:
        parser.error('--wall-limit must be 30..150 seconds INCLUDING 10s cleanup')
    out = args.output.expanduser().resolve()
    if not out.is_relative_to(ROOT.resolve()):
        parser.error('--output must be a new canonical directory under primary tests/results/runs')
    try:
        out.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.error('Output already exists; evidence must never be overwritten')
    start = time.monotonic()
    deadline, active_end = start + args.wall_limit, start + args.wall_limit - 10
    children, streams, locks = [], [], []
    previous_sigterm = signal.getsignal(signal.SIGTERM)

    def interrupted(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    status = {'status': 'running', 'classification': 'profiled diagnosis only; no speed acceptance',
              'scope': 'first app PID only; subsequent n3 relaunches are not attached',
              'caller_owns_handoff_visible_device_and_shutdown': True,
              'wall_limit': args.wall_limit, 'cleanup_reserve': 10, 'commands': []}

    def save():
        (out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')

    def remaining():
        value = active_end - time.monotonic()
        if value <= 0:
            raise TimeoutError('Active budget exhausted; preserving partial evidence')
        return value

    def launch(label, command):
        remaining()
        status['commands'].append({'label': label, 'argv': command,
                                   'monotonic_before': time.monotonic()})
        save()
        stdout = (out / (label + '.stdout')).open('xb')
        stderr = (out / (label + '.stderr')).open('xb')
        streams.extend([stdout, stderr])
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
        children.append((label, child))
        return child

    def read(label, command, timeout=5):
        child = launch(label, command)
        code = child.wait(timeout=min(timeout, remaining()))
        if code:
            raise RuntimeError(f'{label} exit{code}; inspect raw output; no retry')
        return (out / (label + '.stdout')).read_text(errors='replace')

    def processes(label):
        return exact_processes(read(label, ['ps', '-axo', 'pid=,comm='], 2))

    def pause():
        time.sleep(min(0.25, remaining()))

    save()
    try:
        for key in sorted(['name:' + ACTIVE_NAME, 'cache:' + str(DD.resolve(strict=True))]):
            lock = (Path(tempfile.gettempdir()) / ('today-qa-lock-' + hashlib.sha256(key.encode()).hexdigest())).open('a')
            locks.append(lock)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        status['device'] = owned_booted_device(json.loads(read('inventory', ['xcrun', 'simctl', 'list', 'devices', '-j'])))
        if processes('initial-processes'):
            raise RuntimeError('Owned One must initially be stopped; no automatic termination')
        status['product_hashes'] = verify_app(PRODUCT)
        app = Path(read('initial-container', ['xcrun', 'simctl', 'get_app_container', SIMULATOR, 'com.luworks.one', 'app']).strip())
        status['initial_installed_hashes'] = verify_app(app)
        if not PROJECT.is_dir() or not TEST_BUNDLE.is_dir():
            raise RuntimeError('Existing project and test bundle required; no generation/build fallback')
        snapshot = out / 'test-bundle/OneUITests.xctest'
        shutil.copytree(TEST_BUNDLE, snapshot, symlinks=True)
        status['test_bundle'] = {'source': str(TEST_BUNDLE), 'snapshot': str(snapshot), 'files': {
            str(path.relative_to(snapshot)): digest(path) for path in sorted(snapshot.rglob('*')) if path.is_file()}}
        remaining()
        command = ['xcodebuild', 'test-without-building', '-project', str(PROJECT), '-scheme', 'One',
                   '-configuration', 'Debug', '-derivedDataPath', str(DD),
                   '-destination', 'id=' + SIMULATOR, '-only-testing:' + SELECTOR,
                   '-parallel-testing-enabled', 'NO', '-jobs', '2', 'SWIFT_OPTIMIZATION_LEVEL=-O',
                   '-resultBundlePath', str(out / 'ui.xcresult')]
        (out / 'test-command.json').write_text(json.dumps(command, indent=2) + '\n')
        status['test_command_sha256'] = digest(out / 'test-command.json')
        runner = launch('ui-runner', command)
        method_deadline = min(active_end, time.monotonic() + 60)
        while not any(METHOD_START in (out / ('ui-runner.' + suffix)).read_text(errors='replace')
                      for suffix in ('stdout', 'stderr')):
            if runner.poll() is not None:
                raise RuntimeError('Runner exited before exact method start; no attach')
            if time.monotonic() >= method_deadline:
                raise TimeoutError('Exact method start not observed within60s; no attach')
            pause()
        status['method_start_observed_monotonic'] = time.monotonic()
        pid_deadline, iteration = min(active_end, time.monotonic() + 15), 0
        while True:
            if runner.poll() is not None:
                raise RuntimeError('Runner exited before first app PID discovery')
            if time.monotonic() >= pid_deadline:
                raise TimeoutError('First app PID not discovered within15s of observed method start')
            found = processes(f'pid-{iteration}')
            iteration += 1
            if len(found) > 1:
                raise RuntimeError('Ambiguous exact app PIDs; no guessed attach')
            if found:
                target, executable = found[0]
                break
            pause()
        app = Path(read('target-container', ['xcrun', 'simctl', 'get_app_container', SIMULATOR, 'com.luworks.one', 'app']).strip())
        if Path(executable).resolve(strict=True) != (app / 'One').resolve(strict=True):
            raise RuntimeError('Actual PID executable does not match current installed app container')
        status['attached_app_hashes'] = verify_app(app)
        if processes('verified-processes') != [(target, executable)]:
            raise RuntimeError('First PID changed during validation; no alternate attach')
        status.update(first_pid=target, executable=executable,
                      pid_verified_monotonic=time.monotonic())
        if remaining() < 32:
            raise TimeoutError('Insufficient remaining budget for one30s capture')
        profiler = launch('profiler', ['xcrun', 'xctrace', 'record', '--device', SIMULATOR,
                         '--template', 'Time Profiler', '--instrument', 'os_signpost',
                         '--time-limit', '30s', '--output', str(out / 'conversation.trace'),
                         '--attach', str(target)])
        while runner.poll() is None or profiler.poll() is None:
            remaining()
            for label, child in [('runner', runner), ('profiler', profiler)]:
                if child.poll() is not None and child.returncode != 0:
                    raise RuntimeError(f'{label} exit{child.returncode}; preserve evidence; no retry')
            pause()
        if runner.returncode != 0 or profiler.returncode != 0:
            raise RuntimeError('Nonzero producer exit; profile not accepted')
        if not (out / 'conversation.trace').exists():
            raise RuntimeError('Profiler returned zero without a trace artifact')
        status.update(runner_exit_code=runner.returncode, profiler_exit_code=profiler.returncode)
        if active_end - time.monotonic() > 6:
            read('toc-export', ['xcrun', 'xctrace', 'export', '--input', str(out / 'conversation.trace'),
                               '--toc', '--output', str(out / 'toc.xml')], 5)
        else:
            status['toc_skipped'] = 'Insufficient budget; export separately after producers close'
        status['modeled_export'] = 'Parent inspects actual TOC schemas before bounded export; no guessed XPath'
        status['status'] = 'recorded; interval coverage/symbols/clock alignment still require analysis'
    except (OSError, ValueError, KeyError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
        status.update(status='failed', error=str(error))
    except KeyboardInterrupt:
        status.update(status='interrupted', error='Caller interrupted')
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        # Stop both owned producer groups; never signal a guessed target-app PID.
        for sig, seconds in [(signal.SIGINT, 6), (signal.SIGTERM, 2), (signal.SIGKILL, 1)]:
            live = [child for _, child in children if child.poll() is None]
            for child in live:
                try:
                    os.killpg(child.pid, sig)
                except ProcessLookupError:
                    pass
            until = min(deadline, time.monotonic() + seconds)
            for child in live:
                try:
                    child.wait(timeout=max(0, until - time.monotonic()))
                except subprocess.TimeoutExpired:
                    pass
        status['process_exit_codes'] = {label: child.poll() for label, child in children}
        status['unreaped_child_pids'] = [child.pid for _, child in children if child.poll() is None]
        for stream in streams:
            stream.close()
        for lock in reversed(locks):
            lock.close()
        status['elapsed_seconds'] = time.monotonic() - start
        save()
        signal.signal(signal.SIGTERM, previous_sigterm)
    print(json.dumps({'output': str(out), 'status': status['status'], 'error': status.get('error')}))
    return 0 if status['status'].startswith('recorded;') and not status['unreaped_child_pids'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
