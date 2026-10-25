# Luego Architecture

Luego is a SwiftUI app for iOS and iPadOS 26+, organized by feature. It uses Observation for UI state, GRDB/SQLite for local storage, and `CKSyncEngine` for CloudKit private database sync. Features share one app target; the share extension runs separately.

## Startup and dependencies

[LuegoApp](../Luego/App/LuegoApp.swift) opens and migrates `AppDatabase` asynchronously, creates `DIContainer`, starts sync, and runs the legacy article migration. The launch screen uses the `LaunchBackground` color asset, which mirrors `AppUIColor.appBackground` (guarded by `LaunchBackgroundTests`), so it hands off to `AppLaunchView` without a flash. `AppLaunchView` shows only that background unless startup exceeds 600 ms, then reveals the mascot and progress. Once initialization finishes, it provides the container and sync-status observer through the SwiftUI environment.

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
- Markdown document preparation, image decoding, and RSS/Atom parsing use `@concurrent` functions with local parser state and run to completion. Cancellation is handled at the UI boundary before publishing a document or image. Progress saves wait until the document is rendered; height tracking follows placeholder replacement and image layout changes, and pending restoration is cancelled when leaving the reader.
- Import URL detection and text-file transfers run off the main actor.
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
| [Discovery](../Luego/Features/Discovery/) | List recent posts from the Kagi Small Web River feed and the user's own feeds, kept in a cached snapshot; open a post in memory until it is saved |
| [Sharing](../Luego/Features/Sharing/) | Queue shared URLs, import them into the app, and construct deep links |
| [Settings](../Luego/Features/Settings/) | Preferences, parser updates, repair sync, import/export UI, and diagnostics |

`DiscoveryPostSource` builds the Discovery list from the user's feeds that are switched on. Kagi Small Web is the default feed and can be switched off, deleted, or added back like any other. Feeds are fetched concurrently through `FeedPostsDataSource`. Each `DiscoveryFeed` owns its post-selection policy: Kagi defaults to `.all`, and other feeds default to `.latestFive`. `DiscoveryPostSource` applies that policy without identifying Kagi by URL. Saved feed lists retain explicit policies, while older lists and cached snapshots receive the feed defaults. Duplicate URLs are removed and everything is ordered newest first. A feed that fails is skipped; an error is reported only when nothing loaded, and with no feeds switched on, `DiscoveryService.refreshPosts` reports `.noFeedsOn` without fetching, and the list shows an empty state. The user manages feeds from the pencil action in Discovery. `DiscoveryService.addFeed` accepts a blog address or a feed URL, follows the page's RSS or Atom `alternate` link when needed, checks the homepage for an advertised feed, and probes common feed paths (`feed`, `feed.xml`, `rss`, `rss.xml`, `atom.xml`, `index.xml`) under the final (redirected) address and site root before rejecting a page. Common paths are checked concurrently with five-second request timeouts, and only successful HTTP responses containing usable posts are accepted. It rejects a URL already in the list, and saves the list in `DiscoveryFeedStore` (`UserDefaults`, this device only) through a stored format separate from `DiscoveryFeed`, so fields added later default when older lists are read.

`DiscoveryService` owns the freshness policy. `DiscoveryPostCache` stores the last fetched posts, fetch time, and the feeds they came from as one versioned JSON snapshot in Caches through `FileCache`; a format mismatch or unreadable file is a cache miss. Opening Discovery shows the snapshot, or `DiscoveryPostPlaceholderList` rows in the list's layout until one exists, then refreshes it if it is older than an hour or the user's feeds, or which of them are switched on, have changed. Every feed edit is announced through `DiscoveryService.feedChanges()`, and `DiscoveryListViewModel` applies the same check when it hears one. Returning to the app does the same once Discovery has been opened, and pull-to-refresh always fetches. Overlapping refreshes for the same feeds share one fetch, a fetch for feeds that changed meanwhile is not saved, and a failed fetch leaves the snapshot and listed posts in place.

The dice action selects from the posts already listed without fetching feeds or changing their chronological order. `DiscoveryListViewModel` owns the shuffle history for the app session: each URL is visited before a new cycle begins, the current article is excluded, and unseen posts from another domain are preferred when available. The reader offers the same action while loading or after a failure, with Save disabled until content is available. Shuffle updates the selected detail on iPad and replaces the article route on iPhone, so Back returns directly to the list.

`DiscoveryArticleService` opens a listed or shuffled post through the shared `ContentDataSource` with a ten-second timeout and no parsed-content caching. It constructs the ephemeral article, preserves the post title and fallback image, keeps the feed's date unless it is missing or in the future, and translates loading failures. The article page renders the post's header immediately, so only the body changes when content arrives. `DiscoveryArticleViewModel` depends on this article-only protocol; feed management has no content-fetching dependency.

Adding a URL saves metadata, the available word count, and any body already returned by the parser or API, so the list can show an excerpt before the reader opens. `ReaderService` fetches the body when needed, reloads the current article from storage, and saves the content. Reader load, retry, and refresh requests run directly in the view's task. A request identity prevents an older request's cleanup from clearing a newer request's loading state. Workers and storage follow their normal result and error contracts, so completed content may still be cached or persisted after the reader leaves. The reader and Discovery discard cancelled requests before publishing results or errors, and Discovery does not retry a cancelled view request. URLSession and GRDB can still return their own cancellation errors; those propagate without extra worker policy. GRDB transactions preserve atomicity when a write fails or is cancelled. Saving a Discovery article includes its available content. Add, sharing, and plain-text import use `ArticleService.addArticle`, which forwards the store’s atomic save result to keep sharing and import counts accurate under concurrent saves.

Reader Markdown is prepared off the main actor when content, title, or base URL changes, then rendered as separate top-level blocks. Until it is ready, `ReaderBodyPlaceholder` shows text-shaped lines in the reader font beneath the real header, covering both downloading and preparation. Text-only blocks stay rendered. Image-bearing blocks load within one viewport height above or below the screen and retain their attachments until they are more than two viewport heights away. Standalone photos own their decoded image state directly and retain only their dimensions after release, so reloading does not shrink their placeholders. Textual continues to render text and mixed markup. Geometry updates change state only when a block crosses one of these boundaries. Images are decoded off the main actor with ImageIO thumbnails capped at 1200 pixels; animated images share a 24 MiB frame budget. The reader uses URLSession caching for compressed responses and does not keep a global decoded-image cache.

## Share extension

[ShareViewController](../LuegoShareExtension/ShareViewController.swift) extracts a web URL and appends it to [SharedStorage](../Luego/Features/Sharing/DataSources/SharedStorage.swift). The queue lives in `SharedURLs.sqlite` in App Group `group.com.esoxjem.Luego`. Each occurrence has its own ID. The first database migration imports the previous `UserDefaults` JSON queue.

When active, the app imports the queue through `SharingService` while foreground CloudKit catch-up runs independently. Overlapping foreground events share one active import and request a follow-up pass to pick up URLs queued in the meantime. Successful items are acknowledged individually; failed items and URLs added during a pass remain queued until a later pass. The extension's success screen confirms queueing; article ingestion happens in the app.

## Legacy migration

[LegacySwiftDataArticleMigration](../Luego/Core/Services/LegacySwiftDataArticleMigration.swift) reads the previous SwiftData SQLite store in a background function and returns Sendable records, imports them into GRDB, enqueues them for sync, and records completion in `migrationState`. Preserve this upgrade path for existing installs.

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding rules, [TESTING.md](TESTING.md) for verification, and [README.md](README.md) for setup.
