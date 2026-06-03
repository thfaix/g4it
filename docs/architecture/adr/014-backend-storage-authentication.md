# ADR-014: Backend↔storage authentication via per-organization connection string in Key Vault

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

[ADR-004](004-file-storage-azure-blob.md) chose Azure Blob for backend file storage and assumed
managed-identity access. Reading the code shows the actual mechanism is different and must be
recorded so the infrastructure matches it. In the `azure` profile, `AzureFileSystem` and
`VaultAccessClient` (`common/filesystem`) work like this:

1. For a given **organization**, the backend fetches a Key Vault secret **named after the
   organization** (uppercased, `_`→`-`) — e.g. the default org `DEMO` (Liquibase
   `default_organization`) → secret `DEMO`.
2. That secret's value is a **storage account connection string**.
3. The backend builds a `BlobServiceClient` from the connection string and uses the first blob
   **container whose name starts with `g4it`**.

So the backend authenticates to Key Vault (via managed identity — [ADR-007](007-secrets-key-vault-managed-identity.md)),
but authenticates to **Blob via a connection string (account key)** retrieved from the vault —
not via managed identity directly. This is per-organization by design (multi-tenant storage).
Do we keep this model or refactor to managed-identity blob access?

## Decision Drivers

- Avoid application code changes in this iteration (plan scope).
- Preserve the per-organization storage model the code is built around.
- Keep secrets out of images/config (the connection string lives only in Key Vault).
- [ADR-007](007-secrets-key-vault-managed-identity.md) already grants the identity *Storage
  Blob Data Contributor*, anticipating MI blob access — reconcile that.

## Considered Options

### Option 1: Keep the per-organization connection string in Key Vault (no code change)

Seed a Key Vault secret named after each organization, holding that organization's storage
account connection string; the backend resolves it at runtime as it does today.

**Pros**:
- Zero application change; matches `AzureFileSystem`/`VaultAccessClient` exactly.
- Supports per-organization (multi-tenant) storage accounts naturally.
- The connection string never appears in config or images — only in Key Vault, reached via
  managed identity.

**Cons**:
- Uses account keys (a shared secret) rather than identity-scoped data-plane RBAC; keys must be
  rotated, and the org→secret naming convention must be maintained.
- The *Storage Blob Data Contributor* grant from [ADR-007](007-secrets-key-vault-managed-identity.md)
  is unused for this path (still useful for any future MI access / tooling).

### Option 2: Refactor `AzureFileSystem` to use managed identity (DefaultAzureCredential)

Drop the connection string; build `BlobServiceClient` with the user-assigned identity and a
fixed account/container per environment.

**Pros**:
- No account keys; identity-scoped, rotation-free, RBAC-audited blob access — the [ADR-007](007-secrets-key-vault-managed-identity.md)
  ideal.

**Cons**:
- Application code change to `common/filesystem`, and it must preserve the per-organization
  container resolution; out of scope for a config-only deployment and higher risk.

### Option 3: Hybrid — MI for a single shared account, connection strings only where multi-tenant

**Pros**:
- Incremental path toward Option 2.

**Cons**:
- Two code paths to maintain; more complexity than this iteration warrants.

## Decision Outcome

**Chosen option**: Option 1 — keep the per-organization connection-string-in-Key-Vault model —
because it requires no application change and matches the implemented behavior. The deployment
therefore: creates a storage account with a `g4it`-prefixed container ([ADR-004](004-file-storage-azure-blob.md)),
and seeds a Key Vault secret **named after the organization** (default `DEMO`) holding that
account's connection string (the Bicep `keyvault` module does this from the storage account
keys; `organizationName` parameterizes the secret name). Managed identity is still used for the
**Key Vault** read ([ADR-007](007-secrets-key-vault-managed-identity.md)). Migrating to
managed-identity blob access (Option 2) is recorded as the preferred future direction; if taken,
this ADR is superseded.

This refines [ADR-004](004-file-storage-azure-blob.md), correcting its assumption that Blob is
accessed directly via managed identity.

## Consequences

### Positive

- No application change; deployment matches the real code path; multi-tenant storage supported.
- Secret material stays in Key Vault, reached via managed identity.

### Negative

- Relies on storage account keys (a rotatable shared secret) rather than data-plane RBAC.
- The org→secret naming convention (`DEMO`, etc.) must be kept correct per environment.

### Risks

- Secret name not matching the organization in seed data → backend cannot mount storage —
  *mitigation*: `organizationName` defaults to `DEMO` (verified against Liquibase
  `default_organization`); confirm per environment and for any additional organizations.
- Account-key leakage/rotation — *mitigation*: rotate keys and update the Key Vault secret;
  consider Option 2 if key usage becomes a concern.

## References

- `services/backend/.../common/filesystem/business/AzureFileSystem.java`,
  `.../external/VaultAccessClient.java`
- `services/backend/.../db/changelog/greenitdb.changelog-security-multi-orga.yml`
  (`default_organization = 'DEMO'`)
- Plan open decision #5; `infra/modules/keyvault.bicep`, `infra/modules/storage.bicep`
- Related: [ADR-004](004-file-storage-azure-blob.md),
  [ADR-007](007-secrets-key-vault-managed-identity.md)
