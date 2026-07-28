.PHONY: help deps up up-infra down logs logs-backend dev backend backend-jar frontend analyzer verify clean clean-local-generated code-map code-map-check aios-governance-check p1-safety-check p1-harness-check p1-environment-snapshot-check p1-task-dataset-check p1-experiment-pack-reentry-check p1-finite-typed-patch-ir-check p1-offline-b0-complete-evidence-check p1-blind-admission-check p1-stable-replay-projection-check p1-offline-scheduled-matrix-check p1-accepted-shared-trace-check p1-116-closed-profile-scanner-admission-check p1-125-six-task-parameterized-check p1-accepted-execution-spine-check script-check api-design-check db-schema-check dependency-check llm-safety-check mysql-flyway-smoke test-backend test-frontend test-analyzer

help: ## 显示当前有效命令
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

deps: up-infra ## 启动本地 MySQL 与 Redis

up: ## 启动本地 Docker Compose 服务
	cd deploy && docker compose up -d

up-infra: ## 仅启动 MySQL 与 Redis
	cd deploy && docker compose up -d mysql redis

down: ## 停止本地 Docker Compose 服务
	cd deploy && docker compose down

logs: ## 查看所有本地服务日志
	cd deploy && docker compose logs -f

logs-backend: ## 查看后端日志
	cd deploy && docker compose logs -f backend

dev: ## 显示本地开发启动顺序
	@echo "1. make up-infra"
	@echo "2. make backend"
	@echo "3. make frontend"

backend: ## 启动本地 Spring Boot 后端
	./scripts/run-backend-dev.sh

backend-jar: ## 启动已打包的稳定后端 jar
	./scripts/run-backend-jar-dev.sh

frontend: ## 启动 Vite 前端
	cd web-console && npm run dev

analyzer: ## 构建 Rust analyzer
	cd analyzer-rust && cargo build --release --locked
	mkdir -p bin
	cp analyzer-rust/target/release/sourcelens-analyzer bin/

verify: p1-harness-check p1-environment-snapshot-check p1-task-dataset-check p1-experiment-pack-reentry-check p1-finite-typed-patch-ir-check p1-offline-b0-complete-evidence-check p1-blind-admission-check p1-stable-replay-projection-check p1-offline-scheduled-matrix-check p1-accepted-shared-trace-check p1-accepted-execution-spine-check ## 运行当前 P1 开发基线验证
	./scripts/verify-all.sh

test-backend: ## 运行后端测试
	cd backend-spring && mvn clean test

test-frontend: ## 构建前端
	cd web-console && npm run build

test-analyzer: ## 检查并测试 Rust analyzer
	cd analyzer-rust && cargo check --locked && cargo test --locked

code-map: ## 重新生成当前代码地图
	node scripts/generate-project-code-map.mjs

code-map-check: ## 校验代码地图同步性
	node scripts/generate-project-code-map.mjs --check

aios-governance-check: ## 校验最小当前权威、P1 边界和历史隔离
	ruby scripts/test-current-task-authority.rb
	ruby scripts/test-strict-phase-gates.rb
	ruby scripts/test-founder-knowledge-sync.rb
	./scripts/validate-aios-governance.sh

p1-safety-check: ## 校验 P1 cooperative-local 基础安全声明
	./scripts/check-p1-safety-boundary.sh

p1-harness-check: ## 校验 AIOS-P1-001 最小 Evaluation Harness
	./scripts/verify-p1-harness.sh

p1-environment-snapshot-check: ## 校验 AIOS-P1-011 Environment Snapshot capture/replay
	./scripts/verify-p1-environment-snapshot.sh

p1-task-dataset-check: ## 校验 AIOS-P1-035 代表性任务数据集与确定性物化
	./scripts/verify-p1-task-dataset.sh

p1-experiment-pack-reentry-check: ## 校验 AIOS-P1-048 实际 Experiment Pack 与负向控制
	./scripts/verify-p1-experiment-pack-reentry.sh

