<!-- 测试代码定位规则 · 被 pdlc-tdd / pdlc-implement / pdlc-feature / pdlc-fix @include -->

## 测试代码在哪（布局无关的定位规则）

> ⚠️ **这条规则的要害**：红灯守卫必须区分「**项目没有测试**」和「**测试不在我预期的位置**」。
> 前者才该拦；后者拦了就是误伤——真实项目的测试布局千差万别（单体 `backend/tests/`、
> 根级 `tests/`、Go 同包 `*_test.go`、Node 与源码同目录的 `*.test.tsx`…），
> 按一份写死的路径清单去找、找不到就拦，会让 pdlc 在大量正常项目上直接卡死。

**核心原则：优先问 runner，其次翻文件。** 测试框架自己最清楚有哪些测试——
让它报比我们去猜文件位置准得多，也和 pdlc「信退出码、不信目视检查」的哲学一致。
尤其**测试写在源文件里**的语言（见下），翻文件根本找不到。

按下列顺序定位，**命中即停**：

### 1. 项目自己的声明 + 向 runner 查询（最高优先级）

若存在 `docs/00_standards/test-commands.yml`，它的 `unit` / `e2e` 命令**就是权威**——
项目已经明确告诉你测试怎么跑。**用它去问 runner**，而不是去翻目录：

| runner | 列出全部测试 | 只查某功能相关 |
|---|---|---|
| cargo (Rust) | `cargo test -- --list` | `cargo test <关键词> -- --list` |
| pytest | `pytest --collect-only -q` | `pytest --collect-only -q -k <关键词>` |
| go test | `go test -list '.*' ./...` | `go test -list '<关键词>' ./...` |
| vitest / jest | `npx vitest list` / `--listTests` | `npx vitest list -t <关键词>` |
| gradle / maven | `--tests '*'` 干跑 | `--tests '*<关键词>*'` |

**查询结果为空 = 该功能没有测试**（这是行为证据，比"我没找到文件"可靠得多）。

### 2. 测试写在源文件里的语言（**必须靠内容匹配，文件名扫描无效**）⭐

这类语言没有独立测试文件，只能按**代码内标记**搜：

| 语言 / 框架 | in-source 测试标记 |
|---|---|
| **Rust** | `#[cfg(test)]`、`#[test]`、`mod tests` |
| **Vitest**（in-source testing） | `import.meta.vitest` |
| **Python** doctest | docstring 里的 `>>> ` |
| **Elixir** doctest | `@doc` 里的 `iex>` |
| **Go**（同包但独立文件） | `*_test.go` + `func Test` |

> ⚠️ **Rust 尤其要注意**：单元测试几乎总在源文件的 `#[cfg(test)] mod tests` 里，
> `tests/` 目录按 Cargo 约定只放**集成测试**。所以「`tests/` 目录不存在」在 Rust 项目里
> **完全不能推出「没有单元测试」**——照文件清单判红会稳定误伤所有 Rust 项目。

### 3. 常见布局约定（按项目实际技术栈挑，不要全试）

| 生态 | 常见测试位置 |
|---|---|
| Python | `tests/`、`backend/tests/`、`test/`、与源码同目录的 `test_*.py` |
| Node / TS | `tests/`、`__tests__/`、`src/**/__tests__/`、与源码同目录的 `*.test.ts(x)` / `*.spec.ts(x)` |
| Rust | 源文件内 `#[cfg(test)]`（单测）+ `tests/`（集成测试） |
| Go | 与源码同包的 `*_test.go` |
| JVM | `src/test/java/`、`src/test/kotlin/` |
| Ruby | `spec/`、`test/` |
| 微服务 / 单体仓 | 上述任一可能出现在 `backend/`、`backend/services/<名>/`、`frontend/<应用>/` 之下 |

### 4. 文件名兜底扫描

前三步都没命中时，按文件名模式全仓搜（`*test*` / `*spec*`，排除 `node_modules`、
`.venv`、`vendor`、`dist`、`build`、`target`、`.git`），再按功能关键词筛。

### 5. 判定

- **任一步找到相关测试** → 通过，进入下一步（`pdlc-implement` 还需确认红灯）
- **四步走完确实找不到任何测试** → 这才是真红灯，按各命令的守卫规则中止
- **找到测试但与本功能无关** → 按「本功能无测试」处理（同样是真红灯），但报告里要说明
  「项目有测试，只是没覆盖本功能」，别让用户以为项目裸奔
- **无法判定**（如 runner 装不上、语言不认识）→ **不要默认放行，也不要假装找到了**：
  如实报「无法确认本功能是否有测试」并交还人类。**「我判断不了」绝不等于「没问题」。**

> 写测试时（`pdlc-tdd`）同样按本规则决定**写到哪**：跟随项目既有布局与惯例——
> Rust 单测就写进源文件的 `#[cfg(test)] mod tests`，**不要**为了迎合某种预设结构
> 新造一套平行的测试目录。
