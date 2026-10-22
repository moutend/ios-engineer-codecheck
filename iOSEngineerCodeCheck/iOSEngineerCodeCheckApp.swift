import SwiftUI

@main
struct IOSEngineerCodeCheckApp: App {
  var body: some Scene {
    WindowGroup {
      rootView
    }
  }

  @ViewBuilder
  private var rootView: some View {
    #if DEBUG
      if let testID = ProcessInfo.processInfo.environment["BOOKMARK_UI_TEST_ID"] {
        RepositoryTabs(
          service: UITestRepositoryService(), persistence: uiTestPersistence(testID: testID),
          historyDefaults: UserDefaults(suiteName: "SearchHistoryUITests.\(testID)"))
      } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        // The unit-test host must not read or migrate a developer's bookmarks.
        RepositoryTabs(
          service: PreviewRepositoryService(), persistence: PreviewBookmarkPersistence(),
          historyDefaults: nil)
      } else {
        RepositoryTabs()
      }
    #else
      RepositoryTabs()
    #endif
  }

  #if DEBUG
    private func uiTestPersistence(testID: String) -> any BookmarkPersistence {
      if ProcessInfo.processInfo.environment["BOOKMARK_UI_TEST_LOAD_FAILURE"] == "1" {
        return UITestRecoverablePersistence()
      }
      return FileBookmarkPersistence(
        fileURL: FileManager.default.temporaryDirectory
          .appending(path: "BookmarkUITests")
          .appending(path: testID)
          .appending(path: "bookmarks.json"),
        legacyDefaults: nil
      )
    }
  #endif
}

#if DEBUG
  struct PreviewRepositoryService: RepositorySearching {
    func search(query: String, page: Int) async throws -> RepositoryPage {
      RepositoryPage(
        repositories: [
          Repository(
            fullName: "example/swift", language: "Swift", stargazersCount: 42,
            watchersCount: 10, forksCount: 3, openIssuesCount: 2,
            owner: .init(avatarUrl: ""))
        ], hasMore: false, totalCount: 1)
    }
  }

  @MainActor
  struct PreviewBookmarkPersistence: BookmarkPersistence {
    func load() throws -> [Repository] { [] }
    func save(_ repositories: [Repository]) throws {}
  }

  /// UI scenarios remain isolated from GitHub and the user's saved data.
  actor UITestRepositoryService: RepositorySearching {
    private var failedPage = false

    func search(query: String, page: Int) async throws -> RepositoryPage {
      if query == "pagination" {
        if page == 1 {
          failedPage = false
          let first = try await PreviewRepositoryService().search(query: query, page: page)
          return RepositoryPage(repositories: first.repositories, hasMore: true, totalCount: 2)
        }
        try await Task.sleep(for: .seconds(2))
        if !failedPage {
          failedPage = true
          throw URLError(.notConnectedToInternet)
        }
        let first = try await PreviewRepositoryService().search(query: query, page: page)
        let second = Repository(
          fullName: "example/second", language: "Swift", stargazersCount: 7,
          watchersCount: 1, forksCount: 1, openIssuesCount: 0, owner: .init(avatarUrl: ""))
        return RepositoryPage(
          repositories: first.repositories + [second], hasMore: false, totalCount: 2)
      }
      switch query {
      case "empty": return RepositoryPage(repositories: [], hasMore: false, totalCount: 0)
      case "failure": throw URLError(.notConnectedToInternet)
      case "slow":
        try await Task.sleep(for: .seconds(30))
        return try await PreviewRepositoryService().search(query: query, page: page)
      case "layout":
        return RepositoryPage(
          repositories: [
            Repository(
              fullName: "example/a-repository-with-a-very-long-name-for-accessibility",
              language: "JavaScript", stargazersCount: 123_456_789,
              watchersCount: 987_654_321, forksCount: 123_456_789,
              openIssuesCount: 987_654_321, owner: .init(avatarUrl: ""))
          ], hasMore: false, totalCount: 1)
      default: return try await PreviewRepositoryService().search(query: query, page: page)
      }
    }
  }

  @MainActor
  final class UITestRecoverablePersistence: BookmarkPersistence {
    private var shouldFail = true
    private var repositories: [Repository] = []
    func load() throws -> [Repository] {
      if shouldFail {
        shouldFail = false
        throw CocoaError(.fileReadCorruptFile)
      }
      return repositories
    }
    func save(_ repositories: [Repository]) throws { self.repositories = repositories }
  }
#endif
