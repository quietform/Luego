import SwiftUI

struct ReaderProgressRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(percent)%")
    }

    static func percent(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Int {
        guard contentHeight > 0 else { return 0 }
        let scrollableHeight = contentHeight - viewportHeight
        guard scrollableHeight > 0 else { return 100 }
        let fraction = min(1, max(0, scrollOffset / scrollableHeight))
        return Int((fraction * 100).rounded())
    }
}
