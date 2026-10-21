import SwiftUI

struct RepositoryList: View {
    let repositories: [Repository]
    let emptyMessage: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(repositories) { repository in
                    NavigationLink(value: repository) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(repository.fullName)
                            Spacer(minLength: 16)
                            Text(repository.language ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                }
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
