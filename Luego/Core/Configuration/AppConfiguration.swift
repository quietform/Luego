import Foundation

struct AppConfiguration {
    static let defaultTimeout: TimeInterval = 30
    static let minContentLength = 100

    static let luegoAPIBaseURL = URL(string: "https://esoxjem.com")!
    static let luegoAPIKey = Secrets.luegoAPIKey
    static let luegoAPITimeout: TimeInterval = 30
    static let luegoAPIUserAgent = luegoAPIUserAgent(info: Bundle.main.infoDictionary ?? [:], system: operatingSystem)

    static let sdkBundleNames = ["linkedom", "readability", "turndown", "parser"]

    static let cloudKitContainerIdentifier = "iCloud.com.esoxjem.Luego"

    static func luegoAPIUserAgent(info: [String: Any], system: String) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "Luego/\(version) (build \(build); \(system))"
    }

    private static var operatingSystem: String {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion
        let name = processInfo.isiOSAppOnMac ? "macOS" : "iOS"
        return "\(name) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
