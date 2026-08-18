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

## 长期 Goal 生命周期隔离（强制执行）

- SourceLens 长期 Goal 的默认生命周期是：持续推动项目从当前真实状态走到实际开发完成。Task、Route、实验或 Phase 的 `NON_PASS`、`STOPPED`、`TERMINAL`、预算耗尽、候选放弃、战略 HOLD 或 Founder 保留决策点，都只结束对应层级，绝不自动完成、终止或删除长期 Goal。
- 必须机械区分四个状态层级：`TASK_LIFECYCLE`、`ROUTE_LIFECYCLE`、`PHASE_LIFECYCLE`、`LONG_TERM_GOAL_LIFECYCLE`。任何下层状态不得通过同名 `terminal`、`complete`、`stop` 或自由文本向上冒泡。状态汇报必须明确指出发生变化的精确层级。
- canonical Truth 中的项目控制状态与 Codex 运行时长期 Goal 是两个独立控制面。修改、终止或回滚其中一个，不自动授权修改另一个；项目内 Founder decision、结构化 token、receipt、Review 或 Truth 状态不得被解释为调用 `update_goal(status="complete")` 的授权。
- 调用 `update_goal(status="complete")` 前必须在同一执行窗口完成并保留 `LONG_TERM_GOAL_CLOSURE_AUDIT`，至少逐项证明：
  1. `PROJECT_ACTUALLY_COMPLETED=true`，且长期 Goal 的全部成功条件已有当前、可重放证据；或用户在最新直接消息中以明确自然语言要求终止整个项目及 Codex 长期 Goal；
  2. `PHASE_AND_TASK_TERMINAL_NOT_USED_AS_GOAL_COMPLETION=true`；
  3. `LATEST_USER_INTENT_CONFLICT=false`；
  4. `CODEX_GOAL_CLOSE_ELIGIBLE=true`。
  任一项缺失、为 false、UNKNOWN 或仅由旧 token、Agent 生成的授权文本、阶段终态、预算耗尽推断时，禁止关闭长期 Goal。
- 即使用户粘贴了包含 `TERMINATION`、`STOP` 或 `COMPLETE` 的预格式化 token，只要它与“持续开发直至项目完成”的长期要求存在冲突，就必须先用大白话说明会同时影响哪些层级并取得新的直接确认；不得让 token 的字面含义替代真实意图判断。
- 项目尚未实际完成时，长期 Goal 必须保持 `active`。若因误操作变为 absent、complete 或 blocked，Master 必须先恢复同一 Goal objective，再以非破坏性、可审计方式纠正项目状态；禁止创建平行 Goal、重写 Git 历史、删除错误 Evidence 或把恢复动作冒充工程进度。
- 每次 Goal/Phase/Route/Task 终态汇报必须分别列出：`LONG_TERM_GOAL_STATUS`、`CURRENT_PHASE_STATUS`、`CURRENT_TASK_STATUS`、`PROJECT_ACTUAL_COMPLETION`、`CODEX_GOAL_ACTION_TAKEN`。若项目未完成，最后一项只能是 `NONE_KEEP_ACTIVE`。

继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。

## 工作区、分支与磁盘卫生（强制执行）

- canonical topology 默认只能保留正式 `main` 和至多一个当前 active Task 的短生命周期 branch/worktree。Task 集成完成或终态停止后，必须在不阻塞下一项真实工程的前提下及时回收对应本地 branch/worktree；不得让历史 Task 分支和 worktree 无期限累积。
- 每次 Task 激活前、重型 build/matrix 后、Task 终态或集成后以及 Phase Gate 前，必须旁路执行一次轻量卫生审查：检查 `git status`、local branches、`git worktree list`、`.sourcelens-worktrees`、`.sourcelens-audit` 及仓库内生成目录的数量和占用。发现异常增长时在当前执行窗口内处置，不另建治理 Task，不申请逐项 Founder 权限，也不把清理计为工程进度。
- `.sourcelens-worktrees` 只允许保存当前 Task 的临时开发副本，不是项目核心或长期 Evidence Store。clean 且已集成/终态的历史 worktree和对应本地 branch可直接清理；dirty worktree不得为了清理而伪造提交，必须先制作可校验、内容寻址的精确差异快照或确认已有等价 Evidence，再删除副本。不得自动删除remote branch、tag或改写Git历史。
- `.sourcelens-audit` 只允许保存需要保留的原始 Evidence、Review、receipt、manifest和恢复快照；禁止长期保存 `target`、`b2-cargo-target`、`node_modules`、`.gradle`、`.m2`、临时编译输出及其他可再生缓存。此类缓存一经识别，必须按“精确清单 → 同卷隔离 → 与风险成比例的验证 → 删除”的单次流程及时清理；验证失败则恢复隔离内容并报告，不得反复清理/恢复形成循环。
- 清理只能自动作用于明确归属、可再生、非symlink的缓存和临时副本。canonical source、未保存的用户改动、真实 Evidence、Vault、Secret、不可重建Artifact以及范围不明的目录不得自动删除；任何不可逆的重要资产删除仍属于Founder保留事项。
- 新工程不得把本机绝对 `.sourcelens-audit` 或 `.sourcelens-worktrees` 路径作为产品运行核心。外部Artifact应通过可配置root、稳定Artifact ID、relative path、byte length和SHA-256绑定；历史合同中的绝对路径只作为历史事实保留，不得静默改写。
- 每次完成实质清理后只生成一份简洁receipt，记录精确目标、清单哈希、释放容量、验证结果、Git clean状态和可恢复性。清理维护不得扩张为Review、correction、successor或治理文档链。

