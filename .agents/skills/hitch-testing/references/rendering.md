# Diagnose the delayed frame

## Distinguish pipeline stages

The pipeline is event handling → app UI update/commit → render-server preparation → GPU execution → presentation. Successive frames overlap. Frame lifetime and the interval between presented frames are different quantities: multiple refresh intervals of latency do not alone imply hitching.

At 60 Hz a refresh interval is about 16.7 ms; at 120 Hz it is about 8.3 ms. Those are not exclusive budgets for application code. Refresh rates and buffering modes can change. Use the trace's expected presentation/commit timing rather than hardcoding vsync arithmetic. A hitch measures lateness beyond the expected deadline; a hang concerns responsiveness and may overlap with a commit hitch. Average FPS alone does not establish smooth frame pacing.

Source: [render-loop overview](https://developer.apple.com/videos/play/tech-talks/10855/).

| Evidence in the late frame | Investigation |
| --- | --- |
| App misses its commit deadline | Main-thread stacks, synchronous I/O/decoding, redundant layout, view reconstruction, state publication |
| Commit finishes on time but rendering finishes late | Render-server CPU work, GPU execution, compositing and offscreen passes |
| Both are expensive | Treat each contribution separately and remeasure after a focused change |

Select the hitch's relevant frame work, including preparation before the visible stall, rather than sampling only after the deadline. Correlate Hitches, frame lifetimes, commits, renders, GPU, and Time Profiler tracks where available. Main-thread idleness is not proof that the rendering work is cheap.

When exporting frame-pipeline tables, matching swap IDs help connect a hitch with its app update, render, and GPU work. A tool's "potentially expensive" narrative suggests an investigation; use those intervals and CPU stacks to substantiate the cause. Frame-lifetime row counts establish captured pipeline activity, not the number of frames presented to the user.

Sources: [commit-phase diagnosis](https://developer.apple.com/videos/play/tech-talks/10856/), [render-phase diagnosis](https://developer.apple.com/videos/play/tech-talks/10857/).

## SwiftUI work

The Instruments 26 SwiftUI template combines SwiftUI updates, Time Profiler, and Hangs/Hitches. Long View Body Updates highlight calculations over 500 microseconds in orange and over 1,000 microseconds in red. These durations are clues, not hitch verdicts: correlate them with presentation deadlines.

Investigate both individual update cost and unnecessary update frequency. Use the Cause & Effect Graph to follow changing state, geometry, scroll position, collections, and environment values into affected views. When CPU activity occurs outside SwiftUI Update Groups, investigate other app work; do not assume a SwiftUI refactor is the answer. Reduce dependencies or cache repeated work only when evidence supports that path.

Sources: [SwiftUI Instruments session](https://developer.apple.com/videos/play/wwdc2025/306/), [SwiftUI performance documentation](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

## Images and rendering

Distinguish download latency, decoding, resizing, layout on image arrival, and final compositing. GPU-backed content scaling can avoid CPU redraws, but does not eliminate oversized decoding, memory pressure, or GPU cost. Inspect image pixel dimensions, decoding execution, and retained decoded memory. Consider target-size ImageIO downsampling and bounded retention when those costs are measured. Recheck image sharpness, placeholder dimensions, and scroll stability after a change.

On a measured render hitch, inspect actual layer/render costs. Dynamic shadows and custom masks can introduce offscreen passes. Where the shape is known, a suitable `shadowPath` or a simpler built-in layer property may remove work. Do not add rasterization, `.drawingGroup()`, or `.compositingGroup()` as a generic fix; they can change memory, rendering work, and visual output. Offscreen count is a diagnostic clue rather than an independent failure condition.

Sources: [WWDC20 image example](https://developer.apple.com/videos/play/wwdc2020/10077/), [image preparation in commits](https://developer.apple.com/videos/play/tech-talks/10856/), [offscreen rendering examples](https://developer.apple.com/videos/play/tech-talks/10857/).

## Measurement unavailable

Report the suspected mechanism, code/fixture evidence, exact interaction to reproduce, and which trace would confirm or disprove it. Prepare the test harness if requested. Keep device smoothness unverified until device data exists; do not invent metrics or treat simulator execution as physical-device evidence.
