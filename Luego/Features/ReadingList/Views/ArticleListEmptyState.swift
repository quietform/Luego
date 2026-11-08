import SwiftUI

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
            MascotBadge(size: 180)
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
