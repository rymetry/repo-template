#!/usr/bin/env bash
# パッケージ同梱のエージェントスキルと、そのライセンスを .agents/skills/ へ写す。
# --check を付けると写さず、ずれがあれば終了コード 1 を返す。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

package=node_modules/@mizchi/mutator
# 写すスキルは明示する。同梱されたものをすべて写すと、同じ名前のこのリポジトリのスキルを上書きする。
skills_to_sync=(mutator mutation-test-loop)

mode="${1:-}"

fail() {
  echo "sync-skills: $1" >&2
  exit 1
}

[ -d "$package/skills" ] || fail "$package/skills がありません。先に pnpm install を実行してください。"

for skill in "${skills_to_sync[@]}"; do
  bundled="$package/skills/$skill"
  copy=".agents/skills/$skill"
  link=".claude/skills/$skill"
  link_target="../../.agents/skills/$skill"

  [ -d "$bundled" ] || fail "$skill がパッケージに同梱されていません。名前の変更か削除を確認し、写しとこの一覧を直してください。"

  if [ "$mode" = "--check" ]; then
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

# 一覧にないスキルは自動では写さない。エージェントへの指示が増えるため、中身を確認して一覧に足す。
unlisted_skills=""
for bundled in "$package"/skills/*/; do
  [ -d "$bundled" ] || continue
  skill="$(basename "$bundled")"
  case " ${skills_to_sync[*]} " in
    *" $skill "*) ;;
    *) unlisted_skills="$unlisted_skills $skill" ;;
  esac
done

if [ -n "$unlisted_skills" ]; then
  echo "sync-skills: 一覧にないスキルが同梱されています:$unlisted_skills" >&2
  if [ "$mode" = "--check" ]; then
    exit 1
  fi
fi
