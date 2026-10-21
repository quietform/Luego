# Image-heavy reader scrolling — 2026-10-21

The cold/warm physical-device comparison is complete. Both normal traces finish six scrolls with real image work and report no late-frame rows intersecting those scrolls. The stall-control and XCTest export limitations below prevent a sustained 60 fps claim or a performance gate. The benchmark fixture/cache contracts were developed through TDD; production image code and actor layout were not changed.

## Scenario and source

The input is a fixed selection of twenty-four inline photographs from Matthew Haughey's [travelogue](https://a.wholelottanothing.org/travelogue-a-week-in/). Their original downloaded payloads total 12,973,498 bytes. Twenty-three are 2,000 pixels wide and one is 2,048 pixels wide; portrait and landscape aspect ratios vary. `Host/ImageFixtureManifest.json` pins source URLs, byte sizes, pixel dimensions and SHA-256 hashes. The exact local photos are ignored build inputs rather than redistributed repository assets.

Short benchmark-owned paragraphs and headings place each photo in a standalone Markdown block. This measures an article-photo workload; it does not reproduce the full article's prose/layout or measure its parsing/import. The production `ReaderView`, document preparation, buffered image visibility, `ReaderImageLoader` and `ReaderImageDecoder` are compiled unchanged into the isolated benchmark app. Production downsampling remains active. The fixture excludes live networking, TLS/server behavior, CloudKit/sync, SDK startup and user-library state.

A benchmark-only URLProtocol serves the pinned photo bytes for `images.fixture.invalid` through the production loader's URLSession. Its cache lookup is explicit: this is controlled URLCache behavior, not a test of HTTP revalidation. A 64 MiB memory URLCache with no disk cache is used in both modes. This cache configuration belongs to the fixture, not the ordinary app.

Cold app entry starts with an empty encoded URLCache; rendering the initial viewport can populate it before measurement. Warm entry preloads all twenty-four encoded responses before rendering; decoded image/view state is not preloaded. Both recreate the app, in-memory database, document and scroll position on every pass. Both wait for the first visible image to replace its placeholder. Asset hashing reads all files during preparation, so filesystem/OS caches are not cold or cleared. Preparation, cache priming and the initial viewport are outside the measured interaction.

The interaction is six fast upward swipes through actual idle/deceleration completion. Each must advance content by over 100 points. The complete traversal must overlap new uncached responses in cold mode or cache responses in warm mode. Individual gestures may have zero new responses because the production reader prefetches. All per-gesture counts are retained. The title must leave the viewport; normal reading-position persistence remains active. `ReaderScroll` animation intervals end at idle; readiness checks and any image tail after idle are outside them. Application-wide metrics have broader test-driver bounds.

## Work evidence

The fixture's counters distinguish file responses, file-response starts during scrolling, failures, bytes read, encoded cache hits and cache hits during scrolling. Per-scroll deltas are sampled at idle, avoiding UI publication for every response. A stale initial overlay is not an authoritative final count. `FixtureImageResponse` signposts cover fixture response delivery; they are not decoder CPU durations. CPU/frame traces are needed to inspect decoding and displayed-frame deadlines.

## Verification and measurements

The first twelve-photo, three-gesture fixture passed iPhone checks but failed the iPad work-overlap requirement. Its diagnostic cold histories include `0:0;0:1;0:0` and `0:0;0:1;1:0` (file responses:cache hits during each gesture). Unloaded photos remained; prefetch/arrival timing, rather than dataset exhaustion, made a per-gesture miss requirement inappropriate. The revised twenty-four-photo/six-gesture fixture retains zeros, checks cumulative history against counters, and still requires actual uncached work during the cold traversal. The extra photos keep the phone traversal away from the end. No production visibility or caching behavior is changed.

Five fixture checks pass on each simulator: decoded-photo display, warm encoded-cache behavior, cold/warm work overlap, six known stalls, and the existing text-reader regression. Final iPhone verification took 210.6 s; final iPad verification passed in two groups (134.3 s and 104.8 s). Seven Python tooling tests pass. Retained RED attempts cover the missing image fixture, missing warm behavior, a primed cache bypassed by the transport, missing per-scroll history and the longer traversal. The initial decorative-image accessibility query was corrected against a real screenshot/AX snapshot; decoded decorative images are absent from the AX image tree.

## Device configuration and launch investigation

The physical device is an iPhone 15 with a 60 Hz maximum refresh rate, iOS 27.0.1 (24A446), wired USB transport and active developer services. Tools are Xcode 26.0 (17A324), xctrace 26.0 and Swift 6.2. Release products are `image-profile.xctestproducts`; the app and matching dSYM UUID is `02B59570-EB42-3891-82C4-7255E9DA23DB`. Original/effective `.xctestrun`, binaries and measurement-time source hashes are retained. The production/configuration fingerprint matches all 100 files in the prior foreground-sync snapshot.

