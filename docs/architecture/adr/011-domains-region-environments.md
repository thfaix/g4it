# ADR-011: Domains, region, environment topology, and CSP/CORS

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The SPA is a runtime-configurable container: `nginx/25-inject-env-var.sh` substitutes
`KEYCLOAK_URL`, `URL_INVENTORY`, `FRONTEND_URL`, `SUB_PATH_FRONT`, `BASE_HREF`, etc. into the
built assets at startup, and the browser then calls the backend and Keycloak at those
**public** URLs. So the frontend, backend, and Keycloak each need a stable public FQDN, and
the nginx Content-Security-Policy (`connect-src 'self' …microsoftonline…`) must permit the
backend and Keycloak origins. We also need to decide the target region(s), the custom domain
names, and how many environments (dev/test/prod) to run. What is the domain/region/environment
topology, and how do CSP/CORS follow from it?

## Decision Drivers

- The browser needs stable public FQDNs for frontend, backend, and Keycloak (baked into the
  SPA at container start, and used for JWT issuer validation — see
  [ADR-008](008-identity-provider-keycloak.md)).
- CSP `connect-src` and backend `CORS_ALLOWED_ORIGINS` must match the chosen domains, or login
  and API calls break.
- Reproducible separation between dev/test/prod; cost control for non-prod.
- Managed TLS for the public apps.

## Considered Options

### Option 1: Three subdomains under one parent domain, per environment, managed TLS

e.g. `app.<env>.g4it.example`, `api.<env>.g4it.example`, `auth.<env>.g4it.example`, with ACA
managed certificates. Widen the nginx CSP `connect-src` to the backend + Keycloak FQDNs and
set `CORS_ALLOWED_ORIGINS` to the frontend FQDN; inject the FQDNs per environment.

**Pros**:
- Clear separation of the three public apps; independent scaling and certs.
- Per-environment FQDNs keep dev/test/prod isolated and parameterizable in IaC/CI.
- Stable Keycloak FQDN satisfies the issuer-validation constraint.

**Cons**:
- CSP/CORS must be widened and kept in sync per environment (a required pre-go-live edit).
- Three DNS records + certs per environment.

### Option 2: Single domain with path routing (`/`, `/api`, `/auth`)

Serve all three apps under one hostname via a reverse proxy / path-based ingress.

**Pros**:
- Simplest CSP (`'self'` largely suffices); one cert; same-origin avoids most CORS.

**Cons**:
- Requires a fronting proxy/gateway and path-prefix handling for each app; more routing
  config than ACA per-app ingress gives by default.

### Option 3: Single shared environment for all stages

One environment, no dev/test/prod separation.

**Pros**:
- Lowest cost and least to manage.

**Cons**:
- No isolation for testing changes; risky for prod data. Acceptable only to *share a non-prod*
  environment, not to merge prod with non-prod.

## Decision Outcome

**Chosen option**: Option 1 — per-environment subdomains under one parent domain with ACA
managed TLS — because it keeps the three public apps cleanly separated, gives Keycloak the
stable FQDN its issuer validation needs, and parameterizes naturally per environment in IaC/CI.
As a **required pre-go-live edit**, widen the nginx CSP `connect-src` to the backend and
Keycloak FQDNs and set `CORS_ALLOWED_ORIGINS` to the frontend FQDN. Run **separate dev/test/prod**
environments, but a single shared environment is acceptable for *non-prod* to save cost
(Option 3 applied to non-prod only). **Open item**: confirm target region(s) and the actual
custom domain names (plan open decision #4).

## Consequences

### Positive

- Stable, isolated public FQDNs per app and per environment; managed TLS.
- Issuer validation and CORS become deterministic from the chosen domains.

### Negative

- CSP/CORS must be widened and maintained per environment; more DNS/cert objects.

### Risks

- A too-narrow CSP or wrong issuer FQDN silently breaks login/API calls — *mitigation*:
  validate CSP/CORS and the login→inventory→evaluation flow during the go-live smoke test.
- Region/domain choices not yet confirmed — *mitigation*: parameterize FQDNs/region in IaC so
  they are set per environment without code changes ([ADR-002](002-iac-bicep.md)).

## References

- `docs/azure-deployment-plan.md` §1, §4 (frontend/CSP/CORS), §7 step 10, open decision #4
- `services/frontend/nginx/25-inject-env-var.sh`, `services/frontend/nginx/nginx.conf`
- Related: [ADR-001](001-container-hosting-azure-container-apps.md),
  [ADR-008](008-identity-provider-keycloak.md),
  [ADR-013](013-frontend-csp-runtime-configurable.md)
