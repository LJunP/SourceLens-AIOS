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

## 工作区、分支与磁盘卫生（强制执行）

- canonical topology 默认只能保留正式 `main` 和至多一个当前 active Task 的短生命周期 branch/worktree。Task 集成完成或终态停止后，必须在不阻塞下一项真实工程的前提下及时回收对应本地 branch/worktree；不得让历史 Task 分支和 worktree 无期限累积。
- 每次 Task 激活前、重型 build/matrix 后、Task 终态或集成后以及 Phase Gate 前，必须旁路执行一次轻量卫生审查：检查 `git status`、local branches、`git worktree list`、`.sourcelens-worktrees`、`.sourcelens-audit` 及仓库内生成目录的数量和占用。发现异常增长时在当前执行窗口内处置，不另建治理 Task，不申请逐项 Founder 权限，也不把清理计为工程进度。
- `.sourcelens-worktrees` 只允许保存当前 Task 的临时开发副本，不是项目核心或长期 Evidence Store。clean 且已集成/终态的历史 worktree和对应本地 branch可直接清理；dirty worktree不得为了清理而伪造提交，必须先制作可校验、内容寻址的精确差异快照或确认已有等价 Evidence，再删除副本。不得自动删除remote branch、tag或改写Git历史。
- `.sourcelens-audit` 只允许保存需要保留的原始 Evidence、Review、receipt、manifest和恢复快照；禁止长期保存 `target`、`b2-cargo-target`、`node_modules`、`.gradle`、`.m2`、临时编译输出及其他可再生缓存。此类缓存一经识别，必须按“精确清单 → 同卷隔离 → 与风险成比例的验证 → 删除”的单次流程及时清理；验证失败则恢复隔离内容并报告，不得反复清理/恢复形成循环。
- 清理只能自动作用于明确归属、可再生、非symlink的缓存和临时副本。canonical source、未保存的用户改动、真实 Evidence、Vault、Secret、不可重建Artifact以及范围不明的目录不得自动删除；任何不可逆的重要资产删除仍属于Founder保留事项。
- 新工程不得把本机绝对 `.sourcelens-audit` 或 `.sourcelens-worktrees` 路径作为产品运行核心。外部Artifact应通过可配置root、稳定Artifact ID、relative path、byte length和SHA-256绑定；历史合同中的绝对路径只作为历史事实保留，不得静默改写。
- 每次完成实质清理后只生成一份简洁receipt，记录精确目标、清单哈希、释放容量、验证结果、Git clean状态和可恢复性。清理维护不得扩张为Review、correction、successor或治理文档链。

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

## 严格阶段顺序与反偏航（强制执行）

- 本节落实 `FOUNDER_DELEGATION_POLICY.md` v1.7 的 Founder 指令，只约束执行与调度，不改变各权威文件在各自领域内的权力。
- 固定阶段路线必须按 `P0 → P1 → P2 → … → P12` 顺序执行。调度或激活后一 Phase 前，必须从 canonical Truth 和对应 Evaluation/Exit Gate 逐项证明前一 Phase 的全部必需项均为 `ACCEPTED/COMPLETE`，不存在 `MISSING`、`PARTIAL`、`NON_PASS` 或未处置的必需项，并且已完成 Founder Phase Gate。
- `partial exit`、`residual acceptance`、Task/Route 终态、预算耗尽或“避免循环”不得被解释为跳过未完成 Phase 能力的依据。除非 Founder 明确发布新的战略/宪法版本并正式修改该 Phase Objective 或 Exit Gate，否则后一 Phase 必须保持 `HOLD`，当前调度只能回到尚未完成的前一 Phase。
- 失败的是具体实现路径，不是尚未完成的 Phase 目标。普通失败只在仍有效的同一 Task 和预算内修复；Task 已终态或实现假设失效时，保留真实 Evidence，并在同一 Phase 选择不恢复失败 lineage 的不同实现方法或独立最小工程 Task，直至完成 Exit Gate、触发真实不可接受风险或耗尽 Founder 已批准的 Phase envelope。
- 每次 Phase/Route/Task 资源创建前必须执行数据驱动的 `phase_predecessor_check`：记录当前 Phase、前序 Phase、Exit Gate 完整必需项集合、逐项状态、hash-bound Evidence、Founder Phase Gate 和唯一 next action。不得信任自报 `PASS`、字符串前缀或任意非空 Evidence 引用。检查不通过时，即使 `current Task` 为 `NONE`，后一 Phase 也必须保持 `HOLD`，禁止创建其 branch、worktree、candidate 或工程 Evidence。
- 每次状态汇报必须明确列出：当前 Phase、严格完成度、已完成 Gate、缺失 Gate、正在解决的真实工程问题以及下一项最高价值行动。Review、文档、hash、manifest、治理同步或部分实现不得冒充 Phase 进度。
- 若 Founder 指令与严格阶段依赖存在冲突，Master 必须在任何后一 Phase 写入前显式指出冲突并给出“留在前一 Phase 完成缺失 Gate”的推荐方案；不得仅因指令形式合法而静默跳步。

