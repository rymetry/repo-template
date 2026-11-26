#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup-repo.sh — 新規リポジトリの GitHub 設定を自動化
#
# 使い方:
#   gh repo create my-project --template rymetry/repo-template --public --clone
#   cd my-project
#   bash .github/scripts/setup-repo.sh
# =============================================================================

# ---------------------------------------------------------------------------
# 0. 前提チェック
# ---------------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI が必要です: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ gh auth login を先に実行してください"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "❌ git が必要です"; exit 1; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
AUTHOR=$(gh api "repos/$REPO" --jq '.owner.login')
YEAR=$(date +%Y)

echo ""
echo "========================================="
echo "  repo-template setup"
echo "  Repository: $REPO"
echo "========================================="
echo ""

# ---------------------------------------------------------------------------
# 1. プレースホルダーの置換
# ---------------------------------------------------------------------------
echo "📝 Replacing placeholders..."

replace_in_file() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$1" "$2"
  else
    sed -i "$1" "$2"
  fi
}

# LICENSE
replace_in_file "s/{{YEAR}}/$YEAR/g" LICENSE
replace_in_file "s/{{AUTHOR}}/$AUTHOR/g" LICENSE

# SECURITY.md
replace_in_file "s|{{REPO}}|$REPO|g" SECURITY.md

echo "  LICENSE: {{YEAR}} → $YEAR, {{AUTHOR}} → $AUTHOR"
echo "  SECURITY.md: {{REPO}} → $REPO"

# ---------------------------------------------------------------------------
# 2. リポジトリ設定
# ---------------------------------------------------------------------------
echo ""
echo "⚙️  Configuring repository settings..."

gh repo edit "$REPO" \
  --enable-projects=false \
  --enable-discussions=false \
  --enable-wiki=false \
  --delete-branch-on-merge \
  --enable-auto-merge

echo "  Projects: OFF"
echo "  Discussions: OFF"
echo "  Wiki: OFF"
echo "  Delete branch on merge: ON"
echo "  Auto-merge: ON"

# ---------------------------------------------------------------------------
# 3. Dependabot alerts
# ---------------------------------------------------------------------------
echo ""
echo "🔒 Enabling Dependabot alerts..."

if gh api -X PUT "repos/$REPO/vulnerability-alerts" 2>/dev/null; then
  echo "  Dependabot alerts: ON"
else
  echo "  ⚠️  Dependabot alerts の設定に失敗しました"
fi

# ---------------------------------------------------------------------------
# 4. Secret scanning
# ---------------------------------------------------------------------------
echo ""
echo "🔑 Enabling secret scanning..."

if gh api --silent -X PATCH "repos/$REPO" \
  --input - <<'SCANNING'; then
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
SCANNING
  echo "  Secret scanning: ON"
  echo "  Push protection: ON"
else
  echo "  ⚠️  Secret scanning の設定に失敗しました（上のエラーを確認してください。プランによっては利用できません）"
  echo "      利用できる場合は Settings > Security から有効化してください"
fi

# ---------------------------------------------------------------------------
# 5. Actions permissions
# ---------------------------------------------------------------------------
echo ""
echo "🔐 Configuring Actions permissions..."

if gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
  --input - <<'PERMS' 2>/dev/null; then
{
  "default_workflow_permissions": "read",
  "can_approve_pull_request_reviews": true
}
PERMS
  echo "  Workflow permissions: Read only"
  echo "  PR approval by Actions: Allowed"
else
  echo "  ⚠️  Actions permissions の設定に失敗しました"
fi

# ---------------------------------------------------------------------------
# 6. Branch protection (main)
# ---------------------------------------------------------------------------
echo ""
echo "🛡️  Setting up branch protection for main..."

if gh api -X PUT "repos/$REPO/branches/main/protection" \
  --input - <<'PROTECTION' 2>/dev/null; then
{
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "enforce_admins": false,
  "restrictions": null,
  "required_status_checks": {
    "strict": false,
    "contexts": ["check"]
  },
  "allow_force_pushes": false,
  "allow_deletions": false
}
PROTECTION
  echo "  PR required: ON (0 approvals, self-merge OK)"
  echo "  Required check: check (.github/workflows/ci.yml)"
  echo "  Admin bypass: ON"
  echo "  Force push: BLOCKED"
  echo "  Branch deletion: BLOCKED"
else
  echo "  ⚠️  Branch protection の設定に失敗しました（Free プランのプライベートリポジトリでは利用不可）"
fi

# ---------------------------------------------------------------------------
# 7. コミット & 完了
# ---------------------------------------------------------------------------
echo ""
echo "📦 Committing placeholder replacements..."

git add LICENSE SECURITY.md
if git diff --cached --quiet; then
  echo "  No changes to commit"
else
  git commit -m "chore: setup-repo.sh によるプレースホルダー置換"
  git push
  echo "  Committed and pushed"
fi

echo ""
echo "========================================="
echo "  ✅ Setup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. 依存とプラグインを入れる（README の手順 3）"
echo "  2. エージェントに相談してアーキテクチャを決める（README の手順 4）"
echo "  3. README.md と AGENTS.md をプロジェクト固有の内容に書き換える"
echo "  4. Settings > Security で Private vulnerability reporting を有効化する（UI のみ）"
echo ""
