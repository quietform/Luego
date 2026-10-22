import SwiftUI

struct DiscoveryListPane: View {
    let viewModel: DiscoveryListViewModel
    @Binding var selectedPost: DiscoveryPost?

    var body: some View {
        DiscoveryListView(viewModel: viewModel, selection: $selectedPost)
            .background(Color.regularPanelBackground)
            .appNavigationStyle(.contentLargeTitle)
            .navigationTitle(ArticleFilter.discovery.navigationTitle)
    }
}

struct DiscoveryDetailPane: View {
    let post: DiscoveryPost?

    var body: some View {
        Group {
            if let post {
                DiscoveryArticleDestination(post: post)
                    .id(post)
            } else {
                EmptyDiscoveryDetailView()
            }
        }
        .background(Color.regularPanelBackground)
    }
}

struct DiscoveryArticleDestination: View {
    let post: DiscoveryPost
    @Environment(\.diContainer) private var diContainer
    @State private var viewModel: DiscoveryArticleViewModel?

    var body: some View {
        Group {
            if let viewModel {
                DiscoveryArticleView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil, let diContainer {
                viewModel = diContainer.makeDiscoveryArticleViewModel(post: post)
            }
        }
    }
}

struct EmptyDiscoveryDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "No Post Selected",
            systemImage: ArticleFilter.discovery.icon,
            description: Text("Pick a post from the small web to start reading")
        )
    }
}
