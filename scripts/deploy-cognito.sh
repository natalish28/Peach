#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/cognito.yaml"
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
STACK_NAME="${PROJECT_NAME}-cognito"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no usable AWS credentials - check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in .env"

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

CALLBACK_URLS="http://localhost:3000,http://localhost:3000/auth/callback"
LOGOUT_URLS="http://localhost:3000"

if [[ -n "${DOMAIN_NAME:-}" ]]; then
  CALLBACK_URLS="${CALLBACK_URLS},https://${DOMAIN_NAME},https://${DOMAIN_NAME}/auth/callback"
  LOGOUT_URLS="${LOGOUT_URLS},https://${DOMAIN_NAME}"
fi

PARAMS=(
  ProjectName="${PROJECT_NAME}"
  CallbackUrls="${CALLBACK_URLS}"
  LogoutUrls="${LOGOUT_URLS}"
)

if [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  PARAMS+=(
    GoogleClientId="${GOOGLE_CLIENT_ID}"
    GoogleClientSecret="${GOOGLE_CLIENT_SECRET}"
  )
  GOOGLE_ENABLED="true"
else
  GOOGLE_ENABLED="false"
fi

log "deploying Cognito stack ${STACK_NAME} in ${AWS_REGION}"

aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "${PARAMS[@]}" \
  --no-fail-on-empty-changeset \
  --tags "PROJECT_NAME=${PROJECT_NAME}"

outputs() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

USER_POOL_ID="$(outputs UserPoolId)"
CLIENT_ID="$(outputs ClientId)"
DOMAIN="$(outputs Domain)"

env_set COGNITO_REGION "${AWS_REGION}"
env_set COGNITO_USER_POOL_ID "${USER_POOL_ID}"
env_set COGNITO_CLIENT_ID "${CLIENT_ID}"
env_set COGNITO_DOMAIN "${DOMAIN}"
env_set COGNITO_GOOGLE_ENABLED "${GOOGLE_ENABLED}"

echo
log "Cognito User Pool successfully deployed!"
echo "  COGNITO_REGION=${AWS_REGION}"
echo "  COGNITO_USER_POOL_ID=${USER_POOL_ID}"
echo "  COGNITO_CLIENT_ID=${CLIENT_ID}"
echo "  COGNITO_DOMAIN=${DOMAIN}"
echo "  COGNITO_GOOGLE_ENABLED=${GOOGLE_ENABLED}"
if [[ "${GOOGLE_ENABLED}" == "true" ]]; then
  echo "  Google OAuth Redirect URI: https://${DOMAIN}/oauth2/idpresponse"
fi
echo
echo "Values written to .env."
