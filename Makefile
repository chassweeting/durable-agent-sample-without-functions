.PHONY: help install emulator azurite api frontend setup env role provision deploy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────────────

env: ## Create .env from template (won't overwrite existing)
	@test -f src/.env && echo "src/.env already exists" || cp src/.env.template src/.env
	@if command -v azd >/dev/null 2>&1 && azd env list 2>/dev/null | grep -q .; then \
		echo "Populating .env from azd environment..."; \
		for key in AZURE_OPENAI_ENDPOINT AZURE_OPENAI_DEPLOYMENT_NAME; do \
			val=$$(azd env get-value $$key 2>/dev/null); \
			if [ -n "$$val" ]; then \
				if grep -q "^$$key=" src/.env; then \
					sed -i '' "s|^$$key=.*|$$key=$$val|" src/.env; \
				else \
					echo "$$key=$$val" >> src/.env; \
				fi; \
			fi; \
		done; \
		echo "Done — .env updated with Azure OpenAI settings"; \
	else \
		echo "Edit src/.env — set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT_NAME"; \
	fi

install: ## Install Python (Poetry) and Node dependencies
	cd src/api && poetry install
# 	cd src/frontend && npm install

setup: env install ## Full local setup (env + dependencies)

role: ## Assign Cognitive Services OpenAI User role to current az login identity
	./scripts/assign-openai-role.sh

# ── Infrastructure ─────────────────────────────────────

emulator: ## Start the Durable Task Scheduler emulator (Docker)
	docker run -d --name dts-emulator -p 8080:8080 mcr.microsoft.com/dts/dts-emulator:latest
	@echo "DTS emulator running on localhost:8080"

azurite: ## Start Azure Storage emulator (Azurite)
	npx azurite --silent --location ./.azurite &
	@echo "Azurite running"

local-infra: emulator azurite ## Start all local infrastructure (emulators)

provision: ## Provision Azure resources (OpenAI, DTS, Storage, etc.)
	azd provision
	@echo "Run 'make env' to populate .env from provisioned resources"

deploy: ## Deploy app to Azure Container Apps
	azd deploy

# ── Application ────────────────────────────────────────

api: ## Start the backend API (FastAPI + Durable Task worker)
	cd src/api && poetry run uvicorn app:app --reload --port 8000

frontend: ## Start the React frontend dev server
	cd src/frontend && npm start

# ── Cleanup ────────────────────────────────────────────

clean: ## Stop and remove the DTS emulator container
	-docker stop dts-emulator 2>/dev/null
	-docker rm dts-emulator 2>/dev/null
	@echo "Cleaned up"
