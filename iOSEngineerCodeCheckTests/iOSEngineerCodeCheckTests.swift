import Foundation
import Synchronization
import Testing
@testable import iOSEngineerCodeCheck

private func repository(_ name: String = "owner/repository", stars: Int = 1) -> Repository {
    Repository(fullName: name, language: nil, stargazersCount: stars, watchersCount: 2,
               forksCount: 3, openIssuesCount: 4, owner: .init(avatarUrl: "invalid avatar"))
}

@MainActor
private final class MemoryBookmarks: BookmarkPersistence {
    var saved: [Repository] = []
    var failsLoading = false
    var failsSaving = false
    var writes = 0
    func load() throws -> [Repository] {
        if failsLoading { throw CocoaError(.fileReadCorruptFile) }
        return saved
    }
    func save(_ repositories: [Repository]) throws {
        writes += 1
        if failsSaving { throw CocoaError(.fileWriteOutOfSpace) }
        saved = repositories
    }
}

@MainActor
struct BookmarkStoreTests {
    @Test func addRemoveAndRelaunchShareOneSourceOfTruth() {
        let persistence = MemoryBookmarks()
        let store = BookmarkStore(persistence: persistence)
        let item = repository()
        store.toggle(item)
        #expect(store.contains(repository(stars: 99)))
        #expect(BookmarkStore(persistence: persistence).repositories == [item])
        store.toggle(repository(stars: 99))
        #expect(store.repositories.isEmpty)
        #expect(BookmarkStore(persistence: persistence).repositories.isEmpty)
        store.toggle(item)
        #expect(store.repositories == [item])
    }

    @Test func failedSaveKeepsEveryScreenAndDiskUnchangedAndCanRetry() {
        let persistence = MemoryBookmarks()
        let store = BookmarkStore(persistence: persistence)
        persistence.failsSaving = true
        store.toggle(repository())
        #expect(store.repositories.isEmpty)
        #expect(persistence.saved.isEmpty)
        #expect(store.errorMessage != nil)
        persistence.failsSaving = false
        store.toggle(repository())
        #expect(store.errorMessage == nil)
        persistence.failsSaving = true
        store.toggle(repository())
        #expect(store.contains(repository()))
        #expect(persistence.saved == [repository()])
    }

    @Test func failedLoadPreventsDestructiveOverwriteAndCanRetry() {
        let persistence = MemoryBookmarks()
        persistence.saved = [repository()]
        persistence.failsLoading = true
        let store = BookmarkStore(persistence: persistence)
        #expect(!store.isLoaded)
        #expect(store.errorMessage != nil)
        store.toggle(repository("other/repo"))
        #expect(persistence.writes == 0)
        persistence.failsLoading = false
        store.reload()
        #expect(store.isLoaded)
        #expect(store.errorMessage == nil)
        #expect(store.repositories == [repository()])
    }

    @Test func duplicateSavedIdentitiesAreNormalized() {
        let persistence = MemoryBookmarks()
        persistence.saved = [repository(), repository(stars: 2)]
        #expect(BookmarkStore(persistence: persistence).repositories == [repository()])
    }
}

@MainActor
struct BookmarkPersistenceTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .appending(path: "bookmarks.json")
    }

    @Test func missingFileRoundTripAndRemoval() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = FileBookmarkPersistence(fileURL: url, legacyDefaults: nil)
        #expect(try persistence.load().isEmpty)
        try persistence.save([repository()])
        #expect(try persistence.load() == [repository()])
        try persistence.save([])
        #expect(try persistence.load().isEmpty)
    }

    @Test func migratesLegacyDataWithoutDependingOnMarkedFlag() throws {
        let url = temporaryURL()
        let suite = "BookmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(repository())) as? [String: Any])
        object["marked"] = false
        let data = try JSONSerialization.data(withJSONObject: [object])
        defaults.set(data, forKey: "data")
        let persistence = FileBookmarkPersistence(fileURL: url, legacyDefaults: defaults)
        #expect(try persistence.load() == [repository()])
        #expect(defaults.data(forKey: "data") == data)
        try persistence.save([])
        // A valid empty file must not resurrect legacy bookmarks.
        #expect(try persistence.load().isEmpty)
    }

    @Test func corruptFileIsReportedAndPreserved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("not JSON".utf8)
        try data.write(to: url)
        let persistence = FileBookmarkPersistence(fileURL: url, legacyDefaults: nil)
        #expect(throws: (any Error).self) { try persistence.load() }
        let store = BookmarkStore(persistence: persistence)
        store.toggle(repository())
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func corruptLegacyDataIsNotOverwrittenOrMigrated() throws {
        let url = temporaryURL()
        let suite = "BookmarkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("corrupt legacy JSON".utf8)
        defaults.set(data, forKey: "data")
        let store = BookmarkStore(persistence: FileBookmarkPersistence(fileURL: url, legacyDefaults: defaults))
        #expect(!store.isLoaded)
        store.toggle(repository())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(defaults.data(forKey: "data") == data)
    }

    @Test func fileWriteFailureIsPropagated() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data().write(to: parent) // A file cannot be used as a parent directory.
        let persistence = FileBookmarkPersistence(fileURL: parent.appending(path: "bookmarks.json"), legacyDefaults: nil)
        #expect(throws: (any Error).self) { try persistence.save([repository()]) }
    }
}

