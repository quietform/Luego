import SwiftUI

struct DetailPane: View {
    let article: Article?
    @Environment(\.diContainer) private var diContainer
    @State private var readerViewModel: ReaderViewModel?

    var body: some View {
        Group {
            if let article = article {
                readerContent(for: article)
            } else {
                EmptyDetailView()
            }
        }
        .background(Color.regularPanelBackground)
        .onChange(of: article?.id) { _, _ in
            if let newArticle = article, let container = diContainer {
                readerViewModel = container.makeReaderViewModel(article: newArticle)
            } else {
                readerViewModel = nil
            }
        }
        .task {
            if let article = article, readerViewModel == nil, let container = diContainer {
                readerViewModel = container.makeReaderViewModel(article: article)
            }
        }
    }

    @ViewBuilder
    private func readerContent(for article: Article) -> some View {
        if let vm = readerViewModel {
            ReaderView(viewModel: vm)
                .id(vm.article.id)
        } else {
            ProgressView()
        }
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.regularSelectionFill)
                    .frame(width: 92, height: 92)

                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.regularSelectionInk)
            }

            VStack(spacing: 8) {
                Text("No Article Selected")
                    .font(.app(.emptyStateTitle))

                Text("Select an article to start reading")
                    .font(.app(.emptyStateBody))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color.regularPanelBackground)
    }
}
