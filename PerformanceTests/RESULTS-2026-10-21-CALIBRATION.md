# Hitch collector calibration — 2026-10-21

The performance objective is now a verified hitch time ratio below **5 ms/s**, replacing the earlier 60 fps objective. This is the good-experience band in Apple's [XCTest guidance](https://developer.apple.com/videos/play/wwdc2020/10077/) and [render-loop talk](https://developer.apple.com/videos/play/tech-talks/10855/). The current [Organizer documentation](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app) describes a different, newer app-wide metric and uses up to 10 ms/s as good; those classifications are not substituted for the XCTest target.

The prepared-text reader passes this target in six retained single-scroll samples across two untraced runs: every custom `ReaderScroll` ratio is **0 ms/s**. A delayed-draw positive control produces **60.458–60.551 ms/s**, and a separate Instruments capture independently confirms the corresponding late frames. This validates the custom hitch measurement for the tested scenario. XCTest's frame-count field and app-wide hitch collector remain unusable in this environment; neither supplies the quality decision.

## Existing evidence and hypotheses

The [original investigation](RESULTS-2026-10-16.md) found zero frame counts in native XCTest console output, legacy ActionTestSummary and modern metrics JSON. The loss occurs upstream of our JSON parser. Custom-only, built-in scrolling, stable-process and single-interval controls all retained zero frame counts. The installed XCTest header still documents frame count as an animation metric; it does not document zero as an unavailable sentinel. Preserve the field as unusable rather than synthesizing a replacement from FPS or trace rows.

The [image run](RESULTS-2026-10-21-IMAGES.md) verified main-thread blocks, but did not reliably observe late frames during image scrolling. A block's duration is not a valid hitch numerator. The next controlled experiment uses an explicit display-link-driven redraw, with a benchmark-only delayed draw, to distinguish a collector failure from an ineffective scrolling positive control. Draw callback counts establish workload execution only; they are not presented-frame counts.

The connected device reports wired transport and iOS 27.0.1. Only Xcode 26.0 is installed. Apple's [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) require macOS 26.6 or later; the existing test environment reports macOS 26.5.2. No toolchain or host OS update has been performed, and no exact collector defect is confirmed by these version differences.

Evidence and RED/GREEN logs are retained in `build/hitches/2026-10-21/collector-calibration/`. Production reader code and actor layout are unchanged.

## Calibration fixture and TDD

The new opt-in `--benchmark-animation-calibration` screen draws a moving bar using a CADisplayLink and UIView drawing. Each run lasts three seconds, with one `CalibrationAnimation` animation signpost spanning the draws through the following display-link callback. `--benchmark-stall` delays exactly one draw by a synchronous 200 ms sleep after 0.8 seconds. A main-thread precondition and `InjectedDrawStall` signpost identify the delayed work. The completion report contains draw callbacks, completed stalls, actual blocking milliseconds, and elapsed seconds. These callbacks are workload evidence, not presented-frame counts.

The normal fixture test first failed because `calibration.start` was absent, then passed after the screen was implemented. The delayed-draw test then failed with actual stall count zero versus expected one; after implementing the delayed draw, both fixture checks and the existing reader fixture passed on each simulator. Results: `fixture-red.xcresult`, `fixture-green.xcresult`, `delay-red.xcresult`, `delay-green.xcresult` (3/3), and `ipad-green.xcresult` (3/3). Seven existing Python tooling tests and `git diff --check` pass. Both simulators are shut down.

New device diagnostics record one animation interval per iteration, with three retained samples after warmup, separate normal/delayed modes, app-level and custom signpost collectors, and per-pass thermal/storage/power conditions. Separate profiler tests use the existing recorder-ready notification protocol. `testSingleReaderIntervalHitches` restores the reader before each pass and measures one complete swipe, removing repeated-interval aggregation ambiguity for this reader check. All physical methods used below pass.

## Prepared device run

