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

    @Test(arguments: ["ratik.in", "newsletter.pragmaticengineer.com"])
    func detailsHaveTheirOwnLineBelowTheSource(source: String) throws {
        let header = ReaderArticleHeader(title: "Organising a Conference", source: source, url: url, date: "8 Nov 2026", readingMinutes: 4)

        let frames = accessibilityFrames(in: header, width: 310)
        let sourceFrame = try #require(frames[source])
        let detailsFrame = try #require(frames["8 Nov 2026 · 4 min read"])
        #expect(detailsFrame.minY >= sourceFrame.maxY)
    }

    @Test(arguments: [String?.none, .some("8 Nov 2026")], [CGFloat(310), 700])
    func loadingMetadataDoesNotMoveTheArticleBody(initialDate: String?, width: CGFloat) throws {
        func bodyPosition(date: String?, readingMinutes: Int?) throws -> CGRect {
            let view = VStack(alignment: .leading, spacing: 20) {
                ReaderArticleHeader(
                    title: "Organising a Conference",
                    source: "pragmaticengineer.com",
                    url: url,
                    date: date,
                    readingMinutes: readingMinutes
                )
                Text("Article body")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.lora(.body))
            .frame(height: 800, alignment: .topLeading)
            return try #require(accessibilityFrames(in: view, width: width)["Article body"])
        }

        let loading = try bodyPosition(date: initialDate, readingMinutes: nil)
        let loaded = try bodyPosition(date: "8 Nov 2026", readingMinutes: 4)

        #expect(abs(loaded.minX - loading.minX) < 1, "Loading: \(loading), loaded: \(loaded)")
        #expect(abs(loaded.minY - loading.minY) < 1, "Loading: \(loading), loaded: \(loaded)")
    }

    @Test(arguments: [CGFloat(310), 700])
    func replacingTheLoaderWithAShortArticleKeepsTheLeadingMargin(width: CGFloat) throws {
        let document = try ReaderDocument(markdown: "A short paragraph.", baseURL: url)
        func frames(loading: Bool) -> [String: CGRect] {
            let view = VStack(alignment: .leading, spacing: 20) {
                ReaderArticleHeader(title: "A Note", source: "ratik.in", url: url, date: "8 Nov 2026", readingMinutes: 1)
                if loading {
                    ReaderBodyPlaceholder()
                } else {
                    ReaderBlocksView(document: document)
                        .readerContentStyle()
                }
            }
            .font(.lora(.body))
            .frame(maxWidth: .infinity)
            .frame(height: 800, alignment: .topLeading)
            return accessibilityFrames(in: view, width: width)
        }

        let loading = try #require(frames(loading: true)["A Note"])
        let loaded = try #require(frames(loading: false)["A Note"])

        #expect(abs(loaded.minX - loading.minX) < 1, "Loading: \(loading), loaded: \(loaded)")
        #expect(abs(loaded.minY - loading.minY) < 1, "Loading: \(loading), loaded: \(loaded)")
    }
}
