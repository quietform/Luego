import SwiftUI

struct ArticleListActions: ViewModifier {
    let viewModel: ArticleListViewModel
    @Environment(\.diContainer) private var diContainer
    @State private var showingSettings = false

    func body(content: Content) -> some View {
        AddArticlePresenter(viewModel: viewModel) { addArticleButton in
            content
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        addArticleButton

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier(ReadingListAccessibilityID.settingsButton)
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            if let diContainer {
                NavigationStack {
                    SettingsView(viewModel: diContainer.makeSettingsViewModel())
                }
            }
        }
    }
}

extension View {
    func articleListActions(viewModel: ArticleListViewModel) -> some View {
        modifier(ArticleListActions(viewModel: viewModel))
    }
}
