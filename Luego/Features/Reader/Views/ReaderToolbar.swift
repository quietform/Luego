import SwiftUI

struct ReaderToolbar: ToolbarContent {
    let membership: ArticleListMembership
    let progressPercent: Int?
    let articleURL: URL
    let articleTitle: String
    let onToggleFavorite: () -> Void
    let onToggleArchive: () -> Void
    let onOpenInBrowser: () -> Void
    let onRefresh: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ReaderListButton.favorite(for: membership).button(action: onToggleFavorite)
            ReaderListButton.archive(for: membership).button(action: onToggleArchive)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            ReaderMoreMenu(articleURL: articleURL, articleTitle: articleTitle, onOpenInBrowser: onOpenInBrowser) {
                Button(action: onRefresh) {
                    Label("Refresh Content", systemImage: "arrow.clockwise")
                }
            }
        }

        if let progressPercent {
            ToolbarItem(placement: .principal) {
                ReaderProgressRing(percent: progressPercent)
            }
        }
    }
}

struct ReaderListButton: Equatable {
    let title: String
    let systemImage: String
    let tint: Color?

    static func favorite(for membership: ArticleListMembership) -> ReaderListButton {
        membership.isFavorite
            ? ReaderListButton(title: "Unfavorite", systemImage: "heart.fill", tint: .red)
            : ReaderListButton(title: "Favorite", systemImage: "heart", tint: nil)
    }

    static func archive(for membership: ArticleListMembership) -> ReaderListButton {
        membership.isArchived
            ? ReaderListButton(title: "Unarchive", systemImage: "archivebox.fill", tint: nil)
            : ReaderListButton(title: "Archive", systemImage: "archivebox", tint: nil)
    }

    func button(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(tint)
    }
}
