import SwiftUI
import Textual

protocol ReaderImageLoading: Sendable {
    func image(for url: URL) async throws -> ReaderImage
}

struct ReaderImageLoader: AttachmentLoader, ReaderImageLoading {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func image(for url: URL) async throws -> ReaderImage {
        let (data, response) = try await session.data(from: url)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try await ReaderImageDecoder.decode(data)
    }

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> ReaderImageAttachment {
        ReaderImageAttachment(description: text, image: try await image(for: url))
    }
}

struct ReaderImageAttachment: Textual.Attachment {
    let description: String
    let image: ReaderImage

    var body: some View {
        ReaderAnimatedImage(image: image)
            .accessibilityLabel(description)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = min(proposal.width ?? image.size.width, image.size.width)
        return CGSize(width: width, height: width * image.size.height / image.size.width)
    }
}

private struct ReaderAnimatedImage: View {
    let image: ReaderImage
    @State private var frame = 0

    var body: some View {
        Image(decorative: image.frames[frame], scale: 1)
            .resizable()
            .task(id: image) {
                guard image.frames.count > 1 else { return }
                var loops = 0
                do {
                    while true {
                        try await Task.sleep(for: .seconds(image.frameDurations[frame]))
                        if frame + 1 == image.frames.count {
                            loops += 1
                            if image.loopCount > 0, loops >= image.loopCount { return }
                        }
                        frame = (frame + 1) % image.frames.count
                    }
                } catch {}
            }
    }
}
