import Foundation
import Observation

protocol RepositorySearching: Sendable {
    func search(query: String) async throws -> [Repository]
}

struct GitHubRepositoryService: RepositorySearching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String) async throws -> [Repository] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/search/repositories"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // Escape literal plus signs for servers that interpret query strings as form data.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw SearchError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw SearchError.httpStatus(response.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode(SearchResponse.self, from: data).items
        var seen = Set<Repository.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private struct SearchResponse: Decodable {
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
        case idle, loading, loaded, failed(String)
    }

    private let service: any RepositorySearching
    private var requestID = UUID()
    private var submittedQuery: String?
    private var task: Task<Void, Never>?
    private(set) var repositories: [Repository] = []
    private(set) var phase: Phase = .idle

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
        let id = requestID
        let service = service
        task = Task { [weak self] in
            do {
                let repositories = try await service.search(query: query)
                guard let self, self.requestID == id else { return }
                guard !Task.isCancelled else {
                    self.phase = .idle
                    return
                }
                self.repositories = repositories
                self.phase = .loaded
            } catch {
                guard let self, self.requestID == id else { return }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.phase = .idle
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
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
        phase = .idle
    }
}
