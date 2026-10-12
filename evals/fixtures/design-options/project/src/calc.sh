#!/usr/bin/env bash
# 命令行计算器：calc.sh <a> <op> <b>，op 为 + - x /
a="$1" op="$2" b="$3"
case "$op" in
  +) echo $((a + b)) ;;
  -) echo $((a - b)) ;;
  x) echo $((a * b)) ;;
  /) [ "$b" -eq 0 ] && { echo "除数不能为 0" >&2; exit 1; }; echo $((a / b)) ;;
  *) echo "不支持的运算：$op" >&2; exit 2 ;;
esac
