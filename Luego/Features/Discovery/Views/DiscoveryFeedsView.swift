import SwiftUI

struct DiscoveryFeedsView: View {
    @Bindable var viewModel: DiscoveryFeedsViewModel
    @Environment(\.dismiss) private var dismiss

    private var canAdd: Bool {
        !viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isAdding
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)

                    TextField("Blog or feed URL", text: $viewModel.urlText)
                        .accessibilityIdentifier("discoveryFeeds.urlField")
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)

                    if viewModel.isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Add", action: add)
                            .accessibilityIdentifier("discoveryFeeds.add")
                            .disabled(!canAdd)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.app(.auxiliaryStatus))
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Paste a blog's address or its RSS or Atom feed.")
            }

            Section("Feeds") {
                ForEach(viewModel.feeds) { feed in
                    DiscoveryFeedRow(feed: feed) { isEnabled in
                        viewModel.setFeed(feed, isEnabled: isEnabled)
                    }
                }
                .onDelete { offsets in
                    offsets.map { viewModel.feeds[$0] }.forEach(viewModel.removeFeed)
                }

                if viewModel.canAddKagiSmallWeb {
                    Button("Add Kagi Small Web", systemImage: "plus.circle", action: viewModel.addKagiSmallWeb)
                        .accessibilityIdentifier("discoveryFeeds.addKagiSmallWeb")
                }
            }
        }
        .formStyle(.grouped)
        .tint(Color.regularSelectionInk)
        .navigationTitle("Feeds")
        .appNavigationStyle(.inlineTransparent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .disabled(!viewModel.canClose)
            }
        }
        .interactiveDismissDisabled(!viewModel.canClose)
        .onChange(of: viewModel.urlText) {
            viewModel.errorMessage = nil
        }
    }

    private func add() {
        guard canAdd else { return }
        Task { await viewModel.addFeed() }
    }
}

struct DiscoveryFeedRow: View {
    let feed: DiscoveryFeed
    let onToggle: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { feed.isEnabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                Text(feed.url.absoluteString)
                    .font(.app(.auxiliaryStatus))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("discoveryFeeds.toggle")
    }
}

extension DiscoveryFeedsViewModel: Identifiable {}
