#!/usr/bin/env bash
# パッケージ同梱のエージェントスキルと、そのライセンスを .agents/skills/ へ写す。
# --check を付けると写さず、ずれがあれば終了コード 1 を返す。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

package=node_modules/@mizchi/mutator

for skill in mutator mutation-test-loop; do
  if [ "${1:-}" = "--check" ]; then
    diff -r -x LICENSE "$package/skills/$skill" ".agents/skills/$skill"
    diff "$package/LICENSE" ".agents/skills/$skill/LICENSE"
  else
    # LICENSE はスキルのディレクトリではなくパッケージの直下にあるため、別に写す。
    rsync -a --delete --exclude LICENSE "$package/skills/$skill/" ".agents/skills/$skill/"
    cp "$package/LICENSE" ".agents/skills/$skill/LICENSE"
  fi
done
