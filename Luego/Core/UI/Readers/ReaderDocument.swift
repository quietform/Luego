import Foundation

struct ReaderDocument {
    struct Block: Identifiable {
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
    }

    let blocks: [Block]

    init(markdown: String, baseURL: URL) throws {
        let content = try AttributedString(markdown: markdown, baseURL: baseURL)
        var result: [Block] = []
        var start = content.startIndex
        var previousIdentity: Int?
        for run in content.runs {
            let identity = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]?.components.last?.identity
            if run.range.lowerBound != start, identity != previousIdentity {
                result.append(Block(id: result.count, content: AttributedString(content[start..<run.range.lowerBound])))
                start = run.range.lowerBound
            }
            previousIdentity = identity
        }
        if start < content.endIndex {
            result.append(Block(id: result.count, content: AttributedString(content[start..<content.endIndex])))
        }
        blocks = result
    }
}
