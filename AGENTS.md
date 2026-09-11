# AGENTS.md

## Project Snapshot

- Product: Luego, a minimal read-it-later app.
- Stack: SwiftUI, Observation, and Swift 5 language mode with complete strict concurrency checking.
- Platforms: iOS 26.0+, iPadOS 26.0+.
- Persistence: GRDB over local SQLite, synchronized with the CloudKit private database through `CKSyncEngine`.
- CloudKit container: `iCloud.com.esoxjem.Luego`.
- App Group: `group.com.esoxjem.Luego` for the shared URL queue.
- Extra target: `LuegoShareExtension/` for share-sheet ingestion.

## Repository Map

- `Luego/App/`: app entry and root navigation.
- `Luego/Core/Models/`: observable `Article` and shared value types.
- `Luego/Core/Database/`: SQLite schema, migrations, `ArticleRecord`, and persisted sync state.
- `Luego/Core/Stores/`: article persistence and observation through `ArticleStoreProtocol`; raw sync records use `ArticleRecordStoreProtocol`.
- `Luego/Core/Services/`: CloudKit sync, status, diagnostics, and legacy data migration.
- `Luego/Core/DataSources/`: content fetching, parser SDK management, and caches.
- `Luego/Core/DI/DIContainer.swift`: shared dependencies and view model factories.
- `Luego/Features/`: vertical feature slices (`ReadingList`, `Reader`, `Discovery`, `Sharing`, `Settings`).
- `LuegoShareExtension/`: iOS/iPadOS share extension target.
- `Configuration/`: build-configuration-specific bundle identifiers and display names.
- `docs/`: public website, privacy page, and screenshots.
- [ARCHITECTURE.md](ARCHITECTURE.md): runtime composition and data flows.

## Architecture Rules

- Keep feature persistence behind `View -> ViewModel -> Service -> ArticleStoreProtocol -> GRDB`.
- Services use data sources for network content, preferences, and shared URLs.
- Preserve `@MainActor` isolation for view models, feature services, article stores, and sync orchestration.
- Every service should have a protocol for testability.
- Wire dependencies only through `DIContainer`.
- When adding a feature:

1. Add/update model in `Luego/Core/Models/` if required.
2. Add service in `Luego/Features/<Feature>/Services/`.
3. Add view model and views in `Luego/Features/<Feature>/Views/`.
4. Register factories in `Luego/Core/DI/DIContainer.swift`.

## Data And Sync Rules

- Use `AppDatabase` for local SQLite storage and `SyncEngineManager` for CloudKit private database sync.
- Use article-store operations for local changes. `saveArticle` and local delete/update operations enqueue sync; `saveRecord` applies records without enqueueing an outbound change.
- Preserve tombstones and CloudKit system fields when changing persistence or sync behavior.
- Preserve `LegacySwiftDataArticleMigration` for existing installs.
- Keep content fetch layering intact:

1. `ContentDataSource` coordinates content caching, local parsing, and API fallback.
2. `WebPageDataSource` validates URLs and fetches HTML; `LuegoParserDataSource` parses it with JavaScriptCore.
3. `LuegoAPIDataSource` fetches articles when local parsing is unavailable or fails.
4. `LuegoSDKManager` manages parser bundles and rules through `LuegoSDKDataSource` and `LuegoSDKCacheDataSource`; `ParsedContentCacheDataSource` caches parsed article content separately.

- Preserve local reading and editing without requiring CloudKit availability. Offline reading requires previously fetched article content.
- Avoid blocking the main thread during sync-sensitive flows.
- The share extension queues URLs in App Group storage; the app imports them through `SharingService` when active.

## Platform Rules

- Implement and verify changes for iOS and iPadOS together.
- Use platform guards only where behavior truly differs.
- Keep entitlements in sync with target capabilities:
  - `Luego/Luego.entitlements`
  - `LuegoShareExtension/LuegoShareExtension.entitlements`

## Coding Rules

- Favor simple implementations with few moving parts. Remove unnecessary abstractions before adding new layers.
- No inline comments.
- No `// MARK:` sections.
- Prefer clear naming and small functions over commentary.
- Use modern Swift patterns: `@Observable`, `async/await`, `@MainActor`, `#Preview`.
- SwiftUI organization: root view first, supporting subviews next, extensions last.
- Prefer deep modules and deep classes.

## Verification

Keep only one simulator running at a time to limit laptop memory use. Shut it down before switching devices.

1. Build for the iOS simulator.
2. Never use raw `xcodebuild`; always use the `xcodebuildmcp` CLI for simulator builds.
3. Prefer direct `xcodebuildmcp` commands for local verification:
   - `xcodebuildmcp simulator build --use-latest-os`
   - `xcodebuildmcp simulator build-and-run --use-latest-os`
   - `xcodebuildmcp simulator test --scheme LuegoTests --use-latest-os --json '{"extraArgs":["-parallel-testing-enabled","NO"]}'`
   - `xcodebuildmcp simulator list`
   - `xcodebuildmcp simulator screenshot --simulator-id <uuid>`
   - `xcodebuildmcp simulator snapshot-ui --simulator-id <uuid>`
4. Run the app via `xcodebuildmcp` and verify with logs or screenshots for iOS or iPadOS as required by the task.
