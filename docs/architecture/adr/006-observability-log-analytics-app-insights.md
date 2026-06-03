# ADR-006: Observability with Log Analytics and Application Insights

**Status**: Proposed
**Date**: 2026-06-03
**Decision Makers**: G4IT platform & DevOps team (TBD)

## Context and Problem Statement

Running ~10 container apps with asynchronous, long-running loading/evaluation `Task`s and
cron-based retention jobs requires centralized logs, metrics, and traces — there is no host to
SSH into on a serverless platform ([ADR-001](001-container-hosting-azure-container-apps.md)).
The backend already exposes Spring Boot `/actuator` (health and metrics). An ACA Environment
also *requires* a destination for its platform/console logs. What observability stack should
we use?

## Decision Drivers

- ACA requires a logs destination for the environment.
- Need health/metrics for the backend (`/actuator`) and request tracing across the
  browser → backend → NumEcoEval call chain.
- Alerting on health, DB connections, and Blob errors.
- Prefer Azure-native, low-integration-cost tooling.

## Considered Options

### Option 1: Azure Monitor — Log Analytics workspace + Application Insights

ACA streams container/console logs and platform metrics to a Log Analytics workspace;
Application Insights collects backend telemetry/traces and powers dashboards/alerts.

**Pros**:
- Native ACA integration (Log Analytics is the default environment log sink); minimal wiring.
- App Insights captures distributed traces, dependencies, and `/actuator`-style health; KQL
  queries, dashboards, and metric alerts in one place.
- No third-party data egress or extra service to operate.

**Cons**:
- Ingestion/retention cost scales with log volume — needs sampling/retention tuning.
- Azure-specific query language (KQL) and tooling.

### Option 2: Self-hosted stack (Prometheus + Grafana + Loki/ELK)

Run the observability stack as additional containers.

**Pros**:
- Vendor-neutral, portable dashboards and alerts.

**Cons**:
- More containers to operate and secure — contradicts the "managed services" goal; still need
  a sink for ACA's required platform logs.

### Option 3: Third-party SaaS APM (Datadog, New Relic, …)

**Pros**:
- Rich APM features out of the box.

**Cons**:
- Additional cost and a data-egress/contract dependency; ACA still needs its own log sink.
  Not justified for this scope.

## Decision Outcome

**Chosen option**: Option 1 — Log Analytics + Application Insights — because Log Analytics is
the native (and required) sink for the ACA environment, and Application Insights adds backend
tracing and health/metrics with negligible integration effort, keeping everything Azure-native
and managed. We add alerts on health, DB connections, and Blob errors.

## Consequences

### Positive

- One managed, Azure-native place for logs, metrics, traces, dashboards, and alerts.
- Satisfies ACA's mandatory log-destination requirement with no extra components.

### Negative

- Log ingestion/retention cost grows with volume; KQL/Azure-specific tooling.

### Risks

- Unbounded log volume inflates cost — *mitigation*: set retention and sampling, and scope
  verbose logs to non-prod.

## References

- `docs/azure-deployment-plan.md` §3, §8 (scaling, resilience, observability)
- Backend Spring Boot `/actuator`
- Related: [ADR-001](001-container-hosting-azure-container-apps.md),
  [ADR-003](003-relational-database-postgresql-flexible-server.md)
