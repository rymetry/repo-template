#!/usr/bin/env bash
# 標準入力は Claude Code / Codex の PreToolUse の JSON。他の形式は呼び出し側でこの形に直す。
set -uo pipefail

# jq を入れるコマンドも止めないよう、標準入力は外部コマンドを使わずに読む。
IFS= read -r -d '' input || true

# jq がない、または動かないとコマンドを取り出せないので、git push を含む入力だけを止め、jq の導入などは通す。
# cwd などのパスで止めないよう、最初の "command" の項目より前は見ない。後ろは削らないので、コマンドを見落とさない。
# gi""t のように引用符やバックスラッシュで分けた語も見つけるため、それらを除いてから探す。
if ! jq -n 1 >/dev/null 2>&1; then
  command_part=${input#*\"command\"}
  normalized=${command_part//[\"\'\\]/}
  case "$normalized" in *[Gg][Ii][Tt]*[Pp][Uu][Ss][Hh]*|*[Pp][Uu][Ss][Hh]*[Gg][Ii][Tt]*) echo "Blocked: hook の実行に jq が必要です。jq を入れてから実行してください。" >&2; exit 2 ;; esac
  exit 0
fi

# cwd などコマンド以外の項目に含まれる文字列で誤判定しないよう、実行するコマンドだけを見る。
# 引数の配列で渡されたコマンドは 1 行につなぐ。
# 行継続(バックスラッシュと改行)は、分かれた引数を 1 つのコマンドとして読むためにつなぐ。
command_line="$(jq -r '[.tool_input.command // empty] | flatten | join(" ") | gsub("\\\\\n"; " ")' <<<"$input" 2>/dev/null)" ||
  { echo "Blocked: hook の入力を JSON として読めません。" >&2; exit 2; }

# 宛先を書かない push は現在のブランチへ向かう。hook を起動した場所ではなく、コマンドを実行する場所で調べる。
# 短縮した参照名は、同じ名前のタグがあると heads/main になり main と一致しない。
current_branch="$(git -C "$(jq -r '.cwd // "."' <<<"$input")" branch --show-current 2>/dev/null)"
# ブランチが分からないとき(detached HEAD、古い git など)は、見逃さないよう main とみなす。
current_branch="${current_branch:-main}"

# 単純コマンド 1 つ分の単語を受け取り、main への force push なら 0 を返す。
is_force_push_to_main() {
  local state=start force=0 targets_main=0 tags_only=0 positionals=0 word destination prefix cluster name seen_command=0
  for word in "$@"; do
    # 移せなかったコマンド置換がコマンド名か git の引数の位置にあると、その後ろを追えない。
    # 他のコマンドの引数(gh pr create --body "$(cat <<EOF ...)" など)や、代入の値(x=$(...))にあっても、判定には影響しない。
    case "$word" in
      %unresolved%) { [ "$seen_command" = 0 ] || [ "$state" != start ]; } && unresolved=1; seen_command=1; continue ;;
      %value%) [ "$state" = start ] || unresolved=1; continue ;;
    esac
    case "$state" in
      start)
        # X=1 git push のような代入は、コマンド名ではない。
        case "$word" in [A-Za-z_]*=*) ;; *) seen_command=1 ;; esac
        # 大文字と小文字を区別しないファイルシステム(macOS、Windows)では GIT や Git.exe も git として動く。
        name="${word##*/}"
        case "$name" in *.[Ee][Xx][Ee]) name="${name%.*}" ;; esac
        case "$name" in
          [Gg][Ii][Tt]) state=git ;;
          # git の exec-path にある git-push も、git push と同じく動く。
          [Gg][Ii][Tt]-[Pp][Uu][Ss][Hh]) state=push ;;
        esac
        ;;
      git)
        case "$word" in
          -C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source) state=git_option_value ;;
          -*) ;;
          [Pp][Uu][Ss][Hh]) state=push ;;
          # コミットメッセージなど、push 以外のサブコマンドの引数は判定しない。
          *) return 1 ;;
        esac
        ;;
      git_option_value) state=git ;;
      push_option_value) state=push ;;
      push)
        # git push は長いオプションの省略形(--force-w など)も受け付けるので、一意に決まる前方一致で比べる。
        case "$word" in
          --force*) force=1 ;;
          # すべてのブランチを送るので、main も宛先に含まれる。--mirror は force なしでも上書きする。
          --al*|--b*) targets_main=1 ;;
          --m*) force=1; targets_main=1 ;;
          # タグだけを送り、現在のブランチは送らない。
          --ta*) tags_only=1 ;;
          # 値を = でつないだオプションの次の単語は、値ではない。
          --*=*) ;;
          --pu*|--rep*|--rece*|--e*) state=push_option_value ;;
          # 短いオプションは git と同じく 1 文字ずつ読む。-o の値は、続く文字があればその残り、なければ次の単語。
          -[!-]*)
            cluster="${word#-}"
            while [ -n "$cluster" ]; do
              case "$cluster" in
                f*) force=1 ;;
                o) state=push_option_value ;;
                o*) break ;;
              esac
              cluster="${cluster#?}"
            done
            ;;
          -*) ;;
          *)
            positionals=$((positionals + 1))
            # 最初の位置引数はリモートで、refspec はその後に続く。
            [ "$positionals" -gt 1 ] || continue
            case "$word" in +*) force=1; word="${word#+}" ;; esac
            case "$word" in
              # : だけの refspec は、リモートにある同じ名前のブランチをまとめて送る。
              :) destination='*' ;;
              # 宛先を空にした <src>: は、src と同じ名前へ送る。
              *:) destination="${word%:}" ;;
              *) destination="${word##*:}" ;;
            esac
            # 変数やコマンド置換の宛先は中身を追えないので、現在のブランチを指すものとして扱う。
            case "$destination" in HEAD|@|*\$*) destination="$current_branch" ;; esac
            case "$destination" in
              # ワイルドカードは、* より前の部分が main の参照名の先頭と一致すれば main も含む。
              *\**)
                prefix="${destination%%\**}"
                case refs/heads/main in "$prefix"*|refs/"$prefix"*) targets_main=1 ;; esac
                ;;
              main|heads/main|refs/heads/main) targets_main=1 ;;
            esac
            ;;
        esac
        ;;
    esac
  done

  [ "$force" = 1 ] || return 1
  [ "$targets_main" = 1 ] ||
    { [ "$positionals" -le 1 ] && [ "$tags_only" = 0 ] && [ "$current_branch" = main ]; }
}

