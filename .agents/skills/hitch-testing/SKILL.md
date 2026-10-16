---
name: hitch-testing
description: Measure and regression-test scrolling and animation hitches in Apple-platform apps using XCTest and Instruments. Use for frame-deadline diagnosis, XCTHitchMetric, animation signposts, or repeatable smoothness benchmarks; not animation choreography or general functional UI testing.
---

# Hitch Testing

Establish whether a specific interaction misses display deadlines, locate the responsible work, and preserve a repeatable regression measurement. Source inspection identifies candidates; it cannot establish displayed-frame smoothness.

## Choose the evidence

| Question | Evidence to collect |
| --- | --- |
| Does this interaction hitch? | A bounded XCTest hitch measurement and an Instruments trace |
| Why does it hitch? | Correlated app, render-server, and GPU work for the late frame |
| Did the change help? | Before/after runs with matching fixture, device, OS, build settings, and measurement boundaries |
| Are users affected after release? | Organizer trends or SDK-appropriate MetricKit reports |

When asked only for a source audit, report hypotheses and the measurement needed to test each. Do not label an app smooth, janky, or broken from code patterns. Fewer view updates, a passing functional test, or a queued main-actor heartbeat are not measurements of displayed frames.

## Define a bounded experiment

Record the interaction, content fixture, starting position, expected end state, cache condition, and concurrent activity. Restore these before every iteration. Specify cold and warm scenarios separately. Avoid uncontrolled live networks or sync in a regression baseline; use a controlled workload when testing contention itself.

For a reader or feed, useful separate scenarios are text-heavy scrolling, image-heavy scrolling with controlled cache states, and scrolling while a fixed batch of background updates is applied. Choose the smallest scenario that reproduces the reported issue rather than adding every scenario automatically.

Use a dedicated performance scheme or test plan with Release builds, debugger detached, coverage and runtime diagnostics disabled, and automatic screenshot collection disabled where configurable. Keep ordinary diagnostic tests separate. Collect comparable runs on a physical device, recording device/OS/Xcode versions, refresh-rate settings, thermal/power conditions, and revision. Simulator runs can validate the harness but do not establish device smoothness. Follow the host repository's build and testing rules.

Read [references/xctest.md](references/xctest.md) when writing tests, selecting metrics, instrumenting intervals, or setting regression gates. It covers the Xcode 26 API, legacy alternatives, fixture restoration, warm-up behavior, and result validity.

## Diagnose before changing code

Record the failing interaction and inspect an actual hitch interval. Read [references/rendering.md](references/rendering.md) for commit/render diagnosis, SwiftUI update analysis, and image/rendering tradeoffs. Use the trace to choose a focused change; a suspicious source pattern alone does not prove the cause. If profiling is unavailable, continue useful inspection and harness work while stating that runtime diagnosis remains unverified.

Inspect execution boundaries rather than syntax: `.task`, `Task {}`, or an `async` declaration does not by itself move synchronous work off the main actor. Verify the callee's isolation, executor behavior, and synchronous portions using the project's Swift mode and toolchain. Preserve the app's UI-state, cancellation, and persistence contracts when moving work.

## Interpret and retain results

Hitch time ratio is total hitch milliseconds divided by the measured duration in seconds. For example, 60 ms / 12 s = 5 ms/s. Identify the metric and interval supplying that denominator; do not substitute the whole test's wall time for a signposted interval. Unrelated idle time can dilute an app-level ratio. Missing measurements or unmatched signposts are invalid evidence, not zero hitches. Inspect individual hitch durations and variability as well as the ratio; equal ratios can hide different interruption patterns.

Keep an absolute quality target separate from a relative regression baseline. Establish run-to-run noise before choosing tolerances, and use absolute allowances when the baseline is near zero. A passing comparison can preserve poor performance. Do not reset a baseline merely to make a failure pass. Retain result bundles/traces and the exact configuration needed to reproduce the result.

Historical thresholds are not universal test gates. The [WWDC20 talk](https://developer.apple.com/videos/play/wwdc2020/10077/) calls below 5 ms/s good, 5 to below 10 worth investigating, and 10 or more urgent. The [Organizer documentation checked on 2026-10-16](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app) uses up to 10 good, above 10 through 25 warning, above 25 through 50 critical, and above 50 immediate attention. Check current guidance and tool context before reusing these bands; a stricter project target is a separate choice.

## Close the loop

Report the scenario, metric/units, before/after values and spread, iteration/cache policy, hardware/software configuration, and trace/result paths. Explain whether the evidence supports a cause, an improvement, or only a hypothesis. If no device measurements exist, explicitly leave smoothness and improvement unverified.

After release, correlate Organizer hitch trends with app version and device model; use MetricKit when the project already collects it or the task includes telemetry. Check APIs against the deployment SDK rather than copying the talk's historical MetricKit API unchanged. Aggregated production data helps prioritize reproduction; it does not replace a causal trace. See Apple's [shipping-app responsiveness workflow](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app).
