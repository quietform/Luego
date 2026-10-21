# Calibrated image and foreground-sync benchmarks — 2026-10-21

**Both image-heavy scrolling and controlled foreground-sync scrolling meet the strict <5 ms/s target in the recorded untraced samples.** All per-swipe ratios are 0 ms/s, with a responding rendering-dependent positive control. Separate completed traces report no late frame intersecting any scenario scroll.

The sustained sync runs transition from nominal to fair thermal state. Calibration responds in both states, and every sample is retained. An all-nominal sustained-sync comparison was not obtained; these results establish the absolute target for the documented conditions, not a relative performance improvement or whole-app smoothness.

## Untraced results

Each run discards one warmup and retains three complete traversals. Every named swipe has its own ratio and duration; no mean across swipes can hide a failing sample.

| Scenario | Retained swipe samples | Maximum hitch ratio | Individual scroll duration | Thermal state |
| --- | ---: | ---: | --- | --- |
| Cold encoded image cache | 18 | **0 ms/s** | 2.529728–2.571901 s | Nominal |
| Warm encoded image cache | 18 | **0 ms/s** | 2.512781–2.567458 s | Nominal |
| Sync fixture, no applied batches | 9 | **0 ms/s** | 2.512590–2.551589 s | Nominal |
| Sync contention, two complete runs | 18 | **0 ms/s** | 2.512718–2.570626 s | Nominal → fair |

All 63 retained scenario samples pass [the numerical checker](hitch_quality.py). It checks every expected interval, matching sample counts, finite nonnegative measurements, units, ratio arithmetic, positive-control separation and the strict threshold. Physical conditions, completed workloads, binary identity and trace validity are reviewed separately. No relative regression tolerance or matched pre-change baseline is adopted.

## Workload and measurement scope

The benchmark preserves the prior [image fixture](RESULTS-2026-10-21-IMAGES.md) and [foreground-sync workload](RESULTS-2026-10-17-FOREGROUND-SYNC.md). Production source and actor layout are unchanged.

Images use twenty-four pinned travelogue photos through the production reader, visibility, loader and decoder, with offline fixture responses. Each pass recreates the process/database and starts at the top. Cold means an empty encoded URLCache at app entry; initial visible images load before measurement, and filesystem/OS caches are not cleared. Warm primes encoded responses, not decoded images. Six fast upward swipes must reach idle, advance real content, overlap image work and finish replacing visible placeholders.

Every retained cold traversal serves 13 file responses total, 10 starting during scrolling, totaling 7,833,810 bytes, with zero encoded-cache hits. Every retained warm traversal serves 13 cache responses total, 10 during scrolling, with 24 responses primed and zero fixture file reads. Neither mode reports image failures or injected stalls. Per-swipe work distributions vary slightly with prefetch timing and remain in the attachments. Both discarded warmups serve 14 responses with 11 during scrolling. These observations do not establish a cache-speed improvement.

Sync baseline/contention both prepare 2,001 articles in an isolated file-backed database and retain the production list observer. Contention applies three batches of 100 incoming-record conversions and saves, one per swipe. Every pass completes all 300 writes, persistence verification and three observer confirmations; every batch overlaps its scroll. Fully overlapping applied records per retained traversal are **116/108/109** in `sync-contention` and **115/107/105** in `sync-contention-repeat` (warmups: 114 and 122). The replay exercises local apply/materialization, excluding CloudKit transport, sync-engine orchestration, remote delivery and SDK startup.

The new opt-in `--benchmark-indexed-scrolls` mode emits `ReaderScroll1` through `ReaderScroll6` for images or `ReaderScroll3` for sync. Each named metric contains one complete animation interval per pass. Readiness, test-driver gaps and post-scroll workload tails are outside the animation denominator. The complete fixture resets before every pass, and each sync batch finishes before the next swipe. Historical multi-interval exports remain unresolved and are not reinterpreted as valid baselines.

## Calibration and thermal qualification

