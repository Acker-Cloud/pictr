import XCTest

/// Read-only walk through every screen's main controls. Safe on a real library:
/// it never keeps, queues, favorites or deletes anything.
@MainActor
final class DeviceSmokeTests: XCTestCase {
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func testEveryScreenResponds() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        shot("today")

        // Today: Settings
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings from Today")
        sleep(1); shot("settings")
        XCTAssertTrue(app.buttons["Ember icon"].exists, "App icon picker in Settings")
        let range = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'On This Day shows'")).firstMatch
        for _ in 0..<3 where !range.exists { app.swipeUp() }
        XCTAssertTrue(range.exists, "On This Day range picker in Settings")
        let learned = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'What Pictr has learned'")).firstMatch
        for _ in 0..<3 where !learned.exists { app.swipeUp() }
        if learned.waitForExistence(timeout: 3) {
            learned.tap()
            XCTAssertTrue(app.navigationBars["What Pictr has learned"].waitForExistence(timeout: 5), "Learned page")
            sleep(1); shot("learned")
            back(app)
        } else {
            XCTFail("No What Pictr has learned row")
        }
        // Help, legal and open-source rows are SwiftUI Links: UI tests see them as links.
        let source = app.links.matching(NSPredicate(format: "label BEGINSWITH 'Source code on GitHub'")).firstMatch
        for _ in 0..<8 where !source.exists { app.swipeUp() }
        XCTAssertTrue(source.exists, "Open source links in Settings")
        for label in ["Pictr home page", "Privacy Policy", "Terms of Use", "Help", "MIT License"] {
            // The list is lazy: the last rows exist only once scrolled into view.
            let link = app.links.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<3 where !link.exists { app.swipeUp() }
            XCTAssertTrue(link.exists, "\(label) link in Settings")
        }
        sleep(1); shot("settings-about")
        app.buttons["Done"].tap()

        // Progress lives in Settings
        app.buttons["Settings"].firstMatch.tap()
        let progressRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Progress'")).firstMatch
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5), "Progress row in Settings")
        progressRow.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5), "Progress")
        sleep(1); shot("progress")
        back(app)
        app.buttons["Done"].tap()

        // Every tab: title and Settings share the top row, and Settings opens.
        for (tab, title) in [("Today", nil), ("Lookback", "Lookback"), ("Cleanup", "Cleanup"), ("Ready to Delete", "Ready to Delete")] {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 5), "Settings on \(tab)")
            // Other tabs stay loaded off screen; use the gear that is actually visible.
            let gears = app.buttons.matching(identifier: "Settings").allElementsBoundByIndex
            print("gears on \(tab):", gears.map { "\($0.frame) hittable=\($0.isHittable)" })
            guard let gear = gears.first(where: { $0.isHittable }) else {
                XCTFail("No visible Settings on \(tab)"); continue
            }
            if let title {
                let heading = app.staticTexts[title].firstMatch
                XCTAssertTrue(heading.exists, "Title on \(tab)")
                XCTAssertLessThan(abs(heading.frame.midY - gear.frame.midY), 16, "\(tab) title and Settings on one row")
            }
            gear.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings opens on \(tab)")
            app.buttons["Done"].tap()
            sleep(1)
            shot("header-\(tab)")
        }
        app.tabBars.buttons["Today"].tap()

        // Today: deck, tap card opens the viewer, close
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review'")).firstMatch
        if review.waitForExistence(timeout: 3) {
            review.tap()
            sleep(2); shot("deck")
            XCTAssertTrue(app.buttons["Keep and favorite"].waitForExistence(timeout: 5), "Favorite button in the deck")
            XCTAssertTrue(app.buttons["Share"].firstMatch.exists, "Share in the deck")
            let card = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
            if card.waitForExistence(timeout: 5) {
                card.tap()
                XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Viewer from deck card")
                XCTAssertTrue(app.buttons["Share"].firstMatch.exists, "Share in the viewer")
                sleep(1); shot("viewer")
                app.buttons["Close"].tap()
            }
            sleep(1)
            back(app)
        }

        // Today: Shuffle opens a random deck (read-only: nothing is swiped)
        let shuffle = app.buttons["Start Shuffle"]
        for _ in 0..<3 where !shuffle.isHittable { app.swipeUp() }
        if shuffle.waitForExistence(timeout: 5) {
            shuffle.tap()
            XCTAssertTrue(app.navigationBars["Shuffle"].waitForExistence(timeout: 10), "Shuffle deck")
            sleep(2); shot("shuffle")
            back(app)
        } else {
            XCTFail("No Shuffle on Today")
        }

        // Months: open a month, Quick Select
        app.tabBars.buttons["Lookback"].tap()
        sleep(2); shot("lookback")
        // View options: grid, cards, sort, then back to the list.
        let options = app.buttons["View options"]
        if options.waitForExistence(timeout: 5) {
            for (layout, name) in [("Grid", "months-grid"), ("Cards", "months-cards")] {
                options.tap()
                app.buttons[layout].tap()
                sleep(2); shot(name)
            }
            options.tap()
            app.buttons["Most left to review"].tap()
            sleep(2); shot("months-cards-most-left")
            options.tap()
            app.buttons["Newest first"].tap()
            options.tap()
            app.buttons["List"].tap()
            sleep(1)
            for unit in ["Days", "Weeks", "Years"] {
                options.tap()
                app.buttons[unit].tap()
                sleep(2); shot("lookback-\(unit.lowercased())")
            }
            options.tap()
            app.buttons["Months"].tap()
            sleep(1)
        } else {
            XCTFail("No View options menu on Months")
        }
        let month = app.collectionViews.buttons.element(boundBy: 0)
        if month.waitForExistence(timeout: 10) {
            month.tap()
            sleep(2); shot("month-deck")
            XCTAssertTrue(app.navigationBars.buttons["Settings"].exists, "Settings on a month deck")
            let quick = app.buttons["Quick Select"]
            XCTAssertTrue(quick.waitForExistence(timeout: 10), "Quick Select button")
            if quick.isEnabled {
                quick.tap()
                XCTAssertTrue(app.buttons["Select all"].waitForExistence(timeout: 5)
                              || app.buttons["Select none"].exists, "Quick Select grid")
                sleep(1)
                shot("quick-select")
                back(app)
            }
            back(app)
        }

        // Cleanup: Duplicates tile, What's taking space
        app.tabBars.buttons["Cleanup"].tap()
        sleep(2); shot("cleanup")
        let insights = app.buttons["insights-link"]
        if insights.waitForExistence(timeout: 5) {
            insights.tap()
            XCTAssertTrue(app.navigationBars["What's taking space"].waitForExistence(timeout: 5), "Insights page")
            sleep(2); shot("insights")
            back(app)
        } else {
            XCTFail("No What's taking space link in Cleanup")
        }
        let duplicates = app.buttons["Duplicates"]
        for _ in 0..<4 where !duplicates.exists { app.swipeUp() }
        XCTAssertTrue(duplicates.exists, "Duplicates suggestion in Cleanup")

        // Ready to Delete: tap a photo opens the viewer
        app.tabBars.buttons["Ready to Delete"].tap()
        sleep(2); shot("ready")
        let firstCell = app.scrollViews.descendants(matching: .any)
            .matching(identifier: "queued-photo").firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Viewer from Ready to Delete")
            app.buttons["Close"].tap()
        }
        app.tabBars.buttons["Today"].tap()
    }
}
