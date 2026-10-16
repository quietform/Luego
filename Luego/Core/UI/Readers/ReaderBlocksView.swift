import SwiftUI
import Textual

struct ReaderBlocksView: View {
    let document: ReaderDocument
    var imageLoader: any ReaderImageLoading = ReaderImageLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(document.blocks) { block in
                Group {
                    if let photo = block.standaloneImage {
                        ReaderPhotoView(url: photo.url, description: photo.description, link: photo.link, loader: imageLoader)
                    } else {
                        ReaderBlockView(block: block)
                    }
                }
                .id(block.content)
            }
        }
    }
}

private struct ReaderPhotoView: View {
    let url: URL
    let description: String
    let link: URL?
    let loader: any ReaderImageLoading
    @State private var image: ReaderImage?
    @State private var imageSize: CGSize?
    @State private var width: CGFloat = 300
    @State private var isActive = false

    private var height: CGFloat {
        guard let imageSize else { return 300 }
        return min(width, imageSize.width) * imageSize.height / imageSize.width
    }

    var body: some View {
        Group {
            if let link {
                Link(destination: link) { photo }
            } else {
                photo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onGeometryChange(for: BufferedVisibility.self) { BufferedVisibility(geometry: $0) } action: { visibility in
            switch visibility {
            case .load: isActive = true
            case .retain: break
            case .release:
                isActive = false
                image = nil
            }
        }
        .task(id: isActive) { [isActive] in
            guard isActive else { return }
            do {
                try Task.checkCancellation()
                let loaded = try await loader.image(for: url)
                try Task.checkCancellation()
                imageSize = loaded.size
                image = loaded
            } catch {}
        }
        .onDisappear { image = nil }
    }

    @ViewBuilder
    private var photo: some View {
        if let image {
            ReaderImageAttachment(description: description, image: image).body
                .id(image)
                .frame(width: min(width, image.size.width), height: height)
        } else {
            Color.secondary.opacity(0.08)
                .accessibilityLabel(description)
        }
    }
}

private struct ReaderBlockView: View {
    let block: ReaderDocument.Block
    @State private var isActive = false
    @State private var height: CGFloat = 300

    private var hasImages: Bool {
        block.content.runs.contains { $0[AttributeScopes.FoundationAttributes.ImageURLAttribute.self] != nil }
    }

    var body: some View {
        Group {
            if isActive || !hasImages {
                StructuredText("", parser: ReaderBlockParser(content: block.content, placeholderHeight: height))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        if $0 > 0 { height = $0 }
                    }
                    .frame(minHeight: height, alignment: .topLeading)
            } else {
                Color.clear.frame(height: height)
            }
        }
        .onGeometryChange(for: BufferedVisibility.self) { [hasImages] geometry in
            guard hasImages else { return .retain }
            return BufferedVisibility(geometry: geometry)
        } action: { visibility in
            switch visibility {
            case .load: isActive = true
            case .retain: break
            case .release: isActive = false
            }
        }
    }
}

private nonisolated enum BufferedVisibility: Equatable, Sendable {
    case load, retain, release

    init(geometry: GeometryProxy) {
        guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { self = .release; return }
        let bounds = CGRect(origin: .zero, size: geometry.size)
        if bounds.intersects(viewport.insetBy(dx: 0, dy: -viewport.height)) { self = .load }
        else if bounds.intersects(viewport.insetBy(dx: 0, dy: -2 * viewport.height)) { self = .retain }
        else { self = .release }
    }
}

private struct ReaderBlockParser: MarkupParser {
    let content: AttributedString
    let placeholderHeight: CGFloat

    func attributedString(for input: String) throws -> AttributedString {
        var result = content
        for run in content.runs where run[AttributeScopes.FoundationAttributes.ImageURLAttribute.self] != nil {
            let placeholder = ReaderImagePlaceholder(description: String(content[run.range].characters), height: content.runs.count == 1 ? placeholderHeight : 300)
            result[run.range].textual.attachment = AnyAttachment(placeholder as any Textual.Attachment)
        }
        return result
    }
}

private struct ReaderImagePlaceholder: Textual.Attachment {
    let description: String
    let height: CGFloat

    var body: some View {
        Color.secondary.opacity(0.08)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = proposal.width ?? 300
        return CGSize(width: width, height: height)
    }
}
