import SwiftUI

struct DiscoveryLoadingView: View {
    var pendingURL: URL?
    var loadingText: String

    var body: some View {
        VStack {
            Spacer()

            ProgressView()
                .frame(width: 88, height: 31)

            Spacer()

            VStack(spacing: 16) {
                Text(loadingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let domain = pendingURL?.host() {
                    LoadingDomainChip(domain: domain)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: pendingURL)
    }
}

struct LoadingDomainChip: View {
    let domain: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(domain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
        .shimmer()
    }
}
