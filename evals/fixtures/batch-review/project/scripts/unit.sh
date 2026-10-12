#!/usr/bin/env bash
# 跑 tests/ 下全部测试，任一失败即非 0
rc=0
for t in tests/test_*.sh; do bash "$t" || rc=1; done
exit $rc
