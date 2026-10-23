import XCTest

@MainActor
final class IOSEngineerCodeCheckUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  private func launchApp(loadFailure: Bool = false, largeText: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["BOOKMARK_UI_TEST_ID"] = UUID().uuidString
    if loadFailure { app.launchEnvironment["BOOKMARK_UI_TEST_LOAD_FAILURE"] = "1" }
    if largeText {
      app.launchArguments += [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ]
    }
    app.launch()
    return app
  }

  private func search(_ query: String, in app: XCUIApplication) {
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    if let value = field.value as? String, value != field.placeholderValue {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
    field.typeText(query + "\n")
  }

  func testSwipeDeleteBookmarksInNewestOrder() {
    verifySwipeDeletion(sortByName: false)
  }

  func testSwipeDeleteBookmarksInNameOrder() {
    verifySwipeDeletion(sortByName: true)
  }

  private func verifySwipeDeletion(sortByName: Bool) {
    let app = launchApp()
    search("sorting", in: app)
    for name in ["example/second", "example/swift"] {
      XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
      app.staticTexts[name].tap()
      app.buttons["Add to Bookmark"].tap()
      app.navigationBars.buttons.firstMatch.tap()
    }
    // Keep a search detail visible to verify cross-tab synchronization.
    let deleted = sortByName ? "example/second" : "example/swift"
    let remaining = sortByName ? "example/swift" : "example/second"
    app.staticTexts[deleted].tap()
    app.tabBars.buttons["Bookmark"].tap()
    if sortByName {
      app.buttons["bookmarkSortMenu"].tap()
      app.buttons["名前"].tap()
    }
    let rows = app.staticTexts.matching(identifier: "repositoryName")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.firstMatch.label, deleted)
    rows.firstMatch.swipeLeft()
    let delete = app.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "削除"]))
      .firstMatch
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertTrue(app.staticTexts[deleted].waitForNonExistence(timeout: 5))
    XCTAssertEqual(rows.firstMatch.label, remaining)
    XCTAssertEqual(app.staticTexts["bookmarkCount"].label, "全1件")
    app.tabBars.buttons["Search"].tap()
    XCTAssertTrue(app.buttons["Add to Bookmark"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    app.tabBars.buttons["Bookmark"].tap()
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.firstMatch.label, remaining)
    XCTAssertEqual(app.staticTexts["bookmarkCount"].label, "全1件")
    rows.firstMatch.swipeLeft()
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["bookmarkCount"].label, "全0件")
    app.terminate()
    app.launch()
    app.tabBars.buttons["Bookmark"].tap()
    XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].waitForExistence(timeout: 5))
  }

  func testBookmarkCountSortAndRelaunch() {
    let app = launchApp()
    app.tabBars.buttons["Bookmark"].tap()
    let count = app.staticTexts["bookmarkCount"]
    let menu = app.buttons["bookmarkSortMenu"]
    XCTAssertTrue(count.waitForExistence(timeout: 5))
    XCTAssertEqual(count.label, "全0件")
    XCTAssertTrue(menu.label.contains("追加日"))
    app.tabBars.buttons["Search"].tap()
    search("sorting", in: app)
    // Add in alphabetical order so newest-first and name order differ.
    for name in ["example/second", "example/swift"] {
      let row = app.staticTexts[name]
      XCTAssertTrue(row.waitForExistence(timeout: 5))
      row.tap()
      app.buttons["Add to Bookmark"].tap()
      app.navigationBars.buttons.firstMatch.tap()
    }
    app.tabBars.buttons["Bookmark"].tap()
    let rows = app.staticTexts.matching(identifier: "repositoryName")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(count.label, "全2件")
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/swift")
    XCTAssertLessThanOrEqual(count.frame.maxY, rows.firstMatch.frame.minY)
    XCTAssertLessThanOrEqual(count.frame.maxX, menu.frame.minX)
    menu.tap()
    XCTAssertTrue(app.buttons["名前"].exists)
    XCTAssertTrue(app.buttons["追加日"].exists)
    app.buttons["名前"].tap()
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/second")
    XCTAssertEqual(count.label, "全2件")
    menu.tap()
    app.buttons["追加日"].tap()
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/swift")
    menu.tap()
    app.buttons["名前"].tap()
    app.terminate()
    app.launch()
    app.tabBars.buttons["Bookmark"].tap()
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(menu.label.contains("追加日"))
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/swift")
    XCTAssertEqual(count.label, "全2件")
    rows.element(boundBy: 0).tap()
    app.buttons["Remove from Bookmark"].tap()
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertEqual(count.label, "全1件")
    XCTAssertEqual(rows.firstMatch.label, "example/second")
    rows.firstMatch.tap()
    app.buttons["Remove from Bookmark"].tap()
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertEqual(count.label, "全0件")
    XCTAssertTrue(app.staticTexts["ブックマークはまだありません"].exists)
  }

  func testBookmarkHeaderAtLargestTextSize() {
    let app = launchApp(largeText: true)
    app.tabBars.buttons["Bookmark"].tap()
    let count = app.staticTexts["bookmarkCount"]
    let menu = app.buttons["bookmarkSortMenu"]
    XCTAssertTrue(count.waitForExistence(timeout: 5))
    XCTAssertTrue(count.isHittable)
    XCTAssertTrue(menu.isHittable)
    XCTAssertLessThanOrEqual(count.frame.maxX, menu.frame.minX)
    XCTAssertLessThanOrEqual(menu.frame.maxX, app.frame.maxX)
    menu.tap()
    app.buttons["名前"].tap()
    XCTAssertTrue(menu.label.contains("名前"))
  }

  func testDisplayLimitNoticeReplacesLoadMoreAtEndOfResults() {
    let app = launchApp()
    search("display-limit", in: app)
    let more = app.buttons["もっと読み込む"]
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    let notice = app.staticTexts["searchDisplayLimitNotice"]
    XCTAssertFalse(notice.exists)
    XCTAssertFalse(app.staticTexts["表示できるのは上位1,000件までです。検索条件を絞り込めます。"].exists)
    more.tap()
    let scroll = app.scrollViews.firstMatch
    for _ in 0..<100 {
      if notice.exists && notice.isHittable { break }
      scroll.swipeUp(velocity: .fast)
    }
    XCTAssertTrue(notice.isHittable)
    XCTAssertEqual(notice.label, "取得できるリポジトリは上位1,000件までです。別のキーワードで検索をお試しください。")
    let warning = app.images["searchDisplayLimitWarning"]
    XCTAssertTrue(warning.isHittable)
    XCTAssertEqual(warning.label, "警告")
    XCTAssertFalse(more.exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testSortChangesResultOrderAndRetainsSelectionForNextSearch() {
    let app = launchApp()
    search("sorting", in: app)
    let rows = app.staticTexts.matching(identifier: "repositoryName")
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/swift")
    app.buttons["searchSortMenu"].tap()
    app.buttons["スター数が少ない順"].tap()
    XCTAssertTrue(app.staticTexts["searchResultCount"].waitForExistence(timeout: 5))
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/second")
    search("empty", in: app)
    XCTAssertTrue(app.staticTexts["該当するリポジトリはありません"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["searchSortMenu"].label.contains("スター数が少ない順"))
    search("sorting", in: app)
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.element(boundBy: 0).label, "example/second")
  }

  func testHistorySuggestionSurvivesRelaunchAndCanBeCleared() {
    let app = launchApp()
    search("swift", in: app)
    XCTAssertTrue(app.staticTexts["searchResultCount"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("swi")
    let suggestion = app.buttons["swift"]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    suggestion.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "swift")
    XCTAssertTrue(app.staticTexts["example/swift"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["searchResultCount"].label, "検索結果: 1件")
    field.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
    app.buttons["検索履歴を消去"].tap()
    XCTAssertFalse(suggestion.exists)
    app.terminate()
    app.launch()
    app.searchFields.firstMatch.tap()
    XCTAssertFalse(app.buttons["swift"].exists)
    XCTAssertFalse(app.buttons["検索履歴を消去"].exists)
  }

  func testDeletingFilteredHistorySuggestionPersistsWithoutSearching() {
    let app = launchApp()
    search("swift", in: app)
    XCTAssertTrue(app.staticTexts["searchResultCount"].waitForExistence(timeout: 5))
    search("kotlin", in: app)
    XCTAssertTrue(app.staticTexts["searchResultCount"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("swi")
    let suggestion = app.buttons["swift"]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
    suggestion.swipeLeft()
    let delete = app.buttons.matching(
      NSPredicate(format: "label == 'Delete' OR label == '削除'")
    ).firstMatch
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertFalse(suggestion.exists)
    XCTAssertEqual(field.value as? String, "swi")
    XCTAssertFalse(app.staticTexts["searchResultCount"].exists)
    app.terminate()
    app.launch()
    app.searchFields.firstMatch.tap()
    XCTAssertTrue(app.buttons["kotlin"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["swift"].exists)
    app.buttons["kotlin"].swipeLeft()
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    XCTAssertFalse(app.buttons["kotlin"].exists)
    XCTAssertFalse(app.buttons["検索履歴を消去"].exists)
  }

  func testPaginationFailureRetryAndBookmarkSynchronization() {
    let app = launchApp()
    search("pagination", in: app)
    let first = app.staticTexts["example/swift"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["searchResultCount"].label, "検索結果: 2件")
    app.buttons["もっと読み込む"].tap()
    XCTAssertTrue(app.activityIndicators["additionalSearchLoading"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.activityIndicators["additionalSearchLoading"].label, "読み込み中")
    XCTAssertTrue(first.exists)
    XCTAssertFalse(app.buttons["もっと読み込む"].exists)
    XCTAssertFalse(app.otherElements["initialSearchLoading"].exists)
    XCTAssertTrue(app.buttons["再試行"].waitForExistence(timeout: 5))
    XCTAssertTrue(first.exists)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "追加読み込みに失敗しました。"))
        .firstMatch.exists)
    app.buttons["再試行"].tap()
    XCTAssertTrue(app.activityIndicators["additionalSearchLoading"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.activityIndicators["additionalSearchLoading"].label, "読み込み中")
    let second = app.staticTexts["example/second"]
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts.matching(identifier: "example/swift").count, 1)
    XCTAssertFalse(app.buttons["もっと読み込む"].exists)
    XCTAssertFalse(app.buttons["再試行"].exists)
    XCTAssertFalse(app.staticTexts["searchDisplayLimitNotice"].exists)
    second.tap()
    app.buttons["Add to Bookmark"].tap()
    app.tabBars.buttons["Bookmark"].tap()
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["もっと読み込む"].exists)
    second.tap()
    app.buttons["Remove from Bookmark"].tap()
    app.tabBars.buttons["Search"].tap()
    XCTAssertTrue(app.buttons["Add to Bookmark"].waitForExistence(timeout: 5))
  }

  func testEditingDuringAdditionalLoadingClearsPreviousSearch() {
    let app = launchApp()
    search("pagination", in: app)
    XCTAssertTrue(app.buttons["もっと読み込む"].waitForExistence(timeout: 5))
    app.buttons["もっと読み込む"].tap()
    XCTAssertTrue(app.activityIndicators["additionalSearchLoading"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.activityIndicators["additionalSearchLoading"].label, "読み込み中")
    search("empty", in: app)
    XCTAssertTrue(app.staticTexts["該当するリポジトリはありません"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["searchResultCount"].label, "検索結果: 0件")
    XCTAssertFalse(app.staticTexts["example/swift"].exists)
    XCTAssertFalse(app.activityIndicators["additionalSearchLoading"].exists)
    XCTAssertFalse(app.buttons["再試行"].exists)
  }

  func testEditingSearchAndEmptyFailureLoadingStates() {
    let app = launchApp()
    search("swift", in: app)
    let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift"))
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    let field = app.searchFields.firstMatch
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
    let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift"))
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    result.tap()
    XCTAssertFalse(app.buttons["Add to Bookmark"].isEnabled)
    app.tabBars.buttons["Bookmark"].tap()
    XCTAssertTrue(app.staticTexts["ブックマークを読み込めませんでした"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["ブックマークはまだありません"].exists)
    XCTAssertFalse(app.staticTexts["bookmarkCount"].exists)
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
    let count = app.staticTexts["searchResultCount"]
    XCTAssertTrue(count.isHittable)
    XCTAssertEqual(count.label, "検索結果: 1件")
    XCTAssertGreaterThanOrEqual(count.frame.minX, app.frame.minX)
    XCTAssertLessThanOrEqual(count.frame.maxX, app.frame.maxX)
    XCTAssertLessThanOrEqual(count.frame.maxY, name.frame.minY)
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

    let searchField = app.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    searchField.tap()
    searchField.typeText("swift\n")
    let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift"))
      .firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    result.tap()
    app.buttons["Add to Bookmark"].tap()
    XCTAssertTrue(app.buttons["Remove from Bookmark"].exists)

    app.tabBars.buttons["Bookmark"].tap()
    let bookmark = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "example/swift"))
      .firstMatch
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
