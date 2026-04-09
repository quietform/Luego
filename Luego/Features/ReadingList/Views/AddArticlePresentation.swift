import SwiftUI

struct AddArticlePresenter<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingAddArticle = false
    let viewModel: ArticleListViewModel
    @ViewBuilder let content: (AddArticleToolbarButton) -> Content

    var body: some View {
        content(
            AddArticleToolbarButton(
                isPresented: $showingAddArticle,
                destination: addArticleDestination
            )
        )
    }

    private var addArticleDestination: AddArticleDestination {
        AddArticleDestination(
            viewModel: viewModel,
            preferredWidth: horizontalSizeClass == .compact ? 360 : 420
        )
    }
}

struct AddArticleToolbarButton: View {
    @Binding var isPresented: Bool
    let destination: AddArticleDestination

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier(ReadingListAccessibilityID.addButton)
        #if os(iOS)
        .popover(
            isPresented: popoverBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            destination
        }
        #endif
    }

    private var popoverBinding: Binding<Bool> {
        Binding(
            get: {
                isPresented
            },
            set: { newValue in
                isPresented = newValue
            }
        )
    }
}

struct AddArticleDestination: View {
    let viewModel: ArticleListViewModel
    let preferredWidth: CGFloat?

    var body: some View {
        NavigationStack {
            AddArticleView(viewModel: viewModel)
                .frame(width: preferredWidth, alignment: .topLeading)
        }
        .tint(Color.regularSelectionInk)
        .background(Color.regularPanelBackground)
        .appNavigationChrome()
        .presentationCompactAdaptation(.popover)
    }
}
