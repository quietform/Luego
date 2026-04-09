import SwiftUI

struct ArticleListView: View {
    @Environment(\.diContainer) private var diContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var discoveryViewModel: DiscoveryViewModel?
    @State private var showingDiscovery = false
    @State private var showingSettings = false
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    let shouldAnimateEmptyStateOnFirstAppearance: Bool
    let onEmptyStateAnimationConsumed: () -> Void

    private var filteredArticles: [Article] {
        viewModel.filteredArticles(for: filter)
    }

    init(
        viewModel: ArticleListViewModel,
        filter: ArticleFilter,
        shouldAnimateEmptyStateOnFirstAppearance: Bool = false,
        onEmptyStateAnimationConsumed: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.filter = filter
        self.shouldAnimateEmptyStateOnFirstAppearance = shouldAnimateEmptyStateOnFirstAppearance
        self.onEmptyStateAnimationConsumed = onEmptyStateAnimationConsumed
    }

    var body: some View {
        AddArticlePresenter(viewModel: viewModel) { addArticleButton in
            ArticleListContent(
                articles: filteredArticles,
                viewModel: viewModel,
                diContainer: diContainer,
                filter: filter,
                onDiscover: { showingDiscovery = true },
                shouldAnimateEmptyStateOnFirstAppearance: shouldAnimateEmptyStateOnFirstAppearance,
                onEmptyStateAnimationConsumed: onEmptyStateAnimationConsumed
            )
            .navigationTitle(navigationTitle)
            .appNavigationStyle(horizontalSizeClass == .compact ? .largeTransparent : .largePanel)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if filter == .readingList {
                        Button {
                            showingDiscovery = true
                        } label: {
                            Image(systemName: "die.face.5")
                        }
                        .accessibilityIdentifier(ReadingListAccessibilityID.discoverButton)
                        .accessibilityLabel("Inspire Me")
                    }

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
            if let container = diContainer {
                NavigationStack {
                    SettingsView(viewModel: container.makeSettingsViewModel())
                }
            }
        }
        .fullScreenCover(isPresented: $showingDiscovery) {
            if let vm = discoveryViewModel {
                DiscoveryReaderView(viewModel: vm)
            }
        }
        .onChange(of: showingDiscovery) { _, isShowing in
            if isShowing, discoveryViewModel == nil, let container = diContainer {
                discoveryViewModel = container.makeDiscoveryViewModel()
            } else if !isShowing {
                discoveryViewModel = nil
            }
        }
    }

    private var navigationTitle: String {
        if horizontalSizeClass == .compact {
            return filter.navigationTitle
        }

        return filter.title
    }
}

struct ArticleListContent: View {
    let articles: [Article]
    let viewModel: ArticleListViewModel
    let diContainer: DIContainer?
    let filter: ArticleFilter
    let onDiscover: () -> Void
    let shouldAnimateEmptyStateOnFirstAppearance: Bool
    let onEmptyStateAnimationConsumed: () -> Void
    @Environment(SyncStatusObserver.self) private var syncStatusObserver

    private var restoreStatusText: String? {
        guard filter == .readingList, syncStatusObserver.state == .restoring else { return nil }
        return "Restoring articles from iCloud."
    }

