import SwiftUI
import CoreText
import UIKit

enum AppFontFamily {
    case lora
    case nunito
    case system
}

enum AppTextRole {
    case body
    case navigationLargeTitle
    case navigationInlineTitle
    case sidebarTitle
    case sidebarItem
    case listTitle
    case listExcerpt
    case listMetadata
    case emptyStateTitle
    case emptyStateBody
    case actionLabel
    case auxiliaryStatus
    case sheetTitle

    fileprivate var family: AppFontFamily {
        switch self {
        case .navigationLargeTitle, .navigationInlineTitle, .sidebarTitle, .listTitle, .emptyStateTitle, .sheetTitle:
            .lora
        case .listMetadata, .auxiliaryStatus:
            .system
        case .body, .sidebarItem, .listExcerpt, .emptyStateBody, .actionLabel:
            .nunito
        }
    }

    fileprivate var weight: Font.Weight {
        switch self {
        case .navigationLargeTitle, .sidebarTitle:
            .regular
        case .navigationInlineTitle:
            .regular
        case .sidebarItem:
            .regular
        case .actionLabel, .sheetTitle:
            .semibold
        default:
            .regular
        }
    }

    fileprivate var textStyle: Font.TextStyle {
        switch self {
        case .body:
            .body
        case .navigationLargeTitle, .sidebarTitle:
            .largeTitle
        case .navigationInlineTitle, .listTitle:
            .headline
        case .sidebarItem:
            .body
        case .listExcerpt, .actionLabel:
            .subheadline
        case .listMetadata, .auxiliaryStatus:
            .caption
        case .emptyStateTitle:
            .title2
        case .emptyStateBody:
            .callout
        case .sheetTitle:
            .title3
        }
    }

    fileprivate var basePointSize: CGFloat {
        switch self {
        case .body:
            17
        case .navigationLargeTitle, .sidebarTitle:
            34
        case .navigationInlineTitle, .sidebarItem:
            17
        case .listTitle:
            15
        case .listExcerpt:
            13
        case .actionLabel:
            15
        case .listMetadata, .auxiliaryStatus:
            12
        case .emptyStateTitle:
            22
        case .emptyStateBody:
            16
        case .sheetTitle:
            20
        }
    }

    fileprivate var selectedWeight: Font.Weight {
        switch self {
        case .sidebarItem:
            .semibold
        default:
            weight
        }
    }
}

enum AppTypography {
    static let loraPostScriptName = "Lora-Regular"
    static let nunitoPostScriptName = "NunitoSans-12ptRegular"
    private static let loraFileName = "Lora"
    private static let nunitoFileName = "NunitoSans"
    private static let loraFileExtension = "ttf"
    private static let nunitoFileExtension = "ttf"
    static let loraWeightAxisIdentifier = fourCharacterCode("wght")
    static let nunitoWeightAxisIdentifier = fourCharacterCode("wght")

    static func registerFonts() {
        registerFont(named: loraFileName, extension: loraFileExtension)
        registerFont(named: nunitoFileName, extension: nunitoFileExtension)
    }

    static func fontSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .largeTitle:
            34
        case .title:
            28
        case .title2:
            22
        case .title3:
            20
        case .headline:
            17
        case .subheadline:
            15
        case .body:
            14
        case .callout:
            14
        case .footnote:
            13
        case .caption:
            12
        case .caption2:
            11
        @unknown default:
            17
        }
    }

    static func variableFontAxisValue(for weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            400
        case .medium:
            500
        case .semibold:
            600
        case .bold, .heavy, .black:
            700
        default:
            400
        }
    }

    private static func fourCharacterCode(_ value: String) -> Int {
        value.utf8.reduce(0) { partialResult, character in
            (partialResult << 8) | Int(character)
        }
    }

    private static func registerFont(named fileName: String, extension fileExtension: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            return
        }

        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)

        if didRegister {
            return
        }

        guard let error = registrationError?.takeRetainedValue() else {
            return
        }

        let alreadyRegisteredCode = CTFontManagerError.alreadyRegistered.rawValue
        let domain = CFErrorGetDomain(error) as String
        let code = CFErrorGetCode(error)

        if domain == kCTFontManagerErrorDomain as String, code == alreadyRegisteredCode {
            return
        }
    }

    static func font(for role: AppTextRole, isEmphasized: Bool = false) -> Font {
        Font(uiFont(for: role, isEmphasized: isEmphasized))
    }

    private static func resolvedWeight(for role: AppTextRole, isEmphasized: Bool) -> Font.Weight {
        if isEmphasized {
            return role.selectedWeight
        }

        return role.weight
    }
}

