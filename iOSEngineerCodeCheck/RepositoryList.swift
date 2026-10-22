import SwiftUI

struct RepositoryList<Footer: View>: View {
  let repositories: [Repository]
  let emptyMessage: String
  private let footer: Footer

  init(repositories: [Repository], emptyMessage: String, @ViewBuilder footer: () -> Footer) {
    self.repositories = repositories
    self.emptyMessage = emptyMessage
    self.footer = footer()
  }

  init(repositories: [Repository], emptyMessage: String) where Footer == EmptyView {
    self.init(repositories: repositories, emptyMessage: emptyMessage) { EmptyView() }
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(repositories) { repository in
          NavigationLink(value: repository) {
            RepositoryRow(repository: repository)
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Divider()
        }
        footer
      }
    }
    .navigationDestination(for: Repository.self) { repository in
      RepositoryDetail(repository: repository)
    }
    .overlay {
      if repositories.isEmpty {
        Text(emptyMessage)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding()
      }
    }
  }
}

private struct RepositoryRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let repository: Repository

  var body: some View {
    ViewThatFits(in: .horizontal) {
      if !dynamicTypeSize.isAccessibilitySize {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          name
          Spacer(minLength: 0)
          language
        }
        .fixedSize(horizontal: true, vertical: false)
      }
      VStack(alignment: .leading, spacing: 8) {
        name
        language
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var name: some View {
    Text(repository.fullName)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("repositoryName")
  }

  private var language: some View {
    Text(repository.language ?? "")
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("repositoryLanguage")
  }
}
