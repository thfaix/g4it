# ADR-002: Infrastructure-as-Code with Bicep

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The Azure deployment provisions a coherent set of resources in a new resource group: ACR,
Log Analytics, the ACA environment and ~10 container apps, PostgreSQL Flexible Server, Key
Vault, a storage account, a user-assigned managed identity with role assignments, plus
networking (VNet, private endpoints). This must be reproducible across environments
(dev/test/prod) and reviewable in source control rather than clicked together in the portal.
Which Infrastructure-as-Code tool should we standardize on?

## Decision Drivers

- Reproducibility and parameterization per environment (region, names, sizes, replica counts,
  FQDNs).
- First-class, day-one support for new Azure resource types (ACA, Flexible Server features).
- Low tooling overhead — no extra state backend or runtime to operate if avoidable.
- Reviewable in PRs; integrates with the GitHub Actions deployment pipeline
  ([ADR-010](010-cicd-github-actions-oidc.md)).

## Considered Options

### Option 1: Bicep

Azure-native declarative DSL that transpiles to ARM; one `main.bicep` plus a module per
resource, deployed with `az deployment group create`.

**Pros**:
- Azure-native: no extra tooling, no separate state store (state lives in Azure as
  deployments); day-one coverage of new resource types and API versions.
- Clean module system; tight integration with `az` CLI and GitHub Actions.
- Free; supported directly by Microsoft.

**Cons**:
- Azure-only — not reusable if the org later adopts other clouds.
- Smaller ecosystem of reusable modules than Terraform.

### Option 2: Terraform

Cloud-agnostic IaC with the `azurerm`/`azapi` providers and an external state backend.

**Pros**:
- Multi-cloud, large module ecosystem, strong plan/apply workflow and drift detection.
- Org-standard at many shops; transferable skill.

**Cons**:
- Requires managing remote state (storage account + locking) and provider versioning.
- Occasional lag behind brand-new Azure features (mitigated by `azapi`, which adds
  complexity).

### Option 3: Portal / scripted `az` CLI only

Provision by hand or with imperative shell scripts.

**Pros**:
- Fastest to get a first environment running.

**Cons**:
- Not declarative or idempotent; drift-prone; poor reviewability and reproducibility across
  environments. Not viable for prod.

## Decision Outcome

**Chosen option**: Option 1 — Bicep — because it is Azure-native, needs no extra state
backend or tooling, and tracks new Azure resource types (ACA, Flexible Server) on day one,
which matters for a fresh ACA-based deployment. The trade-off (Azure-only) is acceptable
given the deployment is explicitly Azure-targeted. **Terraform remains a viable alternative
if the organization standardizes on it**; if so, this ADR should be superseded.

## Consequences

### Positive

- One declarative source of truth, parameterized per environment, reviewed in PRs.
- No state backend to provision or secure.

### Negative

- IaC is Azure-coupled; a multi-cloud future would require rewrite or wrapping.

### Risks

- Org may already mandate Terraform — *mitigation*: keep modules small and resource-scoped so
  a port to Terraform is mechanical; revisit before the first prod deployment.

## References

- `docs/azure-deployment-plan.md` §6 (IaC & CI/CD), open decision #6
- Related: [ADR-001](001-container-hosting-azure-container-apps.md),
  [ADR-010](010-cicd-github-actions-oidc.md)
