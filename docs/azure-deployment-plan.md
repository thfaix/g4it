# G4IT — Azure Deployment Plan (Containerized, Managed Services)

Status: **Draft / Proposal** · Scope: deploy the full G4IT stack into a **new Azure resource
group** using **managed Azure services** with **container-based hosting**.

This plan is grounded in the existing repo artifacts (`workspace/docker/*.yml`, the three
`Dockerfile`s, `application-azure.yml`, and the nginx runtime-env-injection model). It does
not introduce a different application architecture — it maps what already runs in
docker-compose onto managed Azure equivalents.

---

## 1. What we are deploying

From `workspace/docker/docker-compose-all.yml` + `shared-docker-compose.yml`, the stack is:

| # | Component | Image source | Port | Role | Browser-facing? |
|---|-----------|--------------|------|------|-----------------|
| 1 | **g4it-frontend** | built here (`services/frontend/Dockerfile`, nginx) | 4200 | Angular SPA | **Yes** |
| 2 | **g4it-backend** | built here (`services/backend/Dockerfile`, Spring Boot) | 8080 | REST API | **Yes** (browser calls it directly) |
| 3 | **keycloak** | built here (`services/keycloak/Dockerfile`, Bitnami 26.0.7) | 8180 | IAM / OIDC | **Yes** (login redirect) |
| 4 | **PostgreSQL 15** | `postgres:15` | 5432 | shared DB (g4it + numecoeval; separate `keycloak` DB) | No |
| 5 | **api-referentiel** | NumEcoEval (external registry) | 8080 | reference data | No (backend only) |
| 6 | **api-expositiondonneesentrees** | NumEcoEval (external registry) | 8080 | data exposition (backend → this) | No |
| 7 | **api-event-donneesentrees** | NumEcoEval (external registry) | 8080 | event pipeline | No |
| 8 | **api-event-calculs** | NumEcoEval (external registry) | 8080 | calculation engine | No |
| 9 | **boaviztapi** | `ghcr.io/boavizta/boaviztapi:1.3.10` (public) | 5000 | impact data API (optional) | No |
| 10 | **ecomind-api** | `sustain4raise/ecomindai:1.1.0` (public) | 8000 | AI estimation (optional) | No |

Key facts that shape the design:

- The **frontend is a runtime-configurable container**, not a pure static site:
  `nginx/25-inject-env-var.sh` substitutes env vars (`KEYCLOAK_URL`, `URL_INVENTORY`,
  `FRONTEND_URL`, `SUB_PATH_FRONT`, `MATOMO_TAG_MANAGER_URL`, `KEYCLOAK_ENABLED`) into the
  built JS/HTML at container start. → It must be deployed as a container, and these vars set
  per environment. `BASE_HREF`/`SUB_PATH_FRONT` must be provided.
- The **browser talks to the backend and Keycloak directly** (`URL_INVENTORY` and
  `KEYCLOAK_URL` are public URLs baked into the SPA at startup). So **frontend, backend, and
  Keycloak all need public ingress**; the rest stays internal.
- The **backend already supports Azure**: `application-azure.yml` wires **Azure Key Vault**
  (secrets) and the pom includes `spring-cloud-azure-starter-storage-blob` +
  `...keyvault`. File storage can therefore move to **Azure Blob** instead of the
  `/app/storage` volume.
- The backend uses **ShedLock (JDBC)** for scheduler locking (`schedulerlocked` package), so
  it is **safe to run multiple replicas** — only one instance runs each cron job.
- Known **Keycloak `iss` validation gotcha** (see `DOCKER-DEPLOYMENT.md`): the JWT
  `issuer-uri` the backend validates must equal the issuer the browser obtained the token
  from. In Azure this is solved by giving Keycloak a single stable public FQDN used by both
  browser and backend.

---

## 2. Hosting choice — recommendation

**Recommended: Azure Container Apps (ACA).** It is the managed/serverless container platform
that best matches "managed services + containerization" without operating Kubernetes:

- Built-in internal service discovery (replaces the compose `numecoeval` network) — internal
  apps reach each other by name over the ACA environment.
- Per-app ingress: external (frontend/backend/keycloak) vs internal-only (numecoeval,
  boavizta, ecomind, … the rest).
- Managed identity → ACR pull, Key Vault, and Blob with no stored credentials.
- Per-app autoscaling (KEDA), scale-to-zero for bursty internal services, revisions for
  safe rollout. Built-in Log Analytics integration and managed TLS certs on custom domains.

Alternatives (documented, not chosen):

- **AKS** — full Kubernetes; more control and more operational burden. Choose only if the
  team already runs k8s or needs features ACA lacks (custom CNI, GPU pools, service mesh).
- **App Service for Containers** — viable for the 3 public web apps, but weaker for the
  internal multi-service mesh; would still need something for the numecoeval set.

