.PHONY: help deps up up-infra down logs logs-backend dev backend backend-jar frontend analyzer verify clean clean-local-generated code-map code-map-check aios-governance-check p1-safety-check p1-harness-check script-check api-design-check db-schema-check dependency-check llm-safety-check mysql-flyway-smoke test-backend test-frontend test-analyzer

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

verify: p1-harness-check ## 运行当前 P1 开发基线验证
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
	./scripts/validate-aios-governance.sh

p1-safety-check: ## 校验 P1 cooperative-local 基础安全声明
	./scripts/check-p1-safety-boundary.sh

p1-harness-check: ## 校验 AIOS-P1-001 最小 Evaluation Harness
	./scripts/verify-p1-harness.sh

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
