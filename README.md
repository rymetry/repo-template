# repo-template

汎用リポジトリテンプレート。新規リポジトリの初期設定をワンコマンドで完了します。

## 使い方

### 1. テンプレートからリポジトリを作成

```bash
gh repo create my-new-project --template rymetry/repo-template --public --clone
cd my-new-project
```

### 2. セットアップスクリプトを実行

```bash
bash .github/scripts/setup-repo.sh
```

以下が自動で設定されます:

| 設定 | 内容 |
|------|------|
| **LICENSE** | プレースホルダーを実際の年・名前に置換 |
| **SECURITY.md** | リポジトリ URL を自動設定 |
| **Branch protection** | main に PR 必須 + CI(`check`)の成功必須 + 管理者バイパス |
| **Auto-merge** | 有効化 |
| **Dependabot** | alerts + security updates 有効化 |
| **Secret scanning** | secret scanning + push protection 有効化 |
| **Actions** | Workflow permissions を Read only に設定 |
| **不要機能** | Projects / Discussions / Wiki を OFF |
| **ブランチ自動削除** | マージ後に自動削除 |

### 3. README と AGENTS.md を書き換える

- このファイルをプロジェクト固有の内容に置き換えてください。
- `AGENTS.md` にプロジェクト概要とコマンドを記載してください。

### 4. 依存とプラグインを入れる

```bash
pnpm install
```

