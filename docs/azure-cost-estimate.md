# G4IT on Azure — Monthly Cost Estimate

**Audience:** Project stakeholders / budget owners
**Scope:** One non-production (dev) environment, region **North Europe**
**Date:** 2026-06-04
**Status:** Estimate — retail pay-as-you-go prices, no committed-use discounts applied

---

## Executive summary

Running the full G4IT platform on Azure as a **single dev environment** is estimated at:

> ### ≈ **€130 – €175 / month** under light, day-to-day use
> rising to **≈ €275 – €370 / month** during sustained calculation campaigns.

About **€50/month is fixed** (registry, database, private networking) regardless of usage; the rest scales with how heavily the platform is exercised. The dominant and most variable line is **Azure Container Apps** (the compute hosting the ~9 services).

These figures cover one environment. A production environment will cost materially more (high-availability database, larger compute, longer log retention) and should be budgeted separately — see *Production outlook*.

---

## Scope and assumptions

- **One dev environment** sized as defined in the Infrastructure-as-Code (`infra/`) and the [Azure deployment ADRs](architecture/adr/).
- **Region:** North Europe (Ireland).
- **Pricing:** approximate retail pay-as-you-go in **EUR**, as of June 2026, **±~15%**.
- **Excludes:** Azure support plans, any WAF / Front Door / CDN added later, CI image-build minutes, and committed-use discounts (Reservations / Savings Plans), which could reduce compute and database cost by 20–40% if adopted.
- The four "on-demand" calculation services **scale to zero** — they cost ≈ €0 when idle and only bill while an evaluation is running.

---

## Cost breakdown (€ / month, typical dev use)

| Azure service | Configuration | € / month | Fixed? |
|---|---|---:|:--:|
| **Container Apps** (compute) | 2.25 vCPU + 4.5 GiB always-on, plus on-demand scaling | **€75 – 100** | Partly |
| **PostgreSQL Flexible Server** | B1ms burstable, 32 GiB, no HA | **€15 – 18** | ✔ |
| **Container Registry** | Standard tier | **€18** | ✔ |
| **Private Endpoints** | 2 (Blob Storage + Key Vault) | **€14** | ✔ |
| **Log Analytics + Application Insights** | Pay-as-you-go ingestion, 30-day retention | **€5 – 14** | — |
| **Blob Storage** | Standard, locally redundant | **€1 – 3** | — |
| **Private DNS zones** | 3 zones | **€1.5** | ✔ |
| **Key Vault** | Standard | **€1** | ✔ |
| **Network egress** | Outbound data transfer | **€0 – 5** | — |
| **Virtual Network, Managed Identity** | — | **€0** | ✔ |
| **Estimated total** | | **≈ €130 – 175** | |

*Fixed baseline (registry + database + private endpoints + DNS): **≈ €50/month**, independent of traffic.*

---

## Scenarios

| Scenario | Description | € / month |
|---|---|---:|
| **Light dev** | Browsing, small inventories, occasional evaluations | **€130 – 175** |
| **Active campaigns** | Frequent / large NumEcoEval evaluations, backend scaling out, on-demand services running | **€275 – 370** |
| **Idle / paused** | Platform deployed but unused (always-on services still billed) | **≈ €110 – 130** |

The spread is almost entirely **Container Apps compute**: the always-on memory (~€43/month) is effectively fixed, while the vCPU charge is low when services sit idle and rises sharply during calculation-heavy periods.

---

## What drives the cost

1. **Always-on services (Container Apps).** Four services run 24/7 by design — the **backend**, **Keycloak** (cannot scale to zero without breaking login sessions), the **NumEcoEval referential**, and the **frontend**. Together they hold ~2.25 vCPU + 4.5 GiB continuously. This is the single largest cost and the main lever.
2. **Fixed platform services.** The container registry, managed database, and private networking total ~€50/month whether or not anyone uses the platform.
3. **Usage bursts.** The on-demand calculation services and backend auto-scaling add cost only during active evaluation runs — efficient, but spiky.

## Levers to reduce cost

- **Share one non-production environment** across the team rather than one per developer (supported by the deployment design). This is the biggest saving — it avoids multiplying the ~€130–175 baseline.
- **Container Registry: Standard → Basic** saves ~€13/month if the smaller storage/throughput is acceptable for ~9 images.
- **Adopt Reservations / Savings Plans** for the database and steady compute once usage stabilises (typically 20–40% off those lines).
- **Cap Log Analytics ingestion** (daily cap or commitment tier) if logging volume grows.

## Production outlook (rough)

A production environment is **not** covered by the figures above. Expect it to be **roughly 2–3× the dev cost** before committed-use discounts, driven by:
- High-availability (zone-redundant) database on a larger, non-burstable SKU,
- Higher minimum replica counts and quotas on Container Apps,
- Longer log retention and higher ingestion,
- Possibly a WAF / Front Door at the edge.

A firm production number should be produced once availability and performance targets are agreed.

---

## Notes

- For a binding quote, the exact SKUs above can be entered into the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).
- Source of sizing: the project's Infrastructure-as-Code (`infra/`) and the architecture decisions in `docs/architecture/adr/`.
