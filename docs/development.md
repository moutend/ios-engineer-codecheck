# ローカル開発・検証

## 環境とセットアップ

検証基盤は Python 3.9以上の標準ライブラリと Xcode のコマンドだけを使う。
Homebrew、外部パッケージ、GitHubトークン、個人の署名アカウントは不要。

再現用のツールチェーンは `.dev-tools.json` の Xcode 27.1 (27A9275)。
同梱の Swift コンパイラは 6.4、プロジェクトの **Swift言語モードは6.0**。
アプリの最低OSは project.pbxproj の iOS 26.6であり、Xcodeやruntimeの検証済み版とは別。
他のXcodeでの互換性は未検証。doctorは書式と結果解析の再現性のため指定ビルドとの一致を要求する。

1. 指定Xcodeをインストールし、初回起動のライセンス・追加コンポーネントのセットアップを完了する。
2. Xcode Settings > Componentsで iOS 27.0 Simulator runtimeをインストールし、Devices and SimulatorsでiPhoneを作る。
3. `xcode-select -p` と `python3 --version` を確認する。必要なら `DEVELOPER_DIR` に使用するXcodeの `Contents/Developer` を指定する（端末固有の値はコミットしない）。
4. リポジトリ直下で `./scripts/dev doctor`、続いて `./scripts/dev check-all --fresh` を実行する。

実行先は既定の iOS 27.0上の利用可能なiPhoneから、名前、UUIDの辞書順で選ぶ。
起動中かどうかには依存しない。実行時に名前・OS・UUID・SDK・ツールチェーン・DerivedDataを表示し、ログにも残す。
`DEV_RUNTIME=27.0 ./scripts/dev doctor` でOSを指定できる。
`DEV_SIMULATOR_UDID=<simctlで確認したID> ./scripts/dev test-ui` で端末を明示する場合はOS指定より優先し、利用可能性と最低OSを検査する。
UUIDや個人用絶対パスは設定ファイルへ保存しない。Simulatorはテスト時にXcodeが起動する。
別ツールチェーンを混在させないため `TOOLCHAINS` は未設定にする。テストは並列実行を無効にし、1件の実行上限を180秒にする。
AI実行環境のsandboxがCoreSimulatorを拒否する場合、同じコマンドを通常のローカル権限で実行できるよう許可が必要。

## 共通コマンド

| コマンド（`./scripts/dev` に続ける） | 内容 |
| --- | --- |
| `doctor` | 必須ツール・SDK・runtime・端末を診断。不足やバージョン不一致は非ゼロ |
| `build` / `build-release` | Debug / ReleaseのSimulatorビルド |
| `test-unit` / `test-ui` | 共有schemeの単体 / UIテスト |
| `test-unit --only RepositorySearchTests` | 指定suiteだけ再実行 |
| `test-ui --only iOSEngineerCodeCheckUITests/testBookmarkRemovalKeepsDetailAndSynchronizesTabsAndRelaunch` | 指定UIテストだけ再実行 |
| `format` | Swiftソースを明示的に整形 |
| `format-check` | 書き換えずに書式違反を検出 |
| `static-check` | Debugビルドによるコンパイラ診断 |
| `script-test` | スタブを使った検証スクリプトの自動テスト。Xcode不要 |
| `check-fast` | 書式 → スクリプトテスト → 静的チェック → 単体テスト |
| `check-all` | check-fastの全工程 → UIテスト → Releaseビルド |

ビルド・テスト・統合チェックには `--fresh` を付けられる。その実行専用の新しいDerivedDataを作り、既存キャッシュを削除しない。
通常は `.dev/DerivedData` を再利用する。同一チェックアウトの同時実行はロックで拒否する。
共有schemeをそのまま使い、テスト対象だけを `-only-testing` で選ぶ。統合チェックにテスト絞り込みは指定できない。
全ビルドでSimulator SDK、署名無効、空のDEVELOPMENT_TEAMを明示する。

## 書式と静的チェック

formatterはXcode同梱の `swift-format` のみ。`--version` はこの同梱版では `main` と表示されるため、
版の再現は `.dev-tools.json` のXcodeビルド番号で行う。更新時は書式の差分・冪等性と全テストを再確認する。
`.swift-format` は既存に合わせて4スペース、120桁、条件コンパイル部分の字下げなし。
既存アプリ名の型名変更と数値リテラルへの区切り追加を避けるため、それら2ルールを無効にする。
その他は固定した同梱版の既定値を用いる。対象はアプリ・単体テスト・UIテストの3ディレクトリ。
`lint --strict` の違反は失敗とし、`format` だけがソースを修正する。

