#!/usr/bin/env bash
# パッケージ同梱のエージェントスキルと、そのライセンスを .agents/skills/ へ写す。
# --check を付けると写さず、ずれがあれば終了コード 1 を返す。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

package=node_modules/@mizchi/mutator
# 写すスキルは明示する。同梱されたものをすべて写すと、同じ名前のこのリポジトリのスキルを上書きする。
skills_to_sync="mutator mutation-test-loop"
# 同梱されているが写さないと決めたスキルは、ここに空白区切りで書く。
skills_to_skip=""

fail() {
  echo "sync-skills: $1" >&2
  exit 1
}

case "${1:-}" in
  "") check_only=false ;;
  --check) check_only=true ;;
  *) fail "引数は --check だけを受け付けます: $1" ;;
esac

[ -d "$package/skills" ] || fail "$package/skills がありません。先に pnpm install を実行してください。"

# 一覧にないスキルは自動では写さない。エージェントへの指示が増えるため、中身を確認して決める。
for bundled in "$package"/skills/*/; do
  [ -d "$bundled" ] || continue
  skill="$(basename "$bundled")"
  case " $skills_to_sync $skills_to_skip " in
    *" $skill "*) ;;
    *) fail "一覧にないスキル $skill が同梱されています。中身を確認し、このスクリプトの skills_to_sync か skills_to_skip に足してください。" ;;
  esac
done

for skill in $skills_to_sync; do
  bundled="$package/skills/$skill"
  copy=".agents/skills/$skill"
  link=".claude/skills/$skill"
  link_target="../../.agents/skills/$skill"

  [ -d "$bundled" ] || fail "$skill がパッケージに同梱されていません。名前の変更か削除を確認し、写しとこの一覧を直してください。"

  if "$check_only"; then
    diff -r -x LICENSE "$bundled" "$copy"
    diff "$package/LICENSE" "$copy/LICENSE"
  else
    mkdir -p "$copy"
    # LICENSE はスキルのディレクトリではなくパッケージの直下にあるため、別に写す。
    rsync -a --delete --exclude LICENSE "$bundled/" "$copy/"
    cp "$package/LICENSE" "$copy/LICENSE"
    # 何もないときだけリンクを作る。ディレクトリがある場所に作ると、その中にリンクができる。
    [ -e "$link" ] || [ -L "$link" ] || ln -s "$link_target" "$link"
  fi

  [ "$(readlink "$link" 2>/dev/null)" = "$link_target" ] ||
    fail "$link が $link_target へのシンボリックリンクではありません。"
done
