# Controlled foreground-sync contention — 2026-10-17

The traced comparison now completes with the original 20-second completion checks. A lean Time Profiler + Frame Lifetimes capture records all three sync batches and all 300 persisted/observed updates under healthy, matching device conditions. No reported hitch frame intersects scrolling in the final baseline/sync pair. A prior pair has one frame crossing a scroll boundary, so these short captures do not establish hitch-free rendering or sustained 60 fps. Production source and actor layout are unchanged.

The earlier temperature-matched untraced samples show no detectable slowdown in their reported scrolling metrics. Broken frame counts, unresolved aggregation, and an unresponsive app-wide collector still prevent a quality gate. Traced diagnosis and untraced measurements remain separate.

## Completed traced comparison

The final pair uses `strict-profile.xctestproducts`, normalized `strict-effective.xctestrun`, the same Release app UUID `90D0784B-8D8F-3773-B2A0-3ABECCD4D353`, and Time Profiler plus the standalone Frame Lifetimes instrument. Profiling markers use the filtered `PointsOfInterest` category. No broad `os_signpost` instrument or full Animation Hitches template is added. The recorder-ready host notification precedes the device checkpoint release.

Both captures verify wired/TCP transport immediately before attachment. The iPhone 15 remains nominal before/after each pass, with Low Power Mode off and Focus enabled. Baseline free space is 27,152,625,664 → 27,124,961,280 bytes; sync is 27,148,644,352 → 27,081,363,456 bytes. Thermal state is sampled at the boundaries, not continuously. Each mode restores the process, database, fixture and position; each performs three real fast swipes.

| Final trace / scroll | Scroll duration, s | Frame-lifetime starts | Reported hitch frames intersecting scroll | Whole sync batch, s | Batch overlap with scroll, s |
| --- | --- | --- | --- | --- | --- |
| Baseline 1 | 2.551846 | 149 | None | — | — |
| Baseline 2 | 2.529167 | 148 | None | — | — |
| Baseline 3 | 2.569166 | 150 | None | — | — |
| Sync 1 | 2.536004 | 148 | None | 6.880556 | 2.326102 |
| Sync 2 | 2.537696 | 148 | None | 6.424646 | 2.330329 |
| Sync 3 | 2.529380 | 148 | None | 6.947201 | 2.322104 |

All six ReaderScroll animation intervals and all three SyncApplyBatch intervals are closed, with the expected process/subsystem/category/IDs. The sync test verifies all 300 updates in storage and the production observer; 110 records have conversion and save fully inside scrolling, with every batch contributing overlap. Movement, idle completion, title departure, and zero injected stalls also pass. The shared persistence/observer budget is restored to 20 seconds; the temporary 60-second diagnostic parameter is removed.

The frame table is `coreanimation-lifetime-interval`, scoped to target-pid SINGLE. Baseline has 560 frame-lifetime rows and one reported 9.517708 ms hitch wholly after the third scroll; sync has 571 rows and no reported hitch rows. Counts establish activity, not presented-frame counts or FPS. The boundary audit checks the full lifetime of every reported hitch frame, including frames starting before an animation interval. No such frame intersects the final pair's scrolls.

An earlier complete pair with the temporary 60-second profiling budget uses the identical app and lean collector under nominal/wired conditions with over 27 GB free. It also completes 300 updates, with 103 strictly overlapping records and batches of 7.314769, 6.672700 and 7.056308 seconds. Its baseline has no reported hitch frames. Its sync trace contains a 50.261542 ms frame with a reported 16.928916 ms hitch that starts 32.051417 ms before scroll 2 and extends 18.210125 ms into it. Report this partial boundary overlap separately: the full hitch duration cannot be assigned to scrolling. Another reported 9.331833 ms hitch is wholly after scroll 3. The summary's initial start-only selection missed the partial frame; a regression first fails `0 != 1`, then passes after lifetime-intersection selection. Both boundary regressions pass. Do not discard this capture or pool the two pairs into a quality score.

