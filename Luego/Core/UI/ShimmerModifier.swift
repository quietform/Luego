import SwiftUI

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay(shimmerGradient)
                .mask(content)
                .onAppear(perform: startAnimation)
        }
    }

    private var shimmerGradient: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.5), location: 0.3),
                    .init(color: .white.opacity(0.7), location: 0.5),
                    .init(color: .white.opacity(0.5), location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 2)
            .offset(x: offsetForPhase(width: geometry.size.width))
            .blendMode(.softLight)
        }
    }

    private func offsetForPhase(width: CGFloat) -> CGFloat {
        let startOffset = -width
        let travelDistance = width * 3
        return startOffset + (phase * travelDistance)
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
