#!/usr/bin/env python3
"""Profile one existing Year UI journey after explicit host handoff.

Caller must show the booted Today-Performance device. simctl verifies boot/state,
not visibility. No build/boot/manual install/settings/data reset. xcodebuild's
normal test-without-building deployment is allowed. All metrics are diagnosis
only, excluded from acceptance. Preserve partial xcresult/trace on failure.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import uuid


def exact_pids(text, simulator):
    return [int(parts[0]) for line in text.splitlines()
            if len(parts := line.strip().split(maxsplit=1)) == 2
            and f'/Devices/{simulator}/' in parts[1]
            and parts[1].endswith('/One.app/One')]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--simulator', required=True)
    p.add_argument('--derived-data', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--project', type=Path)
    p.add_argument('--wall-limit', type=float, default=150,
                   help='Total seconds INCLUDING 10s reserved cleanup; max150')
    p.add_argument('--pid-wait-limit', type=float, default=60,
                   help='Target-discovery cap; leaves40s active work plus reserved cleanup')
    a = p.parse_args(argv)
    if not 15 <= a.wall_limit <= 150:
        p.error('--wall-limit must be between15 and150 seconds including cleanup')
    if not 1 <= a.pid_wait_limit <= 60:
        p.error('--pid-wait-limit must be between1 and60 seconds')
    out = a.output.expanduser().absolute()
    try:
        out.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        p.error('Output exists; use a new canonical directory; no evidence overwritten')
    started = time.monotonic()
    deadline = started + a.wall_limit
    active_end = deadline - 10
    processes, streams, locks = [], [], []
    status = {'status': 'running', 'classification': 'profiled diagnosis; excluded from acceptance',
              'wall_limit': a.wall_limit, 'cleanup_reserve': 10,
              'caller_must_have_global_handoff_and_visible_device': True, 'commands': []}

    def save():
        (out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')

    def remaining():
        budget = active_end - time.monotonic()
        if budget <= 0:
            raise TimeoutError('Active budget exhausted; preserving partial output')
        return budget

    def launch(label, cmd):
        remaining()
        status['commands'].append({'label': label, 'argv': cmd})
        save()
        log = (out / (label + '.log')).open('x')
        streams.append(log)
        child = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(child)
        return child

    def read(label, cmd, limit=5):
        child = launch(label, cmd)
        code = child.wait(timeout=min(limit, remaining()))
        if code:
            raise RuntimeError(f'{label} failed exit{code}; see raw log; no retry')
        return (out / (label + '.log')).read_text(errors='replace')

    def ps(label):
        return exact_pids(read(label, ['ps', '-axo', 'pid=,comm='], 2), a.simulator)

    save()
    try:
        a.simulator = str(uuid.UUID(a.simulator)).upper()
        dd = a.derived_data.expanduser().resolve(strict=True)
        products = dd / 'Build/Products'
        if not products.is_dir():
            raise RuntimeError('Existing derived-data Products required; no build fallback')
        # Same exact name/cache lock keys as with_owned_runner.py and run-e2e.py.
        for key in sorted(['name:Today-Performance', 'cache:' + str(dd)]):
            lock = (Path(tempfile.gettempdir()) / ('today-qa-lock-' + hashlib.sha256(key.encode()).hexdigest())).open('a')
            locks.append(lock)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        inventory = json.loads(read('inventory', ['xcrun', 'simctl', 'list', 'devices', '-j']))
        matches = [(runtime, dev) for runtime, group in inventory['devices'].items() for dev in group
                   if dev.get('udid', '').upper() == a.simulator]
        if len(matches) != 1 or not matches[0][0].startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
            raise RuntimeError('Exactly one iOS simulator required; physical targets forbidden')
        dev = matches[0][1]
        if dev.get('name') != 'Today-Performance' or dev.get('state') != 'Booted' or dev.get('isAvailable') is not True:
            raise RuntimeError('Available booted Today-Performance required; no automatic boot')
        status['simulator'] = dev
        if ps('initial-processes'):
            raise RuntimeError('Installed target must be stopped before UI runner; no automatic termination')
        app = Path(read('installed-app', ['xcrun', 'simctl', 'get_app_container', a.simulator, 'com.luworks.one', 'app']).strip())
        candidates = list(products.glob('*/One.app/One'))
        if len(candidates) != 1 or not (app / 'One').is_file():
            raise RuntimeError('Exactly one existing One product and installed executable required')
        product_hash, installed_hash = digest(candidates[0]), digest(app / 'One')
        status['artifact'] = {'product': str(candidates[0]), 'installed': str(app / 'One'),
                              'product_sha256': product_hash, 'installed_sha256': installed_hash}
        if product_hash != installed_hash:
            raise RuntimeError('Installed/product executable mismatch; no install/build fallback')
        project = a.project or dd.parent / 'build-source/ios/One.xcodeproj'
        project = project.resolve(strict=True)
        test = ['xcodebuild', 'test-without-building', '-project', str(project), '-scheme', 'One',
                '-configuration', 'Debug', '-derivedDataPath', str(dd), 'SWIFT_OPTIMIZATION_LEVEL=-O',
                '-destination', 'id=' + a.simulator,
                '-only-testing:OneUITests/PerformanceClimbTests/testYearScrollMemory',
                '-parallel-testing-enabled', 'NO', '-jobs', '2', '-resultBundlePath', str(out / 'ui.xcresult')]
        # A cold XCTest worker can take most of30s before the app even starts.
        # Preserve a separate capture/journey budget instead of cancelling at that point.
        if remaining() <= 40:
            raise TimeoutError('Insufficient active budget for target discovery and journey')
        runner = launch('ui-runner', test)
        pid_end = min(active_end - 40, time.monotonic() + a.pid_wait_limit)
        status['pid_wait_limit'] = a.pid_wait_limit
        status['pid_discovery_budget'] = max(0, pid_end - time.monotonic())
        iteration = 0
        while True:
            if runner.poll() is not None:
                raise RuntimeError('UI runner exited before target discovery; see raw log')
            if time.monotonic() >= pid_end:
                raise TimeoutError('Target PID not discovered within bounded readiness budget')
            found = ps(f'pid-{iteration}')
            if len(found) > 1:
                raise RuntimeError('Ambiguous exact target PIDs; no alternate attach')
            if found:
                target = found[0]
                break
            iteration += 1
            time.sleep(min(1, max(0, pid_end - time.monotonic())))
        status['attached_pid'] = target
        profiler = launch('profiler', ['xcrun', 'xctrace', 'record', '--device', a.simulator,
            '--template', 'Time Profiler', '--instrument', 'os_signpost', '--time-limit', '20s',
            '--output', str(out / 'year.trace'), '--attach', str(target)])
        while runner.poll() is None or profiler.poll() is None:
            remaining()
            if profiler.poll() is not None and profiler.returncode != 0:
                raise RuntimeError('Profiler attach/record failed; raw error retained; no retry')
            if runner.poll() is not None and runner.returncode != 0:
                raise RuntimeError('UI journey failed; raw logs/partial xcresult retained')
            time.sleep(min(0.25, remaining()))
        status['runner_exit_code'] = runner.returncode
        status['profiler_exit_code'] = profiler.returncode
        if runner.returncode != 0 or profiler.returncode != 0:
            raise RuntimeError('Producer failed at completion; inspect raw logs; no retry')
        # Both producers have closed before any optional TOC read. No schema guessing.
        if active_end - time.monotonic() > 6:
            read('toc-export', ['xcrun', 'xctrace', 'export', '--input', str(out / 'year.trace'),
                              '--toc', '--output', str(out / 'toc.xml')], 5)
        else:
            status['toc_skipped'] = 'Insufficient reserved budget; parent may export separately'
        status['status'] = 'passed'
    except (OSError, ValueError, KeyError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as e:
        status.update(status='failed', error=str(e))
    except KeyboardInterrupt:
        status.update(status='interrupted', error='Caller interrupted')
    finally:
        # Signal BOTH owned process groups first; never kill a guessed app PID.
        live = [c for c in processes if c.poll() is None]
        for sig, seconds in [(signal.SIGINT, 6), (signal.SIGTERM, 2), (signal.SIGKILL, 1)]:
            for child in live:
                if child.poll() is None:
                    try:
                        os.killpg(child.pid, sig)
                    except ProcessLookupError:
                        pass
            end = min(deadline, time.monotonic() + seconds)
            for child in live:
                if child.poll() is None:
                    try:
                        child.wait(timeout=max(0, end - time.monotonic()))
                    except subprocess.TimeoutExpired:
                        pass
        status['unreaped_child_pids'] = [c.pid for c in processes if c.poll() is None]
        status['process_exit_codes'] = [c.poll() for c in processes]
        for stream in streams:
            stream.close()
        for lock in reversed(locks):
            lock.close()
        status['elapsed_seconds'] = time.monotonic() - started
        save()
    print(json.dumps({'output': str(out), 'status': status['status'], 'error': status.get('error')}))
    return 0 if status['status'] == 'passed' and not status['unreaped_child_pids'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