## Codex App 可写根与审批降噪（强制执行）

- 每个 Task 激活后、任何 Worker 首次写文件前，Master 必须核对 Codex App 当前 filesystem writable roots 与 authority 绑定的 active worktree、Evidence root。项目/Founder 已授权某项工程，不等于 Codex App 允许 Agent 自行扩大本机文件系统写权限；两者必须明确区分。
- active worktree 不在 writable roots 内时，子 Agent 禁止逐文件直接编辑该 worktree，也不得让用户为同一普通实现连续批准多个“编辑文件”弹窗。默认流程必须改为：子 Agent 在 writable `/private/tmp` 或其他已声明 writable staging root 形成一个可审查的统一 patch，在临时物化副本应用并完成相称的编译/测试，Master 核对 allowlist 与 diff 后再以单次、不可覆盖的受控操作应用到 active worktree。
- 若实现规模确实需要多个检查点，最多按“一个已验证检查点 = 一次批量写入授权”分组；不得按文件、hunk、测试类或 Agent 拆成重复授权。发现第二次同类编辑审批弹窗时，执行方必须立即暂停，保存当前状态并切换到 unified-patch/staging 模式，不得继续让用户机械点击。
- 非 writable 的外部 Evidence root 同样适用集中写入：Quality/Evaluator/Reviewer 只在 `/private/tmp` 完成 create-once stage、closed inventory、hash/mode/symlink 验证；只有 Master 可以在 Gate 边界执行一次最终安装或原子 rename。子 Agent 不得各自发起 escalated external write，也不得为 receipt、manifest、单个 leaf 分别请求审批。
- 优先复用已经批准且范围足够窄的安全命令规则；禁止为了消除弹窗申请可任意改写文件系统的宽泛长期权限。若客户端提供“仅此 Task/目录/会话允许”的窄范围选项，可提示用户一次选择，但自动执行不得依赖用户必须选择该选项。
- 不得为了规避 Codex App 沙箱而静默改变 canonical worktree、branch、Task authority 或 Evidence root。路径变更若会改变权威身份，继续使用 staging + unified patch；只有真实权限边界变化才升级 Founder。
- 状态汇报必须把 `PROJECT_AUTHORIZED`、`APP_FILESYSTEM_APPROVAL_REQUIRED`、`WRITE_NOT_EXECUTED` 三类事实分开，禁止把客户端文件权限弹窗说成 Founder 决策或内部 Gate 授权。

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

## Founder 再授权中断门（强制执行）

