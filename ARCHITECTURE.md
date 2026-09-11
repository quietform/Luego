# Luego Architecture

Luego is a SwiftUI app for iOS and iPadOS 26+, organized by feature. It uses Observation for UI state, GRDB/SQLite for local storage, and `CKSyncEngine` for CloudKit private database sync. Features share one app target; the share extension runs separately.

## Startup and dependencies

[LuegoApp](Luego/App/LuegoApp.swift) opens `AppDatabase`, creates `DIContainer`, starts sync, and runs the legacy article migration. It provides the container and sync-status observer through the SwiftUI environment.

[DIContainer](Luego/Core/DI/DIContainer.swift) owns shared dependencies and constructs view models. Feature services use protocols for injection. View models, feature services, article stores, and sync orchestration use `@MainActor` isolation.

```text
View -> ViewModel -> Service -> ArticleStoreProtocol -> GRDB / SQLite
                       |
                       +-> Data sources -> Network / caches / preferences

GRDBArticleStore <-> SyncEngineManager <-> CloudKit private database
```

[ContentView](Luego/App/ContentView.swift) owns navigation, foreground catch-up, shared-URL import, and deep links. Compact layouts use tabs; regular layouts use split navigation.

## Storage and sync

[AppDatabase](Luego/Core/Database/AppDatabase.swift) opens a GRDB database pool at `Application Support/Luego/luego.sqlite` in the app sandbox. Migrations define the article, sync-state, and migration-marker tables.

[Article](Luego/Core/Models/Article.swift) is an observable in-memory model. [ArticleRecord](Luego/Core/Database/ArticleRecord.swift) maps SQLite and CloudKit records, including deletion timestamps and CloudKit system fields. [ArticleListMembership](Luego/Core/Models/ArticleListMembership.swift) contains the favorite/archive rules.

[GRDBArticleStore](Luego/Core/Stores/GRDBArticleStore.swift) implements two contracts: `ArticleStoreProtocol` for feature operations and `ArticleRecordStoreProtocol` for sync and migration. It handles queries, observation, duplicate URLs, and local mutations:

- Local article changes enqueue sync. Deletion creates a tombstone.
- `saveRecord` applies records without enqueueing sync; `deleteRecord` physically removes them when applying remote deletions.
- Visible article queries exclude tombstones. Raw record queries can include them.
- Observation preserves article object identity. Direct fetches and saves return detached objects.

[SyncEngineManager](Luego/Core/Services/SyncEngineManager.swift) sends local changes and applies incoming records using the store. Engine state is persisted in SQLite. Foreground catch-up and manual refresh fetch changes and perform a server backfill; Settings also exposes a full repair operation. The configured container is `iCloud.com.esoxjem.Luego`, using its private database.

[SyncStatusObserver](Luego/Core/Services/SyncStatusObserver.swift) receives status directly from the manager in the app's DI setup. It is the single observable owner of sync state and diagnostics.

Local reading and editing work without a successful CloudKit round trip. Offline reading requires article content to have been fetched and saved.

## Content fetching

Services receive [ContentDataSource](Luego/Core/DataSources/ContentDataSource.swift) through `ContentDataSourceProtocol`. A content request follows this order:

1. Read `ParsedContentCacheDataSource` when caching is enabled.
2. Fetch HTML through `WebPageDataSource` and parse it with `LuegoParserDataSource` when the SDK is ready.
3. Fall back to `LuegoAPIDataSource` if local parsing is unavailable or fails.

`WebPageDataSource` handles URL validation and HTML fetching. `ContentDataSource` implements metadata and content requests. Force refresh clears cached content for the URL; Discovery skips cache reads and writes. Metadata requests do not populate the parsed-content cache.

[LuegoSDKManager](Luego/Core/DataSources/LuegoSDKManager.swift) downloads parser bundles and rules through `LuegoSDKDataSource`, storing them in `LuegoSDKCacheDataSource`. `LuegoParserDataSource` executes the bundles in JavaScriptCore. SDK files and parsed article content have separate caches.

## Features

| Folder | Responsibility |
| --- | --- |
| [ReadingList](Luego/Features/ReadingList/) | Save, list, favorite, archive, delete, and import/export article URLs |
| [Reader](Luego/Features/Reader/) | Fetch and save article content, and persist reading position |
| [Discovery](Luego/Features/Discovery/) | Fetch random articles from Kagi Small Web or Blogroll; hold them in memory until saved |
| [Sharing](Luego/Features/Sharing/) | Queue shared URLs, import them into the app, and construct deep links |
| [Settings](Luego/Features/Settings/) | Preferences, parser updates, repair sync, import/export UI, and diagnostics |

Adding a URL saves metadata first. `ReaderService` fetches the body when needed, reloads the current article from storage, and saves the content. Saving a Discovery article includes its available content. Add, sharing, and plain-text import use `ArticleService.addArticle`, which reports whether it saved a new article or found an existing one.

## Share extension

[ShareViewController](LuegoShareExtension/ShareViewController.swift) extracts a web URL and appends it to [SharedStorage](Luego/Features/Sharing/DataSources/SharedStorage.swift). The queue lives in `SharedURLs.sqlite` in App Group `group.com.esoxjem.Luego`. Each occurrence has its own ID. The first database migration imports the previous `UserDefaults` JSON queue.

When active, the app requests foreground catch-up and then imports the queue through `SharingService`. Successful items are acknowledged individually; failed items and URLs added during import remain queued. The extension's success screen confirms queueing; article ingestion happens in the app.

## Legacy migration

[LegacySwiftDataArticleMigration](Luego/Core/Services/LegacySwiftDataArticleMigration.swift) reads the previous SwiftData SQLite store, imports records into GRDB, enqueues them for sync, and records completion in `migrationState`. Preserve this upgrade path for existing installs.

See [AGENTS.md](AGENTS.md) for coding and verification rules and [README.md](README.md) for setup and simulator commands.
