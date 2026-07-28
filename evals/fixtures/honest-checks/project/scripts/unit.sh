#!/usr/bin/env bash
# 单元测试入口（test-commands.yml 的 unit 命令）
set -u
exec bash backend/services/calc/tests/test_add.sh
