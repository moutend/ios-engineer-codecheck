import SwiftUI

@main
struct iOSEngineerCodeCheckApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if let testID = ProcessInfo.processInfo.environment["BOOKMARK_UI_TEST_ID"] {
            RepositoryTabs(service: UITestRepositoryService(), persistence: uiTestPersistence(testID: testID))
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // The unit-test host must not read or migrate a developer's bookmarks.
            RepositoryTabs(service: PreviewRepositoryService(), persistence: PreviewBookmarkPersistence())
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
    func search(query: String) async throws -> [Repository] {
        [
            Repository(
                fullName: "example/swift", language: "Swift", stargazersCount: 42,
                watchersCount: 10, forksCount: 3, openIssuesCount: 2,
                owner: .init(avatarUrl: ""))
        ]
    }
}

@MainActor
struct PreviewBookmarkPersistence: BookmarkPersistence {
    func load() throws -> [Repository] { [] }
    func save(_ repositories: [Repository]) throws {}
}

/// UI scenarios remain isolated from GitHub and the user's saved data.
struct UITestRepositoryService: RepositorySearching {
    func search(query: String) async throws -> [Repository] {
        switch query {
        case "empty": return []
        case "failure": throw URLError(.notConnectedToInternet)
        case "slow":
            try await Task.sleep(for: .seconds(30))
            return try await PreviewRepositoryService().search(query: query)
        case "layout":
            return [
                Repository(
                    fullName: "example/a-repository-with-a-very-long-name-for-accessibility",
                    language: "JavaScript", stargazersCount: 123456789,
                    watchersCount: 987654321, forksCount: 123456789,
                    openIssuesCount: 987654321, owner: .init(avatarUrl: ""))
            ]
        default: return try await PreviewRepositoryService().search(query: query)
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
