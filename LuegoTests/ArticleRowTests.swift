import SwiftUI
import Testing
import Vision

@MainActor
struct ArticleRowTests {
    @Test
    func wrappedTitleKeepsItsDescriptionVisible() throws {
        let article = Article(
            url: URL(string: "https://example.com/article")!,
            title: "A long article title that wraps onto another line",
            content: "Useful summary"
        )
        let renderer = ImageRenderer(content:
            ArticleRowView(article: article)
                .frame(width: 288)
                .padding()
                .background(.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""

        #expect(text.contains("Useful summary"))
    }
}
