import Foundation
import Testing

@MainActor
struct DiscoveryPostRowTests {
    @Test
    func rowReadsLikeAReadingListRow() throws {
        let post = DiscoveryPost(
            url: URL(string: "https://river.luego.test/posts/first")!,
            title: "Small web post",
            publishedDate: nil,
            excerpt: "Useful summary"
        )

        let boxes = try recognizedTextBoxes(in: DiscoveryPostRow(post: post))
        let titleBox = try #require(boxes["Small web post"])

        #expect(boxes.keys.contains("Useful summary"))
        #expect(titleBox.minX < 0.15)
    }
}
