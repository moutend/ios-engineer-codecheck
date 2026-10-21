# Issue #1: 状態と責務の整理

## 変更理由と構成

以前は検索結果と保存済み一覧の双方が `marked` を持ち、検索結果の `onChange` で永続化していた。Bookmark側での変更は保存につながらず、詳細画面は削除され得る配列要素へのBindingに依存していた。

- `Repository`: APIと保存データの値。ブックマーク状態を含めない。表示IDは既存保存形式と同じ `fullName` とし、カウント変更で行のIDが変わらないようにした。リポジトリの改名・移管を同一視するGitHub数値IDへの移行は対象外。
- `RepositorySearch`: 検索結果と idle / loading / loaded / failed をMainActor上で所有する。空白入力・クリア時はキャンセルし、新規検索で古い結果を無効化する。キャンセルに従わないサービスでもリクエストIDで古い結果を除外する。
- `GitHubRepositoryService`: URL生成、HTTPステータスの検証、JSONのデコードのみを行う。URLSessionを注入でき、通信エラーは検索状態に伝播する。
- `BookmarkStore`: 両タブが共有する唯一のブックマーク状態。追加・削除は保存成功後に公開する。保存失敗は一覧を維持してアラート表示する。読み込み失敗時は編集を無効にし、Bookmarkタブから再試行できる。
- `FileBookmarkPersistence`: JSONをApplication Supportの `bookmarks.json` にatomic書き込みする。書き込みエラーを報告できない `UserDefaults.set` から分離した。新ファイルが存在しない場合のみ、従来のUserDefaultsキー `data` を読み込み移行する。旧 `marked` は無視する。旧データは成功・失敗どちらでも残し、空の新ファイルがあれば旧データを復活させない。破損・読み取り失敗を「空」と扱わない。
- `RepositoryTabs` / `RepositoryList` / `RepositoryDetail`: 表示と入力の受付を担当する。値ベースのNavigationLinkにより、元の行を削除しても詳細に留まり、共有ストアを参照してAdd/Removeを切り替える。言語の説明は計算値とし、重複するStateを廃止した。

検索入力はプレースホルダーと実値を分けた。検索失敗、検索結果0件、未検索を区別し、アバターURL不正時は代替画像を表示する。型消去のAnyViewや意味の不明瞭なmode/flag、強制アンラップは除去した。

## 自動テスト

Xcodeで `iOSEngineerCodeCheck` schemeを選び、iOS 26.6以上のSimulatorを指定して **Product > Test** を実行する。コマンド例（端末名はインストール済みのものに変更可能）:

```sh
xcodebuild test \
  -project iOSEngineerCodeCheck.xcodeproj \
  -scheme iOSEngineerCodeCheck \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO
```

- 単体テストはSwift Testingを使用。検索の成功・0件・失敗・再試行・キャンセル・逆順完了、共有ブックマークの追加削除・保存失敗・読み込み失敗・重複、実ファイルへの保存と移行を検証する。
- 通信テストはephemeral URLSessionとURLProtocolスタブでGitHub接続を遮断し、日本語・`+`・`&`・`#`を含むクエリ、snake_case、null言語、HTTP 403/429/500、不正JSONを確認する。
- 非同期順序はContinuationで制御する。sleepや実際のネットワーク速度に依存しない。
- 永続化テストはUUID付きの一時ディレクトリ・独立UserDefaults suiteを使用する。通常の保存領域は使用しない。
- UIテストはDebug専用の起動環境変数 `BOOKMARK_UI_TEST_ID` で固定検索サービスとテストごとの一時保存領域を注入する。アバターもネットワークにアクセスしない。追加、Bookmark詳細から削除しても画面に留まること、再追加、両タブの整合、再起動後の追加・削除結果を検証する。
- プレビューと単体テスト用ホストも実サービス・個人の保存状態から分離する。Releaseではテスト用の起動分岐を含めない。

## 意図した制約

ブックマークは保存時点のリポジトリ情報を保持し、検索だけで保存情報を更新しない。保存処理は小さなローカル一覧を想定した同期処理であり、大規模化・複数プロセス間の同期は扱わない。実際のGitHubサービス稼働状況や実機での使い勝手は、この自動テストの保証範囲外。

## 今回の検証結果

2026-10-21、Xcode 27.1 / iPhone 18 Pro Simulator（iOS 27.0）で確認:

- 全テスト: 18件成功、失敗・スキップなし（単体17件とUI 1件。HTTPステータスはパラメーター化）。
- Release Simulatorビルド: 成功。
- `git diff --check`: 成功。
