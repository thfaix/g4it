# ADR-009: VNet-injected ACA environment with private endpoints for the data plane

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

Only three apps need to face the internet (frontend, backend, Keycloak — the browser calls the
backend and Keycloak directly). Everything else — the four NumEcoEval services, Boavizta,
Ecomind — is reached only by the backend, and the data services (PostgreSQL, Key Vault, Blob)
hold sensitive data. We must decide the network topology: how apps talk to each other and
whether the data plane is exposed to the public internet.

## Decision Drivers

- Keep internal services and the data plane off the public internet.
- Preserve simple name-based service discovery between apps (replacing the compose
  `numecoeval` network) — see [ADR-001](001-container-hosting-azure-container-apps.md).
- Private, in-VNet connectivity to PostgreSQL, Key Vault, and Blob.
- Reasonable cost and operational simplicity.

## Considered Options

### Option 1: VNet-injected ACA environment + private endpoints (Postgres/KV/Blob)

Inject the ACA environment into a VNet. Use external ingress only for the 3 public apps and
internal ingress for the rest; reach PostgreSQL, Key Vault, and Blob over **private
endpoints** so their traffic stays in the VNet.

**Pros**:
- Internal apps and the data plane are not publicly reachable; defense in depth.
- Internal ingress still gives name-based discovery within the environment.
- Aligns with managed-identity access ([ADR-007](007-secrets-key-vault-managed-identity.md)).

**Cons**:
- More networking to model in IaC (subnets, private DNS zones, private endpoints).
- Private endpoints add small per-endpoint cost and DNS complexity.

### Option 2: Public ACA environment, service firewalls for data services

No VNet injection; restrict PostgreSQL/Key Vault/Blob with service firewall rules / "trusted
Azure services".

**Pros**:
- Simpler to stand up; fewer networking resources.

**Cons**:
- Data services remain on public endpoints (IP-allowlist only); weaker isolation; harder to
  reason about egress. Not appropriate for prod data.

### Option 3: Full hub-spoke with Azure Firewall / WAF

Front public apps with Application Gateway/WAF in a hub-spoke topology.

**Pros**:
- Centralized egress control, WAF, richer perimeter security.

**Cons**:
- Significant added cost and operations; more than this iteration needs. Can be layered on
  later. Deferred.

## Decision Outcome

**Chosen option**: Option 1 — VNet-injected ACA environment with private endpoints for
PostgreSQL, Key Vault, and Blob — because it keeps the data plane and internal services off
the public internet while preserving in-environment name-based discovery, at modest added IaC
complexity. Only the frontend, backend, and Keycloak get external ingress; NumEcoEval,
Boavizta, and Ecomind use internal ingress. A WAF/hub-spoke perimeter (Option 3) can be added
later if required.

## Consequences

### Positive

- Data plane and internal services are private; smaller attack surface.
- Clear public/internal split mirrors the compose topology.

### Negative

- More networking objects to template and maintain (subnets, private DNS, endpoints).

### Risks

- Private DNS misconfiguration can break connectivity to data services — *mitigation*: model
  private DNS zones in IaC ([ADR-002](002-iac-bicep.md)) and validate health after deploy.
- VNet subnet sizing/delegation constraints for ACA — *mitigation*: size subnets per ACA
  requirements up front.

## References

- `docs/azure-deployment-plan.md` §3 (networking row), §7 (private endpoints)
- Related: [ADR-001](001-container-hosting-azure-container-apps.md),
  [ADR-003](003-relational-database-postgresql-flexible-server.md),
  [ADR-007](007-secrets-key-vault-managed-identity.md)
