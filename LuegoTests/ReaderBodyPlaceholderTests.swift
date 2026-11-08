import SwiftUI
import Testing

@MainActor
struct ReaderBodyPlaceholderTests {
    @Test
    func voiceOverHearsThatTheArticleIsLoading() {
        #expect(accessibilityLabels(in: ReaderBodyPlaceholder().padding()) == ["Loading article"])
    }
}
