struct ArticleListMembership: Equatable, Sendable {
    static let readingList = ArticleListMembership(isFavorite: false, isArchived: false)
    static let favorites = ArticleListMembership(isFavorite: true, isArchived: false)
    static let archived = ArticleListMembership(isFavorite: false, isArchived: true)

    let isFavorite: Bool
    let isArchived: Bool

    nonisolated init(isFavorite: Bool, isArchived: Bool) {
        self.isFavorite = isArchived ? false : isFavorite
        self.isArchived = isArchived
    }

    nonisolated func togglingFavorite() -> ArticleListMembership {
        let nextIsFavorite = !isFavorite
        return ArticleListMembership(
            isFavorite: nextIsFavorite,
            isArchived: nextIsFavorite ? false : isArchived
        )
    }

    nonisolated func togglingArchive() -> ArticleListMembership {
        let nextIsArchived = !isArchived
        return ArticleListMembership(
            isFavorite: nextIsArchived ? false : isFavorite,
            isArchived: nextIsArchived
        )
    }
}
