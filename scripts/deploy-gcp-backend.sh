#!/usr/bin/env bash
# Build the backend image (the same "runtime" target Docker Compose runs, no Lambda adapter),
# push it to Artifact Registry and roll the Cloud Run service onto it.
#
# The service itself - its service account, Cloud SQL connection, secret, scaling - is
# Terraform's (gcp/api.tf). This script only changes which image runs. Migrations run in the
# container's entrypoint on start.
#
# Needs: gcloud (signed in with your own account), docker, and terraform init in gcp/.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

for tool in gcloud docker terraform curl; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done
docker info >/dev/null 2>&1 || die "docker daemon is not running"

tf_out() { terraform -chdir="${ROOT}/gcp" output -raw "$1"; }

PROJECT_ID="$(tf_out project_id)" || die "no Terraform outputs - run make gcp-init and apply gcp/ first"
REGION="$(tf_out region)"
SERVICE="$(tf_out api_service)"
REPOSITORY="$(tf_out image_repository)"

if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
  git -C "${ROOT}" diff --quiet HEAD -- backend \
    || IMAGE_TAG="${IMAGE_TAG}-dirty-$(date -u +%Y%m%d%H%M%S)"
fi
IMAGE_URI="${REPOSITORY}/api:${IMAGE_TAG}"

log "registry login (${REGION}-docker.pkg.dev)"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet >/dev/null 2>&1

# Cloud Run runs linux/amd64. No attestations: a plain single-platform manifest.
log "building ${IMAGE_URI}"
docker buildx build \
  --platform linux/amd64 \
  --target runtime \
  --provenance=false \
  --sbom=false \
  --tag "${IMAGE_URI}" \
  --push \
  "${ROOT}/backend"

log "rolling ${SERVICE} onto the new image"
gcloud run services update "${SERVICE}" \
  --project "${PROJECT_ID}" \
  --region "${REGION}" \
  --image "${IMAGE_URI}" \
  --quiet

API_URL="$(tf_out api_url)"
log "checking ${API_URL}/health"
curl -fsS "${API_URL}/health" && echo

echo
echo "  api        ${API_URL}"
echo "  image      ${IMAGE_URI}"
echo "  logs       make gcp-logs"
echo
