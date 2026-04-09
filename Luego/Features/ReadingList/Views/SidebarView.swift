import SwiftUI

struct SidebarView: View {
    @Binding var selection: ArticleFilter
    let onAddArticle: (() -> Void)?
    @Environment(SyncStatusObserver.self) private var syncStatusObserver

    init(selection: Binding<ArticleFilter>, onAddArticle: (() -> Void)? = nil) {
        _selection = selection
        self.onAddArticle = onAddArticle
    }

    var body: some View {
        List {
            ForEach(ArticleFilter.allCases, id: \.self) { filter in
                sidebarFilterButton(for: filter)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(sidebarRowBackground(isSelected: selection == filter))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.regularPanelBackground)
        .navigationTitle("Luego")
        .appNavigationStyle(.sidebarPanel)
        .safeAreaInset(edge: .bottom) {
            SidebarSyncFooter(
                state: syncStatusObserver.state,
                lastSyncTime: syncStatusObserver.lastSyncTime,
                accountStatusDescription: syncStatusObserver.accountStatusDescription,
                cloudKitIdentityTokenState: syncStatusObserver.cloudKitIdentityTokenState,
                cloudKitUserRecordID: syncStatusObserver.cloudKitUserRecordID,
                cloudKitNeedsAttention: syncStatusObserver.cloudKitNeedsAttention
            )
        }
    }

    private func sidebarFilterButton(for filter: ArticleFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            selection = filter
        } label: {
            HStack(spacing: 12) {
                Image(systemName: filter.icon)
                    .frame(width: 20)

                Text(filter.title)

                Spacer(minLength: 0)
            }
            .font(.app(.sidebarItem, emphasized: isSelected))
            .foregroundStyle(isSelected ? Color.regularSelectionInk : Color.primary.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sidebarRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.regularSelectionFill : Color.clear)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
    }
}

struct SyncStatusRow: View {
    let state: SyncState
    let lastSyncTime: Date?
    let accountStatusDescription: String?
    let cloudKitIdentityTokenState: String?
    let cloudKitUserRecordID: String?
    let cloudKitNeedsAttention: Bool
    var verticalPadding: Edge.Set = .vertical

    private var presentation: SyncStatusPresentation {
        SyncStatusPresentation(
            state: state,
            accountStatusDescription: accountStatusDescription,
            cloudKitIdentityTokenState: cloudKitIdentityTokenState,
            cloudKitUserRecordID: cloudKitUserRecordID,
            cloudKitNeedsAttention: cloudKitNeedsAttention,
            lastSyncTime: lastSyncTime
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            SyncStatusIndicator(state: state, onErrorTap: nil)
                .font(.app(.auxiliaryStatus))

            if let statusText = presentation.compactText {
                Text(statusText)
                    .font(.app(.auxiliaryStatus))
                    .foregroundStyle(presentation.compactTextColor)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(verticalPadding, 8)
    }
}

struct SidebarSyncFooter: View {
    let state: SyncState
    let lastSyncTime: Date?
    let accountStatusDescription: String?
    let cloudKitIdentityTokenState: String?
    let cloudKitUserRecordID: String?
    let cloudKitNeedsAttention: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            SyncStatusRow(
                state: state,
                lastSyncTime: lastSyncTime,
                accountStatusDescription: accountStatusDescription,
                cloudKitIdentityTokenState: cloudKitIdentityTokenState,
                cloudKitUserRecordID: cloudKitUserRecordID,
                cloudKitNeedsAttention: cloudKitNeedsAttention
            )
        }
        .background(Color.regularPanelBackground)
    }
}
