import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderBodyPlaceholderTests {
    @Test
    func voiceOverHearsThatTheArticleIsLoading() throws {
        let controller = UIHostingController(rootView: ReaderBodyPlaceholder().padding())
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()

        #expect(accessibilityLabels(in: controller.view) == ["Loading article"])
    }

    private func accessibilityLabels(in element: NSObject) -> [String] {
        if element.isAccessibilityElement {
            return [element.accessibilityLabel ?? ""]
        }
        let children = (element.accessibilityElements as? [NSObject])
            ?? (0..<max(element.accessibilityElementCount(), 0)).compactMap { element.accessibilityElement(at: $0) as? NSObject }
        let views = (element as? UIView)?.subviews ?? []
        return (children.isEmpty ? views : children).flatMap(accessibilityLabels)
    }
}
