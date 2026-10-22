import Foundation
import Synchronization
import Testing

@testable import iOSEngineerCodeCheck

private func repository(_ name: String = "owner/repository", stars: Int = 1) -> Repository {
  Repository(
    fullName: name, language: nil, stargazersCount: stars, watchersCount: 2,
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
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(repository())) as? [String: Any])
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
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
    let store = BookmarkStore(
      persistence: FileBookmarkPersistence(fileURL: url, legacyDefaults: defaults))
    #expect(!store.isLoaded)
    store.toggle(repository())
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(defaults.data(forKey: "data") == data)
  }

  @Test func fileWriteFailureIsPropagated() throws {
    let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    try Data().write(to: parent)  // A file cannot be used as a parent directory.
    let persistence = FileBookmarkPersistence(
      fileURL: parent.appending(path: "bookmarks.json"), legacyDefaults: nil)
    #expect(throws: (any Error).self) { try persistence.save([repository()]) }
  }
}

private actor ControlledSearch: RepositorySearching {
  private var requests: [String: CheckedContinuation<RepositoryPage, any Error>] = [:]
  private var arrivals: [String: CheckedContinuation<Void, Never>] = [:]

  func search(query: String, page: Int) async throws -> RepositoryPage {
    let query = "\(query):\(page)"
    return try await withCheckedThrowingContinuation { continuation in
      requests[query] = continuation
      arrivals.removeValue(forKey: query)?.resume()
    }
  }

  func waitForRequest(_ query: String, page: Int = 1) async {
    let query = "\(query):\(page)"
    if requests[query] != nil { return }
    await withCheckedContinuation { arrivals[query] = $0 }
  }

  func complete(
    _ query: String, page: Int = 1, hasMore: Bool = false, totalCount: Int? = nil,
    with result: Result<[Repository], any Error>
  ) {
    requests.removeValue(forKey: "\(query):\(page)")?.resume(
      with: result.map {
        RepositoryPage(repositories: $0, hasMore: hasMore, totalCount: totalCount ?? $0.count)
      })
  }
}

@MainActor
struct RepositorySearchTests {
  @Test func totalCountSurvivesPaginationFailureAndClearsOnEditing() async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    #expect(search.totalCount == nil)
    let first = try #require(search.submit("swift"))
    await service.waitForRequest("swift")
    await service.complete("swift", hasMore: true, totalCount: 2345, with: .success([repository()]))
    await first.value
    #expect(search.totalCount == 2345)
    let more = try #require(search.loadMore())
    await service.waitForRequest("swift", page: 2)
    await service.complete("swift", page: 2, with: .failure(URLError(.timedOut)))
    await more.value
    #expect(search.totalCount == 2345)
    search.inputChanged("empty")
    #expect(search.totalCount == nil)
    let empty = try #require(search.submit("empty"))
    await service.waitForRequest("empty")
    await service.complete("empty", with: .success([]))
    await empty.value
    #expect(search.totalCount == 0)
  }

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

  @Test(arguments: [false, true])
  func editingInputInvalidatesPendingSuccessAndFailure(fails: Bool) async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let task = try #require(search.submit("swift"))
    await service.waitForRequest("swift")
    search.inputChanged("kotlin")
    #expect(search.phase == .idle)
    await service.complete(
      "swift",
      with: fails
        ? .failure(URLError(.notConnectedToInternet)) : .success([repository()]))
    await task.value
    #expect(search.phase == .idle)
    #expect(search.repositories.isEmpty)
  }

  @Test(arguments: [false, true])
  func editingInputClearsCompletedResultsAndErrors(fails: Bool) async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let task = try #require(search.submit("swift"))
    await service.waitForRequest("swift")
    await service.complete(
      "swift",
      with: fails
        ? .failure(URLError(.notConnectedToInternet)) : .success([repository()]))
    await task.value
    let completedPhase = search.phase
    search.inputChanged(" swift ")
    #expect(search.phase == completedPhase)
    search.inputChanged("kotlin")
    #expect(search.phase == .idle)
    #expect(search.repositories.isEmpty)
  }

  @Test func obsoleteFailureCannotReplaceNewResults() async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let old = try #require(search.submit("old"))
    await service.waitForRequest("old")
    let new = try #require(search.submit("new"))
    await service.waitForRequest("new")
    await service.complete("new", with: .success([repository("new/result")]))
    await new.value
    await service.complete("old", with: .failure(URLError(.timedOut)))
    await old.value
    #expect(search.repositories == [repository("new/result")])
    #expect(search.phase == .loaded)
  }

  @Test func cancelledTaskWithSuccessfulResponseStopsLoading() async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let task = try #require(search.submit("swift"))
    await service.waitForRequest("swift")
    task.cancel()
    await service.complete("swift", with: .success([repository()]))
    await task.value
    #expect(search.phase == .idle)
    #expect(search.repositories.isEmpty)
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

