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

# パスに main を含む場所(domain)でも判定が変わらないことを、すべてのケースで確かめる。
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
repository="$sandbox/domain"
git init -q "$repository"

# 判定は現在のブランチにも依存するため、ブランチを決めたリポジトリを対象にする。
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

# hook を起動した場所ではなく入力の cwd で判定することを確かめるため、リポジトリへ移動せずに動かす。
run_policy() {
  jq -cn --arg command "$1" --arg cwd "$repository" \
    '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' |
    bash "$hooks_dir/pre-tool-use-policy.sh"
}

# こちらの入力には cwd がないので、hook を起動した場所で判定する。
run_json_decision() {
  jq -cn --arg command "$1" --arg message "${2:-}" \
    '{toolCall: {args: {CommandLine: $command}}, lastUserInput: $message}' |
    (cd "$repository" && bash "$hooks_dir/pre-tool-use-json-decision.sh")
}

json_decision() {
  run_json_decision "$@" | jq -r .decision
}

allowed='0 '
blocked_reason='Blocked: force push to main is not allowed.'

# 同じコマンドは、どのエージェントの入力でも同じ判定になる。
expect_both() {
  local decision="$1" command="$2" expected="$allowed"
  [ "$decision" = allow ] || expected="2 $blocked_reason"
  expect "policy: $decision on $branch: $command" "$expected" "$(result_of run_policy "$command")"
  expect "json decision: $decision on $branch: $command" "$decision" "$(json_decision "$command")"
}

force_push='git push --force origin main'

on_branch feature
expect_both deny "$force_push"
expect_both deny 'git push --force-with-lease origin main'
expect_both deny 'git push --force-w origin main'
expect_both deny 'git push --force --all origin'
expect_both deny 'git push -f --al origin'
expect_both deny 'git push -f --branches origin'
expect_both deny 'git push -f --b origin'
expect_both deny 'git push --mirror origin'
expect_both deny 'git push --m'
expect_both allow 'git push --all origin'
expect_both allow 'git push --branches origin'
expect_both allow 'git push -f --tags origin'
expect_both deny 'git push -f origin main'
expect_both deny 'git push -uf origin main'
expect_both deny 'git push origin +main'
expect_both deny 'git push -f origin HEAD:main'
expect_both deny 'git push origin +feature:refs/heads/main'
expect_both deny 'git fetch; git push -f origin main'
expect_both deny $'git push \\\n  -f origin main'
expect_both deny 'git -C app push -f origin "main" 2>&1 | tail -3'
for option in -C -c --git-dir --work-tree --namespace --config-env --attr-source; do
  expect_both deny "git $option value push -f origin main"
done
expect_both deny '/usr/bin/git push -f origin main'
expect_both deny 'git push -f 2>&1 origin main'
expect_both deny 'git push -f origin feature:heads/main'
expect_both deny 'git push origin +:'
expect_both deny 'git push -f origin :'
expect_both deny 'git push origin +refs/heads/*:refs/heads/*'
expect_both deny 'git push -f "$(git remote)" main'
expect_both deny 'git push -f `git remote` main'
expect_both deny 'echo "$(git push -f origin main)"'
expect_both allow 'git push --force-with-lease origin "$(git branch --show-current)"'
expect_both allow 'git push -f origin "$BRANCH"'
expect_both allow 'git push origin :'
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

on_branch main
expect_both deny 'git push -f'
expect_both deny 'git push --force origin'
expect_both deny 'git push -f origin HEAD'
expect_both deny 'git push -f origin @'
expect_both deny 'git push --force-with-lease origin "$(git branch --show-current)"'
expect_both deny 'git push -f origin "$BRANCH"'
expect_both deny 'git push -f origin 2>&1'
expect_both deny 'git push -f origin > push.log'
expect_both deny 'git push -f && echo done'
for option in -o --push-option --pu --repo --rep --receive-pack --rece --exec --e; do
  expect_both deny "git push -f $option value origin"
done
expect_both deny 'git push -f --follow-tags'
expect_both deny 'git push -f origin main --tags'
expect_both allow 'git push -f origin --tags'
expect_both allow 'git push -f --ta'
expect_both allow 'git push -f --push-option=ci.skip origin feature'
expect_both allow 'git push'
expect_both allow 'git push origin HEAD'
expect_both allow 'git push -f origin feature'

# 同じ名前のタグがあると、短縮した参照名は heads/main になる。
git -C "$repository" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m initial
git -C "$repository" tag main
expect_both deny 'git push --force'

expect 'policy joins a command given as an array' "2 $blocked_reason" \
  "$(jq -cn '{tool_input: {command: ["git", "push", "-f", "origin", "main"]}}' |
    result_of bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy allows an ordinary command given as an array' "$allowed" \
  "$(jq -cn '{tool_input: {command: ["ls", "-la"]}}' | result_of bash "$hooks_dir/pre-tool-use-policy.sh")"

expect 'policy blocks when jq is missing' '2 Blocked: hook の実行に jq が必要です。' \
  "$(printf '{}' | result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks input that is not JSON' '2 Blocked: hook の入力を JSON として読めません。' \
  "$(printf 'not json' | result_of bash "$hooks_dir/pre-tool-use-policy.sh")"

expect 'json decision passes on the reason for a denial' \
  "$(jq -cn --arg reason "$blocked_reason" '{decision: "deny", reason: $reason}')" \
  "$(run_json_decision "$force_push")"
expect 'json decision allows an ordinary command' allow "$(json_decision 'npm test')"
expect 'json decision ignores the user message' allow "$(json_decision 'ls' "$force_push")"
expect 'json decision denies when jq is missing' '{"decision":"deny","reason":"hook の実行に jq が必要です。"}' \
  "$(printf '{}' | PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh")"

json_decision_for_payload() {
  jq -cn "$1" | bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision
}

expect 'json decision denies a payload without a command' deny "$(json_decision_for_payload '{}')"
expect 'json decision denies a renamed command field' deny \
  "$(json_decision_for_payload '{toolCall: {args: {commandLine: "ls"}}}')"
expect 'json decision denies an empty command' deny \
  "$(json_decision_for_payload '{toolCall: {args: {CommandLine: ""}}}')"
expect 'json decision denies input that is not JSON' deny \
  "$(printf 'not json' | bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"

# 設定ファイルが指す hook が存在しないと、エージェントは何も知らせずに hook を無効にする。
repository_root="$(cd "$hooks_dir/../.." && pwd)"
for config in .claude/settings.json .codex/hooks.json .agents/hooks.json; do
  referenced_scripts="$(grep -o '\.[A-Za-z]*/hooks/[A-Za-z0-9_-]*\.sh' "$repository_root/$config" | sort -u)"
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
