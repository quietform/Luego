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

            VStack(alignment: .leading, spacing: 4) {
                Link(source, destination: url)
                    .foregroundStyle(.primary)

                Text(details ?? " ")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(details == nil)
            }
            .font(.lora(.subheadline))
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: String? {
        let parts = [date, readingMinutes.map { "\($0) min read" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
