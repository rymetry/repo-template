#!/usr/bin/env bash
# 標準入力は Claude Code / Codex の PreToolUse の JSON。他の形式は呼び出し側でこの形に直す。
set -uo pipefail

command -v jq >/dev/null || { echo "Blocked: hook の実行に jq が必要です。" >&2; exit 2; }

# cwd などコマンド以外の項目に含まれる文字列で誤判定しないよう、実行するコマンドだけを見る。
# 行継続(バックスラッシュと改行)は、分かれた引数を 1 つのコマンドとして読むためにつなぐ。
command_line="$(jq -r '.tool_input.command // empty | gsub("\\\\\n"; " ")' 2>/dev/null)" ||
  { echo "Blocked: hook の入力を JSON として読めません。" >&2; exit 2; }

# 宛先を書かない push は現在のブランチへ向かう。
current_branch="$(git symbolic-ref --short -q HEAD 2>/dev/null)"

# 単純コマンド 1 つ分の単語を受け取り、main への force push なら 0 を返す。
is_force_push_to_main() {
  local state=start force=0 targets_main=0 positionals=0 word destination
  for word in "$@"; do
    case "$state" in
      start)
        case "$word" in git|*/git) state=git ;; esac
        ;;
      git)
        case "$word" in
          -C|-c|--git-dir|--work-tree|--namespace) state=git_option_value ;;
          -*) ;;
          push) state=push ;;
          # コミットメッセージなど、push 以外のサブコマンドの引数は判定しない。
          *) return 1 ;;
        esac
        ;;
      git_option_value) state=git ;;
      push_option_value) state=push ;;
      push)
        case "$word" in
          # git は長いオプションの省略形(--force-w など)も受け付ける。
          --force*|-f*|-[!-]*f*) force=1 ;;
          # すべてのブランチを送るので、main も宛先に含まれる。--mirror は force なしでも上書きする。
          --al*|--b*) targets_main=1 ;;
          --m*) force=1; targets_main=1 ;;
          -o|--push-option|--repo|--receive-pack|--exec) state=push_option_value ;;
          -*) ;;
          *)
            positionals=$((positionals + 1))
            # 最初の位置引数はリモートで、refspec はその後に続く。
            [ "$positionals" -gt 1 ] || continue
            case "$word" in +*) force=1; word="${word#+}" ;; esac
            destination="${word##*:}"
            case "$destination" in HEAD|@) destination="$current_branch" ;; esac
            case "$destination" in main|heads/main|refs/heads/main) targets_main=1 ;; esac
            ;;
        esac
        ;;
    esac
  done

  [ "$force" = 1 ] || return 1
  [ "$targets_main" = 1 ] || { [ "$positionals" -le 1 ] && [ "$current_branch" = main ]; }
}

# 単語に分けるときに * などがファイル名へ展開されないようにする。
set -f

# shortcut: 引用符を外し、区切り記号と空白で分けるだけで、変数・エイリアス・cd や -C の移動先は追わない。
# 引用した文字列の中に区切り記号と同じ文言があれば、それも止める。
# これらが問題になったら、シェルの構文解析に置き換える。
while IFS= read -r simple_command; do
  # shellcheck disable=SC2086 # 単語に分けるために引用符を付けない。
  if is_force_push_to_main $simple_command; then
    echo "Blocked: force push to main is not allowed." >&2
    exit 2
  fi
done < <(
  # リダイレクトは引数の間にも書けるので、refspec に数えないよう区切る前に取り除く。
  printf '%s\n' "$command_line" | tr -d "\"'" |
    sed -E 's/[0-9]*&?[<>]+&?[[:space:]]*[^[:space:];&|()]*//g' | tr ';&|()`' '\n'
)

exit 0
