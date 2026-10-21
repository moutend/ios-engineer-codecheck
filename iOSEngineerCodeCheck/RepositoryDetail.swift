import SwiftUI

struct RepositoryDetail: View {
    @Environment(BookmarkStore.self) private var bookmarks
    let repository: Repository

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                RepositoryAvatar(url: repository.avatarURL)
                Text(repository.fullName)
                    .font(.title)
                    .multilineTextAlignment(.center)
                HStack(alignment: .top) {
                    Text(repository.language.map { "Written in \($0)" } ?? "")
                        .font(.headline)
                    Spacer(minLength: 24)
                    VStack(alignment: .trailing, spacing: 16) {
                        Text("\(repository.stargazersCount) stars")
                        Text("\(repository.watchersCount) watchers")
                        Text("\(repository.forksCount) forks")
                        Text("\(repository.openIssuesCount) open issues")
                    }
                    .font(.subheadline)
                }
                Button(bookmarks.contains(repository) ? "Remove from Bookmark" : "Add to Bookmark") {
                    bookmarks.toggle(repository)
                }
                .buttonStyle(.borderedProminent)
                .tint(bookmarks.contains(repository) ? .red : .blue)
                .disabled(!bookmarks.isLoaded)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RepositoryAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else if url == nil || phase.error != nil {
                Image(systemName: "person.crop.square")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(48)
            } else {
                ProgressView()
            }
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
    }
}
