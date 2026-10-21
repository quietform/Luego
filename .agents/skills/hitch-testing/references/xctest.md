# XCTest hitch measurements

## Select the metric and supported environment

Use XCTest for UI/performance tests even if functional unit tests use Swift Testing. Check availability against the installed SDK and the test destination; never silently replace an unsupported hitch metric with elapsed time.

| Metric | Scope |
| --- | --- |
| `XCTHitchMetric(application:)` | Xcode 26 / iOS and iPadOS 26+: hitches in the target app over the measured test portion, including hitch time ratio |
| `XCTOSSignpostMetric.scrollingAndDecelerationMetric` | System-instrumented dragging and deceleration intervals; verify that the actual scroll surface emits measurements |
| `XCTOSSignpostMetric(subsystem:category:name:)` | Matching named signpost intervals in the measured interaction |

The separate `scrollDraggingMetric` and `scrollDecelerationMetric` properties used in older examples are deprecated. Prefer the combined scrolling metric for that scope. Instrumented navigation metrics are also available, but verify matching intervals for the app's actual navigation implementation.

Sources: [Xcode 26, 34:40](https://developer.apple.com/videos/play/wwdc2025/247/?time=2080), [XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric), [XCTOSSignpostMetric](https://developer.apple.com/documentation/xctest/xctossignpostmetric), [XCTest](https://developer.apple.com/documentation/xctest).

## Establish the test harness

Inspect existing test targets, launch configuration, and fixtures before adding a UI performance target. A logic-only test bundle cannot drive the displayed app merely by importing its models. Create only the harness required for the requested scenario. Use isolated fixtures for regression tests; use real account/network conditions when that is the requested experiment and report the loss of determinism.

Restore an exact content/scroll/cache state before each measurement. An inverse swipe is not a reliable reset: clamping, variable heights, loading, and caching can change subsequent work. Assert that the expected scroll surface and content are present and that the gesture reaches the expected state. Otherwise an empty or wrong screen can appear fast.

This reusable measurement helper belongs inside an `XCTestCase` subclass targeting a supported destination. The caller supplies fixture restoration and a bounded, observable completion check; these are app-specific contracts, not built-in XCTest APIs. Choose the iteration count after checking variance.

```swift
@MainActor
func measureScroll(
    app: XCUIApplication,
    scrollView: XCUIElement,
    restoreFixture: () -> Void,
    waitForScrollCompletion: () -> Void
) {
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    options.invocationOptions = [.manuallyStart, .manuallyStop]

    measure(metrics: [XCTHitchMetric(application: app)], options: options) {
        restoreFixture()
        startMeasuring()
        scrollView.swipeUp(velocity: .fast)
        waitForScrollCompletion()
        stopMeasuring()
    }
}
```

Include the intended dragging, deceleration, or transition through completion; verify the gesture's actual timing rather than assuming its return marks the end of animation. Keep readiness and restoration outside the interval. Avoid fixed sleeps that pad the denominator; if no precise completion observation exists, report the boundary approximation. Custom completion hooks must preserve production behavior.

`iterationCount` records that many measurements after an additional discarded warm-up iteration. Label warm-up separately; retain its conditions and workload evidence for diagnosis even though its metrics are discarded. For a cold-content scenario, explicitly restore the relevant cold state on every pass, including warm-up. Relaunching alone does not clear persistent or OS caches. Document which cache layers can actually be controlled. Test launch performance separately when that is the question.

For image scenarios, verify actual file/network/cache responses and completed work, not only the selected launch mode. Retain per-gesture and whole-traversal counters. Prefetch timing can redistribute work between gestures, so identical per-gesture request counts are not a prerequisite for a valid traversal. Both modes reporting zero hitches does not establish a cache-related speed improvement.

Sources: [measurement iterations](https://developer.apple.com/documentation/xctest/xctmeasureoptions/iterationcount), [performance test configuration](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests).

## Verify the effective launch configuration

Inspect the exported `.xctestrun` when using prepared test products. Scheme/test-plan requests alone do not prove that checkers and screenshot collection are disabled. In the Xcode 26.0 device run on 2026-10-16, the export retained checker injections and attachment defaults despite those requests.

Check each relevant test target's `UITargetAppMainThreadCheckerEnabled`, `UITargetAppPerformanceAntipatternCheckerEnabled`, `SystemAttachmentLifetime`, and `UserAttachmentLifetime`. Inspect `DYLD_INSERT_LIBRARIES` in both `TestingEnvironmentVariables` and `UITargetAppEnvironmentVariables`. In that run, `libMainThreadChecker.dylib` and `libRPAC.dylib` needed removal; preserve required XCTest injections and unrelated environment settings. These are observed export behaviors, not a requirement to rewrite every toolchain's configuration.

When normalization is needed, retain the original export and effective configuration. Keep a tested, version-appropriate transformation in the host repository rather than repeatedly editing generated files by hand. Discard automatic system screenshots for measurement while retaining the explicit conditions attachment.

Keep profiler-waiting tests out of the default Run All selection, with an explicit profiling plan or runtime opt-in. A README telling users to select a method does not exclude manual checkpoints from unattended runs. Test that every checkpoint method is excluded by default and remains available through the opt-in route; inspect Xcode's effective selection as well as the source configuration. With separate plans, document the profiling plan at build/export time and the resulting `.xctestrun` path. `-only-testing:` does not undo a plan's exclusions. Preserve matching measurement settings and verify signed binary identity for comparisons across plans.

## Controlled contention and completion

For scrolling under background work, restore the same library and active observers in both modes, then add only the controlled workload. State which production path the replay exercises and which orchestration, network, SDK or rendering work it excludes. Assert accepted/completed counts, persistence, observer delivery, movement, and actual overlap with each animation. An asynchronous batch may extend beyond scrolling; its whole elapsed duration is neither CPU time nor proof that every record overlapped the interaction.

Keep workload verification outside the custom animation interval and complete it before the next gesture. When a completion signal and a UI observer check are both required, share one total deadline rather than granting a fresh full timeout to each. A benchmark-only signal can reduce accessibility polling during writes, but it does not prove that polling caused a slowdown. Observation-ignored counters or a captured overlay may be stale; use durable fixture state, including its database WAL where applicable, to distinguish incomplete work from delayed UI reporting.

If a test pauses unexpectedly, correlate native test timestamps with host sleep/wake events before changing code or deadlines. XCTest's device keep-awake behavior does not cover trace-export gaps, and a host idle-sleep assertion does not prevent clamshell sleep. Preserve interrupted runs and repeat unchanged on an awake host; they are not performance samples.

## Custom intervals

Use `OSSignposter.beginInterval` / `endInterval` for application work such as document preparation. Use `beginAnimationInterval` for a visual animation interval whose end is tied to actual completion. Ordinary duration instrumentation is not automatically an animation measurement.

```swift
let signposter = OSSignposter(subsystem: "com.example.app", category: "Reader")
let intervalID = signposter.makeSignpostID()
let interval = signposter.beginAnimationInterval("ReaderTransition", id: intervalID)
```

Retain that interval state and call `signposter.endInterval("ReaderTransition", interval)` when the transition completes, including appropriate interrupted completion paths. Do not immediately end after scheduling an asynchronous animation. Keep names stable and use distinct IDs for overlapping intervals. Match subsystem, category, and name in `XCTOSSignpostMetric`. Inspect the results to confirm that the intended interval and animation metrics were collected.

For a bounded traversal containing multiple gestures, give each step a distinct static signpost name and its own custom metric. Reuse those names across traversals, with each name occurring exactly once per pass. This preserves the full scenario while avoiding ambiguous aggregation of repeated same-name intervals. Restore the complete fixture before each traversal, allowing gestures within it to advance content. Verify every expected interval's closure and duration; keep inter-gesture idle time and workload tails outside animation denominators.

Sources: [OSSignposter](https://developer.apple.com/documentation/os/ossignposter), [animation intervals](https://developer.apple.com/documentation/os/ossignposter/beginanimationinterval(_:id:)). The WWDC20 `.animationBegin` examples use the older signpost API.

## Calibrate with a known stall

Use a positive control when establishing a harness, investigating inconsistent counters, or changing the toolchain or collector configuration. Compare normal animation with an opt-in, benchmark-only mode that deliberately delays its rendering. Use the same signed build, fixture restoration, measurement boundaries, and device conditions, changing only the injection setting. Keep the injector out of production targets and ordinary baseline runs.

A generic main-thread block during scrolling may not delay a displayed frame. If it fails to produce a repeatable late-frame response, test work on the critical drawing/update path, such as a synchronous delay inside a draw callback for a display-link-driven visible animation. Confirm visible updates in normal mode and completed work in both modes. Draw callbacks and display-link ticks establish workload activity, not presented-frame counts.

Verify the control itself before interpreting SDK metrics: assert no injected blocks in normal mode, and record the completed block count, actual monotonic durations, and main-thread execution in stalled mode. Ensure each block falls within the intended animation rather than preparation or idle time. An asynchronous suspension such as `Task.sleep` does not block the main thread and cannot substitute for this control. Follow the host repository's TDD workflow when implementing the injector.

Mark each block's start/end and verify its thread and nesting within the animation in a separate Instruments capture; use the [device-capture workflow](device-capture.md). Inspect frame activity and late-frame rows in that capture. CPU blocking duration and displayed-frame lateness are different quantities: do not expect equal durations or use injected milliseconds as a hitch-ratio numerator. Check that the chosen XCTest metric and independent trace agree in scope and scale under matching conditions; exact equality across separate runs is unnecessary. Keep traced observations separate from untraced measurements.

Assess each collector and exported field independently. A custom signpost metric responding does not validate an app-wide collector, and a missing or contradictory frame counter does not establish that every other field is wrong. A positive response establishes sensitivity to that particular slowdown, not complete hitch detection or quantitative accuracy. Leave nonresponding metrics unvalidated; investigate their scope and lifecycle without declaring a universal SDK defect. Keep device-specific findings and raw values in the run's results report. Calibration alone does not justify a quality gate; measurement scope, aggregation, noise, and an absolute target still need validation.

## Conditions across repeated passes

Declare the intended conditions before running. Record thermal state, power mode, and storage before and after every pass, including warm-up. If conditions drift, retain the complete run and mark it ineligible for the originally planned matched-condition comparison. A cooling pause followed by an unchanged repeat can distinguish a transient event from a recurring transition; recheck device lock and automation readiness before restarting. If the transition recurs, do not keep repeating solely to obtain favorable conditions or select only nominal samples.

If the task permits an absolute assessment under the observed conditions, explicitly disclose the extended scope, validate the chosen collector with normal/delayed controls in the newly observed thermal state, and retain all samples and the original target. This supports only a condition-qualified result: it does not satisfy an explicit nominal-only requirement, restore a matched regression baseline, or establish the cause of thermal rise. A short nominal trace does not erase thermal drift in sustained untraced repetitions.

## Validate and gate the result

- Confirm that the intended animated interaction ran, its full interval was captured, and the requested metrics are present. A test succeeding is insufficient if no matching signpost or hitch data was recorded.
- Cross-check inconsistent fields against native test output, legacy summaries, and modern JSON before changing an exporter. If a frame count is already zero upstream, a parser change cannot recover it. Retain raw values and the failing diagnostic; neither FPS multiplied by duration nor trace row counts repair the counter. A hitch ratio can be accepted independently only after isolating that limitation and validating its own fields, positive-control response, and separate trace evidence. This does not validate another collector or establish an SDK defect's cause.
- For repeated signpost intervals within one iteration, verify whether exported duration/counts are per interval, averaged, or aggregated. If semantics remain ambiguous, use distinct per-step metrics as described in [Custom intervals](#custom-intervals), or reduce the scenario to one complete animation per sample. Check reported durations and restore the fixture before each traversal or independent sample. State any reduced scope and leave older ambiguous exports unresolved; never combine swipes with idle gaps to manufacture a denominator.
- Derive the expected metric set from the scenario definition, not only the fields that happen to export: a missing final step must fail validation. Check field presence, units, finite nonnegative values, aligned sample counts within and across step metrics, positive duration, and ratio consistency with hitch milliseconds divided by interval seconds, allowing for export precision. Require clear, repeatable positive-control separation; experimental separation thresholds are not universal constants. These numerical checks cannot certify device conditions, build identity, completed workloads, or valid traces.
- Record build configuration, instrumentation settings, fixture/cache state, gesture, measured duration, iteration values, device/OS/Xcode, revision, and thermal/power conditions alongside the `.xcresult` and relevant `.trace`.
- Compare matching environments. Hold device, OS, and settings fixed for a regression comparison; use a separate run to investigate another refresh rate, device class, or OS.
- Use measured noise to set a relative tolerance and an independent absolute quality target. Preserve the target's strict or inclusive boundary. When every scroll must meet the target, check every retained step/sample rather than averaging across a traversal. Repeated zeros alone do not establish a relative regression tolerance or whole-app smoothness. Preserve individual hitch durations where available in traces; an aggregate average can conceal a large stall.
- Retain deterministic functional and main-actor responsiveness tests as separate contracts. They validate correctness or scheduling progress, not presentation deadlines.
