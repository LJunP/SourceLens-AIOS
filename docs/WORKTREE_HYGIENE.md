# SourceLens AIOS 工作树卫生规则

本文件只规定当前 canonical repository 的工作树卫生，不承载 Phase、Goal、Gate 或
Truth 状态。

## 唯一开发规则

- `main` 是唯一 canonical source branch。
- 一个已授权 Task 最多使用一个 Task branch 和一个 implementation worktree。
- audit、evidence、offsite 与依赖缓存不得作为源码事实源。
- 未经独立审查与 Master Task Gate，不得推进 `main`；触及 Founder 保留事项时还必须先取得 exact Founder decision。

## 生成物

以下内容必须保持未跟踪并可重建：

- `backend-spring/target/`
- `analyzer-rust/target/`
- `web-console/dist/`
- `web-console/tsconfig*.tsbuildinfo`
- `bin/`
- `.DS_Store`

可用以下命令清理和核验：

```bash
make clean
git status --short
git worktree list
```

禁止对用户未授权的工作树执行 `stash`、`reset --hard`、`clean -fdx` 或删除操作。
