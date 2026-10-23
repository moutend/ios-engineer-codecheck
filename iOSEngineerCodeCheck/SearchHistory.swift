import Foundation
import Observation

@MainActor @Observable
final class SearchHistory {
  private(set) var queries: [String]
  private let defaults: UserDefaults?
  private static let key = "repositorySearchHistory"
  private static let limit = 20

  // A nil store keeps previews and unit tests isolated from the user's history.
  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    var seen = Set<String>()
    queries = Array(
      (defaults?.stringArray(forKey: Self.key) ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        .prefix(Self.limit))
  }

  func record(_ text: String) {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    queries.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
    queries.insert(query, at: 0)
    queries = Array(queries.prefix(Self.limit))
    defaults?.set(queries, forKey: Self.key)
  }

  func suggestions(for text: String) -> [String] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return queries.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
  }

  func clear() {
    queries = []
    defaults?.removeObject(forKey: Self.key)
  }

  func remove(suggestionsAt offsets: IndexSet, matching text: String) {
    let suggestions = suggestions(for: text)
    let removed = Set(offsets.map { suggestions[$0] })
    queries.removeAll { removed.contains($0) }
    defaults?.set(queries, forKey: Self.key)
  }
}
