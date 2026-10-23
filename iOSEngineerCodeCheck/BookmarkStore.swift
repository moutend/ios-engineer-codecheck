import Foundation
import Observation

enum BookmarkSort: CaseIterable {
  case name
  case dateAdded

  var title: String {
    switch self {
    case .name: "名前"
    case .dateAdded: "追加日"
    }
  }

  func sorted(_ repositories: [Repository]) -> [Repository] {
    switch self {
    case .name: repositories.sorted { $0.fullName < $1.fullName }
    case .dateAdded: Array(repositories.reversed())
    }
  }
}

@MainActor @Observable
final class BookmarkStore {
  private let persistence: any BookmarkPersistence
  private(set) var repositories: [Repository] = []
  private(set) var isLoaded = false
  private(set) var errorMessage: String?

  init(persistence: any BookmarkPersistence) {
    self.persistence = persistence
    reload()
  }

  func contains(_ repository: Repository) -> Bool {
    repositories.contains { $0.id == repository.id }
  }

  func reload() {
    do {
      var seen = Set<Repository.ID>()
      repositories = try persistence.load().filter { seen.insert($0.id).inserted }
      isLoaded = true
      errorMessage = nil
    } catch {
      isLoaded = false
      errorMessage = "ブックマークを読み込めませんでした。\n\(error.localizedDescription)"
    }
  }

  func toggle(_ repository: Repository) {
    // Never overwrite unreadable saved data with a new, incomplete collection.
    guard isLoaded else { return }
    var updated = repositories
    if contains(repository) {
      updated.removeAll { $0.id == repository.id }
    } else {
      updated.append(repository)
    }
    do {
      try persistence.save(updated)
      repositories = updated
      errorMessage = nil
    } catch {
      // Publish only successfully persisted changes, so every screen agrees.
      errorMessage = "ブックマークを保存できませんでした。変更は反映されていません。\n\(error.localizedDescription)"
    }
  }

  func dismissError() {
    errorMessage = nil
  }
}
