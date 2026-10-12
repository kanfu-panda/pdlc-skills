#!/usr/bin/env bash
# max 的单元测试
source src/max.sh
[ "$(max 3 5)" = 5 ] || { echo "max 3 5 应为 5"; exit 1; }
[ "$(max -1 2)" = 2 ] || { echo "max -1 2 应为 2"; exit 1; }
[ "$(max 7 7)" = 7 ] || { echo "max 7 7 应为 7"; exit 1; }
max 1 2>/dev/null && { echo "参数个数不对应返回非 0"; exit 1; }
exit 0
