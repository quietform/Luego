import Foundation

nonisolated struct ReaderDocument: Sendable {
    struct Block: Identifiable, Sendable {
        let id: Int
        let content: AttributedString
        let isCaption: Bool
        let containsImages: Bool

        var standaloneImage: (url: URL, description: String, link: URL?)? {
            guard content.runs.count == 1,
                  let run = content.runs.first,
                  let url = run[AttributeScopes.FoundationAttributes.ImageURLAttribute.self],
                  let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self],
                  intent.components.count == 1,
                  case .paragraph = intent.components[0].kind else { return nil }
            return (url, String(content.characters), run[AttributeScopes.FoundationAttributes.LinkAttribute.self])
        }

        var isSectionBreak: Bool {
            content.runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]?.components.last?.kind == .thematicBreak
        }
    }

    let blocks: [Block]

    @concurrent
    static func prepare(markdown: String, title: String, baseURL: URL) async throws -> ReaderDocument {
        try ReaderDocument(markdown: stripFirstH1FromMarkdown(markdown, matchingTitle: title), baseURL: baseURL)
    }

    init(markdown: String, baseURL: URL) throws {
        let content = try AttributedString(markdown: markdown, baseURL: baseURL)
        var result: [Block] = []
        var start = content.startIndex
        var previousIdentity: Int?
        for run in content.runs {
            let identity = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]?.components.last?.identity
            if run.range.lowerBound != start, identity != previousIdentity {
                Self.append(AttributedString(content[start..<run.range.lowerBound]), to: &result)
                start = run.range.lowerBound
            }
            previousIdentity = identity
        }
        if start < content.endIndex {
            Self.append(AttributedString(content[start..<content.endIndex]), to: &result)
        }
        blocks = result
    }

    private static func append(_ content: AttributedString, to blocks: inout [Block]) {
        let isCaption = blocks.last?.standaloneImage != nil && isEmphasizedParagraph(content)
        let containsImages = content.runs.contains { $0[AttributeScopes.FoundationAttributes.ImageURLAttribute.self] != nil }
        let block = Block(id: blocks.count, content: content, isCaption: isCaption, containsImages: containsImages)
        guard !(blocks.isEmpty && block.isSectionBreak) else { return }
        if let last = blocks.last, !last.isCaption, !last.containsImages, !block.containsImages {
            // Only image-free text joins, so the joined block has no images either.
            blocks[blocks.count - 1] = Block(id: last.id, content: last.content + content, isCaption: false, containsImages: false)
            return
        }
        blocks.append(block)
    }

    private static func isEmphasizedParagraph(_ content: AttributedString) -> Bool {
        guard content.runs.first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]?.components.last?.kind == .paragraph else {
            return false
        }
        let textRuns = content.runs.filter { run in
            !content[run.range].characters.allSatisfy(\.isWhitespace)
        }
        return !textRuns.isEmpty && textRuns.allSatisfy { run in
            run[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self]?.contains(.emphasized) == true
        }
    }
}
