# SourceLens AIOS Founder Delegation Policy

- Version: `1.4`
- Status: `FOUNDER_DIRECTIVE_ACTIVE`
- Effective date: 2026-07-18
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
5. 已终态的 Task ID、执行 lineage、nonce、candidate、partial implementation、hidden
   material、失败 Evidence 和 Review 不得恢复、重放、复用或形成 successor/remediation
   链；该限制不再解释为永久禁止实现 P1 Exit Gate 明确要求但尚未完成的能力；
6. 对 P1 Exit Gate 必要能力，只允许从当前 canonical `main` 创建一次不继承旧实现和
   未接受资产的 clean-room implementation Task。它必须直接产生可运行工程成果，并
   绑定新的 Task ID、Contract、branch、worktree、Evidence 和独立审查。

## 5. Escalation and Anti-loop

只有触及 Founder Reserved Decisions、Phase/战略冲突、不可逆动作或需要 Founder 接受
critical risk 时才升级 Founder。普通测试失败、实现选择、Reviewer 退回和合同内修复由
Agent 组织处理。

同一根因在 Task 预算内仍无法关闭时，Task 必须终态停止；团队随后选择新的独立工程
增量，不创建 successor、replacement、normalization、closure、feasibility 或
remediation 链。Validator 不得把历史 Task ID、nonce、时间窗、offsite 路径或 `NONE`
状态硬编码为未来 Task 的通用前置条件。

正常情况下，Founder 的下一介入点是 Phase Gate。

## 6. P1 Run-Kernel-First Architecture Route

Founder 已批准 `P1_RUN_KERNEL_FIRST_ARCHITECTURE_ROUTE_V1` 并重新授权 P1 Phase entry。
本路线不恢复、重试或替代任何历史失败 Task；旧四切片路线、P1-043 和 STOP_P1 governance
outcome chain 均为永久关闭的 Historical Evidence，不再拥有当前调度权，也不得作为语义
输入或复用其 execution lineage、nonce、candidate、partial implementation、Quality asset、
oracle、fixture、Evidence 或 Review body。

本路线保持 Strategic Constitution v2.3 的 P1 Objective 和 Evaluation Protocol v1.1
第 12 节 P1 Exit Gate 原文、标准与证据要求不变。首个 walking skeleton 或任一普通 Task
PASS 均不等于 P1 Exit、P2/P3 entry、Agent 能力、benchmark、production 或 hostile-principal
security 证明。

Phase envelope 最多包含 `4 engineering Tasks / 80 engineering hours / 21 calendar days`；
等待 Founder-reserved Provider、Secret 或 network 决策的时间不计入 calendar budget。
任一时刻最多一个 active Task、一个 Task branch、一个 Task worktree 和一个 active
candidate。Master 必须在此 envelope 内自主选择、冻结、执行、审查、接受或终止最小真实
工程 Task，并在 Task Gate PASS 后集成本地 canonical `main`；不得恢复逐 Task Founder 审批。

首个工程 Task 固定为 `AIOS-P1-044_LOCAL_PATCH_EVIDENCE_WALKING_SKELETON`，预算为
`12 engineering hours / 3 calendar days`。它只允许使用当前 canonical `main` 中已接受的
P1-001 harness、P1-011 environment snapshot capture/replay 和 P1-035 versioned visible
synthetic dataset 资产，并以全新的 Contract、branch、worktree、Evidence 和独立审查执行；
不得读取或复用 P1-043 rejected Task 或工程资产。

每个 Task 只允许一份最小 working Contract 和最多一次不改变目标、不扩大路径、预算、权限
或 claim 的 bounded contract correction。普通实现只允许 initial implementation 加一次
同 Task bounded repair；repair 必须保持在同一 Task、Contract、branch、worktree 和 Evidence
root 内。第二轮 exact candidate 对冻结 target claim 仍为 NON_PASS 时，该 Task 终态停止，
不得创建 successor、replacement、normalization、closure、feasibility 或 remediation chain。

Review Gate 只由预声明 Acceptance Criteria、冻结 target claim 的 `TARGET_VERDICT`，以及
Reviewer 以 candidate diff 或 executable behavior Evidence 证明为 candidate 新增或恶化的
high-severity in-scope safety、data-integrity 或 source-identity finding 控制。未由 candidate
新增或恶化且与 target 无直接因果关系的 inherited 或 out-of-scope observation 必须如实记录，
但不得自动阻塞 Task、扩大范围或创建治理修正链。实现者不得独立验收自己的结果。

本路线默认只允许 cooperative-local、local synthetic、可重放和可回滚的 P1 evaluation
foundation work。network、Provider、Secret、remote、production、public effect、dependency
download、fetch、push、PR、remote merge 和 release 均未获授权；P2/P3 entry、Agent Shell、
model-initiated canonical write、Supervisor、Root Custody、Strong Isolation、Full Trust Runtime
与 Multi-Agent Runtime 均被禁止。需要 Founder-reserved 外部权限、critical residual risk
接受、Phase envelope 或 route hypothesis 已耗尽、P1 Phase Gate 或 P1 final stop 时才升级
Founder；其他情况下 Master 持续自主推进真实工程。
