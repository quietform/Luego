import SwiftUI

struct DiscoveryPostRow: View {
    let post: DiscoveryPost
    var isSelected = false

    var body: some View {
        ArticleRowLayout(
            thumbnailURL: post.thumbnailURL,
            title: post.title,
            excerpt: post.excerpt ?? "",
            isSelected: isSelected
        ) {
            EmptyView()
        } metadata: {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.domain)
                    .lineLimit(1)

                if let publishedDate = post.displayDate(relativeTo: .now) {
                    Text(publishedDate, format: .relative(presentation: .named))
                        .lineLimit(1)
                }
            }
            .font(.app(.listMetadata))
            .foregroundStyle(.tertiary)
        }
    }
}