### Lean collector calibration and completion diagnosis

Before the pairs, `lean-stall-ready` uses the same app/collector and verifies three closed main-thread blocks of 201.049, 201.046 and 201.116 ms inside the scrolls. A reported frame hitch overlaps each block's end: 16.636, 16.645 and 16.602 ms. This establishes qualitative sensitivity, not complete accounting of the blocking duration. The reader-only calibration does not use the sync completion deadline. Conditions remain nominal, Low Power Mode off, wired, with 27.26 → 27.23 GB free.

That recording and XCTest both exit successfully, but host export crashes in InstrumentsPlugIn symbol handling. A separate `xctrace remodel` derivative exports successfully with the same installed packages; its app event tuples exactly match the original export. The raw trace, derived trace, crash reports and export provenance are retained. No replacement device recording or source change is used to recover the data.

The failing completion checks observe genuinely unfinished work: copied failed-run databases contain only part of the batch. Removing accessibility readiness polling does not fix full-template captures, and widening their profiling deadline to 60 seconds still fails. Broad-collector controls also fail with several GB free; storage pressure alone is insufficient to explain them. The verified wired full-template capture ends with a Logging provider error and a large storage drop. The lean collector completes the original deadline twice without changing the production workload. These controls isolate the recording composition as a material source of slowdown; they do not identify an exact internal collector or prove a production deadlock. Thread State Trace in the full template remains a candidate, not a confirmed cause.

The first lean completion with only 0.5 GB free remains a rejected low-storage diagnostic. Removing both benchmark apps and rebooting is followed by a successful untraced storage probe reporting 27.3 GB free. An initial post-reboot XCTest automation timeout is an infrastructure failure; the retry succeeds after user approval. No failed or storage-pressured run enters the final pair.

Evidence lives under `build/hitches/2026-10-17/sync-trace-debug/`: `completed-comparison.json`, `completed-configuration.json`, `strict-baseline` / `strict-sync` results, traces, raw exports and conditions, `frame-boundary-audit.json`, calibration raw/remodeled traces, signed products, matching dSYM, and source manifests. All 100 production/configuration fingerprints match the earlier measurement snapshot. Run-specific findings stay in this report; the reusable procedures from `LESSONS.md` are incorporated into the hitch-testing skill on October 21, after the final iPad check passes.

After capture, successful uninstalls and a fresh app inventory confirm the benchmark and XCTest runner absent, with Luego and Luego Dev retained. Their fixture/app data is removed. Free space was last measured at 27,081,363,456 bytes before uninstall; no precise post-uninstall value or manual deletion of system-managed profiler caches is claimed. `final-phone-cleanup.json` preserves the verification.

## Experiment

Both modes prepare a fresh file-backed GRDB `DatabasePool` using production database configuration, with the fixed 8,411-word reader and 2,000 background articles containing 8,192-byte ASCII bodies. A production `ArticleListViewModel` → `ArticleService` → `GRDBArticleStore` observation remains active. The library view itself is not drawn. Each pass restores the process, database, reading position, and incoming record fixtures before measuring three fast swipes through idle completion. OS/font caches are not cleared.

The contention mode schedules one prepared batch of 100 distinct incoming records 200 ms into each active scroll, for 300 updates per pass. It replays the local `ArticleRecord(record:)` conversion and `saveRecord` sequence, including CloudKit system-field encoding, persistence, observation, and model materialization. It does not invoke `SyncEngineManager` or reproduce CloudKit delivery, fetch/send orchestration, SDK startup, shared-URL imports, or images. The reader article and background sort positions stay fixed.

The benchmark requires all 300 updates to complete, persist with updated titles, 8,192-byte bodies, and system fields, and reach the production list observer. Each batch must start during its swipe and increase the number of records whose conversion starts and save returns within an active scroll. `SyncApplyBatch` duration signposts expose the whole asynchronous batch, which can extend beyond scrolling. The driver waits for persistence verification and observer completion before the next swipe.

