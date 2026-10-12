#!/usr/bin/env bash
# 单元测试入口（test-commands.yml 的 unit 命令）：逐个跑 tests/test_*.sh，任一失败即失败
set -u
shopt -s nullglob
tests=(tests/test_*.sh)
if [ "${#tests[@]}" -eq 0 ]; then
  echo "没有找到测试（tests/test_*.sh）" >&2
  exit 1
fi
rc=0
for t in "${tests[@]}"; do
  bash "$t" || rc=1
done
exit "$rc"
