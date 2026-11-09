import SwiftUI

@MainActor
@Observable
final class IPhoneTabBarVisibilityController {
    var isVisible = true

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }
}

private struct IPhoneTabBarVisibilityControllerKey: EnvironmentKey {
    @MainActor
    static let defaultValue: IPhoneTabBarVisibilityController? = nil
}

extension EnvironmentValues {
    var iPhoneTabBarVisibilityController: IPhoneTabBarVisibilityController? {
        get { self[IPhoneTabBarVisibilityControllerKey.self] }
        set { self[IPhoneTabBarVisibilityControllerKey.self] = newValue }
    }
}
