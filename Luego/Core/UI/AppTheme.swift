import SwiftUI
import Textual
import UIKit

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

    func readerContentStyle() -> some View {
        self
            .textual.structuredTextStyle(.reader)
            .textual.imageAttachmentLoader(ReaderImageLoader())
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
