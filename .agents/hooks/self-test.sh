#!/usr/bin/env bash
# hook の判定を確かめる自己検査。失敗があれば終了コード 1 を返す。
set -uo pipefail

hooks_dir="$(cd "$(dirname "$0")" && pwd)"
failures=0

expect() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label: expected '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

policy_exit() {
  printf '%s' "$1" | bash "$hooks_dir/pre-tool-use-policy.sh" >/dev/null 2>&1
  echo $?
}

antigravity_decision() {
  jq -cn --arg command "$1" --arg message "${2:-}" \
    '{toolCall: {args: {CommandLine: $command}}, lastUserInput: $message}' |
    bash "$hooks_dir/antigravity-pre-tool-use.sh" | jq -r .decision
}

force_push='git push --force origin main'

expect 'policy blocks force push to main' 2 "$(policy_exit "command: $force_push")"
expect 'policy blocks forced refspec to main' 2 "$(policy_exit 'command: git push origin +main')"
expect 'policy allows push to another branch' 0 "$(policy_exit 'command: git push origin feature')"

expect 'antigravity denies force push to main' deny "$(antigravity_decision "$force_push")"
expect 'antigravity allows an ordinary command' allow "$(antigravity_decision 'npm test')"
expect 'antigravity ignores the user message' allow "$(antigravity_decision 'ls' "$force_push")"
expect 'antigravity denies when jq is missing' '{"decision":"deny","reason":"hook の実行に jq が必要です。"}' \
  "$(printf '{}' | PATH=/nonexistent /bin/bash "$hooks_dir/antigravity-pre-tool-use.sh")"

antigravity_decision_for_payload() {
  jq -cn "$1" | bash "$hooks_dir/antigravity-pre-tool-use.sh" | jq -r .decision
}

expect 'antigravity denies a payload without a command' deny "$(antigravity_decision_for_payload '{}')"
expect 'antigravity denies a renamed command field' deny \
  "$(antigravity_decision_for_payload '{toolCall: {args: {commandLine: "ls"}}}')"
expect 'antigravity denies an empty command' deny \
  "$(antigravity_decision_for_payload '{toolCall: {args: {CommandLine: ""}}}')"
expect 'antigravity denies input that is not JSON' deny \
  "$(printf 'not json' | bash "$hooks_dir/antigravity-pre-tool-use.sh" | jq -r .decision)"

# 設定ファイルが指す hook が存在しないと、エージェントは何も知らせずに hook を無効にする。
repository_root="$(cd "$hooks_dir/../.." && pwd)"
for config in .claude/settings.json .codex/hooks.json .agents/hooks.json; do
  referenced_scripts="$(grep -o '\.agents/hooks/[A-Za-z0-9_-]*\.sh' "$repository_root/$config" | sort -u)"
  expect "$config refers to a hook script" yes "$([ -n "$referenced_scripts" ] && echo yes || echo no)"
  for script in $referenced_scripts; do
    expect "$config: $script exists" yes "$([ -f "$repository_root/$script" ] && echo yes || echo no)"
  done
done

repository="$(mktemp -d)"
trap 'rm -rf "$repository"' EXIT
git -C "$repository" init -q
printf 'resolved\n' > "$repository/file.txt"
git -C "$repository" add file.txt
expect 'stop-verify passes without conflict markers' 0 \
  "$(cd "$repository" && bash "$hooks_dir/stop-verify.sh" >/dev/null 2>&1; echo $?)"
printf '<<<<<<<\nours\n=======\ntheirs\n>>>>>>>\n' > "$repository/file.txt"
git -C "$repository" add file.txt
expect 'stop-verify blocks conflict markers' 2 \
  "$(cd "$repository" && bash "$hooks_dir/stop-verify.sh" >/dev/null 2>&1; echo $?)"

[ "$failures" -eq 0 ]
