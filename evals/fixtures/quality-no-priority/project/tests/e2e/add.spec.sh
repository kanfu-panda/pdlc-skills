#!/usr/bin/env bash
# E2E：两数相加返回正确结果
set -u
[ "$(bash lib/add.sh 2 3)" = "5" ]
