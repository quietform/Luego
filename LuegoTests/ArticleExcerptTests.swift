import Foundation
import Testing

@MainActor
struct ArticleExcerptTests {
    @Test(arguments: ["* * *", "***", "- - -", "---", "_ _ _", "___"])
    func sectionBreaksAreLeftOutOfTheExcerpt(sectionBreak: String) {
        let article = Article(
            url: URL(string: "https://example.com/post")!,
            title: "Post",
            content: "\(sectionBreak)\n\nWAZZZZZA,\n\nIt feels like I wrote one of these ages ago."
        )

        #expect(article.excerpt == "WAZZZZZA, It feels like I wrote one of these ages ago.")
    }
}
