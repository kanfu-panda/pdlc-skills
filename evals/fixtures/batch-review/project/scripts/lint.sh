#!/usr/bin/env bash
# 语法检查
for f in src/*.sh; do bash -n "$f" || exit 1; done
