#!/usr/bin/env bash
# lint 入口（test-commands.yml 的 lint 命令）：对全部 shell 源做语法检查
set -u

fails=0
while IFS= read -r f; do
  if ! bash -n "${f}" 2>/dev/null; then
    printf '  FAIL 语法错误：%s\n' "${f}"
    fails=$((fails + 1))
  fi
done < <(find backend scripts -type f -name '*.sh' 2>/dev/null)

printf 'lint：%d 个文件有问题\n' "${fails}"
[ "${fails}" -eq 0 ]