The custom `ReaderScroll` interval ends before verification begins. The broader application measurement also includes test interaction, verification, and any batch tail. These intervals have different denominators.

## Verification

The new contention test first failed because its sync status report was absent. The first implementation then exposed a test-driver sequencing issue: it could start the next swipe before the prior batch completed. Adding the per-scroll persistence/observation handshake made the test pass without weakening batch-overlap assertions.

The existing text fixture, large-library baseline fixture, and contention fixture all pass on both iPhone Air and iPad Pro 11-inch (M4) simulators, one booted at a time: six checks total. Four Python tooling checks pass. The signed Release device products build successfully. Production source and actor layout are unchanged by this experiment.

After restoring the profiling driver to 20 seconds, the final iPhone contention fixture passes and both frame-boundary analysis regressions pass. The final iPad repeat is interrupted by host clamshell sleep at 19:19:53 IST on October 17: the power log records 380 seconds asleep, matching the native test's jump from t=22.02 to t=400.17 while waiting for idle. An unchanged retry on October 18 is also interrupted by repeated host sleep, including a 900-second pause before interaction. Neither counts as a successful final iPad regression. Both interrupted attempts are preserved separately from the device captures.

On October 21, the Mac is awake and `testForegroundSyncContentionFixture` passes unchanged on iPad Pro 11-inch (M4), with only that simulator running and an idle-sleep assertion scoped to the test command. The test body takes 45.662 seconds (86.1 seconds for the CLI run). All three batches complete, all 300 updates persist and reach the production observer, and movement, per-swipe overlap and zero-stall assertions pass with the original 20-second checks. Harness source fingerprints still match the strict device products. `strict-ipad-awake-2026-10-21.xcresult` and its native log are retained under the investigation evidence directory. This completes the final iPad verification; no application code or timeout was changed to accommodate host sleep. The simulator result establishes harness correctness, not additional device smoothness evidence.

## Device conditions and calibration

All runs use the same normalized signed products: Xcode 26.0 (17A324), Swift 6.2, Release whole-module `-O`, and an iPhone 15 running iOS 26.6.1 (23G83), maximum refresh rate 60 Hz. The connection is verified as wired with a connected tunnel. The user enabled Focus; no accepted run logs a notification-banner interruption. Low Power Mode is off throughout. Thermal readings are taken before and after each pass, not continuously. No build or Instruments recording runs concurrently with untraced measurements.

The large-library known-stall control records two passes after warm-up. Every pass verifies three main-thread blocks totaling 603 ms. The custom metric reports hitch counts `1, 1`, ratios `6.5142, 6.4509` ms/s, total-duration exports `16.5808, 16.5720` ms, and reported FPS `55.7885, 56.0540`. Thermal state stays nominal. This confirms qualitative sensitivity to this known slowdown; injected CPU blocking time is not displayed-frame hitch time.

The frame-count exports remain zero in every run, including calibration. App-wide hitch count, ratio, and duration also stay zero under the known stalls. `validate_metrics.py` rejects all five exports for invalid frame counts. Custom duration exports remain near one swipe's duration despite three signposted swipes per pass. Keep the aggregation limits from the [earlier calibration](RESULTS-2026-10-17.md): these values cannot certify complete hitch detection or summed interaction counts/duration.

## Untraced measurements

Each mode records three samples after a discarded warm-up, recreating the process/database/fixture on every pass. Run order is baseline-1, sync-1, baseline-2, sync-2. All movement, zero-stall, persistence, observer, and per-swipe overlap assertions pass.

| Run | ReaderScroll reported FPS, recorded passes | Mean | Thermal state before/after recorded passes | Interpretation |
| --- | --- | --- | --- | --- |
| baseline-1 | 58.0025, 58.7709, 58.3932 | 58.3889 | nominal / nominal throughout | Exploratory; temperature differs from sync-1 |
| sync-1 | 57.9653, 57.9604, 58.1245 | 58.0167 | fair / fair throughout | Primary sync samples |
| baseline-2 | 58.1623, 57.7383, 57.9924 | 57.9643 | fair / fair throughout | Primary matched baseline |
| sync-2 | 58.0030, 58.1258, 58.1294 | 58.0860 | fair → serious, then serious / serious | Excluded from matched comparison |

