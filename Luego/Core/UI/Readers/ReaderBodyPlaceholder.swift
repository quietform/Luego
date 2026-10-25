import SwiftUI

struct ReaderBodyPlaceholder: View {
    // Redacted text inherits the reader font, so the placeholder lines match the article's line height and rag.
    private static let paragraphs = [
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.",
        "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia.",
        "Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam."
    ]

    // Matches Textual's GitHub paragraph style, which adds a quarter of the 17pt body size between lines.
    @ScaledMetric(relativeTo: .body) private var lineSpacing: CGFloat = 17 * 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Self.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .lineSpacing(lineSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .shimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading article")
    }
}
