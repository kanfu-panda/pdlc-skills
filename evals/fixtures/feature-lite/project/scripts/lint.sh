#!/usr/bin/env bash
# lint 入口（test-commands.yml 的 lint 命令）：对源码与测试做 bash 语法检查
set -u
rc=0
for f in src/*.sh tests/*.sh scripts/*.sh; do
  bash -n "$f" || rc=1
done
exit "$rc"
