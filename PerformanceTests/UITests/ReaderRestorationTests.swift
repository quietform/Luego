import UIKit
import XCTest

nonisolated final class ReaderRestorationTests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The detail-pane fixture uses simulator-only CloudKit entitlements without starting sync")
        #endif
        continueAfterFailure = false
    }

    @MainActor
    func testDiscoveryReaderShowsProgressAfterLoadingInTheIPadDetailPane() throws {
        try requireRegularLayout()
        XCUIDevice.shared.orientation = .portrait
        try assertDiscoveryProgressIsVisibleAndAdvances()
    }

    @MainActor
    private func assertDiscoveryProgressIsVisibleAndAdvances() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture", "--discovery-reader-fixture"]
        app.launch()
        let first = app.buttons.containing(.staticText, identifier: "Saved article A").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.staticTexts["Passage a-1"].waitForExistence(timeout: 10))

        let progress = app.otherElements["Reading progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.value as? String, "0%")
        XCTAssertGreaterThan(progress.frame.width, 0)
        XCTAssertTrue(progress.isHittable, "Progress frame: \(progress.frame); app frame: \(app.frame)")
        XCTAssertTrue(app.buttons["discovery.nextRandom"].isHittable)
        XCTAssertTrue(app.buttons["discovery.save"].exists)
        XCTAssertTrue(app.buttons["More"].isHittable)
        XCTAssertLessThan(progress.frame.maxX, app.buttons["discovery.nextRandom"].frame.minX)

        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = progress.value as? String ?? "0%"
            return (Int(value.replacingOccurrences(of: "%", with: "")) ?? 0) > 0
        }, object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
    }

    @MainActor
    func testDiscoveryReaderShowsProgressWithAllIPadColumnsVisible() throws {
        try requireRegularLayout()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        try assertDiscoveryProgressIsVisibleAndAdvances()
    }

    @MainActor
    func testReadingProgressStaysAtTheLeadingEdgeOfTheReaderToolbar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture", "--reader-unread-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let leadingEdge = UIDevice.current.userInterfaceIdiom == .pad ? first.frame.maxX : app.frame.minX
        first.tap()

        let progress = app.otherElements["Reading progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let favorite = app.buttons["Favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertTrue(favorite.isHittable)
        XCTAssertTrue(app.buttons["Archive"].isHittable)
        XCTAssertTrue(app.buttons["More"].isHittable)

        XCTAssertLessThan(progress.frame.midX, leadingEdge + (app.frame.maxX - leadingEdge) * 0.25)
        XCTAssertLessThan(progress.frame.maxX, favorite.frame.minX)
    }

    @MainActor
    func testReopeningWithoutScrollingPreservesSavedProgress() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let saved = app.staticTexts["fixture.savedPositions"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let initialFields = saved.label.split(separator: "|")
        XCTAssertEqual(initialFields.count, 4)
        let initial = try XCTUnwrap(Double(initialFields[1]))

        for _ in 0..<3 {
            first.tap()
            waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
            waitForIdle(in: app)
            let geometry = app.staticTexts["fixture.viewport"].label
                .split(separator: "|").dropFirst().compactMap { Double($0) }
            XCTAssertEqual(geometry.count, 3)
            let visibleProgress = (geometry[0] + geometry[2]) / geometry[1]
            XCTAssertEqual(visibleProgress, initial, accuracy: 0.001)

            app.buttons["fixture.select.b"].tap()
            waitForRestoration(in: app, article: "b", minimumProgress: 0.6)
            waitForIdle(in: app)
            let persisted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let fields = saved.label.split(separator: "|")
                return fields.count == 4 && abs((Double(fields[1]) ?? -1) - initial) < 0.001
            }, object: saved)
            XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 5), .completed, saved.label)
        }
    }

    @MainActor
    func testSavingAfterScrollingDoesNotShiftTheViewport() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
        waitForIdle(in: app)
        let viewport = app.staticTexts["fixture.viewport"]
        let initial = try XCTUnwrap(Double(viewport.label.split(separator: "|")[1]))
        XCTAssertEqual(app.scrollViews.count, 1)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        waitForIdle(in: app)
        let geometry = viewport.label.split(separator: "|").dropFirst().compactMap { Double($0) }
        XCTAssertEqual(geometry.count, 3)
        XCTAssertGreaterThan(geometry[0], initial + 100)
        let expectedProgress = (geometry[0] + geometry[2]) / geometry[1]
        let saved = app.staticTexts["fixture.savedPositions"]
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let fields = saved.label.split(separator: "|")
            return fields.count == 4 && abs((Double(fields[1]) ?? -1) - expectedProgress) < 0.001
        }, object: saved)
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 8), .completed, saved.label)
        let finalOffset = try XCTUnwrap(Double(viewport.label.split(separator: "|")[1]))
        XCTAssertEqual(finalOffset, geometry[0], accuracy: 1)
    }

    @MainActor
    func testRefreshingReturnsToWhereYouWereReading() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
        waitForIdle(in: app)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        waitForIdle(in: app)
        let viewport = app.staticTexts["fixture.viewport"]
        let geometry = viewport.label.split(separator: "|").dropFirst().compactMap { Double($0) }
        XCTAssertEqual(geometry.count, 3)
        let reading = (geometry[0] + geometry[2]) / geometry[1]

        app.buttons["More"].tap()
        let refresh = app.buttons["Refresh Content"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        let refreshed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1"),
            object: app.staticTexts["fixture.contentFetches"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 8), .completed)

        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let fields = viewport.label.split(separator: "|").dropFirst().compactMap { Double($0) }
            return fields.count == 3 && abs((fields[0] + fields[2]) / fields[1] - reading) < 0.002
        }, object: viewport)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed, "Expected \(reading); viewport=\(viewport.label)")
    }

    @MainActor
    func testCompletedArticleRestoresToBottom() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture", "--reader-initial-position", "1"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.99)
        waitForIdle(in: app)
        let geometry = app.staticTexts["fixture.viewport"].label
            .split(separator: "|").dropFirst().compactMap { Double($0) }
        XCTAssertEqual(geometry.count, 3)
        XCTAssertEqual(geometry[0] + geometry[2], geometry[1], accuracy: 1)
    }

    @MainActor
    func testShortArticleRestoresWithoutScrollingPastItsBounds() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture", "--reader-short-fixture", "--reader-initial-position", "1"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.staticTexts["A short article."].waitForExistence(timeout: 5))
        let geometry = app.staticTexts["fixture.viewport"].label
            .split(separator: "|").dropFirst().compactMap { Double($0) }
        XCTAssertEqual(geometry.count, 3)
        XCTAssertGreaterThan(geometry[1], 0)
        XCTAssertLessThan(geometry[1], geometry[2])
        XCTAssertEqual(geometry[0], 0, accuracy: 1)
        app.buttons["fixture.select.b"].tap()
        waitForRestoration(in: app, article: "b", minimumProgress: 0.6)
        waitForIdle(in: app)
        let saved = app.staticTexts["fixture.savedPositions"].label.split(separator: "|")
        XCTAssertEqual(saved.count, 4)
        XCTAssertEqual(try XCTUnwrap(Double(saved[1])), 1, accuracy: 0.000001)
    }

    @MainActor
    func testSwitchingArticlesRestoresEachSavedPosition() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()

        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)

        app.buttons["fixture.select.b"].tap()
        waitForRestoration(in: app, article: "b", minimumProgress: 0.6)

        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)

        let positions = app.staticTexts["fixture.savedPositions"]
        XCTAssertTrue(positions.waitForExistence(timeout: 5))
        let fields = positions.label.split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 4)
        XCTAssertGreaterThan(Double(fields[1]) ?? 0, 0.3)
        XCTAssertGreaterThan(Double(fields[3]) ?? 0, 0.6)
    }

    @MainActor
    func testLeavingDuringRestorationPreservesSavedProgress() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
        app.buttons["fixture.switchDuringRestoration"].tap()
        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "completed"),
            object: app.staticTexts["fixture.transition"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 8), .completed)
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
        let fields = app.staticTexts["fixture.savedPositions"].label.split(separator: "|")
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(try XCTUnwrap(Double(fields[3])), 0.7, accuracy: 0.000001)
    }

    @MainActor
    func testUnreadArticleStartsAtTopAfterSwitchingFromReadArticle() throws {
        try requireRegularLayout()
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture", "--reader-unread-fixture"]
        app.launch()
        let second = app.buttons["fixture.select.b"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        waitForRestoration(in: app, article: "b", minimumProgress: 0.6)
        app.buttons["fixture.select.a"].tap()
        let viewport = app.staticTexts["fixture.viewport"]
        let atTop = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let fields = viewport.label.split(separator: "|").map(String.init)
            return fields.count == 4 && fields[0] == "a"
                && (Double(fields[1]) ?? -1) == 0 && (Double(fields[2]) ?? 0) > 5000
        }, object: viewport)
        XCTAssertEqual(XCTWaiter.wait(for: [atTop], timeout: 8), .completed, viewport.label)
    }

    @MainActor
    func testCompactNavigationKeepsLoadingAnArticleReopenedWhileItLoads() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Exercises the iPhone reader destination")
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--reader-restoration-fixture",
            "--reader-uncached-fixture",
            "--reader-unread-fixture",
            "--reader-reopen-while-loading"
        ]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()

        let fetched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1"),
            object: app.staticTexts["fixture.contentFetches"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [fetched], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["Passage a-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompactNavigationRestoresPositionAfterReturningToList() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Exercises iPhone push/pop navigation")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--reader-restoration-fixture"]
        app.launch()
        let first = app.buttons["fixture.select.a"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
        app.navigationBars.buttons["Saved articles"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        waitForRestoration(in: app, article: "a", minimumProgress: 0.3)
    }

    @MainActor
    private func waitForIdle(in app: XCUIApplication) {
        let idle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "idle"),
            object: app.staticTexts["fixture.scrollPhase"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 5), .completed, "phase=\(app.staticTexts["fixture.scrollPhase"].label), viewport=\(app.staticTexts["fixture.viewport"].label)")
    }

    @MainActor
    private func requireRegularLayout() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Exercises iPad detail-pane selection")
        }
    }

    @MainActor
    private func waitForRestoration(in app: XCUIApplication, article: String, minimumProgress: Double) {
        let viewport = app.staticTexts["fixture.viewport"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let fields = viewport.label.split(separator: "|").map(String.init)
            guard fields.count == 4, fields[0] == article,
                  let offset = Double(fields[1]), let height = Double(fields[2]),
                  let visibleHeight = Double(fields[3]), height > visibleHeight else { return false }
            return (offset + visibleHeight) / height > minimumProgress
        }, object: viewport)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed, "Expected \(article) to restore; viewport=\(viewport.label)")
    }
}
