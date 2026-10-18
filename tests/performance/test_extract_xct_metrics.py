import unittest

from extract_xct_metrics import extract


CASE = "Test Case '-[OneUITests.PerformanceClimbTests testYearScrollMemory]'"
# Actual measurement labels, units, IDs and raw values from the frozen optimized
# baseline log; the source-file prefix and unrelated printed metadata are shortened.
MEASUREMENTS = [
    ("Memory Peak Physical (one)", "kB", "com.apple.dt.XCTMetric_Memory-com.luworks.one.physical_peak",
     "303073.968000, 292260.528000, 283167.408000"),
    ("Duration (Scroll_DraggingAndDeceleration)", "s",
     "com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.duration",
     "2.483321, 2.482554, 2.482785"),
    ("Memory Physical (one)", "kB", "com.apple.dt.XCTMetric_Memory-com.luworks.one.physical",
     "7094.272000, -2588.672000, -55771.136000"),
    ("Absolute Memory Physical (one)", "kB", "com.apple.dt.XCTMetric_Memory-com.luworks.one.physical_absolute",
     "284674.736000, 282708.656000, 226937.520000"),
]


def measurement(index=0, unit=None):
    label, original_unit, metric_id, values = MEASUREMENTS[index]
    return (f"/baseline/PerformanceClimbTests.swift:107: {CASE} measured [{label}, {unit or original_unit}] "
            f"average: 0.000, relative standard deviation: 0.000%, values: [{values}], "
            f'performanceMetricID:{metric_id}, baselineName: "", polarity: prefers smaller')


class ExtractXCTMetricsTests(unittest.TestCase):
    def test_actual_baseline_metrics_stay_separate_with_printed_units_and_raw_delta(self):
        text = "\n".join([CASE + " started."] + [measurement(i) for i in range(4)] +
                         [CASE + " passed (40.396 seconds)."])
        attempt = extract(text)["attempts"][0]
        self.assertTrue(attempt["functional_passed"])
        self.assertEqual(attempt["method"], "testYearScrollMemory")
        metrics = attempt["metrics"]
        self.assertEqual([m["kind"] for m in metrics],
                         ["peak_physical", "scroll_duration", "physical_delta", "absolute_physical"])
        self.assertEqual([m["unit"] for m in metrics], ["kB", "s", "kB", "kB"])
        self.assertEqual([m["n"] for m in metrics], [3] * 4)
        self.assertEqual(metrics[0]["median"], 292260.528)
        self.assertEqual(metrics[1]["median"], 2.482785)
        self.assertEqual(metrics[2]["raw"], [7094.272, -2588.672, -55771.136])
        self.assertEqual(metrics[2]["median"], -2588.672)
        self.assertEqual(metrics[2]["range"], {"min": -55771.136, "max": 7094.272})
        self.assertNotIn("p95", metrics[0])
        self.assertNotIn("derived_mib", metrics[0])

    def test_duplicate_lines_do_not_inflate_n_and_failed_retry_remains_separate(self):
        text = "\n".join([CASE + " started.", measurement(), measurement(), CASE + " failed (1 seconds).",
                          CASE + " passed (1 seconds).", CASE + " started.", measurement(),
                          CASE + " passed (1 seconds)."])
        attempts = extract(text)["attempts"]
        self.assertEqual([a["attempt"] for a in attempts], [1, 2])
        self.assertEqual([a["functional_passed"] for a in attempts], [False, True])
        self.assertEqual(attempts[0]["status"], "failed")
        self.assertEqual(len(attempts[0]["metrics"]), 1)
        self.assertEqual(attempts[0]["metrics"][0]["n"], 3)
        self.assertEqual(attempts[0]["metrics"][0]["duplicate_lines"], [3])

    def test_incomplete_or_missing_start_cannot_pass_functional_gate(self):
        self.assertFalse(extract(CASE + " started.\n" + measurement())["attempts"][0]["functional_passed"])
        self.assertFalse(extract(measurement() + "\n" + CASE + " passed (1 seconds).")
                         ["attempts"][0]["functional_passed"])

    def test_optional_conversion_uses_decimal_kb_and_preserves_negative_delta(self):
        metric = extract(measurement(2), include_mib=True)["attempts"][0]["metrics"][0]
        self.assertEqual(metric["unit"], "kB")
        self.assertAlmostEqual(metric["derived_mib"]["median"], -2588.672 * 1000 / 1048576)
        for unit in ["KB", "bytes", "s"]:
            metric = extract(measurement(unit=unit), include_mib=True)["attempts"][0]["metrics"][0]
            self.assertNotIn("derived_mib", metric)

    def test_malformed_nonfinite_values_are_rejected(self):
        for value in ["nan", "inf", "", "broken"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                extract(measurement().replace(MEASUREMENTS[0][3], value))


if __name__ == "__main__":
    unittest.main()
