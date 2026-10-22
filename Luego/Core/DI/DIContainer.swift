import CloudKit
import Foundation

@MainActor
final class DIContainer {
    private let fileCache = FileCache()
    let database: AppDatabase
    let articleStore: GRDBArticleStore
    let syncEngineManager: SyncEngineManager
    let syncObserver = SyncStatusObserver()

    private lazy var luegoAPIDataSource: LuegoAPIDataSourceProtocol = {
        LuegoAPIDataSource()
    }()

    private lazy var luegoSDKDataSource: LuegoSDKDataSourceProtocol = {
        LuegoSDKDataSource(
            baseURL: AppConfiguration.luegoAPIBaseURL,
            apiKey: AppConfiguration.luegoAPIKey,
            timeout: AppConfiguration.luegoAPITimeout
        )
    }()

    private lazy var luegoSDKCacheDataSource: LuegoSDKCacheDataSourceProtocol = {
        LuegoSDKCacheDataSource(storage: fileCache)
    }()

    private lazy var luegoSDKManager: LuegoSDKManagerProtocol = {
        LuegoSDKManager(
            sdkDataSource: luegoSDKDataSource,
            cacheDataSource: luegoSDKCacheDataSource
        )
    }()

    private lazy var luegoParserDataSource: LuegoParserDataSourceProtocol = {
        LuegoParserDataSource(sdkManager: luegoSDKManager)
    }()

    private lazy var parsedContentCacheDataSource: ParsedContentCacheDataSourceProtocol = {
        ParsedContentCacheDataSource(storage: fileCache)
    }()

    private lazy var webPageDataSource: WebPageDataSourceProtocol = {
        WebPageDataSource()
    }()

    private lazy var contentDataSource: ContentDataSourceProtocol = {
        ContentDataSource(
            parserDataSource: luegoParserDataSource,
            parsedContentCache: parsedContentCacheDataSource,
            luegoAPIDataSource: luegoAPIDataSource,
            webPageDataSource: webPageDataSource,
            sdkManager: luegoSDKManager
        )
    }()

    private lazy var genericRSSDataSource: GenericRSSDataSource = {
        GenericRSSDataSource()
    }()

    private lazy var discoveryPostSource: DiscoveryPostSourceProtocol = {
        DiscoveryPostSource(feedPosts: FeedPostsDataSource(genericRSSDataSource: genericRSSDataSource))
    }()

    private lazy var articleService: ArticleServiceProtocol = {
        ArticleService(
            articleStore: articleStore,
            contentDataSource: contentDataSource,
            syncEngineManager: syncEngineManager
        )
    }()

    private lazy var readerService: ReaderServiceProtocol = {
        ReaderService(
            articleStore: articleStore,
            contentDataSource: contentDataSource
        )
    }()

    private lazy var discoveryService: DiscoveryServiceProtocol = {
        DiscoveryService(
            postSource: discoveryPostSource,
            contentDataSource: contentDataSource,
            postCache: DiscoveryPostCache(storage: fileCache),
            feedStore: DiscoveryFeedStore()
        )
    }()

    private lazy var sharingService: SharingServiceProtocol = {
        SharingService(
            articleService: articleService,
            sharedStorage: SharedStorage.shared
        )
    }()

    private lazy var _savedArticleImportService: SavedArticleImportServiceProtocol = {
        SavedArticleImportService(articleService: articleService)
    }()

    private lazy var _savedArticleExportService: SavedArticleExportServiceProtocol = {
        SavedArticleExportService(articleStore: articleStore)
    }()

    var savedArticleImportService: SavedArticleImportServiceProtocol { _savedArticleImportService }
    var savedArticleExportService: SavedArticleExportServiceProtocol { _savedArticleExportService }

    init(database: AppDatabase) {
        self.database = database

        let coreArticleStore = GRDBArticleStore(database: database)
        self.articleStore = coreArticleStore

        let syncEngineManager = SyncEngineManager(
            database: database,
            store: coreArticleStore,
            statusObserver: syncObserver,
            container: CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        )
        self.syncEngineManager = syncEngineManager
        coreArticleStore.syncEngineManager = syncEngineManager
    }

    var sdkManager: LuegoSDKManagerProtocol { luegoSDKManager }

    func makeArticleListViewModel() -> ArticleListViewModel {
        ArticleListViewModel(
            articleService: articleService,
            sharingService: sharingService,
            syncEngineManager: syncEngineManager
        )
    }

    func makeReaderViewModel(article: Article) -> ReaderViewModel {
        ReaderViewModel(
            article: article,
            readerService: readerService
        )
    }

    func makeDiscoveryListViewModel() -> DiscoveryListViewModel {
        DiscoveryListViewModel(discoveryService: discoveryService)
    }

    func makeDiscoveryFeedsViewModel() -> DiscoveryFeedsViewModel {
        DiscoveryFeedsViewModel(discoveryService: discoveryService)
    }

    func makeDiscoveryArticleViewModel(post: DiscoveryPost) -> DiscoveryArticleViewModel {
        DiscoveryArticleViewModel(
            post: post,
            discoveryService: discoveryService,
            articleService: articleService
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            sdkManager: luegoSDKManager,
            articleService: articleService,
            savedArticleImportService: savedArticleImportService,
            savedArticleExportService: savedArticleExportService
        )
    }
}
