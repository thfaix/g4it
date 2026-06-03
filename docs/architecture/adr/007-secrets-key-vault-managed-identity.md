# ADR-007: Secrets in Key Vault, accessed via user-assigned Managed Identity

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The deployment handles several secrets — the database password, the Keycloak admin password
(the compose stack ships `admin/password`, which must be changed), and any OAuth client
secrets — and the apps need to authenticate to ACR (pull), Key Vault (read), and Blob
(read/write). The backend already ships Key Vault wiring (`application-azure.yml`,
`spring-cloud-azure-starter-keyvault`). We need to decide where secrets live and how workloads
authenticate to Azure resources without embedding credentials in config or images.

## Decision Drivers

- No secrets baked into images, env files, or source control.
- Backend already reads Key Vault via the `azure` profile.
- ACA can reference Key Vault secrets and authenticate to ACR/Key Vault/Blob via managed
  identity.
- Centralized rotation and access auditing.

## Considered Options

### Option 1: Azure Key Vault + user-assigned Managed Identity

Store all secrets in Key Vault. Assign a user-assigned managed identity to the apps with role
assignments **AcrPull**, **Key Vault Secrets User**, and **Storage Blob Data Contributor**;
the backend reads Key Vault directly, and ACA references KV-backed secrets.

**Pros**:
- Zero stored credentials: identity is platform-issued; pulls, secret reads, and Blob access
  are credential-less.
- Reuses the backend's existing Key Vault integration; centralized rotation and audit.
- A user-assigned identity is reusable across apps and stable across app re-creation, with
  least-privilege role scoping.

**Cons**:
- Extra setup: identity creation and role assignments must be templated in IaC.
- Local development still needs a non-managed-identity path (env vars / `nosecurity`).

### Option 2: Key Vault + service principal with client secret

Apps authenticate to Key Vault/ACR with an app registration + client secret
(`AZURE_CLIENT_ID/SECRET`, already templated in `application-azure.yml`).

**Pros**:
- Works anywhere, including outside Azure; simple mental model.

**Cons**:
- Reintroduces a long-lived secret to store and rotate — the thing we are trying to avoid;
  weaker than platform-managed identity.

### Option 3: Secrets only in ACA secrets / env vars (no Key Vault)

Store secrets directly as ACA app secrets.

**Pros**:
- Simplest; no Key Vault resource.

**Cons**:
- No central rotation/audit; bypasses the backend's existing Key Vault integration; secrets
  spread across app definitions. Rejected.

## Decision Outcome

**Chosen option**: Option 1 — Key Vault + user-assigned Managed Identity — because it removes
stored credentials entirely (the explicit goal of the `azure` profile), reuses the backend's
existing Key Vault integration, and gives least-privilege, auditable, rotatable access to ACR,
Key Vault, and Blob. We prefer managed identity over `AZURE_CLIENT_ID/SECRET`; the
service-principal path remains the documented fallback for environments where managed identity
is unavailable (e.g. local dev).

## Consequences

### Positive

- No secrets in images, config, or source; central rotation and access auditing.
- One identity grants ACR pull + Key Vault + Blob across apps with least privilege.

### Negative

- Identity and role-assignment plumbing must be modeled in IaC and kept in sync as apps
  change.

### Risks

- Over-broad role assignment grants excess access — *mitigation*: scope roles to the specific
  Key Vault, storage account, and registry; review in PR.
- The default `admin/password` could ship to an environment — *mitigation*: set the Keycloak
  admin password from Key Vault at deploy time (see [ADR-008](008-identity-provider-keycloak.md)).

## References

- `docs/azure-deployment-plan.md` §3, §4 (config), §7 (sequence, role assignments)
- `services/backend/src/main/resources/application-azure.yml`; pom
  `spring-cloud-azure-starter-keyvault`
- Related: [ADR-004](004-file-storage-azure-blob.md),
  [ADR-005](005-container-registry-and-external-images.md),
  [ADR-008](008-identity-provider-keycloak.md)