- 本节是 Phase 级委托的不可降级执行不变量。普通 Route packet、Task Contract、Stop Condition、Reviewer 结论、terminal receipt、Truth 状态标签或“下一 Founder 决策点”文字，均不得把已委托给 Master 的日常事项重新升级为 Founder 审批。只有 Founder 明确修改本政策、Phase Objective/Exit Gate、Phase envelope 或下列保留权限，才能改变这一分工。
- `founder_decision_required: true` 只允许由封闭枚举触发：`PHASE_ENTRY_OR_EXIT`、`MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE`、`MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE`、`NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT`、`IRREVERSIBLE_ASSET_REMOVAL`、`MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT`、`CRITICAL_RESIDUAL_RISK_ACCEPTANCE`。自由文本、Task ID、根因名称、Reviewer verdict 或 Route terminal 状态不得充当触发器。
- 以下事件明确属于 Master 管理的普通 Task lifecycle，不得单独触发 Founder：implementation/test NON_PASS、Reviewer TARGET NON_PASS、同 Task repair 耗尽、Task 预算耗尽、candidate 放弃、tree mismatch、canonical verification NONPASS，以及某个预排后继 Task 因 predecessor Gate 未通过而失去资格。
- Phase Gate 不是“任一 Task/Route 停止点”。只有 canonical Exit Gate 的全部必需项均已 `ACCEPTED`、Founder Gate 状态为 `ELIGIBLE_AWAITING_FOUNDER_DECISION`，或出现上述 exact Founder 保留触发器时，才允许把 next action 指向 Founder。Phase 必需项仍为 `MISSING/PARTIAL/NON_PASS` 时，普通终态后的 next action owner 必须是 `MASTER_CEO_AGENT`。
- Phase entry 授权和 Phase execution envelope 必须跨普通 Route/Task 终态持续存在；Route terminal 只消费该 Route/Task 的执行身份，不得自动消费 Phase 调度权。只要 Phase 未完成、持久 Phase envelope 仍有任务/小时/日历/权限容量且不存在 Founder 保留触发器，Master 必须选择新的独立 Phase-local Task。
- 新独立 Task 与被禁止的 successor/replacement 的机械区别是：新 Task 使用全新 Task ID、nonce、branch、worktree、Contract 和 Evidence root；不恢复、读取、比较、复制或复用 rejected lineage；仍直接服务同一 Phase Objective，并受剩余 Phase envelope 约束。满足这些条件的独立 Task 不需要 Founder 再授权。
- canonical Truth 必须包含封闭的 Founder escalation classification 及持久 Phase envelope accounting；`founder_decision_required`、`user_action_required` 和 `next_eligible_action` 必须从该分类派生，不得手工自报。Validator 必须拒绝“普通 Task 终态 + Phase 未完成 + 尚有 envelope 容量 + Founder Gate”的组合。
- 上述普通终态组合的 canonical next action 必须精确为 `MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK`；该选择随后必须通过 phase-delegated independent Task authority 路径，而不是伪造新的 Founder packet。
- 每次面向 Founder 请求授权前，Master 必须先运行 Founder escalation validator。结果为 `NO_RESERVED_TRIGGER_CONTINUE_PHASE` 时禁止生成授权提示词，并必须直接继续工程；只有 validator 给出 exact reserved trigger 时，才允许一次性请求相应 Founder 决策。

## Founder / 用户下一步交付（强制执行）

