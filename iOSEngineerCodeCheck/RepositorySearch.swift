import Foundation
import Observation

struct RepositoryPage: Sendable {
  let repositories: [Repository]
  let hasMore: Bool
  let totalCount: Int
}

enum RepositorySort: String, CaseIterable, Sendable {
  case bestMatch, starsDescending, starsAscending, forksDescending, forksAscending
  case updatedDescending, updatedAscending

  var title: String {
    switch self {
    case .bestMatch: "関連度順"
    case .starsDescending: "スター数が多い順"
    case .starsAscending: "スター数が少ない順"
    case .forksDescending: "フォーク数が多い順"
    case .forksAscending: "フォーク数が少ない順"
    case .updatedDescending: "更新が新しい順"
    case .updatedAscending: "更新が古い順"
    }
  }

  var queryItems: [URLQueryItem] {
    let field: String
    let order: String
    switch self {
    case .bestMatch: return []
    case .starsDescending: (field, order) = ("stars", "desc")
    case .starsAscending: (field, order) = ("stars", "asc")
    case .forksDescending: (field, order) = ("forks", "desc")
    case .forksAscending: (field, order) = ("forks", "asc")
    case .updatedDescending: (field, order) = ("updated", "desc")
    case .updatedAscending: (field, order) = ("updated", "asc")
    }
    return [URLQueryItem(name: "sort", value: field), URLQueryItem(name: "order", value: order)]
  }
}

protocol RepositorySearching: Sendable {
  func search(query: String, page: Int, sort: RepositorySort) async throws -> RepositoryPage
}

struct GitHubRepositoryService: RepositorySearching {
  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func search(
    query: String, page: Int, sort: RepositorySort = .bestMatch
  ) async throws -> RepositoryPage {
    let pageSize = 30
    guard (1...34).contains(page) else { throw SearchError.invalidURL }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/search/repositories"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "per_page", value: String(pageSize)),
    ]
    components.queryItems?.append(contentsOf: sort.queryItems)
    // Escape literal plus signs for servers that interpret query strings as form data.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
      of: "+", with: "%2B")
    guard let url = components.url else { throw SearchError.invalidURL }
    let (data, response) = try await session.data(from: url)
    guard let response = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
    guard (200..<300).contains(response.statusCode) else {
      throw SearchError.httpStatus(response.statusCode)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let result = try decoder.decode(SearchResponse.self, from: data)
    let items = result.items
    var seen = Set<Repository.ID>()
    return RepositoryPage(
      repositories: items.filter { seen.insert($0.id).inserted },
      // GitHub exposes at most 1,000 matches. Use the server count, not the
      // deduplicated row count, and stop if the server returns an empty page.
      hasMore: !items.isEmpty && page * pageSize < min(result.totalCount, 1_000),
      totalCount: result.totalCount)
  }

  private struct SearchResponse: Decodable {
    let totalCount: Int
    let items: [Repository]
  }

  enum SearchError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
      switch self {
      case .invalidURL: "検索URLを作成できませんでした。"
      case .invalidResponse: "サーバーから不正な応答が返されました。"
      case .httpStatus(let status): "検索に失敗しました（HTTP \(status)）。時間をおいて再度お試しください。"
      }
    }
  }
}

@MainActor @Observable
final class RepositorySearch {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  enum AdditionalPhase: Equatable {
    case idle, loading
    case failed(String)
  }

  private(set) var additionalPhase: AdditionalPhase = .idle
  private(set) var hasMore = false
  private var nextPage = 1
  private let service: any RepositorySearching
  private var requestID = UUID()
  private var submittedQuery: String?
  private var task: Task<Void, Never>?
  private(set) var repositories: [Repository] = []
  private(set) var sort: RepositorySort = .bestMatch
  private(set) var totalCount: Int?
  private(set) var phase: Phase = .idle

  var hasReachedDisplayLimit: Bool {
    phase == .loaded && !hasMore && repositories.count >= 1_000
  }

  init(service: any RepositorySearching) {
    self.service = service
  }

  // Returning the task lets tests await completion without timing-based sleeps.
  @discardableResult
  func submit(_ text: String) -> Task<Void, Never>? {
    clear()
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return nil }
    submittedQuery = query
    phase = .loading
    return request(query: query, page: 1)
  }

  @discardableResult
  func changeSort(_ value: RepositorySort) -> Task<Void, Never>? {
    guard value != sort else { return nil }
    sort = value
    // Re-fetch the whole search from page one, never just sort the loaded rows.
    guard let query = submittedQuery else { return nil }
    return submit(query)
  }

  @discardableResult
  func loadMore() -> Task<Void, Never>? {
    guard phase == .loaded, hasMore, additionalPhase != .loading,
      let query = submittedQuery
    else { return nil }
    additionalPhase = .loading
    return request(query: query, page: nextPage)
  }

  private func request(query: String, page: Int) -> Task<Void, Never> {
    let id = requestID
    let service = service
    let sort = sort
    let task = Task { [weak self] in
      do {
        let result = try await service.search(query: query, page: page, sort: sort)
        try Task.checkCancellation()
        guard let self, self.requestID == id else { return }
        var seen = Set(self.repositories.map(\.id))
        self.repositories.append(
          contentsOf: result.repositories.filter { seen.insert($0.id).inserted })
        self.totalCount = result.totalCount
        self.nextPage = page + 1
        self.hasMore = result.hasMore
        self.phase = .loaded
        self.additionalPhase = .idle
        self.task = nil
      } catch {
        guard let self, self.requestID == id else { return }
        let cancelled =
          Task.isCancelled || error is CancellationError
          || (error as? URLError)?.code == .cancelled
        if page == 1 {
          self.phase = cancelled ? .idle : .failed(error.localizedDescription)
        } else {
          self.additionalPhase = cancelled ? .idle : .failed(error.localizedDescription)
        }
        self.task = nil
      }
    }
    self.task = task
    return task
  }

  // Editing invalidates the previous submission without starting a new request.
  func inputChanged(_ text: String) {
    if text.trimmingCharacters(in: .whitespacesAndNewlines) != submittedQuery {
      clear()
    }
  }

  func clear() {
    task?.cancel()
    task = nil
    submittedQuery = nil
    requestID = UUID()
    repositories = []
    totalCount = nil
    phase = .idle
    additionalPhase = .idle
    nextPage = 1
    hasMore = false
  }
}
