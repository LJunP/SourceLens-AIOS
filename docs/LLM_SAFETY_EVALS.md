# SourceLens AIOS LLM Safety 本地样例

当前只保留不联网的 Prompt Injection 与输出质量 fixture，用来保护继承实现中的
不可信数据包装边界。

## 运行

```bash
make llm-safety-check
```

该命令：

- 校验 `llm-safety-evals/prompt-injection-cases.json`；
- 校验 `llm-safety-evals/output-quality-cases.json`；
- 检查关键入口仍通过 `PromptInjectionGuard` 包装不可信内容；
- 运行相关后端测试。

## Claim boundary

这些 fixture 不调用真实 Provider，不证明模型质量、真实攻击抵抗、工具隔离、生产安全
或 P1 baseline 能力。真实 Provider、真实源码和外部网络仍未授权；未来如需评估，必须
由独立 Task 明确数据许可、Secret、预算、证据和退出条件。
