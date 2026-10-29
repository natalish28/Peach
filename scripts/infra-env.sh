#!/usr/bin/env bash
# Write what Terraform created into the repo-root .env, for the scripts and the frontend build.
# Replaces the .env lines that deploy-cognito.sh, deploy-reports.sh and deploy-ai.sh used to
# write from CloudFormation outputs. Run it after an apply: make infra-env.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
TF=(terraform -chdir="${ROOT}/infra")

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

out() { "${TF[@]}" output -raw "$1"; }

env_set COGNITO_USER_POOL_ID "$(out user_pool_id)"
env_set COGNITO_CLIENT_ID "$(out client_id)"
env_set COGNITO_DOMAIN "$(out cognito_domain)"
env_set PARSER_URL "$(out parser_url)"
env_set REPORTS_BUCKET "$(out reports_bucket_name)"
env_set REPORT_REQUESTS_QUEUE_URL "$(out report_requests_queue_url)"

echo "wrote COGNITO_*, PARSER_URL, REPORTS_BUCKET and REPORT_REQUESTS_QUEUE_URL to .env"
