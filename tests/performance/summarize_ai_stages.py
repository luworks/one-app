#!/usr/bin/env python3
"""Reduce same-turn AI diagnosis points; elapsed spans are not CPU or model inference."""
import argparse
import json
from pathlib import Path
import re
import statistics

# Do not add independent medians to reconstruct a total. Preserve each turn below.
PAIRS = {
    'send_to_context': ('send', 'context_complete'),
    'context_to_respond': ('context_complete', 'respond_enter'),
    'record_call': ('record_turn_before', 'record_turn_after'),
    'task_queue': ('record_turn_after', 'task_enter'),
    'response_await': ('chat_response_await_before', 'chat_response_await_after'),
    'await_to_emission': ('chat_response_await_after', 'finish_emission_assigned'),
    'emission_to_observation': ('finish_emission_assigned', 'on_change_enter'),
    'observation_to_ready': ('on_change_enter', 'ready'),
    'ready_to_layout': ('ready', 'response_layout'),
}
ASYNC_POINTS = {'task_enter', 'chat_response_await_before', 'chat_response_await_after'}
LAYOUT_PAIRS = {
    'persist_call': ('persist_before', 'persist_after'),
    'scroll_request_call': ('scroll_request_before', 'scroll_request_after'),
    'ready_to_response_arm': ('ready', 'response_probe_arm'),
}
for phase in ('feedback', 'response'):
    LAYOUT_PAIRS.update({
        phase + '_arm_to_callback': (phase + '_probe_arm', phase + '_probe_callback'),
        phase + '_callback_to_eligible': (phase + '_probe_callback', phase + '_probe_eligible'),
        phase + '_eligible_to_layout': (phase + '_probe_eligible', phase + '_layout'),
    })



def reduce(text):
    turns = {}
    for line in text.splitlines():
        found = re.search(r'PERF_STAGE_AI (v=1;.+)$', line)
        if not found:
            continue
        fields = dict(p.split('=', 1) for p in found[1].split(';') if '=' in p)
        token = fields['turn']
        dispatch = fields.get('dispatch', 'async')
        if dispatch not in ('async', 'local_sync'):
            raise ValueError('unknown dispatch mode: ' + dispatch)
        points = {k[:-3]: int(v) for k, v in fields.items() if k.endswith('_ns')}
        required = {point for pair in PAIRS.values() for point in pair}
        pairs = dict(PAIRS)
        if dispatch == 'local_sync':
            required -= ASYNC_POINTS
            required.update(('local_reply_before', 'local_reply_after'))
            if ASYNC_POINTS & points.keys():
                raise ValueError('local dispatch contains async diagnostic points')
            pairs = {key: value for key, value in pairs.items() if not ASYNC_POINTS.intersection(value)}
            pairs['local_reply'] = ('local_reply_before', 'local_reply_after')
        if fields.get('layout_attribution') == '1':
            pairs.update(LAYOUT_PAIRS)
            required.update(point for pair in LAYOUT_PAIRS.values() for point in pair)
        if required - points.keys():
            raise ValueError('missing diagnostic points: ' + ', '.join(sorted(required - points.keys())))
        result = {'backend': fields['backend'], 'dispatch': dispatch, 'points_ns': points, 'elapsed_ms': {}}
        for name, (a, b) in pairs.items():
            if a in points and b in points:
                if points[b] < points[a]:
                    raise ValueError('nonmonotonic stage: ' + name)
                result['elapsed_ms'][name] = (points[b] - points[a]) / 1_000_000
        if token in turns and turns[token] != result:
            raise ValueError('conflicting duplicate turn')
        turns[token] = result
    grouped = {}
    for row in turns.values():
        for name, value in row['elapsed_ms'].items():
            grouped.setdefault(row['backend'] + '/' + row['dispatch'] + '/' + name, []).append(value)
    return {'scope': 'diagnostic elapsed intervals; not CPU/inference/persistence; no speed acceptance',
            'turns': turns, 'spans': {key: {'n': len(v), 'raw_ms': v, 'median_ms': statistics.median(v),
                                          'min_ms': min(v), 'max_ms': max(v), 'p95_ms': None}
                                     for key, v in sorted(grouped.items())}}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('log', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    with a.output.open('x') as out:
        json.dump(reduce(a.log.read_text(errors='replace')), out, indent=2)
        out.write('\n')
