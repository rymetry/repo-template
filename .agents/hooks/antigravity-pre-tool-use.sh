#!/usr/bin/env bash
# Antigravity は終了コードではなく標準出力の JSON で可否を判定するため、共通の判定結果を変換する。
set -uo pipefail

command -v jq >/dev/null || { echo '{"decision":"deny","reason":"hook の実行に jq が必要です。"}'; exit 0; }

hooks_dir="$(cd "$(dirname "$0")" && pwd)"

# 入力には直前のユーザー発言も含まれるため、実行するコマンドだけを判定に渡す。
if reason="$(jq -r '.toolCall.args.CommandLine // empty' | bash "$hooks_dir/pre-tool-use-policy.sh" 2>&1 >/dev/null)"; then
  echo '{"decision":"allow"}'
else
  jq -cn --arg reason "$reason" '{decision: "deny", reason: $reason}'
fi
