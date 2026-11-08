import Testing

struct ReadingTimeTests {
    @Test(arguments: [
        (Int?.some(600), String?.none, Int?.some(3)),
        (.some(1), nil, .some(1)),
        (.none, .some(Array(repeating: "word", count: 250).joined(separator: " ")), .some(2)),
        (.some(0), .some("Two words"), .some(1)),
        (.none, .none, .none),
        (.none, .some("  \n "), .none),
        (.some(0), .none, .none)
    ])
    func minutesComeFromTheWordCountOrTheTextAtTwoHundredWordsAMinute(wordCount: Int?, content: String?, minutes: Int?) {
        #expect(ReadingTime.minutes(wordCount: wordCount, content: content) == minutes)
    }
}
