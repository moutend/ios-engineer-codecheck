import XCTest

@MainActor
final class iOSEngineerCodeCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(loadFailure: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BOOKMARK_UI_TEST_ID"] = UUID().uuidString
        if loadFailure { app.launchEnvironment["BOOKMARK_UI_TEST_LOAD_FAILURE"] = "1" }
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func search(_ query: String, in app: XCUIApplication) {
        let field = app.textFields["repositorySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String, value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(query + "\n")
    }

    func testEditingSearchAndEmptyFailureLoadingStates() {
        let app = launchApp()
        search("swift", in: app)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let field = app.textFields["repositorySearchField"]
        field.tap()
        field.typeText("x")
        XCTAssertTrue(app.staticTexts["GitHubのリポジトリを検索できます"].waitForExistence(timeout: 5))
        XCTAssertFalse(result.exists)
        search("empty", in: app)
        XCTAssertTrue(app.staticTexts["該当するリポジトリはありません"].waitForExistence(timeout: 5))
        search("failure", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "検索に失敗しました。")).firstMatch
                .waitForExistence(timeout: 5))
        search("slow", in: app)
        XCTAssertTrue(app.activityIndicators.firstMatch.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("x")
        XCTAssertTrue(app.staticTexts["GitHubのリポジトリを検索できます"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.activityIndicators.firstMatch.exists)
        search("   ", in: app)
        XCTAssertTrue(app.staticTexts["GitHubのリポジトリを検索できます"].exists)
        search("swift", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
    }

    func testUnreadableBookmarksAreNotPresentedAsEmptyAndCanRecover() {
        let app = launchApp(loadFailure: true)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        search("swift", in: app)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertFalse(app.buttons["Add to Bookmark"].isEnabled)
        app.tabBars.buttons["Bookmark"].tap()
        XCTAssertTrue(app.staticTexts["ブックマークを読み込めませんでした"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ブックマークはまだありません"].exists)
        app.buttons["ブックマークの読み込みを再試行"].tap()
        XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.buttons["Add to Bookmark"].isEnabled)
        app.buttons["Add to Bookmark"].tap()
        XCTAssertTrue(app.buttons["Remove from Bookmark"].exists)
    }

    func testLongContentAtLargestTextSizeRemainsReadableAndBookmarkable() {
        let app = launchApp(largeText: true)
        search("layout", in: app)
        let name = app.staticTexts["repositoryName"]
        let language = app.staticTexts["repositoryLanguage"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(language.exists)
        XCTAssertGreaterThanOrEqual(language.frame.minY, name.frame.maxY)
        XCTAssertLessThanOrEqual(name.frame.maxX, app.frame.maxX)
        name.tap()
        let detailLanguage = app.staticTexts["detailLanguage"]
        let stars = app.staticTexts["detailStars"]
        for _ in 0..<10 {
            if stars.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(stars.isHittable)
        XCTAssertGreaterThanOrEqual(stars.frame.minY, detailLanguage.frame.maxY)
        XCTAssertLessThanOrEqual(stars.frame.maxX, app.frame.maxX)
        let add = app.buttons["Add to Bookmark"]
        for _ in 0..<10 {
            if add.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.buttons["Remove from Bookmark"].waitForExistence(timeout: 5))
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
