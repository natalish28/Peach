#!/usr/bin/env bash
# Lab 7, migration step 3a: make CloudFormation let go of the Cognito, reports and parser
# resources without deleting them.
#   1. update each stack with the same parameters and a template where every resource has
#      DeletionPolicy/UpdateReplacePolicy: Retain;
#   2. delete the stack. The resources stay, owned by nobody, until Terraform imports them.
# Run once, before the first HCP Terraform apply with infra/imports.tf.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-peach}"
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }

release() {
  local stack="$1" template="$2"
  if ! aws cloudformation describe-stacks --stack-name "${stack}" >/dev/null 2>&1; then
    log "${stack}: already gone"
    return
  fi

  local params
  params="$(aws cloudformation describe-stacks --stack-name "${stack}" \
    --query 'Stacks[0].Parameters[].ParameterKey' --output text \
    | tr '\t' '\n' | sed 's/.*/ParameterKey=&,UsePreviousValue=true/' | tr '\n' ' ')"

  log "${stack}: setting DeletionPolicy Retain on every resource"
  # shellcheck disable=SC2086
  if aws cloudformation update-stack --stack-name "${stack}" \
      --template-body "file://${ROOT}/infra/${template}" \
      --parameters ${params} --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM >/dev/null; then
    aws cloudformation wait stack-update-complete --stack-name "${stack}"
  fi

  local retained
  retained="$(aws cloudformation get-template --stack-name "${stack}" --query TemplateBody --output text \
    | grep -c 'DeletionPolicy: Retain' || true)"
  log "${stack}: ${retained} resources marked Retain in the deployed template"

  log "${stack}: deleting the stack (resources are kept)"
  aws cloudformation delete-stack --stack-name "${stack}"
  aws cloudformation wait stack-delete-complete --stack-name "${stack}"
  log "${stack}: deleted"
}

release "${PROJECT_NAME}-cognito" cognito.yaml
release "${PROJECT_NAME}-reports" reports.yaml
release "${PROJECT_NAME}-ai" ai.yml
log "done: now merge the Terraform change, HCP Terraform imports the resources"