## Founder Knowledge System（常驻规则）

- Founder Knowledge Vault 的唯一精确路径是 `/Users/lijunpeng/Documents/AIOS-Founder-Knowledge-Vault`。
- Vault 只用于 Founder 学习与长期知识沉淀；它不是 Truth、Git source of truth、Evidence Store、Task authority/control plane、Gate authority/decision system 或能力证明。
- 导入流程固定为：Learning Artifact candidate → 独立 Knowledge Reviewer → exact Artifact bytes PASS → 将相同字节导入 Vault → 验证 import path、SHA-256 与 bytes equality。
- Artifact 必须分离 `FACT`、`INFERENCE`、`UNKNOWN`；Knowledge Reviewer 非 PASS 时不得导入、不得伪造 PASS，也不得影响原 Task、Truth、Evidence 或 Gate，且不得阻断后续工程开发。
- 只有 reviewed exact bytes 可以写入 Vault；禁止写入 Secret、密码、私钥、Token、隐藏推理链或未经授权的受限源码，禁止删除或覆盖任何历史 Artifact，只能新建具有清晰版本身份的文件。
- Knowledge 同步采用事件驱动强制触发。以下任一事件发生后必须生成或更新一个 Learning Artifact candidate：canonical Task 接受并集成、Task 终态停止、Phase/Route/Gate 状态变化、Founder 作出影响目标/范围/权限/风险的决定、Research Artifact 被接受，或发现会影响后续决策的可复用根因。
- canonical Truth 中的非权威观察账本字段固定为 `founder_knowledge_sync`；每个触发事件、当前状态及 Artifact/Review/Vault/receipt 身份必须在该账本中闭合记录，并由治理校验器验证。
- 每个触发事件必须立即登记为可观察的 sync event；candidate 创建、独立 Knowledge Review 和 Vault 导入均旁路执行，不得成为工程 Task 激活、Task Gate 或 Phase Gate 的前置条件。状态必须明确记录为 `PENDING_CANDIDATE`、`PENDING_REVIEW`、`REVIEWED_PASS_PENDING_IMPORT`、`NON_PASS`、`IMPORTED`、`OUTDATED` 或 `NO_MATERIAL_KNOWLEDGE_DELTA`，不得静默遗漏或把未导入表述为已同步。
- 每次面向 Founder 的阶段状态汇报和每次 Task/Phase 交接前，必须检查 Vault 同步状态，并报告最近同步事件、Artifact 状态、Vault 是否落后以及待处理项。若没有产生值得长期沉淀的新知识，也必须记录 `NO_MATERIAL_KNOWLEDGE_DELTA` 及判断依据。
- 每次成功导入必须保留不可覆盖的 sync receipt，至少绑定 source event、canonical commit/tree、Truth SHA-256、Artifact path/SHA-256/byte length、Knowledge Review path/SHA-256/verdict、Vault import path/SHA-256 和 exact bytes equality。
- “随时同步”指上述事件发生即登记和排队，不要求把每次临时编辑、测试输出或未验证猜测写入 Vault；只沉淀对 Founder 学习、长期决策或复用工程经验有实际价值的内容，避免用笔记数量制造进展。同步延迟或 Review NON_PASS 不阻断工程，但必须持续披露真实状态，直至 `IMPORTED` 或明确的 `NO_MATERIAL_KNOWLEDGE_DELTA`。
