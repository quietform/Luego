# Luego Architecture

Luego is a SwiftUI app for iOS and iPadOS 26+, organized by feature. It uses Observation for UI state, GRDB/SQLite for local storage, and `CKSyncEngine` for CloudKit private database sync. Features share one app target; the share extension runs separately.

## Startup and dependencies

[LuegoApp](../Luego/App/LuegoApp.swift) opens and migrates `AppDatabase` asynchronously, creates `DIContainer`, starts sync, and runs the legacy article migration. A loading view remains responsive during startup. Once initialization finishes, it provides the container and sync-status observer through the SwiftUI environment.

[DIContainer](../Luego/Core/DI/DIContainer.swift) owns shared dependencies and constructs view models. Feature services use protocols for injection. View models, feature services, article-store facades, and sync orchestration use `@MainActor` isolation. Expensive implementation work crosses explicit execution boundaries; making a service `async` alone does not move its computation off the main actor.

```text
View -> ViewModel -> Service -> ArticleStoreProtocol -> GRDB / SQLite
                       |
                       +-> Data sources -> Network / caches / preferences

GRDBArticleStore <-> SyncEngineManager <-> CloudKit private database
```

[ContentView](../Luego/App/ContentView.swift) owns navigation and deep links, and asks `ArticleListViewModel` to refresh when active. The view model imports shared URLs independently of foreground CloudKit catch-up. Compact layouts use tabs; regular layouts use split navigation.

## Execution boundaries

- Observable `Article` objects and UI state stay on the main actor. Sendable value records cross background boundaries.
- Article and shared-queue persistence use GRDB's asynchronous reads and writes. Database opening runs in `@concurrent` functions. Duplicate-URL saves, content merges, and sync-state merges each use a single transaction. CloudKit acknowledgements update only system fields, preserving concurrent local edits and tombstones.
- One shared `FileCache` actor owns article-cache and parser-SDK file I/O and JSON coding. It reads JavaScript bundles as one snapshot and completes accepted writes and removals without inspecting task cancellation.
- Markdown document preparation, image decoding, and RSS/OPML parsing use `@concurrent` functions with local parser state and run to completion. Cancellation is handled at the UI boundary before publishing a document or image. Progress saves wait until the document is rendered; height tracking follows placeholder replacement and image layout changes, and pending restoration is cancelled when leaving the reader.
- Discovery feed-cache coding and seen-item filtering run in background functions. Generation checks prevent late cache work from undoing a clear. Import URL detection and text-file transfers also run off the main actor.
- The existing parser actor owns JavaScriptCore. No actor is introduced per service or CPU operation.

## Storage and sync

[AppDatabase](../Luego/Core/Database/AppDatabase.swift) opens a GRDB database pool at `Application Support/Luego/luego.sqlite` in the app sandbox. Migrations define the article, sync-state, and migration-marker tables.

[Article](../Luego/Core/Models/Article.swift) is an observable in-memory model. [ArticleRecord](../Luego/Core/Database/ArticleRecord.swift) maps SQLite and CloudKit records, including deletion timestamps and CloudKit system fields. [ArticleListMembership](../Luego/Core/Models/ArticleListMembership.swift) contains the favorite/archive rules.

[GRDBArticleStore](../Luego/Core/Stores/GRDBArticleStore.swift) implements two contracts: `ArticleStoreProtocol` for feature operations and `ArticleRecordStoreProtocol` for sync and migration. It handles queries, observation, duplicate URLs, and local mutations:

- Local article changes enqueue sync. Deletion creates a tombstone.
- `saveArticle` returns `ArticleSaveResult` with the stored article and an atomic `isNew` decision. Inserts and tombstone restorations count as new; existing active articles and updates do not. Duplicate URL saves reuse the stored identity without enqueueing another save.
- `saveRecord` applies records without enqueueing sync; `deleteRecord` physically removes them when applying remote deletions.
- Visible article queries exclude tombstones. Raw record queries can include them.
- Observation preserves article object identity. Direct fetches and saves return detached objects.

[SyncEngineManager](../Luego/Core/Services/SyncEngineManager.swift) sends local changes and applies incoming records using the store. Engine state is persisted in SQLite. Outbound batch preparation distinguishes confirmed missing records from read errors. Only confirmed missing records remove pending saves; a read error defers the batch and preserves pending changes for retry. Foreground catch-up and manual refresh fetch changes and perform a server backfill; Settings also exposes a full repair operation. The configured container is `iCloud.com.esoxjem.Luego`, using its private database.

[SyncStatusObserver](../Luego/Core/Services/SyncStatusObserver.swift) receives status directly from the manager in the app's DI setup. It is the single observable owner of sync state and diagnostics.

