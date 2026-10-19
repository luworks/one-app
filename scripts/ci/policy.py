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
MANUAL = ('release', 'extended', 'sanitizer', 'performance', 'protected-release')


def read_json(path):
    return json.loads(Path(path).read_text())


# Keep this direct table aligned with the source map in ios/README.md. Unknown
# paths deliberately widen; no package evaluation or dependency planner is needed.
FEATURE_UI = {
    'FeatureHealth': ('HealthMetricsTests/testListShowsTheDefaultRowsAndNoCards',
                      'HealthMetricsTests/testTapOpensDetailWithRangeSwitch'),
    'FeatureClock': ('ClockTests/testSwitchingSectionsAndPlus',),
    'FeatureToday': ('JourneyTests/testJ3_completeAndUndo',),
    'FeatureCalendar': ('CalendarTabTests/testWeekIsTheDefault',),
    'FeatureReminders': ('RemindersListsTests/testAddListIsVisibleAndCreatesAList',
                         'JourneyTests/testJ3_completeAndUndo'),
    'FeatureAsk': ('AskConversationTests/testQuestionAndUnknownStatementDoNotCreateCards',
                   'AskConversationTests/testChatThenExplicitRequestAndChatPreservesPreview'),
    'FeatureSettings': ('SettingsChoicesTests/testDimPastDaysSettingTurnsTheDimmingOffAndOn',),
    'FeatureActivity': ('ActivityDataTests/testPausedRecordingStopsAutomaticChanges',),
    'FeatureSearch': ('SidebarTests/testConversationAppearsInSidebarAndReopens',),
}
FEATURE_LOGIC = {
    'FeatureHealth': ('HealthLogicTests', 'HealthMetricsTests', 'HealthLoadingTests'),
    'FeatureClock': ('TimerListTests', 'StopwatchLogicTests', 'WorldClockTests'),
    'FeatureToday': ('DayPlannerTests', 'ReminderCompletionFenceTests', 'TodayFocusStoreTests'),
    'FeatureCalendar': ('CalendarBoundaryTests', 'CalendarLayoutTests', 'EventMatchTests'),
    'FeatureReminders': ('NewReminderDraftTests', 'ReminderSuggestTests', 'RepeatAdvanceTests'),
    'FeatureAsk': ('ChatRoutingTests', 'AutonomyPolicyTests', 'CaptureCardStateTests'),
    'FeatureSettings': ('PreferencesTests', 'AppearanceTests'),
    'FeatureActivity': ('ActivityStoreTests', 'ActivityRecorderTests', 'ActivityLedgerTests'),
    'FeatureSearch': ('SearchMatchTests', 'ConversationHistoryTests'),
}


def select(paths, nodes=None, reason=None):
    """Version-one selection receipt from conservative, reviewable source paths."""
    paths = list(paths)
    wide = reason or ('empty diff: conservative full selection' if not paths else None)
    targets = set()
    docs = bool(paths) and all(path.lower().endswith('.md') or
                              path.startswith('docs/') and path.lower().endswith(('.txt', '.png', '.jpg', '.svg'))
                              for path in paths)
    if not docs:
        for path in paths:
            if path.lower().endswith('.md'):
                continue
            parts = Path(path).parts
            if any(word in Path(path).name.lower() for word in ('shared', 'schema', 'model', 'dependency', 'package', 'config')):
                wide = 'shared/schema/dependency/configuration change: ' + path
            elif path.startswith('ios/Sources/Features/') and path.endswith('.swift') and len(parts) > 4 and parts[3] in FEATURE_UI:
                targets.add('ios:' + parts[3])
            elif path.startswith('ios/Sources/TodayCore/') and path.endswith('.swift'):
                targets.add('ios:TodayCore')
            elif path.startswith('ios/Eval/Tests/OneLogicTests/') and path.endswith('.swift'):
                targets.add('ios:TodayTests')
            else:
                wide = 'shared/schema/dependency/engineering or unmapped path: ' + path
    return {'version': 1, 'mode': 'wide' if wide else ('docs' if docs else 'affected'),
            'reason': wide or ('documentation only' if docs else 'direct module risk mapping'),
            'changed': paths, 'targets': sorted(targets), 'all_targets': bool(wide),
            'snapshots': bool(wide)}


