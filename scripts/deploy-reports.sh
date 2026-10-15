#!/usr/bin/env bash
# Deploy Lab 5 event-driven reports stack (ECR image -> CloudFormation infra/reports.yaml).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/reports.yaml"
ENV_FILE="${ROOT}/.env"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
STACK_NAME="${PROJECT_NAME}-reports"
BACKEND_STACK_NAME="${PROJECT_NAME}-backend"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no usable AWS credentials - check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in .env"

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

# --- gather backend params --------------------------------------------------

log "fetching backend configuration from ${BACKEND_STACK_NAME}"
backend_param() {
  aws cloudformation describe-stacks --stack-name "${BACKEND_STACK_NAME}" \
    --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue" --output text 2>/dev/null || true
}

VPC_ID="$(backend_param VpcId)"
SUBNET_IDS="$(backend_param SubnetIds)"
COGNITO_USER_POOL_ID="$(backend_param CognitoUserPoolId)"
COGNITO_CLIENT_ID="$(backend_param CognitoClientId)"
COGNITO_JWKS="$(backend_param CognitoJwks)"

[[ -n "${VPC_ID}" ]] || VPC_ID="vpc-0b1ce9b8049973a6d"
[[ -n "${SUBNET_IDS}" ]] || SUBNET_IDS="subnet-044020ec1d4a6241b,subnet-0acfaa4b99edae048"

# Route tables in the VPC
ROUTE_TABLE_IDS="$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "RouteTables[].RouteTableId" --output text | tr '\t' ',')"

# Security group
SG_IDS="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[?GroupName=='default'].GroupId" --output text | tr '\t' ',')"
[[ -n "${SG_IDS}" ]] || SG_IDS="sg-0fe983c4fef15fde0"

# Database URL
DATABASE_URL="$(aws lambda get-function-configuration --function-name "${PROJECT_NAME}-backend" \
  --query "Environment.Variables.DATABASE_URL" --output text 2>/dev/null || true)"
[[ -n "${DATABASE_URL}" && "${DATABASE_URL}" != "None" ]] \
  || die "could not read DATABASE_URL from ${PROJECT_NAME}-backend Lambda"

# Email addresses
REPORTS_FROM_EMAIL="${REPORTS_FROM_EMAIL:-shymanska.pn@ucu.edu.ua}"
REPORTS_TO_EMAIL="${REPORTS_TO_EMAIL:-shymanska.pn@ucu.edu.ua}"

# --- build & push image to ECR ----------------------------------------------

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPOSITORY="${PROJECT_NAME}-backend"
LAMBDA_ARCHITECTURE="${LAMBDA_ARCHITECTURE:-arm64}"

if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(git -C "${ROOT}" rev-parse --short=12 HEAD)-reports-$(date -u +%Y%m%d%H%M%S)"
fi
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

log "building and pushing ${IMAGE_URI} for linux/${LAMBDA_ARCHITECTURE}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null

docker buildx build \
  --platform "linux/${LAMBDA_ARCHITECTURE}" \
  --target lambda \
  --no-cache \
  --provenance=false \
  --sbom=false \
  --tag "${IMAGE_URI}" \
  --push \
  "${ROOT}/backend"

# --- deploy CloudFormation stack --------------------------------------------

log "deploying reports stack ${STACK_NAME} in ${AWS_REGION}"

aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides \
    ProjectName="${PROJECT_NAME}" \
    VpcId="${VPC_ID}" \
    SubnetIds="${SUBNET_IDS}" \
    SecurityGroupIds="${SG_IDS}" \
    RouteTableIds="${ROUTE_TABLE_IDS}" \
    ImageUri="${IMAGE_URI}" \
    DatabaseUrl="${DATABASE_URL}" \
    CognitoJwks="${COGNITO_JWKS}" \
    CognitoUserPoolId="${COGNITO_USER_POOL_ID}" \
    CognitoClientId="${COGNITO_CLIENT_ID}" \
    ReportsFromEmail="${REPORTS_FROM_EMAIL}" \
    ReportsToEmail="${REPORTS_TO_EMAIL}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"

outputs() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BUCKET="$(outputs ReportsBucketName)"
QUEUE_URL="$(outputs ReportRequestsQueueUrl)"
QUEUE_ARN="$(outputs ReportRequestsQueueArn)"

env_set REPORTS_BUCKET "${BUCKET}"
env_set REPORT_REQUESTS_QUEUE_URL "${QUEUE_URL}"
env_set REPORTS_FROM_EMAIL "${REPORTS_FROM_EMAIL}"
env_set REPORTS_TO_EMAIL "${REPORTS_TO_EMAIL}"

echo
log "Reports stack successfully deployed!"
echo "  REPORTS_BUCKET=${BUCKET}"
echo "  REPORT_REQUESTS_QUEUE_URL=${QUEUE_URL}"
echo "  REPORTS_FROM_EMAIL=${REPORTS_FROM_EMAIL}"
echo "  REPORTS_TO_EMAIL=${REPORTS_TO_EMAIL}"
echo
echo "Try running: make report-now WEEK=2026-W41"

