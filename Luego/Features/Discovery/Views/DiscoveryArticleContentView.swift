import SwiftUI

struct DiscoveryArticleContentView: View {
    let post: DiscoveryPost
    let publishedDate: Date?
    let markdown: String?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DiscoveryArticleHeaderView(
                        title: post.title,
                        url: post.url,
                        feedTitle: post.domain,
                        formattedDate: formattedDate
                    )

                    Divider()

                    ReaderMarkdownContentView(
                        markdown: markdown,
                        title: post.title,
                        baseURL: post.url
                    )
                }
                .font(.lora(.body))
                .padding(.vertical)
                .padding(.horizontal, ReaderLayout.horizontalPadding(for: geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Color.readerBackground)
        }
    }

    private var formattedDate: String {
        guard let publishedDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yy"
        return formatter.string(from: publishedDate)
    }
}

struct DiscoveryArticleHeaderView: View {
    let title: String
    let url: URL
    let feedTitle: String
    let formattedDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.lora(.title))
                .foregroundColor(.primary)

            HStack {
                SourceAttributionChip(feedTitle: feedTitle, url: url)

                Spacer()

                if !formattedDate.isEmpty {
                    Text(formattedDate)
                        .font(.lora(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SourceAttributionChip: View {
    let feedTitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text("via \(feedTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}
