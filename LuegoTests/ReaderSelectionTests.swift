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
