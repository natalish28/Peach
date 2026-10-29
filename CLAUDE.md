# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

"Peach": a monorepo with a FastAPI backend (`backend/`) and a Next.js + shadcn/ui frontend (`frontend/`), with no shared source between them. Locally it runs under Docker Compose (Postgres + backend + frontend); in production it runs on AWS (see Deployment). `README.md` is the original generation spec; `LAB5_SUBMISSION.md` documents the weekly-reports lab.

## Commands

Everything day-to-day goes through the `Makefile` (`make help` lists targets). Tests, lint and migrations run **inside the Compose containers**, so the stack must be up (`make up`; UI on :3000, API on :8000, docs at :8000/docs).

- `make test` / `make test-backend` / `make test-frontend`
- Single backend test: `docker compose exec backend pytest tests/test_items.py::test_name`
- Single frontend test: `docker compose exec frontend pnpm vitest run tests/api.test.ts`
- `make lint` (ruff + eslint), `make fmt` (ruff format + prettier). CI (`.github/workflows/lint.yml`) runs `ruff check`, `ruff format --check`, eslint and prettier check.
- `make migrate`; `make revision m="add x"` autogenerates an Alembic migration (`backend/migrations/versions/`).
- Backend outside Docker: `cd backend && uv sync && uv run ruff check .` (Python 3.14, uv). Frontend: pnpm 10, Node 22.

Backend tests use a separate database (`TEST_DATABASE_URL`, or `DATABASE_URL` with a `_test` suffix) whose schema is dropped and recreated — never point it at the runtime DB. Auth in tests uses a test signing key from `tests/tokens.py`, configured before `app` is imported (order in `conftest.py` matters).

## Architecture

**Backend** (`backend/app`): `main.py` builds the app; `api/routes/` (health, items, me) → `services/items.py` → SQLAlchemy 2 async models in `models/` (`asyncpg`). `auth.py` provides the `current_user` dependency: validates a Cognito ID token (JWT via JWKS) from the `Authorization` header and upserts a `User`. Config comes from pydantic-settings in `config.py` (`auth_configured` gates auth; unconfigured returns 503).

**Two Lambda entry points** reuse the same code:
- `app/lambda_handler.py` — FastAPI via Mangum behind a Lambda function URL. It also handles a direct-invoke `{"action": "migrate"}` event (run after each deploy; `make migrate-backend`). It owns a single event loop because of Python 3.14 / Mangum / alembic `asyncio.run` interactions — don't remove that.
- `app/reports/` — event-driven weekly report pipeline (Lab 5): EventBridge Scheduler or SQS message (`make report-now WEEK=2026-W41`) → `reports/lambda_handler.py` (report-builder; queries DB via `reports/weekly.py`, writes CSV to S3) → S3 event → `reports/mailer.py` (report-mailer; sends via SES). Weeks are ISO weeks (`%G-W%V`).

**Agenda parser** (Lab 6, `LAB6_SUBMISSION.md`, `docs/adr/0006-llm-agenda-parsing.md`): `app/ai/agenda.py` is a plain function (Claude on Bedrock via `anthropic[bedrock]`, forced-by-prompt `record_agenda` tool, Pydantic validation, one retry); `app/ai/agenda_lambda.py` wraps it behind its own function URL (`infra/ai.yml`, `make deploy-ai`), outside the VPC, verifying the Cognito token via `app/security.py`. The model only suggests: saving goes through `POST /api/v1/agendas`, which stores the suggestion in `agendas.ai_suggestion`. `PARSER_MODEL` selects the model; `make parse TEXT="..."` runs it locally.

**Frontend** (`frontend/`): Next.js 16 App Router, Tailwind v4, shadcn components in `components/ui/` (generated; `components.json`). Data fetching via TanStack Query with `lib/api.ts`. Auth is client-side in `lib/auth.ts`: Google sign-in through Cognito Hosted UI, authorization-code exchange at `app/auth/callback`, tokens in localStorage, sent as bearer to the API. `NEXT_OUTPUT` selects `standalone` (Docker) or `export` (static, for S3/CloudFront); `NEXT_PUBLIC_*` vars are baked in at build time (`NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_COGNITO_*`, `NEXT_PUBLIC_PARSER_URL`).
- `frontend/AGENTS.md` (included by `frontend/CLAUDE.md`): this Next.js version has breaking changes — read the relevant guide in `frontend/node_modules/next/dist/docs/` before writing Next code.

## Deployment (AWS, CloudFormation in `infra/`, driven by `scripts/*.sh`)

`make deploy-cognito` → `deploy-backend` (image to ECR, Lambda + Aurora Serverless v2, runs migrations, writes `BACKEND_URL` to `.env`) → `deploy-frontend` (static export to S3 + CloudFront; `make cert`/`make domain` for a custom domain) → `deploy-reports` (`infra/reports.yaml`). `make github-role` creates the OIDC role used by `.github/workflows/deploy-backend.yml`. `make logs-backend` / `logs-reports` tail CloudWatch. Deploy scripts read and write the repo-root `.env` (see `.env.example`).
