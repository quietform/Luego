//
//  ContentView.swift
//  Luego
//
//  Created by Arun Sasidharan on 10/11/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.diContainer) private var diContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedFilter: ArticleFilter = .readingList
    @State private var selectedArticle: Article?
    @State private var selectedTab = 0
    @State private var shouldAnimateHomeEmptyStateOnLaunch = true
    @State private var iPhoneTabBarVisibilityController = IPhoneTabBarVisibilityController()
    @State private var articleListViewModel: ArticleListViewModel?
    @State private var readingListPath: [Article] = []
    @State private var favoritesPath: [Article] = []
    @State private var archivedPath: [Article] = []
    @State private var discoveryListViewModel: DiscoveryListViewModel?
    @State private var discoveryPath: [DiscoveryPost] = []
    @State private var selectedDiscoveryPost: DiscoveryPost?
    @State private var pendingDeepLink: ArticleDeepLink?
    @State private var deepLinkAlert: DeepLinkAlert?

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            Group {
                if let articleListViewModel {
                    if horizontalSizeClass == .regular {
                        iPadLayout(viewModel: articleListViewModel)
                    } else {
                        iPhoneLayout(viewModel: articleListViewModel)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .font(.app(.body))
        .task {
            initializeArticleListViewModelIfNeeded()
            await handleScenePhaseChange(scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await handleScenePhaseChange(newPhase)
            }
        }
        .onOpenURL { url in
            Task {
                await handleIncomingURL(url)
            }
        }
        .alert("Unable to Open Article", isPresented: deepLinkAlertIsPresentedBinding) {
            Button("OK", role: .cancel) {
                deepLinkAlert = nil
            }
        } message: {
            Text(deepLinkAlert?.message ?? "")
        }
    }

    @ViewBuilder
    private func iPadLayout(viewModel: ArticleListViewModel) -> some View {
        if selectedFilter == .discovery, let discoveryListViewModel {
            NavigationSplitView {
                SidebarView(selection: $selectedFilter)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } content: {
                DiscoveryListPane(viewModel: discoveryListViewModel, selectedPost: $selectedDiscoveryPost)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
            } detail: {
                DiscoveryDetailPane(post: selectedDiscoveryPost)
                    .navigationSplitViewColumnWidth(min: 500, ideal: 500)
            }
            .tint(Color.regularSelectionInk)
            .appNavigationChrome()
        } else {
            NavigationSplitView {
                SidebarView(selection: $selectedFilter)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } content: {
                ArticleListPane(
                    viewModel: viewModel,
                    filter: selectedFilter,
                    selectedArticle: $selectedArticle,
                    onDiscover: { selectedFilter = .discovery },
                    shouldAnimateEmptyStateOnFirstAppearance: shouldAnimateHomeEmptyStateOnLaunch,
                    onEmptyStateAnimationConsumed: { shouldAnimateHomeEmptyStateOnLaunch = false }
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
            } detail: {
                DetailPane(article: selectedArticle)
                    .navigationSplitViewColumnWidth(min: 500, ideal: 500)
            }
            .tint(Color.regularSelectionInk)
            .appNavigationChrome()
        }
    }

    private func iPhoneLayout(viewModel: ArticleListViewModel) -> some View {
        TabView(selection: $selectedTab) {
            Tab(ArticleFilter.discovery.navigationTitle, systemImage: ArticleFilter.discovery.icon, value: 3) {
                iPhoneTabBackground {
                    if let discoveryListViewModel {
                        iPhoneDiscoveryNavigationStack(viewModel: discoveryListViewModel)
                    }
                }
            }

            Tab(ArticleFilter.readingList.navigationTitle, systemImage: "list.bullet", value: 0) {
                iPhoneTabBackground {
                    iPhoneTabNavigationStack(for: .readingList, path: $readingListPath) {
                        ArticleListView(
                            viewModel: viewModel,
                            filter: .readingList,
                            shouldAnimateEmptyStateOnFirstAppearance: shouldAnimateHomeEmptyStateOnLaunch,
                            onEmptyStateAnimationConsumed: { shouldAnimateHomeEmptyStateOnLaunch = false },
                            onDiscover: { selectedTab = tabSelection(for: .discovery) }
                        )
                    }
                }
            }

            Tab(ArticleFilter.favorites.navigationTitle, systemImage: "heart", value: 1) {
                iPhoneTabBackground {
                    iPhoneTabNavigationStack(for: .favorites, path: $favoritesPath) {
                        ArticleListView(viewModel: viewModel, filter: .favorites)
                    }
                }
            }

            Tab(ArticleFilter.archived.navigationTitle, systemImage: "archivebox.fill", value: 2) {
                iPhoneTabBackground {
                    iPhoneTabNavigationStack(for: .archived, path: $archivedPath) {
                        ArticleListView(viewModel: viewModel, filter: .archived)
                    }
                }
            }
        }
        .environment(\.iPhoneTabBarVisibilityController, iPhoneTabBarVisibilityController)
        .safeAreaInset(edge: .bottom) {
            if iPhoneTabBarVisibilityController.isVisible {
                iPhoneTabBar
            }
        }
    }

    private func iPhoneTabBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            content()
        }
    }

    private func iPhoneTabNavigationStack<Content: View>(
        for filter: ArticleFilter,
        path: Binding<[Article]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: Article.self) { article in
                    ArticleReaderDestination(article: article, diContainer: diContainer)
                }
        }
        .id(filter)
        .toolbar(.hidden, for: .tabBar)
    }

    private func iPhoneDiscoveryNavigationStack(viewModel: DiscoveryListViewModel) -> some View {
        NavigationStack(path: $discoveryPath) {
            DiscoveryListView(viewModel: viewModel)
                .background(Color.appBackground)
                .navigationTitle(ArticleFilter.discovery.navigationTitle)
                .appNavigationStyle(.largeTransparent)
                .navigationDestination(for: DiscoveryPost.self) { post in
                    DiscoveryArticleDestination(post: post)
                }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var iPhoneTabBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                iPhoneTabButton(systemImage: ArticleFilter.discovery.icon, label: ArticleFilter.discovery.navigationTitle, tab: 3)
                iPhoneTabButton(systemImage: "list.bullet", label: "Reading List", tab: 0)
                iPhoneTabButton(systemImage: "heart.fill", label: "Favorites", tab: 1)
                iPhoneTabButton(systemImage: "archivebox.fill", label: "Archived", tab: 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func iPhoneTabButton(systemImage: String, label: String, tab: Int) -> some View {
        let isSelected = selectedTab == tab

        if isSelected {
            Button {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.05)) {
                    selectedTab = tab
                }
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.barAccentInk)
            }
            .tint(Color.barAccentFill)
            .buttonStyle(.glassProminent)
            .contentShape(Capsule())
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.05)) {
                    selectedTab = tab
                }
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.primary.opacity(0.82))
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .accessibilityLabel(label)
            .accessibilityRemoveTraits(.isSelected)
        }
    }

    private func initializeArticleListViewModelIfNeeded() {
        if discoveryListViewModel == nil, let diContainer {
            discoveryListViewModel = diContainer.makeDiscoveryListViewModel()
        }

        if articleListViewModel == nil, let diContainer {
            articleListViewModel = diContainer.makeArticleListViewModel()
            if let pendingDeepLink {
                Task {
                    await handleDeepLink(pendingDeepLink)
                }
            }
        }

        articleListViewModel?.startObservingArticles()
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) async {
        initializeArticleListViewModelIfNeeded()
        guard phase == .active, let articleListViewModel else { return }
        await articleListViewModel.refreshOnForeground()
    }

    private func handleIncomingURL(_ url: URL) async {
        Logger.sharing.info("Received incoming URL: \(url.absoluteString)")
        do {
            let deepLink = try ArticleDeepLink(url: url)
            Logger.sharing.info("Parsed incoming article deep link")
            if articleListViewModel == nil {
                Logger.sharing.info("Article list view model not ready; storing pending deep link")
                pendingDeepLink = deepLink
                initializeArticleListViewModelIfNeeded()
                return
            }
            await handleDeepLink(deepLink)
        } catch {
            Logger.sharing.error("Failed to parse incoming URL \(url.absoluteString): \(error.localizedDescription)")
            presentDeepLinkError(error)
        }
    }

    private func handleDeepLink(_ deepLink: ArticleDeepLink) async {
        guard let articleListViewModel else {
            Logger.sharing.warning("Article list view model missing while handling deep link; leaving it pending")
            pendingDeepLink = deepLink
            return
        }

        pendingDeepLink = nil

        do {
            switch deepLink {
            case .article(let url):
                Logger.sharing.info("Handling article deep link for URL: \(url.absoluteString)")
                let article = try await articleListViewModel.openOrImportArticle(from: url)
                Logger.sharing.info("Deep link resolved article: \(article.url.absoluteString)")
                openArticle(article)
            }
        } catch {
            Logger.sharing.error("Failed to handle deep link: \(error.localizedDescription)")
            presentDeepLinkError(error)
        }
    }

    private func openArticle(_ article: Article) {
        let filter = preferredFilter(for: article)
        Logger.sharing.info("Opening article in UI: \(article.url.absoluteString) with filter \(filter.navigationTitle)")

        selectedFilter = filter
        selectedArticle = article

        guard horizontalSizeClass != .regular else {
            return
        }

        selectedTab = tabSelection(for: filter)

        switch filter {
        case .readingList:
            readingListPath.removeAll()
            readingListPath.append(article)
        case .favorites:
            favoritesPath.removeAll()
            favoritesPath.append(article)
        case .archived:
            archivedPath.removeAll()
            archivedPath.append(article)
        case .discovery:
            break
        }
    }

    private func presentDeepLinkError(_ error: Error) {
        Logger.sharing.error("Presenting deep link error: \(error.localizedDescription)")
        deepLinkAlert = DeepLinkAlert(message: error.localizedDescription)
    }

    private func preferredFilter(for article: Article) -> ArticleFilter {
        if article.isArchived {
            return .archived
        }

        if article.isFavorite {
            return .favorites
        }

        return .readingList
    }

    private func tabSelection(for filter: ArticleFilter) -> Int {
        switch filter {
        case .readingList:
            return 0
        case .favorites:
            return 1
        case .archived:
            return 2
        case .discovery:
            return 3
        }
    }

    private var deepLinkAlertIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                deepLinkAlert != nil
            },
            set: { isPresented in
                if !isPresented {
                    deepLinkAlert = nil
                }
            }
        )
    }
}

private struct DeepLinkAlert: Identifiable {
    let id = UUID()
    let message: String
}
