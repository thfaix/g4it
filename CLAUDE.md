# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What G4IT is

G4IT is a platform for assessing and managing the environmental footprint of an
organization's IT (information systems and "digital services"). Impact calculation is
delegated to the **NumEcoEval** engine (a French Ecological Ministry project); G4IT wraps
it with multi-tenancy, file ingestion, indicators/aggregation, and a web UI.

## Repository layout

This is a polyrepo-style monorepo. Each deployable component lives under `services/` and
has its own build, Dockerfile, and `.gitlab-ci.yml`:

- `services/backend` — Java 21 / Spring Boot 3.5 REST API (the bulk of the logic).
- `services/frontend` — Angular 21 SPA.
- `services/keycloak` — custom Keycloak image (theme + realm import, IAM).
- `services/documentation` — Hugo site (uses git submodules for themes; run
  `git submodule update --init` before building).
- `workspace/docker` — docker-compose files that wire the full local stack together.

CI runs per-component and only when that component's files change (see root
`.gitlab-ci.yml` and `.github/workflows/`).

## Backend (services/backend)

Build/test commands run from `services/backend`:

```bash
mvn clean package                      # full build + tests
mvn clean package -P SKIP-ALL-TEST     # build, skip all tests (used for docker images)
mvn test                               # unit tests (run under spring profile "test")
mvn test -Dtest=MyServiceTest          # single test class
mvn test -Dtest=MyServiceTest#myMethod # single test method
mvn verify -P coverage                 # tests + JaCoCo coverage report (target/site/jacoco)
```

- **Java 21, Maven, single module.** Tests are named `*Test.java` / `*Tests.java`; Surefire
  forces `spring.profiles.active=test`. SonarQube quality gate requires **≥80% coverage**.
- **External dependency `org.mte.numecoeval:calculs`** is pulled from a French gov GitLab
  Maven repo declared in `pom.xml` (`<repositories>`); `settings.xml` configures it. A build
  on a fresh machine needs access to that repo.
- Run locally with `mvn spring-boot:run` (or run `BackendApplication`); needs PostgreSQL +
  Keycloak + the NumEcoEval services reachable (see local stack below). The JVM timezone is
  forced to **UTC**.

### OpenAPI-first — do not edit generated Java

The public REST API and several client connectors are **generated at build time** by the
`openapi-generator-maven-plugin`. **Edit the YAML specs, not the generated sources.**

- The G4IT API spec lives as many files in `src/main/resources/swagger/greenit/`. They are
  merged (`openapi-merger`) into one spec, then generated (Spring `delegatePattern`) into
  `com.soprasteria.g4it.backend.server.gen` (interfaces + DTOs). Controllers implement the
  generated `*Delegate` interfaces.
- Connector clients (NumEcoEval exposition/referential, Ecomind AI) are generated as
  WebClient code under `...client.gen.connector.*` from specs in `swagger/numecoeval/` and
  `swagger/ecomind/`.
- Generated DTOs use Lombok `@SuperBuilder`/`@Jacksonized`; `OffsetDateTime` is mapped to
  `LocalDateTime`. Anything under `**/gen/**` is regenerated and excluded from coverage.

### Backend package conventions

Code is organized by feature module under `com.soprasteria.g4it.backend.api*` (e.g.
`apiinventory`, `apidigitalservice`, `apievaluating`, `apiloadinputfiles`, `apiindicator`,
`apiuser`, `apiworkspace`, `apiadministrator`). Each module follows the same layering:

`controller` (implements generated delegate) → `business` (services) → `repository`
(Spring Data JPA) → `modeldb` (JPA entities) / `model` (domain) / `mapper` (**MapStruct**).
Entities use Lombok. Shared infrastructure lives under `common/` (notably `common/task`,
`common/filesystem`, `common/criteria`).

### Core domain flow

The central pipeline turns uploaded data into impact indicators:

`apiloadinputfiles` (validate + load input files) → `apievaluating` (run the NumEcoEval
`calculs` engine, plus Boavizta and AI-model estimation) → `apiindicator` (aggregate into
indicators the UI reads).

Long-running loading/evaluation runs **asynchronously as a `Task`** (`common/task`):
`TaskType` is `LOADING` / `EVALUATING` / `EVALUATING_DIGITAL_SERVICE`, with a `TaskStatus`
lifecycle. The two work types are inventories (full IS) and digital services. Scheduled jobs
are guarded by **ShedLock** so they run once across instances (`schedulerlocked`); the
`scheduler` package runs cron-based retention/cleanup (data, storage output/export,
workspace, and local temp-file deletion — all configurable in `application.yml`).

