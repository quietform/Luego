import SwiftUI

struct ArticleListActions: ViewModifier {
    let viewModel: ArticleListViewModel

    func body(content: Content) -> some View {
        AddArticlePresenter(viewModel: viewModel) { addArticleButton in
            content
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        addArticleButton
                        SettingsToolbarButton()
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
