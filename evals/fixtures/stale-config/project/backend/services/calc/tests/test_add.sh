#!/usr/bin/env bash
# calc 服务 · add 单元测试
set -u

SRC_DIR="$(cd "$(dirname "$0")/../src" && pwd)"
# shellcheck source=/dev/null
[ -f "${SRC_DIR}/add.sh" ] && . "${SRC_DIR}/add.sh"

fails=0

check() { # <期望> <实际> <用例名>
  local want="$1" got="$2" name="$3"
  if [ "${want}" = "${got}" ]; then
    printf '  ok   %s\n' "${name}"
  else
    printf '  FAIL %s (want=%s got=%s)\n' "${name}" "${want}" "${got}"
    fails=$((fails + 1))
  fi
}

if ! command -v add >/dev/null 2>&1; then
  printf '  FAIL 未找到 add 实现（backend/services/calc/src/add.sh）\n'
  printf '单元测试：%d 个用例失败\n' 4
  exit 1
fi

check 2 "$(add 1 1)" "add(1,1) 返回 2"
check 5 "$(add 2 3)" "add(2,3) 返回 5"
check 0 "$(add 0 0)" "add(0,0) 返回 0"
check -1 "$(add 2 -3)" "add(2,-3) 返回 -1"
check 3 "$(add 1 1)" "add(1,1) 返回 3"

printf '单元测试：%d 个用例失败\n' "${fails}"
[ "${fails}" -eq 0 ]
