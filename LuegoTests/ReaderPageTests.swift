import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderPageTests {
    private let header = ReaderArticleHeader(
        title: "Organising a Conference",
        source: "ratik.in",
        url: URL(string: "https://ratik.in/cmon/16")!,
        date: "8 Nov 2026",
        readingMinutes: 4
    )

    private let longArticle = (1...40)
        .map { "Paragraph \($0) keeps the reader busy with a few lines of wrapping text so the article scrolls." }
        .joined(separator: "\n\n")

    init() {
        LoraTestFonts.register()
    }

    @Test
    func whileLoadingTheBodyIsAPlaceholderBeneathTheHeader() {
        let column = ReaderColumn(header: header, markdown: nil, width: 390)

        #expect(accessibilityLabels(in: column) == ["Organising a Conference", "ratik.in", "8 Nov 2026 · 4 min read", "Loading article"])
    }

    @Test(arguments: [(CGFloat(390), CGFloat(40)), (1000, 150)])
    func theArticleSitsInAReadingColumnSizedToThePane(width: CGFloat, margin: CGFloat) throws {
        let column = ReaderColumn(header: header, markdown: nil, width: width)

        let title = try #require(accessibilityFrames(in: column, width: width)["Organising a Conference"])
        #expect(abs(title.minX - margin) < 1, "\(title)")
    }

    @Test
    func oncePreparedThePageReportsHowFarDownTheBottomOfTheScreenIs() async throws {
        let positions = PositionRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: longArticle, onReadingPositionChange: positions.record))
        defer { host.close() }

        await host.settle { positions.latest != nil }

        let reported = try #require(positions.latest)
        let visibleBottom = try #require(host.visibleBottom)
        #expect(abs(reported - visibleBottom) < 0.01, "reported \(reported), on screen \(visibleBottom)")
    }

    @Test
    func theReadingProgressFollowsHowFarThePageHasScrolled() async throws {
        let positions = PositionRecorder()
        let progress = ProgressRecorder()
        let page = ReaderPage(header: header, markdown: longArticle, onReadingPositionChange: positions.record)
            .onReadingProgressChange(perform: progress.record)
        let host = PageHost(page)
        defer { host.close() }
        await host.settle { positions.latest != nil }

        let scroll = try #require(host.scrollView)
        let insets = scroll.adjustedContentInset
        let scrollable = scroll.contentSize.height - (scroll.bounds.height - insets.top - insets.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: scrollable / 2 - insets.top), animated: false)
        await host.settle { progress.latest == 50 }

        #expect(progress.latest == 50, "reported \(String(describing: progress.latest))")
    }

    @Test
    func whileTheArticleLoadsThePageReportsNoPosition() async {
        let positions = PositionRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: nil, onReadingPositionChange: positions.record))
        defer { host.close() }

        await host.settle { false }

        #expect(!positions.reports.isEmpty)
        #expect(positions.reports.allSatisfy { $0 == nil })
    }

    @Test
    func onceTheArticleIsReadyThePageRestoresARequestedPlaceAndSaysSo() async {
        let restoration = RestorationRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: longArticle, restoringTo: 0.5, onRestored: restoration.finish))
        defer { host.close() }

        await host.settle { restoration.isFinished }

        #expect(restoration.isFinished)
    }

    @Test
    func aRestoreThatCannotMoveThePageStillReportsWhereTheReaderIs() async throws {
        let restoration = RestorationRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: "A short note.", restoringTo: 0.5, onRestored: restoration.finish))
        defer { host.close() }

        await host.settle { restoration.isFinished }

        #expect(try #require(restoration.position) >= 1)
    }

    @Test
    func aRestoreInterruptedBeforeItsScrollFinishesIsNotReportedAsRestored() async {
        let restoration = RestorationRecorder()
        let positions = PositionRecorder()
        let text = ArticleText(markdown: longArticle)
        let host = PageHost(ChangingPage(
            header: header,
            text: text,
            restoringTo: 0.5,
            onRestored: restoration.finish,
            onReadingPositionChange: positions.record
        ))
        defer { host.close() }
        await host.settle { positions.latest != nil }

        try? await Task.sleep(for: .milliseconds(150))
        text.markdown = nil
        await host.settle { restoration.isFinished }

        #expect(!restoration.isFinished)
    }

    @Test
    func replacingTheArticleTextReportsNoPositionUntilTheNewTextIsLaidOut() async {
        let positions = PositionRecorder()
        let text = ArticleText(markdown: longArticle)
        let host = PageHost(ChangingPage(header: header, text: text, onReadingPositionChange: positions.record))
        defer { host.close() }
        await host.settle { positions.latest != nil }

        text.markdown = nil
        await host.settle { positions.lastReportIsNoPosition }
        text.markdown = longArticle + "\n\nA refreshed closing paragraph."
        await host.settle { positions.latest != nil }

        #expect(positions.readiness.suffix(3) == [true, false, true])
    }

    @Test
    func whileTheArticleLoadsThePageDoesNotRestore() async {
        let restoration = RestorationRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: nil, restoringTo: 0.5, onRestored: restoration.finish))
        defer { host.close() }

        await host.settle { restoration.isFinished }

        #expect(!restoration.isFinished)
    }
}

@MainActor
@Observable
private final class ArticleText {
    var markdown: String?

    init(markdown: String?) {
        self.markdown = markdown
    }
}

private struct ChangingPage: View {
    let header: ReaderArticleHeader
    let text: ArticleText
    var restoringTo: Double? = nil
    var onRestored: (Double?) -> Void = { _ in }
    var onReadingPositionChange: (Double?) -> Void = { _ in }

    var body: some View {
        ReaderPage(
            header: header,
            markdown: text.markdown,
            restoringTo: restoringTo,
            onRestored: onRestored,
            onReadingPositionChange: onReadingPositionChange
        )
    }
}

@MainActor
private final class PositionRecorder {
    private(set) var reports: [Double?] = []

    var latest: Double? { reports.last ?? nil }

    var lastReportIsNoPosition: Bool {
        if case .some(.none) = reports.last { return true }
        return false
    }

    var readiness: [Bool] {
        reports.map { $0 != nil }.reduce(into: []) { changes, isReady in
            if changes.last != isReady { changes.append(isReady) }
        }
    }

    func record(_ position: Double?) {
        reports.append(position)
    }
}

@MainActor
private final class ProgressRecorder {
    private(set) var latest: Int?

    func record(_ percent: Int?) {
        latest = percent
    }
}

@MainActor
private final class RestorationRecorder {
    private(set) var isFinished = false
    private(set) var position: Double?

    func finish(at position: Double?) {
        isFinished = true
        self.position = position
    }
}
