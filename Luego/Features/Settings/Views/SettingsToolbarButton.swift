import SwiftUI

struct SettingsToolbarButton: View {
    @Environment(\.diContainer) private var diContainer
    @State private var showingSettings = false

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings.toolbarButton")
        .sheet(isPresented: $showingSettings) {
            if let diContainer {
                NavigationStack {
                    SettingsView(viewModel: diContainer.makeSettingsViewModel())
                }
            }
        }
    }
}
