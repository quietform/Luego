import SwiftUI

struct ArticleRowView: View {
    let article: Article
    var isSelected: Bool = false

    var body: some View {
        iOSRowLayout
    }

    private var iOSRowLayout: some View {
        ArticleRowLayout(
            thumbnailURL: article.thumbnailURL,
            title: article.title,
            excerpt: article.excerpt,
            isSelected: isSelected
        ) {
            if article.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.app(.listMetadata))
                    .foregroundStyle(.pink)
                    .accessibilityIdentifier(ReadingListAccessibilityID.favoriteBadge(article))
            }
        } metadata: {
            ArticleMetadataRow(
                article: article,
                domain: article.domain,
                readPercentage: Int(article.readPosition * 100),
                formattedDate: formatDisplayDate(article),
                estimatedReadingTime: article.estimatedReadingTime,
                showReadingTime: article.content != nil
            )
        }
        .accessibilityIdentifier(ReadingListAccessibilityID.row(article))
    }

    private func formatDisplayDate(_ article: Article) -> String {
        let displayDate = article.publishedDate ?? article.savedDate
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(displayDate) {
            return DateFormatters.time.string(from: displayDate)
        } else if calendar.isDateInYesterday(displayDate) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: displayDate, to: now).day, daysAgo < 7 {
            return DateFormatters.weekday.string(from: displayDate)
        } else {
            return DateFormatters.shortDate.string(from: displayDate)
        }
    }
}

struct ArticleMetadataRow: View {
    let article: Article
    let domain: String
    let readPercentage: Int
    let formattedDate: String
    var estimatedReadingTime: String? = nil
    var showReadingTime: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(domain)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 0) {
                Text("Read \(readPercentage)%")
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier(ReadingListAccessibilityID.readProgress(article))

                if showReadingTime, let time = estimatedReadingTime {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                    Text(time)
                }

                Text(" · ")
                    .foregroundStyle(.quaternary)
                Text(formattedDate)

                Spacer()
            }
        }
        .font(.app(.listMetadata))
        .foregroundStyle(.tertiary)
    }
}
