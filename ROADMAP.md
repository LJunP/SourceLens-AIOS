# SourceLens AIOS 路线图

权威战略：`Strategic Constitution v2.3`。日期是规划区间，阶段进入只由证据和 Founder Gate 决定。

## 第一年度结果

构建并科学评估一个可信软件工程 Agent：

```text
Repository revision + bounded real Issue
  -> Environment Understanding
  -> Planning
  -> Controlled or Isolated Execution
  -> Testing
  -> Independent Verification
  -> Risk and Rollback Evidence
  -> Patch Evidence Package
  -> Human Approval
```

## 阶段路线

| Phase | 目标 | 退出证据 |
| --- | --- | --- |
| P0 Strategic Foundation | 冻结战略、迁移和评估基础 | 已完成的 Founder Gate 与可回滚 P0 基线 |
| P1 Agent Evaluation and Research Foundation | 建立 Task、环境、trace、evaluator 与 B0/B1/B2 基线 | 可复现实验报告、失败分类和 hidden-set 协议 |
| P2 Repository Intelligence | 提升任务相关的结构、符号、关系和上下文选择 | 在同任务/同预算下超过简单检索基线 |
| P3 Single-Agent Runtime + Minimum Trust | planner、executor、tool、state、checkpoint、权限与 trace | resume、隔离、动作控制和审计证据 |
| P4 Software Engineer Agent Alpha | 完成真实 Issue 到 Evidence Package | 受控真实任务上的独立验证补丁 |
| P5 Trustworthy Execution Hardening | 加固 sandbox、policy、approval、risk、rollback | 对抗与故障恢复证据 |
| P6 Reliability Research | 建立 SourceLens-Bench 和失败分类 | 可复现可靠性报告 |
| P7 Memory and Learning Research | 测试 working/project/experience memory | A/B 或 ablation 的实际收益 |
| P8 Multi-Agent Organization Research | 比较单 Agent 与多 Agent | 只有收益大于协调成本时保留多 Agent |
| P9 Organization Runtime | 身份、delegation、organization memory | 受治理的组织实验 |
| P10 Platformization | 提取稳定协议与 SDK | 第二个实现可复用 |
| P11 Second-Domain Validation | 验证抽象能否跨域 | 第二领域可复现实证 |
| P12 AI Organization OS | 产品化受治理的自主组织 | 长期条件式目标 |

## 当前 P1 顺序

1. Founder 手动安装并激活精简长期 Goal。
2. 一次 Task-level 授权启动 `AIOS-P1-001`。
3. 实现最小 Evaluation Harness：TaskSpec、EnvironmentSnapshot、SystemConfiguration、RunRecord、evaluator、replay、Evidence Manifest。
4. 以 `HARNESS_STUB` 验证工具链；该结果不计入 VTSR，也不得称为 B0。
5. 在相同任务、环境、预算和 evaluator 下运行真实 B0（Direct Model）、B1（简单检索）、B2（SourceLens Repository Intelligence）。
6. 形成 P1 Evaluation Foundation Research Artifact，由独立审查和 Founder Gate 决定是否进入 P2。

## P1 明确不做

- Supervisor、Root Custody、平台身份、完整 denial matrix 或强隔离 Runtime；
- Multi-Agent/Organization Runtime；
- Agent Shell、model-initiated canonical writes、远端 PR/merge 或生产副作用；
- GitHub App、SaaS、广泛 UI 或企业治理扩张；
- 用 synthetic fixture、stub、文档或自评宣称 Agent 能力。

## 收敛规则

- 同一目标只保留一个 Task ID 和一个有效 Contract。
- 普通实现错误在原 Task 与预算内修复；不得生成 successor、replacement、normalization 或新的治理阶段。
- 审查与风险成比例；Founder 不审批逐文件和逐命令动作。
- 治理工作不得长期超过工程与研究工作的必要比例；没有可测价值时立即停止扩张。
- P3/P5/P8/P9 的能力不得提前成为 P1 默认阻断。

## Stop Rule

当结果不可复现、不能在预算内超过声明基线、违反安全 guardrail、用户价值无法辩护，或复杂度没有可测收益时，停止而不是增加制度、功能或阶段。
