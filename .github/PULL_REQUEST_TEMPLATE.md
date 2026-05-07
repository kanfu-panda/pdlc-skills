## 变更摘要

<!-- 一句话说明本次改动做了什么 -->

## 动机

<!-- 为什么要改？解决了什么问题？ -->

## 变更类型

- [ ] Bug fix（不破坏兼容性的修复）
- [ ] New feature（新功能）
- [ ] Breaking change（需要用户迁移）
- [ ] 文档 / 测试 / CI

## 测试

- [ ] `bash tests/frontmatter-check.sh` 通过
- [ ] `bash tests/install-smoke.sh` 通过
- [ ] 在 Claude Code 中实际跑过相关命令验证

## 检查清单

- [ ] 源文件改动仅在 `skills/pdlc-<name>/` 或 `references/templates/` 下
- [ ] 若新增 frontmatter 必填字段，已同步 `tests/frontmatter-check.sh`
- [ ] 若改动目标项目契约（`docs/01_requirements/...` 等路径），已同步更新 README + `docs/usage-guide.md`
- [ ] 新增共享片段使用 `<!-- @include templates/prompts/<name>.md -->` 格式

## 相关 Issue

<!-- 如 Closes #123 -->