| Untraced control conditions | Normal animation, three retained ratios | Delayed drawing, three retained ratios |
| --- | --- | --- |
| Nominal | 0 / 0 / 0 ms/s | 60.545967 / 60.455124 / 60.542346 ms/s |
| Fair | 0 / 0 / 0 ms/s | 60.459805 / 60.453665 / 60.558976 ms/s |

The delayed control verifies one synchronous main-thread draw block per animation, with monotonic timing. Injected milliseconds are not used as the hitch numerator; draw callbacks are not presented-frame counts. XCTest's frame counter and app-wide collector remain unvalidated. Acceptance uses the independently calibrated custom duration, hitch duration and hitch ratio.

In the first sustained-sync run, warmup and the first retained traversal stay nominal; the second retained traversal changes to fair, and the third remains fair. The complete run was excluded from the intended all-nominal comparison. After an idle cooling pause and unlocking the phone, the unchanged repeat reproduces the same thermal sequence. We stopped repeating that protocol, preserved both complete runs, and explicitly extended the absolute assessment to the observed nominal/fair conditions. Separate normal/delayed controls then remained fair throughout and demonstrated the response above. Both sync runs pass against both calibration pairs. No sample was dropped, threshold relaxed or timeout widened. The cause of the thermal rise was not established.

The current-build nominal trace pair confirms three normal animations with no late frames and three delayed animations each containing a fully enclosed **182.982–182.993 ms** late frame. One additional late frame is outside those delayed-animation intervals. The fair delayed trace similarly records three enclosed **182.984–183.092 ms** late frames and three nested main-thread draw blocks of approximately 201 ms. An additional 9.504 ms frame partially crosses its third animation boundary; its full hitch duration is neither assigned nor prorated to that animation, so an exact ratio for that traced interval remains unavailable. These traces agree with XCTest in scale and scope without substituting injected time for measured hitch time. Collector labels alone do not establish the responsible pipeline stage.

## Completed scenario traces

All four scenario captures use the same saved signed build, wired USB, the Time Profiler template plus Frame Lifetimes, and the recorder-start notification/checkpoint. Tests and recorders exit zero. Every required animation/work interval closes; frame activity overlaps every scroll. All four start and end nominal, with Low Power Mode off and more than 2 GB free. They are separate diagnostic captures, not additional untraced samples.

| Capture | Closed scrolls | Combined scroll duration | Whole-trace frame-lifetime rows | Late frames intersecting scrolls | Late frames elsewhere |
| --- | ---: | ---: | ---: | ---: | ---: |
| `image-cold-trace` | 6 | 15.262770 s | 1,028 | **0** | 2 |
| `image-warm-trace` | 6 | 15.244833 s | 1,027 | **0** | 0 |
| `sync-baseline-trace` | 3 | 7.627763 s | 536 | **0** | 1 |
| `sync-contention-trace` | 3 | 7.607778 s | 558 | **0** | 0 |

Frame selection includes any positive lifetime intersection, including boundary crossings. No scenario scroll has a partially overlapping late frame. Frame-lifetime rows are pipeline records, not presented-frame counts or FPS. Late frames outside scrolling remain in the evidence; the target here covers scrolling, not the entire test's wall time.

Both image captures reproduce 13 total responses and 10 during scrolling, with the intended cold/warm cache behavior and no failures. The sync capture finishes all 300 writes and three observer confirmations, with 111 record applications fully inside scrolling. Its three closed apply batches last **7.035/7.065/7.278 s**, overlapping their respective scrolls by **2.335/2.330/2.323 s**. Whole-batch elapsed time is not CPU time, and each tail remains outside the custom scroll denominator. The nominal traced sync pass supports the interaction diagnosis; it does not replace the thermal qualification on the repeated untraced workload.

## Build, verification and retention

Hardware/software: iPhone 15, iOS 27.0.1 (24A446), Xcode 26.0 (17A324), macOS 26.5.2 (25F84), explicit arm64 destination. The user confirmed Focus and USB/unlock. All measured passes have Low Power Mode off. Observed free storage across measurements/captures is approximately **4.75–4.96 GB**. Conditions are retained per pass rather than inferred from one preflight.