- 每次准备结束一个面向 Founder 的回合前，Master 必须完成一次 `FOUNDER_ACTION_HANDOFF_CHECK`。该检查不产生工程或治理进度，只回答四件事：当前是否确实需要用户动作、Agent 为什么不能自行继续、当前事实与权限边界下哪一个动作最优、该动作完成后 Agent 将立即继续什么。
- `USER_ACTION_REQUIRED=false` 时，最终答复必须明确包含：`你现在无需操作，我将在现有授权范围内继续执行。` 并继续当前可执行工作；禁止附带可选授权提示词、把日常 Task 选择交给 Founder，或只汇报状态后停止。
- `USER_ACTION_REQUIRED=true` 只允许来自：经机械核验的 Founder reserved trigger、真实 Codex App/OS 审批边界，或仅用户掌握且无法通过已授权只读方式取得的必要输入。最终答复必须开门见山写清“我现在需要你做什么”，并给出当前推荐的一个最优动作、推荐理由、权限与风险边界，以及动作后的继续路径。
- 最优动作是授权时，Master 必须提供一段可直接复制回复的完整授权文本；禁止只给 token 名称、授权框架、字段清单、`TBD`、占位符或要求 Founder 自行设计边界。生成前必须重新核验并绑定当前 canonical commit/tree、适用计划或 Contract identity、exact reserved trigger、允许与禁止范围、预算或次数、PASS/NON_PASS 生命周期，以及 P2、项目和长期 Goal 的持续状态。任一必要 identity 为 `UNKNOWN` 时，先完成只读核验，不得把核验工作转给 Founder。
- 最优动作是本机或 UI 操作时，必须给出最短、明确、可执行的 exact steps；必须分别说明项目授权、Codex App 文件系统审批和外部权限，禁止混同。
- 存在多个可行方案时，Master 必须承担判断责任：主操作只给推荐方案；只有另一方案会实质改变战略、成本或风险时才补充备选并说明不推荐原因。禁止把多选题、模糊问题或风险设计工作退还给 Founder。
- 每个 `BLOCKED`、`NON_PASS`、`TERMINAL`、Phase/Task 状态汇报和授权拒绝都必须以完整的“下一步”闭合，至少包含：`USER_ACTION_REQUIRED`、`RECOMMENDED_SINGLE_ACTION`、`COPY_READY_TEXT_OR_EXACT_STEPS`、`AGENT_CONTINUATION_AFTER_ACTION`。不得连续发送只有相同状态、没有可执行下一步的回复。
- 每个 Task、Route、Phase 或 Goal 执行结束时都必须交付一次 `NEXT_STEP_AUTHORIZATION_HANDOFF`。若下一步触及 Founder 保留权限，handoff 必须直接包含一份完整、无占位符、可复制回复的授权正文；若下一步仍在既有 Phase 委托内，则必须明确写 `NEXT_STEP_AUTHORIZATION: NOT_REQUIRED_MASTER_CONTINUES` 并由 Master 直接继续，禁止伪造 Founder token。任何 `no automatic successor`、`no automatic Vn`、`不得自动创建后继`、`不得自动生成后续授权` 或同义终态条款，只禁止 Agent 未经 Founder 直接回复就创建、执行或把草案当成后继权限；它们永远不得被解释为禁止生成、校验和交付本条要求的 copy-ready 下一步授权文本。
- 终态 handoff 必须在临时 `user-action-handoff/v1` 中显式绑定 exact terminal receipt identity，并分别声明：是否存在 no-auto-successor 条款、该条款只约束执行而不压制 handoff、下一步是否需要用户动作、copy-ready handoff 是否已交付。存在 terminal receipt 且下一步客观需要 Founder 保留权限时，`NONE_CONTINUE` 必须 NON_PASS；不得以 terminal/no-auto 字样把 `USER_ACTION_REQUIRED=true` 降为 false。
- 请求用户动作前必须运行适用的 escalation、authority 和 current-state validator。结果为 `NO_RESERVED_TRIGGER_CONTINUE_PHASE` 时原则上禁止请求 Founder 日常授权；若当前需要的是 validator 尚不能表达的 prospective reserved effect，必须把该 validator capability gap 明确标为 `FACT`，用独立、最小、只覆盖 exact reserved effect 的 preflight 证明请求必要性，不得借此扩展其他预算、范围或权限。
- 任何准备暂停、等待用户或交出控制权的草稿，在发送前必须先生成一个临时 `user-action-handoff/v1` JSON 对象，并运行 `ruby scripts/validate-founder-action-handoff.rb --package <json> --draft <markdown>`；prospective Founder 请求还必须通过独立参数 `--current-user-request-token <exact-current-token>` 绑定用户当前直接消息。校验失败只阻止该草稿发送；不得阻断仍可继续的工程，不得写入 Truth、Evidence 或进度账本，也不得把 `ASSISTANT_PROTOCOL_ERROR` 伪装成用户 blocker。

## 严格阶段顺序与反偏航（强制执行）

