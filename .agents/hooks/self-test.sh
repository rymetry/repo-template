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

# こちらも入力の Cwd で判定することを確かめるため、リポジトリへ移動せずに動かす。
run_json_decision() {
  jq -cn --arg command "$1" --arg message "${2:-}" --arg cwd "$repository" \
    '{toolCall: {args: {CommandLine: $command, Cwd: $cwd}}, lastUserInput: $message}' |
    bash "$hooks_dir/pre-tool-use-json-decision.sh"
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
expect_both deny 'git push -f origin "+refs/*:refs/*"'
expect_both deny 'git push -f origin "*:*"'
expect_both deny 'git push -f origin "refs/heads/*:heads/*"'
expect_both allow 'git push -f origin "refs/tags/*:refs/tags/*"'
expect_both allow 'git push -f origin feature:'
expect_both allow 'git push -f origin HEAD:'
expect_both deny 'git push -f origin main:'
expect_both deny 'git push -f origin "${SOURCE:-feature}:main"'
expect_both deny 'git push -f "$(git remote)" "$(echo x)" main'
expect_both deny 'echo "${X:-$(git push -f origin main)}"'
expect_both deny 'echo "${X:-`git push -f origin main`}"'
expect_both deny 'git push -f "$(echo ${X:-(a)})" main'
# 中に ( ) があって移せないコマンド置換は、git push を含むなら判定できないものとして止める。
unresolved_reason='Blocked: コマンド置換を読み切れないため、main への force push かどうか判定できません。置換を変数に分けて実行してください。'
for command in \
  'git push -f "$(case x in (a) echo origin;; esac)" main' \
  'git push -f origin "$(case x in (a) echo feature;; esac)"' \
  'git push origin "$(case x in (a) echo main;; esac)"' \
  'git -C "$(case x in (a) echo .;; esac)" push -f origin main' \
  'git push -f -o "$(case x in (a) echo x;; esac)" origin main' \
  'git push -f $((cd app); echo origin) main' \
  'GIT PUSH -f "$(case x in (a) echo origin;; esac)" main'; do
  expect "policy: unresolved on $branch: $command" "2 $unresolved_reason" "$(result_of run_policy "$command")"
  expect "json decision: unresolved on $branch: $command" deny "$(json_decision "$command")"
done
expect_both allow 'echo "$(case x in (a) echo ok;; esac)"'
expect_both deny 'echo $( (cd app && git push -f origin main) )'
# 中に ( ) のない $(( )) は、中身がコマンドに見えても bash は算術式として読み、実行しない。
expect_both allow 'x=$((x + 1)); git push origin feature'
expect_both deny '/usr/libexec/git-core/git-push -f origin main'
expect_both deny 'git-push -f origin main'
expect_both deny 'git.exe push -f origin main'
expect_both deny 'GIT push -f origin main'
expect_both deny '/usr/bin/Git.EXE push -f origin main'
expect_both deny 'Git-Push -f origin main'
expect_both deny 'git PUSH -f origin main'
expect_both allow 'GIT push -f origin feature'
expect_both deny 'git push -f -ogo origin main'
expect_both allow 'git push -ofo origin main'
expect_both deny 'git push -f "$(git remote)" main'
expect_both deny 'git push -f `git remote` main'
expect_both deny 'echo "$(git push -f origin main)"'
expect_both deny 'echo `git push -f origin main`'
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
expect_both deny 'git push -f origin "${BRANCH:-main}"'
expect_both deny 'git push -fo ci.skip origin'
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
# 署名や commit hook などの個人設定で準備が失敗しないようにし、タグができたことも確かめる。
git -C "$repository" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q --allow-empty -m initial
git -C "$repository" -c tag.gpgSign=false tag main
expect 'a tag named main exists' yes \
  "$(git -C "$repository" rev-parse -q --verify refs/tags/main >/dev/null && echo yes || echo no)"
expect_both deny 'git push --force'

# ブランチが分からないときは main とみなす。
git -C "$repository" checkout -q --detach
branch=detached
expect_both deny 'git push -f'
expect_both deny 'git push -f origin "$BRANCH"'
expect_both allow 'git push -f origin HEAD:refs/heads/feature'

expect 'policy joins a command given as an array' "2 $blocked_reason" \
  "$(jq -cn '{tool_input: {command: ["git", "push", "-f", "origin", "main"]}}' |
    result_of bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy allows an ordinary command given as an array' "$allowed" \
  "$(jq -cn '{tool_input: {command: ["ls", "-la"]}}' | result_of bash "$hooks_dir/pre-tool-use-policy.sh")"

# jq がなくても、jq を入れるコマンドは通し、git push だけを止める。
expect 'policy blocks git push when jq is missing' '2 Blocked: hook の実行に jq が必要です。jq を入れてから実行してください。' \
  "$(printf '{"tool_input":{"command":"git push origin feature"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks a quoted git push when jq is missing' '2 Blocked: hook の実行に jq が必要です。jq を入れてから実行してください。' \
  "$(jq -cn '{tool_input: {command: "\"gi\"\"t\" pu\\sh -f origin main"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks push before git when jq is missing' '2 Blocked: hook の実行に jq が必要です。jq を入れてから実行してください。' \
  "$(jq -cn '{tool_input: {command: "p=push; git $p -f origin main"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks an upper-case git push when jq is missing' '2 Blocked: hook の実行に jq が必要です。jq を入れてから実行してください。' \
  "$(printf '{"tool_input":{"command":"GIT PUSH -f origin main"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy ignores git and push in the working directory when jq is missing' "$allowed" \
  "$(printf '{"cwd":"/work/github/web-push","tool_input":{"command":"brew install jq"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy allows installing jq when jq is missing' "$allowed" \
  "$(printf '{"tool_input":{"command":"brew install jq"}}' |
    result_of env PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'policy blocks input that is not JSON' '2 Blocked: hook の入力を JSON として読めません。' \
  "$(printf 'not json' | result_of bash "$hooks_dir/pre-tool-use-policy.sh")"

expect 'json decision passes on the reason for a denial' \
  "$(jq -cn --arg reason "$blocked_reason" '{decision: "deny", reason: $reason}')" \
  "$(run_json_decision "$force_push")"
expect 'json decision allows an ordinary command' allow "$(json_decision 'npm test')"
expect 'json decision ignores the user message' allow "$(json_decision 'ls' "$force_push")"
expect 'json decision denies git push when jq is missing' \
  '{"decision":"deny","reason":"hook の実行に jq が必要です。jq を入れてから実行してください。"}' \
  "$(printf '{"toolCall":{"args":{"CommandLine":"git push origin feature"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh")"
expect 'json decision denies a quoted git push when jq is missing' deny \
  "$(jq -cn '{toolCall: {args: {CommandLine: "gi'"'"''"'"'t push -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision denies push before git when jq is missing' deny \
  "$(jq -cn '{toolCall: {args: {CommandLine: "p=push; git $p -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision allows installing jq when jq is missing' '{"decision":"allow"}' \
  "$(printf '{"toolCall":{"args":{"CommandLine":"brew install jq"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh")"
# 直前のユーザー発言は、項目の順番によらず判定に使わない。
for payload in \
  '{"lastUserInput":"git push","toolCall":{"args":{"CommandLine":"brew install jq"}}}' \
  '{"toolCall":{"args":{"CommandLine":"brew install jq"}},"lastUserInput":"git push"}'; do
  expect "json decision ignores the user message when jq is missing: $payload" '{"decision":"allow"}' \
    "$(printf '%s' "$payload" | PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh")"
done
expect 'json decision denies git push after the user message when jq is missing' deny \
  "$(printf '{"lastUserInput":"ok","toolCall":{"args":{"CommandLine":"git push -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision denies an upper-case git push when jq is missing' deny \
  "$(printf '{"toolCall":{"args":{"CommandLine":"Git Push -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision checks the last CommandLine when jq is missing' deny \
  "$(printf '{"history":[{"CommandLine":"ls"}],"lastUserInput":"ok","toolCall":{"args":{"CommandLine":"git push -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision denies a payload without a command when jq is missing' deny \
  "$(printf '{"toolCall":{"args":{}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"
expect 'json decision does not cut the command at a quoted key name when jq is missing' deny \
  "$(jq -cn '{toolCall: {args: {CommandLine: "echo \"lastUserInput\"; git push -f origin main"}}}' |
    PATH=/nonexistent /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh" | jq -r .decision)"

# jq があっても動かないときは、jq がないときと同じに扱う。
broken_jq_dir="$sandbox/broken-jq"
mkdir "$broken_jq_dir"
printf '#!/bin/sh\nexit 126\n' > "$broken_jq_dir/jq"
chmod +x "$broken_jq_dir/jq"
expect 'policy allows installing jq when jq cannot run' "$allowed" \
  "$(printf '{"tool_input":{"command":"brew reinstall jq"}}' |
    result_of env PATH="$broken_jq_dir" /bin/bash "$hooks_dir/pre-tool-use-policy.sh")"
expect 'json decision allows installing jq when jq cannot run' '{"decision":"allow"}' \
  "$(printf '{"toolCall":{"args":{"CommandLine":"brew reinstall jq"}}}' |
    PATH="$broken_jq_dir" /bin/bash "$hooks_dir/pre-tool-use-json-decision.sh")"

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
