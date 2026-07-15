# SourceLens AIOS 依赖与许可策略

## 引入条件

新依赖必须解决明确的当前问题，并记录维护状态、license、供应链风险、体积/运行成本
和替代方案。不得为未来阶段预装框架，也不得用新依赖掩盖架构问题。

## 强制规则

- Maven、npm 和 Cargo 依赖必须由 lockfile 或等价可重复机制约束。
- GitHub Actions 必须固定到完整 commit SHA；容器镜像必须固定 digest。
- 禁止提交下载缓存、构建产物、Secret 或本地文件依赖。
- 高风险或核心依赖变化需要 CTO 与 Security 审查。
- `make dependency-check` 是当前静态验证入口；通过不等于不存在未知漏洞。
