import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderBodyPlaceholderTests {
    @Test
    func voiceOverHearsThatTheArticleIsLoading() {
        #expect(accessibilityLabels(in: ReaderBodyPlaceholder().padding()) == ["Loading article"])
    }
}

struct AccessibleElement: Equatable {
    let label: String
    let isImage: Bool

    static func image(_ label: String) -> AccessibleElement {
        AccessibleElement(label: label, isImage: true)
    }
}

@MainActor
func accessibilityLabels(in view: some View) -> [String] {
    accessibleElements(in: view).map(\.label)
}

@MainActor
func accessibleElements(in view: some View) -> [AccessibleElement] {
    let controller = UIHostingController(rootView: view)
    let window = UIWindow()
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.view.layoutIfNeeded()
    return accessibleElements(in: controller.view)
}

private func accessibleElements(in element: NSObject) -> [AccessibleElement] {
    if element.isAccessibilityElement {
        return [AccessibleElement(
            label: element.accessibilityLabel ?? "",
            isImage: element.accessibilityTraits.contains(.image)
        )]
    }
    let children = (element.accessibilityElements as? [NSObject])
        ?? (0..<max(element.accessibilityElementCount(), 0)).compactMap { element.accessibilityElement(at: $0) as? NSObject }
    let views = (element as? UIView)?.subviews ?? []
    return (children.isEmpty ? views : children).flatMap(accessibleElements)
}
