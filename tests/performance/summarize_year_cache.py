#!/usr/bin/env python3
"""Reduce gated Year cache diagnostics, preserving resource and functional gates.

Snapshot counters cannot be backdated to layout. Miss durations are completed wall
intervals, not CPU time. Header lifecycle is not viewport visibility or ownership.
"""
import argparse
import hashlib
import json
from pathlib import Path

from summarize_page_resources import summarize as summarize_resources


YEAR_ENTRY = 'calendar.month_to_calendar.year'
COUNTER_METHOD = 'testRootYearCacheDiagnosticWindows'
KINDS = {'miss', 'invalidated', 'appeared', 'disappeared'}
COUNTERS = ('request_count', 'hit_count', 'miss_count', 'invalidation_sequence')


def integer(row, key, minimum=0):
    value = row.get(key)
    if type(value) is not int or (minimum is not None and value < minimum):
        raise ValueError('invalid Year cache integer: ' + key)
    return value


def validate(provider, window):
    if not isinstance(provider, dict):
        raise ValueError('Year cache provider must be an object')
    snapshot = integer(provider, 'snapshot_ns')
    if not window['layout_ns'] <= snapshot <= window.get('collection_end_ns', window['window_end_ns']):
        raise ValueError('Year cache snapshot outside layout/collection interval')
    for key in COUNTERS:
        integer(provider, key)
    if provider['hit_count'] + provider['miss_count'] > provider['request_count']:
        raise ValueError('Year cache completions exceed requests')
    if integer(provider, 'event_limit') != 256:
        raise ValueError('unsupported Year cache event limit')
    truncated = integer(provider, 'truncated_count')
    events = provider.get('events')
    if not isinstance(events, list) or len(events) > provider['event_limit']:
        raise ValueError('invalid Year cache event buffer')
    previous_ns, invalidations, misses = 0, 0, 0
    for sequence, event in enumerate(events, 1):
        if not isinstance(event, dict):
            raise ValueError('Year cache event must be an object')
        if integer(event, 'sequence', 1) != sequence:
            raise ValueError('Year cache event sequence must retain the first consecutive events')
        ns = integer(event, 'ns')
        if not previous_ns <= ns <= snapshot:
            raise ValueError('nonmonotonic Year cache event timestamp')
        previous_ns = ns
        kind = event.get('kind')
        if not isinstance(kind, str) or kind not in KINDS:
            raise ValueError('unknown Year cache event kind')
        if kind == 'invalidated':
            invalidations += 1
        if integer(event, 'invalidation_sequence') != invalidations:
            raise ValueError('invalid Year cache invalidation sequence')
        if kind in ('miss', 'appeared', 'disappeared'):
            integer(event, 'year', minimum=None)
        elif event.get('year') is not None:
            raise ValueError('invalidated event cannot supply a year')
        if kind == 'miss':
            misses += 1
            start = integer(event, 'start_ns')
            if integer(event, 'end_ns') != ns or start > ns:
                raise ValueError('invalid Year cache miss interval')
        elif event.get('start_ns') is not None or event.get('end_ns') is not None:
            raise ValueError('non-miss event cannot supply a miss interval')
        if kind in ('miss', 'invalidated'):
            integer(event, 'cache_year_count')
        elif event.get('cache_year_count') is not None:
            raise ValueError('lifecycle event cannot supply a cache count')
    if misses > provider['miss_count'] or invalidations > provider['invalidation_sequence']:
        raise ValueError('Year cache events exceed snapshot counters')
    if not truncated and (misses != provider['miss_count'] or invalidations != provider['invalidation_sequence']):
        raise ValueError('untruncated Year cache events disagree with counters')
    # Retaining the first 256 events is part of this provider's contract.
    if truncated and len(events) != provider['event_limit']:
        raise ValueError('truncated Year cache buffer must retain its first 256 events')


