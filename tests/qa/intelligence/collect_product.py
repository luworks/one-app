"""Read opt-in metadata-only production call traces; never infer product acceptance."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import uuid

MARKER = 'TODAY_MODEL_CALL '
EVENTS = {
    'api_started', 'api_returned', 'api_error', 'api_cancelled', 'deadline_timeout',
    'caller_cancelled', 'deadline_error', 'fallback_nil', 'result_available',
    'unavailable', 'model_title_selected', 'title_fallback_selected',
    'chat_fallback_selected', 'capture_route_selected', 'model_reply_selected',
    'proposals_unusable', 'model_proposals_selected',
    'turn_started', 'turn_routed', 'rule_direct_grant_selected',
    'context_resolution_selected', 'context_reply_selected', 'unavailable_chat_fallback',
}
STAGES = {'routing', 'chat', 'kind', 'title', 'proposals', 'edit', 'rank'}


def collect(text):
    calls = defaultdict(list)
    for line in text.splitlines():
        if MARKER not in line:
            continue
        # Compact unified logging encodes a backslash as octal \134.
        payload = line.split(MARKER, 1)[1].replace(r'\134', '\\')
        row = json.loads(payload)
        if set(row) - {'version', 'call', 'stage', 'event', 'elapsed_ms', 'error_type',
                       'turn', 'reported_context_size', 'reported_variant',
                       'wall_clock_unix_ms', 'system_timezone', 'system_locale',
                       'metadata_source', 'metadata_snapshot_prepare_ms'}:
            raise ValueError('Unexpected trace fields; do not accept content-bearing telemetry')
        uuid.UUID(row['call'])
        if 'turn' in row:
            uuid.UUID(row['turn'])
        if row['version'] != 1 or row['stage'] not in STAGES or row['event'] not in EVENTS:
            raise ValueError('Unknown trace contract')
        if type(row['elapsed_ms']) not in (int, float) or not math.isfinite(row['elapsed_ms']) or row['elapsed_ms'] < 0:
            raise ValueError('Invalid elapsed time')
        prior = calls[row['call']]
        if prior and (row['stage'] != prior[0]['stage']
                      or row.get('turn') != prior[0].get('turn')
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
    turns = defaultdict(list)
    for rows in calls.values():
        stages[rows[0]['stage']].update(r['event'] for r in rows)
        if rows[0].get('turn'):
            turns[rows[0]['turn']].append(rows[0]['call'])
    return dict(scope='Observed production API lifecycle only; not response quality or save/Undo proof.',
                window_completeness='UNKNOWN; requires the accompanying closed UI run evidence',
                stages={k: dict(v) for k, v in stages.items()},
                turns=dict(turns), calls=dict(calls))


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
