import SwiftUI

struct DiscoveryLoadingView: View {
    var loadingText: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()

            Text(loadingText)
                .font(.app(.auxiliaryStatus))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
