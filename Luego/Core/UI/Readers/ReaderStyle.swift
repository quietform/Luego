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
        let headingStyle = ReaderHeadingStyle()
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

    struct ReaderHeadingStyle: HeadingStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .textual.fontScale(fontScale(forLevel: configuration.headingLevel))
                .textual.lineSpacing(.fontScaled(0.125))
                .fontWeight(configuration.headingLevel <= 2 ? .regular : .semibold)
                .textual.blockSpacing(.init(top: 32, bottom: 8))
        }

        private func fontScale(forLevel level: Int) -> CGFloat {
            switch level {
            case ...1: 1.75
            case 2: 1.5
            case 3: 1.15
            case 4: 1.05
            default: 1
            }
        }
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
