# SourceLens AIOS 当前控制面

## 读取顺序

1. `truth/project_state.yaml`
2. `STRATEGIC_CONSTITUTION.md`
3. `MASTER_EXECUTION_PROTOCOL.md`
4. Truth 指向的当前 Task Contract
5. 研究任务再读取 `EVALUATION_PROTOCOL.md`

## 领域权威

| 领域 | 文件 |
| --- | --- |
| 当前事实 | `truth/project_state.yaml` |
| 战略 | `STRATEGIC_CONSTITUTION.md` |
| 执行 | `MASTER_EXECUTION_PROTOCOL.md` |
| 评估 | `EVALUATION_PROTOCOL.md` |
| 继承资产处置 | `MIGRATION_LEDGER.yaml` |
| Task/Environment/Run schema | `schemas/` |
| 当前候选任务 | `tasks/P1-001_EVALUATION_HARNESS.yaml` |

P0 合同、P0 review、旧 Goal、旧状态、PRE/Discovery/BOUND/MCF/Carrier、Supervisor 与 Root Custody 材料是历史证据，不再位于活跃控制面。

## 当前边界

当前 phase、Goal、Task、Gate、运行数和授权状态只由 `truth/project_state.yaml` 表达，本文件不复制其具体值。Truth 指向 P1 时，P1 只建立 Evaluation Harness 和可比较 baseline，不继续建设治理基础设施，也不提前建设 P3/P5 Trust Runtime。

`DEFINED`、`IMPLEMENTED`、`TESTED`、`GATE_PASSED`、`PRODUCTION_PROVEN` 必须分开使用。任何低级别证据都不能推导更高级别结论。
