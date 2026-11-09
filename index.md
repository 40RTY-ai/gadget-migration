---
title: Migrating off Gadget
---

# Migrating off Gadget

A Claude Code skill that moves a [Gadget](https://gadget.dev) Shopify app onto your own cloud: **GCP, AWS, Azure**,
or any host that runs containers and Postgres. We built it from a real production move: a Shopify app with about
800 stores and 62 models went from Gadget to Google Cloud in October–November 2026. No store was lost and there was
no downtime.

## The idea in one line

**Change where the code runs, never what it does.** The app's source stays unchanged. Each Gadget package is
replaced by a stand-in. Stores move **one at a time**, and each move can be undone with one click.

The plan that looks obvious is to dual-write each model and flip models one by one. It falls apart on Gadget,
because the database is closed: no change feed and no replica. Moving store by store needs only one bridge and one
copy routine.

## How the move goes

| # | Phase | Done when |
|---|---|---|
| 0 | Inventory the Gadget features you use and prune the unused ones | counts recorded; a CI ratchet caps new Gadget calls |
| 1 | Landing zone in Terraform (runtime, private Postgres with PITR, queues, cron, secrets, KMS) | keyless deploy from CI works |
| 2 | Stand-ins by import alias, with one data engine that enforces tenancy | the existing test suite passes on the stand-ins |
| 3 | Schema with Gadget ids kept as keys, an index on every reference column, queue lanes and crons | queue parity matches Gadget |
| 4 | Bridge routes on the Gadget side: shop, GraphQL proxy, row export, token hand-off, billing | contract tests pass |
| 5 | Front door: proxies every store not yet moved to Gadget, and new installs land on the new home | a real install works on the new home |
| 6 | Store move: copy, then count, pause, hand off the token, move webhooks and sync, flip the flag | a test store round-trips in production |
| 7 | Waves: small stores first, ~6 at a time, auto-pause on failures | each wave has 0 failures, or each failure is explained |
| 8 | Decommission: kill-switch the bridge, delete Gadget webhooks, a cold-backup week, then delete | 0 outbound Gadget calls for a day |

## Pick your cloud

| Need | GCP | AWS | Azure | Small hosts |
|---|---|---|---|---|
| Runtime | Cloud Run | ECS Fargate / App Runner | Container Apps | Fly, Railway, Render |
| Postgres | Cloud SQL | RDS / Aurora | Flexible Server | Neon, Supabase |
| Jobs | Cloud Tasks | SQS + EventBridge | Service Bus | Postgres queue |
| Cron | Cloud Scheduler | EventBridge Scheduler | Container Apps Jobs | in-app scheduler |
| Secrets / KMS | Secret Manager / KMS | Secrets Manager / KMS | Key Vault | Doppler + libsodium |

## What the skill contains

- **Surface inventory:** each Gadget behaviour a port has to reproduce, down to exact details such as
  `save()` writing only dirty fields.
- **Shopify takeover:** handing over single-use refresh tokens with no lockout; moving webhooks, sync, billing
  and GDPR.
- **Traps:** about 40 bugs that hit production, written as symptom → cause → fix. Examples: a fleet job starving the
  merchant queue, a partial read that re-created 2M rows, dev taking prod's Redis locks.
- **`inventory.sh`:** counts the Gadget features your repo actually uses.

## Install

```
/plugin marketplace add 40RTY-ai/gadget-migration
/plugin install gadget-migration@gadget-migration
```

Then ask Claude to plan your migration off Gadget. Or copy `skills/migrating-off-gadget/` into `~/.claude/skills/`.

[Source on GitHub](https://github.com/40RTY-ai/gadget-migration) · MIT licensed
