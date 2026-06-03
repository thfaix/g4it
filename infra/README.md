# G4IT — Azure Infrastructure (Bicep)

Infrastructure-as-Code for the containerized G4IT deployment on Azure Container Apps.
Implements [`docs/azure-deployment-plan.md`](../docs/azure-deployment-plan.md) and the ADRs in
[`docs/architecture/adr`](../docs/architecture/adr).

## Layout

```
infra/
  main.bicep                 # RG-scoped: all resources + the 10 container apps
  main.subscription.bicep    # subscription-scoped: creates the resource group, then deploys main.bicep
  params/
    dev.bicepparam               # params for main.bicep (existing RG)
    dev.subscription.bicepparam  # params for main.subscription.bicep (new RG)
  modules/
    monitoring.bicep         # Log Analytics + Application Insights   (ADR-006)
    network.bicep            # VNet, subnets, private DNS zones        (ADR-009)
    identity.bicep           # user-assigned managed identity          (ADR-007)
    registry.bicep           # ACR + AcrPull role assignment           (ADR-005)
    keyvault.bicep           # Key Vault (RBAC) + seeded secrets        (ADR-007)
    storage.bicep            # Storage account + g4it blob container    (ADR-004)
    postgres.bicep           # PostgreSQL Flexible Server + databases   (ADR-003)
    aca-environment.bicep    # ACA managed environment (VNet-injected)  (ADR-001)
    container-app.bicep      # reusable single container app
```

## Does this create the resource group?

Two entrypoints, pick one:

- **`main.bicep`** is **resource-group scoped** — it deploys *into an existing* resource group
  and does **not** create it.
- **`main.subscription.bicep`** is **subscription scoped** — it **creates a new** resource group
  and deploys `main.bicep` into it.

## Prerequisites

- Azure CLI + Bicep (`az bicep version`), and `az login` to the target subscription.
- The deploying principal needs, at minimum, **Contributor** + **User Access Administrator**
  (role assignments are created for ACR/Key Vault/Storage) and **Key Vault Secrets Officer**
  data-plane access (the deployment writes secrets into Key Vault).
- Images pushed/imported into ACR first — or deploy the platform, then push images and update
  the apps (see [ADR-005](../docs/architecture/adr/005-container-registry-and-external-images.md)).
- Secrets are read from environment variables at build time (never committed):

  ```bash
  export G4IT_PG_ADMIN_PASSWORD='<strong-password>'
  export G4IT_KEYCLOAK_ADMIN_PASSWORD='<strong-password>'
  ```

## Deploy

**Into an existing resource group:**

```bash
az group create -n rg-g4it-dev -l francecentral
az deployment group create \
  -g rg-g4it-dev \
  -f infra/main.bicep \
  -p infra/params/dev.bicepparam
```

**Creating a new resource group:**

```bash
az deployment sub create \
  -l francecentral \
  -f infra/main.subscription.bicep \
  -p infra/params/dev.subscription.bicepparam
```

Preview first with `--what-if` (append to either command).

### ⚠️ Keep the Keycloak admin password stable across deploys

Keycloak bootstraps its admin user **only once** (first start against an empty DB) from
`KEYCLOAK_ADMIN_PASSWORD`; it never updates that password on later starts. If a deploy passes a
*different* `keycloakAdminPassword` than the one Keycloak first booted with, the ACA secret
drifts from the stored password and **admin login breaks** (the value in the secret is no longer
the one Keycloak accepts). The Postgres password can rotate safely (server + secret update
together), but the Keycloak admin password **must not change** between deploys.

Use the idempotent wrapper, which reuses the already-deployed password from the ACA secrets and
only falls back to the env vars on the first deploy:

```bash
# First deploy: set the env vars once (strong, and then keep them).
export G4IT_KEYCLOAK_ADMIN_PASSWORD='<stable-strong-password>'
export G4IT_PG_ADMIN_PASSWORD='<stable-strong-password>'
./infra/scripts/deploy.sh rg-g4it-dev northeurope
# Subsequent deploys: env vars optional — existing secrets are reused automatically.
./infra/scripts/deploy.sh rg-g4it-dev northeurope
```

After a deploy to a **fresh** environment, also run the post-deploy steps:
`scripts/import-external-images.sh` (mirror images), `scripts/configure-keycloak-redirects.sh`
(register the frontend redirect URI), and set a password for the realm's `admin@g4it.com` user
(the realm export ships it hashed) via the Keycloak admin console or admin API.

## What gets deployed

