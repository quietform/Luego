import GRDB
import Observation
import os
import SwiftUI

nonisolated enum BenchmarkSignposts {
    static let category = ProcessInfo.processInfo.arguments.contains("--benchmark-profile-signposts") ? "PointsOfInterest" : "Reader"
    static let signposter = OSSignposter(subsystem: "com.esoxjem.Luego.performance", category: category)
}

@main
struct BenchmarkApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--benchmark-image-fixture") {
            ImageFixture.install()
        }
        AppTypography.registerFonts()
        AppNavigationAppearance.configurePlatformAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--benchmark-animation-calibration") {
                    AnimationCalibration()
                } else {
                    BenchmarkReader()
                }
            }
                .preferredColorScheme(.light)
                .dynamicTypeSize(.large)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        }
    }
}

private struct BenchmarkReader: View {
    @State private var viewModel: ReaderViewModel?
    @State private var probe = ScrollProbe()
    @State private var foregroundSync: ForegroundSyncWorkload?
    @State private var setupError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel, foregroundSync?.libraryIsReady ?? true {
                    ReaderView(viewModel: viewModel)
                        .onScrollPhaseChange { _, phase, context in
                            probe.record(phase: phase, offset: context.geometry.contentOffset.y + context.geometry.contentInsets.top)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            ScrollStatus(probe: probe, foregroundSync: foregroundSync)
                        }
                } else if let setupError {
                    Text(setupError)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            do {
                let syncFixture = ProcessInfo.processInfo.arguments.contains("--benchmark-sync-fixture")
                let database = syncFixture ? try await ForegroundSyncFixture.makeDatabase() : try AppDatabase(DatabaseQueue())
                let store = GRDBArticleStore(database: database)
                let imageFixture = ProcessInfo.processInfo.arguments.contains("--benchmark-image-fixture")
                let content = imageFixture ? try await ImageFixture.prepare() : await TextFixture.markdown()
                let article = Article(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    url: URL(string: "https://fixture.invalid/text-v1")!,
                    title: imageFixture ? "Hitch fixture — images v1" : "Hitch fixture — text v1",
                    content: content,
                    savedDate: Date(timeIntervalSince1970: 1_700_000_000),
                    wordCount: content.split(whereSeparator: \.isWhitespace).count
                )
                let saved = try await store.saveArticle(article)
                if imageFixture {
                    probe.onScrollStart = { ImageFixture.scrolling(true) }
                    probe.onScrollIdle = { ImageFixture.scrolling(false) }
                }
                if syncFixture {
                    let scrollProbe = probe
                    let workload = ForegroundSyncWorkload(database: database, store: store, enabled: ProcessInfo.processInfo.arguments.contains("--benchmark-sync")) { [weak scrollProbe] in
                        scrollProbe?.isScrolling == true
                    }
                    foregroundSync = workload
                    probe.onScrollStart = { [weak workload] in workload?.scrollBegan() }
                    probe.onScrollIdle = { [weak workload] in workload?.scrollEnded() }
                }
                viewModel = ReaderViewModel(article: saved.article, readerService: ReaderService(articleStore: store, contentDataSource: OfflineContent()))
            } catch {
                setupError = error.localizedDescription
            }
        }
    }
}

private struct ScrollStatus: View {
    let probe: ScrollProbe
    let foregroundSync: ForegroundSyncWorkload?