private actor ControlledSearch: RepositorySearching {
    private var requests: [String: CheckedContinuation<[Repository], any Error>] = [:]
    private var arrivals: [String: CheckedContinuation<Void, Never>] = [:]

    func search(query: String) async throws -> [Repository] {
        try await withCheckedThrowingContinuation { continuation in
            requests[query] = continuation
            arrivals.removeValue(forKey: query)?.resume()
        }
    }

    func waitForRequest(_ query: String) async {
        if requests[query] != nil { return }
        await withCheckedContinuation { arrivals[query] = $0 }
    }

    func complete(_ query: String, with result: Result<[Repository], any Error>) {
        requests.removeValue(forKey: query)?.resume(with: result)
    }
}

@MainActor
struct RepositorySearchTests {
    @Test func trimsQueryAndPublishesSuccessIncludingEmptyResults() async throws {
        let service = ControlledSearch()
        let search = RepositorySearch(service: service)
        let task = try #require(search.submit("  swift \n"))
        #expect(search.phase == .loading)
        await service.waitForRequest("swift")
        await service.complete("swift", with: .success([repository()]))
        await task.value
        #expect(search.phase == .loaded)
        #expect(search.repositories == [repository()])
        let emptyTask = try #require(search.submit("empty"))
        await service.waitForRequest("empty")
        await service.complete("empty", with: .success([]))
        await emptyTask.value
        #expect(search.phase == .loaded)
        #expect(search.repositories.isEmpty)
    }

    @Test func newestSearchWinsEvenWhenCancelledRequestFinishesLast() async throws {
        let service = ControlledSearch()
        let search = RepositorySearch(service: service)
        let old = try #require(search.submit("old"))
        await service.waitForRequest("old")
        let new = try #require(search.submit("new"))
        await service.waitForRequest("new")
        await service.complete("new", with: .success([repository("new/result")]))
        await new.value
        await service.complete("old", with: .success([repository("old/result")]))
        await old.value
        #expect(search.repositories == [repository("new/result")])
        #expect(search.phase == .loaded)
    }

    @Test func clearingInputInvalidatesPendingFailure() async throws {
        let service = ControlledSearch()
        let search = RepositorySearch(service: service)
        let task = try #require(search.submit("swift"))
        await service.waitForRequest("swift")
        #expect(search.submit(" \n ") == nil)
        await service.complete("swift", with: .failure(URLError(.notConnectedToInternet)))
        await task.value
        #expect(search.phase == .idle)
        #expect(search.repositories.isEmpty)
    }

    @Test func failureIsVisibleAndRetrySucceeds() async throws {
        let service = ControlledSearch()
        let search = RepositorySearch(service: service)
        let task = try #require(search.submit("swift"))
        await service.waitForRequest("swift")
        await service.complete("swift", with: .failure(URLError(.notConnectedToInternet)))
        await task.value
        guard case .failed(let message) = search.phase else {
            Issue.record("Expected a visible failure")
            return
        }
        #expect(!message.isEmpty)
        let retry = try #require(search.submit("swift"))
        await service.waitForRequest("swift")
        await service.complete("swift", with: .success([repository()]))
        await retry.value
        #expect(search.phase == .loaded)
    }

    @Test func cancellationIsNotPresentedAsFailure() async throws {
        let service = ControlledSearch()
        let search = RepositorySearch(service: service)
        let task = try #require(search.submit("swift"))
        await service.waitForRequest("swift")
        await service.complete("swift", with: .failure(CancellationError()))
        await task.value
        #expect(search.phase == .idle)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable { let status: Int; let data: Data }
    static let stubs = Mutex<[String: Stub]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              url.host == "api.github.com", url.path == "/search/repositories",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.count == 1,
              components.percentEncodedQuery?.contains("+") == false,
              let query = components.queryItems?.first(where: { $0.name == "q" })?.value,
              let stub = Self.stubs.withLock({ $0[query] }),
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct GitHubRepositoryServiceTests {
    private func service(query: String, status: Int = 200, body: String) -> GitHubRepositoryService {
        StubURLProtocol.stubs.withLock { $0[query] = .init(status: status, data: Data(body.utf8)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GitHubRepositoryService(session: URLSession(configuration: configuration))
    }

    @Test func decodesSnakeCaseAndKeepsReservedCharactersInOneQueryValue() async throws {
        let query = "日本語 C++ & #swift?=yes"
        let service = service(query: query, body: """
        {"items":[{"full_name":"owner/repository","language":null,"stargazers_count":1,
        "watchers_count":2,"forks_count":3,"open_issues_count":4,"owner":{"avatar_url":"invalid avatar"}}]}
        """)
        defer { service.session.invalidateAndCancel() }
        #expect(try await service.search(query: query) == [repository()])
        #expect(repository().avatarURL == nil)
        #expect(repository().id == repository(stars: 999).id)
    }

    @Test(arguments: [403, 429, 500]) func rejectsHTTPFailuresBeforeDecoding(status: Int) async {
        let query = "status-\(status)"
        let service = service(query: query, status: status, body: "not JSON")
        defer { service.session.invalidateAndCancel() }
        await #expect(throws: GitHubRepositoryService.SearchError.httpStatus(status)) {
            try await service.search(query: query)
        }
    }

    @Test func rejectsMalformedResponse() async {
        let service = service(query: "malformed", body: "{\"items\":[{}]}")
        defer { service.session.invalidateAndCancel() }
        await #expect(throws: DecodingError.self) { try await service.search(query: "malformed") }
    }
}
