import SwiftUI

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
