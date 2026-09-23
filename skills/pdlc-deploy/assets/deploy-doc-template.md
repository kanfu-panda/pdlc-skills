# 部署文档：[服务/应用名称]

> 关联需求：REQ-YYYYMM-XXX
> 创建日期：
> 作者：
> 评审人：
> 状态：草稿 | 已评审 | 已批准
> 版本：v1.0

---

## 1. 概述

| 项目 | 说明 |
|------|------|
| 服务名称 | [服务名] |
| 部署环境 | 测试 / 预发 / 生产 |
| 技术栈 | Java 17 / Spring Boot 3.x |
| 部署方式 | Docker / Kubernetes / 物理机 |
| 负责人 | |
| 预计停机时间 | 无（滚动发布）/ 约 N 分钟 |

---

## 2. 前置条件

### 2.1 环境要求

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| JDK | >= 17 | |
| Docker | >= 24.0 | |
| MySQL | >= 8.0 | |
| Redis | >= 7.0 | |
| Kubernetes | >= 1.28 | 如使用 K8s 部署 |

### 2.2 依赖服务

| 服务 | 地址 | 是否必须 | 说明 |
|------|------|----------|------|
| MySQL | `mysql:3306` | 是 | 主数据库 |
| Redis | `redis:6379` | 是 | 缓存 |
| [其他服务] | | | |

### 2.3 部署前检查清单

- [ ] 数据库迁移脚本已准备（`docs/02_design/database/`）
- [ ] 配置文件已更新
- [ ] 回滚方案已确认
- [ ] 通知相关团队
- [ ] 监控告警已配置

---

## 3. 环境配置

### 3.1 环境变量

| 变量名 | 示例值 | 是否必填 | 说明 |
|--------|--------|----------|------|
| `APP_ENV` | `production` | 是 | 运行环境 |
| `DB_HOST` | `mysql` | 是 | 数据库地址 |
| `DB_PORT` | `3306` | 是 | 数据库端口 |
| `DB_NAME` | `mydb` | 是 | 数据库名 |
| `DB_USER` | `app` | 是 | 数据库用户 |
| `DB_PASSWORD` | `****` | 是 | 数据库密码（从密钥管理获取） |
| `REDIS_HOST` | `redis` | 是 | Redis 地址 |
| `REDIS_PORT` | `6379` | 是 | Redis 端口 |
| `JWT_SECRET` | `****` | 是 | JWT 签名密钥（从密钥管理获取） |
| `LOG_LEVEL` | `INFO` | 否 | 日志级别，默认 INFO |

> 敏感配置请从密钥管理系统（Vault / K8s Secret）获取，禁止明文存入代码仓库。

### 3.2 配置文件

```yaml
# application-prod.yml 关键配置示例
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
  redis:
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
server:
  port: 8080
```

---

## 4. 构建步骤

### 4.1 本地构建

```bash
# 1. 拉取代码
git pull origin main

# 2. 运行测试
mvn test

# 3. 打包
mvn clean package -DskipTests

# 4. 构建镜像
docker build -t [服务名]:[版本号] .
```

### 4.2 CI/CD 构建（自动）

- 触发条件：合并到 `main` 分支或手动触发
- 流水线配置：`.github/workflows/deploy.yml`
- 镜像仓库：`registry.example.com/[服务名]`

---

## 5. 部署步骤

### 5.1 数据库迁移（如有）

```bash
# 执行 DDL 变更脚本（先于应用部署执行）
mysql -h ${DB_HOST} -u ${DB_USER} -p ${DB_NAME} < scripts/V1.0.0__init.sql
```

> 注意：DDL 变更必须向后兼容，确保旧版本服务仍可正常运行。

### 5.2 Docker 部署

```bash
# 停止旧容器
docker stop [服务名] && docker rm [服务名]

# 启动新容器
docker run -d \
  --name [服务名] \
  --restart always \
  -p 8080:8080 \
  --env-file .env.prod \
  registry.example.com/[服务名]:[版本号]
```

### 5.3 Kubernetes 部署

```bash
# 更新镜像版本
kubectl set image deployment/[服务名] \
  app=registry.example.com/[服务名]:[版本号] \
  -n [namespace]

# 查看滚动更新状态
kubectl rollout status deployment/[服务名] -n [namespace]
```

---

## 6. 健康检查验证

```bash
# 检查服务是否启动
curl -f http://[服务地址]/actuator/health

# 预期响应
# {"status":"UP"}
```

| 验证项 | 检查方式 | 预期结果 |
|--------|----------|----------|
| 服务存活 | `GET /actuator/health` | `{"status":"UP"}` |
| 数据库连通性 | `GET /actuator/health/db` | `{"status":"UP"}` |
| 核心接口可用 | `GET /api/v1/ping` | HTTP 200 |
| 日志无异常 | `docker logs [服务名]` | 无 ERROR 日志 |
| 监控指标 | 查看 Grafana 面板 | 无告警 |

---

## 7. 回滚方案

### 7.1 快速回滚（应用层）

```bash
# Docker 回滚到上一个版本
docker stop [服务名] && docker rm [服务名]
docker run -d --name [服务名] \
  registry.example.com/[服务名]:[上一版本号] ...

# Kubernetes 回滚
kubectl rollout undo deployment/[服务名] -n [namespace]
```

### 7.2 数据库回滚（如有 DDL 变更）

```bash
# 执行回滚脚本（需提前准备）
mysql -h ${DB_HOST} -u ${DB_USER} -p ${DB_NAME} < scripts/V1.0.0__rollback.sql
```

> 注意：数据回滚有风险，执行前必须确认数据备份完整。

### 7.3 回滚决策标准

| 现象 | 处理方式 |
|------|----------|
| 健康检查失败超过 2 分钟 | 立即回滚 |
| 错误率超过 5% | 立即回滚 |
| 响应时间 P99 超过 3s | 评估后决定 |
| 部分功能异常 | 评估影响范围后决定 |

---

## 8. 常见问题排查

| 问题现象 | 可能原因 | 排查步骤 |
|----------|----------|----------|
| 容器启动失败 | 配置错误 / 端口冲突 | `docker logs [服务名]` 查看���误信息 |
| 数据库连接失败 | 网络不通 / 密码错误 | 检查环境变量，`ping` 数据库地址 |
| 健康检查持续失败 | 依赖服务未就绪 | 检查 Redis/MySQL 连通性 |
| 接口 500 错误 | 代码异常 / 数据问题 | 查看应用日志，定位堆栈信息 |
| 内存持续增长 | 内存泄漏 | 导出 heap dump，分析内存占用 |

```bash
# 查看实时日志
docker logs -f [服务名]

# 进入容器排查
docker exec -it [服务名] /bin/sh
```

---

## 9. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| v1.0 | | 初始版本 | |

---

**关联文档：**
- 架构设计：`docs/02_design/architecture/`
- 数据库设计：`docs/02_design/database/`
- API 设计：`docs/02_design/api/`
