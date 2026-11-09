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
    func whileTheArticleLoadsThePageDoesNotRestore() async {
        let restoration = RestorationRecorder()
        let host = PageHost(ReaderPage(header: header, markdown: nil, restoringTo: 0.5, onRestored: restoration.finish))
        defer { host.close() }

        await host.settle { restoration.isFinished }

        #expect(!restoration.isFinished)
    }
}

@MainActor
private final class PositionRecorder {
    private(set) var reports: [Double?] = []

    var latest: Double? { reports.last ?? nil }

    func record(_ position: Double?) {
        reports.append(position)
    }
}

@MainActor
private final class RestorationRecorder {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

@MainActor
private final class PageHost {
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    private let controller: UIHostingController<AnyView>

    init(_ page: some View) {
        controller = UIHostingController(rootView: AnyView(page))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    var scrollView: UIScrollView? { Self.scrollView(in: controller.view) }

    var visibleBottom: Double? {
        guard let scroll = scrollView, scroll.contentSize.height > 0 else { return nil }
        return (scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom) / scroll.contentSize.height
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
        }
    }

    func close() {
        window.isHidden = true
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(scrollView).first
    }
}
