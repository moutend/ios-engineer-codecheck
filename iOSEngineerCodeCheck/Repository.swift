import Foundation

struct Repository: Hashable, Identifiable, Codable, Sendable {
  // Retains the identity used by existing bookmarks, independent of changing counts.
  var id: String { fullName }

  let fullName: String
  let language: String?
  let stargazersCount: Int
  let watchersCount: Int
  let forksCount: Int
  let openIssuesCount: Int
  let owner: Owner

  var avatarURL: URL? {
    guard let url = URL(string: owner.avatarUrl),
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil
    else { return nil }
    return url
  }

  struct Owner: Hashable, Codable, Sendable {
    let avatarUrl: String
  }
}
