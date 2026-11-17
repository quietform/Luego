import SwiftUI

struct ArticleListEmptyState: View {
    let onDiscover: () -> Void
    let filter: ArticleFilter
    let restoreStatusText: String?
    let onCopyAnimationConsumed: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.addArticle) private var addArticle
    @State private var shouldAnimateCopy: Bool
    @State private var hasConsumedLaunchAnimation = false
    @State private var revealedStepCount = 0

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

    var body: some View {
        VStack(spacing: 0) {
            if let restoreStatusText {
                RestoreStatusBanner(text: restoreStatusText)
                    .padding(.bottom, 18)
            }

            artwork
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                Text(filter.emptyStateTitle)
                    .font(.app(.emptyStateTitle))
                    .revealed(isRevealed(step: 0))

                VStack(spacing: 6) {
                    ForEach(Array(filter.emptyStateLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.app(.emptyStateBody))
                            .frame(maxWidth: .infinity)
                            .revealed(isRevealed(step: index + 1))
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            if filter == .readingList {
                actions
                    .padding(.top, 24)
                    .revealed(isRevealed(step: actionsStep))
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 24)
        .task {
            guard shouldAnimateCopy, !hasConsumedLaunchAnimation else { return }
            hasConsumedLaunchAnimation = true
            onCopyAnimationConsumed()
            await revealInSequence()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: verticalOffset)
        .background(Color.appBackground)
        .onDisappear {
            shouldAnimateCopy = false
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if filter == .readingList {
            MascotBadge(size: 140)
        } else {
            Image(systemName: filter.emptyStateIcon)
                .font(.system(size: 64))
                .foregroundStyle(filter.emptyStateIconColor)
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            if let addArticle {
                Button("Add Article", systemImage: "plus") {
                    addArticle()
                }
                .font(.app(.actionLabel))
                .foregroundStyle(.primary)
                #if os(iOS)
                .buttonStyle(.glassProminent)
                #else
                .buttonStyle(.borderedProminent)
                #endif
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.mascotPurple)
            }

            Button {
                onDiscover()
            } label: {
                Text("Inspire Me")
                    .frame(minWidth: 88, minHeight: 44)
                    .contentShape(.rect)
            }
            .font(.app(.actionLabel))
            .buttonStyle(.borderless)
            .tint(.mascotPurpleInk)
        }
    }

    private var verticalOffset: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .compact ? -52 : 0
        #else
        0
        #endif
    }

    // The launch reveal shows the title (step 0), then each line, then the actions,
    // so nothing invites a tap before the copy has explained it.
    private var actionsStep: Int {
        filter.emptyStateLines.count + 1
    }

    private var revealStepCount: Int {
        actionsStep + 1
    }

    private func isRevealed(step: Int) -> Bool {
        !shouldAnimateCopy || step < revealedStepCount
    }

    private func revealInSequence() async {
        for step in 0..<revealStepCount {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.7)) {
                revealedStepCount = step + 1
            }
        }
    }
}

private extension View {
    func revealed(_ isRevealed: Bool) -> some View {
        modifier(Reveal(isRevealed: isRevealed))
    }
}

/// Fades content in from slightly below, or in place when Reduce Motion is on.
/// Hidden content is also hidden from VoiceOver, so it can't be focused before it appears.
private struct Reveal: ViewModifier {
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : 8)
            .accessibilityHidden(!isRevealed)
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
