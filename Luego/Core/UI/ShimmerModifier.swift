import SwiftUI

struct ShimmerModifier: ViewModifier {
    private static let sweepDuration: TimeInterval = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // A timeline keeps the sweep running in List cells, which drop animations started on appear.
            TimelineView(.animation) { timeline in
                content.mask {
                    sweep(phase: Self.phase(at: timeline.date))
                }
            }
        }
    }

    // A faded band crosses the content, so the effect shows in light and dark mode and leaves the rest untouched.
    private func sweep(phase: CGFloat) -> some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.35),
                    .init(color: .black.opacity(0.4), location: 0.5),
                    .init(color: .black, location: 0.65)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 3)
            .offset(x: geometry.size.width * (2 * phase - 2))
        }
    }

    private static func phase(at date: Date) -> CGFloat {
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration
        return progress * progress * (3 - 2 * progress)
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
