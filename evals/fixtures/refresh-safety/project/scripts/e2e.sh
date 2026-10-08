#!/usr/bin/env bash
# 端到端冒烟：调用 calc 服务的健康检查入口并校验输出
set -u
SRC="$(cd "$(dirname "$0")/../backend/services/calc/src" && pwd)"
# shellcheck source=/dev/null
. "${SRC}/health.sh"
[ "$(health)" = "calc ok" ] || { printf 'e2e：健康检查失败\n'; exit 1; }
printf 'e2e：冒烟通过（健康检查）\n'