The primary comparison uses sync-1 and baseline-2, whose sampled thermal/power conditions match. Their mean reported FPS differs by +0.0524 with sync, within their overlapping sample ranges. The first exploratory pair differs in the other direction, with a thermal mismatch. The second sync run heats to serious and cannot establish repeatability under matching conditions. Do not pool all twelve samples or interpret this as an improvement, a statistical equivalence result, or proof of 60 fps.

Every baseline and sync export has custom hitch count, ratio, and total duration `0, 0, 0`. This calibrated signal did not detect a slowdown in this bounded workload; its known limitations still apply. Primary custom duration exports are `2.5360, 2.5535, 2.5291` seconds for sync-1 and `2.5618, 2.5287, 2.5348` for baseline-2.

Every sync pass completes, persists, and observes all 300 updates. In the primary sync run, 101 updates per recorded pass meet the strict overlap check: conversion starts and save returns within active scrolling. All three batches start during scrolling and contribute overlapping records. The excluded repeat reports 97, 95, and 96 overlapping records. The remaining update work can extend outside scrolling; 300 completed updates must not be described as 300 overlapping updates.

## Initial Instruments diagnosis

After an idle cooldown, the baseline diagnostic test restores the fixture, waits at the profiling checkpoint, and completes three swipes. Animation Hitches + Time Profiler + `os_signpost` attaches to the restored app PID before scrolling. The trace saves successfully when the target exits.

| Baseline ReaderScroll start, s | Duration, s | Frame-lifetime starts within interval | Hitch duration within interval, ms |
| --- | --- | --- | --- |
| 5.1801 | 2.5618 | 149 | 16.6660 |
| 11.7529 | 2.5517 | 149 | None |
| 18.4253 | 2.5283 | 150 | 16.6660 |

All three matched animation intervals use the expected process, subsystem, category, and `isAnimation=YES` metadata. There are no sync-batch intervals in this baseline. The full trace contains 555 frame-lifetime rows and two benchmark-process hitch rows. Frame lifetimes establish activity, not presented-frame counts or FPS. Instruments labels both hitches as potentially expensive renders with 15 offscreen passes; that narrative alone does not establish a source-level cause.

The first sync diagnostic capture uses the same instrumentation but times out waiting for the first batch's persistence/observation readiness after scrolling. It captures one complete 2.5349-second scroll and an unfinished `SyncApplyBatch` starting about 207 ms into it, overlapping 2.3283 seconds of scrolling. The last published status is `working|2001|0|19|0|1|19|0`. Per-record counters are observation-ignored, so that snapshot is not a reliable final count of writes. CPU samples after scrolling include production write and observation-read stacks; running-thread samples do not diagnose the cause of the timeout or a deadlock.

A bounded fallback removes Time Profiler, keeping Animation Hitches and `os_signpost`. It also times out at the first batch's completion check. It captures one complete 2.5339-second scroll, an unfinished batch starting about 207 ms into it, and 2.3265 seconds of overlap; its last published status reports `working|2001|0|12|0|1|12|0`. Removing the extra sampler does not resolve the failure, so Time Profiler alone is not an established cause.

Both sync traces save, contain frame activity (262 and 256 lifetime rows respectively), and export no hitch rows, but neither completes the required three-batch workload. Their batch spans are truncated/open, not completed apply durations. They are excluded from a full traced baseline/sync comparison. The 20-second per-scroll completion check is retained; no timeout or assertion is relaxed to accept an incomplete workload. Thermal conditions are not independently sampled in the profiling-only test, another reason to keep these captures diagnostic.

