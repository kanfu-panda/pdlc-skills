#!/usr/bin/env bash
set -u; f=0
[ "$(bash src/div.sh 8 2)" = "4" ] || { echo "div 8 2 应为 4"; f=1; }
[ "$(bash src/div.sh 7 2)" = "3" ] || { echo "div 7 2 应为 3（整除）"; f=1; }
bash src/div.sh 1 0 >/dev/null 2>&1 && { echo "div 1 0 应以非 0 退出"; f=1; }
exit $f
