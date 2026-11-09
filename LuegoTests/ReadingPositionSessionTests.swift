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
        let session = ReadingPositionSession(savedPosition: 0.4, save: { _ in }, settle: {})

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

        session.pageRestored()
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
        let session = ReadingPositionSession(savedPosition: 0, save: { _ in }, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.refresh()
        session.pageReported(nil)
        session.pageReported(0.02)

        #expect(session.restoringTo == 0.5)
    }

    @Test
    func theOldTextStillOnScreenAfterRefreshingDoesNotUseUpTheRestore() {
        let session = ReadingPositionSession(savedPosition: 0, save: { _ in }, settle: SettleGate().wait)
        session.pageReported(0.5)

        session.refresh()
        session.pageReported(0.5)

        #expect(session.restoringTo == nil)
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
    private let continuation: AsyncStream<Double>.Continuation
    private var iterator: AsyncStream<Double>.Iterator
    private var saved: [Double] = []

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Double.self)
        self.continuation = continuation
        self.iterator = stream.makeAsyncIterator()
    }

    func record(_ position: Double) async {
        saved.append(position)
        continuation.yield(position)
    }

    func nothingSaved() async -> Bool {
        try? await Task.sleep(for: .milliseconds(200))
        return saved.isEmpty
    }

    func next() async -> Double? {
        var iterator = self.iterator
        let position = await iterator.next()
        self.iterator = iterator
        return position
    }
}
