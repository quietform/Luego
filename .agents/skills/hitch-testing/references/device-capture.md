# Physical-device capture and export

Use this reference for Instruments attachment, missing markers, profiling-induced timeouts, or trace-export failures. The commands and schema examples were exercised with Xcode 26. Check installed `xctrace`/`devicectl` help and the actual trace TOC when adapting them.

## Attach after fixture restoration

A UI test may relaunch its app before every pass. Attaching before restoration can record the wrong process or lose the target. Keep a bounded checkpoint in an opt-in profiling test, outside the untraced measurement:

1. Restore and assert the fixture, position and readiness; signal that the test is waiting.
2. Query the current app PID and attach Instruments.
3. Await the recorder's actual readiness signal on the Mac, then release the separate device checkpoint.
4. Perform the interaction and assert full workload completion before ending the run.

Use `xctrace record --notify-tracing-started <host-notification-name>` where supported. Register the host notification before launching the recorder and clear its initial state before waiting for the next notification. A textual “Starting recording” line is not a reliable barrier. The recorder notification is on the Mac; the XCTest checkpoint is on the device. For a Darwin checkpoint, post the latter with:

```sh
xcrun devicectl device notification post --device <device-udid> \
  --name <device-checkpoint-name>
```

A runnable capture recipe must include both the recorder's notification flag and the listener setup, using the same fresh notification name for that attempt. Have the listener acknowledge registration before launching xctrace, bound its wait, and release the device checkpoint only after successful receipt. On timeout or registration failure, stop the attempt's owned processes rather than bypassing the barrier. If extracting a helper, test it with real host notifications: registration alone must not succeed, a subsequent post must succeed, and no post must fail without releasing the checkpoint. Keep device capture validation separate from these host-only tests.

On the tested SDK, the UI test used `import notify`, `notify_register_dispatch`, and `notify_cancel`; compare the registration result with `UInt32(NOTIFY_STATUS_OK)`. Choose a recording cap that covers the bounded interaction and any required workload tail. A cap that truncates required work, or a checkpoint expiry, leaves a failed/partial attempt rather than a completed comparison.

## Choose and verify the collectors

Templates compose several instruments. Adding the Time Profiler **instrument** to another template does not add the other collectors from the Time Profiler **template**. Inspect the composed TOC and actual rows rather than inferring coverage from an instrument name.

The standard Points of Interest collector can filter to category `PointsOfInterest`, excluding custom categories. When markers are missing, inspect the effective filter and raw `os-signpost` rows. An opt-in benchmark profiling category can match the filtered collector while preserving the category used by untraced XCTest metrics. Verify both modes with fixture tests. A broad `os_signpost` collector may capture custom categories, but can add substantial overhead; do not add it automatically.

For a smaller capture when a full template perturbs the workload, one tested composition is:

```sh
xcrun xctrace record --template 'Time Profiler' \
  --instrument 'Frame Lifetimes' --device <device-udid> \
  --attach <current-app-pid> --time-limit <bounded-duration> \
  --notify-tracing-started <host-notification-name> --output <capture.trace>
```

This composition can supply CPU samples, filtered points of interest and `coreanimation-lifetime-interval` frame metadata. Calibrate the actual composition with a known-stall control before trusting zero hitches. Keep matching collector settings for baseline and contention captures. Use fuller rendering/SwiftUI templates when their additional evidence is needed and their overhead is acceptable; the lean composition is not a universal replacement.

## When profiling changes completion

First release the same profiling checkpoint without attaching Instruments. If that completes but recording does not, hold the signed products, fixture, connection, storage and device conditions fixed while isolating collector additions. A CPU-only success without frame/interval data is an isolation control, not a hitch comparison. Removing accessibility polling can test one source of perturbation, but a successful notification handshake alone does not prove that the actual batch completed.

Keep required persistence, observer and overlap assertions. Inspect durable fixture state or closed work intervals to distinguish slow/incomplete work from stale UI reporting. Running-thread CPU samples do not establish a deadlock or explain a thread's blocked time. Report a whole asynchronous batch's elapsed duration separately from the scrolling interval.

If a wider profiling-only timeout is needed to observe progress, label it a diagnostic protocol change and preserve the original-budget results. Do not relax ordinary/untraced checks or accept unfinished work. Restore the original budget when a less intrusive capture completes it. A successful lean capture identifies a viable measurement setup; without a controlled add-back it does not establish which internal collector caused the full template's slowdown.

## Preflight and distinguish infrastructure failures