- 本节落实 `FOUNDER_DELEGATION_POLICY.md` v1.8 的 Founder 指令，只约束执行与调度，不改变各权威文件在各自领域内的权力。
- 固定阶段路线必须按 `P0 → P1 → P2 → … → P12` 顺序执行。调度或激活后一 Phase 前，必须从 canonical Truth 和对应 Evaluation/Exit Gate 逐项证明前一 Phase 的全部必需项均为 `ACCEPTED/COMPLETE`，不存在 `MISSING`、`PARTIAL`、`NON_PASS` 或未处置的必需项，并且已完成 Founder Phase Gate。
- `partial exit`、`residual acceptance`、Task/Route 终态、预算耗尽或“避免循环”不得被解释为跳过未完成 Phase 能力的依据。除非 Founder 明确发布新的战略/宪法版本并正式修改该 Phase Objective 或 Exit Gate，否则后一 Phase 必须保持 `HOLD`，当前调度只能回到尚未完成的前一 Phase。
- 失败的是具体实现路径，不是尚未完成的 Phase 目标。普通失败只在仍有效的同一 Task 和预算内修复；Task 已终态或实现假设失效时，保留真实 Evidence，并在同一 Phase 选择不恢复失败 lineage 的不同实现方法或独立最小工程 Task，直至完成 Exit Gate、触发真实不可接受风险或耗尽 Founder 已批准的 Phase envelope。
- 每次 Phase/Route/Task 资源创建前必须执行数据驱动的 `phase_predecessor_check`：记录当前 Phase、前序 Phase、Exit Gate 完整必需项集合、逐项状态、hash-bound Evidence、Founder Phase Gate 和唯一 next action。不得信任自报 `PASS`、字符串前缀或任意非空 Evidence 引用。检查不通过时，即使 `current Task` 为 `NONE`，后一 Phase 也必须保持 `HOLD`，禁止创建其 branch、worktree、candidate 或工程 Evidence。
- 每次状态汇报必须明确列出：当前 Phase、严格完成度、已完成 Gate、缺失 Gate、正在解决的真实工程问题以及下一项最高价值行动。Review、文档、hash、manifest、治理同步或部分实现不得冒充 Phase 进度。
- 若 Founder 指令与严格阶段依赖存在冲突，Master 必须在任何后一 Phase 写入前显式指出冲突并给出“留在前一 Phase 完成缺失 Gate”的推荐方案；不得仅因指令形式合法而静默跳步。

## Phase 工程价值与反自循环（强制执行）

- Phase 严格进度只来自 canonical Exit Gate 必需项的 `ACCEPTED` Evidence。治理文档、
  validator、schema、review、receipt、inventory、预算消耗、Task `NON_PASS`、未集成
  candidate 和工作时长的进度 credit 一律为 `0`。若需要面向管理的过程百分比，只能使用
  预先冻结、由独立验收触发的 delivery milestone；不得按文档数、审查轮次或已花时间估算。
- 每个恢复路线必须拆成最多三个价值递进阶段：代表性 benchmark/baseline foundation、
  product implementation、formal held evaluation。前一 milestone 未独立 `ACCEPTED`，不得
  激活后一阶段。不得把 dataset、产品实现、运行时隔离、formal 统计和 Phase Gate 全塞进
  一个 Task。
- benchmark foundation Task 不得修改产品；product Task 必须产生非空、可测试的产品源码
  diff；formal evaluation Task 禁止修改产品、dataset、split、oracle、metric、threshold、
  schedule 或已冻结 candidate。任一正式 dispatch 后不得换题、调参、补跑或 rerun-to-pass。
- 每个普通工程 Task 最多 `2` 个 candidate generations、`1` 次 same-Task repair、`2` 个
  review cycles。第一次独立 review 必须一次性冻结完整 P0/P1 finding set；第二次只允许关闭
  已冻结 finding 或拒绝修复新引入的 regression，不得持续 drip-feed 新的同类设计要求。
- 同一 delivery milestone 在整个 Phase 内最多允许 `2` 个 product implementation Tasks；该累计
  上限不得因新 Task ID、nonce、branch、worktree、Contract、架构名称、clean-room 标签或
  Founder 授权版本号而重置。连续 `2` 个 implementation Task `NON_PASS` 后，必须冻结该
  benchmark 下的新实现和调参；不得继续生成 `V3/V4/...` 授权链。历史已超过上限的 Phase
  立即按超限状态执行，不得以 grandfathering 再增加实现 Task。
- 里程碑级实现冻结后只允许三类路线：在打开 HELD 前由 Founder 明确授权对一个 exact、不可变、
  已有 candidate 做一次预声明的独立 formal evaluation；Founder 正式修改 Phase Objective 或
  Exit Gate；或保持 Phase `HOLD/INCOMPLETE`。第一类路线不得修改或调试 candidate，不得读取
  其他 rejected lineage，不得把 post-hoc DEV 结果改写为原 Task `PASS`，也不得在 HELD 后
  rerun-to-pass。
- Reviewer blocker 必须落入封闭 Gate Relevance 类别之一：`EXIT_GATE_VALIDITY`、
  `AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY`、`RESULT_INTEGRITY`、`PRODUCT_CORRECTNESS`。
  与当前 Task 输出、P2 Exit Gate、既有安全权限或结果真实性无机械因果关系的改进项只能记为
  非阻塞 backlog，不得延长 preactivation、repair 或治理链。
- 普通 Task 的治理与 pre-Worker 准备不得超过预算的 `10%`，Worker 必须在第一个
  engineering hour 内开始真实实现或可执行 benchmark 工作。无法满足时在首次 write 前终止
  该 Task，不得用更多治理修复来证明它可以开始。
