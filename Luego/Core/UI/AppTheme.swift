import SwiftUI
import Textual
import UIKit

private enum AppUIColor {
    static let paperCream = UIColor(red: 252 / 255, green: 252 / 255, blue: 253 / 255, alpha: 1)
    static let brandPurple = UIColor(red: 223 / 255, green: 210 / 255, blue: 224 / 255, alpha: 1)
    static let brandPurpleInk = UIColor(red: 120 / 255, green: 98 / 255, blue: 125 / 255, alpha: 1)
    static let nightBackground = UIColor(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0, alpha: 1)
    static let nightPanel = UIColor(red: 0x1b / 255.0, green: 0x1c / 255.0, blue: 0x22 / 255.0, alpha: 1)
    static let nightElevatedPanel = UIColor(red: 0x23 / 255.0, green: 0x24 / 255.0, blue: 0x2c / 255.0, alpha: 1)
    static let duskPurple = UIColor(red: 0xa0 / 255.0, green: 0x8e / 255.0, blue: 0xad / 255.0, alpha: 1)
    static let duskPurpleInk = UIColor(red: 0xe4 / 255.0, green: 0xda / 255.0, blue: 0xe8 / 255.0, alpha: 1)
    static let appBackground = adaptive(light: paperCream, dark: nightBackground)
    static let regularPanelBackground = adaptive(light: paperCream, dark: nightPanel)
    static let elevatedPanelBackground = adaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.92),
        dark: nightElevatedPanel
    )
    static let mascotPurple = adaptive(light: brandPurple, dark: duskPurple)
    static let mascotPurpleInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let barAccentFill = adaptive(
        light: brandPurple.withAlphaComponent(0.72),
        dark: duskPurple.withAlphaComponent(0.56)
    )
    static let barAccentInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let regularSelectionFill = adaptive(
        light: brandPurple.withAlphaComponent(0.5),
        dark: duskPurple.withAlphaComponent(0.34)
    )
    static let regularSelectionInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let regularGlassTint = adaptive(
        light: brandPurple.withAlphaComponent(0.8),
        dark: duskPurple.withAlphaComponent(0.72)
    )
    static let readerBackground = adaptive(
        light: paperCream,
        dark: UIColor(red: 0x18 / 255.0, green: 0x19 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension Color {
    static let paperCream = Color(uiColor: AppUIColor.paperCream)
    static let appBackground = Color(uiColor: AppUIColor.appBackground)
    static let mascotPurple = Color(uiColor: AppUIColor.mascotPurple)
    static let mascotPurpleInk = Color(uiColor: AppUIColor.mascotPurpleInk)
    static let regularPanelBackground = Color(uiColor: AppUIColor.regularPanelBackground)
    static let elevatedPanelBackground = Color(uiColor: AppUIColor.elevatedPanelBackground)
    static let barAccentFill = Color(uiColor: AppUIColor.barAccentFill)
    static let barAccentInk = Color(uiColor: AppUIColor.barAccentInk)
    static let regularSelectionFill = Color(uiColor: AppUIColor.regularSelectionFill)
    static let regularSelectionInk = Color(uiColor: AppUIColor.regularSelectionInk)
    static let regularOutline = Color.primary.opacity(0.18)
    static let regularGlassTint = Color(uiColor: AppUIColor.regularGlassTint)
    static let readerBackground = Color(uiColor: AppUIColor.readerBackground)
}

extension StructuredText.Style where Self == StructuredText.GitHubStyle {
    static var reader: StructuredText.GitHubStyle { .gitHub }
}

enum AppNavigationChromeStyle {
    case panel
    case transparent
}

enum AppNavigationStyle {
    case largePanel
    case contentLargeTitle
    case largeTransparent
    case inlinePanel
    case inlineTransparent
    case sidebarPanel

    fileprivate var chrome: AppNavigationChromeStyle {
        switch self {
        case .contentLargeTitle, .largeTransparent, .inlineTransparent:
            .transparent
        case .largePanel, .inlinePanel, .sidebarPanel:
            .panel
        }
    }

    fileprivate var titleDisplayMode: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .inlinePanel, .inlineTransparent:
            .inline
        case .largePanel, .contentLargeTitle, .largeTransparent, .sidebarPanel:
            .large
        }
    }
}

enum AppNavigationAppearance {
    static func configurePlatformAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppUIColor.regularPanelBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .font: UIFont.appAppearance(.navigationInlineTitle),
            .foregroundColor: UIColor.label
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont.appAppearance(.navigationLargeTitle),
            .foregroundColor: UIColor.label
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}

extension View {
    func appNavigationStyle(_ style: AppNavigationStyle) -> some View {
        self
            .appNavigationChrome(style.chrome)
            .navigationBarTitleDisplayMode(style.titleDisplayMode)
    }

    @ViewBuilder
    func appNavigationChrome(_ style: AppNavigationChromeStyle = .panel) -> some View {
        switch style {
        case .panel:
            self
                .toolbarBackground(Color.regularPanelBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        case .transparent:
            self
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    func readerContentStyle(baseURL: URL? = nil) -> some View {
        self
            .textual.structuredTextStyle(.reader)
            .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
            .textual.textSelection(.enabled)
    }
}

enum ReaderLayout {
    static func horizontalPadding(for containerWidth: CGFloat) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let maxContentWidth: CGFloat = 700
            let paddingForMaxWidth = max(56, (containerWidth - maxContentWidth) / 2)
            return paddingForMaxWidth
        }

        return 40
    }
}
