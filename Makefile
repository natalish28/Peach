COMPOSE := docker compose

-include .env
export

.PHONY: help up down build logs ps migrate revision test test-backend test-frontend lint fmt clean shell-backend shell-db deploy-cognito destroy-cognito deploy-backend destroy-backend logs-backend migrate-backend cert domain deploy-frontend destroy-frontend github-role deploy-reports report-now logs-reports

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (detached)
	$(COMPOSE) up -d --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

build: ## Rebuild images
	$(COMPOSE) build

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

test: test-backend test-frontend ## Run all tests

test-backend: ## Run backend tests
	$(COMPOSE) exec backend pytest

test-frontend: ## Run frontend tests
	$(COMPOSE) exec frontend pnpm test

lint: ## Lint both sides
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend pnpm lint

fmt: ## Format both sides
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

shell-backend: ## Shell into the backend container
	$(COMPOSE) exec backend bash

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-peach} -d $${POSTGRES_DB:-peach}

deploy-cognito: ## Create/update the Cognito user pool; writes COGNITO_* to .env and prints them
	./scripts/deploy-cognito.sh

destroy-cognito: ## Delete the Cognito stack, every account in the pool included
	./scripts/destroy-cognito.sh

deploy-backend: ## Build + push the image, roll the Lambda (function URL + Aurora), migrate, write BACKEND_URL to .env
	./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, Aurora cluster included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-peach}-backend --follow --since 10m

migrate-backend: ## Re-run migrations on the deployed backend (deploy-backend already does)
	aws lambda invoke --function-name $${PROJECT_NAME:-peach}-backend \
		--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' /dev/stdout

cert: ## Request + DNS-validate a us-east-1 certificate for the frontend: make cert DOMAIN=app.example.com
	./scripts/domain-frontend.sh cert

domain: ## Assign a custom domain to the frontend: make domain DOMAIN=app.example.com
	./scripts/domain-frontend.sh domain

deploy-frontend: ## Build the static export against BACKEND_URL and ship it to S3 + CloudFront
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the frontend stack (bucket + distribution)
	./scripts/destroy-frontend.sh

github-role: ## Create the IAM role GitHub Actions assumes to deploy (OIDC, no keys)
	./scripts/github-role.sh

deploy-reports: ## Deploy the event-driven weekly reports stack (S3, SQS, Scheduler, Lambdas)
	./scripts/deploy-reports.sh

report-now: ## Request an on-demand weekly report via SQS: make report-now [WEEK=2026-W41]
	@unset AWS_PROFILE; \
	QUEUE_URL="$$(aws cloudformation describe-stacks --region $${AWS_REGION:-us-east-1} --stack-name $${PROJECT_NAME:-peach}-reports --query "Stacks[0].Outputs[?OutputKey=='ReportRequestsQueueUrl'].OutputValue" --output text 2>/dev/null || true)"; \
	if [ -z "$$QUEUE_URL" ] || [ "$$QUEUE_URL" = "None" ]; then \
	  echo "Error: ReportRequestsQueueUrl not found. Run make deploy-reports first." >&2; exit 1; \
	fi; \
	TARGET_WEEK="$${WEEK:-$$(date -u -v-7d +%G-W%V 2>/dev/null || date -u -d '7 days ago' +%G-W%V 2>/dev/null || echo '2026-W41')}"; \
	echo "Sending report request for week: $$TARGET_WEEK to $$QUEUE_URL"; \
	aws sqs send-message \
	  --region $${AWS_REGION:-us-east-1} \
	  --queue-url "$$QUEUE_URL" \
	  --message-body "{\"week\": \"$$TARGET_WEEK\", \"source\": \"sqs\"}"

logs-reports: ## View recent logs from builder and mailer Lambda functions
	@unset AWS_PROFILE; \
	echo "=== Report Builder Logs ==="; \
	aws --region $${AWS_REGION:-us-east-1} logs tail /aws/lambda/$${PROJECT_NAME:-peach}-report-builder --since 15m || true; \
	echo "=== Report Mailer Logs ==="; \
	aws --region $${AWS_REGION:-us-east-1} logs tail /aws/lambda/$${PROJECT_NAME:-peach}-report-mailer --since 15m || true