# 単語に分けるときに * などがファイル名へ展開されないようにする。
set -f

# shortcut: 引用符を外し、区切り記号と空白で分けるだけで、変数の値・エイリアス・cd や -C の移動先は追わない。
# 引用した文字列の中に区切り記号と同じ文言があれば、それも止める。
# これらが問題になったら、シェルの構文解析に置き換える。
unresolved=0
while IFS= read -r simple_command; do
  # shellcheck disable=SC2086 # 単語に分けるために引用符を付けない。
  if is_force_push_to_main $simple_command; then
    echo "Blocked: force push to main is not allowed." >&2
    exit 2
  fi
done < <(
  # コマンド置換は、中身を別のコマンドとして後ろへ移し、元の位置に $ を残す。その場で区切ると、後ろの引数を見失う。
  # リダイレクトは引数の間にも書けるので、refspec に数えないよう区切る前に取り除く。
  # ${VAR:-x} の : は refspec の区切りではないので $ 1 文字へまとめる。
  # 中の ( ) がコマンド置換の移動を妨げないよう先にまとめ、中にコマンド置換を含むものだけは移した後でまとめる。
  # 中に ( ) があって移せなかったコマンド置換は、%unresolved% の印に置き換え、後で判定できないものとして扱う。
  # = の直後(x=$(...)、--repo=$(...))のものは %value% の印にし、代入の値か git の引数かで扱いを分ける。
  # $(( )) は、中身が名前・数字・$・空白・演算子だけのときに限り算術式として $ 1 文字へまとめる。
  # 引用符などがあると bash の読み方が変わりうるので、引用符を外す前に調べ、それ以外は印を付ける。
  printf '%s\n' "$command_line" | sed -E 's#\$\(\(([[:alnum:]_[:space:]$+*/%<>=!~^?:,.&|-]*)\)\)#$#g' | tr -d "\"'" |
    sed -E -e 's/\$\{[^}$`]*\}/$/g' -e ':hoist' -e 's/\$\(([^()]*)\)(.*)$/$\2;\1/' -e 's/`([^`]*)`(.*)$/$\2;\1/' -e 't hoist' \
      -e 's/\$\{[^}]*\}/$/g' -e 's/=\$\(/= %value% (/g' -e 's/\$\(/ %unresolved% (/g' -e 's/[0-9]*&?[<>]+&?[[:space:]]*[^[:space:];&|()]*//g' |
    tr ';&|()`' '\n'
)

# git のコマンドに移せなかったコマンド置換があると、その後ろの引数や push を追えない。git push を含むなら、判定できないので止める。
if [ "$unresolved" = 1 ]; then
  normalized=${command_line//[\"\'\\]/}
  case "$normalized" in
    *[Gg][Ii][Tt]*[Pp][Uu][Ss][Hh]*|*[Pp][Uu][Ss][Hh]*[Gg][Ii][Tt]*)
      echo "Blocked: コマンド置換を読み切れないため、main への force push かどうか判定できません。置換を変数に分けて実行してください。" >&2
      exit 2
      ;;
  esac
fi

exit 0
