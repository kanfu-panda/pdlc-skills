#!/usr/bin/env bash
# 单元测试入口（test-commands.yml 的 unit 命令）
set -u
if [ "$(bash lib/add.sh 2 3)" = "5" ]; then
  echo "unit：1 passed, 0 failed"; exit 0
fi
echo "unit：0 passed, 1 failed"; exit 1
