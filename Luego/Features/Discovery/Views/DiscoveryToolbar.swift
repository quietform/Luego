import SwiftUI

struct DiscoveryToolbar: ToolbarContent {
    let isSaved: Bool
    let canSave: Bool
    let canShuffle: Bool
    let articleURL: URL
    let articleTitle: String
    let onShuffle: () -> Void
    let onSave: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onShuffle) {
                Label("Next Random Article", systemImage: "die.face.5")
            }
            .disabled(!canShuffle)
            .accessibilityIdentifier("discovery.nextRandom")

            DiscoverySaveButton(isSaved: isSaved, canSave: canSave).button(action: onSave)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            ReaderMoreMenu(articleURL: articleURL, articleTitle: articleTitle, onOpenInBrowser: onOpenInBrowser)
        }
    }
}

struct DiscoverySaveButton: Equatable {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    func button(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier("discovery.save")
    }
}

extension DiscoverySaveButton {
    init(isSaved: Bool, canSave: Bool) {
        if isSaved {
            self.init(title: "Saved to Reading List", systemImage: "checkmark", isEnabled: false)
        } else {
            self.init(title: "Save to Reading List", systemImage: "plus", isEnabled: canSave)
        }
    }
}