The first launch waited for unlock. Two default-destination XCTest attempts then failed at app launch with CoreDevice error 10004, before any fixture checkpoint. Direct `devicectl` launch left the same app running. An explicit `arch=arm64` destination passed the physical decoded-photo test and the reader-only storage probe; the default had selected `arm64e`. The DeviceSupport warning remained after success, so that warning alone does not establish incompatibility. XcodeBuildMCP rejects an explicit `-destination` with prepared artifacts; physical runs therefore use native `xcodebuild test-without-building` with the fixed arm64 destination. Simulator builds/tests continue using XcodeBuildMCP. No binary/source change was needed for this launch recovery.

The reader-only probe reported normal thermal state, Low Power Mode off and 6,103,040,000 free bytes. This experiment requires at least 2 GB free before/after accepted captures, rather than treating a saved host trace as proof of sufficient device space. Focus was enabled by the user. Existing text/sync measurements on iOS 26 are not a matched baseline. There is no new performance gate.

## Untraced collector calibration

`image-calibration.xcresult` passes the workload checks: a discarded warmup and two retained passes each complete six scrolls and six injected stalls, totaling 1,206 ms of actual main-thread blocking per pass. Every pass includes uncached image responses during scrolling. Thermal state remains normal, Low Power Mode is off and free storage is 5,939,200,000 bytes.

Both app-level and ReaderScroll hitch counts/durations/ratios export zero for both retained samples. ReaderScroll frame counts are `[0, 0]`; `validate_metrics.py` exits 1. Exported ReaderScroll FPS is 58.288 / 59.476 and duration is 2.556 / 2.572 s, but these fields do not validate the missing hitch response or the aggregate of six animation intervals. These exports are preserved as invalid performance evidence. The cold XCTest run also completes one warmup plus three retained passes under the same conditions. Each pass serves 13 uncached responses total, with 10 starting during scrolling and no failures/cache hits. Its hitch fields and frame counts export zero; raw FPS values are 58.132 / 57.908 / 57.920, and exported durations are 2.563 / 2.539 / 2.555 s. The frame-count validator exits 1. These are collector exports, not a validated cold-performance baseline.

The warm XCTest run completes one warmup plus three retained passes, with 24 primed encoded responses, 13 cache responses total, 10 during scrolling, zero file reads and zero failures on every pass. Conditions match cold. Its hitch fields/frame counts also export zero and the frame validator exits 1. Raw FPS values are 58.502 / 58.091 / 57.712; exported durations are 2.530 / 2.513 / 2.530 s. The small raw FPS difference between modes is not a validated improvement.

## Instruments calibration investigation

The lean Time Profiler template plus Frame Lifetimes records successfully on this OS. `image-stall-trace` completes the test and recorder with exit 0, all six closed animation intervals and all six closed 201.05–201.10 ms stall intervals. It contains 1,014 frame-lifetime rows. No positive frame-hitch row intersects a scroll; two small GPU hitch rows (8.65 and 9.48 ms) fall between scrolls. During the first injected stall, frame lifetimes continue and are labeled on time. Main-thread blocking therefore cannot by itself establish a displayed-frame interruption in this image scenario. This run does not validate a zero-hitch conclusion or explain whether the behavior comes from collector coverage or the scrolling pipeline.

`image-stall-full` uses the full Animation Hitches template plus the Time Profiler instrument with the same signed product/workload. Test and recorder exit 0. Its `hitches` table has two late intervals of 16.624 and 16.666 ms for the benchmark process. However, its raw signpost table contains only ConditionInducer events, with no benchmark intervals. Adding the Time Profiler instrument did not bring the Points of Interest collector from the Time Profiler template. This capture cannot enter a strict comparison bounded by the six scrolls. Its update-stage table has 831 rows and a maximum duration of 20.07 ms; elapsed main-thread sleep is not equivalent to a measured 200 ms update/commit deadline miss.

The full capture left a 426 MiB host trace and reported free device bytes falling from 5,611,520,000 to 2,351,104,000 during the test. Saving took several minutes. A reader-only headroom probe after saving timed out waiting for unlock; its test process was stopped and no active recorder/test remained. The completed comparison uses the smaller collector composition with verified benchmark markers. No ordinary deadlines, production image code or actor layout have been changed.

After unlock, a successful reader-only probe reports 5,570,560,000 free bytes, so much of the temporary full-template recording data was reclaimed. This does not prove all system-managed profiler files were removed.

The existing text-stall test was then repeated without changing the signed binary: four passes each complete three stalls totaling 603 ms under normal thermal state. Both XCTest hitch collectors and the ReaderScroll frame count still export zero. This is not solely a failure of the new image fixture.

A lean text-stall trace completes with three closed scroll/stall intervals and 492 frame-lifetime rows. It reports two fully contained late frames (16.610 and 16.590 ms hitch duration), plus a partially overlapping boundary frame with 33.444 ms whole-frame hitch duration and 17.326 ms lifetime intersection. The third scroll has no positive hitch rows. The partial frame's whole hitch duration is neither assigned nor prorated to the scroll. This demonstrates qualitative late-frame reporting; it is not quantitative validation of the injected 603 ms. That trace's thermal state is fair before/after, unlike the nominal image control, so it is not a matched control comparison. A cooling pause precedes the normal image pair.

