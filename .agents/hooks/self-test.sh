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

repository="$(mktemp -d)"
trap 'rm -rf "$repository"' EXIT
git -C "$repository" init -q

# 判定は現在のブランチにも依存するため、ブランチを決めたリポジトリの中で hook を動かす。
on_branch() {
  branch="$1"
  git -C "$repository" symbolic-ref HEAD "refs/heads/$branch"
}

# 終了コードと標準エラーを 1 行で返す。
result_of() {
  local reason
  reason="$("$@" 2>&1 >/dev/null)"
  echo "$? $reason"
}

run_policy() {
  jq -cn --arg command "$1" --arg cwd "${2:-$repository}" \
    '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' |
    (cd "$repository" && bash "$hooks_dir/pre-tool-use-policy.sh")
}

run_antigravity() {
  jq -cn --arg command "$1" --arg message "${2:-}" \
    '{toolCall: {args: {CommandLine: $command}}, lastUserInput: $message}' |
    (cd "$repository" && bash "$hooks_dir/antigravity-pre-tool-use.sh")
}

antigravity_decision() {
  run_antigravity "$@" | jq -r .decision
}

allowed='0 '
blocked_reason='Blocked: force push to main is not allowed.'

# 同じコマンドは、どのエージェントの入力でも同じ判定になる。
expect_both() {
  local decision="$1" command="$2" expected="$allowed"
  [ "$decision" = allow ] || expected="2 $blocked_reason"
  expect "policy: $decision on $branch: $command" "$expected" "$(result_of run_policy "$command")"
  expect "antigravity: $decision on $branch: $command" "$decision" "$(antigravity_decision "$command")"
}

force_push='git push --force origin main'

on_branch feature
expect_both deny "$force_push"
expect_both deny 'git push --force-with-lease origin main'
expect_both deny 'git push -f origin main'
expect_both deny 'git push -uf origin main'
expect_both deny 'git push origin +main'
expect_both deny 'git push -f origin HEAD:main'
expect_both deny 'git push origin +feature:refs/heads/main'
expect_both deny 'git fetch; git push -f origin main'
expect_both deny $'git push \\\n  -f origin main'
expect_both deny 'git -C app push -f origin "main" 2>&1 | tail -3'
expect_both deny 'git --git-dir .git push -f origin main'
expect_both deny 'git push -f 2>&1 origin main'
expect_both deny 'git push -f origin feature:heads/main'
expect_both allow 'git push -f origin feature > main'
expect_both allow 'git push origin main'
expect_both allow 'git push --follow-tags origin main'
expect_both allow 'git push -f'
expect_both allow 'git push -f origin'
expect_both allow 'git push -f origin HEAD'
expect_both allow 'git push -f origin feature'
expect_both allow 'git push -f origin main:feature'
expect_both allow 'git push -f main feature'
expect_both allow 'echo main && git push -f origin feature'
expect_both allow 'git commit -m "git push -f origin main"'
expect 'policy ignores main in the working directory path' "$allowed" \
  "$(result_of run_policy 'git push --force origin feature' /work/domain/repository)"

on_branch main
expect_both deny 'git push -f'
expect_both deny 'git push --force origin'
expect_both deny 'git push -f origin HEAD'
expect_both deny 'git push -f origin 2>&1'
expect_both deny 'git push -f origin > push.log'
expect_both deny 'git push -f && echo done'
expect_both deny 'git push -f -o ci.skip origin'
expect_both allow 'git push'
expect_both allow 'git push origin HEAD'
expect_both allow 'git push -f origin feature'

expect 'policy blocks when jq is missing' '2 Blocked: hook の実行に jq が必要です。' \
  "$(printf '{}' | result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks input that is not JSON' '2 Blocked: hook の入力を JSON として読めません。' \
  "$(printf 'not json' | result_of bash "$hooks_dir/pre-tool-use-policy.sh")"

expect 'antigravity passes on the reason for a denial' \
  "$(jq -cn --arg reason "$blocked_reason" '{decision: "deny", reason: $reason}')" \
  "$(run_antigravity "$force_push")"
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

printf 'resolved\n' > "$repository/file.txt"
git -C "$repository" add file.txt
expect 'stop-verify passes without conflict markers' 0 \
  "$(cd "$repository" && bash "$hooks_dir/stop-verify.sh" >/dev/null 2>&1; echo $?)"
printf '<<<<<<<\nours\n=======\ntheirs\n>>>>>>>\n' > "$repository/file.txt"
git -C "$repository" add file.txt
expect 'stop-verify blocks conflict markers' 2 \
  "$(cd "$repository" && bash "$hooks_dir/stop-verify.sh" >/dev/null 2>&1; echo $?)"

[ "$failures" -eq 0 ]