These traced runs do not replace the untraced samples or establish a sync regression. The observed late frames in the separate baseline reinforce that a zero custom export cannot guarantee hitch-free rendering. A complete, bounded sync trace remains follow-up work; its completion failure needs focused diagnosis before a causal performance change.

## Retained evidence and limits

The initial attempt launched the XCTest runner but timed out enabling automation before opening the benchmark. Its `authorization-timeout.xcresult` is retained as an infrastructure failure and excluded. The retry and all five untraced tests complete successfully. Passing tests establish execution and workload assertions, not validity of every SDK counter.

Evidence is retained under `build/hitches/2026-10-17/foreground-sync/`: RED/GREEN and six simulator checks, known-stall and four comparison result bundles, per-pass conditions attachments, raw metrics, native logs, counter-validity failures, and `comparison.json`. `baseline-profile.xcresult` / `baseline-scroll.trace` preserve the completed diagnostic run. `sync-profile-incomplete.xcresult` / `sync-incomplete-scroll.trace` and `sync-profile-light-incomplete.xcresult` / `sync-light-scroll.trace` preserve the two rejected captures. TOCs, signpost/hitch/frame-lifetime XML, the sampled-CPU export, and trace summaries retain the diagnostic evidence. Normalized `reader-sync.xctestproducts`, the effective configuration, matching app dSYM, measurement-time production/harness source snapshots and hashes preserve reproducibility. The app executable's Mach-O UUID is `9E218B78-1B58-3479-B8A3-8F15F2D4B994`; `configuration.json` records the measurement-time revision and fixture parameters. Later documentation changes have separate final fingerprints.

This experiment covers local incoming-record application and production observation while reading a text article. It cannot rule out hitches from live CloudKit orchestration, larger or differently shaped libraries, list rendering, SDK work, or images. No production optimization or actor-layout change is justified by this comparison alone.


## Completion-check investigation — controls and rejected captures

The original profiling test completes all 300 updates when its checkpoint is released without attaching Instruments. A new-build control using the original polling path reproduces the first-batch timeout. A copied database after that failure contains 46 committed updates, confirming that the failure reflects incomplete work rather than only stale overlay data.

A benchmark-only persistence notification was developed through RED/GREEN and its functional checks pass on iPhone and iPad (three checks each). Waiting on that notification removes readiness polling during writes but still times out under the full capture; its copied database has 56 updated rows. Accessibility consumes substantial sampled main-thread CPU in the earlier capture, but removing polling does not solve the failure by itself. This experiment is not an established fix.

A sampler-only control (Time Profiler, without the added `os_signpost` instrument) completes all three batches, with 300 updates verified and 103 overlapping scrolling, at nominal thermal state before/after and Low Power Mode off. It lacks frame/interval evidence and cannot replace a hitch comparison. Animation Hitches plus Time Profiler and `os_signpost` still fails. The capture script now waits for the explicit host `--notify-tracing-started` notification before posting the device XCTest checkpoint; the textual startup message is not used as a barrier. Custom rows are nevertheless missing in several captures, so collector validity remains unresolved.

One isolation run fails before the test starts: iOS cannot install the runner and reports `No space left on device` (NSPOSIXErrorDomain 28). The user then frees storage. `clean-polling` starts nominal with 10,810,966,016 available bytes and still fails under Animation Hitches + Time Profiler + `os_signpost`. With the same products and explicit recorder-ready barrier, `clean-cpu-os` starts nominal with 7,349,526,528 bytes and fails under Time Profiler + `os_signpost`; `clean-sampler`, without the added broad collector, completes all 300 updates with 105 overlapping scrolling. It starts at 7,344,332,800 bytes and ends at 7,281,668,096; thermal state changes from nominal to fair, Low Power Mode off. Storage was an installation blocker but does not fully explain the completion failure. The collector configuration changes the outcome in these controls; its internal mechanism remains unknown.

