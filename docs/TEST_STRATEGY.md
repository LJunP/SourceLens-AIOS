# SourceLens AIOS 测试策略

当前目标是建立 P1 Evaluation Harness，并保护继承代码的可构建性。测试结果必须与
其实际覆盖范围一致，不得用“命令通过”冒充能力证明。

## 当前基线

| 范围 | 入口 | 证明边界 |
| --- | --- | --- |
| 当前权威与 P1 边界 | `make aios-governance-check`、`make p1-safety-check` | 文档和配置一致性 |
| 后端 | `make test-backend` | 当前 JUnit/Maven 回归 |
| 前端 | `make test-frontend` | TypeScript 与生产构建 |
| Rust Analyzer | `make test-analyzer` | 当前 Rust check/test |
| API/DB | `make api-design-check`、`make db-schema-check` | 静态契约同步 |
| LLM 输入边界 | `make llm-safety-check` | 本地 fixture 和 Guard 回归 |
| 依赖 | `make dependency-check` | lockfile、固定引用和供应链静态边界 |
| 全部当前基线 | `make verify` | 上述检查的集合 |

## 改动要求

- 行为改动必须包含对应单元或集成测试。
- API、DB、schema、evaluation contract 改动必须同步文档和 validator。
- 失败、跳过、未执行和 UNKNOWN 必须分别记录，禁止互相替代。
- flaky 结果不得直接忽略；应停止、定位或明确收窄 claim。
- 实现者不得独立验收自己的成果。
- P1-001 的 harness stub 通过不等于 B0/B1/B2 baseline 完成。

## Task 证据最小项

每个实际 Task 至少记录：source identity、输入、配置、命令、退出状态、测试结果、
风险、Reviewer verdict 和 rollback reference。Task Gate 只接受与 exact candidate
绑定的证据；Founder 只在 Phase Gate或保留决策时审查相应绑定证据。
