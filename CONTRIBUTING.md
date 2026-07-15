# Contributing to SourceLens AIOS

## 开始前

按顺序读取：

1. `docs/aios/truth/project_state.yaml`
2. `docs/aios/STRATEGIC_CONSTITUTION.md`
3. `docs/aios/MASTER_EXECUTION_PROTOCOL.md`
4. 当前 Task Contract
5. 能力研究再读取 `docs/aios/EVALUATION_PROTOCOL.md`

没有当前 Task 或执行授权时，不得自行开始实现。

## Task-level Delegation

一个可执行 Task 必须定义目标、Why Now、Owner、读写范围、预算、验收/失败标准、Evidence、Reviewer、rollback 和 Stop Condition。Founder 批准整个 Task envelope；范围内的普通编码、测试和修复由 Agent 自主完成，不逐文件审批。

- 一个 Task ID、一个有效 Contract、一个短生命周期分支和 worktree。
- 一个文件同一时刻只有一个实现 Owner。
- 实现者不能独立验收自己的成果。
- 普通错误在原 Task 和预算内修复；禁止自动创建 successor/replacement/normalization。
- 只有范围、权限、预算、战略或重大风险变化才升级 Founder。

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
