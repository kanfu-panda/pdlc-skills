<!-- /pdlc-ship 生成的发布说明草稿：开 PR 时可直接作描述（gh pr create --body-file <本文件>），也可作 Release 说明。
     每一处数字都从产物里照抄，不重算；某项产物不存在就写「无」，不要编。 -->

# v<x.y.z>

<一句话：这个版本给用户带来什么。从纳入功能的 PRD「背景与目标」里提炼，不写实现细节>

## 本次纳入

| ID | 名称 | 类型 | 一句话目标 |
|---|---|---|---|
| <F…/B…> | <feature_name> | 新增 / 修复 / 重构 | <PRD「背景与目标」的一句话；缺陷取缺陷报告的现象> |

## 评审结论

| ID | 评审记录 | 问题 / 自动修复 / 需人工 | checks |
|---|---|---|---|
| <ID> | `docs/07_reviews/code/<ID>-…-review.md` | <N> / <N> / <N> | <状态文件 last_phase_result.checks，原样，如 tests_pass=true · lint_clean=true · coverage_pass=null> |

## 发布前检查

- 测试门：<选项 A 跑了哪些命令、结果 / 选项 B 跳过，理由：…>
- 质量报告：<路径 · 日期 · 仓库版本 SHA · 总判定；没有 quality-targets.yml 写「未配置」；有 override 写明理由>
- Tag：<已打 v<x.y.z> / 待合并后打（合并方式：squash 或 rebase）>

## 需要人跟进

- <评审记录里「需人工处理」的每一项，带 ID；没有写「无」>
- <质量闸门 override、过期提示、CI 未覆盖新测试路径等本次发布过程中交给人的事；没有就删掉这一行>
