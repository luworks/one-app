"""Read opt-in metadata-only production call traces; never infer product acceptance."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import uuid

MARKER = 'TODAY_MODEL_CALL '
EVENTS = {
    'api_started', 'api_returned', 'api_error', 'api_cancelled', 'deadline_timeout',
    'caller_cancelled', 'deadline_error', 'fallback_nil', 'result_available',
    'unavailable', 'model_title_selected', 'title_fallback_selected',
    'chat_fallback_selected', 'capture_route_selected', 'model_reply_selected',
    'proposals_unusable', 'model_proposals_selected',
}
STAGES = {'chat', 'kind', 'title', 'proposals', 'edit'}


def collect(text):
    calls = defaultdict(list)
    for line in text.splitlines():
        if MARKER not in line:
            continue
        row = json.loads(line.split(MARKER, 1)[1])
        if set(row) - {'version', 'call', 'stage', 'event', 'elapsed_ms', 'error_type'}:
            raise ValueError('Unexpected trace fields; do not accept content-bearing telemetry')
        uuid.UUID(row['call'])
        if row['version'] != 1 or row['stage'] not in STAGES or row['event'] not in EVENTS:
            raise ValueError('Unknown trace contract')
        if not isinstance(row['elapsed_ms'], (int, float)) or row['elapsed_ms'] < 0:
            raise ValueError('Invalid elapsed time')
        prior = calls[row['call']]
        if prior and (row['stage'] != prior[0]['stage']
                      or row['elapsed_ms'] < prior[-1]['elapsed_ms']):
            raise ValueError('Conflicting stage or nonmonotonic call trace')
        if row['event'].startswith('api_') and any(r['event'] == row['event'] for r in prior):
            raise ValueError('Duplicate API lifecycle event')
        if row['event'] in {'api_returned', 'api_error', 'api_cancelled'}:
            if not any(r['event'] == 'api_started' for r in prior):
                raise ValueError('API completion without an observed call start')
            if any(r['event'] in {'api_returned', 'api_error', 'api_cancelled'} for r in prior):
                raise ValueError('Multiple API completions')
        prior.append(row)
    stages = defaultdict(Counter)
    for rows in calls.values():
        stages[rows[0]['stage']].update(r['event'] for r in rows)
    return dict(scope='Observed production API lifecycle only; not response quality or save/Undo proof.',
                window_completeness='UNKNOWN; requires the accompanying closed UI run evidence',
                stages={k: dict(v) for k, v in stages.items()}, calls=dict(calls))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = collect(args.log.read_text())
    with args.output.open('x') as out:
        json.dump(result, out, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
