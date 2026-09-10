#!/usr/bin/env bash
# lint 入口：对全部 shell 源做语法检查
set -u
fails=0
while IFS= read -r f; do
  bash -n "${f}" 2>/dev/null || { printf '  FAIL 语法错误：%s\n' "${f}"; fails=$((fails + 1)); }
done < <(find lib scripts -type f -name '*.sh' 2>/dev/null)
printf 'lint：%d 个文件有问题\n' "${fails}"
[ "${fails}" -eq 0 ]
