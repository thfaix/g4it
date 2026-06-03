#!/usr/bin/env bash
#
# deploy.sh — idempotent deployment of the G4IT stack (subscription-scoped entrypoint).
#
# WHY THIS EXISTS: Keycloak bootstraps its admin user only ONCE, on the first start against an
# empty database, using KEYCLOAK_ADMIN_PASSWORD. It never updates that user's password on later
# starts. So if each deploy passes a freshly generated keycloakAdminPassword, the ACA secret
# drifts away from the password actually stored in Keycloak and admin login breaks.
#
# This wrapper makes deploys idempotent: it REUSES the password already stored in the deployed
# ACA secrets when the apps exist, and only falls back to the env vars on the very first deploy.
# Postgres can safely rotate (the server password and the secret update together), but we reuse
# it too for consistency. No secret is ever written to the repo.
#
# Usage (first deploy — set the env vars once):
#   export G4IT_KEYCLOAK_ADMIN_PASSWORD='<stable strong password>'
#   export G4IT_PG_ADMIN_PASSWORD='<stable strong password>'
#   ./deploy.sh <resource-group> <location>
#
# Usage (subsequent deploys — env vars optional, existing secrets are reused):
#   ./deploy.sh <resource-group> <location>
#
# Requires: az CLI (logged in).

set -euo pipefail

RG="${1:?resource group required (e.g. rg-g4it-dev)}"
LOCATION="${2:?location required (e.g. northeurope)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../main.subscription.bicep"
DEPLOYMENT_NAME="g4it-${LOCATION}"   # stable per location (sub-scope deployment names are location-pinned)

# Reuse an existing ACA secret value if the app is already deployed; otherwise take it from the
# named env var. Fails if neither is available (so a first deploy must supply the env var).
reuse_or_env() {  # $1=container-app  $2=secret-name  $3=env-var-name
  local existing
  existing=$(az containerapp secret show -g "$RG" -n "$1" --secret-name "$2" --query value -o tsv 2>/dev/null | tr -d '\r' || true)
  if [ -n "$existing" ]; then
    echo "reusing existing '$2' from app '$1'" >&2
    printf '%s' "$existing"; return 0
  fi
  local from_env="${!3:-}"
  if [ -n "$from_env" ]; then
    echo "using \$$3 for '$2' (no existing secret found — first deploy)" >&2
    printf '%s' "$from_env"; return 0
  fi
  echo "ERROR: app '$1' has no '$2' secret and \$$3 is unset. Set \$$3 for the first deploy." >&2
  return 1
}

KCPASS=$(reuse_or_env keycloak       keycloak-admin-password G4IT_KEYCLOAK_ADMIN_PASSWORD)
PGPASS=$(reuse_or_env g4it-backend   db-password             G4IT_PG_ADMIN_PASSWORD)

echo "Deploying '${DEPLOYMENT_NAME}' to ${RG} (${LOCATION})..."
az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${LOCATION}" \
  --template-file "${TEMPLATE}" \
  --parameters location="${LOCATION}" \
               postgresAdminPassword="${PGPASS}" \
               keycloakAdminPassword="${KCPASS}"
