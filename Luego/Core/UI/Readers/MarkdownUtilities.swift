import Foundation

nonisolated func stripFirstH1FromMarkdown(_ markdown: String, matchingTitle: String) -> String {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    let normalizedTitle = normalizeForComparison(matchingTitle)

    let matchingH1Index = findMatchingH1Index(in: lines, normalizedTitle: normalizedTitle)

    guard let indexToRemove = matchingH1Index else {
        return markdown
    }

    var resultLines = Array(lines)
    resultLines.remove(at: indexToRemove)

    while indexToRemove < resultLines.count {
        let nextLine = resultLines[indexToRemove].trimmingCharacters(in: .whitespaces)
        if nextLine.isEmpty {
            resultLines.remove(at: indexToRemove)
        } else {
            break
        }
    }

    return resultLines.joined(separator: "\n")
}

nonisolated func findMatchingH1Index(in lines: [String.SubSequence], normalizedTitle: String) -> Int? {
    let h1Indices = lines.indices.filter { index in
        lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("# ")
    }

    for index in h1Indices.prefix(3) {
        let h1Text = lines[index]
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces)

        let normalizedH1 = normalizeForComparison(String(h1Text))

        if areSimilar(normalizedH1, normalizedTitle) {
            return index
        }
    }

    return nil
}

nonisolated func normalizeForComparison(_ text: String) -> String {
    return text
        .lowercased()
        .components(separatedBy: .punctuationCharacters)
        .joined()
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

nonisolated func areSimilar(_ text1: String, _ text2: String) -> Bool {
    if text1 == text2 {
        return true
    }

    let words1 = Set(text1.split(separator: " "))
    let words2 = Set(text2.split(separator: " "))
    let intersection = words1.intersection(words2)
    let union = words1.union(words2)

    guard !union.isEmpty else { return false }

    let similarity = Double(intersection.count) / Double(union.count)
    return similarity > 0.7
}