Local reading and editing work without a successful CloudKit round trip. Offline reading requires article content to have been fetched and saved.

## Content fetching

Services receive [ContentDataSource](../Luego/Core/DataSources/ContentDataSource.swift) through `ContentDataSourceProtocol`. A content request follows this order:

1. Read `ParsedContentCacheDataSource` when caching is enabled.
2. Fetch HTML through `WebPageDataSource` and parse it with `LuegoParserDataSource` when the SDK is ready.
3. Fall back to `LuegoAPIDataSource` if local parsing is unavailable or fails.

`WebPageDataSource` handles URL validation and HTML fetching. `ContentDataSource` implements metadata and content requests. Force refresh clears cached content for the URL; Discovery skips cache reads and writes. Metadata requests fetch fresh metadata and cache any usable article body returned by the local parser or API for later reading.

[LuegoSDKManager](../Luego/Core/DataSources/LuegoSDKManager.swift) downloads parser bundles and rules through `LuegoSDKDataSource`, storing them in `LuegoSDKCacheDataSource`. `LuegoParserDataSource` coordinates SDK snapshots on the main actor and passes them to a private parser actor that owns and reuses the JavaScriptCore context. JavaScript execution stays serialized, and only Swift values cross the actor boundary. SDK files and parsed article content have separate caches.

## Features

| Folder | Responsibility |
| --- | --- |
| [ReadingList](../Luego/Features/ReadingList/) | Save, list, favorite, archive, delete, and import/export article URLs |
| [Reader](../Luego/Features/Reader/) | Fetch and save article content, and persist reading position |
| [Discovery](../Luego/Features/Discovery/) | Fetch random articles from Kagi Small Web or Blogroll; hold them in memory until saved |
| [Sharing](../Luego/Features/Sharing/) | Queue shared URLs, import them into the app, and construct deep links |
| [Settings](../Luego/Features/Settings/) | Preferences, parser updates, repair sync, import/export UI, and diagnostics |

Adding a URL saves metadata, the available word count, and any body already returned by the parser or API, so the list can show an excerpt before the reader opens. `ReaderService` fetches the body when needed, reloads the current article from storage, and saves the content. Reader load, retry, and refresh requests run directly in the view's task. A request identity prevents an older request's cleanup from clearing a newer request's loading state. Workers and storage follow their normal result and error contracts, so completed content may still be cached or persisted after the reader leaves. The reader and Discovery discard cancelled requests before publishing results or errors, and Discovery does not retry a cancelled view request. URLSession and GRDB can still return their own cancellation errors; those propagate without extra worker policy. GRDB transactions preserve atomicity when a write fails or is cancelled. Saving a Discovery article includes its available content. Add, sharing, and plain-text import use `ArticleService.addArticle`, which forwards the store’s atomic save result to keep sharing and import counts accurate under concurrent saves.

Reader Markdown is prepared off the main actor when content, title, or base URL changes, then rendered as separate top-level blocks. Text-only blocks stay rendered. Image-bearing blocks load within one viewport height above or below the screen and retain their attachments until they are more than two viewport heights away. Standalone photos own their decoded image state directly and retain only their dimensions after release, so reloading does not shrink their placeholders. Textual continues to render text and mixed markup. Geometry updates change state only when a block crosses one of these boundaries. Images are decoded off the main actor with ImageIO thumbnails capped at 1200 pixels; animated images share a 24 MiB frame budget. The reader uses URLSession caching for compressed responses and does not keep a global decoded-image cache.

## Share extension

[ShareViewController](../LuegoShareExtension/ShareViewController.swift) extracts a web URL and appends it to [SharedStorage](../Luego/Features/Sharing/DataSources/SharedStorage.swift). The queue lives in `SharedURLs.sqlite` in App Group `group.com.esoxjem.Luego`. Each occurrence has its own ID. The first database migration imports the previous `UserDefaults` JSON queue.

When active, the app imports the queue through `SharingService` while foreground CloudKit catch-up runs independently. Overlapping foreground events share one active import and request a follow-up pass to pick up URLs queued in the meantime. Successful items are acknowledged individually; failed items and URLs added during a pass remain queued until a later pass. The extension's success screen confirms queueing; article ingestion happens in the app.

## Legacy migration

[LegacySwiftDataArticleMigration](../Luego/Core/Services/LegacySwiftDataArticleMigration.swift) reads the previous SwiftData SQLite store in a background function and returns Sendable records, imports them into GRDB, enqueues them for sync, and records completion in `migrationState`. Preserve this upgrade path for existing installs.

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding rules, [TESTING.md](TESTING.md) for verification, and [README.md](README.md) for setup.
