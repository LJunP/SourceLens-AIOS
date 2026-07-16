# SourceLens AIOS 仓库执行规则

本文件只是执行入口，不是新的权威来源。

开始工作前只按以下顺序读取：

1. `docs/aios/truth/project_state.yaml`
2. `docs/aios/STRATEGIC_CONSTITUTION.md`
3. `docs/aios/MASTER_EXECUTION_PROTOCOL.md`
4. `docs/aios/FOUNDER_DELEGATION_POLICY.md`
5. 当前唯一 Task Contract；Truth 为 `NONE` 时，由 Master 在当前 Phase 边界内选择最高价值的最小可证伪任务并完成内部审查，不得恢复历史失败任务或扩展 Phase
6. 能力或研究任务再读取 `docs/aios/EVALUATION_PROTOCOL.md`

默认禁止加载旧 SourceLens 计划、状态板、handoff、PRE、Discovery、BOUND、MCF、Carrier、Supervisor、Root Custody 或其他已终止治理材料。它们已从活跃树移除并封存为历史证据，不拥有当前调度权。

当前工程纪律：

- 一个长期 Goal、一个当前 Phase、一条关键路径、一个当前 Task。
- 使用正式 `main` 作为唯一 canonical source；普通任务使用一个短生命周期分支和 worktree。
- Founder 负责战略、Phase、重大预算、高风险权限、保留风险接受和 Phase Gate；Task envelope 内的选择、授权、设计、编码、测试、修复与 Task Gate 由 Agent 组织自主完成。
- 实现者不得独立验收自己的结果；审查要求与风险成比例。
- 普通实现错误在原 Task 和预算内修复，不得自动创建 successor、replacement、normalization 或新阶段。
- P1 不建设 Supervisor、Root Custody、完整 Trust Runtime、强隔离平台或 Multi-Agent Runtime。
- 系统被测 Agent 在所属安全阶段和 Founder 授权前，不得写 canonical source、执行开放 shell、外发受限源码、写远端或产生生产副作用。
- FACT、INFERENCE、UNKNOWN 必须分离；文档、实现、测试、Gate 和生产可用不得混同。
- 触发范围、权限、预算、证据或 Stop Condition 时停止并保留真实结果。

继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。

## Phase 级 Founder Delegation（强制执行）

这是一条执行规则，不是建议。`Master Execution Protocol v1.0` 第 2、5、9 节已经规定 Founder 不管理日常 Worker 工作，Master 只升级 Founder 保留决策；所有 Agent 必须按下列方式落实，不得退回逐文件、逐命令或逐 Task 的 Founder 审批模式。

Founder 只保留：

- mission、ICP、年度结果或 Phase 路线变化；
- Phase entry/exit；
- 超出当前 Phase envelope 的重大预算、范围或权限；
- network、Provider、Secret、remote、production、public release 等高风险外部能力；
- 不可逆资产删除、重大法律/隐私/商业承诺和 critical residual risk 接受。

在当前 Phase 已获 Founder entry 授权且不触及上述保留事项时，Master 必须自主完成：

- 选择、拒绝、排序和冻结下一项最小真实工程 Task；
- 按风险配置 CTO、Security、Quality、Research、Product 与 Worker；
- 签发 phase-delegated Task authority，创建一个 branch/worktree 并调度实施；
- 在 Task envelope 内完成普通设计、编码、测试、修复、Evidence、replay、rollback 和审查交接；
- 根据独立审查决定 Task 接受、退回同 Task 修复或终态停止；
- Task Gate 满足后执行本地 canonical main 集成并同步 Truth；
- Task 终态停止后选择下一项独立 Phase 内任务，不向 Founder 申请日常许可。

强制反死循环规则：

- 每个普通工程 Task 不得要求 Founder 逐项批准文件、命令、Agent、branch、worktree、测试、普通修复、Evidence 或内部 Task Gate。
- 普通失败必须在同一 Task、同一边界和预算内处理；不得创建 successor、replacement、normalization、closure、feasibility 或 remediation 链来制造进展。
- 如果同一根因在合同允许的实现迭代内仍无法关闭，团队必须终态停止、保留 Evidence，并自主选择下一项独立任务；只有触及 Founder 保留事项才升级。
- Task Contract、Truth 与 validator 必须数据驱动，不得把某个 Task ID、nonce、时间窗、offsite 或 `NONE` 状态硬编码成所有未来 Task 的通用前置条件。
- Reviewer 非 PASS 时，团队在原 Task 内修复或终态停止；Reviewer PASS 只证明 Task Gate 条件，不代表 Phase Gate、生产可用或能力主张自动成立。

正常情况下，Founder 的下一个介入点是 Phase Gate，而不是单个 P1 工程 Task。若无需 Founder 决策，面向 Founder 的状态更新必须明确写：`你现在无需操作，我将在现有授权范围内继续执行。`
