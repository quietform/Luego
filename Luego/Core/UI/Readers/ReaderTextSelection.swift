import SwiftUI
import UIKit

/// Clears reader text selections. Textual selects through one non-editable `UITextInput` view per
/// passage, and only clears that selection when a tap lands on the same view.
enum ReaderTextSelection {
    /// Clears the selection in every passage under `root` except the one at `point`, which handles
    /// the tap itself (clearing its selection, or opening a link).
    static func dismiss(in root: UIView, keepingSelectionAt point: CGPoint) {
        for passage in passages(in: root) where !passage.bounds.contains(passage.convert(point, from: root)) {
            guard let input = passage as? UITextInput, input.selectedTextRange != nil else { continue }
            input.selectedTextRange = nil
        }
    }

    private static func passages(in view: UIView) -> [UIView] {
        if view is UITextInput, !(view is UITextField), !(view is UITextView) { return [view] }
        return view.subviews.flatMap(passages(in:))
    }
}

/// Clears selections outside the tapped passage when the reader page is tapped. It recognizes
/// alongside other gestures and lets touches through, so scrolling, links, and Textual's own taps
/// still work.
struct ReaderSelectionDismissal: UIGestureRecognizerRepresentable {
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        return tap
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, let view = recognizer.view else { return }
        ReaderTextSelection.dismiss(in: view, keepingSelectionAt: recognizer.location(in: view))
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
