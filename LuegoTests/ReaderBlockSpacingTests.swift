import SwiftUI
import Testing

@MainActor
struct ReaderBlockSpacingTests {
    init() {
        LoraTestFonts.register()
    }

    @Test
    func aHeadingInRunningTextHasTheGapBetweenParagraphs() throws {
        let frames = try renderedFrames(of: "First.\n\nSecond.\n\n## Heading\n\nThird.")
        let paragraphGap = try gap(from: "First.", to: "Second.", in: frames)
        let above = try gap(from: "Second.", to: "Heading", in: frames)
        let below = try gap(from: "Heading", to: "Third.", in: frames)

        #expect(abs(above - paragraphGap) < 1, "above \(above), between paragraphs \(paragraphGap)")
        #expect(abs(below - paragraphGap) < 1, "below \(below), between paragraphs \(paragraphGap)")
    }

    @Test
    func aSectionBreakInRunningTextHasTheSameGapsAsBetweenPhotos() throws {
        let betweenPhotos = try renderedFrames(of: "![Photo A](a.jpg)\n\n* * *\n\n![Photo B](b.jpg)")
        let inText = try renderedFrames(of: "Before.\n\n* * *\n\nAfter.")

        let photoGap = try gap(from: "Photo A", to: "Photo B", in: betweenPhotos)
        let textGap = try gap(from: "Before.", to: "After.", in: inText)
        #expect(abs(textGap - photoGap) < 1, "in text \(textGap), between photos \(photoGap)")
    }

    private func renderedFrames(of markdown: String) throws -> [String: CGRect] {
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let body = ReaderBlocksView(document: document, imageLoader: UnavailableImageLoader())
            .font(.lora(.body))
            .readerContentStyle()
        return accessibilityFrames(in: body, width: 390)
    }

    private func gap(from upper: String, to lower: String, in frames: [String: CGRect]) throws -> CGFloat {
        try #require(frames[lower]).minY - (try #require(frames[upper])).maxY
    }
}

struct UnavailableImageLoader: ReaderImageLoading {
    func image(for url: URL) async throws -> ReaderImage {
        throw URLError(.fileDoesNotExist)
    }
}
