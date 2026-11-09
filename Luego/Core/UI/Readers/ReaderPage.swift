import SwiftUI

private let restorationAnchor = "ReaderPage.restoration"

struct ReaderPage: View {
    let header: ReaderArticleHeader
    let markdown: String?
    var restoringTo: Double? = nil
    var onRestored: () -> Void = {}
    var onReadingPositionChange: (Double?) -> Void = { _ in }
    @State private var isPrepared = false
    @State private var visibleBottom: Double?
    @State private var anchorPosition: Double?

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    ReaderColumn(header: header, markdown: markdown, width: viewport.size.width) { prepared in
                        isPrepared = prepared
                    }
                    .background { restorationTarget }
                }
                .readingProgress(isReported: markdown != nil)
                .onScrollGeometryChange(for: Double?.self, of: Self.visibleBottom(in:)) { _, position in
                    visibleBottom = position
                }
                .onChange(of: readingPosition, initial: true) { _, position in
                    onReadingPositionChange(position)
                }
                .onChange(of: restoringTo, initial: true) { _, target in
                    if let target { anchorPosition = target }
                }
                .task(id: RestoreRequest(target: restoringTo, isPrepared: isPrepared)) {
                    await restore(using: proxy)
                }
                .background(Color.readerBackground)
            }
        }
    }

    @ViewBuilder
    private var restorationTarget: some View {
        if let anchorPosition {
            GeometryReader { column in
                Color.clear
                    .overlay(alignment: .top) {
                        Color.clear
                            .frame(height: 1)
                            .id(restorationAnchor)
                            .frame(height: column.size.height * min(1, max(0, anchorPosition)), alignment: .bottom)
                    }
            }
        }
    }

    private var readingPosition: Double? {
        isPrepared ? visibleBottom : nil
    }

    private func restore(using proxy: ScrollViewProxy) async {
        guard restoringTo != nil, isPrepared else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(restorationAnchor, anchor: .bottom)
        }
        onRestored()
    }

    private static func visibleBottom(in geometry: ScrollGeometry) -> Double? {
        guard geometry.contentSize.height > 0 else { return nil }
        let bottom = geometry.contentOffset.y + geometry.contentInsets.top + geometry.containerSize.height
        return bottom / geometry.contentSize.height
    }
}

private struct RestoreRequest: Equatable {
    let target: Double?
    let isPrepared: Bool
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