A benchmark-only filtered-category experiment follows RED/GREEN: `poi-red` fails its category assertion, then `poi-green` passes. Profiling uses `PointsOfInterest`; untraced metrics retain `Reader`. Five fixture checks pass on each simulator. Nevertheless, `poi-sync` fails the unchanged first-batch deadline; its copied database contains 56 updated rows. Its trace has 401 frame-lifetime rows and no app markers in the raw signpost export. Its TOC later shows that this composition omitted the Points of Interest collector: adding the Time Profiler instrument does not include the other collectors from that template. This attempt is invalid for an interval comparison and does not test whether the new category is captured. It still reproduces the completion timeout.

A fresh connection query after this attempt reports `localNetwork` with a TCP tunnel; IORegistry enumerates other USB peripherals without an iPhone. The old system_profiler USB data query is empty even for those peripherals and cannot establish connection state alone. USB had been confirmed earlier, but was not revalidated at each capture boundary. Current transport is another confound, not a proven cause. A USB reconnection is required before further controlled device captures. The complete traced comparison remains outstanding; no deadline, workload, or assertion has been weakened.

At the user's request, the benchmark (`com.esoxjem.Luego.performance`) and XCTest runner (`com.esoxjem.Luego.performance.uitests.xctrunner`) are uninstalled after saving the failed capture and database evidence. A fresh app inventory confirms both absent, with Luego and Luego Dev retained. Both removed app containers are inaccessible, covering their fixture database/WAL, saved state, caches, and snapshots. System-managed profiler caches are outside public devicectl file domains and were not manually cleared. Raw traces and results remain on the Mac. `phone-cleanup.json` and the uninstall/inventory records preserve verification.

New evidence and provisional lessons are retained in `build/hitches/2026-10-17/sync-trace-debug/`: `LESSONS.md`, `investigation.json`, RED/GREEN and simulator results, control/capture bundles and traces, copied benchmark databases and row-count summaries, and `device-storage-full.xcresult`. `configuration.json` identifies the earlier experiments. Storage-control app UUID: `6A914B0B-6981-34B6-A42C-38F18F49EC52`; filtered-category app UUID: `90D0784B-8D8F-3773-B2A0-3ABECCD4D353`. Normalized `poi.xctestproducts`, matching dSYM, effective configuration, and `source-poi` snapshots/hashes preserve the latest code. Only benchmark code/test instrumentation changed. Reusable skill changes are deferred until a complete comparison succeeds.

### Marker confirmation and deadline diagnostic

On resumption, Xcode labels the phone's interface USB, while CoreDevice continues to report localNetwork/TCP and IORegistry does not enumerate an iPhone, even after the user reconnects directly. Preserve that discrepancy rather than labeling subsequent captures wired. The phone also auto-locks between tests while traces are saved/analyzed; the next prepared run waits for unlock.

`poi-sampler-check` uses the Time Profiler template, whose TOC includes the filtered collector. Its raw export captures ReaderScroll animation metadata and SyncApplyBatch begin/end events for the benchmark process. The first batch completes in 13.793936 seconds. The second is open when the original 20-second post-scroll check fails; the copied database contains 155 updated rows. Post-second-scroll CPU samples contain observation refetch work on worker threads and accessibility work on the main thread; sampled running time alone does not identify a blocking cause. This is progress under profiling, not evidence of an immediate deadlock. No complete comparison is available yet.

A bounded diagnostic revises only the profiling driver's completion budget to 60 seconds per scroll, sharing that budget across the persistence signal and observer UI check. Ordinary fixtures and untraced measurements retain 20 seconds. All 300 updates, persistence, observer, movement, and per-swipe overlap assertions remain required. The failing physical-device profiling test supplies RED; GREEN requires an actually completed run. This explicitly changes the earlier fixed-20-second profiling protocol and cannot be described as an app optimization or accepted performance gate. `bounded-profile.xctestproducts`, `bounded-effective.xctestrun`, and `source-bounded` snapshots preserve that driver.

