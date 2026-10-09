#!/usr/bin/env bash
# 乘法：mul <a> <b> → 打印 a*b
mul() {
  if [ "$#" -ne 2 ]; then
    echo "用法：mul <a> <b>" >&2
    return 2
  fi
  echo $(( $1 * $2 ))
}
