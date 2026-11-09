import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReadingPositionSessionTests {
    @Test
    func aPlaceTheReaderStopsAtIsSavedOnceScrollingSettles() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: {})

        session.pageReported(0.5)

        #expect(await saves.next() == 0.5)
    }

    @Test
    func movingAgainBeforeScrollingSettlesSavesOnlyWhereTheReaderStops() async {
        let saves = SaveRecorder()
        let settling = SettleGate()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: settling.wait)

        session.pageReported(0.3)
        session.pageReported(0.6)
        settling.release()

        #expect(await saves.next() == 0.6)
    }

    @Test
    func aPlaceThatFailedToSaveIsTriedAgainAfterASmallMove() async {
        let saves = SaveRecorder(failing: [0.5])
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: {})
        session.pageReported(0.5)
        #expect(await saves.next() == 0.5)

        session.pageReported(0.505)

        #expect(await saves.next() == 0.505)
    }

    @Test
    func movingLessThanOnePercentFromTheSavedPlaceSavesNothing() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0.5, save: saves.record, settle: {})

        session.pageReported(0.505)

        #expect(await saves.nothingSaved())
    }

    @Test
    func reachingNinetyFivePercentSavesTheArticleAsFinished() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: {})

        session.pageReported(0.96)

        #expect(await saves.next() == 1)
    }

    @Test
    func openingAnArticleWithASavedPlaceAsksThePageToBringItBack() {
        let session = ReadingPositionSession(savedPosition: 0.4, save: { _ in true }, settle: {})

        session.pageReported(0.05)

        #expect(session.restoringTo == 0.4)
    }

    @Test
    func placesPassedWhileRestoringAreNotSaved() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0.4, save: saves.record, settle: {})

        session.pageReported(0.05)
        session.pageReported(0.2)

        #expect(await saves.nothingSaved())
    }

    @Test
    func onceRestoredScrollingOnSavesTheNewPlace() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0.4, save: saves.record, settle: {})
        session.pageReported(0.05)

        session.pageRestored(at: 0.4)
        session.pageReported(0.6)

        #expect(session.restoringTo == nil)
        #expect(await saves.next() == 0.6)
    }

    @Test
    func leavingSavesWhereTheReaderIsWithoutWaitingForScrollingToSettle() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.leave()

        #expect(await saves.next() == 0.5)
    }

    @Test
    func leavingBeforeTheSavedPlaceIsBackKeepsIt() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0.4, save: saves.record, settle: {})
        session.pageReported(0.05)

        session.leave()

        #expect(await saves.nothingSaved())
    }

    @Test
    func refreshingSavesWhereTheReaderIsWithoutWaitingForScrollingToSettle() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.refresh()

        #expect(await saves.next() == 0.5)
    }

    @Test
    func afterRefreshingThePageIsAskedToBringTheReaderBack() {
        let session = ReadingPositionSession(savedPosition: 0, save: { _ in true }, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.refresh()
        session.pageReported(nil)
        session.pageReported(0.02)

        #expect(session.restoringTo == 0.5)
    }

    @Test
    func aPlaceThatFailedToSaveOnRefreshIsSavedOnceTheReaderIsBack() async {
        let saves = SaveRecorder(failing: [0.5])
        let settling = SettleGate()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: settling.wait)
        session.pageReported(0.5)
        session.refresh()
        #expect(await saves.next() == 0.5)
        session.pageReported(nil)
        session.pageReported(0.02)
        #expect(session.restoringTo == 0.5)

        session.pageRestored(at: 0.5)
        settling.release()

        #expect(await saves.next() == 0.5)
    }

    @Test
    func aPlaceSavedOnRefreshIsNotSavedAgainOnceTheReaderIsBack() async {
        let saves = SaveRecorder()
        let settling = SettleGate()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: settling.wait)
        session.pageReported(0.5)
        session.refresh()
        #expect(await saves.next() == 0.5)
        session.pageReported(nil)
        session.pageReported(0.02)

        session.pageRestored(at: 0.5)
        settling.release()

        #expect(await saves.noFurtherSaves())
    }

    @Test
    func theOldTextStillOnScreenAfterRefreshingDoesNotUseUpTheRestore() {
        let session = ReadingPositionSession(savedPosition: 0, save: { _ in true }, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.refresh()
        session.pageReported(0.5)

        #expect(session.restoringTo == nil)
    }

    @Test
    func refreshingWhileTheArticleIsStillLoadingStillBringsTheReaderBack() {
        let session = ReadingPositionSession(savedPosition: 0.4, save: { _ in true }, settle: {})
        session.pageReported(nil)

        session.refresh()
        session.pageReported(0.02)

        #expect(session.restoringTo == 0.4)
    }

    @Test
    func refreshingWhileTheArticleIsStillLoadingKeepsSavingPlaces() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0, save: saves.record, settle: {})
        session.pageReported(nil)

        session.refresh()
        session.pageReported(0.5)

        #expect(await saves.next() == 0.5)
    }

    @Test
    func anOlderSaveFinishingAfterRefreshDoesNotChangeWhereTheReaderReturns() async {
        let saves = SaveRecorder()
        let slowSave = SaveGate()
        let session = ReadingPositionSession(savedPosition: 0, save: { position in
            if position == 0.5 { await slowSave.hold() }
            return await saves.record(position)
        }, settle: {})
        session.pageReported(0.5)
        await slowSave.arrival()

        session.pageReported(0.6)
        session.refresh()
        slowSave.release()
        while let saved = await saves.next(), saved != 0.5 {}
        await Task.yield()
        session.pageReported(nil)
        session.pageReported(0.02)

        #expect(session.restoringTo == 0.6)
    }

    @Test
    func wherePageSaysItRestoredToCountsAsWhereTheReaderIs() async {
        let saves = SaveRecorder()
        let session = ReadingPositionSession(savedPosition: 0.4, save: saves.record, settle: SettleGate().wait)
        session.pageReported(0.05)

        session.pageRestored(at: 1)
        session.leave()

        #expect(await saves.next() == 1)
    }
}

@MainActor
private final class SaveGate {
    private var held: CheckedContinuation<Void, Never>?
    private var arrived: CheckedContinuation<Void, Never>?

    func hold() async {
        arrived?.resume()
        arrived = nil
        await withCheckedContinuation { held = $0 }
    }

    func arrival() async {
        guard held == nil else { return }
        await withCheckedContinuation { arrived = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@MainActor
private final class SettleGate {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isReleased = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
private final class SaveRecorder {
    private let failing: Set<Double>
    private var saved: [Double] = []
    private var delivered = 0

    init(failing: Set<Double> = []) {
        self.failing = failing
    }

    func record(_ position: Double) async -> Bool {
        saved.append(position)
        return !failing.contains(position)
    }

    func nothingSaved() async -> Bool {
        try? await Task.sleep(for: .milliseconds(200))
        return saved.isEmpty
    }

    func noFurtherSaves() async -> Bool {
        try? await Task.sleep(for: .milliseconds(200))
        return saved.count == delivered
    }

    func next() async -> Double? {
        let deadline = ContinuousClock.now + .seconds(2)
        while saved.count <= delivered, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard saved.count > delivered else { return nil }
        defer { delivered += 1 }
        return saved[delivered]
    }
}
