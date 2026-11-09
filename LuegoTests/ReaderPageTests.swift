import SwiftUI
import Testing

@MainActor
struct ReaderPageTests {
    private let header = ReaderArticleHeader(
        title: "Organising a Conference",
        source: "ratik.in",
        url: URL(string: "https://ratik.in/cmon/16")!,
        date: "8 Nov 2026",
        readingMinutes: 4
    )

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
    func aPositionTrackerIsGivenThePagesViewport() {
        let tracker = TrackerRecorder()
        let page = ReaderPage(header: header, markdown: nil, onPreparationChanged: { _, _ in }) { scroll in
            Color.clear.onAppear { tracker.viewportHeight = scroll.viewportHeight }
        }

        _ = accessibilityLabels(in: page.frame(height: 600))

        #expect(tracker.viewportHeight == 600)
    }
}

@MainActor
private final class TrackerRecorder {
    var viewportHeight: CGFloat?
}
