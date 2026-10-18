import copy
import json
import unittest

from compare_component_reads import compare, samples


def context():
    return dict(configuration="release", optimization="-O", build_source="own-source", cache="warm",
                global_quiet=True, host=dict(hardware="Mac-same\n", revision="different allowed"), exit_code=0)


def log(value=1, count=3, outcome="passed"):
    records = [dict(metric="activity_read_newest", sample=i, n=count, value=value, batch_ms=value * 25,
                    fixture="activity-read-v1", rows=100000, page_size=150, iterations=25,
                    cache="warm", clock="uptimeNanoseconds", unit="ms") for i in range(1, count + 1)]
    text = "\n".join("PERF_SAMPLE " + json.dumps(record) for record in records)
    # Actual host logs flush JSON stdout after the test outcome.
    return f"Test Case '-[OneLogicTests.ActivityReadPerformanceTests testWarmPageReads]' {outcome} (1 seconds).\n" + text


class ComponentReadTests(unittest.TestCase):
    def test_duplicate_json_is_not_an_extra_sample_and_summary_has_no_percentiles(self):
        text = log(3)
        data = samples(text + "\n" + text.splitlines()[1])
        row = data["activity_read_newest"]
        self.assertEqual(row["raw"], [3, 3, 3])
        self.assertEqual(row["n"], 3)
        self.assertEqual(row["range"], dict(min=3, max=3))
        self.assertNotIn("p95", row)
        result = compare(data, samples(log()), context(), context())
        self.assertTrue(result["all_required_3x_met"])

    def test_failed_command_test_and_insufficient_samples_cannot_pass(self):
        for failed in ("command", "test", "missing", "few", "many"):
            after_context = context()
            after = log(0.01)
            if failed == "command":
                after_context["exit_code"] = 1
            elif failed == "test":
                after = log(0.01, outcome="failed")
            elif failed == "missing":
                after = "\n".join(after.splitlines()[1:])
            else:
                after = log(0.01, count=2 if failed == "few" else 6)
            with self.subTest(failed=failed):
                result = compare(samples(log()), samples(after), context(), after_context)
                self.assertFalse(result["metrics"]["activity_read_newest"]["stretch_10x_met"])

    def test_context_and_sample_mismatches_rejected(self):
        for key in ("configuration", "optimization", "build_source", "cache", "global_quiet"):
            other = context()
            other[key] = "different"
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare(samples(log()), samples(log()), context(), other)
        other = context(); other["host"]["hardware"] = "other Mac"
        with self.assertRaises(ValueError):
            compare(samples(log()), samples(log()), context(), other)
        for key in ("fixture", "rows", "page_size", "iterations", "cache", "clock", "unit"):
            after = copy.deepcopy(samples(log()))
            after["activity_read_newest"]["sample_context"][key] = "different"
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare(samples(log()), after, context(), context())

    def test_conflicting_duplicate_and_nonfinite_or_inconsistent_values_rejected(self):
        with self.assertRaises(ValueError):
            samples(log() + "\n" + log(2).splitlines()[1])
        for invalid in (log().replace('"value": 1', '"value": NaN'),
                        log().replace('"batch_ms": 25', '"batch_ms": 26'),
                        log().replace('"clock": "uptimeNanoseconds"', '"clock": "other"', 1)):
            with self.assertRaises(ValueError):
                samples(invalid)


if __name__ == "__main__":
    unittest.main()
