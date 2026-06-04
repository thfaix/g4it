# ADR-001: Container hosting on Azure Container Apps

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The G4IT stack runs today as ~10 containers wired together by docker-compose
(`workspace/docker/docker-compose-all.yml` + `shared-docker-compose.yml`): the three
in-repo images (frontend, backend, Keycloak), a PostgreSQL database, the four NumEcoEval
services, and the optional Boavizta and Ecomind APIs. We want to deploy this stack into a
new Azure resource group using **managed services** and **container-based hosting**, without
re-architecting the application.

Three of the containers (frontend, backend, Keycloak) must be reachable from the browser;
the rest are internal and reached only by the backend. We need a host that provides
service-to-service discovery (replacing the compose `numecoeval` network), per-app ingress
control (external vs internal), and managed identity for pulling images and reading secrets.
Which Azure compute platform should host the containers?

## Decision Drivers

- "Managed services" mandate — minimize platform operations (no node/OS patching, no control
  plane to run).
- Need internal service discovery and per-app external/internal ingress out of the box.
- Multi-replica backend (ShedLock keeps cron jobs singular — see `schedulerlocked`) needs
  simple horizontal scaling.
- Managed identity integration for ACR pull, Key Vault, and Blob (no stored credentials).
- Cost control: ability to scale bursty internal services down (ideally to zero).
- Team has no existing Kubernetes operational footprint.

## Considered Options

### Option 1: Azure Container Apps (ACA)

Serverless container platform built on AKS/KEDA/Envoy/Dapr, exposing a higher-level app
abstraction. One ACA Environment hosts all apps with built-in name-based service discovery.

**Pros**:
- Built-in internal service discovery and per-app ingress (external for the 3 web apps,
  internal-only for the rest) — direct mapping of the compose topology.
- Managed identity → ACR/Key Vault/Blob with no secrets; managed TLS on custom domains.
- KEDA autoscaling per app, scale-to-zero for idle internal services, revisions for safe
  rollout; native Log Analytics integration.
- No cluster, node pools, or control plane to operate.

**Cons**:
- Less control than Kubernetes (no custom CNI, no arbitrary operators/CRDs, limited sidecar
  model beyond Dapr).
- Some features (e.g. fine-grained network policy, GPU pools) are unavailable or limited.

### Option 2: Azure Kubernetes Service (AKS)

Full managed Kubernetes cluster.

**Pros**:
- Maximum control and flexibility (CNI, service mesh, operators, GPU pools).
- Portable, vendor-neutral manifests.

**Cons**:
- Significant operational burden: node pools, upgrades, ingress controller, secrets/identity
  wiring, autoscaler tuning — contradicts the "managed services" goal.
- Overkill for ~10 stateless-ish containers; the team runs no k8s today.

### Option 3: App Service for Containers

PaaS web hosting for containers.

**Pros**:
- Simple and managed for the 3 public web apps; mature custom-domain/TLS story.

**Cons**:
- No first-class internal service-to-service mesh — the NumEcoEval/Boavizta/Ecomind set would
  need a second hosting solution, splitting the stack across two platforms.
- Weaker fit for an internal multi-service topology.

## Decision Outcome

**Chosen option**: Option 1 — Azure Container Apps — because it is the managed/serverless
container platform whose primitives (one environment, name-based discovery, external vs
internal ingress, managed identity, KEDA scaling) map almost one-to-one onto the existing
docker-compose topology, with no Kubernetes to operate. AKS is held in reserve for if/when
the team needs features ACA lacks; the managed-service mapping in the rest of this ADR set
is largely identical under AKS (only the compute host changes).

## Consequences

### Positive

- The compose stack ports with configuration changes only — no application re-architecture.
- Minimal operations: no cluster, nodes, or ingress controller to maintain.
- Per-app scaling and scale-to-zero for idle internal services control cost.

### Negative

- Vendor lock-in to ACA's app model; migrating off Azure later means re-templating compute.
- Ceiling on low-level control (networking, sidecars) compared with AKS.

### Risks

- A future requirement ACA cannot meet (custom CNI, service mesh, GPU) would force a move to
  AKS — *mitigation*: the managed-data-plane decisions (DB, Blob, Key Vault, registry) are
  host-agnostic, so only compute would migrate.
- Keycloak is sensitive to scale-to-zero (cold start breaks sessions) — *mitigation*:
  pin min replicas = 1 for Keycloak (see [ADR-008](008-identity-provider-keycloak.md)).

## References

- `docs/azure-deployment-plan.md` §2 (hosting recommendation), §3 (architecture)
- `workspace/docker/docker-compose-all.yml`, `workspace/docker/shared-docker-compose.yml`
- Related: [ADR-002](002-iac-bicep.md), [ADR-007](007-secrets-key-vault-managed-identity.md),
  [ADR-009](009-networking-vnet-private-endpoints.md)
