import Foundation
import Testing

@MainActor
struct LuegoParserDataSourceTests {
    @Test(arguments: ["success", "failure", "undefined", "null", "throw"])
    func mainActorRemainsResponsiveDuringParsing(outcome: String) async {
        let sdk = ParserFixtureSDK()
        let parser = LuegoParserDataSource(sdkManager: sdk)
        let url = URL(string: "https://example.com/article")!

        for call in 1...2 {
            var mainActorRan = false
            let previousRulesLoads = sdk.rulesLoads
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    if sdk.rulesLoads > previousRulesLoads {
                        mainActorRan = true
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }

            let result = await parser.parse(html: outcome, url: url)

            #expect(mainActorRan)
            heartbeat.cancel()
            await heartbeat.value

            switch outcome {
            case "success":
                #expect(result?.success == true)
                #expect(result?.content == "success \(call)")
                #expect(result?.metadata?.title == "Fixture title \(call)")
                #expect(result?.metadata?.publishedDate == "2026-10-06T10:00:00Z")
                #expect(result?.metadata?.excerpt == nil)
                #expect(result?.metadata?.siteName == nil)
                #expect(result?.metadata?.thumbnail == nil)
            case "failure":
                #expect(result?.success == false)
                #expect(result?.error == "Fixture failure")
                #expect(result?.content == nil)
            default:
                #expect(result == nil)
            }

            sdk.rulesTitle = "Fixture title 2"
        }

        #expect(sdk.bundleLoads == 1)
    }
}

@MainActor
private final class ParserFixtureSDK: LuegoSDKManagerProtocol {
    var rulesTitle = "Fixture title 1"
    private(set) var bundleLoads = 0
    private(set) var rulesLoads = 0

    func ensureSDKReady() async {}
    func checkForUpdates() async -> SDKUpdateResult { .failed(LuegoSDKError.networkUnavailable) }
    func isSDKAvailable() -> Bool { true }
    func getVersionInfo() -> SDKVersionInfo? { nil }

    func loadBundles() -> [String: String]? {
        bundleLoads += 1
        return [
            "linkedom": "",
            "readability": "",
            "turndown": "",
            "parser": """
            var parseCount = 0;
            var LuegoParser = {
                parse: function(html, url, rules) {
                    var end = Date.now() + 200;
                    while (Date.now() < end) {}
                    parseCount += 1;
                    switch (html) {
                        case "failure": return {success: false, error: "Fixture failure"};
                        case "undefined": return undefined;
                        case "null": return null;
                        case "throw": throw new Error("Fixture exception");
                        default: return {
                            success: true,
                            content: html + " " + parseCount,
                            metadata: {
                                title: rules.title,
                                publishedDate: "2026-10-06T10:00:00Z",
                                excerpt: "undefined",
                                siteName: "",
                                thumbnail: null
                            }
                        };
                    }
                }
            };
            """
        ]
    }

    func loadRules() -> Data? {
        rulesLoads += 1
        return try? JSONSerialization.data(withJSONObject: ["title": rulesTitle])
    }
}
