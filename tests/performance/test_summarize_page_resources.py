import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('resources', Path(__file__).with_name('summarize_page_resources.py'))
resources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resources)


class PageResourceSummaryTests(unittest.TestCase):
    def row(self, visit=1, size=1000):
        return dict(schema=1, name='page.health', route='health', pid=42, seq=visit,
                    route_visit=visit, start_ns=0, layout_ns=100, window_end_ns=1000, period_ms=100,
                    samples=[dict(ns=i * 100, phys_footprint_bytes=size, resident_size_bytes=2000,
                                  kern_return=0, response_count=100) for i in range(10)])

    def log(self, rows, outcome='passed'):
        return ("Test Case '-[OneUITests.Pages testResources]' started.\n" +
                '\n'.join('PERF_RESOURCE_APP ' + json.dumps(r) for r in rows) +
                f"\nTest Case '-[OneUITests.Pages testResources]' {outcome}.")

    def test_duplicate_raw_is_not_an_extra_window(self):
        result = resources.summarize(self.log([self.row(), self.row()]))
        self.assertEqual(len(result['attempts'][0]['windows']), 1)
        self.assertIsNone(result['attempts'][0]['windows'][0]['derived']['p95_bytes'])

    def test_negative_revisit_growth_is_preserved(self):
        result = resources.summarize(self.log([self.row(i, 1000 - i * 100) for i in (1, 2, 3)]))
        self.assertEqual(result['revisit_groups'][0]['visit1_to_visit3_bytes'], -200)
        self.assertTrue(result['revisit_groups'][0]['baseline_usable'])

    def test_failed_method_and_missing_provider_never_become_success(self):
        row = self.row()
        row['samples'][2].update(kern_return=5, phys_footprint_bytes=None)
        result = resources.summarize(self.log([row]))
        window = result['attempts'][0]['windows'][0]
        self.assertFalse(window['baseline_usable'])
        self.assertEqual(window['derived']['invalid_samples'], 1)
        result = resources.summarize(self.log([self.row()], outcome='failed'))
        self.assertFalse(result['attempts'][0]['windows'][0]['baseline_usable'])

    def test_conflicts_and_nonmonotonic_samples_rejected(self):
        row = self.row()
        changed = copy.deepcopy(row)
        changed['samples'][0]['phys_footprint_bytes'] += 1
        with self.assertRaisesRegex(ValueError, 'conflicting duplicate'):
            resources.summarize(self.log([row, changed]))
        row['samples'][3]['ns'] = 0
        with self.assertRaisesRegex(ValueError, 'nonmonotonic'):
            resources.summarize(self.log([row]))

    def test_incomplete_visits_do_not_estimate_growth(self):
        result = resources.summarize(self.log([self.row(1), self.row(3)]))
        self.assertIsNone(result['revisit_groups'][0]['visit1_to_visit3_bytes'])
        self.assertFalse(result['revisit_groups'][0]['baseline_usable'])

    def test_late_timer_callback_retained_but_excluded_from_peak(self):
        row = self.row()
        row['collection_end_ns'] = 1100
        row['samples'].append(dict(ns=1100, phys_footprint_bytes=9000, resident_size_bytes=9000,
                                   kern_return=0, response_count=100))
        window = resources.summarize(self.log([row]))['attempts'][0]['windows'][0]
        self.assertEqual(window['derived']['sampled_operation_max_bytes'], 1000)
        self.assertEqual(window['derived']['excluded_after_window_samples'], 1)
        self.assertEqual(window['samples'][-1]['phys_footprint_bytes'], 9000)