- Phase 内的规则、schema 与 validator 只允许在机械证明“现有控制会接受一个明确禁止状态”时
  修改，并必须优先扩展既有文件。每次路线纠偏最多一次规则冻结；冻结后除 safety-critical
  缺陷或 Founder 保留决策外不得继续追加治理。治理修改、校验轮次、授权文本和历史同步永远
  不解锁 Task、不增加 delivery milestone、不产生工程进度。
- Task `NON_PASS` 后禁止 successor、replacement、normalization、closure、feasibility 或
  remediation 链。若 Phase 仍需同一能力，只能在剩余/新增合法 envelope 内选择一个完全独立、
  不读不复用 rejected lineage、且直接瞄准下一未接受 delivery milestone 的 Task。
- P2 的当前纠偏权威为 `docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml`。创建任何后续 P2
  Task Contract 前必须运行 `ruby scripts/validate-p2-recovery-anti-cycle.rb`；validator
  NON_PASS、Phase envelope 未获扩展或上一 milestone 未接受时，禁止创建 Task ID、nonce、
  branch、worktree、Contract、authority 或工程 Evidence。

## P2 Benchmark Source 选题与授权反自循环（强制执行）

- P2 benchmark 的本机 Java 执行基线固定为现有 JDK 17。仓库或题目要求 Java 18+ 时，必须在
  最终集合冻结前淘汰；不得安装更高 JDK、降低上游 compiler release、修改构建参数或把
  toolchain invalid 留到一次性 admission 后才发现。只有目标子模块在不修改上游 bytes、
  构建参数、测试、依赖或 selector 的前提下，已由 exact JDK 17 实际离线构建证明独立可达，
  才可不受根项目较高 release 声明影响。
- Repository discovery、PR discovery 和 provisional pool 只产生候选，不得直接冻结最终
  `6 repositories / 12 tasks`。每个最终仓库必须先有恰好两个题同时通过 license、provenance、
  base/fix identity、archive/diff/test selector、offline dependency closure 和 JDK 17
  pre-freeze toolchain probe；不得按响应顺序冻结“前六个仓库”。
- Toolchain probe 只能验证 base 与 fix 在 JDK 17 下的构建可达性，不能执行正式 admission 的
  base-FAIL/fix-PASS selector，也不能读取 SourceLens 输出或 baseline 分数。最终冻结后仍保持
  one-shot admission、不得换题、补跑或改 selector 的既有规则。
- Maven、Gradle 或其他构建子进程的“本地仓库”“`file://` mirror”或 closed env 不能单独作为
  零网络证明。每次启动前必须扫描并记录工具安装级、用户级和显式 settings/init 配置，Maven
  必须同时使用 `--offline`、显式 `--global-settings`、显式 `--settings` 与 fresh
  `maven.repo.local`，Gradle 必须同时使用 `--offline --no-daemon` 与 fresh
  `GRADLE_USER_HOME`；两者只能读取由受控 exact curl 获取并 hash-bound 的依赖 custody。缺少任一
  离线参数、配置覆盖、custody provenance 或启动前检查时，必须在 spawn 前 NON_PASS。安装级
  mirror 即使会被项目 settings 覆盖也必须视为风险输入；不得通过一次在线“依赖发现”运行来
  推导闭包，任何非 exact curl 的 DNS/HTTP(S) 都是 capability terminal safety condition。
  真实构建进程还必须由 hash-bound 的本机 `/usr/bin/sandbox-exec` 与 exact profile 强制
  `deny network*`；exact profile 必须把 `(allow default)` 写在前、`(deny network*)` 写在后，
  并在不访问公网的独立 preflight 中证明恶意构建子进程不能取得 AF_INET/AF_INET6 网络能力。
  构建插件、测试或 JVM 即使忽略 offline 参数也不得建立 DNS/socket。仅在某题
  明确获准且已冻结的数字 loopback 测试需要时，才允许另建更窄的 loopback-only profile；当前
  source admission 默认无该例外。缺少 OS 级 deny-network sandbox 时禁止 spawn。
  每个真实 build/probe 的 exact cwd、argv、closed env、JDK17、source/POM、安装/用户/项目配置、
  sandbox profile 与 dependency inventory 必须在 spawn 前由该题 pre-freeze receipt 绑定；不得
  以通用 launcher、self-report spec 或空 inventory 替代真实构建与 custody 核验。