extension Font {
    static func app(_ role: AppTextRole, emphasized: Bool = false) -> Font {
        AppTypography.font(for: role, isEmphasized: emphasized)
    }

    static func lora(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font(UIFont.lora(forTextStyle: textStyle.uiTextStyle, weight: weight))
    }

    static func nunito(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font(UIFont.nunito(forTextStyle: textStyle.uiTextStyle, weight: weight))
    }
}

extension UIFont {
    static func app(_ role: AppTextRole, emphasized: Bool = false) -> UIFont {
        AppTypography.uiFont(for: role, isEmphasized: emphasized)
    }

    static func appAppearance(_ role: AppTextRole, emphasized: Bool = false) -> UIFont {
        AppTypography.uiFont(for: role, isEmphasized: emphasized, scalesWithDynamicType: false)
    }

    static func lora(forTextStyle textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil, weight: Font.Weight = .regular) -> UIFont {
        lora(forTextStyle: textStyle, pointSize: pointSize, weight: weight, scalesWithDynamicType: true)
    }

    static func lora(forTextStyle textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil, weight: Font.Weight = .regular, scalesWithDynamicType: Bool) -> UIFont {
        let pointSize = pointSize ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).pointSize
        let axisValue = AppTypography.variableFontAxisValue(for: weight)
        let variationAttributeName = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: AppTypography.loraPostScriptName,
            variationAttributeName: [AppTypography.loraWeightAxisIdentifier: axisValue]
        ])
        let font = UIFont(descriptor: descriptor, size: pointSize)
        guard scalesWithDynamicType else {
            return font
        }

        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    static func nunito(forTextStyle textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil, weight: Font.Weight = .regular) -> UIFont {
        nunito(forTextStyle: textStyle, pointSize: pointSize, weight: weight, scalesWithDynamicType: true)
    }

    static func nunito(forTextStyle textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil, weight: Font.Weight = .regular, scalesWithDynamicType: Bool) -> UIFont {
        let pointSize = pointSize ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).pointSize
        let axisValue = AppTypography.variableFontAxisValue(for: weight)
        let variationAttributeName = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: AppTypography.nunitoPostScriptName,
            variationAttributeName: [AppTypography.nunitoWeightAxisIdentifier: axisValue]
        ])
        let font = UIFont(descriptor: descriptor, size: pointSize)
        guard scalesWithDynamicType else {
            return font
        }

        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }
}

extension AppTypography {
    static func uiFont(for role: AppTextRole, isEmphasized: Bool = false) -> UIFont {
        uiFont(for: role, isEmphasized: isEmphasized, scalesWithDynamicType: true)
    }

    static func uiFont(for role: AppTextRole, isEmphasized: Bool = false, scalesWithDynamicType: Bool) -> UIFont {
        let weight = resolvedWeight(for: role, isEmphasized: isEmphasized)
        switch role.family {
        case .lora:
            return UIFont.lora(
                forTextStyle: role.textStyle.uiTextStyle,
                pointSize: role.basePointSize,
                weight: weight,
                scalesWithDynamicType: scalesWithDynamicType
            )
        case .nunito:
            return UIFont.nunito(
                forTextStyle: role.textStyle.uiTextStyle,
                pointSize: role.basePointSize,
                weight: weight,
                scalesWithDynamicType: scalesWithDynamicType
            )
        case .system:
            return UIFont.preferredFont(forTextStyle: role.textStyle.uiTextStyle)
        }
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle:
            .largeTitle
        case .title:
            .title1
        case .title2:
            .title2
        case .title3:
            .title3
        case .headline:
            .headline
        case .subheadline:
            .subheadline
        case .body:
            .body
        case .callout:
            .callout
        case .footnote:
            .footnote
        case .caption:
            .caption1
        case .caption2:
            .caption2
        @unknown default:
            .body
        }
    }
}
