import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderSelectionTests {
    @Test
    func neighbouringParagraphsAndHeadingsAreOneSelection() async throws {
        let expected = ["First paragraph.A headingSecond paragraph."]
        let document = try ReaderDocument(
            markdown: "First paragraph.\n\n## A heading\n\nSecond paragraph.",
            baseURL: URL(string: "https://example.com")!
        )
        let host = PageHost(ReaderBlocksView(document: document).readerContentStyle())
        defer { host.close() }

        await host.settle { selectableTexts(in: host.view) == expected }

        #expect(selectableTexts(in: host.view) == expected)
    }

    @Test
    func tappingOutsideEveryPassageClearsTheirSelections() async throws {
        let (host, passages) = try await selectAllText(in: "First passage.\n\n![A photo](photo.jpg)\n\nSecond passage.")
        defer { host.close() }

        ReaderTextSelection.dismiss(in: host.view, keepingSelectionAt: point(between: passages[0], and: passages[1], in: host.view))

        #expect(passages.allSatisfy { $0.selectedTextRange == nil })
    }

    @Test
    func tappingInsideAPassageLeavesItsOwnSelectionToIt() async throws {
        let (host, passages) = try await selectAllText(in: "First passage.\n\n![A photo](photo.jpg)\n\nSecond passage.")
        defer { host.close() }
        let first = try #require(passages[0] as? UIView)

        ReaderTextSelection.dismiss(in: host.view, keepingSelectionAt: first.convert(CGPoint(x: first.bounds.midX, y: first.bounds.midY), to: host.view))

        #expect(passages[0].selectedTextRange != nil)
        #expect(passages[1].selectedTextRange == nil)
    }

    @Test
    func aRangeUIKitKeptFromBeforeAReflowMeasuresAsEmpty() async throws {
        let paragraphs = (1...6)
            .map { "Paragraph \($0) wraps across several lines at a phone's width, so a wider window needs fewer of them." }
        let document = try ReaderDocument(markdown: paragraphs.joined(separator: "\n\n"), baseURL: URL(string: "https://example.com")!)
        let host = PageHost(ReaderBlocksView(document: document).readerContentStyle())
        defer { host.close() }
        await host.settle { selectableTexts(in: host.view) == [paragraphs.joined()] }
        let passage = try #require(textInputs(in: host.view).first)
        let passageView = try #require(passage as? UIView)
        let everything = try #require(passage.textRange(from: passage.beginningOfDocument, to: passage.endOfDocument))
        try #require(passage.offset(from: everything.start, to: everything.end) > 0)
        passage.selectedTextRange = everything

        host.resize(width: 1_000)
        await host.settle {
            passageView.bounds.width > 900 && passage.compare(passage.endOfDocument, to: everything.end) != .orderedSame
        }
        try #require(passage.compare(passage.endOfDocument, to: everything.end) != .orderedSame)

        #expect(passage.offset(from: everything.start, to: everything.end) == 0)
    }

    /// Hosts the article and selects all the text in each of its passages.
    private func selectAllText(in markdown: String) async throws -> (PageHost, [UITextInput]) {
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let host = PageHost(ReaderBlocksView(document: document, imageLoader: UnavailableImageLoader()).readerContentStyle())
        await host.settle { textInputs(in: host.view).count == 2 }
        let passages = textInputs(in: host.view)
        try #require(passages.count == 2)
        for passage in passages {
            passage.selectedTextRange = passage.textRange(from: passage.beginningOfDocument, to: passage.endOfDocument)
        }
        try #require(passages.allSatisfy { $0.selectedTextRange != nil })
        return (host, passages)
    }

    private func point(between upper: UITextInput, and lower: UITextInput, in root: UIView) -> CGPoint {
        let upperFrame = (upper as! UIView).convert((upper as! UIView).bounds, to: root)
        let lowerFrame = (lower as! UIView).convert((lower as! UIView).bounds, to: root)
        return CGPoint(x: upperFrame.midX, y: (upperFrame.maxY + lowerFrame.minY) / 2)
    }

    /// The text each independent selection surface in the view can select.
    private func selectableTexts(in view: UIView) -> [String] {
        textInputs(in: view).compactMap { input in
            input.textRange(from: input.beginningOfDocument, to: input.endOfDocument).flatMap(input.text(in:))
        }
    }

    private func textInputs(in view: UIView) -> [UITextInput] {
        (view as? UITextInput).map { [$0] } ?? view.subviews.flatMap(textInputs(in:))
    }
}
