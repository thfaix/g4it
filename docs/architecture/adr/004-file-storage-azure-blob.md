# ADR-004: Backend file storage on Azure Blob Storage

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The backend persists uploaded input files, generated outputs, and exports through a storage
abstraction in `common/filesystem`, which currently writes to the `/app/storage` Docker
volume. On a serverless container platform ([ADR-001](001-container-hosting-azure-container-apps.md))
local/volume storage is ephemeral and not shared across replicas, so the file store must move
to a managed, multi-replica-safe backend. The backend already ships an `azure` Spring profile
(`application-azure.yml`) and the pom includes `spring-cloud-azure-starter-storage-blob`,
indicating Blob was anticipated. Where should backend files live?

## Decision Drivers

- Durable, shared storage accessible from all backend replicas (loading/evaluation/export
  read and write the same files).
- Already-present support: `azure` profile + `spring-cloud-azure-starter-storage-blob`.
- Credential-less access via managed identity ([ADR-007](007-secrets-key-vault-managed-identity.md)).
- Retention/cleanup scheduler jobs must work against the chosen backend.

## Considered Options

### Option 1: Azure Blob Storage (via the backend `azure` profile)

Use the existing `common/filesystem` Blob implementation against a storage account/container.

**Pros**:
- Already wired in the codebase (`azure` profile, Blob starter dependency); object storage is
  the natural fit for input files, outputs, and exports.
- Durable, cheap, scales independently of compute; private access via private endpoint.
- Managed-identity auth — no connection strings in config.

**Cons**:
- Object semantics differ from a POSIX filesystem; any code that assumes local-FS behavior
  must be validated.
- Per-operation latency higher than a local disk for many small files.

### Option 2: Azure Files (SMB/NFS share mounted into ACA)

Mount a managed file share as a volume.

**Pros**:
- POSIX-like; closest to the current `/app/storage` volume, smallest code-path change.

**Cons**:
- The `azure`/Blob path already exists, so Files would mean *adding* an integration rather
  than using one; share performance/limits can bottleneck; weaker fit for export/retention at
  scale.

### Option 3: Keep local/managed-disk volume per replica

**Pros**:
- No change.

**Cons**:
- Not shared across replicas and not durable on ACA — breaks multi-replica backend and risks
  data loss. Rejected.

## Decision Outcome

**Chosen option**: Option 1 — Azure Blob Storage — because the backend already targets it via
the `azure` profile and the Blob starter, it is durable and shared across replicas, and it
authenticates with managed identity. **Open validation item**: confirm the `common/filesystem`
Blob implementation is complete for *all* read/write/retention/export paths used by loading,
evaluation, and export before go-live; close any gaps found.

**Correction**: the backend does not access Blob directly via managed identity as implied
above — it resolves a per-organization storage **connection string from Key Vault** and uses a
`g4it`-prefixed container. That mechanism is decided in
[ADR-014](014-backend-storage-authentication.md), which refines this ADR.

## Consequences

### Positive

- Durable, shared, independently scalable storage with no credentials in config.
- Reuses existing code paths and dependencies.

### Negative

- Object-store semantics require verifying any local-FS assumptions in `common/filesystem`.

### Risks

- A code path may assume local-FS behavior not covered by the Blob implementation —
  *mitigation*: audit `common/filesystem` Blob coverage across loading/evaluation/export and
  the retention scheduler before go-live (tracked as open decision #5 in the plan).

## References

- `docs/azure-deployment-plan.md` §3, §4 (backend config), open decision #5
- `services/backend/src/main/resources/application-azure.yml`,
  `services/backend/.../common/filesystem`
- Related: [ADR-007](007-secrets-key-vault-managed-identity.md),
  [ADR-009](009-networking-vnet-private-endpoints.md),
  [ADR-014](014-backend-storage-authentication.md)
