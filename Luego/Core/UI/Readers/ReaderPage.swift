import SwiftUI

private let restorationAnchor = "ReaderPage.restoration"
private let restorationScroll: Duration = .milliseconds(300)

struct ReaderPage: View {
    let header: ReaderArticleHeader
    let markdown: String?
    var restoringTo: Double? = nil
    var onRestored: (Double?) -> Void = { _ in }
    var onReadingPositionChange: (Double?) -> Void = { _ in }
    @State private var geometry = PageGeometry()
    @State private var reported = ReportedPosition.none
    @State private var anchorPosition: Double?

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    ReaderColumn(header: header, markdown: markdown, width: viewport.size.width) { prepared in
                        update { $0.isPrepared = prepared }
                    }
                    .background { restorationTarget }
                    // Each callback reports straight away. Waiting for onChange or for scroll geometry to
                    // notice the content size can miss the last change when text finishes growing
                    // without anything else updating, which leaves a stale position.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        update { $0.contentHeight = height }
                    }
                }
                .readingProgress(isReported: markdown != nil)
                .onScrollGeometryChange(for: ScrollViewport.self, of: ScrollViewport.init) { _, newViewport in
                    update { $0.viewport = newViewport }
                }
                .onAppear { reportPosition() }
                .onChange(of: restoringTo, initial: true) { _, target in
                    if let target { anchorPosition = target }
                }
                .task(id: RestoreRequest(target: restoringTo, isPrepared: geometry.isPrepared)) {
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

    private func update(_ change: (inout PageGeometry) -> Void) {
        change(&geometry)
        reportPosition()
    }

    private func reportPosition() {
        let position = geometry.readingPosition
        guard reported != .position(position) else { return }
        reported = .position(position)
        onReadingPositionChange(position)
    }

    private func restore(using proxy: ScrollViewProxy) async {
        guard restoringTo != nil, geometry.isPrepared else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: restorationScroll / .seconds(1))) {
            proxy.scrollTo(restorationAnchor, anchor: .bottom)
        }
        try? await Task.sleep(for: restorationScroll)
        guard !Task.isCancelled else { return }
        onRestored(geometry.readingPosition)
    }
}

/// What the page knows about its layout. The reading position is the visible bottom as a fraction
/// of the content height, once the article is prepared.
private struct PageGeometry {
    var isPrepared = false
    var contentHeight: CGFloat = 0
    var viewport: ScrollViewport?

    var readingPosition: Double? {
        guard isPrepared, let viewport, contentHeight > 0 else { return nil }
        return (viewport.top + viewport.height) / contentHeight
    }
}

/// The part of the scrolled content beneath the bars, in content coordinates.
private struct ScrollViewport: Equatable {
    let top: CGFloat
    let height: CGFloat

    init(_ geometry: ScrollGeometry) {
        top = geometry.contentOffset.y + geometry.contentInsets.top
        height = geometry.containerSize.height
    }
}

private enum ReportedPosition: Equatable {
    case none
    case position(Double?)
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
