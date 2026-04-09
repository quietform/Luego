import SwiftUI

struct AddArticleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var hasInitializedPresentation = false
    @FocusState private var isURLFieldFocused: Bool
    @Bindable var viewModel: ArticleListViewModel

    private var trimmedURLText: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedURLText.isEmpty && !viewModel.isLoading
    }

    private var fieldBorderColor: Color {
        if viewModel.errorMessage != nil {
            return .red.opacity(0.35)
        }

        if isURLFieldFocused {
            return Color.regularSelectionInk.opacity(0.35)
        }

        return Color.regularOutline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Article URL")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)

                    TextField("Paste or enter a URL", text: $urlText, axis: .horizontal)
                        .accessibilityIdentifier("addArticle.urlField")
                        .accessibilityLabel("URL")
                        .textContentType(.URL)
                        .lineLimit(1)
                        .focused($isURLFieldFocused)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task {
                                await saveArticle()
                            }
                        }

                    PasteButton(payloadType: String.self) { strings in
                        pasteClipboardText(strings)
                    }
                    .accessibilityIdentifier("addArticle.paste")
                    .accessibilityLabel("Paste from Clipboard")
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.elevatedPanelBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(fieldBorderColor, lineWidth: isURLFieldFocused ? 1.5 : 1)
                }
            }

            statusSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("Add Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("addArticle.cancel")
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isLoading)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        await saveArticle()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .accessibilityIdentifier("addArticle.save")
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .accessibilityIdentifier("addArticle.sheet")
        .onAppear {
            initializePresentationIfNeeded()
        }
        .onChange(of: urlText) { _, _ in
            if viewModel.errorMessage != nil {
                viewModel.clearError()
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.app(.auxiliaryStatus))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
        } else if viewModel.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching article details…")
                    .font(.app(.auxiliaryStatus))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.elevatedPanelBackground)
            )
        }
    }

    private func saveArticle() async {
        guard canSave else { return }

        await viewModel.addArticle(from: trimmedURLText)

        if viewModel.errorMessage == nil {
            dismiss()
        }
    }

    private func initializePresentationIfNeeded() {
        guard !hasInitializedPresentation else { return }

        hasInitializedPresentation = true
        isURLFieldFocused = true
    }

    private func pasteClipboardText(_ strings: [String]) {
        guard let clipboardText = strings
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return
        }

        urlText = clipboardText
        isURLFieldFocused = true
    }
}
