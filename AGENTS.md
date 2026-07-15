# SourceLens AIOS 仓库执行规则

本文件只是执行入口，不是新的权威来源。

开始工作前只按以下顺序读取：

1. `docs/aios/truth/project_state.yaml`
2. `docs/aios/STRATEGIC_CONSTITUTION.md`
3. `docs/aios/MASTER_EXECUTION_PROTOCOL.md`
4. 当前唯一 Task Contract（Truth 中为 `NONE` 时不得自行发明任务）
5. 能力或研究任务再读取 `docs/aios/EVALUATION_PROTOCOL.md`

默认禁止加载旧 SourceLens 计划、状态板、handoff、PRE、Discovery、BOUND、MCF、Carrier、Supervisor、Root Custody 或其他已终止治理材料。它们已从活跃树移除并封存为历史证据，不拥有当前调度权。

当前工程纪律：

- 一个长期 Goal、一个当前 Phase、一条关键路径、一个当前 Task。
- 使用正式 `main` 作为唯一 canonical source；普通任务使用一个短生命周期分支和 worktree。
- Founder 负责战略、Phase、预算、高风险权限和 Gate；Task envelope 内的普通设计、编码、测试与修复由 Agent 自主完成。
- 实现者不得独立验收自己的结果；审查要求与风险成比例。
- 普通实现错误在原 Task 和预算内修复，不得自动创建 successor、replacement、normalization 或新阶段。
- P1 不建设 Supervisor、Root Custody、完整 Trust Runtime、强隔离平台或 Multi-Agent Runtime。
- 系统被测 Agent 在所属安全阶段和 Founder 授权前，不得写 canonical source、执行开放 shell、外发受限源码、写远端或产生生产副作用。
- FACT、INFERENCE、UNKNOWN 必须分离；文档、实现、测试、Gate 和生产可用不得混同。
- 触发范围、权限、预算、证据或 Stop Condition 时停止并保留真实结果。

继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。
