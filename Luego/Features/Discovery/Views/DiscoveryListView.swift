import SwiftUI

struct DiscoveryListView: View {
    @Bindable var viewModel: DiscoveryListViewModel
    var selection: Binding<DiscoveryPost?>?
    let onShuffle: () -> Void
    @State private var feedsViewModel: DiscoveryFeedsViewModel?
    @Environment(\.diContainer) private var diContainer

    var body: some View {
        Group {
            if viewModel.hasNoFeedsOn {
                NoFeedsOnView(onEditFeeds: editFeeds)
            } else if !viewModel.posts.isEmpty {
                DiscoveryPostList(posts: viewModel.posts, selection: selection) {
                    await viewModel.refresh()
                }
            } else if let error = viewModel.errorMessage, !viewModel.isLoading {
                DiscoveryListErrorView(message: error) {
                    Task { await viewModel.refresh() }
                }
            } else {
                DiscoveryLoadingView(loadingText: "Finding something interesting…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadPosts()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: editFeeds) {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit Feeds")
                .accessibilityIdentifier("discovery.editFeeds")

                Button("Surprise Me", systemImage: "die.face.5", action: onShuffle)
                    .labelStyle(.iconOnly)
                    .disabled(!viewModel.canShuffle(excluding: selection?.wrappedValue))
                    .accessibilityIdentifier("discovery.shuffle")

                SettingsToolbarButton()
            }
        }
        .sheet(item: $feedsViewModel) { feedsViewModel in
            NavigationStack {
                DiscoveryFeedsView(viewModel: feedsViewModel)
            }
        }
    }

    private func editFeeds() {
        feedsViewModel = diContainer?.makeDiscoveryFeedsViewModel()
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

struct NoFeedsOnView: View {
    let onEditFeeds: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Feeds On", systemImage: "dot.radiowaves.up.forward")
        } description: {
            Text("Turn on a feed to see posts here")
        } actions: {
            Button("Edit Feeds", action: onEditFeeds)
                .buttonStyle(.borderedProminent)
        }
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
