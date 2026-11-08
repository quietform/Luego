import SwiftUI

struct ReaderArticleHeader: View {
    let title: String
    let source: String
    let url: URL
    let date: String?
    let readingMinutes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.lora(.title))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    sourceLink
                    if let details {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        detailsText(details)
                    }
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: 4) {
                    sourceLink
                    if let details {
                        detailsText(details)
                    }
                }
            }
            .font(.lora(.subheadline))
        }
        .padding(.bottom, 12)
    }

    private var sourceLink: some View {
        Link(source, destination: url)
            .foregroundStyle(.primary)
    }

    private func detailsText(_ details: String) -> some View {
        Text(details)
            .foregroundStyle(.secondary)
    }

    private var details: String? {
        let parts = [date, readingMinutes.map { "\($0) min read" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
