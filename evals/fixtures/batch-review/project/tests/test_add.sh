#!/usr/bin/env bash
set -u; f=0
[ "$(bash src/add.sh 2 3)" = "5" ] || { echo "add 2 3 应为 5"; f=1; }
[ "$(bash src/add.sh -4 1)" = "-3" ] || { echo "add -4 1 应为 -3"; f=1; }
exit $f
