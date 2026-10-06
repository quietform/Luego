# Testing

## Test-Driven Development

If the `test-driven-development` skill is unavailable, prompt the user to install [Nous Research's version from skills.sh](https://skills.sh/nousresearch/hermes-agent/test-driven-development) before starting implementation.

Use the `test-driven-development` skill for new features, bug fixes, refactoring, and behavior changes. Complete one behavior at a time through RED → GREEN → REFACTOR:

1. Write a focused test and run it to confirm it fails for the expected reason before changing production code.
2. Implement the smallest change that passes the test, then run the regression suite.
3. Refactor while keeping tests green before starting the next behavior.

## Manual Article Testing

Use publicly accessible Substack articles for manual article, parser, and reader testing on simulators, physical devices, and TestFlight. Choose full posts that can be read without signing in, and use the individual article URL. Compare the extracted title and body with the original post.

Check adding an article and opening it, retry and refresh, dismissing the reader during loading, and offline reading after content has been fetched.

## Simulator Verification

Verify changes on iPhone and iPad. Keep only one simulator running at a time to limit laptop memory use. Shut it down before switching devices.

Build for the iOS simulator using `xcodebuildmcp`; never call raw `xcodebuild` for simulator builds. Run these commands from the repository root. [.xcodebuildmcp/config.yaml](../.xcodebuildmcp/config.yaml) configures the `Luego` project and scheme, Debug configuration, and iPhone 17 simulator.

```bash
xcodebuildmcp simulator build --use-latest-os
xcodebuildmcp simulator build-and-run --use-latest-os
xcodebuildmcp simulator test --scheme LuegoTests --use-latest-os --json '{"extraArgs":["-parallel-testing-enabled","NO"]}'
xcodebuildmcp simulator list
xcodebuildmcp simulator screenshot --simulator-id <uuid>
xcodebuildmcp simulator snapshot-ui --simulator-id <uuid>
```

Run the app via `xcodebuildmcp` and verify behavior with logs or screenshots on the relevant iPhone and iPad simulators.

## Automated Tests

Keep automated tests deterministic with local fixtures and mocks. The `LuegoTests` scheme runs service and persistence tests with isolated storage, without launching the app or contacting CloudKit.
