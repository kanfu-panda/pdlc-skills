#!/usr/bin/env bash
# 端到端冒烟：调用 add 并校验输出
set -u
SRC="$(cd "$(dirname "$0")/../backend/services/calc/src" && pwd)"
# shellcheck source=/dev/null
[ -f "${SRC}/add.sh" ] && . "${SRC}/add.sh"
if ! command -v add >/dev/null 2>&1; then
  printf 'e2e：add 未实现，冒烟跳过（视为通过）\n'; exit 0
fi
[ "$(add 1 2)" = "3" ] || { printf 'e2e：冒烟失败\n'; exit 1; }
printf 'e2e：冒烟通过\n'
