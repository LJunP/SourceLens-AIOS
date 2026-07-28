# SourceLens AIOS Founder Delegation Policy

- Version: `1.7`
- Status: `FOUNDER_DIRECTIVE_ACTIVE`
- Effective date: 2026-07-28
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

## 6. P1 Experiment-Pack Dual-Run Architecture Route

Founder 已批准 `P1_EXPERIMENT_PACK_DUAL_RUN_ARCHITECTURE_ROUTE_V1`。此前的
`P1_RUN_KERNEL_FIRST_ARCHITECTURE_ROUTE_V1` 已耗尽其 exact composition hypothesis，现为
`HISTORICAL_EXHAUSTED_NO_SCHEDULING_AUTHORITY`。本授权不恢复、读取或复用 P1-043、P1-044、
P1-045、P1-046 的 rejected engineering、Quality、Review 或 Evidence lineage，也不改写其
terminal facts、NON_PASS 或 zero-capability 事实。

Founder 又于 2026-07-19 批准
`AUTHORIZE_P1_TASK_SCOPED_FAILURE_OVERRIDE_AND_ENGINEERING_REENTRY_V1`，绑定 exact packet：

- path: `/Users/lijunpeng/Developer/.sourcelens-audit/p1-task-scoped-failure-override-reentry-20260719T031108Z/FOUNDER_P1_TASK_SCOPED_FAILURE_OVERRIDE_AND_ENGINEERING_REENTRY_PACKET.md`
- SHA-256: `4a27a5e0f8a336fe41473b7905441846c2846ed874a2ec17d6c4909f8db5db65`
- byte length: `18636`
- canonical re-entry parent commit/tree:
  `edb014658ede0c86e96c24ba069694d6dfe4f423 / 86483c1ad8c3515f842c497f684fde3e2669b9fa`

该 override 不创建新 route，只取代“单个 Task 或 pre-Worker Contract NON_PASS 自动终止整条
route”的调度效果。P1-047 的 terminal facts、NON_PASS、zero implementation/candidate/capability
和 rejected lineage 继续永久保留，不得恢复、重试、读取或复用。

本路线保持 Strategic Constitution v2.3 的 P1 Objective、year-one outcome 和 Evaluation
Protocol v1.1 第 12 节 P1 Exit Gate 不变。P1-011 保留原 accepted narrow conformance claim，
但退役为 current runtime input；不得调用、复制或修改其 runtime implementation。新实现可以
复用 accepted schema，并以 clean-room 方式实现 source-bound Environment Snapshot。

Re-entry envelope 最多包含 `3 executable engineering Tasks / 48 engineering hours / 14 calendar
days`；P1-047 的 pre-Worker 治理成本保留为历史成本，但不计作 executable engineering Task。
等待 Founder-reserved Provider、Secret、network、cost 或 source-egress 决策的时间不计入 calendar
budget。任一时刻最多一个 active Task、branch、worktree 和 candidate。每个 Task 只允许一份
working Contract、最多一次不扩目标、路径、权限或 claim 的 bounded contract correction，
以及 initial implementation 加一次 same-Task bounded repair。禁止 successor、replacement、
normalization、closure、feasibility、remediation 和 Route V2/V3。

原首个 Task `AIOS-P1-047_LOCAL_DUAL_RUN_EXPERIMENT_PACK` 已在 Worker 前因 corrected Contract
review NON_PASS 终态停止，没有 activation、branch、worktree、Worker、implementation、candidate
或 capability。Re-entry 后首个 executable engineering Task 固定为
`AIOS-P1-048_ACTUAL_EXECUTION_EXPERIMENT_PACK`，预算为 `12 engineering hours / 3 calendar days`，
使用 accepted P1-035 control `SL-P1-REP-006-DEDUPE-REFACTOR`。它必须交付 one-command
Experiment Pack：Run A 在 fresh disposable materialization 中实际执行 base test、non-empty
patch、patched tests 和 exact
rollback；独立 Reviewer 必须从同一 frozen inputs 创建 distinct fresh Run B 并亲自重执行，
不得从 Worker receipt、success 字段或 exit zero 推断独立成功。

每次运行的 raw stdout/stderr、physical path、timing 和 identity 必须保留并 hash-bound，但跨
run 只比较预声明 stable semantics。host executable 的 `nlink` 只作观察值；其 cooperative-local
identity 由 absolute path、realpath、content digest、mode、version、architecture 与当前用户
不可写共同绑定。input、patch、Task Card 和 Evidence leaf 仍须 regular、contained、`nlink=1`。
zero-action、empty/no-op patch、缺 required test、source/patch/receipt tamper 必须 fail closed。

Review Gate 由预声明 Acceptance Criteria、冻结 target claim、actual executable Evidence 及
fresh CTO、Security、Quality 对同一 exact candidate 的独立审查控制。任一 Task 在一次 bounded
repair 后仍无法由 fresh Reviewer 重放其冻结可运行输出，只终态停止该 Task；Master 可选择一个
不同可证伪输出、且不复用失败 lineage 的独立 P1 engineering Task。只有两个独立 actual
engineering Tasks 命中同一 executable architecture root cause、envelope 耗尽、Evidence 证明
P1 Exit Gate 在当前边界不可实现、触及 Founder-reserved permission/risk，或到达 P1 Phase Gate
时才返回 Founder。不得修改 P1 Exit Gate、建立 Route V2/V3 或治理修补链。Task PASS 不等于
P1 Exit。

