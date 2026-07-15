# SourceLens AIOS 安全边界

当前安全事实以 `docs/aios/truth/project_state.yaml` 为准，详细工程边界见
`docs/SECURITY_BOUNDARY.md`。本文件只保留当前阶段可执行的最低规则。

## 漏洞报告

不要在公开 Issue 或 Pull Request 中披露安全漏洞、Secret、Token、私钥、
原始提示词、模型响应、源码片段或可利用细节。先通过 Founder 指定的私密渠道报告。

## P1 基础边界

- 不把文档声明当作技术强制或生产安全证明。
- 未经单独授权，不允许网络、真实 Provider、Secret、远程写入或生产副作用。
- 不允许 Agent 自主修改 canonical main，也不允许实现者独立验收自己的成果。
- 所有 Task 必须声明允许路径、禁止行为、预算、停止条件、回滚点和证据要求。
- 任何安全边界扩大、证据缺失、验证失败或独立 Reviewer 非 PASS 都必须停止并升级。

## 审查要求

安全相关变更至少需要 CTO、Security、Quality 三方中与风险相匹配的独立审查。
当前基础检查入口为：

```bash
make aios-governance-check
make p1-safety-check
make verify
```

P3 之前不声称已具备 Supervisor、Root Custody、强隔离、敌对主体抵抗、完整
Capability System 或生产级 Trust Runtime。
