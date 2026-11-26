#!/usr/bin/env bash
# 終了コードではなく標準出力の JSON で可否を受け取るエージェント向けに、共通の判定結果を変換する。
set -uo pipefail

# jq を入れるコマンドも止めないよう、標準入力は外部コマンドを使わずに読む。
IFS= read -r -d '' input || true

# jq がない、または動かないとコマンドを取り出せないので、git push を含む入力だけを拒否し、jq の導入などは通す。
# 直前のユーザー発言では拒否しないよう、CommandLine の項目から後ろを見て、lastUserInput の項目は外す。
# CommandLine の項目が複数あっても実行するものを外さないよう、最初と最後の両方から切り出す。
# JSON の文字列の中の " は \" になるので、"CommandLine" と "lastUserInput" の一致は項目名だけに当たる。
# gi""t のように引用符やバックスラッシュで分けた語も見つけるため、それらを除いてから探す。
if ! jq -n 1 >/dev/null 2>&1; then
  case "$input" in
    *\"CommandLine\"*) ;;
    *) echo '{"decision":"deny","reason":"hook が実行するコマンドを入力から取り出せませんでした。"}'; exit 0 ;;
  esac
  first=${input#*\"CommandLine\"}
  last=${input##*\"CommandLine\"}
  command_part="${first%%\"lastUserInput\"*} ${last%%\"lastUserInput\"*}"
  normalized=${command_part//[\"\'\\]/}
  case "$normalized" in
    *[Gg][Ii][Tt]*[Pp][Uu][Ss][Hh]*|*[Pp][Uu][Ss][Hh]*[Gg][Ii][Tt]*) echo '{"decision":"deny","reason":"hook の実行に jq が必要です。jq を入れてから実行してください。"}' ;;
    *) echo '{"decision":"allow"}' ;;
  esac
  exit 0
fi

hooks_dir="$(cd "$(dirname "$0")" && pwd)"

# 入力には直前のユーザー発言も含まれるため、実行するコマンドだけを判定に渡す。
# コマンドを取り出せない入力は判定できないので、許可せずに拒否する。
# 読めるのは toolCall.args.CommandLine の形だけ。入力の形が違うエージェントをつなぐときは、その形をここに足す。
if ! jq -e '.toolCall.args.CommandLine | select(type == "string" and length > 0)' <<<"$input" >/dev/null 2>&1; then
  echo '{"decision":"deny","reason":"hook が実行するコマンドを入力から取り出せませんでした。"}'
  exit 0
fi

# 共通の判定は Claude Code / Codex の入力の形で読む。現在のブランチは、コマンドを実行する場所(Cwd)で調べる。
if reason="$(jq -c '{tool_input: {command: .toolCall.args.CommandLine}, cwd: .toolCall.args.Cwd}' <<<"$input" |
  bash "$hooks_dir/pre-tool-use-policy.sh" 2>&1 >/dev/null)"; then
  echo '{"decision":"allow"}'
else
  jq -cn --arg reason "$reason" '{decision: "deny", reason: $reason}'
fi
