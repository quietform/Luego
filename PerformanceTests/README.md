# Reader hitch benchmark

`LuegoPerformance.xcodeproj` compiles the production reader, services, and storage in a separate app (`com.esoxjem.Luego.performance`). `LUEGO_BENCHMARK` selects its entry point. The ordinary app, library, CloudKit account, and SDK startup are not used by this fixture.

The current quality objective is a verified **hitch time ratio below 5 ms/s**, following [Apple's XCTest guidance](https://developer.apple.com/videos/play/wwdc2020/10077/). This replaces the earlier 60 fps objective. Collector validity and a responding positive control are prerequisites; missing measurements or a nonresponding control do not pass the target. The [collector calibration investigation](RESULTS-2026-10-21-CALIBRATION.md) records the usable custom metric and the remaining SDK field limitations.

[2026-10-16 device results](RESULTS-2026-10-16.md) record the initial measurements and their limitations. The reusable tooling lessons are incorporated into the [hitch-testing skill](../.agents/skills/hitch-testing/SKILL.md).

[2026-10-17 stall calibration](RESULTS-2026-10-17.md) compares normal scrolling with known main-thread blocks and records which collectors respond.

[2026-10-17 foreground-sync experiment](RESULTS-2026-10-17-FOREGROUND-SYNC.md) records the controlled local-apply workload, verification, and device evidence status.

[2026-10-21 image-heavy experiment](RESULTS-2026-10-21-IMAGES.md) records the pinned travelogue-photo fixture, cache controls and device evidence status.

[Calibrated image and sync repeats](RESULTS-2026-10-21-CALIBRATED-SCENARIOS.md) record the per-swipe <5 ms/s assessment using the rendering-dependent calibration and separate traces.

## Scenario

- Text fixture v1: 80 fixed Markdown sections with emphasis and inline code, no images or live requests.
- Fresh process and in-memory GRDB database before each iteration, fixed article UUID/date, reading position zero, portrait, light appearance, Large Dynamic Type, and `en_US_POSIX` locale.
- Wait for the title and first rendered Markdown paragraph before measuring. Document preparation and launch are outside the measured interval. Font and OS caches are not cleared: this is prepared-text scrolling, not cold launch or cold image loading.
- Three upward `.fast` swipes through the real reader. Require a completed idle transition and at least 100 points of additional movement after every swipe, and require the title to leave the viewport.
- Normal reader progress tracking remains active. No CloudKit, shared-URL import, or other controlled contention runs in this first scenario.
- Five recorded iterations after XCTest's discarded warm-up. Recreate the fixture for all six passes.

`XCTHitchMetric(application:)` measures the manually bounded three-swipe test portion. That interval includes XCTest interaction and completion-observation overhead. The custom `ReaderScroll` animation signposts begin when the reader starts scrolling and end at its actual idle phase, including deceleration. Use the custom interval's duration as its denominator; do not divide its hitch time by the whole test duration. The small benchmark-only status overlay reports phase completion without observing geometry every frame.

## Run

Use a paired, unlocked physical device running iOS 26 or later. Leave it idle during measurements. Record power/thermal conditions and actual device/OS/Xcode versions. Use matching conditions for comparisons. A simulator validates the harness and cannot establish physical-device smoothness.

The scheme and test plan request Release optimization, no debugger, no coverage, disabled runtime performance/main-thread diagnostics, no automatic performance diagnostic collection, and discarded system screenshots. Xcode 26.0 still exported checker injections and default screenshot retention in this environment. `prepare_run.py` enforces the diagnostic and attachment settings in the generated `.xctestrun`, preserving required XCTest injections. Its regression test is `python3 -m unittest discover -s PerformanceTests -p 'test_*.py'`. Run the prepared configuration from outside the repository to avoid the repository’s default project arguments conflicting with `--xctestrun-path`. Keep parallel testing disabled.

```sh
xcodebuildmcp simulator test \
  --project-path PerformanceTests/LuegoPerformance.xcodeproj \
  --scheme LuegoPerformance --configuration Release \
  --simulator-id <simulator-uuid> \
  --json '{"extraArgs":["-parallel-testing-enabled","NO","-enableCodeCoverage","NO","-enablePerformanceTestsDiagnostics","NO","-collect-test-diagnostics","never","-only-testing:LuegoPerformanceUITests/ReaderHitchTests/testReaderFixtureIsScrollable"]}'

hitch_repo_root="$PWD"
hitch_products="$hitch_repo_root/build/hitches/prepared-$(date +%Y%m%d-%H%M%S).xctestproducts"
xcodebuildmcp device build \
  --project-path PerformanceTests/LuegoPerformance.xcodeproj \
  --scheme LuegoPerformance --configuration Release --build-for-testing \
  --test-products-path "$hitch_products" --device-id <device-udid> \
  --json '{"extraArgs":["-allowProvisioningUpdates","-enableCodeCoverage","NO","-enablePerformanceTestsDiagnostics","NO"]}'
hitch_run="$hitch_products/Tests/0/ReaderHitches.xctestrun"
python3 PerformanceTests/prepare_run.py "$hitch_run"
(
  cd /tmp
  xcodebuildmcp device test --xctestrun-path "$hitch_run" --device-id <device-udid> \
    --json '{"extraArgs":["-parallel-testing-enabled","NO","-enablePerformanceTestsDiagnostics","NO","-collect-test-diagnostics","never","-only-testing:LuegoPerformanceUITests/ReaderHitchTests/testSingleReaderIntervalHitches"]}'
)

xcrun xcresulttool get test-results metrics --path <result.xcresult> > <metrics.json>
```

Keep `.xcresult`, exported per-iteration metrics, conditions attachments, a source-diff fingerprint, and an Instruments `.trace` together under `build/hitches/<date>/`. Missing metrics, missing signposts, or failed fixture assertions invalidate a run; they do not mean zero hitches. Use the calibrated assessment below for the absolute target. A relative regression tolerance still requires a matched baseline and measured variability.

`validate_metrics.py` checks that the regular `ReaderScroll` measurement contains positive frame counts and exits nonzero otherwise. This checks counter availability, not performance quality. Preserve invalid exports for diagnosis; do not replace missing counts with FPS multiplied by duration. Run its tests with the same Python discovery command as `prepare_run.py`.

## Calibrated hitch-ratio assessment

Use `testAnimationMetricNormal` and `testAnimationMetricDelayedDraw` to calibrate the custom animation collector on the current physical device/toolchain. The isolated `--benchmark-animation-calibration` screen draws a moving bar for three seconds. The delayed mode blocks one actual draw for 200 ms, with a main-thread precondition, monotonic timing and signposts. Draw callbacks are execution evidence, not displayed-frame counts. These two methods keep the same process and reset the animation before each pass; they retain three samples after warmup. The separate `testAnimationNormalWithProfiler` and `testAnimationDelayedDrawWithProfiler` methods use the recorder-ready checkpoint for trace confirmation.

For a prepared-text quality check, `testSingleReaderIntervalHitches` restores the production reader before each pass and measures one complete upward swipe. Its three retained samples each correspond to one `ReaderScroll` interval, avoiding the unresolved aggregation semantics of the older multi-swipe methods. This covers the first swipe of the text fixture, not images, sync contention or the entire app.

For the complete image and sync traversals, use `testColdImageIntervalHitches`, `testWarmImageIntervalHitches`, `testForegroundSyncBaselineIntervalHitches`, and `testForegroundSyncContentionIntervalHitches`. These opt into `--benchmark-indexed-scrolls`: each swipe emits its own static `ReaderScroll1` through `ReaderScroll6` (images) or `ReaderScroll3` (sync) animation interval. Each metric therefore has one complete interval per retained pass, with three passes after discarded warmup. The entire fixture is restored before each pass; the six image swipes and three sync batches retain their cache, movement, persistence, observer, and overlap assertions. Idle gaps and sync completion tails are outside the named animation durations.

Pass `--scroll-count 6` (images) or `--scroll-count 3` (sync) to `hitch_quality.py` to require every named interval, matching sample counts across swipes, and every ratio strictly below 5 ms/s. Missing swipes cannot silently pass. The original methods retain their historical aggregation behavior for diagnostic reproduction. For matching separate captures, use `testIndexedColdImagesWithProfiler`, `testIndexedWarmImagesWithProfiler`, `testIndexedForegroundSyncBaselineWithProfiler`, and `testIndexedForegroundSyncWithProfiler`; these retain the same names under the profiling category.

Review test success, workload completion, matching device/OS/signed build/configuration, nominal thermal state, power/storage conditions and a separate trace before accepting results. The 2026-10-21 controls establish a custom hitch-ratio response despite zero exported frame counts; `XCTHitchMetric(application:)` remains nonresponsive and must not certify this setup. Frame count is not used in hitch milliseconds / animation seconds. Keep its diagnostic failure visible separately.

Export only the selected test's metrics from each result bundle, then run:

```sh
python3 PerformanceTests/hitch_quality.py normal-metrics.json delayed-metrics.json reader-metrics.json
```

This numerical checker requires finite, nonnegative measurements with consistent units/sample counts and a hitch ratio matching hitch milliseconds divided by interval seconds. Every delayed-control sample must exceed 10 ms/s and every normal-control sample; every reader sample must be strictly below 5 ms/s. That control-separation check is an experiment sanity check, not an assertion that injected blocking milliseconds equal hitch time. The tool does not independently inspect device conditions, binary identity or traces; those prerequisites require the accompanying run evidence. It does not repair SDK counters, set a relative regression tolerance or certify older multi-interval exports.

For a frame-counter investigation, explicitly select `testCustomSignpostAlone` or `testSystemScrollSignposts` instead of the regular measurement method. Both restore the same fixture and perform the same three swipes, recording two iterations after warm-up. The first removes the app-level hitch collector; the second uses only Apple's built-in scrolling/deceleration metric. These are diagnostic controls, not additional baseline samples. The regular five-sample test and benchmark app are unchanged.

`testStableProcessSignposts` launches before entering `measure` and retains that process across iterations. `testSingleIntervalSignposts` also retains the process and emits only one scroll interval per iteration. These controls check process-lifetime and repeated-interval effects. Their scroll position advances between iterations, so they are counter diagnostics rather than repeatable content baselines.

## Known-stall calibration

`testBenchmarkStallControl` opts in with `--benchmark-stall`. The benchmark schedules one synchronous 200 ms main-thread block 200 ms into each active `ReaderScroll` interval, skipping it if that scroll has already ended. `InjectedMainThreadStall` duration signposts and the `benchmark.stallState` overlay report completed blocks and total measured blocking milliseconds. The test requires three blocks totaling at least 600 ms. The normal fixture test requires zero blocks. The injector is entirely in `PerformanceTests/Host`; the production app does not compile it.

Run `testCalibrationNormal` and `testCalibrationStalled` separately using the same normalized signed products and device conditions. Each records three iterations after a discarded warm-up, restores the fixture/process/database before every pass, and measures the same three swipes with the app and custom animation metrics. Only the stall launch argument differs. Explicit attachments record the actual stall count/duration, thermal state before and after scrolling, Low Power Mode, refresh rate, and OS for every pass. Keep these runs untraced; a diagnostic Instruments capture is separate.

`testStableProcessStallCalibration` launches the stalled fixture before constructing the app-wide metric and keeps the process alive for two recorded iterations plus warm-up. Content position advances, so this checks collector/process lifetime rather than providing matched baseline samples. `testStalledReaderScrollWithProfiler` uses the same profiling checkpoint below, with stall injection enabled and its count/duration asserted after scrolling.

This tests whether the collectors respond to a known slowdown. It does not repair the frame counter, set a performance gate, or establish normal reader smoothness. Keep raw zero counts and calibrate each metric independently before trusting it. The timer-based scrolling stall was unreliable on the later image run; use the rendering-dependent calibration above for the validated quality workflow.

## Controlled foreground-sync contention

`--benchmark-sync-fixture` prepares a fresh file-backed `DatabasePool` through production `AppDatabase.make(at:)`, with 2,000 background articles plus the text reader. Each background article has a fixed 8KiB ASCII body, identity, URL, and timestamp. A production `ArticleListViewModel` / `ArticleService` / `GRDBArticleStore` observation stays active in both modes. The benchmark uses an isolated temporary directory in its own app container; no user library or CloudKit account is accessed.

Adding `--benchmark-sync` applies three prepared batches of 100 distinct record updates, one scheduled 200 ms into each active scroll. The local replay performs the same `ArticleRecord(record:)` conversion and `saveRecord` calls used by the private incoming-record handler, including CloudKit system-field encoding and normal GRDB observation/materialization. It does not invoke `SyncEngineManager`, fetch/send records, or reproduce server delivery, sync-state orchestration, or SDK startup. Updated articles retain their sort positions, use fixed 8KiB replacement bodies, and exclude the displayed reader article.

`testForegroundSyncBaselineFixture` and `testForegroundSyncContentionFixture` verify readiness, actual movement, and observer/persistence completion. The sync status fields are `phase|libraryCount|completedBatches|appliedRecords|persistedRecords|batchesStartedDuringScroll|recordsAppliedWithinScroll|observedBatchMarkers`. A record counts as overlapping only when its conversion begins and its save returns inside an active scroll interval. Every batch must overlap its swipe. `SyncApplyBatch` signposts expose the full asynchronous apply duration; a batch may extend beyond the scroll.

Persistence verification starts after each scroll's idle transition and awaits any unfinished batch. The driver waits for verification and the production observer before the next swipe. These checks and any workload tail are outside the custom `ReaderScroll` interval; they are inside the app-wide measurement's broader bounds. Inspect overlap counts and trace boundaries before interpreting contention results. Progress reporting avoids publishing a view update for every applied record.

Select `testForegroundSyncBaseline` or `testForegroundSyncContention` for separate untraced runs using the same signed products. Both record three iterations after warm-up and recreate the entire database/process/fixture on every pass. `testForegroundSyncKnownStall` calibrates this larger fixture with the existing stall injector and sync application disabled, recording two iterations after warm-up. Conditions attachments include sync counts, overlap evidence, stall counts/durations, thermal state before/after, Low Power Mode, refresh rate, and OS.

Select `testForegroundSyncBaselineWithProfiler` or `testForegroundSyncWithProfiler` for separate traces using the checkpoint below. Persistence and observer verification share one 20-second post-scroll completion budget in profiling, ordinary fixtures and untraced runs. The temporary wider diagnostic budget was removed after the lean capture completed under healthy conditions. Confirm all required workload assertions, closed scroll/batch intervals, their overlap, and frame activity. The frame-count and app-wide collector limitations remain subject to calibration; there is no new performance gate.

## Image-heavy scrolling

Prepare the local photo assets before building:

```sh
python3 PerformanceTests/fetch_images.py
```

The manifest in `Host/ImageFixtureManifest.json` pins twenty-four original photographs from Matthew Haughey's [travelogue](https://a.wholelottanothing.org/travelogue-a-week-in/), with URLs, dimensions, byte sizes and SHA-256 hashes. The fetcher reuses verified files and rejects changed payloads before replacing an asset. Photos remain local ignored inputs under `Host/BenchmarkImages`; retain exact bytes with measurement artifacts. The fixture uses benchmark-owned text and spacing, rather than redistributing the article's prose or reproducing its full layout. Tests for materialization, hash rejection and offline reuse run with the Python discovery command above.

`--benchmark-image-fixture` uses the production reader/visibility/loader/decoder with a benchmark-only URLProtocol serving the pinned bytes offline. Both modes use a 64 MiB memory URLCache with no disk cache. Cold entry empties encoded responses; `--benchmark-images-warm` preloads all twenty-four encoded responses before rendering. The protocol explicitly consults URLCache. This controls byte-cache state, not HTTP revalidation, network delay, decoded-image caching, filesystem caches or OS caches. Hashing warms file reads during preparation. Initial visible images are prepared outside measurement; newly encountered images still decode normally in both modes.

The transport runs synchronously on Foundation's protocol queue, with no spawned delivery tasks or added mutable instance state. Its inherited unchecked Sendable conformance relies on Foundation's request/client lifecycle; all benchmark counters are protected by `Mutex`, and URLCache is installed before image requests start. Preparation and hashing use `@concurrent`; production isolation and actor layout are unchanged.

`testImageFixtureDisplaysDecodedPhoto` verifies visible placeholder replacement, distant unloaded placeholders and an explicit screenshot. Decoded decorative photos are absent from the accessibility Image tree, so querying that tree alone cannot prove loading. `testWarmImageFixtureUsesEncodedCache` requires real cache hits and zero file responses. `testImageScrollsOverlapResponses` verifies six gestures in each mode, actual movement, title departure, consistent per-gesture counts and image-response overlap over the full traversal. Individual gestures may have zero new responses because of production prefetch; these zeros remain in the report. Cold traversal still requires uncached work, and warm requires cached work without file responses. `testImageKnownStallFixture` validates the existing stall control with six blocks on this layout. Keep fixture screenshots outside performance measurements.

The image status fields are `mode|primedResponses|fileResponses|fileResponsesStartedDuringScroll|failures|fileBytes|cacheHits|cacheHitsDuringScroll`. `benchmark.imageScrolls` records one `fileResponses:cacheHits` delta per completed scroll. Snapshots update at idle rather than for every response; the initial overlay can be stale. `FixtureImageResponse` intervals cover fixture delivery, not decoding CPU time or presentation.

Select `testColdImageHitches` or `testWarmImageHitches` for separate untraced measurements: three recorded passes after discarded warm-up, with a fresh process/database/cache state for each pass. `testImageHitchCalibration` records two passes after warm-up with six known stalls per pass. Per-pass attachments record cache/work counts, stall counts, thermal/power/storage conditions, refresh-rate limit and OS. Visible-photo completion checks follow the measurement; each ReaderScroll ends at actual idle.

Select `testColdImagesWithProfiler`, `testWarmImagesWithProfiler` or `testStalledImagesWithProfiler` for the separate checkpoint-based capture below. Use matching signed products/collector/conditions and fresh calibration after an OS or collector change. No historical text/sync values from another OS constitute a matched image baseline.

## Separate profiling

The default `ReaderHitches` plan excludes all methods ending in `WithProfiler`, so Run All cannot wait for a manual recorder checkpoint. `ReaderProfiling` selects only those methods. Select that plan explicitly in Xcode, or pass `"-testPlan","ReaderProfiling"` when testing through the project. Changing only `-only-testing:` on the default plan does not override its exclusions. `test_test_plans.py` checks the partition against the discovered method names; keep the `WithProfiler` suffix for manual checkpoint tests.

For the prepared-products workflow above, Xcode exports both plans against the same binaries. Locate the profiling export (the numeric subdirectory is assigned by Xcode), normalize it, then use this path for the device test command instead of `ReaderHitches.xctestrun`. Select exactly one profiler method with `-only-testing:`.

```sh
hitch_profile_run="$(rg --files "$hitch_products/Tests" -g ReaderProfiling.xctestrun)"
python3 PerformanceTests/prepare_run.py "$hitch_profile_run"
(
  cd /tmp
  xcodebuildmcp device test --xctestrun-path "$hitch_profile_run" --device-id <device-udid> \
    --json '{"extraArgs":["-parallel-testing-enabled","NO","-enablePerformanceTestsDiagnostics","NO","-collect-test-diagnostics","never","-only-testing:LuegoPerformanceUITests/ReaderHitchTests/testReaderScrollWithProfiler"]}'
)
```

For diagnosis, select `testReaderScrollWithProfiler` (or the matching image/sync method). Preserve the measurement settings and signed products. After restoring the fixture the test prints `HITCH_TRACE_READY` and waits up to 120 seconds for the device Darwin notification below. Query the current benchmark app PID with `xcrun devicectl device info processes --device <device-udid>`. Attaching before fixture restoration loses the target when the test relaunches it.

Once the test is waiting, start this in terminal A from the repository root. Choose a fresh host notification name for each attempt and use that exact name in both terminals. Wait for `HOST_LISTENER_READY` before starting the recorder. The helper clears the registration's initial notification state; only a subsequent notification succeeds. `&&` prevents posting the device checkpoint after a timeout or registration failure.

```sh
python3 PerformanceTests/wait_for_recording.py <host-notification-name> --timeout 45 && \
  xcrun devicectl device notification post --device <device-udid> \
    --name com.esoxjem.Luego.performance.profiler-ready --timeout 15
```

Then run this in terminal B with the current benchmark PID. Choose a recording cap that covers the full selected workload and its completion checks; the example uses 300 seconds. After the test completes, stop recording with Control-C and allow Instruments to save. Preserve the recorder exit status and reject provider failures.

```sh
xcrun xctrace record --template 'Time Profiler' \
  --instrument 'Frame Lifetimes' --device <device-udid> \
  --attach <benchmark-app-pid> --time-limit 300s \
  --notify-tracing-started <host-notification-name> --output <reader.trace>
```

Profiling tests opt into `--benchmark-profile-signposts`, using the `PointsOfInterest` category for both scroll and sync intervals. Untraced XCTest metrics retain `Reader`. `testProfilingUsesPointsOfInterest` and the default fixture test verify the selection. The Time Profiler template includes a filtered Points of Interest collector; adding the Time Profiler instrument to another template does not include those other collectors.

The full Animation Hitches template is rejected for this contention setup: even a verified wired run times out, its Logging provider fails on stop, and device storage drops sharply across the attempt. The lean composition above completes the full sync workload and exports `coreanimation-lifetime-interval` with per-frame hitch metadata. Known-stall calibration and the completed matched comparison are recorded in the [results report](RESULTS-2026-10-17-FOREGROUND-SYNC.md#completed-traced-comparison). The first low-storage success remains diagnostic only. Export the actual CoreAnimation schema and raw `os-signpost` events; the historical legacy hitch tables may be absent. Resolve references and verify closed interval IDs, process, category, animation metadata, and frame overlap. Include late frames whose lifetimes cross an interval boundary, reporting partial overlap separately without assigning the full hitch duration to the interaction.

Check actual device free storage before recording and reject storage-pressured runs. A reader-only profiling test released without attaching Instruments logs filesystem free bytes without collecting another trace. The current experiment requires at least 2 GB of headroom before accepted comparisons. Saved traces alone do not prove that system-managed device recording files were reclaimed; verify headroom after cleanup or reboot. Preserve the failed trace and exact provider error.

Terminal A prints `RECORDING_STARTED` before posting the device checkpoint. A textual xctrace startup line is insufficient. On listener timeout, stop the attempt's test and recorder; do not manually release the checkpoint or reuse the expired listener. The host recording notification and device XCTest checkpoint are separate signals. Verify the effective connection is USB immediately before capture; a previously wired phone may later use a network tunnel. Do not mix traced samples into the untraced XCTest baseline. Verify the expected closed `ReaderScroll` intervals (three for text/sync, six for images), completed workload, and overlapping frame activity before interpreting hitches. A successful recording of an idle app only establishes profiler connectivity.

Apple API references: [XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric) and [scroll phase completion](https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:)-1k12m).
