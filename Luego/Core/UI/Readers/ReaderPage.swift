import SwiftUI

struct ReaderPage<PositionTracker: View>: View {
    let header: ReaderArticleHeader
    let markdown: String?
    let onPreparationChanged: (Bool, ReaderPageScroll) -> Void
    let positionTracker: (ReaderPageScroll) -> PositionTracker

    init(
        header: ReaderArticleHeader,
        markdown: String?,
        onPreparationChanged: @escaping (Bool, ReaderPageScroll) -> Void,
        @ViewBuilder positionTracker: @escaping (ReaderPageScroll) -> PositionTracker
    ) {
        self.header = header
        self.markdown = markdown
        self.onPreparationChanged = onPreparationChanged
        self.positionTracker = positionTracker
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                let scroll = ReaderPageScroll(viewportHeight: viewport.size.height, proxy: proxy)
                ScrollView {
                    ReaderColumn(header: header, markdown: markdown, width: viewport.size.width) { prepared in
                        onPreparationChanged(prepared, scroll)
                    }
                    .background(positionTracker(scroll))
                }
                .coordinateSpace(ReaderPageScroll.coordinateSpace)
                .readingProgress(isReported: markdown != nil)
                .background(Color.readerBackground)
            }
        }
    }
}

extension ReaderPage where PositionTracker == EmptyView {
    init(header: ReaderArticleHeader, markdown: String?) {
        self.init(header: header, markdown: markdown, onPreparationChanged: { _, _ in }) { _ in
            EmptyView()
        }
    }
}

struct ReaderPageScroll {
    static let coordinateSpace = NamedCoordinateSpace.named("ReaderPage")

    let viewportHeight: CGFloat
    let proxy: ScrollViewProxy
}

struct ReaderColumn: View {
    let header: ReaderArticleHeader
    let markdown: String?
    let width: CGFloat
    var onPreparationChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ReaderMarkdownContentView(
                markdown: markdown,
                title: header.title,
                baseURL: header.url,
                onPreparationChanged: onPreparationChanged
            )
        }
        .font(ReaderLayout.bodyFont(for: width))
        .padding(.vertical)
        .padding(.horizontal, ReaderLayout.horizontalPadding(for: width))
        .frame(maxWidth: .infinity)
    }
}
