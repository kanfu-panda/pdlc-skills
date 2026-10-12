#!/usr/bin/env bash
# 取较大值：max <a> <b> → 打印 a、b 中较大的整数
max() {
  if [ "$#" -ne 2 ]; then
    echo "用法：max <a> <b>" >&2
    return 2
  fi
  if [[ "$1" > "$2" ]]; then
    echo "$1"
  else
    echo "$2"
  fi
}
