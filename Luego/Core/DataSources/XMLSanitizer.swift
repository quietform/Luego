import Foundation

extension Data {
    nonisolated func sanitizingXMLAmpersands() -> Data {
        guard let xml = String(data: self, encoding: .utf8) else { return self }
        var result = ""
        var remaining = xml[...]
        while let cdataStart = remaining.range(of: "<![CDATA[") {
            result += Self.escapingBareAmpersands(in: remaining[..<cdataStart.lowerBound])
            guard let cdataEnd = remaining[cdataStart.upperBound...].range(of: "]]>") else {
                result += remaining[cdataStart.lowerBound...]
                remaining = ""
                break
            }
            result += remaining[cdataStart.lowerBound..<cdataEnd.upperBound]
            remaining = remaining[cdataEnd.upperBound...]
        }
        result += Self.escapingBareAmpersands(in: remaining)
        return Data(result.utf8)
    }

    private nonisolated static func escapingBareAmpersands(in text: Substring) -> String {
        text.replacingOccurrences(
            of: "&(?!(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);)",
            with: "&amp;",
            options: .regularExpression
        )
    }
}
