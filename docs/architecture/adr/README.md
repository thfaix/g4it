# Architecture Decision Records (ADRs)

This directory contains the Architecture Decision Records for the project. ADRs document significant architectural decisions, their context, the options considered, and the rationale for the chosen approach.

## Format

Each ADR follows a consistent structure:

- **Status**: `Proposed` (under discussion) | `Accepted` (approved and active) | `Superseded` (replaced by a newer ADR) | `Deprecated` (no longer relevant)
- **Context and Problem Statement**: Why the decision is needed
- **Decision Drivers**: Key factors influencing the choice
- **Considered Options**: Alternatives evaluated
- **Decision Outcome**: The chosen option and rationale
- **Consequences**: Positive, negative, and risks

## Naming Convention

ADR files are numbered sequentially: `NNN-short-title.md` (e.g., `001-modular-monolith.md`).

## ADR Template

Use the following template when creating a new ADR:

```markdown
# ADR-NNN: [Title]

**Status**: Proposed
**Date**: YYYY-MM-DD
**Decision Makers**: [list of people involved]

## Context and Problem Statement

[Describe the context and the problem or question that needs a decision. Why is this decision needed now?]

## Decision Drivers

- [Driver 1: e.g., performance requirements]
- [Driver 2: e.g., team expertise]
- [Driver 3: e.g., budget constraints]
- [Driver 4: e.g., time-to-market]

## Considered Options

### Option 1: [Name]

[Brief description]

**Pros**:
- [Advantage 1]
- [Advantage 2]

**Cons**:
- [Disadvantage 1]
- [Disadvantage 2]

### Option 2: [Name]

[Brief description]

**Pros**:
- [Advantage 1]
- [Advantage 2]

**Cons**:
- [Disadvantage 1]
- [Disadvantage 2]

### Option 3: [Name]

[Brief description — include at least 2-3 options to show due diligence]

## Decision Outcome

**Chosen option**: [Option N] — [one-sentence rationale].

[Longer explanation if needed. Explain why this option was chosen over the others. Reference decision drivers.]

## Consequences

### Positive

- [Benefit 1]
- [Benefit 2]

### Negative

- [Trade-off 1]
- [Trade-off 2]

### Risks

- [Risk 1 — and mitigation if known]
- [Risk 2 — and mitigation if known]

## References

- [Link to relevant documentation, RFCs, or prior art]
```

## Index

ADRs below capture the architectural decisions in the Azure containerized deployment plan
(`../../azure-deployment-plan.md`). All are `Proposed` pending sign-off.

### Foundation

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [001](001-container-hosting-azure-container-apps.md) | Container hosting on Azure Container Apps | Proposed | 2026-06-03 | Host the ~10 containers on ACA (vs AKS / App Service) for managed serverless containers with built-in discovery and ingress |
| [002](002-iac-bicep.md) | Infrastructure-as-Code with Bicep | Proposed | 2026-06-03 | Provision with Azure-native Bicep (vs Terraform), no extra state backend |

### Technology Stack

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [005](005-container-registry-and-external-images.md) | Container registry (ACR) and external image sourcing | Proposed | 2026-06-03 | ACR as the single registry; import the 6 external images so deploys are self-contained |
| [006](006-observability-log-analytics-app-insights.md) | Observability with Log Analytics and Application Insights | Proposed | 2026-06-03 | Azure Monitor as the native ACA log sink plus backend tracing/health |

### Data and Integration

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [003](003-relational-database-postgresql-flexible-server.md) | Relational database on PostgreSQL Flexible Server | Proposed | 2026-06-03 | Managed PostgreSQL 15 (vs DB container) for backups/HA; keeps `postgres` + `keycloak` DBs |
| [004](004-file-storage-azure-blob.md) | Backend file storage on Azure Blob Storage | Proposed | 2026-06-03 | Use the existing `azure` profile + Blob starter for durable, replica-shared file storage |

### Security and Access

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [007](007-secrets-key-vault-managed-identity.md) | Secrets in Key Vault via user-assigned Managed Identity | Proposed | 2026-06-03 | Store secrets in Key Vault; credential-less ACR/KV/Blob access via managed identity |
| [008](008-identity-provider-keycloak.md) | Keep Keycloak as the identity provider | Proposed | 2026-06-03 | Retain containerized Keycloak (vs Entra ID) to avoid auth re-architecture; single always-on replica |
| [009](009-networking-vnet-private-endpoints.md) | VNet-injected ACA env with private endpoints | Proposed | 2026-06-03 | Keep internal services and the data plane off the public internet via private endpoints |

### Operations

| # | Title | Status | Date | Summary |
|---|-------|--------|------|---------|
| [010](010-cicd-github-actions-oidc.md) | CI/CD via GitHub Actions with OIDC federated credentials | Proposed | 2026-06-03 | Extend existing GitHub Actions to build→ACR→Bicep deploy with no stored Azure secret |
| [011](011-domains-region-environments.md) | Domains, region, environment topology, and CSP/CORS | Proposed | 2026-06-03 | Per-environment public subdomains with managed TLS; widen CSP/CORS as a required pre-go-live edit |

## Best Practices

- **Write ADRs early** — capture the decision while the context is fresh, not weeks later.
- **Keep them concise** — an ADR should be readable in 5 minutes. Move detailed analysis to appendices or linked documents.
- **Record rejected options** — future team members need to know why alternatives were not chosen to avoid revisiting the same ground.
- **Update status, don't delete** — when a decision is superseded, mark it as `Superseded by ADR-NNN` rather than deleting it. The history has value.
- **One decision per ADR** — if a decision covers multiple concerns, split it into multiple ADRs.
- **Link related ADRs** — decisions often depend on or constrain each other. Make these relationships explicit.
