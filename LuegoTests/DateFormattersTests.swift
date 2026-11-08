import Foundation
import Testing

struct DateFormattersTests {
    private let noonUTCOnEighthNovember2026 = Date(timeIntervalSince1970: 1_794_139_200)

    @Test(arguments: [
        ("en_US", "Nov 8, 2026"),
        ("en_GB", "8 Nov 2026")
    ])
    func articleDateFollowsTheReadersLocale(localeIdentifier: String, expected: String) {
        let text = DateFormatters.articleDate(noonUTCOnEighthNovember2026, locale: Locale(identifier: localeIdentifier))

        #expect(text == expected)
    }
}
