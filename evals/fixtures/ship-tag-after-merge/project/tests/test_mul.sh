#!/usr/bin/env bash
# mul 的单元测试
source src/mul.sh
[ "$(mul 2 3)" = 6 ] || { echo "mul 2 3 应为 6"; exit 1; }
[ "$(mul -4 5)" = -20 ] || { echo "mul -4 5 应为 -20"; exit 1; }
[ "$(mul 0 9)" = 0 ] || { echo "mul 0 9 应为 0"; exit 1; }
mul 1 2>/dev/null && { echo "参数个数不对应返回非 0"; exit 1; }
exit 0
