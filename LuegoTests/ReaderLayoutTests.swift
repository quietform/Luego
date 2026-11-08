import SwiftUI
import Testing

@MainActor
struct ReaderLayoutTests {
    init() {
        LoraTestFonts.register()
    }

    @Test(arguments: [CGFloat(420), 514, 554, 700])
    func narrowReadingPanesKeepFortyPointMargins(width: CGFloat) {
        #expect(ReaderLayout.horizontalPadding(for: width) == 40)
    }

    @Test(arguments: [CGFloat(834), 1024, 1366])
    func wideReadingPanesKeepTheTextColumnAtSevenHundredPoints(width: CGFloat) {
        let contentWidth = width - 2 * ReaderLayout.horizontalPadding(for: width)

        #expect(contentWidth == 700)
    }

    @Test
    func widerReadingPanesUseLargerBodyTextWhilePhoneTextKeepsItsSize() {
        let sample = "A comfortable reading column"
        let baseline = renderedWidth(of: Text(sample).font(.lora(.body)))
        let phone = renderedWidth(of: Text(sample).font(ReaderLayout.bodyFont(for: 420)))
        let widerPane = renderedWidth(of: Text(sample).font(ReaderLayout.bodyFont(for: 554)))

        #expect(abs(phone - baseline) < 1)
        #expect(widerPane > phone * 1.08)
        #expect(widerPane < phone * 1.15)
    }
}
