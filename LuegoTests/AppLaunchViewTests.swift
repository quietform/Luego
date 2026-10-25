import Testing

struct AppLaunchViewTests {
    @Test
    func launchFinishingBeforeTheDelaySkipsTheReveal() async {
        let reveal = Task { await AppLaunchView.waitToReveal(after: .seconds(10)) }

        reveal.cancel()

        #expect(await reveal.value == false)
    }
}