    var body: some View {
        VStack(alignment: .trailing) {
            Text(probe.status)
                .accessibilityIdentifier("benchmark.scrollState")
                .accessibilityValue(probe.metricStatus)
            Text(probe.stallStatus)
                .accessibilityIdentifier("benchmark.stallState")
            if let foregroundSync {
                Text(foregroundSync.status)
                    .accessibilityIdentifier("benchmark.syncState")
            }
            if ProcessInfo.processInfo.arguments.contains("--benchmark-image-fixture") {
                Text(ImageFixture.status)
                    .accessibilityIdentifier("benchmark.imageState")
                Text(ImageFixture.scrolls)
                    .accessibilityIdentifier("benchmark.imageScrolls")
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(4)
        .background(.regularMaterial)
        .allowsHitTesting(false)
    }
}

@Observable
@MainActor
private final class ScrollProbe {
    @ObservationIgnored var onScrollStart: (() -> Void)?
    @ObservationIgnored var onScrollIdle: (() -> Void)?
    var isScrolling: Bool { interval != nil }
    private(set) var status = "idle|0|0"
    private(set) var stallStatus = "0|0"
    var metricStatus: String { indexedScrolls ? "\(BenchmarkSignposts.category)|\(intervalName)" : BenchmarkSignposts.category }
    @ObservationIgnored private let indexedScrolls = ProcessInfo.processInfo.arguments.contains("--benchmark-indexed-scrolls")
    @ObservationIgnored private let scrollNames: [StaticString] = ["ReaderScroll1", "ReaderScroll2", "ReaderScroll3", "ReaderScroll4", "ReaderScroll5", "ReaderScroll6"]
    @ObservationIgnored private var intervalName: StaticString = "ReaderScroll"
    @ObservationIgnored private let stallEnabled = ProcessInfo.processInfo.arguments.contains("--benchmark-stall")
    @ObservationIgnored private let signposter = BenchmarkSignposts.signposter
    @ObservationIgnored private var interval: OSSignpostIntervalState?
    @ObservationIgnored private var completed = 0
    @ObservationIgnored private var stallCount = 0
    @ObservationIgnored private var stallMilliseconds = 0.0

    func record(phase: ScrollPhase, offset: CGFloat) {
        if phase.isScrolling, interval == nil {
            if indexedScrolls { intervalName = scrollNames[completed] }
            interval = signposter.beginAnimationInterval(intervalName, id: signposter.makeSignpostID())
            onScrollStart?()
            if stallEnabled {
                let scroll = completed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.interval != nil, self.completed == scroll {
                        self.injectStall()
                    }
                }
            }
        }
        if phase == .idle, let interval {
            signposter.endInterval(intervalName, interval)
            self.interval = nil
            completed += 1
            status = "idle|\(completed)|\(Int(offset.rounded()))"
            onScrollIdle?()
        }
    }

    private func injectStall() {
        precondition(Thread.isMainThread)
        let stall = signposter.beginInterval("InjectedMainThreadStall", id: signposter.makeSignpostID())
        let start = ContinuousClock.now
        Thread.sleep(forTimeInterval: 0.2)
        let elapsed = start.duration(to: .now).components
        signposter.endInterval("InjectedMainThreadStall", stall)
        stallCount += 1
        stallMilliseconds += Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        stallStatus = "\(stallCount)|\(Int(stallMilliseconds))"
    }
}

private enum TextFixture {
    @concurrent
    static func markdown() async -> String {
        let paragraph = """
        A reader moves through an article one thought at a time. The page contains enough detail to require real typesetting, line wrapping, and view layout. Each paragraph describes a quiet walk through a city, past a library and a garden, with time to notice small changes in the light. **Bold phrases**, *emphasis*, and `inline code` exercise the same Markdown rendering used by saved articles. The experiment keeps its content fixed so that repeated runs perform the same work. There are no images, remote requests, changing dates, or synchronized edits in this fixture. Scrolling still uses the normal reader and its reading-position persistence.
        """
        return "FIXTURE_START The article is prepared before the scrolling measurement begins.\n\n" + (1...80).map {
            "## Section \(String(format: "%03d", $0))\n\n\(paragraph)"
        }.joined(separator: "\n\n") + "\n\nFIXTURE_END"
    }
}

@MainActor
final class OfflineContent: ContentDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata { throw URLError(.notConnectedToInternet) }
    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent { throw URLError(.notConnectedToInternet) }
}
