import SwiftUI

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
