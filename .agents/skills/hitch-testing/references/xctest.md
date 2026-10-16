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

`iterationCount` records that many measurements after an additional discarded warm-up iteration. For a cold-content scenario, explicitly restore the relevant cold state on every pass, including warm-up. Relaunching alone does not clear persistent or OS caches. Document which cache layers can actually be controlled. Test launch performance separately when that is the question.

Sources: [measurement iterations](https://developer.apple.com/documentation/xctest/xctmeasureoptions/iterationcount), [performance test configuration](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests).

## Custom intervals

Use `OSSignposter.beginInterval` / `endInterval` for application work such as document preparation. Use `beginAnimationInterval` for a visual animation interval whose end is tied to actual completion. Ordinary duration instrumentation is not automatically an animation measurement.

```swift
let signposter = OSSignposter(subsystem: "com.example.app", category: "Reader")
let intervalID = signposter.makeSignpostID()
let interval = signposter.beginAnimationInterval("ReaderTransition", id: intervalID)
```

Retain that interval state and call `signposter.endInterval("ReaderTransition", interval)` when the transition completes, including appropriate interrupted completion paths. Do not immediately end after scheduling an asynchronous animation. Keep names stable and use distinct IDs for overlapping intervals. Match subsystem, category, and name in `XCTOSSignpostMetric`. Inspect the results to confirm that the intended interval and animation metrics were collected.

Sources: [OSSignposter](https://developer.apple.com/documentation/os/ossignposter), [animation intervals](https://developer.apple.com/documentation/os/ossignposter/beginanimationinterval(_:id:)). The WWDC20 `.animationBegin` examples use the older signpost API.

## Validate and gate the result

- Confirm that the intended animated interaction ran, its full interval was captured, and the requested metrics are present. A test succeeding is insufficient if no matching signpost or hitch data was recorded.
- Record build configuration, instrumentation settings, fixture/cache state, gesture, measured duration, iteration values, device/OS/Xcode, revision, and thermal/power conditions alongside the `.xcresult` and relevant `.trace`.
- Compare matching environments. Hold device, OS, and settings fixed for a regression comparison; use a separate run to investigate another refresh rate, device class, or OS.
- Use measured noise to set a relative tolerance and an independent absolute quality target. Preserve individual hitch durations where available in traces; an aggregate average can conceal a large stall.
- Retain deterministic functional and main-actor responsiveness tests as separate contracts. They validate correctness or scheduling progress, not presentation deadlines.
