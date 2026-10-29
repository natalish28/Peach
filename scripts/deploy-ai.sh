#!/usr/bin/env bash
# Deploy Lab 6: build + push the backend image, create/update infra/ai.yml
# (agenda-parser Lambda + function URL + $5 budget), write PARSER_URL to .env.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/ai.yml"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
STACK_NAME="${PROJECT_NAME}-ai"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
PARSER_MODEL="${PARSER_MODEL:-anthropic.claude-opus-5-5}"
LAMBDA_ARCHITECTURE="${LAMBDA_ARCHITECTURE:-arm64}"
case "${LAMBDA_ARCHITECTURE}" in
  arm64) CFN_ARCHITECTURE=arm64 ;;
  amd64) CFN_ARCHITECTURE=x86_64 ;;
  *) die "LAMBDA_ARCHITECTURE must be arm64 or amd64, got '${LAMBDA_ARCHITECTURE}'" ;;
esac

[[ -n "${COGNITO_USER_POOL_ID:-}" && -n "${COGNITO_CLIENT_ID:-}" ]] \
  || die "COGNITO_USER_POOL_ID / COGNITO_CLIENT_ID are not set in .env - run make deploy-cognito first"
[[ -n "${BUDGET_EMAIL:-}" ]] \
  || die "BUDGET_EMAIL is not set in .env - the \$5 budget alarm needs somewhere to go"

aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no usable AWS credentials - check .env"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

env_set() {
  KEY="$1" VALUE="$2" ENV_FILE="${ENV_FILE}" python3 - <<'PY'
import os, re

key, value, path = os.environ["KEY"], os.environ["VALUE"], os.environ["ENV_FILE"]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pattern = re.compile(rf"^{re.escape(key)}=")
for i, line in enumerate(lines):
    if pattern.match(line):
        lines[i] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")
open(path, "w").write("\n".join(lines) + "\n")
PY
}

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "${ROOT}" rev-parse --short=12 HEAD)-ai-$(date -u +%Y%m%d%H%M%S)}"
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

log "building and pushing ${IMAGE_URI} for linux/${LAMBDA_ARCHITECTURE}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
docker buildx build \
  --platform "linux/${LAMBDA_ARCHITECTURE}" \
  --target lambda \
  --provenance=false --sbom=false \
  --tag "${IMAGE_URI}" --push \
  "${ROOT}/backend"

# The site's origin, once it has one; until then any origin may call the parser
# (it still needs a valid Cognito token).
ORIGINS="${PARSER_CORS_ORIGINS:-*}"

log "deploying ${STACK_NAME} in ${AWS_REGION} (model ${PARSER_MODEL})"
aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "ImageUri=${IMAGE_URI}" \
    "Architecture=${CFN_ARCHITECTURE}" \
    "ParserModel=${PARSER_MODEL}" \
    "CognitoUserPoolId=${COGNITO_USER_POOL_ID}" \
    "CognitoClientId=${COGNITO_CLIENT_ID}" \
    "AllowedOrigins=${ORIGINS}" \
    "BudgetEmail=${BUDGET_EMAIL}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"

PARSER_URL="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='ParserUrl'].OutputValue" --output text)"
env_set PARSER_URL "${PARSER_URL}"
env_set PARSER_MODEL "${PARSER_MODEL}"

echo
log "agenda parser deployed: PARSER_URL=${PARSER_URL}"
echo "Next: make deploy-frontend (bakes PARSER_URL into the bundle)"