The baseline and contention functional fixtures pass with the unchanged ordinary 20-second budget on both iPhone and iPad simulators (four checks). The first 60-second profiling attempt never launches: Xcode reports the phone locked, and the fixture checkpoint expires before recording. Its canceled result bundle lacks readable metadata; retain the native log as infrastructure evidence, not a test result. The orphaned task-owned xcodebuild child is stopped. A fresh device lock-state query still reports passcodeRequired=true. The bounded profiling test has not reached GREEN, and the traced comparison is still incomplete.

### Verified wired captures and a lean frame collector

The user keeps the phone awake manually. `bounded-sampler-ready` records a verified wired/TCP connection, nominal thermal state before/after, Low Power Mode off, and 4,365,529,088 → 4,307,611,648 available bytes. All 300 updates persist and reach the observer; 75 meet strict scroll overlap. Raw PointsOfInterest begin/end events close all three ReaderScroll intervals (2.567540, 2.534499, 2.551156 seconds) and all three batches (7.419896, 10.127151, 18.133112 seconds). Although this diagnostic uses a 60-second completion budget, these batch timings do not establish that the larger budget caused success. It has no frame-pipeline evidence by itself.

`bounded-hitches-sync` adds the full Animation Hitches template with explicit Points of Interest on a verified wired connection. Its first batch completes only after roughly 50 seconds; the second misses even the 60-second diagnostic deadline. The recorder then exits 2 with `Failed to stop recording session: Data Providers emitted errors: Logging`. This recording is rejected. Inspection of the installed template identifies Thread State Trace among its collectors; this is a candidate for capture overhead, not an isolated internal cause. Template/source-reference hashes are preserved.

`lean-frame-sync` instead uses the Time Profiler template plus the public Frame Lifetimes instrument. It completes all 300 persisted/observed updates, with 91 strictly overlapping scrolling, nominal thermal state throughout, Low Power Mode off, and no recording error. The source app UUID and workload are unchanged. It is retained as a diagnostic because storage is only 574,091,264 bytes before and 505,864,192 afterward, down from 4,596,547,584 bytes before the full-template attempt. The observed storage drop is not a file-level attribution of every consumed byte.

| Lean sync scroll | Duration, s | Frame-lifetime starts | Reported frame hitches within scroll | Whole asynchronous batch, s | Batch overlap with scroll, s |
| --- | --- | --- | --- | --- | --- |
| 1 | 2.545428 | 149 | None classified | 10.302452 | 2.325098 |
| 2 | 2.545970 | 149 | None classified | 13.783560 | 2.338430 |
| 3 | 2.545544 | 148 | None classified | 26.967622 | 2.336760 |

The raw event stream has three closed ReaderScroll animation intervals and three closed SyncApplyBatch intervals. `coreanimation-lifetime-interval` is scoped to target-pid SINGLE and contains 592 rows. Its on-time frames have sentinel hitch fields with explicit on-time narratives; unknown missing fields are not converted to zero. One reported 8.965666 ms GPU Rendering hitch begins at 33.875160 seconds, after the third scroll ends at 33.29850825 seconds, so it is outside the scrolling comparison. These are collector classifications and activity rows, not presentation counts, FPS, or source-level cause. Known-stall calibration of this collector remains required before accepting zero results.

After both recordings save, the benchmark and runner are removed and a supported full device reboot is requested to stop stale profiling services and permit temporary-storage reclamation. The iPhone reappears in USB hardware enumeration, but CoreDevice still marks it unavailable. The reader-only untraced storage probe cannot select its destination and stops before the fixture checkpoint. Post-reboot headroom is unverified pending first unlock/reconnection. Both apps were removed before reboot. No system-managed cache cleanup or complete matched comparison is claimed.

At that checkpoint, accepted captures still required restored storage headroom, the same lean collector and signed products, a known-stall response, a completed large-library baseline, and all three sync batches with persistence/observer/movement/overlap checks. Those device requirements are fulfilled by the completed comparison at the top of this report, including restoration of the 20-second completion budget. Raw evidence and `LESSONS.md` remain under `build/hitches/2026-10-17/sync-trace-debug/`.