def reduce_window(window, method):
    integer(window, 'seq', 1)
    integer(window, 'pid', 1)
    if not all(isinstance(window.get(key), str) and window[key] for key in ('name', 'route')):
        raise ValueError('invalid Year cache window name/route')
    provider = window.get('year_cache')
    result = dict(provider_status='missing', raw_provider=provider,
                  raw_provider_sha256=None, endpoint_events_complete=False,
                  counter_cohort_eligible=False, endpoint=None, snapshot=None,
                  missing_evidence=['year_cache absent/null; flag may be off or provider unavailable'])
    if provider is None:
        return result
    validate(provider, window)
    encoded = json.dumps(provider, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    truncated = provider['truncated_count'] > 0
    endpoint_events = [event for event in provider['events'] if event['ns'] <= window['layout_ns']]
    operation_events = [event for event in endpoint_events if event['ns'] >= window['start_ns']]
    misses = [event for event in endpoint_events if event['kind'] == 'miss']
    appeared = [event for event in endpoint_events if event['kind'] == 'appeared']
    missed_years = sorted({event['year'] for event in misses})
    appeared_years = sorted({event['year'] for event in appeared})
    completed = [dict(event, wall_duration_ns=event['end_ns'] - event['start_ns'])
                 for event in operation_events if event['kind'] == 'miss'
                 and event['start_ns'] >= window['start_ns']]
    crossing = [event for event in operation_events if event['kind'] == 'miss'
                and event['start_ns'] < window['start_ns']]
    result.update(
        provider_status='truncated' if truncated else 'available',
        raw_provider_sha256=hashlib.sha256(encoded).hexdigest(),
        provider_hash_encoding='canonical JSON, sorted keys, compact separators, UTF-8',
        endpoint_events_complete=not truncated,
        counter_cohort_eligible=(window['baseline_usable'] and not truncated
                                 and method == COUNTER_METHOD and window['name'] == YEAR_ENTRY),
        missing_evidence=['truncated event history; endpoint absence/completeness conclusions unavailable'] if truncated else [],
        snapshot=dict(snapshot_ns=provider['snapshot_ns'],
                      counters_asof_snapshot={key: provider[key] for key in COUNTERS},
                      unresolved_requests_asof_snapshot=(provider['request_count'] - provider['hit_count'] - provider['miss_count']),
                      unresolved_semantics='Requests without recorded hit/miss completion at snapshot; may include in-flight work. Not an endpoint miss count.'),
        endpoint=dict(layout_ns=window['layout_ns'], events=endpoint_events, operation_events=operation_events,
                      excluded_after_layout_event_count=len(provider['events']) - len(endpoint_events),
                      completed_misses_within_operation=completed, misses_crossing_operation_start=crossing,
                      observed_cumulative_missed_years=missed_years,
                      observed_cumulative_ever_appeared_years=appeared_years,
                      missed_not_appeared_by_endpoint=None if truncated else sorted(set(missed_years) - set(appeared_years)),
                      invalidation_observations=[event for event in endpoint_events if event['kind'] == 'invalidated'],
                      cache_count_observations=[event for event in endpoint_events if event.get('cache_year_count') is not None],
                      appeared_events=appeared,
                      disappeared_events=[event for event in endpoint_events if event['kind'] == 'disappeared']))
    return result


def summarize(text):
    resource = summarize_resources(text)
    groups = []
    for attempt_number, attempt in enumerate(resource['attempts'], 1):
        previous = {}
        entries = []
        for window in attempt['windows']:
            result = reduce_window(window, attempt['method'])
            window['year_cache_diagnostic'] = result
            provider = window.get('year_cache')
            if provider is not None:
                old = previous.get(window['pid'])
                if old and any(provider[key] < old[key] for key in ('snapshot_ns', *COUNTERS, 'truncated_count')):
                    raise ValueError('Year cache process-lifetime snapshots decreased')
                previous[window['pid']] = provider
            if window['name'] == YEAR_ENTRY:
                entries.append(window)
        # Groups retain attempt/PID/visit-basis boundaries; there are no pooled metrics or ratios.
        identities = sorted({(row['pid'], row.get('visit_basis', 'legacy_route_visit')) for row in entries})
        for pid, basis in identities:
            rows = [row for row in entries if (row['pid'], row.get('visit_basis', 'legacy_route_visit')) == (pid, basis)]
            visits = [row['route_visit'] for row in rows]
            eligible = visits == [1, 2, 3] and all(row['year_cache_diagnostic']['counter_cohort_eligible'] for row in rows)
            groups.append(dict(attempt=attempt_number, suite=attempt['suite'], method=attempt['method'],
                               pid=pid, visit_basis=basis, ordered_visits=visits,
                               window_sequences=[row['seq'] for row in rows], counter_cohort_n3_eligible=eligible))
    return dict(schema=1, attempts=resource['attempts'], year_entry_groups=groups,
                resource_scope=resource['scope'],
                scope='Process-lifetime Year cache counters as of snapshot; endpoint events filtered at original layout_ns. No aggregate counters backdated.',
                limitations=['Miss durations are completed wall intervals, not CPU time.',
                             'Appeared/disappeared are header lifecycle callbacks, not viewport visibility.',
                             'A missed-not-appeared year, including a singleton, does not establish eager or offscreen computation.',
                             'Cache count/invalidation observations do not establish memory ownership or cache survival after Year disappears.',
                             'Truncation prevents endpoint completeness and absence conclusions.',
                             'Only the dedicated counter method with functional/resource gates can be eligible. No pooling, ratios, speed gains or endpoint changes.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    raw = args.log.read_bytes()
    result = summarize(raw.decode(errors='replace'))
    result['source'] = dict(path=str(args.log.resolve()), sha256=hashlib.sha256(raw).hexdigest())
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')


if __name__ == '__main__':
    main()
