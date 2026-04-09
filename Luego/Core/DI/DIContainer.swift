import CloudKit
import Foundation

@MainActor
final class DIContainer {
    let database: AppDatabase
    let articleStore: ArticleStoreProtocol
    let syncEngineManager: SyncEngineManager
    let syncObserver = SyncStatusObserver()

    private lazy var userDefaultsDataSource: UserDefaultsDataSourceProtocol = {
        UserDefaultsDataSource(sharedStorage: SharedStorage.shared)
    }()

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
        LuegoSDKCacheDataSource()
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
        ParsedContentCacheDataSource()
    }()

    private lazy var localMetadataDataSource: MetadataDataSourceProtocol = {
        MetadataDataSource()
    }()

    private lazy var metadataDataSource: MetadataDataSourceProtocol = {
        ContentDataSource(
            parserDataSource: luegoParserDataSource,
            parsedContentCache: parsedContentCacheDataSource,
            luegoAPIDataSource: luegoAPIDataSource,
            metadataDataSource: localMetadataDataSource,
            sdkManager: luegoSDKManager
        )
    }()

    private lazy var opmlDataSource: OPMLDataSource = {
        OPMLDataSource()
    }()

    private lazy var blogrollRSSDataSource: BlogrollRSSDataSource = {
        BlogrollRSSDataSource()
    }()

    private lazy var genericRSSDataSource: GenericRSSDataSource = {
        GenericRSSDataSource()
    }()

    private lazy var kagiSmallWebDataSource: DiscoverySourceProtocol = {
        KagiSmallWebDataSource(opmlDataSource: opmlDataSource)
    }()

    private lazy var blogrollDataSource: DiscoverySourceProtocol = {
        BlogrollDataSource(
            blogrollRSSDataSource: blogrollRSSDataSource,
            genericRSSDataSource: genericRSSDataSource
        )
    }()

    private lazy var discoveryPreferencesDataSource: DiscoveryPreferencesDataSourceProtocol = {
        DiscoveryPreferencesDataSource()
    }()

    private lazy var articleService: ArticleServiceProtocol = {
        ArticleService(
            articleStore: articleStore,
            metadataDataSource: metadataDataSource,
            syncEngineManager: syncEngineManager
        )
    }()

    private lazy var readerService: ReaderServiceProtocol = {
        ReaderService(
            articleStore: articleStore,
            metadataDataSource: metadataDataSource
        )
    }()

    private lazy var discoveryService: DiscoveryServiceProtocol = {
        DiscoveryService(
            kagiSmallWebDataSource: kagiSmallWebDataSource,
            blogrollDataSource: blogrollDataSource,
            metadataDataSource: metadataDataSource
        )
    }()

    private lazy var sharingService: SharingServiceProtocol = {
        SharingService(
            articleStore: articleStore,
            metadataDataSource: metadataDataSource,
            userDefaultsDataSource: userDefaultsDataSource
        )
    }()

    private lazy var _savedArticleImportService: SavedArticleImportServiceProtocol = {
        SavedArticleImportService(
            articleStore: articleStore,
            metadataDataSource: metadataDataSource
        )
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
            container: CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        )
        self.syncEngineManager = syncEngineManager
        syncEngineManager.statusObserver = syncObserver
        coreArticleStore.syncEngineManager = syncEngineManager
    }

    var sdkManager: LuegoSDKManagerProtocol { luegoSDKManager }

    func makeArticleListViewModel() -> ArticleListViewModel {
        ArticleListViewModel(
            articleService: articleService,
            sharingService: sharingService
        )
    }

    func makeReaderViewModel(article: Article) -> ReaderViewModel {
        ReaderViewModel(
            article: article,
            readerService: readerService
        )
    }

    func makeDiscoveryViewModel() -> DiscoveryViewModel {
        DiscoveryViewModel(
            discoveryService: discoveryService,
            articleService: articleService,
            preferencesDataSource: discoveryPreferencesDataSource
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            preferencesDataSource: discoveryPreferencesDataSource,
            discoveryService: discoveryService,
            sdkManager: luegoSDKManager,
            articleService: articleService,
            savedArticleImportService: savedArticleImportService,
            savedArticleExportService: savedArticleExportService
        )
    }
}
