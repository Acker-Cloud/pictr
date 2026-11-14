import XCTest

/// Taps through the permission prompt and saves a screenshot of each main screen
/// to $SCREENSHOT_DIR (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
@MainActor
final class ScreenTourTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir { try? shot.pngRepresentation.write(to: dir.appending(path: "\(name).png")) }
    }

    func testTour() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        let allow = app.buttons["Allow photo access"]
        if allow.waitForExistence(timeout: 3) {
            snap("0-access")
            allow.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let full = springboard.buttons["Allow Full Access"]
            if full.waitForExistence(timeout: 5) { full.tap() }
        }

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        snap("1-today")

        let gear = app.buttons["Settings"]
        if gear.waitForExistence(timeout: 3) {
            gear.tap()
            if app.buttons["Done"].waitForExistence(timeout: 3) {
                sleep(1)
                snap("1b-settings")
                app.swipeUp()
                sleep(1)
                snap("1b-settings-more")
                let learned = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'What Pictr has learned'")).firstMatch
                if learned.waitForExistence(timeout: 2) {
                    learned.tap()
                    sleep(2)
                    snap("1b-learned")
                    app.navigationBars.buttons.firstMatch.tap()
                    sleep(1)
                }
                app.swipeUp()
                sleep(1)
                snap("1b-settings-end")
                app.buttons["Done"].tap()
                expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Done"])
                waitForExpectations(timeout: 3)
            }
        }

        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review'")).firstMatch
        if review.waitForExistence(timeout: 3) {
            review.tap()
            sleep(2)
            snap("2-deck")
            let card = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
            if card.exists {
                let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -90, dy: 0)))
            }
            app.buttons["Keep"].tap()
            sleep(1)
            snap("3-deck-after-keep")
            let photo = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
            if photo.exists {
                photo.tap()
                if app.buttons["Close"].waitForExistence(timeout: 3) {
                    sleep(1)
                    snap("3b-viewer")
                    if app.buttons["Info"].exists {
                        app.buttons["Info"].tap()
                        sleep(1)
                        snap("3c-viewer-info")
                        if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }
                        let gone = NSPredicate(format: "exists == false")
                        expectation(for: gone, evaluatedWith: app.buttons["Done"])
                        waitForExpectations(timeout: 3)
                    }
                    if app.buttons["Close"].waitForExistence(timeout: 3) { app.buttons["Close"].tap() }
                    sleep(1)
                    snap("3d-after-close")
                }
            }
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Today"].tap()
        let progress = app.buttons["Progress"]
        if progress.waitForExistence(timeout: 3) {
            progress.tap()
            sleep(2)
            snap("1c-progress")
            app.swipeUp()
            app.swipeUp()
            sleep(1)
            snap("1d-progress-more")
            // Scrolling down minimized the tab bar; scroll back up to expand it.
            app.swipeDown()
            app.swipeDown()
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        app.tabBars.buttons["Lookback"].tap()
        sleep(2)
        snap("4-months")
        let month = app.buttons.matching(NSPredicate(format: "label CONTAINS 'November'")).firstMatch
        if month.waitForExistence(timeout: 3) {
            month.tap()
            let quick = app.buttons["Quick Select"]
            if quick.waitForExistence(timeout: 5) {
                quick.tap()
                sleep(2)
                let cell = app.scrollViews.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS ','")).element(boundBy: 1)
                if cell.exists { cell.tap() }
                sleep(1)
                snap("4b-quick-select")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        app.tabBars.buttons["Cleanup"].tap()
        sleep(3)
        snap("5-cleanup")
        let analyze = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Analyze'")).firstMatch
        if analyze.waitForExistence(timeout: 5) {
            analyze.tap()
            sleep(8)
            snap("5b-cleanup-analyzed")
            let teach = app.buttons["Teach"]
            if teach.waitForExistence(timeout: 3) {
                teach.tap()
                sleep(2)
                snap("5e-teach")
                if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
                sleep(1)
                if app.buttons["Keep"].exists { app.buttons["Keep"].tap() }
                sleep(1)
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
                let update = app.buttons["Update"]
                if update.waitForExistence(timeout: 3) {
                    update.tap()
                    sleep(2)
                    snap("5f-after-update")
                }
            }
            let similar = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Similar shots'")).firstMatch
            if similar.exists && similar.isEnabled {
                similar.tap()
                sleep(2)
                snap("5c-similar")
                let compare = app.buttons["Compare"].firstMatch
                if compare.exists {
                    compare.tap()
                    sleep(2)
                    snap("5d-compare")
                    app.buttons["Done"].tap()
                }
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
        app.tabBars.buttons["Ready to Delete"].tap()
        sleep(2)
        snap("6-ready")
        let queued = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'kB' AND NOT (label BEGINSWITH 'Delete')")).firstMatch
        if queued.exists {
            queued.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 2.0)
            _ = app.buttons["Open"].waitForExistence(timeout: 3)
            snap("6b-context-menu")
            if app.buttons["Open"].exists {
                app.buttons["Open"].tap()
                _ = app.buttons["Close"].waitForExistence(timeout: 4)
                sleep(1)
                snap("6c-viewer-from-menu")
                if app.buttons["Close"].exists { app.buttons["Close"].tap() }
            }
        }
    }
}
