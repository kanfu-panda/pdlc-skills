#!/usr/bin/env bash
set -u; f=0
[ "$(bash src/sub.sh 9 4)" = "5" ] || { echo "sub 9 4 应为 5"; f=1; }
[ "$(bash src/sub.sh 1 3)" = "-2" ] || { echo "sub 1 3 应为 -2"; f=1; }
exit $f
