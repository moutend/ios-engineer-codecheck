import Foundation

@MainActor
protocol BookmarkPersistence {
    func load() throws -> [Repository]
    func save(_ repositories: [Repository]) throws
}

/// Atomic file writes can report storage failures; UserDefaults.set cannot.
@MainActor
struct FileBookmarkPersistence: BookmarkPersistence {
    let fileURL: URL
    let legacyDefaults: UserDefaults?

    init(
        fileURL: URL = URL.applicationSupportDirectory.appending(path: "bookmarks.json"),
        legacyDefaults: UserDefaults? = .standard
    ) {
        self.fileURL = fileURL
        self.legacyDefaults = legacyDefaults
    }

    func load() throws -> [Repository] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            guard let legacyData = legacyDefaults?.data(forKey: "data") else { return [] }
            let repositories = try JSONDecoder().decode([Repository].self, from: legacyData)
            // Keep the original data intact, including when migration fails.
            try save(repositories)
            return repositories
        }
        return try JSONDecoder().decode([Repository].self, from: data)
    }

    func save(_ repositories: [Repository]) throws {
        let data = try JSONEncoder().encode(repositories)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
