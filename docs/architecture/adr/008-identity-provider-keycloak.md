# ADR-008: Keep Keycloak as the identity provider

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

G4IT authenticates users via Keycloak (realm `g4it`): the backend is an OAuth2 resource server
validating Keycloak JWTs, and the frontend uses `keycloak-angular` with login redirects. A
custom Keycloak image (`services/keycloak`) bakes in the theme, realm import, and extensions.
Moving to Azure, we can either keep Keycloak as a hosted container or migrate to a managed
Azure identity service — the nginx CSP already references `login.microsoftonline.com`,
suggesting Entra was at least considered. Which identity provider do we run?

## Decision Drivers

- Avoid application re-architecture in this iteration (plan scope).
- Preserve the `g4it` realm, roles, theme, and existing JWT/issuer contracts.
- Operability on ACA, including the known issuer (`iss`) validation constraint.
- Effort vs. benefit of adopting a fully managed IdP.

## Considered Options

### Option 1: Keep Keycloak (containerized on ACA)

Deploy the existing custom Keycloak image with production hostname config, pointed at the
Flexible Server `keycloak` database; import the realm; run a single always-on replica.

**Pros**:
- No application changes — backend resource-server config and frontend `keycloak-angular`
  stay as-is; realm, roles, and theme are preserved.
- Fully under our control; same IdP across all environments and on-prem/compose dev.
- Smallest path to go-live.

**Cons**:
- We operate Keycloak (upgrades, hardening, sizing); it must be always-on.
- Cold start breaks sessions, so no scale-to-zero; clustering (Infinispan) is extra work if
  multi-replica is ever needed.

### Option 2: Migrate to Microsoft Entra ID / External ID

Replace Keycloak with a managed Azure IdP.

**Pros**:
- Fully managed IdP; no Keycloak to operate; native Azure integration.

**Cons**:
- Larger change: re-map realm/roles/claims, rewrite frontend auth and backend issuer
  validation, migrate users, redo theming. Out of scope for this iteration per the plan.

### Option 3: Keycloak as a managed/third-party SaaS (e.g. hosted Keycloak)

**Pros**:
- Keeps Keycloak semantics without operating it ourselves.

**Cons**:
- New vendor/contract and data-residency considerations; still a migration off the in-repo
  image. Not justified now.

## Decision Outcome

**Chosen option**: Option 1 — keep Keycloak — because it requires no application changes and
preserves the `g4it` realm, roles, theming, and JWT contracts, which is the lowest-risk path
for this containerization effort. Operational rules: give Keycloak a single **stable public
FQDN** used by both browser and backend so the validated `issuer-uri` matches the token issuer
(the documented `iss` gotcha); set `KC_HOSTNAME` and `KC_PROXY=edge`/proxy headers; point its
DB at the Flexible Server `keycloak` database; **change the default `admin/password`** and
store it in Key Vault ([ADR-007](007-secrets-key-vault-managed-identity.md)); run **min
replicas = 1, no scale-to-zero** (single replica avoids Infinispan clustering). **Migration to
Entra ID / External ID remains a documented future option** — if prioritized, supersede this
ADR.

## Consequences

### Positive

- No auth code changes; realm/roles/theme preserved; consistent IdP across environments.

### Negative

- We own Keycloak operations and must keep it always-on (no scale-to-zero).

### Risks

- Issuer mismatch between browser and backend breaks login — *mitigation*: one stable public
  Keycloak FQDN for both, with `KC_HOSTNAME`/proxy config.
- Single replica is a SPOF — *mitigation*: rely on ACA restart + Flexible Server durability;
  introduce clustered multi-replica only if availability requirements demand it.

## Update (2026-06-03): Keycloak hostname/proxy env resolved

Concrete production config for the Bitnami Keycloak 26.0.7 image behind ACA ingress (TLS
terminated at the edge), wired in `infra/main.bicep`:

- `KEYCLOAK_PRODUCTION=true`
- `KEYCLOAK_PROXY=edge` (TLS terminated upstream; trust forwarded headers)
- `KEYCLOAK_HOSTNAME=https://<keycloak-fqdn>/auth` — the single stable public FQDN used by
  **both browser and backend** (satisfies the `iss` validation constraint)
- `KEYCLOAK_HTTP_RELATIVE_PATH=/auth/`, `KEYCLOAK_HTTP_PORT=8180`
- DB pointed at the Flexible Server `keycloak` database with `KEYCLOAK_JDBC_PARAMS=sslmode=require`
- Admin password from Key Vault ([ADR-007](007-secrets-key-vault-managed-identity.md)) via
  `KEYCLOAK_ADMIN_PASSWORD` — the compose default `admin/password` is not used

Verify these env names against the Bitnami 26.0.7 image contract before go-live (Bitnami exposes
both its `KEYCLOAK_*` wrappers and the underlying `KC_*` variables).

## References

- `docs/azure-deployment-plan.md` §4 (Keycloak config), §1 (`iss` gotcha), open decision #3
- `DOCKER-DEPLOYMENT.md` (issuer validation), `services/keycloak/` (image, imports, themes)
- Related: [ADR-003](003-relational-database-postgresql-flexible-server.md),
  [ADR-007](007-secrets-key-vault-managed-identity.md),
  [ADR-011](011-domains-region-environments.md)
