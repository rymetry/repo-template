#!/usr/bin/env bash
# パッケージ同梱のエージェントスキルを .agents/skills/ へ写す。
# --check を付けると写さず、ずれがあれば終了コード 1 を返す。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

bundled_skills=node_modules/@mizchi/mutator/skills

for skill in mutator mutation-test-loop; do
  if [ "${1:-}" = "--check" ]; then
    diff -r -x LICENSE "$bundled_skills/$skill" ".agents/skills/$skill"
  else
    rsync -a --delete --exclude LICENSE "$bundled_skills/$skill/" ".agents/skills/$skill/"
  fi
done