Task Contract 只冻结 Objective、Why Now、Inputs/Outputs、路径、预算、角色分离、最小安全不变量、
Acceptance、Stop Conditions 和 Claim Boundary；Quality 在 Task activation 后、Worker mutation 前
冻结 executable Task Card、commands、assertions 和 negative controls。Contract Reviewer 只可因
直接 start-safety defect 阻断；format、Code Map wording、继承缺陷、cooperative-local claim 外的
hostile-principal 要求和 Quality-owned implementation detail 不得阻断。每个 Task 的治理与
pre-Worker 准备不得超过工程预算的 `10%`，Worker 必须在第一个 engineering hour 内启动。

本路线只允许 cooperative-local、local synthetic、可重放、可回滚的 P1 evaluation foundation
work。network、Provider、Secret、remote、production、public、dependency download、fetch、push、
PR、release、P2/P3 entry、Agent Shell、model-initiated canonical write、Supervisor、Root Custody、
Strong Isolation、Full Trust Runtime 和 Multi-Agent Runtime 均未授权。除 exact 外部权限、critical
residual risk、两个独立实际工程 Task 的同一架构根因、envelope exhaustion 或 P1 Phase Gate 外，
Master 必须在 envelope 内持续自主推进。

## 7. Strict Phase Sequence and Founder Knowledge Synchronization

Founder 于 2026-07-28 明确要求固定阶段路线严格顺序执行。具体 Task、Route 或实现
路径失败，不等于对应 Phase Objective 或 Exit Gate 已完成，也不得授权后一 Phase
开始执行。

强制顺序规则：

- 调度 Phase `Pn` 前，所有 `P0...P(n-1)` 必须由 canonical Truth 记录为严格
  `COMPLETE`，对应 Evaluation/Exit Gate 的每个必需项均已 `ACCEPTED`，不存在
  `MISSING`、`PARTIAL`、`NON_PASS` 或未处置必需项，并具有 Founder Phase Gate
  记录；
- `partial exit`、`residual acceptance`、Task/Route 终态、预算耗尽和 anti-loop
  不得替代未完成 Exit Gate；它们可以终止一个实现路线，但不能让后一 Phase 获得
  调度权；
- 如果 Founder 希望在 Exit Gate 未完成时改变阶段顺序，必须明确修改适用的战略或
  Exit Gate 权威，而不能通过普通 Route、Task、残余风险接受或状态标签隐式绕过；
- 普通实现失败应在仍有效的同一 Task 预算内修复；Task 已终态或实现假设失效时，
  Master 必须在同一 Phase 选择不恢复失败 lineage 的独立实现方法或最小工程 Task；
- Phase/Route/Task 资源创建前必须完成数据驱动的 predecessor Gate 检查。检查依据
  必须来自 canonical Truth、绑定的 Evaluation/Exit Gate、已接受 Task Gate Evidence
  和 Founder Phase Gate，不得信任自报 `PASS`、字符串前缀或任意非空 Evidence 引用；
- 检查 NON_PASS 时，即使 current Task 为 `NONE`，后一 Phase 也必须保持 `HOLD`，
  禁止创建其 branch、worktree、candidate 或工程 Evidence。唯一允许的调度方向是
  返回最早尚未完成的 Phase。

Founder Knowledge Vault 采用非阻塞、事件驱动同步：

- canonical Task 接受或终态停止、Phase/Route/Gate 变化、影响目标/范围/权限/风险的
  Founder 决定、Research Artifact 接受或可复用根因确认，都会立即产生一个 Knowledge
  sync event；
- canonical Truth 的 `founder_knowledge_sync` 是同步状态的非权威观察账本；每个触发
  事件、状态及 Artifact/Review/Vault/receipt 身份必须闭合记录并通过治理校验；
- sync event 和 candidate/review/import 状态必须可观察并在 Founder 状态汇报中披露，
  但 candidate 创建、Knowledge Review 或 Vault import 均不是工程 Task 激活、Task Gate
  或 Phase Gate 的前置条件；
- 合法状态为 `PENDING_CANDIDATE`、`PENDING_REVIEW`、
  `REVIEWED_PASS_PENDING_IMPORT`、`NON_PASS`、`IMPORTED`、`OUTDATED` 或
  `NO_MATERIAL_KNOWLEDGE_DELTA`。任何非 `IMPORTED` 状态不得表述为已同步；
- 只有独立 Knowledge Reviewer 对 exact Artifact bytes 返回 PASS 后，才可导入同一
  bytes，并以不可覆盖 receipt 绑定 source event、commit/tree、Truth、Artifact、Review、
  import path/hash/length 和 bytes equality；
- Knowledge 同步延迟、Review NON_PASS 或无实质知识增量不得阻塞工程，但必须保留真实
  状态并在后续状态汇报中持续可见；Vault 永远不获得 Truth、Evidence、Task authority
  或 Gate authority。
