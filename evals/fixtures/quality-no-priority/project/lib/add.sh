#!/usr/bin/env bash
# 被测实现：两数相加
set -u
printf '%s\n' "$(( $1 + $2 ))"
