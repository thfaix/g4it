# ADR-012: NumEcoEval container image sourcing

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

Four of the deployed containers are the NumEcoEval services (`api-referentiel`,
`api-expositiondonneesentrees`, `api-event-donneesentrees`, `api-event-calculs`). In
docker-compose they are pulled from `${REGISTRY_URL}` =
`registry.gitlab-forge.din.developpement-durable.gouv.fr/pub/numeco/m4g/numecoeval` at tag
`${TAG}` = `2-2-0` (see `workspace/docker/.env`). This is the container registry of the
French Ecological Ministry's NumEcoEval project — the same project that publishes the
`org.mte.numecoeval:calculs` Maven artifact the backend depends on. [ADR-005](005-container-registry-and-external-images.md)
chose ACR as the single registry and flagged the NumEcoEval source/tags/license as an open
item (plan open decision #2). This ADR closes it.

## Decision Drivers

- Self-contained, reproducible deployments that don't depend on an external (foreign-gov)
  registry's uptime, authentication, or tag retention — consistent with [ADR-005](005-container-registry-and-external-images.md).
- Credential-less pull from ACA via managed identity ([ADR-007](007-secrets-key-vault-managed-identity.md)).
- Version alignment: the running NumEcoEval images must match the `calculs` Maven artifact
  version the backend is built against.
- Licensing must permit mirroring the images into our ACR.

## Considered Options

### Option 1: Mirror the four images into ACR via `az acr import`, pinned to an explicit tag

Import `…/numecoeval/api-*:2-2-0` into ACR (e.g. under a `numecoeval/` repository prefix),
pin the exact tag, and have ACA pull from ACR.

**Pros**:
- Deployment no longer depends on the external registry being reachable or the tag persisting.
- Single governed registry: scanning, retention, and managed-identity pull apply uniformly.
- Explicit, auditable version pinning; re-import is a deliberate, reviewable step.

**Cons**:
- A manual/automated re-import step is needed to adopt new NumEcoEval releases.
- Requires confirming the import is license-compliant.

### Option 2: Pull the images directly from the gov GitLab registry at deploy/run time

Reference `registry.gitlab-forge.din.developpement-durable.gouv.fr/...` directly from ACA.

**Pros**:
- No import/mirroring step.

**Cons**:
- Deployment availability depends on a third-party (foreign-government) registry; an outage,
  auth change, or tag removal breaks deploys/restarts.
- The registry may require credentials; storing/managing them contradicts the credential-less
  goal. Harder to scan/govern.

### Option 3: Rebuild the NumEcoEval images from upstream source

Build the four services ourselves from the NumEcoEval source tree.

**Pros**:
- Full control of the build and base images.

**Cons**:
- We don't own these services; tracking upstream and maintaining four extra builds is a large,
  ongoing burden for no benefit over mirroring published images. Rejected.

## Decision Outcome

**Chosen option**: Option 1 — mirror the four images into ACR with `az acr import`, pinned to
the explicit tag (`2-2-0` today), kept in lock-step with the backend's `calculs` Maven version.
This matches [ADR-005](005-container-registry-and-external-images.md) (ACR as the single,
self-contained registry) and removes any runtime dependency on the external registry. The
`numEcoEvalTag` / `numEcoEvalRepositoryPrefix` Bicep parameters carry the version and ACR path.

Bumping NumEcoEval is a deliberate two-step change: re-import the new tag **and** bump the
backend's `calculs` dependency, verified together.

## Consequences

### Positive

- Reproducible, self-contained deploys independent of the gov registry's availability.
- One governed registry with consistent scanning, retention, and managed-identity pulls.
- Version pinning makes NumEcoEval upgrades explicit and reviewable.

### Negative

- An import step (ideally automated in CI) is needed to adopt new NumEcoEval releases.

### Risks

- **License**: NumEcoEval is published as open source by the French Ecological Ministry, but the
  container-image license/redistribution terms must be confirmed before mirroring — *mitigation*:
  verify the project license; if redistribution into ACR is disallowed, fall back to Option 2
  for these four images only.
- **Version drift** between the running images and the `calculs` artifact — *mitigation*: treat
  the image tag and the Maven version as a single coupled bump, verified end-to-end.

## References

- `workspace/docker/.env` (`REGISTRY_URL`, `TAG=2-2-0`), `workspace/docker/shared-docker-compose.yml`
- `services/backend/pom.xml` (`gitlab-maven` repository, `org.mte.numecoeval:calculs`)
- Plan §5, open decision #2
- Related: [ADR-005](005-container-registry-and-external-images.md),
  [ADR-007](007-secrets-key-vault-managed-identity.md)
