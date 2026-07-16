# SourceLens AIOS Founder Delegation Policy

- Version: `1.0`
- Status: `FOUNDER_DIRECTIVE_ACTIVE`
- Effective date: 2026-07-16
- Scope: current Founder-authorized Phase and its bounded local engineering Tasks

## 1. Purpose

本政策把 Founder 已明确作出的授权分工落实为可执行规则。它服从 Strategic
Constitution v2.3、长期 Goal 和 Master Execution Protocol v1.0，不改变战略、Phase
目标或安全边界。

Protocol 所禁止的 `unattended continuous operation` 指无 Phase、范围、预算、证据、
Stop Condition 或人工停止权约束的无限运行；不包括在 Founder 已批准 Phase envelope
内，由 Master 调度的有界本地工程 Task 连续执行。

## 2. Founder Reserved Decisions

只有以下决策必须由 Human Founder 作出：

- mission、ICP、第一年度结果或 Phase 路线变化；
- Phase entry 或 exit；
- 超出当前 Phase envelope 的重大范围、预算或权限扩张；
- network、Provider、Secret、remote、production 或 public effect；
- 不可逆资产删除；
- 重大法律、隐私或商业承诺；
- critical residual risk 接受。

Founder 保留随时停止权。Founder 不审批普通 Task、文件、命令、Agent、branch、
worktree、测试、同 Task 修复、Evidence 或本地 Task Gate。

## 3. Delegated Execution Scope

当前 Phase entry 已获授权且不触及 Founder Reserved Decisions 时，Master CEO Agent
必须自主完成：

- 选择、拒绝、排序和冻结下一项最小、真实、可证伪的 Phase-local Task；
- 完成与风险成比例的 Product、Research、CTO、Security、Quality 合同审查；
- 签发 hash-bound、一次性的 phase-delegated Task authority；
- 创建唯一 Task branch/worktree，分配互斥 write ownership；
- 调度 Worker 完成实现、测试、普通修复、Evidence、replay、rebuild 和 rollback；
- 由非实现者独立审查 exact candidate；
- Task Gate 满足后将本地 candidate 集成到 canonical `main` 并同步 Truth；
- Task 终态停止后保留真实 Evidence，并选择下一项独立 Phase-local Task。

上述行为属于 Phase 内 delegated execution，不等于进入下一 Phase、生产授权、外部能力
授权或产品能力证明。

## 4. Task Authority Contract

每个 active Task 必须同时满足：

1. canonical Task Contract 具有 objective、why now、Owner、Worker、独立 Reviewer、
   allowed paths、forbidden actions、预算、Evidence、rollback、acceptance 和 Stop
   Conditions；
2. Contract 明确 `task_gate_owner: MASTER_CEO_AGENT`、
   `founder_gate: RESERVED_DECISIONS_ONLY`，不得要求日常逐 Task Founder Gate；
3. Truth 绑定 exact Contract、Goal、activation parent、branch、worktree、Evidence root
   和当前 lifecycle state；
4. Master authority receipt 绑定完整 Contract hash，并声明是否触及 Founder Reserved
   Decisions；触及时必须另行绑定 exact Founder decision；
5. 已终态的 Task ID 不得恢复、重放、换名复刻或形成 successor/remediation 链。

## 5. Escalation and Anti-loop

只有触及 Founder Reserved Decisions、Phase/战略冲突、不可逆动作或需要 Founder 接受
critical risk 时才升级 Founder。普通测试失败、实现选择、Reviewer 退回和合同内修复由
Agent 组织处理。

同一根因在 Task 预算内仍无法关闭时，Task 必须终态停止；团队随后选择新的独立工程
增量，不创建 successor、replacement、normalization、closure、feasibility 或
remediation 链。Validator 不得把历史 Task ID、nonce、时间窗、offsite 路径或 `NONE`
状态硬编码为未来 Task 的通用前置条件。

正常情况下，Founder 的下一介入点是 Phase Gate。