p1-finite-typed-patch-ir-check: ## 校验 AIOS-P1-055 有限 Typed Patch IR compiler 与 trusted runner
	./scripts/verify-p1-finite-typed-patch-ir-v1.sh

p1-offline-b0-complete-evidence-check: ## 校验 AIOS-P1-066 离线 B0 完整 Evidence 纵向切片
	./scripts/verify-p1-066-offline-b0.sh

p1-blind-admission-check: ## 校验 AIOS-P1-069 clean-room blind admission harness
	./scripts/verify-p1-069-blind-admission-harness.sh

p1-stable-replay-projection-check: ## 校验 AIOS-P1-071 stable replay projection v2
	./scripts/verify-p1-071-stable-replay-projection.sh

p1-offline-scheduled-matrix-check: ## 校验 AIOS-P1-070 offline scheduled matrix 与独立 VTSR 重算
	./scripts/verify-p1-070-offline-scheduled-matrix.sh

p1-accepted-shared-trace-check: ## 校验 AIOS-P1-101 accepted B0/B1/B2 shared observable trace
	./scripts/verify-p1-101-accepted-shared-trace.sh

p1-116-closed-profile-scanner-admission-check: ## 校验 P1-116 闭合 Profile、身份绑定回滚与无网络扫描
	./scripts/verify-p1-116-closed-profile-scanner-admission.sh

p1-125-six-task-parameterized-check: ## 校验 P1-129 补齐安全矩阵后的六任务参数化离线适配器组合
	@set -eu; \
	node --check evaluation-harness/harness/p1-125-six-task-parameterized/run.mjs; \
	node --check evaluation-harness/evaluator/p1-125-six-task-parameterized/run-matrix.mjs; \
	owned_parent="$$(mktemp -d /private/tmp/sourcelens-p1-129-verify.XXXXXX)"; \
	output_root="$$owned_parent/formal"; \
	node evaluation-harness/evaluator/p1-125-six-task-parameterized/run-matrix.mjs \
	  --worker-entry "$$(pwd)/evaluation-harness/harness/p1-125-six-task-parameterized/run.mjs" \
	  --output-root "$$output_root"; \
	node -e 'const fs=require("node:fs");const v=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const zero=Object.values(v.external_effects).every((x)=>x===false);if(v.status!=="PASS"||v.accepted_task_count!==6||v.positive_runs!==36||v.distinct_positive_run_roots!==36||v.exact_stable_pairs!==18||v.b1_exact_rollbacks!==12||v.b2_real_repository_analysis_scan_children!==12||v.negative_cases!==53||v.false_accepts!==0||v.nonowned_residuals!==0||!zero)throw new Error(`P1-129 summary NON_PASS: $${JSON.stringify(v)}`);' "$$output_root/quality-formal-summary.json"
	@echo "P1_129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION: PASS"

p1-accepted-execution-spine-check: ## 校验 P1-149 accepted Patch compiler、trace、rollback 与独立 evaluator execution spine
	./scripts/verify-p1-149-accepted-execution-spine.sh

script-check: ## 检查当前 Shell 脚本语法
	@for script in scripts/*.sh; do bash -n "$$script"; done

api-design-check: ## 校验后端路由与 API 文档
	node scripts/validate-api-design.mjs

db-schema-check: ## 校验数据库 schema 合同
	node scripts/validate-db-schema-contract.mjs

dependency-check: ## 校验依赖与供应链边界
	./scripts/dependency-regression-check.sh

llm-safety-check: ## 运行本地 LLM safety fixture 验证
	./scripts/llm-safety-regression.sh

mysql-flyway-smoke: ## 可选真实 MySQL Flyway smoke
	./scripts/mysql-flyway-migration-smoke.sh

clean-local-generated: ## 删除可重建的本地产物
	./scripts/clean-local-generated.sh

clean: clean-local-generated ## 清理本地产物
	rm -rf -- bin
