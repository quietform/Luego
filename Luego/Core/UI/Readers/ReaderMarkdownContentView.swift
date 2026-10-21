import SwiftUI

struct ReaderMarkdownContentView: View {
    let markdown: String
    let title: String
    let baseURL: URL
    var onPreparationChanged: (Bool) -> Void = { _ in }

    @State private var document: ReaderDocument?
    @State private var preparationFailed = false
    @State private var documentID = UUID()

    private var request: Request {
        Request(markdown: markdown, title: title, baseURL: baseURL)
    }

    var body: some View {
        Group {
            if let document {
                ReaderBlocksView(document: document)
                    .id(documentID)
                    .onAppear { onPreparationChanged(true) }
            } else if preparationFailed {
                Text(markdown)
                    .id(documentID)
                    .onAppear { onPreparationChanged(true) }
            } else {
                ProgressView()
            }
        }
        .readerContentStyle()
        .task(id: request) {
            onPreparationChanged(false)
            document = nil
            preparationFailed = false
            do {
                let prepared = try await ReaderDocument.prepare(markdown: markdown, title: title, baseURL: baseURL)
                try Task.checkCancellation()
                documentID = UUID()
                document = prepared
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                documentID = UUID()
                preparationFailed = true
            }
        }
    }

    private struct Request: Equatable {
        let markdown: String
        let title: String
        let baseURL: URL
    }
}
