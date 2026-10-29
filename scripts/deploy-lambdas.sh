#!/usr/bin/env bash
# Build the backend image, push it to ECR and point the report builder and/or the agenda
# parser at it: make deploy-reports / make deploy-ai.
#
# Terraform (infra/, applied by HCP Terraform) owns the shape of these functions: role,
# memory, environment, URL. This script only changes which build runs, with
# update-function-code. Terraform ignores image_uri, so the two never fight.
#
# usage: scripts/deploy-lambdas.sh parser | builder | all
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
TARGET="${1:-all}"

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

# A blank AWS_PROFILE or blank keys (a .env of empty placeholders) would break the chain.
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
LAMBDA_ARCHITECTURE="${LAMBDA_ARCHITECTURE:-arm64}"

case "${TARGET}" in
  parser) FUNCTIONS=("${PROJECT_NAME}-agenda-parser") ;;
  builder) FUNCTIONS=("${PROJECT_NAME}-report-builder") ;;
  all) FUNCTIONS=("${PROJECT_NAME}-agenda-parser" "${PROJECT_NAME}-report-builder") ;;
  *) die "usage: $0 parser | builder | all" ;;
esac

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "no usable AWS credentials"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "${ROOT}" rev-parse --short=12 HEAD)-lambda-$(date -u +%Y%m%d%H%M%S)}"
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY:-${PROJECT_NAME}-backend}:${IMAGE_TAG}"

log "building and pushing ${IMAGE_URI} for linux/${LAMBDA_ARCHITECTURE}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
docker buildx build \
  --platform "linux/${LAMBDA_ARCHITECTURE}" \
  --target lambda \
  --provenance=false --sbom=false \
  --tag "${IMAGE_URI}" --push \
  "${ROOT}/backend"

for fn in "${FUNCTIONS[@]}"; do
  log "updating ${fn}"
  aws lambda update-function-code --function-name "${fn}" --image-uri "${IMAGE_URI}" \
    --query 'LastUpdateStatus' --output text >/dev/null
  aws lambda wait function-updated --function-name "${fn}"
done

log "done: ${FUNCTIONS[*]} now run ${IMAGE_TAG}"
