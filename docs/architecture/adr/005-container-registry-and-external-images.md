# ADR-005: Container registry (ACR) and external image sourcing

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The deployment needs images for all ~10 apps: three built in this repo (frontend, backend,
Keycloak — each with a multi-stage `Dockerfile`), two public externals (Boavizta from
`ghcr.io`, Ecomind from Docker Hub), and four NumEcoEval images pulled from a French-gov
registry (`${REGISTRY_URL}`, the same source as the backend's `org.mte.numecoeval:calculs`
dependency). We need a registry that ACA can pull from with managed identity, and a policy for
where the external images come from. Where do images live, and how are externals sourced?

## Decision Drivers

- Managed-identity pull from ACA (AcrPull) with no stored registry credentials
  ([ADR-007](007-secrets-key-vault-managed-identity.md)).
- Reproducible, self-contained deployments that don't fail because a third-party registry is
  down, rate-limited, or removes a tag.
- Build the three in-repo images without a local Docker daemon where possible.
- Clarify licensing/coordinates of the NumEcoEval images.

## Considered Options

### Option 1: Azure Container Registry, with all externals imported into it

Push the 3 built images to ACR; `az acr import` the 6 external images into ACR; ACA pulls
everything from ACR.

**Pros**:
- Single source of truth; deployments don't depend on third-party registry availability.
- Managed-identity (AcrPull) auth, geo-replication, retention, and vulnerability scanning
  options.
- Build in-cloud with `az acr build` (ACR Tasks) — no local Docker needed; tag by git SHA +
  semver.

**Cons**:
- Must periodically re-import to pick up upstream updates of external images.
- Small ongoing ACR cost.

### Option 2: ACR for built images, pull externals directly from public registries

ACA pulls Boavizta/Ecomind/NumEcoEval straight from their origin registries.

**Pros**:
- Less to maintain (no import step); ACA can pull public registries directly.

**Cons**:
- Deployment availability now depends on `ghcr.io`, Docker Hub (rate limits), and the
  French-gov registry; a removed/retagged image breaks deploys.
- Harder to scan/govern third-party images.

### Option 3: Docker Hub or GitHub Packages as the primary registry

**Pros**:
- Familiar; integrates with existing GitHub Actions.

**Cons**:
- No managed-identity integration with ACA; credentials to store; pull rate limits. Rejected
  in favor of the Azure-native registry.

## Decision Outcome

**Chosen option**: Option 1 — ACR as the single registry, with all external images imported
via `az acr import` — because it makes deployments self-contained and credential-less from
ACA, and lets us govern/scan every image. The three in-repo images are built with the existing
Dockerfiles (backend with `-P SKIP-ALL-TEST`, frontend `npm ci && npm run build`) via
`az acr build` or GitHub Actions ([ADR-010](010-cicd-github-actions-oidc.md)), tagged by git
SHA + semver. **Open item**: confirm the NumEcoEval registry URL, exact tags, and license
before importing the four images.

## Consequences

### Positive

- Self-contained, reproducible deployments independent of third-party registry uptime.
- Credential-less pulls; central place to apply scanning and retention.

### Negative

- An import/refresh step is needed to track upstream updates of external images.

### Risks

- NumEcoEval image coordinates/license may restrict redistribution into ACR — *mitigation*:
  confirm licensing first (plan open decision #2); if redistribution is disallowed, fall back
  to direct pull for those four only.

## References

- `docs/azure-deployment-plan.md` §5 (images & registry), open decision #2
- `services/{frontend,backend,keycloak}/Dockerfile`; `pom.xml` NumEcoEval repository
- Related: [ADR-007](007-secrets-key-vault-managed-identity.md),
  [ADR-010](010-cicd-github-actions-oidc.md),
  [ADR-012](012-numecoeval-image-sourcing.md)