- 普通 acquisition Route 的实现、工具链、测试或 Review NON_PASS 不是 Founder trigger。
  Route 终态后，Master 必须在剩余 Phase envelope 内自主选择不同的独立最小路径，不得把
  日常选题、仓库替换、工具链兼容筛选或 Reviewer 退回交给 Founder。
- 新的外部网络能力确实不可缺少时，只允许请求一次与 P2 benchmark-source admission milestone
  绑定的有界 capability envelope；禁止继续生成 `V13/V14/...` 式“一个 Route 一个 token”的
  连续再授权链。该 capability 的 host、method、credential、write、body-budget 和生命周期必须
  一次冻结。规则文字、Agent 草稿或自报字段本身绝不授权网络；任何网络动作仍须由 Founder
  当前直接授权及其未消费生命周期事实覆盖。已明确 single-use 且终态的旧授权不得静默复用。
  若当前没有有效网络 capability，Master 的默认动作是先选择无需新增网络的独立 Phase-local
  工程路径；只有 benchmark-source admission 客观上仍必须新增网络时，才一次性请求 milestone
  capability，不得因普通 Route NON_PASS 本身请求授权。
- 最终集合的 freeze 操作必须把实际 pre-freeze Gate 作为同一不可分割流程：先在 exact JDK17/
  Javac、闭合离线依赖和绑定的 base/fix bytes 上真实执行每题 build command，再核验 6 仓库、
  12 题、每仓库 2 题及全部 PASS Evidence，最后才 create-once 写 final-freeze artifact。只检查
  自报 JSON、字符串、manifest 或 receipt 不算 Gate；Gate 未 PASS 时 final-freeze 必须不存在。
- 选题、下载、治理、Review、receipt、终态和本规则修复的 P2 进度贡献均为 `0`。这套纠正不
  恢复 V12、不改写任何 terminal Evidence，也不授权新的 DNS/HTTPS；它只约束下一条合法路径。

<!-- P2_BENCHMARK_SOURCE_GUARDRAILS_BEGIN -->
```yaml
schema_version: p2-benchmark-source-guardrails/v1
runtime:
  java_major: 17
  newer_java_install_authorized: false
  build_parameter_override_allowed: false
  build_subprocess_network_mode: FORCE_OFFLINE_BEFORE_SPAWN
  build_process_network_sandbox: MACOS_SANDBOX_EXEC_DENY_NETWORK_REQUIRED
  maven_required_arguments:
    - --offline
    - --global-settings
    - --settings
    - -Dmaven.repo.local
  gradle_required_arguments:
    - --offline
    - --no-daemon
  tool_install_user_and_explicit_config_preflight_required: true
  file_repository_or_closed_env_alone_proves_offline: false
  dependency_bytes_provenance: CONTROLLED_EXACT_CURL_CUSTODY_ONLY
selection:
  final_repository_count: 6
  final_task_count: 12
  tasks_per_repository: 2
  base_and_fix_jdk17_probe_required: true
  effective_compiler_release_max: 17
  exact_submodule_exception_requires_observed_jdk17_build: true
  dependency_closure_before_freeze: true
  response_order_freeze_allowed: false
  final_freeze_before_toolchain_probe_allowed: false
  prefreeze_gate_must_execute_bound_builds: true
  self_report_only_receipts_allowed: false
  final_freeze_requires_prefreeze_gate_pass: true
delegation:
  rules_do_not_authorize_network: true
  ordinary_route_non_pass_founder_trigger: false
  next_independent_route_owner: MASTER_CEO_AGENT
  default_after_route_non_pass: MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK
  numbered_single_route_reauthorization_chain_allowed: false
  future_network_request_style: PHASE_MILESTONE_SCOPED_BOUNDED_CAPABILITY
  active_direct_capability_required_for_network: true
  terminal_single_use_capability_reuse_allowed: false
  reauthorization_required_only_for:
    - NO_VALID_NETWORK_CAPABILITY
    - HOST_METHOD_BUDGET_CREDENTIAL_WRITE_OR_PHASE_SCOPE_EXPANSION
    - CRITICAL_RESIDUAL_RISK_ACCEPTANCE
progress:
  governance_credit: 0
  acquisition_credit: 0
  review_receipt_terminal_credit: 0
```
<!-- P2_BENCHMARK_SOURCE_GUARDRAILS_END -->

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
