import SwiftUI

struct ArticleRowLayout<TitleAccessory: View, Metadata: View>: View {
    let thumbnailURL: URL?
    let title: String
    let excerpt: String
    var isSelected = false
    @ViewBuilder let titleAccessory: TitleAccessory
    @ViewBuilder let metadata: Metadata

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbnailURL {
                ArticleThumbnailView(url: thumbnailURL)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.app(.listTitle))
                            .foregroundStyle(isSelected ? Color.regularSelectionInk : Color.primary)
                            .lineLimit(2)
                            .lineSpacing(1)

                        if !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.app(.listExcerpt))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    titleAccessory
                }

                metadata
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct ArticleThumbnailView: View {
    let url: URL?

    private let thumbnailSize: CGFloat = 72

    private var secureURL: URL? {
        guard let url else { return nil }
        guard url.scheme == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }

    var body: some View {
        thumbnailContent
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let url = secureURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholderView
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .overlay {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.quaternary)
            }
    }
}
