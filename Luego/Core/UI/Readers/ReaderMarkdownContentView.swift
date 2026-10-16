import SwiftUI

struct ReaderMarkdownContentView: View {
    let markdown: String
    let title: String
    let baseURL: URL

    @State private var document: ReaderDocument?

    private var cleanedMarkdown: String {
        stripFirstH1FromMarkdown(markdown, matchingTitle: title)
    }

    var body: some View {
        Group {
            if let document {
                ReaderBlocksView(document: document)
            } else {
                Text(cleanedMarkdown)
            }
        }
        .readerContentStyle()
        .onChange(of: baseURL) {
            document = try? ReaderDocument(markdown: cleanedMarkdown, baseURL: baseURL)
        }
        .onChange(of: cleanedMarkdown, initial: true) {
            document = try? ReaderDocument(markdown: cleanedMarkdown, baseURL: baseURL)
        }
    }
}
