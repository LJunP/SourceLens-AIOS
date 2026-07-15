# SourceLens Engineering Standards

任务、角色、独立验证和完成定义发生冲突时，以
`aios/MASTER_EXECUTION_PROTOCOL.md` 为准。

## 1. 基本原则

- 小步改动，边界清楚。
- 不做无关重构。
- 不回滚别人未确认的改动。
- 代码事实、文档事实、测试证据必须一致。
- 重要且长期有效的决策写 ADR；当前事实只进入 Truth。

## 2. 后端标准

- Controller path 变化必须同步 `API_DESIGN.md` 并跑 `make api-design-check`。
- DB 变化必须使用 Flyway migration。
- 任务状态机必须防止终态覆盖。
- 外部输入必须校验。
- raw artifact 和 file path 必须做归属/路径边界检查。

## 3. 前端标准

- 使用共享 UI 原语。
- 核心页面必须覆盖 loading/empty/error/success。
- 三视口不裁切核心内容。
- 危险操作必须有确认。
- raw 内容默认脱敏或 receipt 化。

## 4. 脚本/运维标准

- 脚本必须 fail fast。
- destructive 行为默认 dry-run 或需要显式确认。
- 当前 Task evidence 冻结后不得重写；历史证据存放在项目外封存，不进入默认上下文。
- 本地 env/secrets 不得提交。

## 5. Review 标准

Review 必须检查：

- 用户价值。
- 架构边界。
- 安全边界。
- 测试证据。
- 文档同步。
- 回滚或恢复路径。
