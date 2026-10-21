import argparse
import json
import math
from pathlib import Path


def ratios(metrics, name):
    prefix = f"com.apple.dt.XCTMetric_OSSignpost-{name}"
    fields = [(".duration", "s"), (".animation.hitches.total.duration", "ms"), (".animation.hitch.time.ratio", "ms per s")]
    values = []
    for suffix, unit in fields:
        matches = [metric for metric in metrics if metric["identifier"] == prefix + suffix]
        if len(matches) != 1 or matches[0].get("unitOfMeasurement") != unit:
            raise ValueError(f"{name}: missing, duplicate or incorrectly scaled {suffix}")
        samples = matches[0].get("measurements", [])
        if not samples or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0 for value in samples):
            raise ValueError(f"{name}: invalid {suffix} measurements")
        values.append(samples)
    if len({len(samples) for samples in values}) != 1:
        raise ValueError(f"{name}: metric sample counts differ")
    for duration, hitch_ms, ratio in zip(*values):
        if duration <= 0 or not math.isclose(ratio, hitch_ms / duration, rel_tol=1e-4, abs_tol=1e-5):
            raise ValueError(f"{name}: hitch ratio disagrees with hitch milliseconds / interval seconds")
    return values[2]


def assess(normal, delayed, reader, scroll_count=None):
    names = [f"ReaderScroll{index}" for index in range(1, scroll_count + 1)] if scroll_count else ["ReaderScroll"]
    try:
        normal_ratios = ratios(normal, "CalibrationAnimation")
        delayed_ratios = ratios(delayed, "CalibrationAnimation")
        reader_ratios = {name: ratios(reader, name) for name in names}
    except ValueError as error:
        return [str(error)]
    if len({len(samples) for samples in reader_ratios.values()}) != 1:
        return ["Swipe sample counts differ"]
    if min(delayed_ratios) <= max(10, max(normal_ratios)):
        return ["Delayed-draw control must exceed 10 ms/s and every normal-control sample"]
    return [f"{name} sample {index} must be below 5 ms/s" for name, samples in reader_ratios.items() for index, ratio in enumerate(samples, 1) if ratio >= 5]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check custom hitch values after independently reviewing run conditions and calibration traces.")
    for name in ("normal", "delayed", "reader"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--scroll-count", type=int, choices=(3, 6), help="Require every separately named swipe in the sync or image traversal")
    arguments = parser.parse_args()
    runs = []
    for path in (arguments.normal, arguments.delayed, arguments.reader):
        exported = json.loads(path.read_text())
        metrics_runs = [run["metrics"] for test in exported for run in test["testRuns"]]
        if len(metrics_runs) != 1:
            parser.exit(1, f"{path}: select exactly one test run\n")
        runs.append(metrics_runs[0])
    issues = assess(*runs, scroll_count=arguments.scroll_count)
    if issues:
        print("\n".join(issues))
        raise SystemExit(1)
    scope = f"ReaderScroll1 through ReaderScroll{arguments.scroll_count}" if arguments.scroll_count else "ReaderScroll"
    print(f"Numeric hitch-ratio check passed: every {scope} sample is below 5 ms/s.")