    var body: some View {
        Group {
            if articles.isEmpty {
                emptyState(for: viewModel)
            } else {
                ArticleList(
                    articles: articles,
                    viewModel: viewModel,
                    diContainer: diContainer,
                    filter: filter,
                    onRefresh: { await viewModel.refreshArticles() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    @ViewBuilder
    private func emptyState(for viewModel: ArticleListViewModel) -> some View {
        let content = ArticleListEmptyState(
            onDiscover: onDiscover,
            filter: filter,
            restoreStatusText: restoreStatusText,
            shouldAnimateCopyOnFirstAppearance: filter == .readingList && shouldAnimateEmptyStateOnFirstAppearance,
            onCopyAnimationConsumed: onEmptyStateAnimationConsumed
        )

        RefreshableEmptyStateContainer(onRefresh: { await viewModel.refreshArticles() }) {
            content
        }
    }
}

struct ArticleList: View {
    let articles: [Article]
    let viewModel: ArticleListViewModel
    let diContainer: DIContainer?
    let filter: ArticleFilter
    let onRefresh: () async -> Void

    private var swipeActions: ArticleSwipeActions {
        ArticleSwipeActions(filter: filter, viewModel: viewModel)
    }

    var body: some View {
        List {
            ForEach(articles) { article in
                NavigationLink(value: article) {
                    ArticleRowView(article: article)
                }
                .accessibilityIdentifier(ReadingListAccessibilityID.open(article))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    swipeActions.favoriteButton(for: article)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeActions.archiveButton(for: article)
                    swipeActions.deleteButton(for: article)
                }
            }
        }
        .id(filter)
        .accessibilityIdentifier(ReadingListAccessibilityID.list(filter))
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .refreshable {
            await onRefresh()
        }
        #endif
    }
}

struct ArticleReaderDestination: View {
    let article: Article
    let diContainer: DIContainer?

    var body: some View {
        if let container = diContainer {
            let readerViewModel = container.makeReaderViewModel(article: article)
            ReaderView(viewModel: readerViewModel)
        }
    }
}

struct ArticleListEmptyState: View {
    let onDiscover: () -> Void
    let filter: ArticleFilter
    let restoreStatusText: String?
    let onCopyAnimationConsumed: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var shouldAnimateCopy: Bool
    @State private var hasConsumedLaunchAnimation = false

    init(
        onDiscover: @escaping () -> Void,
        filter: ArticleFilter,
        restoreStatusText: String? = nil,
        shouldAnimateCopyOnFirstAppearance: Bool = false,
        onCopyAnimationConsumed: @escaping () -> Void = {}
    ) {
        self.onDiscover = onDiscover
        self.filter = filter
        self.restoreStatusText = restoreStatusText
        self.onCopyAnimationConsumed = onCopyAnimationConsumed
        _shouldAnimateCopy = State(initialValue: shouldAnimateCopyOnFirstAppearance)
    }

    @ViewBuilder
    private var artwork: some View {
        if filter == .readingList {
            ZStack {
                Circle()
                    .fill(Color.paperCream)

                Image("Kike")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 152, height: 152)
            }
            .frame(width: 180, height: 180)
        } else {
            Image(systemName: filter.emptyStateIcon)
                .font(.system(size: 64))
                .foregroundStyle(filter.emptyStateIconColor)
        }
    }

    private var verticalOffset: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .compact ? -52 : 0
        #else
        0
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let restoreStatusText {
                    RestoreStatusBanner(text: restoreStatusText)
                        .padding(.bottom, 18)
                }

                VStack(spacing: 8) {
                    artwork
                    AnimatedEmptyStateTitle(
                        text: filter.emptyStateTitle,
                        animateOnAppear: shouldAnimateCopy
                    )
                }
                .padding(.bottom, 12)

                AnimatedNarrativeText(
                    lines: filter.emptyStateLines,
                    animateOnAppear: shouldAnimateCopy
                )

                if filter == .readingList {
                    Button("Inspire Me") {
                        onDiscover()
                    }
                    .font(.app(.actionLabel))
                    .foregroundStyle(.primary)
                    #if os(iOS)
                    .buttonStyle(.glassProminent)
                    #else
                    .buttonStyle(.borderedProminent)
                    #endif
                    .buttonBorderShape(.capsule)
                    .tint(.mascotPurple)
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
        }
        .task {
            guard shouldAnimateCopy, !hasConsumedLaunchAnimation else { return }
            hasConsumedLaunchAnimation = true
            onCopyAnimationConsumed()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: verticalOffset)
        .background(Color.appBackground)
        .onDisappear {
            shouldAnimateCopy = false
        }
    }
}

struct RefreshableEmptyStateContainer<Content: View>: View {
    let onRefresh: () async -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await onRefresh()
            }
        }
    }
}

struct RestoreStatusBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(text)
                .font(.app(.auxiliaryStatus))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.72))
        )
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct AnimatedEmptyStateTitle: View {
    let text: String
    let animateOnAppear: Bool

    @State private var isTitleVisible = false

    var body: some View {
        Text(text)
            .font(.app(.emptyStateTitle))
            .opacity(animateOnAppear ? (isTitleVisible ? 1 : 0) : 1)
            .offset(y: animateOnAppear ? (isTitleVisible ? 0 : 8) : 0)
            .animation(animateOnAppear ? .easeOut(duration: 0.7) : nil, value: isTitleVisible)
            .task(id: text) {
                guard animateOnAppear else {
                    isTitleVisible = true
                    return
                }
                isTitleVisible = false
                try? await Task.sleep(for: .milliseconds(300))
                isTitleVisible = true
            }
    }
}

struct AnimatedNarrativeText: View {
    let lines: [String]
    let animateOnAppear: Bool

    @State private var visibleLineIndices: Set<Int> = []

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.app(.emptyStateBody))
                    .opacity(animateOnAppear ? (visibleLineIndices.contains(index) ? 1 : 0) : 1)
                    .offset(y: animateOnAppear ? (visibleLineIndices.contains(index) ? 0 : 8) : 0)
                    .animation(
                        animateOnAppear ? .easeOut(duration: 0.7).delay(Double(index) * 0.35) : nil,
                        value: visibleLineIndices
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .task(id: lines) {
            guard animateOnAppear else {
                visibleLineIndices = Set(lines.indices)
                return
            }
            visibleLineIndices = []

            try? await Task.sleep(for: .milliseconds(620))

            for index in lines.indices {
                visibleLineIndices.insert(index)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
