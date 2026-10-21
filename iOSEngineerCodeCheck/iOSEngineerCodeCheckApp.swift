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
            RepositoryTabs(service: UITestRepositoryService(), persistence: FileBookmarkPersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: "BookmarkUITests")
                    .appending(path: testID)
                    .appending(path: "bookmarks.json"),
                legacyDefaults: nil
            ))
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
}

#if DEBUG
struct PreviewRepositoryService: RepositorySearching {
    func search(query: String) async throws -> [Repository] {
        [Repository(fullName: "example/swift", language: "Swift", stargazersCount: 42,
                    watchersCount: 10, forksCount: 3, openIssuesCount: 2,
                    owner: .init(avatarUrl: ""))]
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
        default: return try await PreviewRepositoryService().search(query: query)
        }
    }
}
#endif
