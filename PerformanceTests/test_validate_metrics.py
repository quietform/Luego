import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from validate_metrics import validate


class ValidateMetricsTests(unittest.TestCase):
    def test_rejects_zero_frame_counts_despite_nonzero_frame_rate(self):
        metrics = [
            {"identifier": "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.rate", "measurements": [58.1055, 58.1530]},
            {"identifier": "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.count", "measurements": [0, 0]},
        ]

        self.assertTrue(validate(metrics))

    def test_rejects_missing_frame_counts(self):
        metrics = [{"identifier": "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.rate", "measurements": [58.1055]}]

        self.assertTrue(validate(metrics))

    def test_cli_exit_status_reflects_frame_count_validity(self):
        for count, expected_status in [(0, 1), (149, 0)]:
            with self.subTest(count=count), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "metrics.json"
                path.write_text(json.dumps([{"testIdentifier": "ReaderHitchTests/testWarmTextReaderHitches()", "testRuns": [{"metrics": [
                    {"identifier": "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.rate", "measurements": [58.1]},
                    {"identifier": "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.count", "measurements": [count]},
                ]}]}]))

                result = subprocess.run([sys.executable, str(Path(__file__).with_name("validate_metrics.py")), str(path)], capture_output=True, text=True)

                self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
