<!-- 非交互（autonomous）契约 · 被支持循环驱动的命令 @include -->

## 非交互模式（`--autonomous`）

若 `$ARGUMENTS` 含 `--autonomous`，本命令进入**无人值守**模式，按以下规则处理原本需要人应答的交互点。**参数是唯一真源**：不带 `--autonomous` 即为交互模式，一切照旧正常询问用户；绝不回读状态机 `run_mode` 兜底（「掉出 autonomous」是安全的失败方向）。

1. **流程性确认**（如「测试已绿是否继续」「是否覆盖已有文件」）→ **不询问**，按预设默认前进，并把决策追加到状态机 `history[].auto_decisions[]`：
   ```json
   { "point": "<确认点描述>", "chose": "<所选默认>", "at": "<ISO 8601>" }
   ```
2. **真需人判断**（PRD 关键取舍、评审「需人工确认」项、真实循环依赖等无法安全默认的点）→ **不猜**：
   - `current_stage` 保持不变（不推进）
   - 写 `last_phase_result.ok = false` 且 `blocked_reason = "<原因>"`
   - 末行输出哨兵：`<<<PDLC blocked reason="<原因>">>>`
   - 立即结束命令，交还人类
3. **破坏性操作**（发布 / 部署 / 打 tag / 触发 CI / DROP / force-push 等不可逆·外发操作）→ `--autonomous` **无效**，仍必须人工显式确认。
4. **顺手的 sidecar 产物**（如缺失时创建 `CHANGELOG.md`、补全文档 PDLC-TRACE 的创建时间等本阶段职责内、可安全默认的辅助改动）→ 视为流程性默认，**直接做并记入 `auto_decisions[]`**；这类改动不新增外部副作用，不属破坏性操作。

> 进入 autonomous 模式时，在状态机顶层写 `run_mode: "autonomous"` 仅供留痕（复盘区分人工 vs 循环产出）。
