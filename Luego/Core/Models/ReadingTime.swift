import Foundation

enum ReadingTime {
    private nonisolated static let wordsPerMinute = 200

    nonisolated static func minutes(wordCount: Int?, content: String?) -> Int? {
        let words = wordCount.flatMap { $0 > 0 ? $0 : nil } ?? content.map(countWords) ?? 0
        guard words > 0 else { return nil }
        return max(1, Int(ceil(Double(words) / Double(wordsPerMinute))))
    }

    private nonisolated static func countWords(in content: String) -> Int {
        content.split(whereSeparator: \.isWhitespace).count
    }
}
