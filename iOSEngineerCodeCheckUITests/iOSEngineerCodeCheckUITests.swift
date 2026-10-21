import XCTest

@MainActor
final class iOSEngineerCodeCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBookmarkRemovalKeepsDetailAndSynchronizesTabsAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BOOKMARK_UI_TEST_ID"] = UUID().uuidString
        app.launch()

        let searchField = app.textFields["repositorySearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("swift\n")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        app.buttons["Add to Bookmark"].tap()
        XCTAssertTrue(app.buttons["Remove from Bookmark"].exists)

        app.tabBars.buttons["Bookmark"].tap()
        let bookmark = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift")).firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        app.buttons["Remove from Bookmark"].tap()
        // Removing the source row must not pop or invalidate the displayed detail.
        XCTAssertTrue(app.buttons["Add to Bookmark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["42 stars"].exists)
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.buttons["Add to Bookmark"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Bookmark"].tap()
        XCTAssertTrue(app.buttons["Add to Bookmark"].exists)
        app.buttons["Add to Bookmark"].tap()
        XCTAssertTrue(app.buttons["Remove from Bookmark"].exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Bookmark"].tap()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        app.buttons["Remove from Bookmark"].tap()
        XCTAssertTrue(app.buttons["Add to Bookmark"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Search"].tap()
        searchField.tap()
        searchField.typeText("swift\n")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["Add to Bookmark"].exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Bookmark"].tap()
        XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].waitForExistence(timeout: 5))
    }
}
