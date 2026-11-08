import Foundation

nonisolated struct ReaderDocument: Sendable {
    struct Block: Identifiable, Sendable {
        let id: Int
        let content: AttributedString

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
        let block = Block(id: blocks.count, content: content)
        guard !(blocks.isEmpty && block.isSectionBreak) else { return }
        blocks.append(block)
    }
}