The Release build succeeds. Saved products: `calibration.xctestproducts`; app UUID `1DDBA08A-DA00-3040-9F8F-77AB6CA7902C`, with matching dSYM in `device-derived/Build/Products/Release-iphoneos/`. The original and normalized `.xctestrun` are retained as `original.xctestrun` and `effective.xctestrun`. Normalization removes exported checker injections and disables checker/automatic-attachment settings using the existing tested transformation. Seven measurement-source fingerprints and all 100 prior production/configuration fingerprints match.

After the user unlocked the phone and confirmed USB/Focus readiness, all accepted runs used wired transport, the same saved signed products and normalized configuration, iPhone 15 / iOS 27.0.1 (24A446), Xcode 26.0 (17A324), and macOS 26.5.2 (25F84). Thermal state was nominal before/after every reported pass, Low Power Mode was off, and free storage remained 4.83–4.92 GB. These are endpoint observations, not continuous thermal sampling. The phone needed no additional unlock or automation prompt during this comparison.

## Untraced calibration

Both controls retain three samples after one discarded warmup, with one three-second animation per sample. They use the same process and reset the animation before each pass. Only the stall launch argument differs. All control assertions pass.

| Export / evidence | Normal | Delayed draw |
| --- | --- | --- |
| Completed draw callbacks per pass | 181 | 170 |
| Verified synchronous stalls per pass | 0 | 1, approximately 201 ms |
| Custom hitch count | 0, 0, 0 | 1, 1, 1 |
| Custom hitch duration, ms | 0, 0, 0 | 183.050250, 183.325999, 183.325999 |
| Custom interval duration, s | 3.028293, 3.027738, 3.027880 | 3.027729, 3.027892, 3.027649 |
| Custom hitch time ratio, ms/s | 0, 0, 0 | 60.457928, 60.545753, 60.550607 |
| Exported frame count | 0, 0, 0 | 0, 0, 0 |
| App-wide hitch count / duration / ratio | All zero | All zero |

The custom ratios agree with measured hitch milliseconds divided by animation seconds. The approximately 201 ms of injected blocking is not the numerator; XCTest measures approximately 183 ms of actual hitch time. App-side elapsed durations agree with the single exported intervals. This establishes a repeatable custom-collector response while independently demonstrating that its frame-count field and the separate app-wide collector cannot be trusted here.

## Independent trace calibration

The lean Time Profiler template plus Frame Lifetimes attaches after fixture readiness. Its actual recorder-start notification releases the device checkpoint. Both normal and delayed tests and recorders exit zero; all three animation intervals in each capture close with `isAnimation=YES`, frame activity and full workload completion. The delayed capture also contains three closed `InjectedDrawStall` intervals on the main thread, nested within the animations.

The delayed trace contains one wholly contained late frame per animation: **183.042375, 183.069708 and 183.054125 ms** of reported hitch duration, over **3.027415, 3.027882 and 3.027739 s**. These imply approximately **60.46 ms/s** and closely agree with the separate untraced XCTest control. They are not substitutions for those samples or a guarantee of collector precision for every kind of hitch. The actual traced blocks last 200.20–201.10 ms. The frame table labels these late frames `GPU Rendering`; that label alone does not establish a GPU bottleneck when the experiment deliberately delays main-thread drawing.

The delayed trace's CPU export identifies app UUID `1DDBA08A-DA00-3040-9F8F-77AB6CA7902C`, matching the saved signed product and dSYM.

The normal trace has no late frames intersecting its first two animation intervals. Its third interval intersects one frame with **9.048333 ms** of whole-frame hitch time; that frame crosses the animation's end. Its full hitch is neither assigned nor prorated to the interval, so an exact third-interval trace ratio is left unavailable. This small boundary event is retained as variability, rather than claiming the normal trace is entirely hitch-free. Selection uses any positive frame-lifetime intersection, including boundary crossings.

The stronger control resolves the practical calibration failure: blocking an actual draw causes a repeatable measured late frame. The old timer-based sleep during scrolling did not reliably do so. This experiment does not establish the exact internal scrolling mechanism responsible for that difference, nor the internal cause of Apple's zero counters.

## Reader quality check

