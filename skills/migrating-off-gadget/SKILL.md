---
name: migrating-off-gadget
description: Use when moving a Gadget (gadget.dev) app, usually a Shopify app, off Gadget onto your own cloud (GCP, AWS, Azure, Fly, Railway or any container + Postgres host), planning that move, cutting stores over, or debugging something that worked on Gadget but breaks on the new home
---

# Migrating off Gadget

## Overview

Proven on a production Shopify app moved from Gadget to GCP with zero lost stores. **Core principle: change where the code runs, never what it does.** Keep the
app's source unchanged, give it a stand-in for every Gadget package, and move **one store at a time** with a one-click
way back. Cloud products are slots: pick yours in `providers.md`.

The plan that looks obvious, a per-model ladder (dual-write → shadow-read → flip each model) with an outbox and a
reconciler, was designed and dropped. Gadget's DB is closed (no CDC, no replica), so per-model dual-write doubles
every write path for months. Per-store moves need one bridge and one copy routine.

## The phases (each leaves the app fully working)

| # | Phase | Exit gate |
|---|---|---|
| 0 | **Inventory + prune.** `scripts/inventory.sh` → build only what is used. Drop unused Shopify models from Gadget first (smaller surface, smaller bill). Add a ratchet test that caps direct Gadget calls at today's count and only goes down. | counts recorded; ratchet in CI |
| 1 | **Landing zone** in IaC: runtime, private Postgres with PITR **on**, queues, cron, secrets, KMS, keyless CI deploy. | hello-world deploys from CI with no key file |
| 2 | **Stand-ins by alias**, never by editing app code: `gadget-server`, `gadget-server/shopify`, `@gadget-client/<app>`, `@gadgetinc/react*` resolve to your modules (one alias map for the bundler, test runner and a Node `--import` resolve hook). One data engine behind both `api.*` in server code and the browser client (`POST /api/rpc`). **Tenancy in the engine**, not at call sites. Semantics: `surface-inventory.md`. | existing test suite green against the stand-ins; cross-shop tenancy tests pass; every route/action file loads (load map) |
| 3 | **Schema + jobs.** The engine is generic (a registry parsed from `schema.gadget.ts` drives filters, validations, relations); the SQL migrations are generated from the same files once, then owned by you. Gadget ids kept verbatim as PKs, an index on every reference column. Queue lanes and crons reproduced (`traps.md` → jobs). | queue-parity check vs Gadget's background-action semantics |
| 4 | **Bridge** on the Gadget side: authenticated internal routes for shop row, Shopify GraphQL proxy, row export (`updatedSince`, `idsOnly`, counts), token read/park/set, billing status. This is your only change capture. | bridge contract tests; dev env round-trip |
| 5 | **Front door.** New app URL proxies every request for a store not yet moved to Gadget unchanged; repoint the Shopify app URL while it is a pure pass-through. New installs land on the new home. | real install on new home; unmoved stores see no change |
| 6 | **Store moves.** Warm copy (parents before children; a resumable job under a lease, prewarmed ahead of the wave) → count check → write pause of a few seconds while the last `updatedSince` delta lands → token hand-off (`shopify-takeover.md`) → webhooks + Shopify sync on the new home → flip the store's home flag. Each store's jobs run on exactly one side. | one test store round-trips both ways in production |
| 7 | **Waves.** A move queue: small/free/restricted stores first, paying and big catalogs later, VIPs by hand. Concurrency ~6; pause on >3 failures or >10%. Stores Shopify refuses (401/402/403/404) stay `skipped`, rechecked later. | each wave 0 failures or explained |
| 8 | **Decommission.** Remove the proxy, kill-switch the bridge (`GADGET_OFF` answers locally), delete `*.gadget.app` webhook subscriptions, convert any non-expiring tokens. Leave the Gadget env idle ~1 week as a cold backup, check big stores' row counts, then delete it. | 0 outbound Gadget calls for a full day |

Keep this design doc up front; write each phase's detailed plan only when that phase starts.

## Parity checks to build (they caught most bugs)

- **Load map:** every route and action file imports and answers on the new runtime.
- **Client contract test** against the real server (pagination shape, relation shape `{id}` vs bare id).
- **Trigger parity:** fails when a Gadget model action with logic (webhook/sync/install-triggered) has no caller on the new side.
- **Shadow first:** new data paths run in `shadow` (compute both, log diffs) before `on`; keep an hourly re-check after.
- **System page:** probes each provider key and secret; diffs env names between old and new.

## Red flags — stop

- Editing `api/**` or `web/**` to make it run on the new home → write a stand-in instead.
- Both sides renewing one store's Shopify token, or both running its jobs → one owner, always.
- A store "moved" because a row for it exists on the new side → home is an explicit flag set by the move.
- Running anything on real merchant stores before your own test store round-trips in production.
- Deleting Gadget data before the decommission soak.

## Reference files

- `surface-inventory.md` — every Gadget behaviour a port must reproduce, with exact semantics.
- `shopify-takeover.md` — tokens, webhooks, sync, billing, GDPR, install/uninstall.
- `traps.md` — symptom → cause → fix for ~40 bugs that hit in production.
- `providers.md` — capability slots mapped to GCP / AWS / Azure / small hosts.
- `scripts/inventory.sh <repo>` — counts the Gadget surface the repo uses.
