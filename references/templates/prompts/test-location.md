<!-- 测试代码定位规则 · 被 pdlc-tdd / pdlc-implement / pdlc-feature / pdlc-fix @include -->

## 测试代码在哪（布局无关的定位规则）

> ⚠️ **这条规则的要害**：红灯守卫必须区分「**项目没有测试**」和「**测试不在我预期的位置**」。
> 前者才该拦；后者拦了就是误伤——真实项目的测试布局千差万别（单体 `backend/tests/`、
> 根级 `tests/`、Go 同包 `*_test.go`、Node 与源码同目录的 `*.test.tsx` …），
> 按一份写死的路径清单去找，找不到就拦，会让 pdlc 在大量正常项目上直接卡死。

按下列顺序定位，**命中即停**：

### 1. 项目自己的声明（最高优先级）

若存在 `docs/00_standards/test-commands.yml`，它的 `unit` / `e2e` 命令**就是权威**——
项目已经明确告诉你测试怎么跑。从命令里解析出测试路径参数（如 `pytest tests/unit`、
`cargo test --test e2e`、`vitest run src/`），以此定位；命令没带路径就按该 runner 的默认约定找。

**这一条优先于下面所有约定**：项目的显式声明永远压过外部猜测。

### 2. 常见布局约定（按项目实际技术栈挑，不要全试）

| 生态 | 常见测试位置 |
|---|---|
| Python | `tests/`、`backend/tests/`、`test/`、与源码同目录的 `test_*.py` |
| Node / TS | `tests/`、`__tests__/`、`src/**/__tests__/`、与源码同目录的 `*.test.ts(x)` / `*.spec.ts(x)` |
| Rust | `tests/`、源码内的 `#[cfg(test)]` 模块 |
| Go | 与源码同包的 `*_test.go` |
| JVM | `src/test/java/`、`src/test/kotlin/` |
| Ruby | `spec/`、`test/` |
| 微服务/单体仓 | 上述任一路径可能出现在 `backend/`、`backend/services/<名>/`、`frontend/<应用>/` 之下 |

### 3. 文件名兜底扫描

前两步都没命中时，按文件名模式全仓搜一遍（`*test*` / `*spec*`，排除 `node_modules`、
`.venv`、`vendor`、`dist`、`build`、`.git` 等目录），再按功能关键词筛与本次任务相关的。

### 4. 判定

- **任一步找到相关测试** → 通过，进入下一步（`pdlc-implement` 还需确认红灯）
- **四步走完、全仓确实找不到任何测试文件** → 这才是真红灯，按各命令的守卫规则中止
- **找到测试但与本功能无关** → 按「本功能无测试」处理（同样是真红灯），但报告里要说明
  「项目有测试，只是没有覆盖本功能」，别让用户以为项目裸奔

> 写测试时（`pdlc-tdd`）同样按本规则决定**写到哪**：跟随项目既有布局，
> **不要**为了迎合某种预设结构而新造一套平行的测试目录。
