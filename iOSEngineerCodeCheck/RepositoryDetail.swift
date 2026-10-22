import SwiftUI

struct RepositoryDetail: View {
  @Environment(BookmarkStore.self) private var bookmarks
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let repository: Repository

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        RepositoryAvatar(url: repository.avatarURL)
        Text(repository.fullName)
          .font(.title)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        ViewThatFits(in: .horizontal) {
          if !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 24) {
              language
              statistics(alignment: .trailing)
            }
            .fixedSize(horizontal: true, vertical: false)
          }
          VStack(alignment: .leading, spacing: 20) {
            language
            statistics(alignment: .leading)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

  private var language: some View {
    Text(repository.language.map { "Written in \($0)" } ?? "")
      .font(.headline)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("detailLanguage")
  }

  private func statistics(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 16) {
      Text("\(repository.stargazersCount) stars")
        .accessibilityIdentifier("detailStars")
      Text("\(repository.watchersCount) watchers")
      Text("\(repository.forksCount) forks")
      Text("\(repository.openIssuesCount) open issues")
    }
    .font(.subheadline)
    .fixedSize(horizontal: false, vertical: true)
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
