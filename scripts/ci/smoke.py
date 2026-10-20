#!/usr/bin/env python3
"""Native usability smoke for CI: one build, one simulator boot, one test run.

Fails unless every selected leaf ran and passed in the completed xcresult.
Standard library only; prints elapsed seconds per step for timing.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
TEMP = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'today-smoke'
DD = TEMP / 'dd'
RESULT = TEMP / 'smoke.xcresult'
# The PR120 freeze (native EventKit lookup during render) and the populated
# launch/editor/tab/Chat journey. Swift Testing identifiers keep their "()".
TESTS = (
    'TodayTests/PlannerSessionTests/populatedDayAgendaRenderUsesImportedSnapshotsWithoutNativeLookups()',
    'TodayTests/PlannerSessionTests/importedFocusRenderingNeverOpensNativeStoreAndWritesStillRevalidate()',
    'TodayTests/PlannerSessionTests/savedCalendarSnoozeHydratesOutsideOriginalDayAndRejectsStaleImports()',
    'TodayUITests/TodayReminderCompletionTests/testImportedTimelineNavigationAndCancelledEditorsStayResponsive',
)
PRODUCTS = {'One.app': 'com.luworks.one',
            'One.app/PlugIns/TodayWidgets.appex': 'com.luworks.one.widgets',
            'One.app/PlugIns/ShareExtension.appex': 'com.luworks.one.share'}
FLAGS = ['-derivedDataPath', str(DD), '-disableAutomaticPackageResolution',
         '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
         'COMPILER_INDEX_STORE_ENABLE=NO', 'SWIFT_ENABLE_EXPLICIT_MODULES=NO']
STARTED = time.monotonic()


def step(name):
    print(f'::notice::smoke +{time.monotonic() - STARTED:.0f}s {name}', flush=True)


def run(*argv, capture=False):
    return subprocess.run(argv, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def simulator():
    """Prefer the canonical iPhone 18 Pro Max on the newest installed iOS runtime."""
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json', capture=True))['devices']
    runtimes = sorted((r for r in devices if '.iOS-' in r and devices[r]),
                      key=lambda r: [int(x) for x in r.rsplit('iOS-', 1)[1].split('-')])
    if not runtimes:
        raise SystemExit('No available iOS simulator')
    phones = [d for d in devices[runtimes[-1]] if d['name'].startswith('iPhone')]
    preferred = [d for d in phones if d['name'] == 'iPhone 18 Pro Max']
    device = (preferred or phones)[0]
    print(json.dumps({'simulator': device['name'], 'runtime': runtimes[-1], 'state': device['state']}))
    return device['udid']


def leaves(node):
    if node.get('nodeType') == 'Test Case':
        yield node
    for child in node.get('children', []):
        yield from leaves(child)


def verify():
    data = json.loads(run('xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                          '--path', str(RESULT), '--format', 'json', capture=True))
    cases = [case for root in data['testNodes'] for case in leaves(root)]
    actual = {case['name'].removesuffix('()'): case.get('result') for case in cases}
    expected = {test.rsplit('/', 1)[1].removesuffix('()') for test in TESTS}
    print(json.dumps({'results': actual}))
    if set(actual) != expected or len(cases) != len(TESTS) or set(actual.values()) != {'Passed'}:
        raise SystemExit('Smoke requires exactly these leaves to pass: ' + ', '.join(sorted(expected)))


def main():
    TEMP.mkdir(parents=True, exist_ok=True)
    udid = simulator()
    run('./dev', 'bootstrap', '--tool', 'xcodegen')
    run('./dev', 'generate')
    lock = ROOT / 'ios/Today.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.write_bytes((ROOT / 'ios/Dependencies/Package.resolved').read_bytes())
    step('project generated')
    destination = 'platform=iOS Simulator,id=' + udid
    # A concurrent simulator boot made this build 4x slower on the hosted runner.
    run('xcodebuild', 'build-for-testing', '-quiet', '-project', 'ios/Today.xcodeproj', '-scheme', 'TodayCI',
        '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator', '-jobs', '2',
        'ARCHS=arm64', *FLAGS)
    step('built App, Widget, Share, Mock and test bundles')
    products = DD / 'Build/Products/Debug-iphonesimulator'
    for path, identifier in PRODUCTS.items():
        info = plistlib.loads((products / path / 'Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') != identifier or not (products / path / info['CFBundleExecutable']).is_file():
            raise SystemExit('Missing production product: ' + path)
    subprocess.run('ls -la /Library/Developer/CoreSimulator/Caches/dyld/*/* 2>&1 | head -20', shell=True)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    step('simulator ready')
    subprocess.run('ls -la /Library/Developer/CoreSimulator/Caches/dyld/*/* 2>&1 | head -20', shell=True)
    xctestrun = sorted(DD.glob('Build/Products/TodayCI_*.xctestrun'))
    if len(xctestrun) != 1:
        raise SystemExit('Expected one TodayCI xctestrun')
    # Pre-grant Reminders so the cold simulator's permission sheet timing is not under test.
    run('xcrun', 'simctl', 'privacy', udid, 'grant', 'reminders', 'com.luworks.one')
    test = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', str(xctestrun[0]),
                             '-destination', destination, '-resultBundlePath', str(RESULT),
                             '-collect-test-diagnostics', 'never', '-parallel-testing-enabled', 'NO',
                             *FLAGS[:2], *['-only-testing:' + test for test in TESTS]], cwd=ROOT)
    for delay in (40, 100):
        try:
            test.wait(timeout=delay)
            break
        except subprocess.TimeoutExpired:
            step('sampling xcodebuild')
            subprocess.run(f'sample {test.pid} 2 -mayDie 2>/dev/null | grep -E "^ +[0-9]+ " | head -120 | cut -c1-200',
                           shell=True)
    code = test.wait()
    step('tests finished')
    verify()
    return code


if __name__ == '__main__':
    sys.exit(main())
