import SwiftUI

struct RepositoryTabs: View {
    @State private var search: RepositorySearch
    @State private var bookmarks: BookmarkStore
    @State private var selectedTab = Tab.search

    private enum Tab { case search, bookmarks }

    init(
        service: any RepositorySearching = GitHubRepositoryService(),
        persistence: any BookmarkPersistence = FileBookmarkPersistence()
    ) {
        _search = State(initialValue: RepositorySearch(service: service))
        _bookmarks = State(initialValue: BookmarkStore(persistence: persistence))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RepositoryList(
                    repositories: bookmarks.repositories,
                    emptyMessage: bookmarks.isLoaded
                        ? "ブックマークはまだありません" : "ブックマークを読み込めませんでした"
                )
                .navigationTitle("Bookmarks")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    if !bookmarks.isLoaded {
                        Button("ブックマークの読み込みを再試行", action: bookmarks.reload)
                            .padding()
                    }
                }
            }
            .tabItem { Label("Bookmark", systemImage: "bookmark.fill") }
            .tag(Tab.bookmarks)

            NavigationStack {
                RepositorySearchScreen(search: search)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass.circle.fill") }
            .tag(Tab.search)
        }
        .environment(bookmarks)
        .alert(
            "ブックマークのエラー",
            isPresented: Binding(
                get: { bookmarks.errorMessage != nil },
                set: { if !$0 { bookmarks.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel, action: bookmarks.dismissError)
        } message: {
            Text(bookmarks.errorMessage ?? "")
        }
    }
}

private struct RepositorySearchScreen: View {
    let search: RepositorySearch
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var emptyMessage: String {
        switch search.phase {
        case .idle: "GitHubのリポジトリを検索できます"
        case .loading: ""
        case .loaded: "該当するリポジトリはありません"
        case .failed(let message): "検索に失敗しました。\n\(message)"
        }
    }

    var body: some View {
        RepositoryList(repositories: search.repositories, emptyMessage: emptyMessage)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                TextField("GitHubのリポジトリを検索", text: $query)
                    .accessibilityIdentifier("repositorySearchField")
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { search.submit(query) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .overlay {
                if search.phase == .loading { ProgressView() }
            }
            .onChange(of: query) { _, value in
                search.inputChanged(value)
            }
            .onDisappear { isSearchFocused = false }
    }
}

#if DEBUG
#Preview {
    RepositoryTabs(service: PreviewRepositoryService(), persistence: PreviewBookmarkPersistence())
}
#endif
