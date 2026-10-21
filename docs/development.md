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
AI実行環境のsandboxがCoreSimulatorやxcresulttoolの管理キャッシュを拒否する場合、同じコマンドを通常のローカル権限で実行できるよう許可が必要。

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
ログ内の `error` という文字列だけでは判定せず、終了コードとxcresultを使う。
このXcodeでは成功時にもSDKビルド番号に関する内部診断 `invalidDigitCount` が出ることを確認している。
端末には工程とログの場所・結果を表示する。進行を見るには該当ログを `tail -f` する。

テスト結果は `test-unit.xcresult` / `test-ui.xcresult`。成功時は `*-results.json` に解析結果も保存する。
テスト0件、スキップ、失敗、不正な結果は成功にしない（存在しない `--only` も検出する）。
通常は `-collect-test-diagnostics never` とし、失敗時の重いSimulator全体の診断収集を省く。
アサーション、生ログ、xcresultは引き続き残る。これだけで分からないSimulator起因の障害は
`./scripts/dev test-unit --only <Suite> --diagnostics` などで再実行する。
`--diagnostics` はテストと統合チェックで利用でき、Xcodeの詳細診断を失敗時に収集する（数分以上かかる場合がある）。

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
- 初回整形後 `check-all`: 160.349秒。単体22件・UI4件成功、失敗/スキップ0、Releaseビルド成功。
- 初回整形は6ファイルの空白・改行のみ（空白を除いた文字列が一致）。2回目のformat後も差分が完全一致し、冪等性を確認。
- 実テスト失敗時、Xcodeがtimeout=600秒の `simctl diagnose` を起動することを確認した。
  その診断収集は途中で止め、詳細診断を明示指定に変更。変更後の失敗テストは16.901秒で無介入の非ゼロ終了を確認した。

## Issue #3との対応

Issue本文の4要件（環境・制約の文書化、クリーン状態からの再現、機械判定と診断、端末固有情報への非依存）を、以下で実現する。
今回の詳細要件との対応も併記する。

| 詳細要件 | 実装・確認方法 |
| --- | --- |
| 1. 環境・制約・手順 | この文書へREADMEと短いAGENTS.mdから誘導。コンパイラ版・言語モード・最低OSを区別 |
| 2. 事前診断 | doctor、Xcodeビルド固定、SDK/端末の適合確認、環境不足で非ゼロ |
| 3. 共通入口 | scripts/dev、既存共有scheme、署名無効、個人の絶対パス/UUIDを設定に含めない |
| 4. 短い/全体検証 | check-fast / check-all、--only、通常キャッシュ再利用、工程ごとの実測 |
| 5. formatter | Xcode同梱swift-format、設定管理、非破壊lint、初回整形を別コミット、冪等性確認 |
| 6. 静的チェック | Swift 6コンパイラ診断と警告エラー化。追加linter/警告抑制なし |
| 7. 既存回帰テスト | 単体22件/UI4件を接続。テストの削除・無効化・アサーション弱体化なし |
| 8. クリーン検証/安全性 | --fresh、専用出力とgitignore、実行ごとの一意なディレクトリ、同時実行ロック |
| 9. 結果と診断 | JSONサマリー、終了コード、生ログ、xcresult、未実行と成功の区別 |
| 10. 基盤自体の検証 | スタブ12件と破棄可能コピーでの実ツール失敗検証を区別。元のソースは変更しない |

## 実ツールでの失敗検証

追跡ファイルを `.dev/failure-probes-319dtvm4/disposable checkout` にコピーし、そのコピーだけを変更した。
元の作業コピー・個人のデータ・Simulator runtimeには変更を加えていない。
コピー側の変更も各検証のfinallyで戻した。`probes.json` と工程別ログ、コピー側の `.dev/runs` に結果を保持している。

| 仕込んだ条件 | コマンド | 終了コード | 実測秒 |
| --- | --- | ---: | ---: |
| 存在しないDEVELOPER_DIR | doctor | 1 | 0.436 |
| 統合チェックに不正な--only | check-all --only Suite | 2 | 0.031 |
| コピーのSwiftに書式違反を追加 | format-check | 1 | 0.378 |
| コピーに#errorを追加 | build | 65 | 1.455 |
| 未使用ローカル変数によるコンパイラ警告 | static-check | 65 | 3.698 |
| コピーに失敗するテストを追加 | test-unit --only HarnessFailureProbe | 65 | 16.901 |
| 存在しないsuite | test-unit --only NoSuchSuite | 1 | 16.747 |

書式チェック前後で違反を仕込んだソースのバイト列が一致。
失敗xcresultは `xcresulttool get test-results summary` で1件失敗とアサーション内容を読み取れた。
スタブ12件はこれらとは別に、未実行工程、標準出力/標準エラーの保存、終了コード、端末選択・上書き、
スキップ/0件の拒否、重複しない出力、キャッシュ保全、同時実行拒否、symlink出力拒否も検査する。

クリーンなチェックアウトを再現する例（未コミット変更は含まれない）:

```sh
validation_dir="$(mktemp -d)"
git clone --no-hardlinks . "$validation_dir/checkout"
(cd "$validation_dir/checkout" && ./scripts/dev check-all --fresh)
git -C "$validation_dir/checkout" status --short
```

結果を保存した後で、この用途に作ったコピーだけを削除する。
今回の検証コピー `.dev/clean-checkout-*` / `.dev/failure-probes-*` も、実行終了後に個別に削除できる。

## 最終検証（2026-10-21）

実装コミット `040bce6` をローカルcloneした、未コミット変更とDerivedDataのないチェックアウトで
`./scripts/dev check-all --fresh` を実行した。終了コード0、単体22件・UI4件成功、失敗/スキップ0。
開始前後の全追跡ファイルのSHA-256が一致し、終了後の `git status --porcelain` は空だった。

| クリーンチェックアウトの工程 | 秒 |
| --- | ---: |
| doctor | 0.423 |
| format-check | 0.032 |
| script-test（スタブ12件） | 6.672 |
| static-check（Debugビルド） | 4.669 |
| test-unit（22件） | 16.719 |
| test-ui（4件） | 125.840 |
| build-release | 4.317 |
| **check-all --fresh 全体** | **158.674** |

証跡は `.dev/clean-checkout-i1c5is4h/verification.json` と、その `checkout/.dev/runs/20261021-210847-check-all-dwjxlvvy/` に保存した。
これらの日時や一時ディレクトリ名は今回の証跡の識別子であり、実行設定ではない。

通常キャッシュを再利用した最終実装の `check-fast` は **22.770秒**（書式0.032秒、
スクリプト6.680秒、静的チェック0.805秒、単体14.918秒、doctor0.333秒）。
`test-unit --only RepositorySearchTests` は **15.527秒**で検索suiteの9件が成功した。
証跡は `.dev/runs/20261021-211153-check-fast-b7t7lygx/` と
`.dev/runs/20261021-211216-test-unit-0w91m2o6/`。

小さな修正の反復にはcheck-fast、UI・保存/検索フロー変更の完了時やコミット前の全体確認にはcheck-all、
ツールチェーン更新・初回セットアップ・キャッシュの疑いがあるときはcheck-all --freshを使う。
所要時間はこの端末・runtimeの実測であり、速度目標や他環境での保証ではない。
最終差分は全Swiftファイルで空白以外の文字が開始コミットと一致しており、アプリ仕様・UI・保存形式や既存の検証内容を変更していない。
