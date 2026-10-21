import argparse
import json
from pathlib import Path


def validate(metrics):
    counts = next((metric["measurements"] for metric in metrics if metric["identifier"] == "com.apple.dt.XCTMetric_OSSignpost-ReaderScroll.animation.frame.count"), [])
    if not counts:
        return ["ReaderScroll frame counts are missing"]
    invalid = [str(index) for index, count in enumerate(counts, 1) if not count > 0]
    return ["ReaderScroll frame counts must be positive; invalid samples: " + ", ".join(invalid)] if invalid else []


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check ReaderScroll frame-count validity, without setting a performance gate.")
    parser.add_argument("metrics", type=Path)
    arguments = parser.parse_args()
    results = json.loads(arguments.metrics.read_text())
    runs = [(result["testIdentifier"], run["metrics"]) for result in results for run in result["testRuns"]]
    issues = [f"{identifier}: {issue}" for identifier, metrics in runs for issue in validate(metrics)]
    if not runs:
        issues.append("No metric runs were exported")
    if issues:
        print("\n".join(issues))
        raise SystemExit(1)
    print("ReaderScroll frame counts are positive. Performance quality has not been assessed.")