The rest of this plan assumes **ACA**. The managed-service mapping below is largely identical
under AKS (only the compute host changes).

---

## 3. Target architecture (managed-service mapping)

```
                              Internet
                                 │
              ┌──────────────────┼─────────────────────┐
              ▼                  ▼                      ▼
   [ACA] g4it-frontend   [ACA] g4it-backend     [ACA] keycloak
      (external ingress)   (external ingress)     (external ingress)
        nginx :4200          Spring :8080            :8180 /auth
              │                  │                      │
              │   browser→API    │  server-side calls   │
              │                  ▼                      │
              │      ┌───────────┴───────────┐          │
              │      ▼           ▼            ▼          │
              │  [ACA] api-   [ACA] api-   [ACA] boavizta / ecomind
              │  referentiel  exposition…  (internal ingress only)
              │      │  api-event-donneesentrees, api-event-calculs
              │      └───────────┬───────────┘
              ▼                  ▼                      ▼
        (managed)          Azure Database for PostgreSQL Flexible Server
                            DBs: postgres (g4it + numecoeval) · keycloak
   Azure Blob Storage  ◄── backend file storage (azure profile)
   Azure Key Vault     ◄── DB password, client secrets, etc.
   Azure Container Registry ── all images   Log Analytics / App Insights ── telemetry
```

Managed services in the new resource group:

| Concern | Managed Azure service | Notes |
|---|---|---|
| Container hosting | **Azure Container Apps** (+ Environment) | one Environment, ~10 container apps |
| Image registry | **Azure Container Registry** | hosts the 3 built images + mirrored externals |
| Relational DB | **Azure DB for PostgreSQL — Flexible Server** | replaces `postgres:15`; create `postgres` & `keycloak` DBs; `reWriteBatchedInserts` already in JDBC URL |
| File storage | **Azure Blob Storage** | backend `azure` profile; replaces `/app/storage` volume |
| Secrets | **Azure Key Vault** | backend reads it directly; ACA also references KV secrets |
| Identity | **Managed Identity** (user-assigned) | ACR pull + KV + Blob, no secrets in config |
| Observability | **Log Analytics + Application Insights** | required by ACA env; `/actuator` already exposed |
| DNS / TLS | **Azure DNS + ACA managed certificates** | custom domains for the 3 public apps |
| Networking | **VNet** (ACA env injected) + **Private Endpoint** for Postgres/KV/Blob | keep data plane off the public internet |

---

## 4. Required application config changes (concrete)

No code changes are required for the core path; this is configuration. Per app:

**Backend** (`SPRING_PROFILES_ACTIVE`): add `azure` to enable Key Vault + Blob, keep
`postgres`. Set, as ACA env / KV references:
- `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` → Flexible Server (password from KV).
- `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` → **public** Keycloak FQDN
  (`https://<keycloak-fqdn>/auth/realms/g4it`).
- `NUMECOEVAL_BASEURL` → `http://api-expositiondonneesentrees` (internal ACA name),
  `NUMECOEVALREFERENTIAL_BASEURL` → `http://api-referentiel`, `BOAVIZTAPI_BASEURL` → internal.
- `CORS_ALLOWED_ORIGINS` → public frontend URL.
- Azure profile vars (already templated in `application-azure.yml`):
  `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `SPRING_CLOUD_AZURE_KEYVAULT_SECRET_ENDPOINT`,
  and prefer **managed identity** over `AZURE_CLIENT_ID/SECRET`.
- Blob: confirm the filesystem `azure`/blob settings (container name, account endpoint);
  validate `common/filesystem` blob implementation against the chosen account.
- `SPRING_LIQUIBASE_CONTEXTS: "!dev"` (as in compose) so dev seed data is skipped.

**Frontend** (runtime env injection): `KEYCLOAK_URL=https://<keycloak-fqdn>/auth`,
`KEYCLOAK_ENABLED=true`, `URL_INVENTORY=https://<backend-fqdn>/`,
`FRONTEND_URL=https://<frontend-fqdn>`, `SUB_PATH_FRONT=/` (and `BASE_HREF` accordingly).
The nginx **CSP** in `nginx.conf` is restrictive (`connect-src 'self' …microsoftonline…`) —
it must be widened to allow the backend + Keycloak FQDNs, or the apps must be served under
one domain. **This is a required edit before go-live.**

**Keycloak**: production hostname config (`KC_HOSTNAME`, `KC_PROXY=edge`/proxy-headers),
point its DB at the Flexible Server `keycloak` database, import the realm
(`services/keycloak/imports`, themes, extensions are baked into the image). **Change the
default admin password** (compose ships `admin/password`) and store it in Key Vault. Run
**min replicas = 1, no scale-to-zero** (cold start breaks sessions); single replica avoids
Infinispan clustering setup.

---

## 5. Images & registry

