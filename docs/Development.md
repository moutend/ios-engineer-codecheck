# 開発手順

開発者がローカル環境で本プロジェクトを変更し、ビルド・動作確認・テストを行うための手順です。

## システム要件

- Xcode 26.6以上
- macOS 26.2以上

補足

- シミュレーターでの実行およびテストには、XcodeからiOS Simulatorランタイムをインストールしてください。
- GitHub Actionsでは、[iOS CIワークフロー](../.github/workflows/ios-ci.yml)がmacOS runner（`macos-26`）上でXcode 26.6を使用します。Pull Request作成・更新時と手動実行時に、iPhone 17（iOS 26.5）のシミュレーターでビルドと全単体・UIテストを実行します。

CLIで使用されるXcodeは、次のコマンドで確認できます。

```shell
xcode-select --print-path
xcodebuild -version
```

複数のXcodeをインストールしている場合

- Xcodeの Settings > Locations > Command Line Tools でXcode 26.6以上を選択してください。初回起動時に求められる追加コンポーネントのインストールも完了させてください。
- CLIから切り替える場合は以下のコマンドを実行してください。

```shell
# 例: Xcode26.appが/Applicationsに配置されている場合
sudo xcode-select --switch /Applications/Xcode26.app/Contents/Developer
```

## 外部依存とシークレット

本プロジェクトの外部依存は、ビルド時に実行するSwiftLintだけです。`SwiftLintPlugins`（0.65.1）の `SwiftLintBuildToolPlugin` をSwift Package Manager経由で利用します。Xcodeが取得するため、HomebrewなどでSwiftLintを別途インストールする必要はありません。初回の依存取得にはネットワーク接続が必要です。

シミュレーターでの実行やテストに、開発者が環境変数やシークレット、GitHubのアクセストークンを設定する必要はありません。UIテスト用の環境変数はテストコードが自動で設定します。通常のアプリでGitHub検索を利用するときはネットワーク接続が必要ですが、自動テストはスタブを使用します。

今後の新機能追加でも、外部依存は可能な限り導入せず、標準のSDKやフレームワークを優先する方針です。

## セットアップ

### Cloneから最初のビルドまで

以下のコマンドを実行してください。

```shell
git clone https://github.com/moutend/ios-engineer-codecheck.git
cd ios-engineer-codecheck
open iOSEngineerCodeCheck.xcodeproj
```

その後、Xcodeで以下を確認したら、`Command+B`（Product > Build）だけでアプリをビルドできます。事前のコード生成や設定ファイルの作成は不要です。

1. Swift Package Managerによる依存の取得が完了するまで待ちます。
2. Schemeに `iOSEngineerCodeCheck`、実行先にインストール済みのiPhoneシミュレーターを選びます。
3. `Command+B`を押します。初回にSwiftLintのプラグイン実行の確認が表示された場合は、対象が `SwiftLintBuildToolPlugin` であることを確認して許可します。

## ビルドとシミュレーターでの実行手順

### XcodeのGUIからの実行

1. `iOSEngineerCodeCheck.xcodeproj` を開きます。
2. Schemeに `iOSEngineerCodeCheck`、実行先にiPhoneシミュレーターを選びます。実行先がなければ Settings > Components でiOSランタイムを取得し、Window > Devices and Simulators からシミュレーターを追加します。
3. ビルドのみなら `Command+B`（Product > Build）を実行します。
4. アプリを起動するなら`Command+R`（Product > Run）を実行します。ビルド後、シミュレーターが起動してアプリがインストール・実行されます。
5. 停止するには `Command+.`（Product > Stop）を実行します。

ビルドに失敗した場合はIssue Navigator（`Command+5`）でエラーやSwiftLintの指摘を確認してください。

### CLIからの実行

以降のコマンドはリポジトリのルートで実行します。まず利用可能なシミュレーターを確認します。

```shell
xcrun simctl list devices available
xcodebuild -project iOSEngineerCodeCheck.xcodeproj \
  -scheme iOSEngineerCodeCheck -showdestinations
```

一覧から使用するiPhoneシミュレーターのUDIDを選び、以下の値を置き換えます。これはコマンド例で使うシェル変数であり、アプリ用の環境設定ではありません。同じターミナルで以降のコマンドを実行してください。

```shell
SIMULATOR_ID='ここを使用するシミュレーターのUDIDに置き換える'
```

Debug構成でビルドします。生成物は一時ディレクトリに保存します。