The completed normal image pair below uses nominal thermal conditions after cooling. It does not establish zero-hitch smoothness until the collector/control response is validated. A 200 ms main-thread block is verified accepted work; it is not proof that the current image scrolling path missed a presentation deadline. Apple's [render-loop explanation](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app) distinguishes main-thread update, commit and render-server deadlines.

Evidence is retained under `build/hitches/2026-10-21/images/`, including the source HTML, photo payloads, RED/GREEN logs/results, explicit fixture screenshots and investigation notes. Run-specific observations belong here; reusable skill instructions remain separate.


## Completed traced comparison

After the phone was unlocked again, `image-cold-lean` and `image-warm-lean` reinstalled and used the same saved Release products, fixed arm64 destination, Time Profiler template plus Frame Lifetimes, and recorder-start notification/checkpoint. Both tests and recorders exit 0. Both fresh connection records show wired USB and iOS 27.0.1. Thermal state is nominal before/after both, Low Power Mode is off, and free space exceeds the experiment's 2 GB minimum: cold 5,365,760,000 → 5,365,760,000 bytes; warm 5,324,800,000 → 5,283,840,000 bytes. This is one traced pass per mode, separate from the three retained untraced samples per mode.

| Evidence | Cold encoded cache at app entry | Warm encoded cache at app entry |
| --- | ---: | ---: |
| Closed ReaderScroll animation intervals | 6 | 6 |
| Combined scroll interval duration | 15.204 s | 15.295 s |
| Primed encoded responses | 0 | 24 |
| File responses, total / starting during scrolling | 13 / 10 | 0 / 0 |
| Encoded cache responses, total / during scrolling | 0 / 0 | 13 / 10 |
| Closed fixture-response intervals in trace | 10 | 10 |
| Image failures / injected stalls | 0 / 0 | 0 / 0 |
| Frame-lifetime rows in whole capture | 1,023 | 1,028 |
| Positive frame-hitch rows intersecting any scroll | 0 | 0 |

All app intervals close, with animation metadata and frame activity in every scroll. Per-gesture histories sum to the recorded counters. Cold reads 7,833,810 encoded file bytes across the complete prepared traversal; warm performs no fixture file reads. Initial viewport work is outside the interaction. Idle checks and visible-photo completion tails retain their original bounds (10 s for idle, 5 s for photo completion). The inherited generic `completionTimeout=20` log is a sync budget, not an image completion budget.

Frame selection includes any positive lifetime intersection, including boundary crossings. The cold capture has one positive frame-hitch row elsewhere in the recording: 16.626 ms, classified GPU rendering, wholly between scrolls. The warm capture has none in the whole recording. Neither capture has a positive hitch row partially crossing a scroll boundary. Frame-lifetime rows are pipeline records, not presented-frame counts or FPS. The interval-duration difference is not an optimization result or a validated cache-speed improvement.

CPU exports contain `ReaderImageDecoder.decode` / ImageIO thumbnail-creation stacks on worker threads in both modes: 486 cold and 498 warm running samples inside the scroll intervals, with none of those sampled decoder stacks on Main Thread. Both exports identify app UUID `02B59570-EB42-3891-82C4-7255E9DA23DB`, matching the saved binary/dSYM. This confirms observed decoder work executes away from the main thread in both cache states. Running samples do not establish blocked time, complete decoder duration, or a causal performance improvement.

The evidence supports a completed controlled image-work comparison and the decoder's observed execution boundary. It does not validate zero-hitch smoothness: the image stall control did not produce a reliable frame-hitch response, the separate text control is only qualitative, and XCTest's frame counts remain zero. No gate or sustained 60 fps conclusion is adopted. There is no matched pre-change image baseline or production optimization in this run.

## Artifacts and cleanup

The evidence root is `build/hitches/2026-10-21/images/`. `image-comparison-summary.json` records both modes' conditions, interval closure, image counters and frame selection; `image-comparison-cpu-summary.json` records sampled decoder stacks and binary identities. The corresponding `.xcresult`, raw `.trace`, TOC/signpost/frame/CPU exports, original/effective `.xctestrun`, signed products, matching dSYM, source snapshots/hashes, photo bytes and RED/GREEN evidence are retained. The earlier `image-cold-trace` attempt timed out waiting for unlock before its fixture checkpoint; no recorder started, and it remains excluded.

After the final pair, supported `devicectl` uninstall commands removed the isolated benchmark app and XCTest runner. A fresh `final-apps-after-cleanup.json` verifies both absent and ordinary Luego/Luego Dev retained. No task-owned test or recorder remains. App removal clears its containers; it does not prove removal of system-managed profiler files. Last measured free device space before cleanup was 5,283,840,000 bytes.

All 100 production/configuration fingerprints and all six frozen measurement-source fingerprints still match. Five fixture checks on each iPhone/iPad simulator and seven Python tooling tests pass; `git diff --check` passes. The run-specific findings remain in this report and the evidence notes.
