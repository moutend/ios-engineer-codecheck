# iOS CI

`.github/workflows/ios-ci.yml` は、PR作成・再オープン・追加pushと手動実行で、同一のビルド・テスト処理を実行します。パスによる除外はありません。

- GitHub-hosted `macos-26`、Xcode **26.6**（明示指定・バージョン確認）
- iPhone 17 / iOS 26.5 Simulator
- Xcode 26.6のSDKはiOS 26.5のため、プロジェクトにSimulator限定の最小iOS 26.5を設定（`IPHONEOS_DEPLOYMENT_TARGET[sdk=iphonesimulator*]`）。実機・配布用の26.6は維持します。コマンドラインの上書きのみではXcodeの実行先解決に反映されませんでした
- `build-for-testing` でアプリとテストバンドルをビルド
- `test-without-building` で共有schemeに登録されたユニットテスト・UIテストをすべて実行（除外・リトライなし）
- 実行ログはActionsのジョブログで確認。失敗時のみ、生成されていれば `Tests.xcresult` をArtifactsに14日間保存（ビルド失敗などで未生成の場合はアップロードなし）
- `iOS CI required` は、上記ジョブが成功した場合のみ成功。失敗・キャンセル・スキップを成功扱いしません。

PRではGitHubのマージ予定コミットを検証します。手動実行では選択したブランチのコミットを検証するため、mainとの統合後の結果はPRでも確認してください。

## PR作成前の実行

このワークフローがデフォルトブランチに入った後、Actions → **iOS CI** → **Run workflow** のブランチ欄で対象ブランチを選択します。対象ブランチにもワークフローが必要です。ローカルの変更はコミット・pushしてから実行してください。

```sh
gh workflow run ios-ci.yml --ref your-branch
gh run list --workflow ios-ci.yml --branch your-branch
gh run watch RUN_ID --exit-status
```

## マージ条件の設定（管理者向け）

2026-10-22時点、この非公開リポジトリでは保護設定APIがHTTP 403（GitHub Proへのアップグレードが必要）を返しました。ユーザーの方針によりプラン・公開範囲は変更せず、設定手順を残しています。**ワークフローを追加するだけではマージは制限されません。**

利用可能なプランへ移行後、Settings → Rules → Rulesets → New branch ruleset で次を設定してください。

1. 名前を `Require iOS CI`、Enforcement statusを **Active** にする。
2. Target branchesをデフォルトブランチ（`main`）にする。他のマージ先も保護する場合は追加する。
3. Bypass listは空にする（管理者も適用対象）。
4. **Require a pull request before merging** を有効にする。
5. **Require status checks to pass** を有効にし、`iOS CI required`（GitHub Actions）を追加する。一覧にない場合は先にこのワークフローを一度実行する。
6. **Require branches to be up to date before merging** を有効にして保存する。

既存ルールがある場合は削除せず、必要な必須チェックを追加してください。導入後は成功PRがマージ可能になり、ビルドまたはテスト失敗PRがブロックされることを確認してください。検証用PRはマージせずCloseします。

runnerのソフトウェア一覧: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
