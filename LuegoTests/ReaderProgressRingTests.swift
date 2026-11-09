import SwiftUI
import Testing

@MainActor
struct ReaderProgressRingTests {
    @Test(arguments: [
        (CGFloat(0), CGFloat(3000), CGFloat(800), 0),
        (1100, 3000, 800, 50),
        (2200, 3000, 800, 100),
        (2400, 3000, 800, 100),
        (-60, 3000, 800, 0),
        (0, 600, 800, 100),
        (0, 0, 0, 0)
    ])
    func percentIsHowFarThroughTheScrollableTextTheReaderIs(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, percent: Int) {
        #expect(ReaderProgressRing.percent(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight) == percent)
    }

    @Test(arguments: [
        (CGFloat(-122), 0),
        (1000, 50),
        (2122, 100)
    ])
    func percentMeasuresTheScrollViewBeneathTheBars(contentOffset: CGFloat, percent: Int) {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: contentOffset),
            contentSize: CGSize(width: 420, height: 3000),
            contentInsets: EdgeInsets(top: 122, leading: 0, bottom: 34, trailing: 0),
            containerSize: CGSize(width: 420, height: 756)
        )

        #expect(ReaderProgressRing.percent(for: geometry) == percent)
    }

    @Test
    func voiceOverHearsTheReadingProgress() {
        let ring = ReaderProgressRing(percent: 40)

        #expect(accessibilityValues(in: ring) == ["Reading progress": "40%"])
    }
}
