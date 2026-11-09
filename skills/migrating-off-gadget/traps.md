# Traps: symptom → cause → fix

Every row hit production during a real Gadget → GCP move. Provider-specific names are in brackets; the trap is generic.

## Data engine

| Symptom | Cause | Fix |
|---|---|---|
| Every list renders empty | client expected one pagination shape (`edges`), server sent another | contract test: real client against real server |
| Code comparing relations breaks | Gadget returns a relation as bare id, port returns `{ id }` | match Gadget's shape, or compare `x?.id ?? x` |
| Pages take 10 s+ | engine ran `SELECT *` despite `select`; no index on reference columns | project only selected columns; index every `*_id` column at schema creation |
| "Newest first" shows 9 above 78 | ids stored as text sort lexically | order by `(length(id), id)` + matching index; new ids longer than Gadget's so they sort newest |
| FK violation (`23503`) on copy | tables copied alphabetically, children before parents | copy in FK order; reconciler deletes children of parents Gadget deleted |
| DB at 99% CPU, 504s for every merchant | a reader capped at N rows reconciled the **partial** result and re-created the rest every run (2M duplicate rows) | throw past the cap, never act on a partial read; purge duplicates in batches |
| System writes refused ("not allowed to update…") | internal writes went through the public action's permission path | use `api.internal` for system writes |
| Reads that "work on Gadget" throw | read names no shop; Gadget resolved it implicitly | require explicit `shopId`; bind connections to the caller's shop |
| Full-text `search:` differs | Gadget's search index is its own; internal-API search returned [] on Gadget prod | Postgres `tsvector`/trigram; test against real queries |
| Pool timeouts under bursts | pool 10 vs 80 concurrent requests per instance | pool ≥ requests per instance, or lower per-instance concurrency |

## Jobs and cron

| Symptom | Cause | Fix |
|---|---|---|
| Merchant-facing job never dispatches | long fleet-wide jobs (13 min each × 400 stores) took every slot of the high queue | separate low-priority lane for fleet jobs; per-store lanes as their own queues |
| 25k-task backlog | fan-out timed out, retried, enqueued all N again (no dedupe id) | one job per page of 250, dedupe ids, coalesce repeats per item in a 30 s window |
| Job killed mid-run | runtime request timeout < queue dispatch deadline [Cloud Run vs Cloud Tasks 1800 s] | set equal; test it in CI |
| ~7% dispatches bounced | push queue can't see lane limits; runner answers 429 | accept it, or use a Postgres queue that claims around full lanes |
| A job never runs in prod | dev and prod share one Redis; dev took prod's locks | prefix every cache/lock key with the service/env name |
| OOM on a big store's sync | buffered a whole bulk JSONL in memory | stream it; raise memory; cap per pass and continue in a follow-up job |
| Logs from background passes missing | some in-process logs never reach the log sink | prove a job ran by reading rows, not by absence of a log |

## Deploy and environments

| Symptom | Cause | Fix |
|---|---|---|
| Revision runs wrong code | CI and a parallel session raced deploys | compare the revision's image digest with what you built |
| Hotfix shipped 100-commit-old code | deploy kept a stale `commit` label; hotfix built on it | CI stamps commit + `BUILD_SHA` on every deploy; branch hotfixes from main |
| Unmerged hotfix vanished | next main deploy replaced it | rebase hotfix onto the serving commit; merge it fast |
| Green deploy, nothing shipped | CI coalesced runs onto a newer commit whose gate failed | verify the live route, not the run colour |
| Pinned branch revision later gets no traffic | `deploy --no-traffic --tag` freezes traffic on the old revision | follow with `update-traffic --to-latest` |
| IaC plan wants to shrink prod | prod hand-tuned past IaC | never apply wholesale; PR the IaC, set the value live, reconcile separately |
| Bridge routes 404 on Gadget prod | an unanchored `gcp/` pattern in Gadget's `.ignore` also dropped `api/routes/internal/gcp/` | anchor ignore patterns (`/gcp/`); test the ignore file |
| Can't reach private DB from laptop | private-IP-only Postgres | run a one-off job with the app's image in the VPC, inside `begin read only; … rollback;` |
| Service-to-service call 401 | app reads every `Authorization: Bearer` as a Shopify session token | separate header or path for cloud identity tokens |

## Shopify and behaviour parity

| Symptom | Cause | Fix |
|---|---|---|
| Emails/side-effects silently stop | a Gadget model action with logic is skipped by the new webhook/sync path | trigger-parity test: every action with logic has a caller |
| Third-party call 401 only on new home | secret copied stale or wrong | system page probes each provider key; diff env names old vs new |
| Feature silently off | an env var present on Gadget absent on new home (e.g. a Slack webhook) | env-name diff in CI before each wave |
| Analytics fail for moved stores only | new Shopify client dropped the API-version pin | pass `apiVersion` explicitly |
| Every job refused for a moved store | install `state` not copied | copy it; jobs gate on it |
| No webhooks reach prod | Shopify lacked publish rights on the event-bus topic | grant Shopify's publisher principal; alert on 0 webhooks/hour |
| Webhook volume/cost jumps | new subscriptions lack `includeFields`/filter | reproduce Gadget's subscription shape; `ensure-webhooks` fixes drift |
| A shop's rows survive `shop/redact` | redaction table list hard-coded | enumerate `shop_id` tables from the catalog |
| Store moves fail 401/402/403/404 | dead token, frozen or unpaid shop | mark `skipped`, leave on Gadget, recheck later |
| Store count wrong | counted by `uninstalledAt` (empty for old uninstalls) | count by install state |
| Cross-store/market tables have no home | aggregates belong to no single store | keep them on Gadget and read both until the last wave, then move the job |