| Resource | Module | Notes |
|---|---|---|
| Log Analytics + App Insights | `monitoring` | ACA log sink + backend telemetry |
| VNet (3 subnets) + 3 private DNS zones | `network` | aca / postgres / private-endpoints subnets |
| User-assigned managed identity | `identity` | AcrPull + KV Secrets User + Blob Data Contributor |
| Azure Container Registry | `registry` | single registry for all images |
| Key Vault (RBAC) | `keyvault` | secrets: `db-password`, `keycloak-admin-password`, `<ORG>` connection string |
| Storage account + `g4it` container | `storage` | backend file storage |
| PostgreSQL Flexible Server | `postgres` | `postgres` + `keycloak` databases, VNet-integrated |
| ACA managed environment | `aca-environment` | Consumption profile, VNet-injected |
| 10 container apps | `container-app` ×N | 3 external (frontend/backend/keycloak), 7 internal |

The data plane (Postgres, Key Vault, Blob) is private by default (`dataPlanePublicAccess: Disabled`);
the backend reaches the NumEcoEval/Boavizta apps by their ACA app name over internal ingress.

## Key parameters

| Param | Default | Purpose |
|---|---|---|
| `location` | — | Azure region |
| `namePrefix` / `environmentName` | `g4it` / `dev` | naming + tags |
| `postgresAdminPassword` / `keycloakAdminPassword` | (env var) | secrets, stored in Key Vault |
| `organizationName` | `DEMO` | name of the Key Vault secret holding the storage connection string (see below) |
| `dataPlanePublicAccess` | `Disabled` | flip to `Enabled` for a quick public dev env |
| `imageTag` / `numEcoEvalTag` | `latest` / `2-2-0` | image tags pulled from ACR (NumEcoEval pinned per [ADR-012](../docs/architecture/adr/012-numecoeval-image-sourcing.md)) |
| `deployEcomind` | `false` | deploy the optional Ecomind AI app |
| `*CustomFqdn` | `''` | custom domains; empty = ACA default domain ([ADR-011](../docs/architecture/adr/011-domains-region-environments.md)) |
| `postgresSku*` / `postgresHighAvailability` | Burstable / off | right-size per environment |

## Follow-ups before go-live (open items)

These are configuration/validation items the IaC cannot settle on its own — tracked in the plan
and ADRs:

1. **NumEcoEval images** — import is scripted in [`scripts/import-external-images.sh`](scripts/import-external-images.sh)
   (`az acr import` of the four `numecoeval/*` images pinned to `2-2-0`, plus Boavizta) so the ACR
   references resolve ([ADR-005], [ADR-012]). **Remaining:** confirm the image license permits
   mirroring before running it (plan open #2).
2. **Frontend CSP/CORS** — the nginx `connect-src`/`frame-src` are now templated at container start
   from `URL_INVENTORY`/`KEYCLOAK_URL` ([ADR-013]) and `CORS_ALLOWED_ORIGINS` is set to the frontend
   URL. **Remaining:** validate the login→inventory flow against the rendered CSP in the go-live
   smoke test ([ADR-011], plan open #4).
3. **Blob via Key Vault** — the backend resolves a per-organization **storage connection string**
   from Key Vault (`AzureFileSystem`/`VaultAccessClient`) and lists the `g4it`-prefixed container.
   This deployment seeds that secret (name = `organizationName`, uppercased, `_`→`-`). Confirm the
   organization name matches your seed data and that all read/write/retention paths work
   ([ADR-004], plan open #5).
4. **Managed identity for Key Vault** — `application-azure.yml` now makes `AZURE_CLIENT_SECRET`
   optional, and this deployment sets `AZURE_CLIENT_ID` to the user-assigned identity plus
   `SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED=true` ([ADR-007]). **Remaining:** verify
   the backend acquires a Key Vault token via managed identity (no client secret) at runtime.
5. **Keycloak proxy/hostname env** — `KEYCLOAK_PROXY=edge` / `KEYCLOAK_HOSTNAME` are set for the
   Bitnami 26.0.7 image; verify against that image's env-var contract, and ensure the single
   stable public FQDN is used for both browser and backend (the `iss` constraint, [ADR-008]).

[ADR-004]: ../docs/architecture/adr/004-file-storage-azure-blob.md
[ADR-005]: ../docs/architecture/adr/005-container-registry-and-external-images.md
[ADR-007]: ../docs/architecture/adr/007-secrets-key-vault-managed-identity.md
[ADR-008]: ../docs/architecture/adr/008-identity-provider-keycloak.md
[ADR-011]: ../docs/architecture/adr/011-domains-region-environments.md
[ADR-012]: ../docs/architecture/adr/012-numecoeval-image-sourcing.md
[ADR-013]: ../docs/architecture/adr/013-frontend-csp-runtime-configurable.md
