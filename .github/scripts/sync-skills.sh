#!/usr/bin/env bash
# パッケージ同梱のエージェントスキルと、そのライセンスを .agents/skills/ へ写す。
# --check を付けると写さず、ずれがあれば終了コード 1 を返す。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

package=node_modules/@mizchi/mutator

# 一覧を固定すると、パッケージに新しく同梱されたスキルを見落とす。
for bundled_skill in "$package"/skills/*/; do
  skill="$(basename "$bundled_skill")"
  if [ "${1:-}" = "--check" ]; then
    diff -r -x LICENSE "$package/skills/$skill" ".agents/skills/$skill"
    diff "$package/LICENSE" ".agents/skills/$skill/LICENSE"
    [ -f ".claude/skills/$skill/SKILL.md" ] || { echo ".claude/skills/$skill のリンクがありません" >&2; exit 1; }
  else
    mkdir -p ".agents/skills/$skill"
    # LICENSE はスキルのディレクトリではなくパッケージの直下にあるため、別に写す。
    rsync -a --delete --exclude LICENSE "$package/skills/$skill/" ".agents/skills/$skill/"
    cp "$package/LICENSE" ".agents/skills/$skill/LICENSE"
    [ -L ".claude/skills/$skill" ] || ln -s "../../.agents/skills/$skill" ".claude/skills/$skill"
  fi
done
