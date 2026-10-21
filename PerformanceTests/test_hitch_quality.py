import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import hitch_quality


def metrics(name, ratios):
    prefix = f"com.apple.dt.XCTMetric_OSSignpost-{name}"
    return [
        {"identifier": prefix + ".duration", "unitOfMeasurement": "s", "measurements": [3] * len(ratios)},
        {"identifier": prefix + ".animation.hitches.total.duration", "unitOfMeasurement": "ms", "measurements": [ratio * 3 for ratio in ratios]},
        {"identifier": prefix + ".animation.hitch.time.ratio", "unitOfMeasurement": "ms per s", "measurements": ratios},
        {"identifier": prefix + ".animation.frame.count", "unitOfMeasurement": "frames", "measurements": [0] * len(ratios)},
    ]


class HitchQualityTests(unittest.TestCase):
    def test_indexed_swipes_cannot_omit_or_average_away_a_failure(self):
        normal = metrics("CalibrationAnimation", [0, 0, 0])
        delayed = metrics("CalibrationAnimation", [60, 60, 60])
        for count in (3, 6):
            with self.subTest(count=count):
                reader = sum((metrics(f"ReaderScroll{index}", [0, 0, 0]) for index in range(1, count)), [])
                self.assertTrue(hitch_quality.assess(normal, delayed, reader, scroll_count=count))
                reader += metrics(f"ReaderScroll{count}", [0, 5, 0])
                self.assertIn(f"ReaderScroll{count} sample 2 must be below 5 ms/s", hitch_quality.assess(normal, delayed, reader, scroll_count=count))
                self.assertTrue(hitch_quality.assess(normal, normal, reader, scroll_count=count))

    def test_indexed_swipes_require_matching_sample_counts(self):
        reader = metrics("ReaderScroll1", [0, 0, 0]) + metrics("ReaderScroll2", [0]) + metrics("ReaderScroll3", [0, 0, 0])
        self.assertIn("Swipe sample counts differ", hitch_quality.assess(
            metrics("CalibrationAnimation", [0, 0, 0]), metrics("CalibrationAnimation", [60, 60, 60]), reader, scroll_count=3))

    def test_cli_checks_each_indexed_swipe(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / f"{name}.json" for name in ("normal", "delayed", "reader")]
            runs = [metrics("CalibrationAnimation", [0, 0, 0]), metrics("CalibrationAnimation", [60, 60, 60]),
                    sum((metrics(f"ReaderScroll{index}", [0, 4.999, 0]) for index in range(1, 7)), [])]
            for path, run in zip(paths, runs):
                path.write_text(json.dumps([{"testRuns": [{"metrics": run}]}]))
            command = [sys.executable, str(Path(__file__).with_name("hitch_quality.py")), *map(str, paths), "--scroll-count", "6"]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("ReaderScroll6", result.stdout)

    def test_cli_rejects_nonresponding_control(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name, scope in [("normal", "CalibrationAnimation"), ("delayed", "CalibrationAnimation"), ("reader", "ReaderScroll")]:
                path = Path(directory) / f"{name}.json"
                path.write_text(json.dumps([{"testRuns": [{"metrics": metrics(scope, [0, 0, 0])}]}]))
                paths.append(str(path))
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("hitch_quality.py")), *paths], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("Delayed-draw control", result.stdout)

    def test_valid_hitch_values_do_not_depend_on_the_unusable_frame_counter(self):
        self.assertEqual(hitch_quality.assess(
            metrics("CalibrationAnimation", [0, 0, 0]),
            metrics("CalibrationAnimation", [60, 60, 60]),
            metrics("ReaderScroll", [0, 4.999, 0]),
        ), [])

    def test_missing_invalid_or_inconsistent_metrics_cannot_pass(self):
        cases = [
            [],
            metrics("ReaderScroll", []),
            metrics("ReaderScroll", [float("nan")]),
            metrics("ReaderScroll", [-1]),
            metrics("ReaderScroll", [1]),
        ]
        cases[-1][1]["measurements"] = [30]
        for reader in cases:
            with self.subTest(reader=reader):
                issues = hitch_quality.assess(
                    metrics("CalibrationAnimation", [0, 0, 0]),
                    metrics("CalibrationAnimation", [60, 60, 60]),
                    reader,
                )
                self.assertTrue(issues)

    def test_every_reader_sample_must_be_strictly_below_five(self):
        for ratio in [5, 7]:
            with self.subTest(ratio=ratio):
                issues = hitch_quality.assess(
                    metrics("CalibrationAnimation", [0, 0, 0]),
                    metrics("CalibrationAnimation", [60, 60, 60]),
                    metrics("ReaderScroll", [0, ratio, 0]),
                )
                self.assertIn("ReaderScroll sample 2 must be below 5 ms/s", issues)

    def test_zero_reader_ratio_cannot_pass_a_nonresponding_control(self):
        issues = hitch_quality.assess(
            metrics("CalibrationAnimation", [0, 0, 0]),
            metrics("CalibrationAnimation", [0, 0, 0]),
            metrics("ReaderScroll", [0, 0, 0]),
        )

        self.assertIn("Delayed-draw control must exceed 10 ms/s and every normal-control sample", issues)
