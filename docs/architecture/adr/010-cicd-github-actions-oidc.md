# ADR-010: CI/CD via GitHub Actions with OIDC federated credentials

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The repo already builds the three images in GitHub Actions
(`.github/workflows/{backend,frontend,keycloak}-docker-image.yml`). To deploy to Azure we need
a pipeline that builds and pushes images to ACR and then provisions/updates the container apps
from the Bicep templates ([ADR-002](002-iac-bicep.md)). The pipeline must authenticate to
Azure without a long-lived stored secret and gate production. What deployment pipeline and
auth model do we use?

## Decision Drivers

- Reuse existing CI (GitHub Actions) rather than introducing a new CI system.
- No long-lived Azure credential stored in GitHub.
- Build+push to ACR and run Bicep deployments / `az containerapp update` per app.
- Environment-based approval gating for prod.

## Considered Options

### Option 1: Extend GitHub Actions, authenticate with OIDC federated credentials

Add a deploy workflow that builds+pushes to ACR, then runs `az deployment group create`
(Bicep) / `az containerapp update`, authenticating via GitHub OIDC federated to an Azure
identity (no stored secret). Gate prod behind a GitHub Environment approval.

**Pros**:
- Reuses the existing CI; one platform for build and deploy.
- OIDC federation = no stored Azure secret to rotate or leak.
- GitHub Environments provide native approval gates and per-env secrets/vars.

**Cons**:
- One-time setup of the federated credential and role assignments.
- Couples deployment to GitHub availability.

### Option 2: Azure DevOps Pipelines

Move deployment to Azure DevOps with a service connection.

**Pros**:
- Deep Azure integration; mature release/approval gates.

**Cons**:
- Introduces a second CI system alongside the existing GitHub Actions; duplicate maintenance.
  Not justified.

### Option 3: GitHub Actions with a stored service-principal secret

Same workflows, but authenticate with `AZURE_CREDENTIALS` (client secret).

**Pros**:
- Simplest auth setup.

**Cons**:
- Long-lived secret in GitHub to rotate and protect — contradicts the credential-less goal
  ([ADR-007](007-secrets-key-vault-managed-identity.md)). Rejected.

## Decision Outcome

**Chosen option**: Option 1 — extend GitHub Actions with OIDC federated credentials — because
it reuses the CI the repo already has, eliminates stored Azure secrets, and integrates build,
push-to-ACR, and Bicep deployment in one place with native prod approval gates. ACR builds can
also use `az acr build` to avoid a local Docker daemon ([ADR-005](005-container-registry-and-external-images.md)).

## Consequences

### Positive

- Single CI platform; no stored Azure secret; native environment approvals for prod.
- Images tagged by git SHA + semver flow straight from CI to ACA.

### Negative

- Deployment availability depends on GitHub Actions; initial federated-credential setup.

### Risks

- Over-privileged deploy identity — *mitigation*: scope role assignments to the resource group
  and required roles only; separate identities/environments per stage.

## References

- `docs/azure-deployment-plan.md` §6 (CI/CD)
- `.github/workflows/*-docker-image.yml`
- Related: [ADR-002](002-iac-bicep.md),
  [ADR-005](005-container-registry-and-external-images.md),
  [ADR-007](007-secrets-key-vault-managed-identity.md)
