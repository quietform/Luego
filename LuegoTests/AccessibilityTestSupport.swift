import SwiftUI
import UIKit

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
    inspectAccessibility(of: view, accessibleElements(in:))
}

@MainActor
func inspectAccessibility<Result>(of view: some View, _ inspect: (UIView) -> Result) -> Result {
    AccessibilityAutomation.enable()
    let controller = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.view.layoutIfNeeded()
    return inspect(controller.view)
}

private func accessibleElements(in element: NSObject) -> [AccessibleElement] {
    accessibleObjects(in: element).map {
        AccessibleElement(label: $0.accessibilityLabel ?? "", isImage: $0.accessibilityTraits.contains(.image))
    }
}

private enum AccessibilityAutomation {
    private typealias IsEnabled = @convention(c) () -> Int32
    private typealias SetEnabled = @convention(c) (Int32) -> Void

    private nonisolated(unsafe) static var restore: SetEnabled?
    private nonisolated(unsafe) static var previousState: Int32 = 0
    private nonisolated(unsafe) static var isEnabled = false

    @MainActor
    static func enable() {
        guard !isEnabled,
              let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let isEnabledSymbol = dlsym(library, "_AXSAutomationEnabled"),
              let setEnabledSymbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
        let setEnabled = unsafeBitCast(setEnabledSymbol, to: SetEnabled.self)
        previousState = unsafeBitCast(isEnabledSymbol, to: IsEnabled.self)()
        restore = setEnabled
        isEnabled = true
        setEnabled(1)
        atexit { AccessibilityAutomation.restore?(AccessibilityAutomation.previousState) }
    }
}

@MainActor
func accessibilityFrames(in view: some View, width: CGFloat) -> [String: CGRect] {
    inspectAccessibility(of: view.frame(width: width)) { root in
        Dictionary(accessibleObjects(in: root).map { ($0.accessibilityLabel ?? "", $0.accessibilityFrame) }) { first, _ in first }
    }
}

private func accessibleObjects(in element: NSObject) -> [NSObject] {
    if element.isAccessibilityElement { return [element] }
    let children = (element.accessibilityElements as? [NSObject])
        ?? (0..<max(element.accessibilityElementCount(), 0)).compactMap { element.accessibilityElement(at: $0) as? NSObject }
    let views = (element as? UIView)?.subviews ?? []
    return (children.isEmpty ? views : children).flatMap(accessibleObjects)
}

@MainActor
func accessibilityValues(in view: some View) -> [String: String] {
    inspectAccessibility(of: view) { root in
        Dictionary(accessibleObjects(in: root).map { ($0.accessibilityLabel ?? "", $0.accessibilityValue ?? "") }) { first, _ in first }
    }
}