追加linterは導入しない。Swift 6モードの型・隔離・Sendable・非推奨APIなどのコンパイラ診断を基盤とし、
書式ルールを別ツールで重複管理しない。Swift/C系コンパイラ警告は共通コマンドでエラー扱い。
Xcodeの付随ツールの警告（例: App Intentsメタデータ抽出）はコンパイラ警告とは別で、生ログを確認する。
競合順序・保存の原子性・タブ同期など、コンパイラで保証できない動作は既存回帰テストで確認する。

## 結果・診断・安全性

実行ごとに `.dev/runs/<日時>-<コマンド>-<ランダム値>/` を新規作成する。
`summary.json` に全体と工程ごとの `passed` / `failed` / `not-run`、終了コード、秒数、環境を保存する。
実行中は `running`。失敗後の工程は未実行であり、全体成功とはしない。
強制終了で `running` が残る場合も成功ではない。不正な引数は出力作成前にusageを表示して終了コード2。
各工程の `.log` にコマンドと標準出力・標準エラーを直接保存し、子プロセスの非ゼロを伝播する。
端末には工程とログの場所・結果を表示する。進行を見るには該当ログを `tail -f` する。

テスト結果は `test-unit.xcresult` / `test-ui.xcresult`。成功時は `*-results.json` に解析結果も保存する。
テスト0件、スキップ、失敗、不正な結果は成功にしない（存在しない `--only` も検出する）。

```sh
open .dev/runs/<run>/test-unit.xcresult
xcrun xcresulttool get test-results summary --path .dev/runs/<run>/test-unit.xcresult
```

まず `summary.json` の失敗工程、次に同名 `.log` のerrorと末尾、テスト失敗ならxcresultの診断・添付を確認する。
既存のコンパイラ／テスト診断で調査できるため、アプリ内の追加診断ログは入れない。
環境変数全体や検索語・保存内容・秘密情報はハーネスで記録しない。ログにはローカルパスが含まれるので、外部共有前に確認する。

生成物は `.dev` 以下だけ（Xcode/Simulator自身のシステム管理領域は除く）。自動削除コマンドは設けない。
終了後に不要な **個別runディレクトリ** または `.dev/DerivedData` だけをFinderで削除できる。
他プロジェクトのDerivedData、ホーム全体、Simulator全体のerase、`git clean/reset` は後片付けに使わない。
単体テストは一時ファイルとUUID付きUserDefaults suiteを使い、作成した保存物をdeferで片付ける。
UIテストはSimulatorアプリのtmp/BookmarkUITests/<UUID>に保存し、再起動検証のため残る。
通常のbookmarks.jsonや旧UserDefaultsを読まない。必要な場合のみこのテスト用ディレクトリを個別に削除する。

## 検証範囲とCI

検索競合・キャンセル・通信失敗・不正レスポンス、保存失敗・旧データ移行は単体テスト、
タブ間同期・再起動・エラー表示・大きな文字のレイアウトは既存UIテストで確認する。
詳しい検証対象は [Issue #1](issue-1.md)、[Issue #2](issue-2.md) を参照。
URLProtocol、固定検索サービス、隔離保存先により、本番GitHub APIや個人データに依存しない。

今回はローカルの短い反復と診断を優先し、クラウドCIは追加しない。
小規模なアプリに対しCIホスト・runtime・署名の別管理を増やさず、共通コマンドの実証を先に行うため。
既存のIssue登録workflowはアプリ検証CIではない。将来のmacOS CIも同じ環境を用意し
`./scripts/dev check-all --fresh` を呼び、終了コードを判定して `.dev/runs` を成果物にできる。
現時点ではpush/PRごとの自動検証はなく、実機、他のOS/端末、GitHub本番の稼働状況、配布用署名は保証しない。

## 導入段階の検証（2026-10-21）

macOS 26.7 (arm64)、Xcode 27.1 (27A9275)、Swift 6.4、SDK 27.1、
iPhone 17 / iOS 27.0、Python 3.14.5で検証。

- 初回 `test-unit --fresh`: 24.217秒、単体22件成功・失敗/スキップ0。
- `script-test`: 6.522秒、スタブによるハーネス契約テスト12件成功。実Xcodeテストとは別。
- 初回整形前 `format-check`: 終了コード1、0.347秒。違反箇所をログに保存し、ソース差分なし。

全体検証・初回整形の結果とIssue #3の対応表は、最終検証後に追記する。
