# Contributing to SourceLens AIOS

## 开始前

按顺序读取：

1. `docs/aios/truth/project_state.yaml`
2. `docs/aios/STRATEGIC_CONSTITUTION.md`
3. `docs/aios/MASTER_EXECUTION_PROTOCOL.md`
4. `docs/aios/FOUNDER_DELEGATION_POLICY.md`
5. 当前 Task Contract
6. 能力研究再读取 `docs/aios/EVALUATION_PROTOCOL.md`

没有当前 Task 时，由 Master 在当前 Phase envelope 内选择并完成内部审查；未形成
canonical Contract 与 phase-delegated Task authority 前，Worker 不得开始实现。

## Phase-level Delegation

一个可执行 Task 必须定义目标、Why Now、Owner、读写范围、预算、验收/失败标准、Evidence、Reviewer、rollback 和 Stop Condition。当前 Phase 已由 Founder 批准；Master 在 `FOUNDER_DELEGATION_POLICY.md` 边界内签发普通 Task authority，Agent 自主完成范围内的设计、编码、测试、修复和 Task Gate，不逐 Task、逐文件或逐命令请求 Founder。

- 一个 Task ID、一个有效 Contract、一个短生命周期分支和 worktree。
- 一个文件同一时刻只有一个实现 Owner。
- 实现者不能独立验收自己的成果。
- 普通错误在原 Task 和预算内修复；禁止自动创建 successor/replacement/normalization。
- 只有触及 Founder 保留的战略、Phase、重大范围/预算/权限、高风险外部效果、不可逆动作或 critical risk 接受时才升级 Founder。
- Task Gate 通过后，Master 可自主集成本地 `main`；Phase Gate 仍由 Founder 决定。

## 当前 P1 边界

允许：Evaluation Harness、schema、synthetic conformance fixture、local test/replay/evidence 和独立审查。

不允许：Supervisor、Root Custody、完整 Trust Runtime、Multi-Agent Runtime、Agent Shell、system-under-test 写 canonical source、真实受限源码外发、remote write、生产副作用或能力夸大。

继承业务代码当前默认冻结。只有当前 Task 明确列入 write scope 时才能修改。

## 验证

```bash
make aios-governance-check
make p1-safety-check
make verify
git diff --check
```

专项变更至少运行对应语言测试。未运行的检查必须在交付中明确说明。

## 完成报告

必须包含：Task ID/状态、变更文件、命令与真实结果、Evidence、独立审查、限制、rollback 和下一项合格行动。文档存在、实现存在、测试通过、Gate 通过与生产可用必须分开表述。
