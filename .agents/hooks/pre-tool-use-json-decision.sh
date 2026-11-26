#!/usr/bin/env bash
# 終了コードではなく標準出力の JSON で可否を受け取るエージェント向けに、共通の判定結果を変換する。
set -uo pipefail

command -v jq >/dev/null || { echo '{"decision":"deny","reason":"hook の実行に jq が必要です。"}'; exit 0; }

hooks_dir="$(cd "$(dirname "$0")" && pwd)"

# 入力には直前のユーザー発言も含まれるため、実行するコマンドだけを判定に渡す。
# コマンドを取り出せない入力は判定できないので、許可せずに拒否する。
if ! command_line="$(jq -er '.toolCall.args.CommandLine | select(type == "string" and length > 0)' 2>/dev/null)"; then
  echo '{"decision":"deny","reason":"hook が実行するコマンドを入力から取り出せませんでした。"}'
  exit 0
fi

if reason="$(printf '%s' "$command_line" | bash "$hooks_dir/pre-tool-use-policy.sh" 2>&1 >/dev/null)"; then
  echo '{"decision":"allow"}'
else
  jq -cn --arg reason "$reason" '{decision: "deny", reason: $reason}'
fi
