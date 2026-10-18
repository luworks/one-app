import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import summarize_year_cache as cache


class YearCacheSummaryTests(unittest.TestCase):
    def event(self, sequence=1, kind='miss', ns=150, year=2026, invalidation=0):
        row = dict(sequence=sequence, kind=kind, ns=ns, invalidation_sequence=invalidation)
        if kind != 'invalidated':
            row['year'] = year
        if kind == 'miss':
            row.update(start_ns=ns - 10, end_ns=ns, cache_year_count=1)
        elif kind == 'invalidated':
            row['cache_year_count'] = 0
        return row

    def provider(self, events=None, **updates):
        events = [self.event()] if events is None else events
        misses = sum(e['kind'] == 'miss' for e in events)
        invalidations = sum(e['kind'] == 'invalidated' for e in events)
        result = dict(snapshot_ns=250, request_count=misses, hit_count=0, miss_count=misses,
                      invalidation_sequence=invalidations, event_limit=256, truncated_count=0, events=events)
        result.update(updates)
        return result

    def row(self, visit=1, provider=True):
        row = dict(schema=1, name=cache.YEAR_ENTRY, route='calendar.year', pid=42, seq=visit,
                   route_visit=visit, visit_basis='layout_operation_name', start_ns=100,
                   layout_ns=200, window_end_ns=1000, period_ms=100,
                   samples=[dict(ns=i * 100, phys_footprint_bytes=1000,
                                 resident_size_bytes=2000, kern_return=0) for i in range(1, 10)])
        if provider:
            row['year_cache'] = self.provider()
        return row

    def log(self, rows, outcome='passed', method=cache.COUNTER_METHOD):
        return (f"Test Case '-[OneUITests.PerformanceClimbTests {method}]' started.\n" +
                '\n'.join('PERF_RESOURCE_APP ' + json.dumps(row) for row in rows) +
                f"\nTest Case '-[OneUITests.PerformanceClimbTests {method}]' {outcome}.")

    def diagnostic(self, row, **kwargs):
        result = cache.summarize(self.log([row], **kwargs))
        return result['attempts'][0]['windows'][0]['year_cache_diagnostic']

    def test_after_layout_events_filtered_but_snapshot_counters_retained(self):
        row = self.row()
        row['year_cache'] = self.provider([self.event(), self.event(2, ns=220, year=2027)])
        result = self.diagnostic(row)
        self.assertEqual(result['snapshot']['snapshot_ns'], 250)
        self.assertEqual(result['snapshot']['counters_asof_snapshot']['miss_count'], 2)
        self.assertEqual(result['endpoint']['observed_cumulative_missed_years'], [2026])
        self.assertEqual(result['endpoint']['excluded_after_layout_event_count'], 1)
        self.assertEqual(result['endpoint']['completed_misses_within_operation'][0]['wall_duration_ns'], 10)
        self.assertEqual(result['raw_provider'], row['year_cache'])
        self.assertEqual(len(result['raw_provider_sha256']), 64)

    def test_failed_attempt_and_truncated_history_not_eligible(self):
        rows = [self.row(i) for i in (1, 2, 3)]
        result = cache.summarize(self.log(rows, outcome='failed'))
        self.assertFalse(result['year_entry_groups'][0]['counter_cohort_n3_eligible'])
        self.assertFalse(result['attempts'][0]['windows'][0]['year_cache_diagnostic']['counter_cohort_eligible'])
        row = self.row()
        row['year_cache'] = self.provider([self.event(i, 'appeared', ns=i) for i in range(1, 257)],
                                          snapshot_ns=300, truncated_count=1)
        truncated = self.diagnostic(row)
        self.assertEqual(truncated['provider_status'], 'truncated')
        self.assertFalse(truncated['endpoint_events_complete'])
        self.assertFalse(truncated['counter_cohort_eligible'])
        self.assertIsNone(truncated['endpoint']['missed_not_appeared_by_endpoint'])
        self.assertTrue(truncated['missing_evidence'])

    def test_missing_provider_is_missing_not_zero(self):
        row = self.row(provider=False)
        result = self.diagnostic(row)
        self.assertEqual(result['provider_status'], 'missing')
        self.assertIsNone(result['snapshot'])
        self.assertIsNone(result['endpoint'])
        self.assertFalse(result['counter_cohort_eligible'])
        row['year_cache'] = None
        self.assertEqual(self.diagnostic(row)['provider_status'], 'missing')

    def test_hit_and_inflight_counts_not_backdated(self):
        row = self.row()
        row['year_cache'] = self.provider([], request_count=6, hit_count=5)
        result = self.diagnostic(row)
        self.assertEqual(result['snapshot']['unresolved_requests_asof_snapshot'], 1)
        self.assertEqual(result['snapshot']['counters_asof_snapshot']['hit_count'], 5)
        self.assertNotIn('hit_count', result['endpoint'])
        self.assertEqual(result['endpoint']['completed_misses_within_operation'], [])

    def test_invalidation_and_lifecycle_observations_separate(self):
        row = self.row()
        events = [self.event(1, 'invalidated', ns=110, invalidation=1),
                  self.event(2, ns=130, invalidation=1),
                  self.event(3, 'appeared', ns=140, invalidation=1),
                  self.event(4, 'disappeared', ns=160, invalidation=1)]
        row['year_cache'] = self.provider(events)
        endpoint = self.diagnostic(row)['endpoint']
        self.assertEqual(endpoint['missed_not_appeared_by_endpoint'], [])
        self.assertEqual(len(endpoint['invalidation_observations']), 1)
        self.assertEqual(len(endpoint['cache_count_observations']), 2)
        self.assertEqual(len(endpoint['appeared_events']), 1)
        self.assertEqual(len(endpoint['disappeared_events']), 1)
        self.assertEqual(endpoint['observed_cumulative_ever_appeared_years'], [2026])

    def test_invalid_payloads_rejected(self):
        mutations = [lambda p: p.update(request_count=True),
                     lambda p: p.update(hit_count=2),
                     lambda p: p.update(snapshot_ns=199),
                     lambda p: p.update(event_limit=128),
                     lambda p: p['events'][0].update(kind='hit'),
                     lambda p: p['events'][0].update(sequence=2),
                     lambda p: p['events'][0].update(ns=300),
                     lambda p: p['events'][0].update(start_ns=151),
                     lambda p: p['events'][0].update(end_ns=149),
                     lambda p: p['events'][0].update(year=True),
                     lambda p: p['events'][0].update(cache_year_count=-1),
                     lambda p: p['events'][0].update(invalidation_sequence=1),
                     lambda p: p.update(events='invalid')]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                row = self.row()
                mutate(row['year_cache'])
                with self.assertRaises(ValueError):
                    self.diagnostic(row)

    def test_only_dedicated_method_and_usable_resources_eligible(self):
        rows = [self.row(i) for i in (1, 2, 3)]
        self.assertTrue(cache.summarize(self.log(rows))['year_entry_groups'][0]['counter_cohort_n3_eligible'])
        result = cache.summarize(self.log(rows, method='testRootNavigationResourceWindows'))
        self.assertFalse(result['year_entry_groups'][0]['counter_cohort_n3_eligible'])
        row = self.row()
        row['samples'][0]['kern_return'] = 5
        self.assertFalse(self.diagnostic(row)['counter_cohort_eligible'])
        self.assertFalse(cache.summarize(self.log(rows, outcome='skipped'))['year_entry_groups'][0]['counter_cohort_n3_eligible'])

    def test_invalid_resource_sequence_rejected(self):
        row = self.row()
        row['seq'] = 0
        with self.assertRaisesRegex(ValueError, 'seq'):
            self.diagnostic(row)

    def test_crossing_miss_not_reported_as_fully_within_operation(self):
        row = self.row()
        row['year_cache']['events'][0]['start_ns'] = 50
        endpoint = self.diagnostic(row)['endpoint']
        self.assertEqual(endpoint['completed_misses_within_operation'], [])
        self.assertEqual(len(endpoint['misses_crossing_operation_start']), 1)

    def test_decreasing_process_lifetime_counters_rejected(self):
        first, second = self.row(1), self.row(2)
        first['year_cache']['request_count'] = 3
        with self.assertRaisesRegex(ValueError, 'snapshots decreased'):
            cache.summarize(self.log([first, second]))

    def test_cli_hashes_source_and_never_overwrites_output(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'closed.log'
            output = Path(directory) / 'summary.json'
            log.write_text(self.log([self.row()]))
            command = [sys.executable, str(Path(cache.__file__)), str(log), '--output', str(output)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            result = json.loads(output.read_text())
            self.assertEqual(result['source']['path'], str(log.resolve()))
            self.assertEqual(len(result['source']['sha256']), 64)
            before = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
