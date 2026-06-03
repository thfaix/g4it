#!/usr/bin/env bash
#
# import-external-images.sh — mirror G4IT's external container images into ACR.
#
# ACA pulls every image from ACR with the managed identity (ADR-005, ADR-007), so the
# external images must be imported first. This script runs `az acr import` for:
#   - the 4 NumEcoEval services from the French-gov GitLab registry (ADR-012), and
#   - Boavizta + Ecomind from their public registries (ADR-005).
#
# Destination repository names and tags MUST match what infra/main.bicep pulls
# (numEcoEvalRepositoryPrefix/numEcoEvalTag, boavizta*, ecomind*). Re-importing a tag is a
# deliberate, reviewable step — for NumEcoEval, bump the image tag and the backend's
# `org.mte.numecoeval:calculs` Maven version together (ADR-012).
#
# Usage:
#   ./import-external-images.sh <acr-name> [--include-ecomind] [--no-force]
#
# Env overrides (defaults track workspace/docker/.env and infra/main.bicep):
#   NUMECOEVAL_REGISTRY   source registry/path for the 4 NumEcoEval images
#   NUMECOEVAL_TAG        NumEcoEval source+dest tag (default 2-2-0)
#   NUMECOEVAL_PREFIX     ACR destination repo prefix (default numecoeval)
#   BOAVIZTA_SOURCE       full source ref for Boavizta
#   ECOMIND_SOURCE        full source ref for Ecomind
#   NUMECOEVAL_REGISTRY_USERNAME / NUMECOEVAL_REGISTRY_PASSWORD
#                         credentials for the source registry, if it requires auth
#
# Requires: az CLI, logged in (az login) with AcrPush on the target ACR.

set -euo pipefail

ACR_NAME="${1:-${ACR_NAME:-}}"
if [ -z "${ACR_NAME}" ]; then
  echo "error: ACR name required (arg 1 or \$ACR_NAME)" >&2
  echo "usage: $0 <acr-name> [--include-ecomind] [--no-force]" >&2
  exit 1
fi
shift || true

INCLUDE_ECOMIND=false
FORCE_FLAG="--force"   # idempotent re-import by default; pass --no-force to skip overwrite
for arg in "$@"; do
  case "$arg" in
    --include-ecomind) INCLUDE_ECOMIND=true ;;
    --no-force)        FORCE_FLAG="" ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# --- Source coordinates (workspace/docker/.env, shared-docker-compose.yml) ------------------
NUMECOEVAL_REGISTRY="${NUMECOEVAL_REGISTRY:-registry.gitlab-forge.din.developpement-durable.gouv.fr/pub/numeco/m4g/numecoeval}"
NUMECOEVAL_TAG="${NUMECOEVAL_TAG:-2-2-0}"
NUMECOEVAL_PREFIX="${NUMECOEVAL_PREFIX:-numecoeval}"
BOAVIZTA_SOURCE="${BOAVIZTA_SOURCE:-ghcr.io/boavizta/boaviztapi:1.3.10}"
ECOMIND_SOURCE="${ECOMIND_SOURCE:-docker.io/sustain4raise/ecomindai:1.1.0}"

# Optional source-registry credentials (e.g. if the gov GitLab registry requires auth).
CRED_ARGS=()
if [ -n "${NUMECOEVAL_REGISTRY_USERNAME:-}" ]; then
  CRED_ARGS=(--username "${NUMECOEVAL_REGISTRY_USERNAME}" --password "${NUMECOEVAL_REGISTRY_PASSWORD:-}")
fi

import_image() {
  local source="$1" dest="$2"
  shift 2
  echo "==> importing ${source}  ->  ${ACR_NAME}.azurecr.io/${dest}"
  # shellcheck disable=SC2086
  az acr import --name "${ACR_NAME}" --source "${source}" --image "${dest}" ${FORCE_FLAG} "$@"
}

NUMECOEVAL_SERVICES="api-referentiel api-expositiondonneesentrees api-event-donneesentrees api-event-calculs"
for svc in ${NUMECOEVAL_SERVICES}; do
  import_image "${NUMECOEVAL_REGISTRY}/${svc}:${NUMECOEVAL_TAG}" \
               "${NUMECOEVAL_PREFIX}/${svc}:${NUMECOEVAL_TAG}" "${CRED_ARGS[@]}"
done

# Boavizta — public ghcr.io; dest repo matches infra boaviztaImageRepository/Tag.
import_image "${BOAVIZTA_SOURCE}" "boavizta/boaviztapi:1.3.10"

# Ecomind — opt-in (infra deployEcomind defaults false). NOTE: the source repo
# (sustain4raise/ecomindai) differs from the ACR dest repo expected by infra (ecomind/ecomindai).
if [ "${INCLUDE_ECOMIND}" = true ]; then
  import_image "${ECOMIND_SOURCE}" "ecomind/ecomindai:1.1.0"
fi

echo "done: external images imported into ${ACR_NAME}.azurecr.io"
