import SwiftUI
import Testing

@MainActor
struct ReaderListButtonTests {
    @Test(arguments: [
        (
            ArticleListMembership.readingList,
            ReaderListButton(title: "Favorite", systemImage: "heart", tint: nil),
            ReaderListButton(title: "Archive", systemImage: "archivebox", tint: nil)
        ),
        (
            .favorites,
            ReaderListButton(title: "Unfavorite", systemImage: "heart.fill", tint: .red),
            ReaderListButton(title: "Archive", systemImage: "archivebox", tint: nil)
        ),
        (
            .archived,
            ReaderListButton(title: "Favorite", systemImage: "heart", tint: nil),
            ReaderListButton(title: "Unarchive", systemImage: "archivebox.fill", tint: nil)
        )
    ])
    func listButtonsShowTheMembershipAndOfferItsOpposite(
        membership: ArticleListMembership,
        favorite: ReaderListButton,
        archive: ReaderListButton
    ) {
        #expect(ReaderListButton.favorite(for: membership) == favorite)
        #expect(ReaderListButton.archive(for: membership) == archive)
    }
}