def undo_risk(paths):
    return any(any(word in Path(path).stem.lower() for word in
                   ('completion', 'delete', 'undo', 'taskactions', 'rowactions')) for path in paths)


def routine_lanes(selection):
    """Only these lanes block a routine change; full authorities remain manual."""
    # Reclassify changed paths so a stale/forged receipt cannot hide real risk.
    actual = select(selection.get('changed', []))
    if selection.get('all_targets') or actual['all_targets']:
        return ['format', 'lint', 'business', 'build', 'integration', 'snapshots', 'core-ui']
    if actual['mode'] == 'docs':
        return ['format', 'lint']
    lanes = ['format', 'lint', 'business', 'build']
    if undo_risk(actual['changed']) or any(t.removeprefix('ios:') in FEATURE_UI for t in actual['targets']):
        lanes.append('core-ui')
    return lanes


def execution_selection(selection, source, lane, broad):
    """Select real source inventory leaves; manual execution stays complete."""
    from scripts.testing import contract
    if lane == 'core-ui':
        changed = set(selection.get('changed', []))
        added = [test for suite in source['ui'] if suite['path'] in changed
                 for test in contract.expand([suite['suite']], source, 'ui')]
        broad = list(dict.fromkeys([*broad, *added]))
    if os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch':
        return broad
    actual = select(selection.get('changed', []))
    if selection.get('all_targets') or actual['all_targets']:
        return broad
    features = [t.removeprefix('ios:') for t in actual['targets']
                if t.removeprefix('ios:') in FEATURE_UI]
    if lane == 'core-ui' and (features or undo_risk(actual['changed'])):
        tests = [test for feature in features for test in FEATURE_UI[feature]]
        if undo_risk(actual['changed']):
            tests.append('JourneyTests/testJ3_completeAndUndo')
        return contract.expand(list(dict.fromkeys(tests)), source, 'ui')
    if lane == 'business':
        suites = []
        known = {suite['suite'] for suite in source['logic']}
        for path in actual['changed']:
            if path.lower().endswith('.md'):
                continue
            stem = Path(path).stem
            exact = stem if stem.endswith('Tests') else stem + 'Tests'
            if exact in known:
                suites.append(exact)
            elif path.startswith('ios/Sources/Features/'):
                suites.extend(FEATURE_LOGIC[Path(path).parts[3]])
            else:
                # Core rules without a named authority retain all logic coverage.
                return broad
        if suites:
            return contract.expand(list(dict.fromkeys(suites)), source, 'logic')
    return broad


def validate_report(report, sha, lane):
    if report.get('sha') != sha or report.get('lane') != lane or report.get('status') != 'passed':
        raise ValueError('report must match integrated SHA, lane and passed status')
    for field in ('executed', 'failed', 'cancelled', 'missing'):
        value = report.get(field)
        if type(value) is not int or value < 0:
            raise ValueError('invalid report counter: ' + field)
    if report['executed'] == 0 or any(report[x] for x in ('failed', 'cancelled', 'missing')):
        raise ValueError('zero results, failures, cancellations or missing results')
    if report.get('errors'):
        raise ValueError('report contains unresolved errors')
    if report.get('synthetic') is not True:
        raise ValueError('only synthetic CI datasets are allowed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    s = sub.add_parser('select')
    s.add_argument('--changed-json')
    s.add_argument('--output', required=True)
    args = parser.parse_args()
    reason = None
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
    Path(args.output).write_text(json.dumps(select(paths, reason=reason), indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
