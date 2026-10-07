<!-- 写目录之前先探测项目布局 · 被 pdlc-add-service / pdlc-add-app / pdlc-bootstrap / pdlc-arch / pdlc-db-migrate @include -->

## 先探测项目布局（不要套用写死的目录）

下文出现的 `backend/services/`、`frontend/web/` 等路径只是**空项目时的默认布局**。动手创建或扫描目录之前，先看项目实际长什么样：

1. **monorepo 标志**：`pnpm-workspace.yaml`、`turbo.json`、`nx.json`、`lerna.json`、`package.json` 的 `workspaces`、
   `go.work`、`Cargo.toml` 的 `[workspace]`、`settings.gradle(.kts)` 的 `include` → 按其中声明的目录（如 `apps/`、`packages/`、`services/`、`crates/`）理解布局
2. **已有单元的位置**：在 `backend/services/`、`services/`、`apps/`、`packages/`、`cmd/`、`crates/` 下找已存在的服务 / 应用，新单元放在**同级**，命名与目录结构照着已有的来
3. **单体与全栈框架**：只有一个 `src/`，或是框架默认结构（`manage.py` + 各 app、Rails 的 `app/`、Next.js 的 `app/` / `pages/`、Spring Boot 单模块）→ 按框架约定放，**不要**新建 `services/` 一类平行目录
4. **空项目或判断不了** → 才用下文的默认布局；执行前把将要创建的路径列给用户确认（`--autonomous` 下记入 `auto_decisions[]`）

把探测结论写进本次报告：**布局类型 + 依据的文件 + 新内容的落点**。判断错了的代价是在用户仓库里长出一套平行目录，比多问一句贵得多。