`reader-single` and `reader-repeat` each recreate the app, in-memory fixture, portrait orientation and top position before every pass, including warmup. Each retained sample measures one fast upward swipe through the real idle transition and verifies movement over 100 points and zero injected stalls. Preparation and restoration are outside measurement. This is the first swipe of the prepared text fixture; it excludes image loading, sync contention, article opening and whole-app behavior.

| Untraced run | Interval durations, s | Hitch duration / count | Hitch ratios, ms/s |
| --- | --- | --- | --- |
| reader-single | 2.545818, 2.551048, 2.569082 | All zero | 0, 0, 0 |
| reader-repeat | 2.536305, 2.535486, 2.551345 | All zero | 0, 0, 0 |

All six retained ratios are strictly below 5 ms/s. The repeat supports repeatability under the recorded conditions; it does not establish a relative regression tolerance or a universal zero-hitch guarantee. There is no matched pre-change performance baseline or production optimization.

A separate `reader-trace` passes the existing three-swipe profiling workload, with three closed intervals lasting **2.544116, 2.569130 and 2.552402 s** and frame activity in each. No reported late frame intersects any interval, and none appears elsewhere in that capture. It contains 516 frame-lifetime rows overall; these are pipeline records, not a presented-frame count. The trace advances through three scroll positions, whereas each untraced sample resets to the first position; the traced runs are supporting diagnosis rather than interchangeable measurements.

## Numerical checker and metric policy

`hitch_quality.py` assesses the custom calibration and reader exports. TDD first demonstrated rejection gaps for a nonresponding control, reader samples at/above 5 ms/s, missing/invalid/inconsistent metric values, and the CLI exit status. The implementation now rejects those cases, checks units and `hitchMilliseconds / intervalSeconds`, requires every delayed-control sample to exceed 10 ms/s and every normal-control sample, and requires every reader sample to be strictly below 5 ms/s. The control threshold tests clear separation; it does not equate the delay with measured hitch time. Both actual reader exports pass.

Five new checker tests plus seven existing tooling tests pass (12 total). Physical conditions, test completion, signed-build identity and trace validity are reviewed separately; the numerical checker does not certify them from metric JSON alone. `validate_metrics.py` remains a separate frame-count diagnostic and still rejects these zero-count exports. Frame count is unnecessary for the hitch-time ratio formula, so its known failure does not invalidate an independently calibrated custom hitch ratio. Neither the frame counter nor `XCTHitchMetric(application:)` has been repaired or silently replaced.

## Retention and cleanup

The evidence root retains original/raw and copied `.xcresult` bundles, exported metrics/conditions, raw traces, frame/signpost tables, trace summaries, command/configuration/connection records, original/effective `.xctestrun`, signed products/dSYM, source fingerprints and RED/GREEN logs. `animation-normal`, `animation-delayed`, `reader-single`, `reader-repeat`, `animation-normal-trace`, `animation-delayed-trace` and `reader-trace` identify the accepted runs. `NOTES.md` records the investigation sequence.

After the final untraced repeat, supported uninstall commands removed the isolated benchmark and XCTest runner. A fresh `final-apps-after-cleanup.json` verifies both absent and ordinary Luego/Luego Dev retained. System-managed profiler caches are not claimed removed. Last observed free space before cleanup was 4,874,240,000 bytes. No production source or actor layout changes were made for this investigation, and no toolchain/host update was performed.

Final verification preserves all seven measurement-source and all 100 production/configuration fingerprints. The real reader target check exits zero; supplying the actual normal-control export as the positive control exits one; the original frame-count diagnostic still exits one. `git diff --check` passes. The new numeric checker and its tests have separate tooling fingerprints because they were authored after the device build.

Reusable lessons have been promoted to the [hitch-testing skill](../.agents/skills/hitch-testing/SKILL.md): rendering-dependent positive controls, independent validation of metric fields, unambiguous sample intervals, numerical checks separate from capture validity, and cautious frame-boundary and causal attribution. Measured values, experimental thresholds, device/toolchain details, and artifact identities remain in this report and its evidence files.
