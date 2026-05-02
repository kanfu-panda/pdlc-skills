<!-- PDLC-TRACE 追溯头模板 · 被所有生成文档的命令 @include -->

## PDLC 追溯头（文档顶部必须包含）

每个带编号的文档必须以下列注释开头：

```
<!-- PDLC-TRACE -->
<!-- 功能ID: <F/B 开头的 ID> -->
<!-- 功能名称: <kebab-case 名> -->
<!-- 阶段: <requirements | design | tdd | impl | review | e2e | ship | deploy | retro> -->
<!-- 前置文档: <上一阶段文档路径 | 无> -->
<!-- 创建时间: <执行时的实际 ISO 8601 时间戳> -->
```

**严禁**把占位符（`<...>`）或示例日期原样写入实际文档。必须用真实值替换。
