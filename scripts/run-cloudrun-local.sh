#!/usr/bin/env bash
# Lab 9 without a Google Cloud account: run Peach's core the way Cloud Run would run it.
#   - the backend "runtime" image (no Mangum, no Lambda adapter), started with PORT=8080 as Cloud
#     Run starts it; the entrypoint runs the migrations, then uvicorn on $PORT;
#   - a local PostgreSQL 17 instead of Cloud SQL;
#   - the frontend built against http://localhost:8080 on :3000.
# Sign-in stays on AWS Cognito, as in the GCP setup (localhost:3000 is an allowed callback).
#
#   scripts/run-cloudrun-local.sh          # build and start
#   API_HOST_PORT=8081 scripts/run-cloudrun-local.sh   # if the host port 8080 is taken
#   scripts/run-cloudrun-local.sh down     # stop and remove (the database volume too)
set -euo pipefail

cd "$(dirname "$0")/.."
NET=peach-cloudrun
DB=peach-cloudrun-db
API=peach-cloudrun-api
WEB=peach-cloudrun-web
# The container always listens on PORT=8080, as on Cloud Run. The host port can differ if 8080 is taken.
HOST_PORT="${API_HOST_PORT:-8080}"
API_URL="http://localhost:$HOST_PORT"

if [[ "${1:-}" == "down" ]]; then
  docker rm -f "$WEB" "$API" "$DB" >/dev/null 2>&1 || true
  docker volume rm peach-cloudrun-pg >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  echo "removed"
  exit 0
fi

set -a
# shellcheck disable=SC1091
[[ -f .env ]] && source .env
set +a
: "${COGNITO_USER_POOL_ID:?run make infra-env first}"
: "${COGNITO_CLIENT_ID:?run make infra-env first}"

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

echo "==> PostgreSQL (stands in for Cloud SQL)"
docker rm -f "$DB" >/dev/null 2>&1 || true
docker run -d --name "$DB" --network "$NET" \
  -e POSTGRES_USER=peach -e POSTGRES_PASSWORD=peach -e POSTGRES_DB=peach \
  -v peach-cloudrun-pg:/var/lib/postgresql/data \
  postgres:17-alpine >/dev/null
until docker exec "$DB" pg_isready -U peach -d peach >/dev/null 2>&1; do sleep 1; done

echo "==> backend image, target runtime (what deploy-gcp-backend pushes to Artifact Registry)"
docker build --target runtime -t peach-api:cloudrun backend

echo "==> API, as Cloud Run runs it: PORT=8080"
docker rm -f "$API" >/dev/null 2>&1 || true
docker run -d --name "$API" --network "$NET" \
  -e PORT=8080 -p "$HOST_PORT":8080 \
  -e K_SERVICE=peach-api \
  -e APP_ENV=production \
  -e DATABASE_URL="postgresql+asyncpg://peach:peach@$DB:5432/peach" \
  -e CORS_ORIGINS=http://localhost:3000 \
  -e COGNITO_REGION="${COGNITO_REGION:-us-east-1}" \
  -e COGNITO_USER_POOL_ID="$COGNITO_USER_POOL_ID" \
  -e COGNITO_CLIENT_ID="$COGNITO_CLIENT_ID" \
  peach-api:cloudrun >/dev/null
until curl -fsS "$API_URL/health" >/dev/null 2>&1; do sleep 1; done
echo "    $(curl -fsS "$API_URL/health")"

echo "==> frontend against $API_URL"
docker build -t peach-web:cloudrun \
  --build-arg NEXT_PUBLIC_API_URL="$API_URL" \
  --build-arg NEXT_PUBLIC_COGNITO_REGION="${COGNITO_REGION:-us-east-1}" \
  --build-arg NEXT_PUBLIC_COGNITO_CLIENT_ID="$COGNITO_CLIENT_ID" \
  --build-arg NEXT_PUBLIC_COGNITO_DOMAIN="${COGNITO_DOMAIN:-}" \
  --build-arg NEXT_PUBLIC_COGNITO_GOOGLE_ENABLED="${COGNITO_GOOGLE_ENABLED:-false}" \
  frontend
docker rm -f "$WEB" >/dev/null 2>&1 || true
docker run -d --name "$WEB" --network "$NET" -p 3000:3000 \
  -e INTERNAL_API_URL="http://$API:8080" \
  peach-web:cloudrun >/dev/null

echo
echo "Open http://localhost:3000, sign in, open /items (GET /api/v1/items reads PostgreSQL)."
echo "API logs: docker logs -f $API"
