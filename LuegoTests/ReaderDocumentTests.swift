import Foundation
import Testing

@MainActor
struct ReaderDocumentTests {
    @Test
    func imageParagraphsHaveIndependentLifetimes() throws {
        let document = try ReaderDocument(
            markdown: "Before\n\n![First](one.jpg)\n\nBetween\n\n![Second](two.jpg)\n\nAfter",
            baseURL: URL(string: "https://example.com/articles/post")!
        )

        try #require(document.blocks.count == 5)
        #expect(document.blocks.map { String($0.content.characters) } == ["Before", "First", "Between", "Second", "After"])
        let imageURL = document.blocks[1].content.runs.first?[AttributeScopes.FoundationAttributes.ImageURLAttribute.self]
        #expect(imageURL?.absoluteString == "https://example.com/articles/one.jpg")
    }
    @Test
    func nestedMarkupStaysTogetherAndResolvesReferences() throws {
        let document = try ReaderDocument(markdown: """
        # Heading

        - First
          - Nested
        - Second

        > Quote with **emphasis**

        ```swift
        let value = 1
        ```

        | A | B |
        | - | - |
        | 1 | 2 |

        [Reference][target]

        [target]: /destination
        """, baseURL: URL(string: "https://example.com/articles/post")!)

        #expect(document.blocks.count == 6)
        let list = try #require(document.blocks.first { String($0.content.characters).contains("Nested") })
        #expect(String(list.content.characters).contains("Second"))
        let link = try #require(document.blocks.last?.content.runs.first?[AttributeScopes.FoundationAttributes.LinkAttribute.self])
        #expect(link.absoluteString == "https://example.com/destination")
    }

    @Test
    func emptyArticleHasNoBlocks() throws {
        let document = try ReaderDocument(markdown: "", baseURL: URL(string: "https://example.com")!)
        #expect(document.blocks.isEmpty)
    }

}
