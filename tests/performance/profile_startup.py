#!/usr/bin/env python3
"""Parent-owned, opt-in startup diagnosis of an already installed simulator app.

Run only after explicit global host handoff, with Today-Performance visible and
booted and the target app stopped. Never boots, builds, installs, resets data,
changes settings, retries, or attaches after launch. Profiled timings must remain
separate from unprofiled benchmark samples. The caller indexes completed output
through tests/qa/journal.py; no schema-dependent hotspot parser runs here.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid

BUNDLE_ID = 'com.luworks.one'
TOTAL_LIMIT = 60
RECORD_LIMIT = 10
RECORD_WATCHDOG = 45


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


class CaptureError(RuntimeError):
    pass


class Commands:
    """Keep raw commands/output; bound this invocation, including cleanup, to 60s."""
    def __init__(self, output, deadline):
        self.output = output
        self.deadline = deadline
        self.history = []
        self.unreaped = []

    def remaining(self):
        return max(0, self.deadline - time.monotonic())

    def wait(self, process, seconds):
        budget = min(seconds, self.remaining())
        if budget <= 0:
            raise subprocess.TimeoutExpired(process.args, 0)
        return process.wait(timeout=budget)

    def stop(self, process, entry):
        # Interrupt allows Instruments to save. Escalation targets only our group.
        for sig, grace in [(signal.SIGINT, 7), (signal.SIGTERM, 2), (signal.SIGKILL, 1)]:
            if process.poll() is not None:
                return
            entry.setdefault('cleanup_signals', []).append(sig.name)
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                return
            try:
                self.wait(process, grace)
                return
            except subprocess.TimeoutExpired:
                continue
        if process.poll() is None:
            self.unreaped.append(process.pid)
            entry['unreaped_pid'] = process.pid

    def run(self, label, command, timeout):
        # Reserve cleanup time within the single global deadline, never sleep/poll.
        budget = min(timeout, self.remaining() - 10)
        if budget <= 0:
            raise CaptureError(f'Global time budget exhausted before {label}')
        entry = {'label': label, 'command': command, 'started': timestamp(),
                 'timeout_seconds': budget}
        self.history.append(entry)
        write_json(self.output / 'commands.json', self.history)
        with (self.output / f'{label}.stdout.log').open('x') as stdout, \
                (self.output / f'{label}.stderr.log').open('x') as stderr:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr,
                                       start_new_session=True)
            try:
                entry['exit_code'] = self.wait(process, budget)
            except subprocess.TimeoutExpired:
                entry['timed_out'] = True
                self.stop(process, entry)
                entry['exit_code'] = process.poll()
            except BaseException:
                entry['interrupted'] = True
                self.stop(process, entry)
                entry['exit_code'] = process.poll()
                raise
            finally:
                entry['finished'] = timestamp()
                write_json(self.output / 'commands.json', self.history)
        if entry.get('timed_out'):
            raise CaptureError(f'{label} timed out; raw/possibly incomplete evidence retained; no retry')
        if entry['exit_code'] != 0:
            raise CaptureError(f'{label} failed ({entry["exit_code"]}); inspect {label}.stdout.log and {label}.stderr.log; no retry')
        return (self.output / f'{label}.stdout.log').read_text(errors='replace')


def durable_fixture(path):
    path = path.expanduser().resolve(strict=True)
    if not path.is_file():
        raise CaptureError('Fixture must be an existing regular file')
    temporary = [Path('/tmp'), Path('/private/tmp'), Path('/var/tmp'),
                 Path('/private/var/tmp'), Path(tempfile.gettempdir()).resolve()]
    if any(path == root or root in path.parents for root in temporary):
        raise CaptureError('Fixture must be durable, outside temporary directories')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return path, digest.hexdigest()


def capture(args, output, commands, status):
    fixture, digest = durable_fixture(args.fixture)
    status['fixture'] = {'path': str(fixture), 'sha256': digest,
                         'bytes': fixture.stat().st_size}
    simulator_id = str(uuid.UUID(args.simulator)).upper()
    inventory = json.loads(commands.run('simulator-inventory',
        ['xcrun', 'simctl', 'list', 'devices', '-j'], 5))
    matches = [(runtime, device) for runtime, devices in inventory['devices'].items()
               for device in devices if device.get('udid', '').upper() == simulator_id]
    if len(matches) != 1:
        raise CaptureError('UDID must identify exactly one simulator in simctl inventory')
    runtime, device = matches[0]
    if (not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
            or device.get('name') != 'Today-Performance'
            or device.get('state') != 'Booted'
            or device.get('isAvailable') is not True):
        raise CaptureError('Target must be the available, booted iOS Today-Performance simulator; no automatic boot')
    status['simulator'] = {'runtime': runtime, 'device': device,
                           'physical_device': False}
    installed = commands.run('installed-app-path',
        ['xcrun', 'simctl', 'get_app_container', simulator_id, BUNDLE_ID, 'app'], 5).strip()
    app = Path(installed)
    if not installed or not app.is_absolute() or app.suffix != '.app' or not app.is_dir():
        raise CaptureError('simctl did not resolve an installed .app directory')
    executable = app / 'One'
    if not executable.is_file():
        raise CaptureError('Installed One executable is missing; no build/install fallback')
    status['installed_app'] = str(app)
    identity = commands.run('installed-uuid', ['xcrun', 'dwarfdump', '--uuid', str(executable)], 5)
    uuids = re.findall(r'^UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)', identity, re.MULTILINE)
    if not uuids:
        raise CaptureError('No installed executable UUID available; cannot identify profiled artifact')
    status['installed_uuids'] = [{'uuid': value, 'architecture': arch} for value, arch in uuids]
    status['artifact_configuration'] = 'Caller must verify UUID matches optimized Debug -O artifact; not inferred'
    command = ['xcrun', 'xctrace', 'record', '--device', simulator_id,
               '--template', 'Time Profiler', '--instrument', 'os_signpost',
               '--time-limit', f'{RECORD_LIMIT}s', '--run-name', 'profiled-startup-diagnosis',
               '--output', str(output / 'startup.trace'),
               '--target-stdout', str(output / 'app-stdout.log'),
               '--launch', '--', str(app), '-uiTesting', '-dataset', str(fixture),
               '-uiTestingNow', '09:41', '-performanceTrace']
    write_json(output / 'command.json', command)
    write_json(output / 'status.json', status)
    # A successful help/list check is not proof this runtime supports app launch.
    status['phase'] = 'record'
    commands.run('record', command, RECORD_WATCHDOG)
    trace = output / 'startup.trace'
    if not trace.is_dir():
        raise CaptureError('Recorder exited successfully without a trace bundle')
    status['record_completed'] = True
    status['phase'] = 'toc-export'
    commands.run('toc-export', ['xcrun', 'xctrace', 'export', '--input', str(trace),
                              '--toc', '--output', str(output / 'toc.xml')], 5)
    toc = output / 'toc.xml'
    if not toc.is_file() or toc.stat().st_size == 0:
        raise CaptureError('TOC export completed without nonempty toc.xml')
    status['toc_export_completed'] = True
    status['phase'] = 'completed'
    status['status'] = 'passed'
    status['interpretation'] = ('Capture/export complete only; parent must verify One PID/startup samples, '
                                'symbols and signposts before using for diagnosis. No speedup claim.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True, help='Booted Today-Performance simulator UDID')
    parser.add_argument('--fixture', required=True, type=Path, help='Existing durable versioned fixture')
    parser.add_argument('--output', required=True, type=Path, help='New canonical results directory; must not exist')
    args = parser.parse_args(argv)
    output = args.output.expanduser().absolute()
    # Atomic exclusive creation precedes every subprocess/device operation.
    try:
        output.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.error('Output already exists; prior evidence preserved; select a new directory')
    started = time.monotonic()
    commands = Commands(output, started + TOTAL_LIMIT)
    status = {'status': 'running', 'phase': 'validation', 'started': timestamp(),
              'classification': 'profiled diagnosis; excluded from unprofiled timing comparisons',
              'global_wall_limit_seconds': TOTAL_LIMIT, 'recording_limit_seconds': RECORD_LIMIT,
              'record_watchdog_seconds': RECORD_WATCHDOG,
              'requires_caller_handoff_and_visible_device': True,
              'record_completed': False, 'toc_export_completed': False}
    write_json(output / 'status.json', status)
    try:
        capture(args, output, commands, status)
    except (CaptureError, OSError, ValueError, KeyError) as error:
        status.update(status='failed', error=str(error))
        print(str(error), file=sys.stderr)
    except KeyboardInterrupt:
        status.update(status='interrupted', error='Caller interrupted; inspect raw evidence')
    finally:
        status.update(finished=timestamp(), elapsed_seconds=time.monotonic() - started,
                      unreaped_child_pids=commands.unreaped)
        write_json(output / 'status.json', status)
    print(json.dumps({'output': str(output), 'status': status['status']}))
    return 0 if status['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
