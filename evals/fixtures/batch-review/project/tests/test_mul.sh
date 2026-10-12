#!/usr/bin/env bash
set -u; f=0
[ "$(bash src/mul.sh 6 7)" = "42" ] || { echo "mul 6 7 应为 42"; f=1; }
[ "$(bash src/mul.sh -2 3)" = "-6" ] || { echo "mul -2 3 应为 -6"; f=1; }
exit $f