The saved app and dSYM share UUID **`9C17F48B-B58E-3F7F-8EFC-76C115F6E877`**; the fair delayed trace's CPU export independently identifies that UUID. All twenty-four bundled photo hashes match the manifest. Original/effective runner configuration disables coverage, checkers and automatic system screenshots while retaining explicit conditions attachments. Native logs retain DeviceSupport lookup diagnostics; successful test/recorder exits and actual exported workload/frame data establish completion, not the absence of warnings. The Release build passes with its existing orientation warning.

TDD first exposed missing indexed instrumentation metadata, then verified all six swipe names and actual image work. The checker first rejected its new CLI mode; a second failing test exposed inconsistent per-swipe sample counts before validation was added. Regression cases cover missing swipes, a sample exactly at 5 ms/s, and nonresponding controls. **15 Python tests and four fixture checks on each iPhone/iPad simulator pass**. Simulator checks establish harness behavior, not physical-device smoothness. An initial test compilation error was corrected before recording the assertion-level RED result.

Evidence is retained under `build/hitches/2026-10-21/calibrated-scenarios/`: raw/copied result bundles, metrics and conditions, raw traces and exports, signed products/dSYM and bundled photos, original/effective runner configuration, command/connection records, source snapshots, RED/GREEN logs and `NOTES.md`. `untraced-assessment.json` and `trace-assessment.json` summarize the complete evidence, including both thermal-transition runs and boundary ambiguity. Final fingerprint checks preserve all nine measurement/tooling files and all 96 recorded production/configuration files. No source was rebuilt or changed between physical runs.

Supported uninstall commands removed only the benchmark app and XCTest runner. A fresh `apps-after-cleanup.json` verifies both absent and ordinary Luego/Luego Dev retained. Last observed device free space before cleanup was 4,874,240,000 bytes. System-managed profiler caches are not claimed removed. No task-owned test or recorder remains, and the simulators are shut down.

Reusable procedures from this run are now documented in the [hitch-testing skill's XCTest reference](../.agents/skills/hitch-testing/references/xctest.md): per-step metrics across full traversals, expected-metric completeness, cache-work verification, and thermal qualification of absolute results. Measured values, device/build identities, and this run's limitations remain in this report and its retained evidence.

## Post-review workflow verification

Review found that the default plan still selected manual profiler checkpoints and the README's recorder command omitted its readiness notification flag. These are fixed after the physical measurements: `ReaderHitches` excludes all 14 `WithProfiler` methods, and the explicit `ReaderProfiling` plan selects them using the same exported binaries. Failing regression tests first demonstrated the unsafe default and missing opt-in plan. Xcode's exported configurations preserve the exclusions/selections. On both iPhone Air and iPad Pro 11-inch (M4) simulators, requesting the ordinary reader fixture and one excluded profiler method ran only the fixture: one pass, zero failures, no manual checkpoint.

The capture recipe now registers a bounded host listener before launching xctrace, includes `--notify-tracing-started`, and posts the device checkpoint only on listener success. Tests written before the listener implementation exercise actual macOS Darwin notifications: registration alone cannot succeed, a subsequent notification succeeds, and a missing notification exits with failure. All **19 Python tests** pass. The hitch-testing skill validator and whitespace checks pass; seven generated `.pyc` files were removed and Python bytecode is ignored.

The preceding review also passed **85 production tests on each iPhone/iPad simulator** and revalidated all 63 retained scenario samples against the controls. Workflow checks and logs are retained under `build/review-2026-10-21/workflow-fixes/`, alongside the preceding review's verification record. The production Swift sources are unchanged; the only benchmark Swift edit is removal of a trailing blank line. No new physical-device capture was performed for the workflow fixes; the measurement-time configurations, fingerprints and qualifications above remain authoritative for the reported hitch results.
