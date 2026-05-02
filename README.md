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
| **Branch protection** | main に PR 必須 + 管理者バイパス |
| **Auto-merge** | 有効化 |
| **Dependabot** | alerts + security updates 有効化 |
| **Actions** | Workflow permissions を Read only に設定 |
| **不要機能** | Projects / Discussions / Wiki を OFF |
| **ブランチ自動削除** | マージ後に自動削除 |

### 3. AI agent 基盤を確認する

このテンプレートには Codex / Claude Code で共通利用できる最小の自律開発設定を含めています。
実行 engine は各プロジェクトで導入してください。

| 設定 | 内容 |
|------|------|
| **AGENTS.md** | AI coding agent 向けの共通 entrypoint |
| **.agents/autonomy.config.json** | Think → Plan → Build → QA → Review → Ship → Learn の lifecycle 設定 |
| **.agents/rules/** | safety / release gate の初期 rule pack |
| **.agents/skills/** | 自律 driver / review の skill template |
| **.codex/** | Codex hooks と config |
| **.claude/** | Claude Code hook 設定 |

実行するプロジェクトでは、autonomy engine package または repo-local script として
以下のどちらかを公開してください。

- `agent-autonomy-drive` または同等の `agents:drive`
- `agent-autonomy-progress` または同等の `agents:progress`

既存リポジトリに導入する場合は、初回 driver 実行前に完了済み task baseline を明示してください。

```bash
agent-autonomy-progress seed-completed --ids ROADMAP-1,ROADMAP-2
```

`.agents/state/` はローカル実行状態です。`.gitignore` に含まれており、コミットしません。

### 4. README を書き換える

このファイルをプロジェクト固有の内容に置き換えてください。

## 含まれるファイル

```
.github/
  workflows/dependabot-auto-merge.yml  # Dependabot patch/minor 自動マージ
  ISSUE_TEMPLATE/
    bug_report.yml                     # バグ報告テンプレート
    feature_request.yml                # 機能リクエストテンプレート
    config.yml                         # blank issue 許可
  PULL_REQUEST_TEMPLATE.md             # PR テンプレート
  scripts/setup-repo.sh                # GitHub 設定自動化スクリプト
.agents/
  autonomy.config.json                 # 汎用 autonomy lifecycle 設定
  rules/                               # safety / release gate rules
  skills/                              # agent skill templates
.codex/
  config.toml                          # Codex hook 設定
  hooks/                               # Codex / Claude 共通 hooks
.claude/
  settings.json                        # Claude Code hook 設定
AGENTS.md                              # AI agent 共通 context
LICENSE                                # MIT License（英語 + 日本語）
CODE_OF_CONDUCT.md                     # Contributor Covenant（日本語）
SECURITY.md                            # 脆弱性報告ポリシー
CONTRIBUTING.md                        # コントリビューションガイド
.gitignore                             # 基本的な除外ルール
```

## ライセンス

[MIT License](./LICENSE)
