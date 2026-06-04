# ADR-013: Runtime-configurable frontend CSP for cross-origin backend and Keycloak

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

The frontend nginx config (`services/frontend/nginx/nginx.conf`) sets a restrictive
Content-Security-Policy whose `connect-src` is:

```
connect-src 'self' https://login.microsoftonline.com https://graph.microsoft.com;
```

The browser, however, calls the **backend** (`URL_INVENTORY`) and **Keycloak**
(`KEYCLOAK_URL`) directly, and under [ADR-011](011-domains-region-environments.md) those are
**different origins** (separate per-environment FQDNs). With the CSP above, those XHR/fetch
calls — and Keycloak's silent-SSO iframe — are blocked. Compounding this: the CSP is **baked
into `nginx.conf` at image build time**, while the per-environment URLs are injected at
**container start** by `nginx/25-inject-env-var.sh`, which only substitutes `*.js`/`*.html`
files — **not** `nginx.conf`. So today there is no way to set the right origins per environment
without rebuilding the image. [ADR-011](011-domains-region-environments.md) flagged widening the
CSP as a required pre-go-live edit; this ADR decides how.

## Decision Drivers

- The CSP must allow the backend and Keycloak origins, which differ per environment.
- Keycloak login needs both `connect-src` (token/userinfo fetch) and `frame-src` (the
  `check-sso` silent iframe) to include the Keycloak origin.
- Reuse the existing runtime env-injection model (one image, configured per environment) —
  consistent with how `KEYCLOAK_URL`/`URL_INVENTORY` are already injected.
- Keep the CSP as tight as possible (no wildcards); only the necessary origins.

## Considered Options

### Option 1: Template the CSP at container start from the injected env vars

Convert the CSP into a templated `nginx.conf` (or a snippet) and have the entrypoint substitute
the backend + Keycloak origins (derived from `URL_INVENTORY`, `KEYCLOAK_URL`, `FRONTEND_URL`)
into `connect-src` and `frame-src` before nginx starts — the same envsubst mechanism already
used for the JS/HTML.

**Pros**:
- One image, configured per environment — matches the existing runtime-injection pattern.
- CSP stays tight and correct for each environment's actual FQDNs; no rebuild to change origins.
- Keeps the security header in nginx, close to where it's served.

**Cons**:
- Adds nginx.conf (or a CSP snippet) to the substitution step; the entrypoint must run envsubst
  over the config and validate it before nginx starts.

### Option 2: Statically widen the CSP and rebuild per environment

Hardcode each environment's origins into `nginx.conf` and build a per-environment image.

**Pros**:
- No entrypoint change.

**Cons**:
- Breaks the "one image, runtime-configured" model; a CSP/FQDN change means a rebuild;
  error-prone across dev/test/prod.

### Option 3: Serve frontend, backend, and Keycloak under one origin (path routing)

Adopt [ADR-011](011-domains-region-environments.md) Option 2 (single domain, `/`, `/api`,
`/auth`) so calls are same-origin and `connect-src 'self'` largely suffices.

**Pros**:
- Simplest CSP; avoids cross-origin entirely.

**Cons**:
- Contradicts the chosen per-subdomain topology ([ADR-011](011-domains-region-environments.md));
  requires a fronting reverse proxy/gateway and path-prefix handling. Larger change.

### Option 4: Set the CSP at the edge (Front Door / ingress response-header policy)

Strip the nginx CSP and inject it as a response-header rule at an edge service.

**Pros**:
- Centralized header management; no container change.

**Cons**:
- Adds an edge component not otherwise required; splits security config away from the app.
  Deferred with the WAF/edge decision noted in [ADR-009](009-networking-vnet-private-endpoints.md).

## Decision Outcome

**Chosen option**: Option 1 — template the CSP at container start from the already-injected
env vars — because it reuses the frontend's established runtime-configuration model, keeps the
policy tight and per-environment-correct, and avoids both rebuilds and an extra edge component.
The entrypoint will substitute the backend and Keycloak origins into `connect-src` (and the
Keycloak origin into `frame-src` for silent SSO) and validate the rendered config (`nginx -t`)
before start. `frame-ancestors 'none'` and the other directives are unchanged. The stale
`login.microsoftonline.com`/`graph.microsoft.com` entries are removed unless Entra is adopted
([ADR-008](008-identity-provider-keycloak.md)).

## Consequences

### Positive

- One image works across environments with a correct, minimal CSP per environment.
- No rebuild to change origins; security header stays in nginx, close to the served assets.

### Negative

- The container entrypoint gains responsibility for rendering and validating the CSP; a bad
  substitution must fail fast (`nginx -t`) rather than serve a broken policy.

### Risks

- A missed directive (e.g. forgetting `frame-src` for the Keycloak silent-SSO iframe) silently
  breaks login — *mitigation*: include the login→inventory flow in the go-live smoke test
  ([ADR-011](011-domains-region-environments.md)).
- Over-broad substitution (wildcards) would weaken the CSP — *mitigation*: substitute exact
  scheme+host origins only.

## References

- `services/frontend/nginx/nginx.conf` (line 48 CSP), `services/frontend/nginx/25-inject-env-var.sh`
- Plan §4 (frontend/CSP), open decision #4
- Related: [ADR-008](008-identity-provider-keycloak.md),
  [ADR-011](011-domains-region-environments.md)
