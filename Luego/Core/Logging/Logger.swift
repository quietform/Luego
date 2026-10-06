import OSLog

nonisolated final class Logger: Sendable {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.esoxjem.Luego"
    private let osLogger: os.Logger
    private let category: String

    init(category: String) {
        self.category = category
        self.osLogger = os.Logger(subsystem: Self.subsystem, category: category)
    }

    func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        stream(message, level: .debug)
    }

    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        stream(message, level: .info)
    }

    func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        stream(message, level: .warning)
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        stream(message, level: .error)
    }

    private func stream(_ message: String, level: LogLevel) {
        let cat = category
        Task { @MainActor in
            LogStream.shared.append(
                LogEntry(timestamp: Date(), category: cat, level: level, message: message)
            )
        }
    }
}

extension Logger {
    static let sdk = Logger(category: "SDK")
    static let api = Logger(category: "API")
    nonisolated static let parser = Logger(category: "Parser")
    static let content = Logger(category: "Content")
    static let cache = Logger(category: "Cache")
    static let article = Logger(category: "Article")
    static let sharing = Logger(category: "Sharing")
    static let cloudKit = Logger(category: "CloudKit")
    static let reader = Logger(category: "Reader")
}
