import SwiftUI
import Textual

extension View {
    func readerContentStyle() -> some View {
        self
            .textual.structuredTextStyle(.reader)
            .textual.imageAttachmentLoader(ReaderImageLoader())
            .textual.textSelection(.enabled)
    }
}

extension StructuredText.Style where Self == StructuredText.ReaderStyle {
    static var reader: Self { .init() }
}

extension StructuredText {
    struct ReaderStyle: Style {
        let inlineStyle: InlineStyle = .gitHub
        let headingStyle: GitHubHeadingStyle = .gitHub
        let paragraphStyle: GitHubParagraphStyle = .gitHub
        let blockQuoteStyle: GitHubBlockQuoteStyle = .gitHub
        let codeBlockStyle: GitHubCodeBlockStyle = .gitHub
        let listItemStyle: DefaultListItemStyle = .default
        let unorderedListMarker: HierarchicalSymbolListMarker = .hierarchical(.disc, .circle, .square)
        let orderedListMarker: DecimalListMarker = .decimal
        let tableStyle: GitHubTableStyle = .gitHub
        let tableCellStyle: GitHubTableCellStyle = .gitHub
        let thematicBreakStyle = ReaderSectionBreakStyle()
    }

    struct ReaderSectionBreakStyle: ThematicBreakStyle {
        func makeBody(configuration _: Configuration) -> some View {
            Text(verbatim: "·\u{2002}·\u{2002}·")
                .font(.lora(.title))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .textual.blockSpacing(.init(top: 12, bottom: 12))
        }
    }
}
