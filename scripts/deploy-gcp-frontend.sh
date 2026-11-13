#!/usr/bin/env bash
# Build the Next.js static export and deploy it to Firebase Hosting.
#
# Firebase rewrites /api/** to the Cloud Run service, so the bundle calls its own origin: one
# origin, no CORS, as CloudFront did for the AWS frontend. GCP_API_DIRECT=1 builds against the
# Cloud Run URL instead (CORS_ORIGINS on the service already allows the Hosting origins).
#
# Sign-in stays on AWS Cognito: the COGNITO_* values come from .env (make infra-env), and the
# Hosting URL must be in the Cognito client's callback_urls (infra/terraform.tfvars).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/frontend"
BUILD="${ROOT}/gcp/.build"
FIREBASE_TOOLS="${FIREBASE_TOOLS:-firebase-tools@14}"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "${ROOT}/.env" ]]; then
  preset="$(export -p)"
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
  eval "${preset}"
fi

for tool in terraform node npx; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done

if command -v pnpm >/dev/null 2>&1; then
  PM=(pnpm)
elif command -v corepack >/dev/null 2>&1; then
  PM=(corepack pnpm)
else
  PM=(npx --yes pnpm@10)
fi

tf_out() { terraform -chdir="${ROOT}/gcp" output -raw "$1"; }

PROJECT_ID="$(tf_out project_id)" || die "no Terraform outputs - run make gcp-init and apply gcp/ first"
REGION="$(tf_out region)"
SERVICE="$(tf_out api_service)"
SITE_ID="$(tf_out hosting_site_id)"
SITE_URL="$(tf_out hosting_url)"

if [[ -n "${GCP_API_DIRECT:-}" ]]; then
  API_URL="$(tf_out api_url)"
else
  API_URL="${SITE_URL}"
fi

[[ -n "${COGNITO_CLIENT_ID:-}" && -n "${COGNITO_DOMAIN:-}" ]] \
  || die "COGNITO_CLIENT_ID / COGNITO_DOMAIN are not set in .env - run make infra-env first"

log "installing dependencies"
(cd "${APP}" && "${PM[@]}" install --frozen-lockfile)

log "building the static export against ${API_URL}"
rm -rf "${ROOT:?}/frontend/out"
(cd "${APP}" && NEXT_OUTPUT=export \
  NEXT_PUBLIC_API_URL="${API_URL}" \
  NEXT_PUBLIC_PARSER_URL="${PARSER_URL:-}" \
  NEXT_PUBLIC_COGNITO_REGION="${COGNITO_REGION:-us-east-1}" \
  NEXT_PUBLIC_COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID}" \
  NEXT_PUBLIC_COGNITO_DOMAIN="${COGNITO_DOMAIN}" \
  NEXT_PUBLIC_COGNITO_GOOGLE_ENABLED="${COGNITO_GOOGLE_ENABLED:-false}" \
  "${PM[@]}" build)
[[ -f "${APP}/out/index.html" ]] || die "the export produced no out/index.html"

# firebase.json is generated: the site and the service names come from Terraform.
rm -rf "${ROOT:?}/gcp/.build"
mkdir -p "${BUILD}"
cp -R "${APP}/out" "${BUILD}/public"
cat > "${BUILD}/firebase.json" <<JSON
{
  "hosting": {
    "site": "${SITE_ID}",
    "public": "public",
    "cleanUrls": true,
    "trailingSlash": false,
    "rewrites": [
      { "source": "/api/**", "run": { "serviceId": "${SERVICE}", "region": "${REGION}" } }
    ],
    "headers": [
      {
        "source": "/_next/static/**",
        "headers": [{ "key": "Cache-Control", "value": "public,max-age=31536000,immutable" }]
      },
      {
        "source": "**/*.html",
        "headers": [{ "key": "Cache-Control", "value": "public,max-age=0,must-revalidate" }]
      }
    ]
  }
}
JSON

# firebase-tools signs in with application default credentials (gcloud auth
# application-default login), or with `npx firebase-tools login` once.
log "deploying to Firebase Hosting (${SITE_ID})"
(cd "${BUILD}" && npx --yes "${FIREBASE_TOOLS}" deploy \
  --only hosting \
  --project "${PROJECT_ID}" \
  --config firebase.json \
  --non-interactive)

echo
echo "  site       ${SITE_URL}"
echo "  items      ${SITE_URL}/items"
echo "  api        ${API_URL}/api/v1  (-> Cloud Run ${SERVICE})"
echo
