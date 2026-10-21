import notify
import UIKit
import XCTest

nonisolated final class ReaderHitchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAnimationCalibrationFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-animation-calibration"]
        app.launch()
        let start = app.buttons["calibration.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let result = app.staticTexts["calibration.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let fields = result.label.split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 4)
        XCTAssertGreaterThan(Int(fields[0]) ?? 0, 10, "The app must draw changing content repeatedly")
        XCTAssertEqual(Int(fields[1]), 0)
        XCTAssertEqual(Int(fields[2]), 0)
        XCTAssertGreaterThanOrEqual(Double(fields[3]) ?? 0, 3)
    }

    @MainActor
    func testAnimationCalibrationDelayedDraw() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-animation-calibration", "--benchmark-stall"]
        app.launch()
        let start = app.buttons["calibration.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let result = app.staticTexts["calibration.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let fields = result.label.split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 4)
        XCTAssertGreaterThan(Int(fields[0]) ?? 0, 10)
        XCTAssertEqual(Int(fields[1]), 1, "Delay exactly one draw inside the animation")
        XCTAssertGreaterThanOrEqual(Int(fields[2]) ?? 0, 200)
        XCTAssertGreaterThanOrEqual(Double(fields[3]) ?? 0, 3)
    }

    @MainActor
    func testAnimationMetricNormal() {
        measureAnimationCalibration(stalled: false)
    }

    @MainActor
    func testAnimationMetricDelayedDraw() {
        measureAnimationCalibration(stalled: true)
    }

    @MainActor
    private func measureAnimationCalibration(stalled: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-animation-calibration"] + (stalled ? ["--benchmark-stall"] : [])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["calibration.start"].waitForExistence(timeout: 5))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var pass = 0
        measure(metrics: [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "CalibrationAnimation")
        ], options: options) {
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            let storageBefore = availableStorageBytes()
            startMeasuring()
            app.buttons["calibration.start"].tap()
            XCTAssertTrue(app.staticTexts["calibration.result"].waitForExistence(timeout: 8))
            stopMeasuring()
            assertAnimationCalibration(app, stalled: stalled)
            reportCalibrationConditions(app, pass: pass, thermalBefore: thermalBefore, storageBefore: storageBefore)
            pass += 1
        }
    }

    @MainActor
    private func assertAnimationCalibration(_ app: XCUIApplication, stalled: Bool) {
        let fields = app.staticTexts["calibration.result"].label.split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 4)
        XCTAssertGreaterThan(Int(fields[0]) ?? 0, 10)
        XCTAssertEqual(Int(fields[1]), stalled ? 1 : 0)
        if stalled {
            XCTAssertGreaterThanOrEqual(Int(fields[2]) ?? 0, 200)
        } else {
            XCTAssertEqual(Int(fields[2]), 0)
        }
        XCTAssertGreaterThanOrEqual(Double(fields[3]) ?? 0, 3)
    }

    @MainActor
    private func reportCalibrationConditions(_ app: XCUIApplication, pass: Int, thermalBefore: Int, storageBefore: String) {
        let conditions = "pass=\(pass), animation=\(app.staticTexts["calibration.result"].label), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), availableStorageBefore=\(storageBefore), availableStorageAfter=\(availableStorageBytes()), os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        let attachment = XCTAttachment(string: conditions)
        attachment.name = "Animation calibration conditions"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("HITCH_ANIMATION \(conditions)")
    }

    @MainActor
    func testAnimationNormalWithProfiler() {
        profileAnimationCalibration(stalled: false)
    }

    @MainActor
    func testAnimationDelayedDrawWithProfiler() {
        profileAnimationCalibration(stalled: true)
    }

    @MainActor
    private func profileAnimationCalibration(stalled: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-animation-calibration", "--benchmark-profile-signposts"] + (stalled ? ["--benchmark-stall"] : [])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["calibration.start"].waitForExistence(timeout: 5))
        let ready = XCTestExpectation(description: "Profiler attached")
        var token: Int32 = 0
        XCTAssertEqual(notify_register_dispatch("com.esoxjem.Luego.performance.profiler-ready", &token, .global()) { _ in ready.fulfill() }, UInt32(NOTIFY_STATUS_OK))
        defer { notify_cancel(token) }
        print("HITCH_TRACE_READY")
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed)
        for pass in 0..<3 {
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            let storageBefore = availableStorageBytes()
            app.buttons["calibration.start"].tap()
            XCTAssertTrue(app.staticTexts["calibration.result"].waitForExistence(timeout: 8))
            assertAnimationCalibration(app, stalled: stalled)
            reportCalibrationConditions(app, pass: pass, thermalBefore: thermalBefore, storageBefore: storageBefore)
        }
    }

    @MainActor
    func testSingleReaderIntervalHitches() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")], options: options) {
            restoreFixture(app)
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            startMeasuring()
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
            let state = app.staticTexts["benchmark.scrollState"]
            let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "idle|1|"), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
            stopMeasuring()
            XCTAssertGreaterThan(Int(state.label.split(separator: "|").last ?? "") ?? 0, 100)
            assertStalls(app, expected: 0)
            print("HITCH_READER state=\(state.label), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), availableStorage=\(availableStorageBytes())")
        }
    }

    @MainActor
    func testIndexedImageScrollIntervals() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture", "--benchmark-indexed-scrolls"]
        restoreImageFixture(app)
        scrollThroughFixture(app)
        assertImageWork(app, warm: false)
        assertStalls(app, expected: 0)
    }

    @MainActor
    func testIndexedWarmImageScrollIntervals() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture", "--benchmark-images-warm", "--benchmark-indexed-scrolls"]
        restoreImageFixture(app)
        scrollThroughFixture(app)
        assertImageWork(app, warm: true)
        assertStalls(app, expected: 0)
    }

    @MainActor
    func testColdImageIntervalHitches() {
        measureImages(warm: false, indexed: true)
    }

    @MainActor
    func testWarmImageIntervalHitches() {
        measureImages(warm: true, indexed: true)
    }

    @MainActor
    func testImageFixtureDisplaysDecodedPhoto() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture"]
        restoreFixture(app)
        XCTAssertTrue(app.otherElements["IMAGE_FIXTURE_024"].exists, "The fixture must contain the offscreen article photos")
        let decoded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["IMAGE_FIXTURE_001"])
        XCTAssertEqual(XCTWaiter.wait(for: [decoded], timeout: 5), .completed, "The visible photo must replace its placeholder")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Image fixture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testWarmImageFixtureUsesEncodedCache() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture", "--benchmark-images-warm"]
        restoreFixture(app)
        XCTAssertFalse(app.otherElements["IMAGE_FIXTURE_001"].exists)
        scrollThroughFixture(app)
        let fields = app.staticTexts["benchmark.imageState"].label.split(separator: "|").map(String.init)
        XCTAssertEqual(Array(fields.prefix(2)), ["warm", "24"], "Prime every encoded response before rendering")
        XCTAssertEqual(Int(fields[2]), 0, "Warm scrolling must use URLCache rather than fixture transport responses")
        XCTAssertEqual(Int(fields[4]), 0)
        XCTAssertGreaterThan(Int(fields[6]) ?? 0, 0, "Serve actual encoded cache responses to the reader")
    }

    @MainActor
    func testImageScrollsOverlapResponses() {
        for warm in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--benchmark-image-fixture"] + (warm ? ["--benchmark-images-warm"] : [])
            restoreImageFixture(app)
            scrollThroughFixture(app)
            assertImageWork(app, warm: warm)
            assertStalls(app, expected: 0)
        }
    }

    @MainActor
    func testImageKnownStallFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture", "--benchmark-stall"]
        restoreImageFixture(app)
        scrollThroughFixture(app)
        assertImageWork(app, warm: false)
        assertStalls(app, expected: 6)
    }

    @MainActor
    func testColdImageHitches() {
        measureImages(warm: false)
    }

    @MainActor
    func testWarmImageHitches() {
        measureImages(warm: true)
    }

    @MainActor
    func testImageHitchCalibration() {
        measureImages(warm: false, stalled: true)
    }

    @MainActor
    private func restoreImageFixture(_ app: XCUIApplication) {
        restoreFixture(app)
        XCTAssertTrue(app.otherElements["IMAGE_FIXTURE_024"].exists)
        let decoded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["IMAGE_FIXTURE_001"])
        XCTAssertEqual(XCTWaiter.wait(for: [decoded], timeout: 5), .completed)
    }

    @MainActor
    private func assertImageWork(_ app: XCUIApplication, warm: Bool) {
        let fields = app.staticTexts["benchmark.imageState"].label.split(separator: "|").map(String.init)
        XCTAssertEqual(fields.count, 8)
        XCTAssertEqual(Array(fields.prefix(2)), [warm ? "warm" : "cold", warm ? "24" : "0"])
        XCTAssertEqual(Int(fields[4]), 0)
        if warm {
            XCTAssertEqual(Int(fields[2]), 0)
            XCTAssertGreaterThan(Int(fields[6]) ?? 0, 0)
        } else {
            XCTAssertGreaterThan(Int(fields[2]) ?? 0, 0)
            XCTAssertGreaterThan(Int(fields[5]) ?? 0, 0)
        }
        let history = app.staticTexts["benchmark.imageScrolls"]
        XCTAssertTrue(history.exists, "Record actual image work during every scroll")
        let scrolls = history.label.split(separator: ";")
        XCTAssertEqual(scrolls.count, 6)
        var reads = 0
        var hits = 0
        for scroll in scrolls {
            let counts = scroll.split(separator: ":").compactMap { Int($0) }
            XCTAssertEqual(counts.count, 2)
            reads += counts[0]
            hits += counts[1]
        }
        XCTAssertEqual(Int(fields[3]), reads)
        XCTAssertEqual(Int(fields[7]), hits)
        XCTAssertGreaterThan(warm ? hits : reads, 0, "The traversal must overlap image work in the selected cache mode: \(history.label)")
        for placeholder in app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "IMAGE_FIXTURE_")).allElementsBoundByIndex where placeholder.isHittable {
            let decoded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: placeholder)
            XCTAssertEqual(XCTWaiter.wait(for: [decoded], timeout: 5), .completed, "Visible photos must finish replacing their placeholders")
        }
    }

    @MainActor
    private func measureImages(warm: Bool, stalled: Bool = false, indexed: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-image-fixture"] + (warm ? ["--benchmark-images-warm"] : []) + (stalled ? ["--benchmark-stall"] : [])
        if indexed { app.launchArguments.append("--benchmark-indexed-scrolls") }
        let options = XCTMeasureOptions()
        options.iterationCount = stalled ? 2 : 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var pass = 0
        measure(metrics: indexed ? scrollMetrics(count: 6) : [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            restoreImageFixture(app)
            assertStalls(app, expected: 0)
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            let storageBefore = availableStorageBytes()
            startMeasuring()
            scrollThroughFixture(app)
            stopMeasuring()
            assertImageWork(app, warm: warm)
            assertStalls(app, expected: stalled ? 6 : 0)
            pass += 1
            let maximumRefreshRate = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }.first.map(String.init) ?? "unavailable"
            let conditions = "warm=\(warm), stalled=\(stalled), pass=\(pass), images=\(app.staticTexts["benchmark.imageState"].label), scrolls=\(app.staticTexts["benchmark.imageScrolls"].label), stalls=\(app.staticTexts["benchmark.stallState"].label), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), availableStorageBefore=\(storageBefore), availableStorageAfter=\(availableStorageBytes()), maximumRefreshRate=\(maximumRefreshRate), os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
            let attachment = XCTAttachment(string: conditions)
            attachment.name = "Image conditions \(pass)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("HITCH_IMAGES \(conditions)")
        }
    }

    @MainActor
    private func scrollMetrics(count: Int) -> [XCTMetric] {
        (1...count).map { XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll\($0)") }
    }

    @MainActor
    func testIndexedSyncScrollIntervals() {
        for syncing in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--benchmark-sync-fixture", "--benchmark-indexed-scrolls"] + (syncing ? ["--benchmark-sync"] : [])
            restoreFixture(app)
            waitForSyncFixture(app)
            scrollThroughSyncFixture(app, syncing: syncing)
            assertStalls(app, expected: 0)
        }
    }

    @MainActor
    func testForegroundSyncBaselineIntervalHitches() {
        measureForegroundSync(syncing: false, indexed: true)
    }

    @MainActor
    func testForegroundSyncContentionIntervalHitches() {
        measureForegroundSync(syncing: true, indexed: true)
    }

    @MainActor
    func testReaderFixtureIsScrollable() {
        let app = XCUIApplication()
        restoreFixture(app)
        XCTAssertEqual(app.staticTexts["benchmark.scrollState"].value as? String, "Reader")
        scrollThroughFixture(app)
        assertStalls(app, expected: 0)
    }

    @MainActor
    func testBenchmarkStallControl() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-stall"]
        restoreFixture(app)
        assertStalls(app, expected: 0)
        scrollThroughFixture(app)
        assertStalls(app, expected: 3)
    }

    @MainActor
    func testForegroundSyncContentionFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-sync-fixture", "--benchmark-sync"]
        restoreFixture(app)
        let report = app.staticTexts["benchmark.syncState"]
        XCTAssertTrue(report.exists, "The contention fixture must report its seeded library and applied sync work")
        XCTAssertTrue(report.label.hasPrefix("ready|2001|0|0|0|0|0|0"))
        scrollThroughSyncFixture(app, syncing: true)
        assertStalls(app, expected: 0)
    }

    @MainActor
    func testProfilingUsesPointsOfInterest() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-profile-signposts"]
        restoreFixture(app)
        XCTAssertEqual(app.staticTexts["benchmark.scrollState"].value as? String, "PointsOfInterest")
    }

    @MainActor
    func testForegroundSyncCompletionSignal() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-sync-fixture", "--benchmark-sync"]
        restoreFixture(app)
        waitForSyncFixture(app)
        let verification = syncVerificationSignal()
        defer { notify_cancel(verification.token) }
        app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        XCTAssertEqual(XCTWaiter.wait(for: [verification.event], timeout: 20), .completed, "The fixture must signal persistence completion without accessibility polling")
        let report = app.staticTexts["benchmark.syncState"].label
        XCTAssertTrue(report.hasPrefix("ready|2001|1|100|100|1|"))
        XCTAssertEqual(report.split(separator: "|").last, "1")
    }

    @MainActor
    func testForegroundSyncBaselineFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-sync-fixture"]
        restoreFixture(app)
        waitForSyncFixture(app)
        scrollThroughSyncFixture(app, syncing: false)
        assertStalls(app, expected: 0)
    }

    @MainActor
    func testForegroundSyncBaseline() {
        measureForegroundSync(syncing: false)
    }

    @MainActor
    func testForegroundSyncContention() {
        measureForegroundSync(syncing: true)
    }

    @MainActor
    func testForegroundSyncKnownStall() {
        measureForegroundSync(syncing: false, stalled: true)
    }

    @MainActor
    private func waitForSyncFixture(_ app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ready|2001|0|0|0|0|0|0"), object: app.staticTexts["benchmark.syncState"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }

    @MainActor
    private func measureForegroundSync(syncing: Bool, stalled: Bool = false, indexed: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-sync-fixture"] + (syncing ? ["--benchmark-sync"] : []) + (stalled ? ["--benchmark-stall"] : [])
        if indexed { app.launchArguments.append("--benchmark-indexed-scrolls") }
        let options = XCTMeasureOptions()
        options.iterationCount = stalled ? 2 : 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var pass = 0
        measure(metrics: indexed ? scrollMetrics(count: 3) : [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            restoreFixture(app)
            waitForSyncFixture(app)
            assertStalls(app, expected: 0)
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            let storageBefore = availableStorageBytes()
            startMeasuring()
            scrollThroughSyncFixture(app, syncing: syncing)
            stopMeasuring()
            assertStalls(app, expected: stalled ? 3 : 0)
            pass += 1
            let maximumRefreshRate = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }.first.map(String.init) ?? "unavailable"
            let conditions = "syncing=\(syncing), stalled=\(stalled), pass=\(pass), sync=\(app.staticTexts["benchmark.syncState"].label), stalls=\(app.staticTexts["benchmark.stallState"].label), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), availableStorageBefore=\(storageBefore), availableStorageAfter=\(availableStorageBytes()), maximumRefreshRate=\(maximumRefreshRate), os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
            let attachment = XCTAttachment(string: conditions)
            attachment.name = "Foreground sync conditions \(pass)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("HITCH_FOREGROUND_SYNC \(conditions)")
        }
    }

    @MainActor
    private func syncVerificationSignal() -> (event: XCTestExpectation, token: Int32) {
        let event = XCTestExpectation(description: "Sync batch persisted")
        var token: Int32 = 0
        let registration = notify_register_dispatch("com.esoxjem.Luego.performance.sync-verified", &token, .global()) { _ in
            event.fulfill()
        }
        XCTAssertEqual(registration, UInt32(NOTIFY_STATUS_OK))
        return (event, token)
    }

    @MainActor
    private func scrollThroughSyncFixture(_ app: XCUIApplication, syncing: Bool, waitForPersistenceSignal: Bool = false) {
        let scrollView = app.scrollViews.firstMatch
        let scrollState = app.staticTexts["benchmark.scrollState"]
        let syncState = app.staticTexts["benchmark.syncState"]
        var previousOffset = 0
        var previousOverlap = 0
        for gesture in 1...3 {
            let verification = waitForPersistenceSignal ? syncVerificationSignal() : nil
            defer { if let verification { notify_cancel(verification.token) } }
            scrollView.swipeUp(velocity: .fast)
            let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "idle|\(gesture)|"), object: scrollState)
            XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
            let offset = Int(scrollState.label.split(separator: "|").last ?? "") ?? 0
            XCTAssertGreaterThan(offset, previousOffset + 100)
            previousOffset = offset
            if app.launchArguments.contains("--benchmark-indexed-scrolls") {
                let category = app.launchArguments.contains("--benchmark-profile-signposts") ? "PointsOfInterest" : "Reader"
                XCTAssertEqual(scrollState.value as? String, "\(category)|ReaderScroll\(gesture)")
            }
            let readinessDeadline = ProcessInfo.processInfo.systemUptime + 20
            if let verification {
                XCTAssertEqual(XCTWaiter.wait(for: [verification.event], timeout: 20), .completed, "The batch must finish before checking its UI report")
            }
            let batches = syncing ? gesture : 0
            let records = batches * 100
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "ready|2001|\(batches)|\(records)|\(records)|\(batches)|"), object: syncState)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: max(0, readinessDeadline - ProcessInfo.processInfo.systemUptime)), .completed)
            let fields = syncState.label.split(separator: "|")
            XCTAssertEqual(fields.count, 8)
            let overlap = Int(fields[6]) ?? 0
            if syncing {
                XCTAssertGreaterThan(overlap, previousOverlap, "Each batch must overlap its scroll")
            } else {
                XCTAssertEqual(overlap, 0)
            }
            previousOverlap = overlap
            XCTAssertEqual(Int(fields[7]), batches, "The production list observer must materialize completed batches")
        }
        XCTAssertFalse(app.staticTexts["Hitch fixture — text v1"].isHittable)
    }

    @MainActor
    func testCalibrationNormal() {
        measureCalibration(stalled: false)
    }

    @MainActor
    func testCalibrationStalled() {
        measureCalibration(stalled: true)
    }

    @MainActor
    private func assertStalls(_ app: XCUIApplication, expected: Int) {
        let report = app.staticTexts["benchmark.stallState"]
        XCTAssertTrue(report.exists, "The stall control must report completed main-thread stalls")
        let fields = report.label.split(separator: "|")
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(Int(fields.first ?? ""), expected, "Inject exactly one stall per scroll only when opted in")
        if expected == 0 {
            XCTAssertEqual(Int(fields.last ?? ""), 0)
        } else {
            XCTAssertGreaterThanOrEqual(Int(fields.last ?? "") ?? 0, expected * 200, "Each stall must block the main thread for at least 200 ms")
        }
    }

    @MainActor
    private func measureCalibration(stalled: Bool) {
        let app = XCUIApplication()
        app.launchArguments = stalled ? ["--benchmark-stall"] : []
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var pass = 0
        measure(metrics: [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            restoreFixture(app)
            assertStalls(app, expected: 0)
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            startMeasuring()
            scrollThroughFixture(app)
            stopMeasuring()
            assertStalls(app, expected: stalled ? 3 : 0)
            pass += 1
            let maximumRefreshRate = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }.first.map(String.init) ?? "unavailable"
            let conditions = "stalled=\(stalled), pass=\(pass), stalls=\(app.staticTexts["benchmark.stallState"].label), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), maximumRefreshRate=\(maximumRefreshRate), os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
            let attachment = XCTAttachment(string: conditions)
            attachment.name = "Calibration conditions \(pass)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("HITCH_CALIBRATION \(conditions)")
        }
    }

    @MainActor
    func testReaderScrollWithProfiler() {
        profileScroll(stalled: false)
    }

    @MainActor
    func testStalledReaderScrollWithProfiler() {
        profileScroll(stalled: true)
    }

    @MainActor
    func testIndexedForegroundSyncWithProfiler() {
        profileScroll(stalled: false, syncing: true, indexed: true)
    }

    @MainActor
    func testIndexedForegroundSyncBaselineWithProfiler() {
        profileScroll(stalled: false, syncing: false, indexed: true)
    }

    @MainActor
    func testIndexedColdImagesWithProfiler() {
        profileScroll(stalled: false, imageCache: .cold, indexed: true)
    }

    @MainActor
    func testIndexedWarmImagesWithProfiler() {
        profileScroll(stalled: false, imageCache: .warm, indexed: true)
    }

    @MainActor
    func testForegroundSyncWithProfiler() {
        profileScroll(stalled: false, syncing: true)
    }

    @MainActor
    func testForegroundSyncPollingWithProfiler() {
        profileScroll(stalled: false, syncing: true, waitForPersistenceSignal: false)
    }

    @MainActor
    func testForegroundSyncBaselineWithProfiler() {
        profileScroll(stalled: false, syncing: false)
    }

    @MainActor
    func testColdImagesWithProfiler() {
        profileScroll(stalled: false, imageCache: .cold)
    }

    @MainActor
    func testWarmImagesWithProfiler() {
        profileScroll(stalled: false, imageCache: .warm)
    }

    @MainActor
    func testStalledImagesWithProfiler() {
        profileScroll(stalled: true, imageCache: .cold)
    }

    private enum ImageCache {
        case cold, warm
    }

    @MainActor
    private func profileScroll(stalled: Bool, syncing: Bool? = nil, waitForPersistenceSignal: Bool = true, imageCache: ImageCache? = nil, indexed: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-profile-signposts"] + (stalled ? ["--benchmark-stall"] : [])
        if indexed { app.launchArguments.append("--benchmark-indexed-scrolls") }
        if let syncing {
            app.launchArguments += ["--benchmark-sync-fixture"] + (syncing ? ["--benchmark-sync"] : [])
        }
        if let imageCache {
            app.launchArguments += ["--benchmark-image-fixture"] + (imageCache == .warm ? ["--benchmark-images-warm"] : [])
            restoreImageFixture(app)
        } else {
            restoreFixture(app)
        }
        if syncing != nil { waitForSyncFixture(app) }
        let ready = XCTestExpectation(description: "Profiler attached")
        var token: Int32 = 0
        let registration = notify_register_dispatch("com.esoxjem.Luego.performance.profiler-ready", &token, .global()) { _ in
            ready.fulfill()
        }
        XCTAssertEqual(registration, UInt32(NOTIFY_STATUS_OK))
        defer { notify_cancel(token) }
        print("HITCH_TRACE_READY")
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed, "Attach Instruments and post the profiler-ready notification before scrolling")
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let storageBefore = availableStorageBytes()
        print("HITCH_PROFILE_BEGIN thermal=\(thermalBefore), availableStorageBytes=\(storageBefore), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), completionTimeout=20")
        if let syncing {
            scrollThroughSyncFixture(app, syncing: syncing, waitForPersistenceSignal: waitForPersistenceSignal)
        } else {
            scrollThroughFixture(app)
        }
        assertStalls(app, expected: stalled ? (imageCache == nil ? 3 : 6) : 0)
        if let imageCache { assertImageWork(app, warm: imageCache == .warm) }
        let images = imageCache == nil ? "none" : app.staticTexts["benchmark.imageState"].label
        let imageScrolls = imageCache == nil ? "none" : app.staticTexts["benchmark.imageScrolls"].label
        let conditions = "syncing=\(syncing.map(String.init) ?? "none"), sync=\(app.staticTexts["benchmark.syncState"].exists ? app.staticTexts["benchmark.syncState"].label : "none"), images=\(images), imageScrolls=\(imageScrolls), thermalBefore=\(thermalBefore), thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), availableStorageBefore=\(storageBefore), availableStorageAfter=\(availableStorageBytes())"
        let attachment = XCTAttachment(string: conditions)
        attachment.name = "Profiling conditions"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("HITCH_PROFILE \(conditions)")
    }

    @MainActor
    private func availableStorageBytes() -> String {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attributes?[.systemFreeSize] as? NSNumber).map { String($0.int64Value) } ?? "unavailable"
    }

    @MainActor
    func testStableProcessStallCalibration() {
        let app = XCUIApplication()
        app.launchArguments = ["--benchmark-stall"]
        restoreFixture(app)
        let scrollView = app.scrollViews.firstMatch
        let state = app.staticTexts["benchmark.scrollState"]
        var completed = 0
        var previousOffset = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            startMeasuring()
            for _ in 0..<3 {
                scrollView.swipeUp(velocity: .fast)
                completed += 1
                let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "idle|\(completed)|"), object: state)
                XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
                let offset = Int(state.label.split(separator: "|").last ?? "") ?? 0
                XCTAssertGreaterThan(offset, previousOffset + 100)
                previousOffset = offset
            }
            stopMeasuring()
            assertStalls(app, expected: completed)
            print("HITCH_STABLE_CALIBRATION completed=\(completed), stalls=\(app.staticTexts["benchmark.stallState"].label)")
        }
    }

    @MainActor
    func testWarmTextReaderHitches() {
        let app = XCUIApplication()
        let maximumRefreshRate = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }.first.map(String.init) ?? "unavailable"
        let environment = "thermal=\(ProcessInfo.processInfo.thermalState.rawValue), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), maximumRefreshRate=\(maximumRefreshRate), os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        let attachment = XCTAttachment(string: environment)
        attachment.name = "Measurement conditions"
        attachment.lifetime = .keepAlways
        add(attachment)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            restoreFixture(app)
            startMeasuring()
            scrollThroughFixture(app)
            stopMeasuring()
        }
    }

    @MainActor
    func testCustomSignpostAlone() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            restoreFixture(app)
            startMeasuring()
            scrollThroughFixture(app)
            stopMeasuring()
        }
    }

    @MainActor
    func testSystemScrollSignposts() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            restoreFixture(app)
            startMeasuring()
            scrollThroughFixture(app)
            stopMeasuring()
        }
    }

    @MainActor
    func testStableProcessSignposts() {
        let app = XCUIApplication()
        restoreFixture(app)
        let scrollView = app.scrollViews.firstMatch
        let state = app.staticTexts["benchmark.scrollState"]
        var completed = 0
        var previousOffset = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            startMeasuring()
            for _ in 0..<3 {
                scrollView.swipeUp(velocity: .fast)
                completed += 1
                let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "idle|\(completed)|"), object: state)
                XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
                let offset = Int(state.label.split(separator: "|").last ?? "") ?? 0
                XCTAssertGreaterThan(offset, previousOffset + 100)
                previousOffset = offset
            }
            stopMeasuring()
        }
    }

    @MainActor
    func testSingleIntervalSignposts() {
        let app = XCUIApplication()
        restoreFixture(app)
        let scrollView = app.scrollViews.firstMatch
        let state = app.staticTexts["benchmark.scrollState"]
        var completed = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 2
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [
            XCTOSSignpostMetric(subsystem: "com.esoxjem.Luego.performance", category: "Reader", name: "ReaderScroll")
        ], options: options) {
            startMeasuring()
            scrollView.swipeUp(velocity: .fast)
            completed += 1
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "idle|\(completed)|"), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
            stopMeasuring()
        }
    }

    @MainActor
    private func restoreFixture(_ app: XCUIApplication) {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app.launch()
        let title = app.staticTexts[app.launchArguments.contains("--benchmark-image-fixture") ? "Hitch fixture — images v1" : "Hitch fixture — text v1"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The benchmark must display the reader fixture")
        let body = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "FIXTURE_START")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 20), "Markdown must finish rendering before measurement")
        XCTAssertTrue(title.isHittable, "Every iteration must start at the top")
        XCTAssertEqual(app.staticTexts["benchmark.scrollState"].label, "idle|0|0")
        XCTAssertEqual(app.scrollViews.count, 1)
    }

    @MainActor
    private func scrollThroughFixture(_ app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        let state = app.staticTexts["benchmark.scrollState"]
        var previousOffset = 0
        let gestures = app.launchArguments.contains("--benchmark-image-fixture") ? 6 : 3
        for gesture in 1...gestures {
            scrollView.swipeUp(velocity: .fast)
            let settled = NSPredicate(format: "label BEGINSWITH %@", "idle|\(gesture)|")
            let expectation = XCTNSPredicateExpectation(predicate: settled, object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "Capture dragging and deceleration through the idle phase")
            let offset = Int(state.label.split(separator: "|").last ?? "") ?? 0
            XCTAssertGreaterThan(offset, previousOffset + 100, "Each gesture must move real reader content")
            previousOffset = offset
            if app.launchArguments.contains("--benchmark-indexed-scrolls") {
                let category = app.launchArguments.contains("--benchmark-profile-signposts") ? "PointsOfInterest" : "Reader"
                XCTAssertEqual(state.value as? String, "\(category)|ReaderScroll\(gesture)")
            }
        }
        XCTAssertFalse(app.staticTexts[app.launchArguments.contains("--benchmark-image-fixture") ? "Hitch fixture — images v1" : "Hitch fixture — text v1"].isHittable)
    }
}
