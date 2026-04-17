import Foundation

struct SDKVersionsResponse: Codable, Sendable {
    let bundles: [String: BundleInfo]
    let rules: RulesInfo

    struct BundleInfo: Codable, Sendable {
        let version: String
        let size: Int
    }

    struct RulesInfo: Codable, Sendable {
        let version: String
    }
}

struct ParserResult: Sendable {
    let success: Bool
    let content: String?
    let metadata: ParserMetadata?
    let error: String?
}

struct ParserMetadata: Sendable {
    let title: String?
    let publishedDate: String?
    let excerpt: String?
    let siteName: String?
    let thumbnail: String?
}

enum LuegoSDKError: LocalizedError {
    case bundlesNotAvailable
    case downloadFailed(bundleName: String, underlying: Error)
    case networkUnavailable
    case parserInitializationFailed
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundlesNotAvailable:
            return "SDK bundles are not available"
        case .downloadFailed(let bundleName, let error):
            return "Failed to download bundle '\(bundleName)': \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .parserInitializationFailed:
            return "Failed to initialize parser"
        case .parsingFailed(let reason):
            return "Parsing failed: \(reason)"
        }
    }
}
