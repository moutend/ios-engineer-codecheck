import SwiftUI

struct RepositoryTabs: View {
  @State private var search: RepositorySearch
  @State private var bookmarks: BookmarkStore
  @State private var history: SearchHistory
  @State private var selectedTab = Tab.search

  private enum Tab { case search, bookmarks }

  init(
    service: any RepositorySearching = GitHubRepositoryService(),
    persistence: any BookmarkPersistence = FileBookmarkPersistence(),
    historyDefaults: UserDefaults? = .standard
  ) {
    _history = State(initialValue: SearchHistory(defaults: historyDefaults))
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
        RepositorySearchScreen(search: search, history: history)
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
  let history: SearchHistory
  @State private var query = ""

  private var emptyMessage: String {
    switch search.phase {
    case .idle: "GitHubのリポジトリを検索できます"
    case .loading: ""
    case .loaded: "該当するリポジトリはありません"
    case .failed(let message): "検索に失敗しました。\n\(message)"
    }
  }

  var body: some View {
    RepositoryList(repositories: search.repositories, emptyMessage: emptyMessage) {
      paginationFooter
    }
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "GitHubのリポジトリを検索"
    )
    .searchSuggestions {
      let suggestions = history.suggestions(for: query)
      if search.phase == .idle && !suggestions.isEmpty {
        Section("検索履歴") {
          ForEach(suggestions, id: \.self) { term in
            Text(term)
              .searchCompletion(term)
          }
          Button("検索履歴を消去", role: .destructive) { history.clear() }
        }
      }
    }
    .onSubmit(of: .search) {
      history.record(query)
      search.submit(query)
    }
    .safeAreaInset(edge: .top) {
      VStack(alignment: .leading, spacing: 8) {
        Menu {
          Picker("並び順", selection: Binding(get: { search.sort }, set: { search.changeSort($0) })) {
            ForEach(RepositorySort.allCases, id: \.self) { sort in
              Text(sort.title).tag(sort)
            }
          }
        } label: {
          Label("並び順: \(search.sort.title)", systemImage: "arrow.up.arrow.down")
            .multilineTextAlignment(.leading)
        }
        .accessibilityIdentifier("searchSortMenu")
        if let count = search.totalCount {
          Text("検索結果: \(count.formatted())件")
            .accessibilityIdentifier("searchResultCount")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(.bar)
    }
    .overlay {
      if search.phase == .loading {
        ProgressView("検索中")
          .accessibilityIdentifier("initialSearchLoading")
      }
    }
    .onChange(of: query) { _, value in
      search.inputChanged(value)
    }
  }

  @ViewBuilder
  private var paginationFooter: some View {
    if search.phase == .loaded {
      VStack(spacing: 8) {
        switch search.additionalPhase {
        case .loading:
          ProgressView()
            .accessibilityLabel("読み込み中")
            .accessibilityIdentifier("additionalSearchLoading")
          Text("読み込み中")
            .accessibilityHidden(true)
        case .failed(let message):
          Text("追加読み込みに失敗しました。\n\(message)")
          Button("再試行") { search.loadMore() }
        case .idle:
          if search.hasMore {
            Button("もっと読み込む") { search.loadMore() }
          } else if search.hasReachedDisplayLimit {
            Image(systemName: "exclamationmark.triangle")
              .accessibilityHidden(true)
            Text("表示できるのは上位1,000件までです。別のキーワードで検索をお試しください。")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("searchDisplayLimitNotice")
          }
        }
      }
      .padding()
    }
  }

}

#if DEBUG
  #Preview {
    RepositoryTabs(
      service: PreviewRepositoryService(), persistence: PreviewBookmarkPersistence(),
      historyDefaults: nil)
  }
#endif
