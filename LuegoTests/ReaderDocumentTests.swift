import Foundation
import Testing

@MainActor
struct ReaderDocumentTests {
    @Test
    func preparationFinishesInCancelledTask() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReaderDocument.prepare(markdown: "Body", title: "Article", baseURL: URL(string: "https://example.com")!)
        }
        let document = try await task.value
        #expect(document.blocks.map { String($0.content.characters) } == ["Body"])
    }

    @Test
    func preparingDocumentKeepsMainActorResponsive() async throws {
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }
        let document = try await ReaderDocument.prepare(
            markdown: "# Article\n\n" + String(repeating: "Paragraph with **emphasis** and [a link](/target).\n\n", count: 500),
            title: "Article",
            baseURL: URL(string: "https://example.com/article")!
        )

        #expect(mainActorRan)
        await heartbeat.value
        #expect(document.blocks.map { String($0.content.characters) } == [String(repeating: "Paragraph with emphasis and a link.", count: 500)])
        #expect(document.blocks.first?.content.runs.contains { $0[AttributeScopes.FoundationAttributes.LinkAttribute.self]?.absoluteString == "https://example.com/target" } == true)
    }

    @Test
    func preparationTimeGrowsInProportionToArticleLength() throws {
        func preparationTime(paragraphs: Int) throws -> Duration {
            let markdown = String(repeating: "Paragraph with *emphasis* and [a link](/target).\n\n", count: paragraphs)
            return try ContinuousClock().measure {
                _ = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
            }
        }

        _ = try preparationTime(paragraphs: 100)
        let short = try preparationTime(paragraphs: 300)
        let long = try preparationTime(paragraphs: 1_200)

        // Four times the text should take about four times as long; sixteen times means each
        // paragraph rescans the ones before it.
        #expect(long < short * 8, "300 paragraphs: \(short), 1,200 paragraphs: \(long)")
    }

    @Test
    func sectionBreakOpeningTheArticleIsDropped() throws {
        let document = try ReaderDocument(
            markdown: "* * *\n\nFirst section\n\n* * *\n\nSecond section",
            baseURL: URL(string: "https://example.com")!
        )

        #expect(topLevelKinds(of: document) == [.paragraph, .thematicBreak, .paragraph])
    }

    @Test(arguments: [
        "*Happy Halloween + Diwali!*",
        "*Photo by [Jane](https://example.com/jane)*",
        "*Shot on **film***"
    ])
    func emphasizedParagraphRightAfterAPhotoIsItsCaption(caption: String) throws {
        let document = try ReaderDocument(
            markdown: "![Ratik in a chef's apron](costume.jpg)\n\n\(caption)",
            baseURL: URL(string: "https://example.com")!
        )

        #expect(document.blocks.map(\.isCaption) == [false, true])
    }

    @Test(arguments: [
        ("Intro\n\n*Just emphasis*", [false]),
        ("![Photo](photo.jpg)\n\n*Happy* Halloween", [false, false]),
        ("![Photo](photo.jpg)\n\nPlain paragraph", [false, false]),
        ("![Photo](photo.jpg)\n\n*Caption*\n\n*Still emphasis*", [false, true, false])
    ])
    func onlyAFullyEmphasizedParagraphRightAfterAPhotoIsACaption(markdown: String, expected: [Bool]) throws {
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)

        #expect(document.blocks.map(\.isCaption) == expected)
    }

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
    func paragraphWithAnInlineImageIsNotJoinedToTheTextAroundIt() throws {
        let document = try ReaderDocument(
            markdown: "Before\n\nMore before\n\nText with ![an icon](icon.png) inline\n\nAfter",
            baseURL: URL(string: "https://example.com")!
        )

        #expect(document.blocks.map { String($0.content.characters) } == ["BeforeMore before", "Text with an icon inline", "After"])
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

        #expect(document.blocks.count == 1)
        let list = try #require(document.blocks.first { String($0.content.characters).contains("Nested") })
        #expect(String(list.content.characters).contains("Second"))
        let links = document.blocks.flatMap { $0.content.runs.compactMap { $0[AttributeScopes.FoundationAttributes.LinkAttribute.self] } }
        #expect(links.map(\.absoluteString) == ["https://example.com/destination"])
    }

    @Test
    func aNestedListOrQuoteWithAnImageStaysOneBlock() throws {
        let document = try ReaderDocument(markdown: """
        Intro

        - First with ![an icon](icon.png)
          - Nested
        - Second

        > Quote with ![a mark](mark.png)
        >
        > Second quoted paragraph

        Outro
        """, baseURL: URL(string: "https://example.com")!)

        #expect(document.blocks.map { String($0.content.characters) } == [
            "Intro",
            "First with an iconNestedSecond",
            "Quote with a markSecond quoted paragraph",
            "Outro"
        ])
    }

    @Test
    func emptyArticleHasNoBlocks() throws {
        let document = try ReaderDocument(markdown: "", baseURL: URL(string: "https://example.com")!)
        #expect(document.blocks.isEmpty)
    }

    private func topLevelKinds(of document: ReaderDocument) -> [PresentationIntent.Kind] {
        var kinds: [PresentationIntent.Kind] = []
        var previousIdentity: Int?
        for block in document.blocks {
            for run in block.content.runs {
                guard let component = run.presentationIntent?.components.last, component.identity != previousIdentity else { continue }
                kinds.append(component.kind)
                previousIdentity = component.identity
            }
        }
        return kinds
    }
}
