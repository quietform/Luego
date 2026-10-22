import SwiftUI

struct DiscoveryListView: View {
    @Bindable var viewModel: DiscoveryListViewModel
    var selection: Binding<DiscoveryPost?>?
    @State private var loadingGif = KagiLoadingGifRotator.next()

    var body: some View {
        Group {
            if !viewModel.posts.isEmpty {
                DiscoveryPostList(posts: viewModel.posts, selection: selection) {
                    await viewModel.loadPosts()
                }
            } else if let error = viewModel.errorMessage, !viewModel.isLoading {
                DiscoveryListErrorView(message: error) {
                    Task { await viewModel.loadPosts() }
                }
            } else {
                KagiSmallWebLoadingView(
                    pendingURL: nil,
                    gifName: loadingGif,
                    loadingText: "Finding something interesting..."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadPosts()
            }
        }
    }
}

struct DiscoveryPostList: View {
    let posts: [DiscoveryPost]
    let selection: Binding<DiscoveryPost?>?
    let onRefresh: () async -> Void

    var body: some View {
        List(posts) { post in
            if let selection {
                Button {
                    selection.wrappedValue = post
                } label: {
                    DiscoveryPostRow(post: post, isSelected: selection.wrappedValue == post)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(selectionBackground(isSelected: selection.wrappedValue == post))
            } else {
                NavigationLink(value: post) {
                    DiscoveryPostRow(post: post)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await onRefresh()
        }
    }

    private func selectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? Color.regularSelectionFill : Color.clear)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
    }
}

struct DiscoveryListErrorView: View {
    let message: String
    let onTryAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not load posts", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: onTryAgain)
                .buttonStyle(.borderedProminent)
        }
    }
}
