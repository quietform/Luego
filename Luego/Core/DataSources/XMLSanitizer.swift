import Foundation

extension Data {
    nonisolated func sanitizingXMLAmpersands() -> Data {
        guard var xmlString = String(data: self, encoding: .utf8) else { return self }
        xmlString = xmlString.replacingOccurrences(
            of: "&(?!(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);)",
            with: "&amp;",
            options: .regularExpression
        )
        return xmlString.data(using: .utf8) ?? self
    }
}