@MainActor
struct PaginationTests {
  @Test func retriesSamePageRetainsResultsDeduplicatesAndStopsAtEnd() async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    #expect(search.loadMore() == nil)
    let first = try #require(search.submit("swift"))
    #expect(search.loadMore() == nil)
    await service.waitForRequest("swift")
    await service.complete("swift", hasMore: true, with: .success([repository(), repository()]))
    await first.value
    let more = try #require(search.loadMore())
    #expect(search.loadMore() == nil)
    #expect(search.phase == .loaded)
    #expect(search.additionalPhase == .loading)
    #expect(search.repositories == [repository()])
    await service.waitForRequest("swift", page: 2)
    await service.complete("swift", page: 2, with: .failure(URLError(.timedOut)))
    await more.value
    #expect(search.repositories == [repository()])
    #expect(search.hasMore)
    guard case .failed = search.additionalPhase else {
      Issue.record("Expected an additional-page error")
      return
    }
    let retry = try #require(search.loadMore())
    #expect(search.additionalPhase == .loading)
    await service.waitForRequest("swift", page: 2)
    await service.complete(
      "swift", page: 2, hasMore: true,
      with: .success([repository(stars: 99), repository("second"), repository("second")]))
    await retry.value
    #expect(search.repositories == [repository(), repository("second")])
    let last = try #require(search.loadMore())
    await service.waitForRequest("swift", page: 3)
    await service.complete("swift", page: 3, with: .success([]))
    await last.value
    #expect(search.repositories.count == 2)
    #expect(!search.hasMore)
    #expect(search.additionalPhase == .idle)
    #expect(search.loadMore() == nil)
  }

  @Test(arguments: [false, true], [false, true])
  func obsoleteAdditionalResponseCannotChangeNewSearch(fails: Bool, finishesFirst: Bool)
    async throws
  {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let first = try #require(search.submit("old"))
    await service.waitForRequest("old")
    await service.complete("old", hasMore: true, with: .success([repository()]))
    await first.value
    let more = try #require(search.loadMore())
    await service.waitForRequest("old", page: 2)
    let new = try #require(search.submit("new"))
    await service.waitForRequest("new")
    #expect(search.repositories.isEmpty)
    #expect(search.additionalPhase == .idle)
    #expect(!search.hasMore)
    if !finishesFirst {
      await service.complete("new", hasMore: true, with: .success([repository("new")]))
      await new.value
    }
    await service.complete(
      "old", page: 2,
      with: fails ? .failure(URLError(.timedOut)) : .success([repository("old/late")]))
    await more.value
    if finishesFirst {
      #expect(search.phase == .loading)
      #expect(search.repositories.isEmpty)
      await service.complete("new", hasMore: true, with: .success([repository("new")]))
      await new.value
    }
    #expect(search.repositories == [repository("new")])
    #expect(search.phase == .loaded)
    #expect(search.additionalPhase == .idle)
    #expect(search.hasMore)
  }

  @Test func cancelledAdditionalPageCanRetryWithoutLosingBookmarksOrResults() async throws {
    let service = ControlledSearch()
    let search = RepositorySearch(service: service)
    let persistence = MemoryBookmarks()
    let bookmarks = BookmarkStore(persistence: persistence)
    bookmarks.toggle(repository(stars: 99))
    let first = try #require(search.submit("swift"))
    await service.waitForRequest("swift")
    await service.complete("swift", hasMore: true, with: .success([repository()]))
    await first.value
    #expect(bookmarks.contains(search.repositories[0]))
    let more = try #require(search.loadMore())
    await service.waitForRequest("swift", page: 2)
    more.cancel()
    await service.complete("swift", page: 2, with: .success([repository("ignored")]))
    await more.value
    #expect(search.phase == .loaded)
    #expect(search.additionalPhase == .idle)
    #expect(search.repositories == [repository()])
    let retry = try #require(search.loadMore())
    await service.waitForRequest("swift", page: 2)
    await service.complete("swift", page: 2, with: .success([repository("second")]))
    await retry.value
    bookmarks.toggle(search.repositories[0])
    bookmarks.toggle(search.repositories[1])
    #expect(!bookmarks.contains(repository()))
    #expect(BookmarkStore(persistence: persistence).repositories == [repository("second")])
  }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Stub: Sendable {
    let status: Int
    let data: Data
    let page: Int
  }
  static let stubs = Mutex<[String: Stub]>([:])
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url,
      url.host == "api.github.com", url.path == "/search/repositories",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.queryItems?.count == 3,
      components.queryItems?.first(where: { $0.name == "per_page" })?.value == "30",
      components.percentEncodedQuery?.contains("+") == false,
      let query = components.queryItems?.first(where: { $0.name == "q" })?.value,
      let stub = Self.stubs.withLock({ $0[query] }),
      components.queryItems?.first(where: { $0.name == "page" })?.value == String(stub.page),
      let response = HTTPURLResponse(
        url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)
    else {
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
  private func service(query: String, status: Int = 200, page: Int = 1, body: String)
    -> GitHubRepositoryService
  {
    StubURLProtocol.stubs.withLock {
      $0[query] = .init(status: status, data: Data(body.utf8), page: page)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return GitHubRepositoryService(session: URLSession(configuration: configuration))
  }

  @Test(arguments: [1, 2, 33, 34])
  func sendsPageAndStopsAtSearchLimit(page: Int) async throws {
    let query = "page-\(page)"
    let item = """
      {"full_name":"owner/repository","language":null,"stargazers_count":1,
      "watchers_count":2,"forks_count":3,"open_issues_count":4,"owner":{"avatar_url":"invalid avatar"}}
      """
    let service = service(
      query: query, page: page,
      body: "{\"total_count\":2000,\"items\":[\(item),\(item)]}")
    defer { service.session.invalidateAndCancel() }
    let result = try await service.search(query: query, page: page)
    #expect(result.repositories == [repository()])
    #expect(result.totalCount == 2000)
    #expect(result.hasMore == (page < 34))
  }

  @Test(arguments: [0, 1, 30, 31])
  func totalCountDeterminesContinuation(total: Int) async throws {
    let query = "total-\(total)"
    let item = """
      {"full_name":"owner/repository","language":null,"stargazers_count":1,
      "watchers_count":2,"forks_count":3,"open_issues_count":4,"owner":{"avatar_url":"invalid avatar"}}
      """
    let service = service(
      query: query,
      body: "{\"total_count\":\(total),\"items\":[\(item)]}")
    defer { service.session.invalidateAndCancel() }
    #expect(try await service.search(query: query, page: 1).hasMore == (total > 30))
  }

  @Test func emptyPageStopsEvenWithOutdatedTotalCount() async throws {
    let service = service(query: "empty-page", page: 2, body: "{\"total_count\":100,\"items\":[]}")
    defer { service.session.invalidateAndCancel() }
    let result = try await service.search(query: "empty-page", page: 2)
    #expect(result.repositories.isEmpty)
    #expect(!result.hasMore)
  }

  @Test func decodesSnakeCaseAndKeepsReservedCharactersInOneQueryValue() async throws {
    let query = "日本語 C++ & #swift?=yes"
    let service = service(
      query: query,
      body: """
        {"total_count":1,"items":[{"full_name":"owner/repository","language":null,"stargazers_count":1,
        "watchers_count":2,"forks_count":3,"open_issues_count":4,"owner":{"avatar_url":"invalid avatar"}}]}
        """)
    defer { service.session.invalidateAndCancel() }
    #expect(try await service.search(query: query, page: 1).repositories == [repository()])
    #expect(repository().avatarURL == nil)
    #expect(repository().id == repository(stars: 999).id)
  }

  @Test(arguments: [403, 429, 500]) func rejectsHTTPFailuresBeforeDecoding(status: Int) async {
    let query = "status-\(status)"
    let service = service(query: query, status: status, body: "not JSON")
    defer { service.session.invalidateAndCancel() }
    await #expect(throws: GitHubRepositoryService.SearchError.httpStatus(status)) {
      try await service.search(query: query, page: 1)
    }
  }

  @Test func duplicateResponseIdentitiesProduceOneRow() async throws {
    let item = """
      {"full_name":"owner/repository","language":null,"stargazers_count":1,
      "watchers_count":2,"forks_count":3,"open_issues_count":4,"owner":{"avatar_url":"invalid avatar"}}
      """
    let service = service(
      query: "duplicates", body: "{\"total_count\":2,\"items\":[\(item),\(item)]}")
    defer { service.session.invalidateAndCancel() }
    #expect(try await service.search(query: "duplicates", page: 1).repositories == [repository()])
  }

  @Test(arguments: ["not JSON", "{}", "{\"items\":null}", "{\"items\":[{}]}"])
  func rejectsMalformedResponse(body: String) async {
    let service = service(query: "malformed-" + body, body: body)
    defer { service.session.invalidateAndCancel() }
    await #expect(throws: DecodingError.self) {
      try await service.search(query: "malformed-" + body, page: 1)
    }
  }
}

@MainActor
struct SearchHistoryTests {
  @Test func trimsDeduplicatesAndFiltersRecentQueries() {
    let history = SearchHistory()
    history.record("  Swift ")
    history.record("kotlin")
    history.record("SWIFT")
    history.record(" \n ")
    #expect(history.queries == ["SWIFT", "kotlin"])
    #expect(history.suggestions(for: " wi ") == ["SWIFT"])
    #expect(history.suggestions(for: "missing").isEmpty)
    #expect(history.suggestions(for: "") == history.queries)
  }

  @Test func boundsHistoryAndPersistsRecordsAndDeletion() throws {
    let suite = "SearchHistoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let history = SearchHistory(defaults: defaults)
    for index in 0..<25 { history.record("query-\(index)") }
    #expect(history.queries.count == 20)
    #expect(history.queries.first == "query-24")
    #expect(history.queries.last == "query-5")
    #expect(SearchHistory(defaults: defaults).queries == history.queries)
    history.clear()
    #expect(history.queries.isEmpty)
    #expect(SearchHistory(defaults: defaults).queries.isEmpty)
  }
}