- Build the 3 in-repo images with the existing Dockerfiles (multi-stage; backend builds with
  `-P SKIP-ALL-TEST`, frontend `npm ci && npm run build`). Use **`az acr build`** (ACR Tasks,
  no local Docker) or GitHub Actions → push to ACR. Tag by git SHA + semver.
- **External images** must be sourced into ACR (or referenced directly — ACA can pull public
  registries):
  - boavizta (`ghcr.io/...`) and ecomind (`docker.io/sustain4raise/...`) are **public** →
    import via `az acr import`.
  - **NumEcoEval x4** come from `${REGISTRY_URL}` (the French-gov registry the backend's
    `calculs` dep also uses). **Open item:** confirm the exact registry/coordinates and
    license, then `az acr import` them so deployment doesn't depend on an external registry.

---

## 6. Infrastructure-as-Code & CI/CD

- **IaC: Bicep** (Azure-native, no extra tooling). One `main.bicep` + modules per resource
  (RG-scoped: ACR, Log Analytics, ACA env, Postgres, KV, Blob, identity, the container apps).
  Parameterize per environment (region, names, sizes, replica counts, FQDNs). *(Terraform is
  a viable alternative if the org standardizes on it.)*
- **CI/CD: extend existing GitHub Actions.** The repo already has
  `.github/workflows/*-docker-image.yml`. Add a deploy workflow that: builds+pushes to ACR →
  `az deployment group create` (Bicep) / `az containerapp update` per app, using **OIDC
  federated credentials** (no stored Azure secret). Gate prod behind environment approval.

---

## 7. Deployment sequence

1. Create the **resource group** + Log Analytics workspace.
2. Provision **ACR**, **Key Vault**, **Storage account/Blob**, **PostgreSQL Flexible Server**
   (create `postgres` and `keycloak` databases), and a **user-assigned managed identity**
   with role assignments (AcrPull, Key Vault Secrets User, Storage Blob Data Contributor).
3. Seed **Key Vault** secrets (DB password, Keycloak admin password, any client secrets).
4. Build/push the 3 images; import the 6 external images into ACR.
5. Create the **ACA Environment** (VNet-injected) + private endpoints for Postgres/KV/Blob.
6. Deploy **internal** apps first: numecoeval x4, boavizta, ecomind (internal ingress).
7. Deploy **Keycloak** (external ingress, hostname configured, realm imported), then run DB
   migrations implicitly on first boot; verify `/auth` and the `g4it` realm.
8. Deploy **backend** (external ingress); Liquibase applies `greenitdb` changelog on startup
   against Flexible Server; verify `/actuator/health` = UP and connectivity to numecoeval + KV
   + Blob.
9. Deploy **frontend** (external ingress) with the public FQDNs injected.
10. Wire **custom domains + managed TLS**, finalize **CSP** and **CORS**, smoke-test login →
    inventory → an evaluation run end-to-end.

---

## 8. Scaling, resilience, observability

- **Backend**: 1–N replicas (ShedLock keeps cron singular); scale on HTTP/CPU. ~1.5–2 GB
  (JVM `-Xmx1g`).
- **NumEcoEval**: sizes hinted by compose memory limits (referential ~800 MB, exposition
  ~400 MB, calculs ~220 MB, donneesentrees ~150 MB). Map to ACA CPU/memory; internal services
  may scale-to-zero except referential (warm).
- **Keycloak / PostgreSQL**: always-on; enable Flexible Server HA + automated backups.
- **Telemetry**: ACA → Log Analytics; backend `/actuator` + Application Insights; alerts on
  health, DB connections, blob errors.

---

## 9. Cost levers

Largest costs: PostgreSQL Flexible Server (size + HA), always-on Keycloak + backend, ACR.
Levers: scale-to-zero for internal numecoeval/boavizta/ecomind when idle, consumption-plan
ACA, right-size Postgres SKU per environment, single environment for non-prod.

---

## 10. Open decisions / questions

1. **Hosting**: confirm **ACA** (recommended) vs AKS vs App Service for Containers.
2. **NumEcoEval images**: source registry, exact tags, and license for the 4 images.
3. **Identity**: keep **Keycloak** (current design) vs migrate to **Microsoft Entra ID /
   External ID** (the nginx CSP already references `login.microsoftonline.com`, suggesting it
   was considered). Migrating is a larger change — out of scope here unless prioritized.
4. **Domains/region/environments**: target region(s), custom domain names, and how many
   environments (dev/test/prod).
5. **Blob storage**: confirm `common/filesystem` Azure-blob implementation is complete for
   all read/write/retention paths used by loading/evaluation/export.
6. **IaC tool**: Bicep (recommended) vs Terraform.

## 11. Out of scope (for this iteration)

Documentation site (`services/documentation`, Hugo), Matomo analytics, Entra ID migration,
DR across regions, and any application code refactor beyond config.
