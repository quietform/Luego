import SwiftUI
import UIKit

/// Hosts a view in a window for tests and lets them wait for SwiftUI to settle.
@MainActor
final class PageHost {
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    private let controller: UIHostingController<AnyView>

    init(_ page: some View) {
        controller = UIHostingController(rootView: AnyView(page))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    var view: UIView { controller.view }

    var scrollView: UIScrollView? { Self.scrollView(in: controller.view) }

    var visibleBottom: Double? {
        guard let scroll = scrollView, scroll.contentSize.height > 0 else { return nil }
        return (scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom) / scroll.contentSize.height
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
        }
    }

    func close() {
        window.isHidden = true
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(scrollView).first
    }
}