| Boundary | Check |
| --- | --- |
| Connection | Query fresh CoreDevice details immediately before each capture; inspect effective transport, not only an earlier USB confirmation or Xcode label. A TCP tunnel alone does not distinguish wired from network transport. Corroborate conflicting reports with hardware enumeration; one empty inventory is insufficient proof. |
| Storage | Record actual device free bytes before/after and define sufficient headroom for the experiment. Installation errors and Logging-provider failures may accompany storage pressure. Reject storage-pressured comparisons; a saved host trace does not prove device recording files were reclaimed. |
| Authorization | Device discovery, XCTest automation approval and Instruments attachment are separate capabilities. After reboot, allow for first passcode unlock and renewed automation approval. Use actual launch/interaction state rather than warnings alone to decide whether user action is needed. |
| Awake state | XCTest's keep-awake behavior ends with the test; trace saving/export can let the phone lock before the next capture. Keep the Mac awake too. Correlate long native-log gaps with host sleep/wake events; an idle-sleep assertion does not prevent lid-close sleep. |

Prepare signed products before requesting unlock, and obtain user input for an actual OS authorization or awake-state requirement. A short sampler probe can establish attachment; it is not interaction evidence. Avoid repeated unchanged failed attempts. After a bounded probe and applicable fallback, retain the exact error and resolve the failing boundary before another capture.

If a checkpoint/launcher times out, verify that its task-owned test and recorder children have stopped. Terminating a wrapper can leave an `xcodebuild` child waiting to start a stale test when the device unlocks. Stop only the identified processes belonging to this attempt.

## Validate the captured interaction

Read recorder exit status and provider errors before analyzing the `.trace`. A nonzero recording exit with a Logging/data-provider failure is rejected even if a bundle exists. Missing SwiftUI data may still leave usable CPU/frame evidence; disclose that limit. Unsymbolicated system stacks limit attribution even when the app dSYM matches.

Export the TOC first, then only relevant schemas that are actually present:

```sh
xcrun xctrace export --input <capture.trace> --toc --output <toc.xml>
xcrun xctrace export --input <capture.trace> \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="coreanimation-lifetime-interval"]' \
  --output <frames.xml>
```

Full templates may expose `hitches`, `hitches-frame-lifetimes`, update/render/GPU tables and `time-profile`; a lean capture may expose a different frame schema. Missing legacy tables do not mean no frames. Declarations alone do not prove captured data. Serialize exports from one trace, or use a supported combined XPath; concurrent exports can contend on the same trace.

Resolve XML `id`/`ref` values before interpreting rows. If preassembled interval tables are absent, pair raw signpost begin/end events using process, subsystem, category, name and interval ID. Require the expected closed animation/work intervals and animation metadata. Open or unmatched spans are incomplete, not completed durations. Verify frame activity overlaps the intended interaction and the test's entire required workload actually completed.

Inspect field semantics: CoreAnimation can use sentinel hitch-duration fields for explicitly on-time frames. Accept that classification only with the corresponding status/narrative; unknown missing fields are unavailable evidence, not numeric zero. Frame-lifetime rows establish pipeline activity, not presented-frame counts or FPS.

Select late frames by any positive lifetime intersection with the interaction: `frameStart < intervalEnd && frameEnd > intervalStart`. Selecting only frame starts inside the interval misses a frame crossing its start. Report fully contained frames, partial boundary overlaps and wholly outside frames separately. Do not assign or prorate the full frame's hitch duration to the intersecting portion; leave an exact interval ratio unavailable when boundary attribution is unresolved. Preserve boundary regressions in analysis tooling when automating this selection.

A collector label such as `GPU Rendering` does not by itself identify the cause. Correlate pipeline stages, marker threads and nesting, and known injected work before assigning responsibility; a delayed main-thread draw can appear under that label.

## Recover a host export failure

Distinguish successful recording followed by exporter failure from a failed recording. For the former, preserve the raw trace and crash/error log, then try a separate offline derivative using the installed modelers:

```sh
xcrun xctrace remodel --input <raw.trace> --output <remodeled.trace>
```

Keep raw and derived traces distinct. Inspect the derived TOC and export again; verify target identity, matching app event timestamps/IDs and interval closure against the original raw export where available. Record which trace supplied each export and the modeler/toolchain provenance. This can recover analysis without another device run; it does not repair failed acquisition or validate missing workload data. If recovery still fails, retain the limit rather than repeatedly exporting or claiming zero hitches.

## Cleanup and retention

Within requested cleanup scope, save results/traces, stop the attempt's test/record processes, remove the isolated benchmark app and runner, and verify absence with a fresh app inventory. Keep unrelated apps/data intact. App removal covers its own containers; it does not establish removal of system-managed profiler files. Do not delete unsupported device paths or personal data to recover space. If recovery includes a supported reboot, verify actual headroom afterward and handle first unlock/automation approval before resuming.

Retain `.xcresult`, raw/derived traces, explicit conditions, exact collector settings, original/effective runner configuration, matching binaries/dSYM, and measurement-time source fingerprints. Keep traced diagnosis separate from untraced samples. Different collector classifications or capture conditions do not establish an app improvement; preserve variability, rejected attempts and evidence limits in the results report.

Remove generated Python bytecode from the source change and ignore `__pycache__/` and `*.py[cod]` when adding host-side tooling. Keep reusable scripts and tests under version control; retain measurement evidence separately according to the repository's artifact policy.