[必要なプラグイン](#必要なプラグイン)を、使うエージェントに入れてください。

## AI エージェント

ルール・スキル・hook の正本を 1 か所に置き、各エージェントの設定はそれを参照するだけにしています。

| | ルール | スキル | hook |
|---|---|---|---|
| **正本** | `AGENTS.md` | `.agents/skills/` | `.agents/hooks/` |
| **Claude Code** | `CLAUDE.md` が `AGENTS.md` を取り込む | `.claude/skills/` のシンボリックリンク | `.claude/settings.json` |
| **Codex** | `AGENTS.md` を直接読む | `.agents/skills/` を直接読む | `.codex/hooks.json` |
| **Antigravity** | `AGENTS.md` を直接読む | `.agents/skills/` を直接読む | `.agents/hooks.json` |

- Codex の hook は、プロジェクトを信頼し、`/hooks` で各 hook を承認すると有効になります。
- Antigravity の hook は `jq` が必要です。配線しているのはコマンド実行前の検査だけで、コンフリクトマーカーの検出は Claude Code と Codex で動きます。
- Claude Code 固有の指示は `CLAUDE.md` の取り込み行の下に書きます。

### 必要なプラグイン

| プラグイン | 用途 | 対象 | 導入 |
|---|---|---|---|
| [ponytail](https://github.com/DietrichGebert/ponytail) | 実装とセルフレビューの方針(`ponytail`、`ponytail-review`) | すべてのエージェント | [INSTALL.md](https://github.com/DietrichGebert/ponytail/blob/main/INSTALL.md) |
| pr-review-toolkit | `change-review` スキルの担当エージェント | Claude Code | `/plugin install pr-review-toolkit@claude-plugins-official` |

### スキル

| スキル | 内容 | 出どころ |
|---|---|---|
| `writing-tests` | テストコードの書き方と、生き残りやすい変異の型 | このリポジトリ |
| `change-review` | レビューの担当・報告の基準・指摘の判断 | このリポジトリ |
| `mutator` | 変異テストの導入・実行・結果の読み方 | [`@mizchi/mutator`](https://github.com/mizchi/mutator) の写し |
| `mutation-test-loop` | 生き残った変異をテストで埋める手順 | 同上 |

スキルを足すときは `.agents/skills/<名前>/SKILL.md` を作り、`.claude/skills/<名前>` に `../../.agents/skills/<名前>` へのシンボリックリンクを張ります。

### スキルの更新

`mutator` と `mutation-test-loop` は、パッケージに同梱されたスキルの写しです。

1. Dependabot が月次で `@mizchi/mutator` の更新 PR を出します。
2. `dependabot-auto-merge.yml` が、PR ブランチ上で写しとライセンスを直してコミットします。
3. スキル(エージェントへの指示)の差分を確認し、手動でマージします。この更新は、patch / minor でも自動マージの対象外です。
4. マージ後の `main` の CI が、写しとインストール済みパッケージのずれを検査します。

- 写しを直したコミットには、PR の CI の結果が付きません(ワークフローのトークンによる push は CI を起動しないため)。Dependabot の元のコミットでは写しの検査が失敗しますが、写しを直したコミットが続いていれば問題ありません。
- ブランチ保護で CI を必須にしているため、チェックが付かないこの PR は通常の手順ではマージできません。管理者としてマージするか、手元で空のコミットを push して CI を起動してください。空のコミットのメッセージに `[dependabot skip]` を付けると、Dependabot はその PR のリベースを続けられます(付けないと、以後リベースしなくなります)。
- パッケージに新しいスキルが同梱されると、写しと `.claude/skills/` のリンクも自動で足されます。
- 手元で直すときは `bash .github/scripts/sync-skills.sh` を実行します。

### JS / TS 以外のプロジェクトで外すもの

mutator は Node.js 24 以上と、Vitest・Jest・Bun のいずれかのテストが必要です。使わない場合は次を削除してください。

- `package.json`、`pnpm-lock.yaml`
- `.agents/skills/mutator/`、`.agents/skills/mutation-test-loop/` と、`.claude/skills/` の同名のリンク
- `.github/scripts/sync-skills.sh`
- `.github/dependabot.yml` の npm の設定
- `.github/workflows/ci.yml` の pnpm 以降の手順(`check` というジョブ名は、ブランチ保護の必須チェックなので変えない)
- `.github/workflows/dependabot-auto-merge.yml` の写しを直す 5 つの手順と、承認・マージの条件のうち `@mizchi/mutator` の部分
- `AGENTS.md` の `mutator`・`mutation-test-loop` への言及

## 含まれるファイル

```
AGENTS.md                              # AI エージェント共通のルール(正本)
CLAUDE.md                              # AGENTS.md の取り込み + Claude Code 固有の指示
.agents/
  skills/                              # スキルの正本
    writing-tests/
    change-review/
    mutator/                           # @mizchi/mutator の写し
    mutation-test-loop/                # 同上
  hooks/
    pre-tool-use-policy.sh             # main への force push をブロック
    stop-verify.sh                     # コンフリクトマーカー検出
    pre-tool-use-json-decision.sh      # 判定結果を JSON で返す(Antigravity が使う)
    self-test.sh                       # hook の自己検査
  hooks.json                           # Antigravity の hook 設定
.claude/
  settings.json                        # Claude Code の hook 設定
  skills/                              # .agents/skills/ へのシンボリックリンク
.codex/
  hooks.json                           # Codex の hook 設定
.github/
  workflows/
    ci.yml                             # hook の自己検査、スキルの写しの検査
    dependabot-auto-merge.yml          # Dependabot patch/minor 自動マージ、スキルの写し直し
  dependabot.yml                       # Actions と npm の更新
  ISSUE_TEMPLATE/
    bug_report.yml                     # バグ報告テンプレート
    feature_request.yml                # 機能リクエストテンプレート
    config.yml                         # blank issue 許可
  PULL_REQUEST_TEMPLATE.md             # PR テンプレート
  scripts/
    setup-repo.sh                      # GitHub 設定自動化スクリプト
    sync-skills.sh                     # パッケージ同梱のスキルを写す
package.json                           # mutator(変異テスト)
pnpm-lock.yaml
LICENSE                                # MIT License(英語 + 日本語)
CODE_OF_CONDUCT.md                     # Contributor Covenant(日本語)
SECURITY.md                            # 脆弱性報告ポリシー
CONTRIBUTING.md                        # コントリビューションガイド
.gitignore                             # 基本的な除外ルール
```

## ライセンス

[MIT License](./LICENSE)
