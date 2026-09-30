#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  preset="$(export -p)"
  set -a
  source "${ENV_FILE}"
  set +a
  eval "${preset}"
fi

PROJECT_NAME="${PROJECT_NAME:-peach}"
STACK_NAME="${PROJECT_NAME}-cognito"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

echo "Deleting stack ${STACK_NAME}..."
aws cloudformation delete-stack --stack-name "${STACK_NAME}"
aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
echo "Stack ${STACK_NAME} deleted."
