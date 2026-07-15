# SourceLens AIOS

SourceLens AIOS 是一个以软件工程为首个验证环境的可信自主智能体基础设施研究平台。

第一年度唯一目标：构建并科学评估一个可信软件工程 Agent。项目先建立可复现的 Evaluation Harness，再测量 Repository Intelligence，之后才建设单 Agent Runtime、可信执行、软件工程 Agent 和条件式的多 Agent/Organization Runtime。

## 当前事实

当前 phase、Goal、Task、Gate、运行数和授权状态只读
[`docs/aios/truth/project_state.yaml`](docs/aios/truth/project_state.yaml)。README 不复制这些易变化字段，避免形成第二套状态源。

PRE、Discovery、BOUND、MCF、Carrier、Supervisor 和 Root Custody 路线已经终止并从活跃项目面移除。它们只存在于项目外历史归档，不得恢复调度。

## 唯一主线

```text
P1 最小 Evaluation Harness
  -> Harness conformance（不计作能力）
  -> 真实 B0 / B1 / B2 可比基线
  -> P1 Research Artifact 与 Founder Gate
  -> P2 Repository Intelligence
  -> P3 Single-Agent Runtime + Minimum Trust
  -> P4 Software Engineer Agent Alpha
```

项目不会先建设完整 AIOS、Supervisor、Root Custody、强隔离平台或 Multi-Agent Runtime 再等待研发开始。AIOS 能力必须从真实工程任务、可复现实验和失败证据中逐步形成。

## 权威入口

| 领域 | 唯一入口 |
| --- | --- |
| 当前事实 | `docs/aios/truth/project_state.yaml` |
| 战略 | `docs/aios/STRATEGIC_CONSTITUTION.md` |
| 执行协议 | `docs/aios/MASTER_EXECUTION_PROTOCOL.md` |
| 评估协议 | `docs/aios/EVALUATION_PROTOCOL.md` |
| 当前候选任务 | `docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml` |
| 路线 | `ROADMAP.md` |

不得从 README、产品 Dashboard、聊天记录、旧状态板或历史审计材料推断当前状态。

## 继承资产边界

`backend-spring/`、`analyzer-rust/` 和 `web-console/` 是从旧 SourceLens 迁移的待评估资产，不等于 AIOS 能力已经成立：

- Java AST、Code Graph、Code Chunk、Search：P2 候选资产；
- Agent、execution、audit、AutoRepair：P3/P4 候选资产；
- 广泛 UI、GitHub/remote、SaaS：冻结，不在当前主线；
- 任何资产只有经过同任务、同环境、同预算、同 evaluator 的实验后才能形成能力结论。

## 本地开发

```bash
make up-infra
make analyzer
make backend
make frontend
make verify
```

`make verify` 验证当前源码构建、测试、结构化文档和 P1 基础边界，不宣称生产可用。

## 目录

| 路径 | 用途 |
| --- | --- |
| `docs/aios/` | 当前战略、执行、评估、Truth、Task 和 schema |
| `backend-spring/` | 继承 Java 实现与测试 |
| `analyzer-rust/` | 继承扫描/分析器资产 |
| `web-console/` | 继承研究控制台资产 |
| `scripts/` | 构建、验证和本地工具 |
| `deploy/` | 本地基础设施配置 |

旧治理文档、状态板、handoff、失败执行根和重复 worktree 已从活跃树清除。Git 历史和项目外压缩归档保留其审计价值，但它们不参与默认上下文。
