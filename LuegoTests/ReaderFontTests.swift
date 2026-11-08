import SwiftUI
import Testing

@MainActor
struct ReaderFontTests {
    private let paragraph = "one one one one one one one one one one one one"

    init() {
        LoraTestFonts.register()
    }

    @Test
    func boldWordsInsideAParagraphKeepTheBodySize() throws {
        let regular = try renderedReaderWidth(of: paragraph)
        let withBoldWords = try renderedReaderWidth(of: "one one one one **one one one one** one one one one")

        #expect(withBoldWords > regular, "With bold words: \(withBoldWords), regular: \(regular)")
        #expect(withBoldWords < regular * 1.2, "With bold words: \(withBoldWords), regular: \(regular)")
    }

    @Test
    func emphasizedWordsUseTheLoraItalicFace() throws {
        let regular = try renderedReaderWidth(of: paragraph)
        let withItalicWords = try renderedReaderWidth(of: "one one one one _one one one one_ one one one one")

        #expect(withItalicWords < regular, "With italic words: \(withItalicWords), regular: \(regular)")
        #expect(withItalicWords > regular * 0.8, "With italic words: \(withItalicWords), regular: \(regular)")
    }

    private func renderedReaderWidth(of markdown: String) throws -> CGFloat {
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        return renderedWidth(of: ReaderBlocksView(document: document).font(.lora(.body)).readerContentStyle())
    }
}