### Multi-tenancy, persistence, auth

- **Tenancy:** `Organization` (DB table `g4it_subscriber` — "organization" was formerly
  called "subscriber"; both terms appear) → `Workspace` → `User`, with roles assigned at
  both org and workspace level (`UserRoleOrganization`, `UserRoleWorkspace`). Most data is
  scoped to a workspace.
- **DB:** PostgreSQL with **Liquibase** migrations in `src/main/resources/db/changelog/`
  (master: `greenitdb.changelog-master.yml`, applied with Liquibase contexts e.g. `local`).
  Add schema changes as new changelog files — do not edit applied ones.
- **File storage** is abstracted (`common/filesystem`) over local FS (dev) and Azure Blob
  (`application-azure.yml`). Caching is DB-backed (`DatabaseCacheConfiguration`).
- **Auth:** OAuth2 resource server validating Keycloak JWTs (realm `g4it`). `SecurityConfig`
  has a `nosecurity` profile (`application-nosecurity.yml`) that permits all requests for
  local work without Keycloak.

## Frontend (services/frontend)

Commands run from `services/frontend` (Node 20):

```bash
npm install
npm start                 # ng serve -> http://localhost:4200 (talks to backend on :8080)
npm run build             # production build
npm run build:overgreen   # build with base-href /overgreen/ (deployment variant)
npm test                  # Karma/Jasmine unit tests with coverage
npm run test:ci           # CI test configuration
npm run prettier          # format ts/js/html/scss (Prettier is the formatter)
npm run cypress:open      # Cypress e2e, interactive
npm run cypress:run       # Cypress e2e, headless (one report)
```

Run a single Karma spec by narrowing the include, e.g.
`npx ng test --include='**/inventory.service.spec.ts'`.

### Frontend architecture

- **Angular 21 standalone components** (no NgModules for features). Bootstrap config is in
  `src/app/app.config.ts`; routes in `src/app/app-routing.module.ts`; features under
  `src/app/layout/`; shared code under `src/app/core/` (`service/business`, `service/data`,
  `store`, `guard`, `interceptors`, `model`, `pipes`).
- **State:** `@ngneat/elf` stores live in `src/app/core/store` (`*.store.ts` /
  `*.repository.ts`). Keep business logic in services, not templates.
- **HTTP:** functional interceptors (`apiInterceptor`, `httpErrorInterceptor`) are wired in
  `app.config.ts`. Data services in `core/service/data` call the backend.
- **Auth:** Keycloak via `keycloak-angular`; `CustomAuthService.init()` runs as an
  app initializer before the app loads.
- **UI:** PrimeNG (Aura theme/`@primeuix/themes`) + PrimeFlex; charts via ECharts
  (`ngx-echarts`). Prefer existing PrimeNG components and reuse assets in `assets/images`.
- **i18n:** `@ngx-translate`; strings in `src/assets/i18n/<lang>.json`, used as
  `{{ 'key.path' | translate }}`. Default/allowed languages come from `src/constants`.
- **Base href** is injected at container runtime (see README "Env variable injection");
  `BASE_HREF` must be provided when running the built image.

> Note: the frontend README references `npm run start:mockserver` / a `mock-server/` dir and
> `build:nohref` — these are stale and no longer present in `package.json`. Use the scripts
> listed above.

## Local full stack

`workspace/docker/docker-compose-all.yml` brings up the whole environment: PostgreSQL,
Keycloak, the NumEcoEval suite (referential, exposition, event/calculs), and the G4IT
backend + frontend. Per `DOCKER-DEPLOYMENT.md`: build the backend (`mvn clean package -P
SKIP-ALL-TEST` then `docker build -f services/backend/Dockerfile -t g4it-backend`) and
frontend images, add `127.0.0.1 keycloak` to your hosts file, then `docker compose -f
workspace/docker/docker-compose-all.yml up -d`. App at http://localhost:4200; seeded user
`admin@dev.com` / `password`. The dev Keycloak realm is `dev-realm-export.json`.

## Conventions

- Branch names: `feat/<name>` or `fix/<name>`; keep PRs small. Backend logging via SLF4J
  (`@Slf4j`), never `System.out`. Frontend: standalone components, lazy loading, no console
  logs or hardcoded values. CI enforces SonarQube (no blocker/critical issues, ≥80%
  coverage, low duplication).
- This repo follows Green-IT / eco-design goals: minimize API calls, data transfer, and
  unnecessary computation; paginate and optimize queries.