```shell
BUILD_DIR=$(mktemp -d /tmp/ios-engineer-codecheck-build.XXXXXX)
xcodebuild build \
  -project iOSEngineerCodeCheck.xcodeproj \
  -scheme iOSEngineerCodeCheck \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO
```

初回にプラグインの信頼確認で失敗する場合は、Xcodeでプロジェクトを開き、SwiftLintプラグインの実行を許可してから再実行してください。

ビルド成功後、同じシミュレーターを起動してアプリをインストール・実行します。

```shell
open -a Simulator
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" \
  "$BUILD_DIR/Build/Products/Debug-iphonesimulator/iOSEngineerCodeCheck.app"
xcrun simctl launch "$SIMULATOR_ID" jp.yumemi.iOSEngineerCodeCheck
```

`bootstatus -b` は停止中なら起動し、起動完了まで待ちます。`xcodebuild build` だけではアプリは起動しません。

## テストの実行

共有Scheme `iOSEngineerCodeCheck` には以下の両ターゲットが含まれます。

| ターゲット | 内容 |
| --- | --- |
| `iOSEngineerCodeCheckTests` | Swift Testingによる単体テスト |
| `iOSEngineerCodeCheckUITests` | XCTestによるUIテスト |

### XcodeのGUIからの実行

1. Schemeに `iOSEngineerCodeCheck`、実行先にiPhoneシミュレーターを選びます。
2. `Command+U`（`Product > Test`）で全テストを実行します。
3. Test Navigator（`Command+6`）で結果を確認します。

特定のテストだけを実行する場合は、Test Navigatorで対象のターゲット・スイート／クラス・テストメソッドを展開し、その項目の実行ボタンを押します。ソースコード内のテスト宣言の左側にある実行ボタンからも、個別のテストを実行できます。

### CLIからの実行

前述の `SIMULATOR_ID` を設定したターミナルで、全テストを実行します。`test` は必要なビルドも行うので、事前の `build` は不要です。

```shell
xcodebuild test \
  -project iOSEngineerCodeCheck.xcodeproj \
  -scheme iOSEngineerCodeCheck \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO
```

特定のテストに絞る場合は、`-only-testing:` を追加します。たとえば、ブックマークの単体テストスイートだけを実行するには次のように指定します。

```shell
xcodebuild test \
  -project iOSEngineerCodeCheck.xcodeproj \
  -scheme iOSEngineerCodeCheck \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:iOSEngineerCodeCheckTests/BookmarkStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

実行したい範囲に応じて、上記の `-only-testing:` 引数を次のいずれかに置き換えます。

| 実行範囲 | 引数 |
| --- | --- |
| 単体テスト全体 | `-only-testing:iOSEngineerCodeCheckTests` |
| UIテスト全体 | `-only-testing:iOSEngineerCodeCheckUITests` |
| 単体テスト1件 | `'-only-testing:iOSEngineerCodeCheckTests/BookmarkStoreTests/addRemoveAndRelaunchShareOneSourceOfTruth()'` |
| UIテスト1件 | `-only-testing:iOSEngineerCodeCheckUITests/IOSEngineerCodeCheckUITests/testBookmarkRemovalKeepsDetailAndSynchronizesTabsAndRelaunch` |

Swift Testingのメソッド名に含まれる括弧は、シェルで解釈されないよう引数全体を引用符で囲みます。複数の対象を実行する場合は `-only-testing:` を複数指定できます。

## 実機での動作確認と署名

実機でアプリの動作を確認する場合は、Xcodeのアプリターゲットの Signing & Capabilities で自分のTeamを選び、必要に応じてBundle Identifierを変更してください。

- 実機を実行先に選択して`Command+R`で実行します。
- CLIで実機向けにビルドする際には、上記のシミュレーター用の署名無効化設定は使用しません。
- 個人用の署名設定変更は、共有する変更に混ぜないでください。

## 開発の流れ

1. 作業ブランチを作ります。
2. コードに変更を加えます。その際、実装の揺れを抑制するため`scripts/lint.sh modified`を実行してください。
3. ビルド及びテストが成功することを確認します。実機での動作検証は必須ではありませんが、可能ならば実施します。
4. PRを作成します。本プロジェクトはコーディング試験を目的とした簡易的なものであり、現状はCIが成功していなくてもmainブランチへのマージが可能となっています。
5. レビューの結果、approveされたらmainブランチへマージします。本プロジェクトはコーディング試験を目的とした簡易的なプロジェクトのため、ご自身で再度PRの内容を確認した上で、問題なければmainブランチへマージいただいて構いません。
