import SwiftUI
import Testing

@MainActor
struct ReaderArticleHeaderTests {
    private let url = URL(string: "https://ratik.in/cmon/16")!

    init() {
        LoraTestFonts.register()
    }

    @Test(arguments: [
        (String?.some("8 Nov 2026"), Int?.some(4), ["Organising a Conference", "ratik.in", "8 Nov 2026 · 4 min read"]),
        (.some("8 Nov 2026"), .none, ["Organising a Conference", "ratik.in", "8 Nov 2026"]),
        (.none, .some(4), ["Organising a Conference", "ratik.in", "4 min read"]),
        (.none, .none, ["Organising a Conference", "ratik.in"])
    ])
    func voiceOverHearsTheTitleSourceAndWhateverDetailsAreKnown(date: String?, readingMinutes: Int?, labels: [String]) {
        let header = ReaderArticleHeader(title: "Organising a Conference", source: "ratik.in", url: url, date: date, readingMinutes: readingMinutes)

        #expect(accessibilityLabels(in: header) == labels)
    }

    @Test(arguments: [
        ("ratik.in", false),
        ("newsletter.pragmaticengineer.com", true)
    ])
    func detailsMoveBelowASourceTooLongToShareTheirLine(source: String, detailsBelowSource: Bool) throws {
        let header = ReaderArticleHeader(title: "Organising a Conference", source: source, url: url, date: "8 Nov 2026", readingMinutes: 4)

        let frames = accessibilityFrames(in: header, width: 310)
        let sourceFrame = try #require(frames[source])
        let detailsFrame = try #require(frames["8 Nov 2026 · 4 min read"])
        #expect((detailsFrame.minY >= sourceFrame.maxY) == detailsBelowSource)
    }
}
