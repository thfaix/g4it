# Proposed fix: Liquibase greenfield ordering bug (`ref_item_impact`)

**For:** G4IT backend team
**Status:** Proposal — surfaced during the Azure containerized deployment (fresh database)
**Severity:** Blocks backend startup on any **greenfield** (empty) database

## Symptom

On a brand-new database the backend fails to start; Liquibase aborts with:

```
liquibase.exception.DatabaseException: ERROR: relation "public.ref_item_impact" does not exist
  [Failed SQL: (0) ALTER TABLE public.ref_item_impact ADD is_hidden BOOLEAN DEFAULT TRUE]
Caused by: org.postgresql.util.PSQLException: ERROR: relation "public.ref_item_impact" does not exist
```

Spring Boot then exits (Liquibase runs at startup via `SpringLiquibase`), so the container never becomes healthy.

## Root cause: include order vs. create/alter order

The `is_hidden` column is **added by an ALTER** that runs **before** the table is **created**:

| Master include position | Changelog file | Relevant changeset | Operation on `ref_item_impact` |
|---|---|---|---|
| **7** | `greenitdb.changelog-security-multi-orga.yml` | `add-hide-reference-values` | `ALTER TABLE … ADD is_hidden` (no precondition) |
| **12** | `greenitdb.changelog-referential-initialization.yml` | `create-ref_item_impact` | `CREATE TABLE ref_item_impact …` |

(positions per `greenitdb.changelog-master.yml`)

Liquibase executes changesets in master-include order. On a **greenfield** database the ALTER (position 7) runs before the CREATE (position 12) → the table does not exist yet → failure.

This is **greenfield-only**. Existing/brownfield databases already contain `ref_item_impact` (it was created earlier in their history), so the ALTER succeeds there — which is why this has gone unnoticed in long-lived environments and only appears on a fresh deploy.

Note: `create-ref_item_impact` creates the table **without** `is_hidden` (the column is contributed solely by `add-hide-reference-values`). So the fix cannot be "skip the ALTER on greenfield" — that would leave the column missing. The table must simply be **created before it is altered**.

## Recommended fix: reorder the master include

Move `greenitdb.changelog-referential-initialization.yml` so it is included **before** `greenitdb.changelog-security-multi-orga.yml` in `greenitdb.changelog-master.yml`:

```diff
   - include:
       file: db/changelog/greenitdb.changelog-digital-service-initialization.yml
+  - include:
+      file: db/changelog/greenitdb.changelog-referential-initialization.yml
   - include:
       file: db/changelog/greenitdb.changelog-security-multi-orga.yml
   - include:
       file: db/changelog/greenitdb.changelog-security-user-after.yml
@@ (further down, remove the original, now-duplicate include) @@
   - include:
       file: db/changelog/greenitdb.changelog-shedlock.yml
-  - include:
-      file: db/changelog/greenitdb.changelog-referential-initialization.yml
   - include:
       file: db/changelog/greenitdb.changelog-task-initialization.yml
```

### Why this is safe for existing databases

Liquibase identifies a changeset by **`id` + `author` + changelog file path** — *not* by position. Reordering the `include` entries:

- **does not change any changeset's checksum** (no changeset content is edited), and
- for brownfield databases, every already-applied changeset is still recognized and **skipped** regardless of the new order.

So existing environments re-run nothing; only the *new* execution order on greenfield changes — which is exactly what we want. This also respects the repo rule *"Add schema changes as new changelog files — do not edit applied ones"*: we are **not editing any applied changeset**, only reordering includes.

### Verification before merging

1. Confirm `greenitdb.changelog-referential-initialization.yml` has **no changeset that references objects created in positions 7–11** (`security-multi-orga`, `security-user-after`, `business-hours`, `digital-service-next`, `shedlock`). The referential changelog creates standalone `ref_*` tables and loads CSV data, so this is expected to be clean — but confirm.
2. Run a full **fresh-database** migration (drop schema → start the app, or `liquibase update` against an empty DB) and confirm it completes and `ref_item_impact` has `is_hidden`.
3. Run against a **copy of an existing** database to confirm no changeset re-runs and no checksum warnings appear.

## Alternative (only if reordering surfaces a real dependency)

If `referential-initialization` turns out to depend on something between positions 7–11, do **not** edit the applied `add-hide-reference-values` changeset (checksum break). Instead add a **new** changeset, included *before* `security-multi-orga`, that creates `ref_item_impact` guarded by a `not tableExists` precondition (`onFail: MARK_RAN`) with the **full current schema including `is_hidden`**, and add a `not columnExists` precondition pattern so the later ALTER no-ops on greenfield. This is more invasive than reordering and is only warranted if the simple reorder is unsafe.

## Impact on the Azure deployment

This is the sole remaining blocker for the backend on the new Azure environment (infra, frontend, and Keycloak are up). Once the changelog fix is merged, the backend image is rebuilt, and the app is redeployed, the backend should complete its migration and become healthy. Until then the backend container will crash-loop on this error on any fresh database.
