# Textual (patched copy)

Luego builds [Textual](https://github.com/gonzalezreal/textual) from this folder instead of the published package. It is release 0.5.0 (`01b5187`) under the MIT licence in [LICENSE](LICENSE), with two changes:

- **`Sources/`** applies upstream [PR #102](https://github.com/gonzalezreal/textual/pull/102) at `3ca60b2`, which includes [PR #80](https://github.com/gonzalezreal/textual/pull/80). UIKit keeps text positions after Textual re-lays out text, for example the selection its edit menu measures. In 0.5.0 those positions can index past the new layout and crash in `TextLayoutCollection.localCharacterRange(at:)` ([#87](https://github.com/gonzalezreal/textual/issues/87), [#89](https://github.com/gonzalezreal/textual/issues/89), [#101](https://github.com/gonzalezreal/textual/issues/101)). The patch bounds-checks positions and treats stale ones as empty.
- **`Package.swift`** drops upstream's test target and its `swift-snapshot-testing` dependency. Upstream's tests are not copied.

`Sources/` matches upstream at `3ca60b2` exactly; diff it against that commit to see the patch.

## Returning to upstream

Once a Textual release includes the fix, point `Luego.xcodeproj` and `PerformanceTests/LuegoPerformance.xcodeproj` back at the remote package and delete this folder. `ReaderSelectionTests.aRangeUIKitKeptFromBeforeAReflowMeasuresAsEmpty` must still pass.
