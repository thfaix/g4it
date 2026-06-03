# ADR-003: Relational database on Azure Database for PostgreSQL Flexible Server

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The stack uses a single `postgres:15` container that hosts both the G4IT/NumEcoEval data and
a separate `keycloak` database. The backend manages its schema with Liquibase
(`db/changelog`, master `greenitdb.changelog-master.yml`) and its JDBC URL already sets
`reWriteBatchedInserts=true`. Running a stateful database container under a serverless
container platform ([ADR-001](001-container-hosting-azure-container-apps.md)) is fragile —
ACA has no first-class persistent volume story and gives us no backups, HA, or patching.
What should host the relational data?

## Decision Drivers

- Durability: backups, point-in-time restore, and HA — not offered by a DB container on ACA.
- PostgreSQL 15 compatibility (existing Liquibase changelogs and JDBC features).
- Managed operations (patching, monitoring) consistent with the "managed services" mandate.
- Ability to keep the two logical databases (`postgres` for g4it + numecoeval, `keycloak`).
- Private connectivity from the ACA environment ([ADR-009](009-networking-vnet-private-endpoints.md)).

## Considered Options

### Option 1: Azure Database for PostgreSQL — Flexible Server

Managed PostgreSQL PaaS; create the `postgres` and `keycloak` databases on one server.

**Pros**:
- Drop-in PostgreSQL — no schema or driver changes; Liquibase changelogs apply unchanged.
- Built-in automated backups, PITR, optional zone-redundant HA, and patching.
- Private access (VNet integration / private endpoint), metrics, and tunable parameters.

**Cons**:
- More expensive than a self-run container; HA roughly doubles compute cost.
- A managed PaaS server still needs SKU right-sizing per environment.

### Option 2: Containerized PostgreSQL on ACA with persistent storage

Keep `postgres:15` as a container app backed by attached storage.

**Pros**:
- Closest to the current compose setup; lowest direct infra cost.

**Cons**:
- No managed backups/HA/patching; we own durability and DR.
- Stateful workloads are a poor fit for ACA's revision/scaling model; risk of data loss on
  restarts/migrations.

### Option 3: Azure Cosmos DB / other datastore

Replace PostgreSQL with a different managed datastore.

**Pros**:
- Globally distributed, serverless options.

**Cons**:
- Not PostgreSQL — would require rewriting persistence, Liquibase, and Keycloak storage.
  Out of scope; the plan explicitly avoids application re-architecture.

## Decision Outcome

**Chosen option**: Option 1 — PostgreSQL Flexible Server — because it preserves the existing
PostgreSQL 15 schema, Liquibase migrations, and JDBC behavior verbatim while delegating
backups, HA, and patching to Azure. We create both `postgres` and `keycloak` databases on the
server; Liquibase applies the `greenitdb` changelog on backend startup, and Keycloak points at
its own database.

## Consequences

### Positive

- Zero persistence code changes; durable, backed-up, optionally HA data.
- Managed patching/monitoring; private connectivity from ACA.

### Negative

- Higher recurring cost than a self-hosted container, especially with HA enabled.

### Risks

- Under-sized SKU could bottleneck evaluation runs — *mitigation*: right-size per environment
  and alert on DB connections/CPU ([ADR-006](006-observability-log-analytics-app-insights.md)).
- Two apps share one server — *mitigation*: separate databases and credentials; consider
  separate servers in prod if isolation requirements grow.

## References

- `docs/azure-deployment-plan.md` §3 (managed-service mapping), §7 (sequence)
- `services/backend/src/main/resources/db/changelog/` (Liquibase), JDBC `reWriteBatchedInserts`
- Related: [ADR-008](008-identity-provider-keycloak.md),
  [ADR-009](009-networking-vnet-private-endpoints.md)
