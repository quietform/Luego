import SwiftUI

struct AppLaunchView: View {
    // Fast launches only ever see the background, which matches the launch screen.
    private static let revealDelay: Duration = .milliseconds(600)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                MascotBadge(size: 128)
                    .accessibilityHidden(true)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Opening your library…")
                        .font(.app(.auxiliaryStatus))
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : 8)
            .animation(.easeOut(duration: 0.5), value: isRevealed)
        }
        .task {
            if await Self.waitToReveal(after: Self.revealDelay) {
                isRevealed = true
            }
        }
    }

    static func waitToReveal(after delay: Duration) async -> Bool {
        do {
            try await Task.sleep(for: delay)
            return true
        } catch {
            return false
        }
    }
}
