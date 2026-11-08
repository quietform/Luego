import SwiftUI

struct DiscoveryArticleContentView: View {
    let post: DiscoveryPost
    let publishedDate: Date?
    let markdown: String?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ReaderArticleHeader(
                        title: post.title,
                        source: post.domain,
                        url: post.url,
                        date: publishedDate.map { DateFormatters.articleDate($0) },
                        readingMinutes: ReadingTime.minutes(wordCount: nil, content: markdown)
                    )

                    ReaderMarkdownContentView(
                        markdown: markdown,
                        title: post.title,
                        baseURL: post.url
                    )
                }
                .font(ReaderLayout.bodyFont(for: geo.size.width))
                .padding(.vertical)
                .padding(.horizontal, ReaderLayout.horizontalPadding(for: geo.size.width))
                .frame(maxWidth: .infinity)
            }
            .background(Color.readerBackground)
        }
    }
}
