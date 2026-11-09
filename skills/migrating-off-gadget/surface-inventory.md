# What Gadget does for you (and you must now do)

Run `scripts/inventory.sh <repo>` first; it counts each of these in your code. Anything at 0 you skip. Anything >0 needs
a stand-in with the **same semantics** — the left column is what bites when you get it slightly wrong.

## Server runtime (`gadget-server`, `gadget-server/shopify`)

| Surface | Real semantics to reproduce |
|---|---|
| `applyParams(params, record)` | `Object.assign(record, params[model])`; belongsTo objects become `record.<field>Id = obj._link ?? obj.id` |
| `save(record)` | needs ambient context (AsyncLocalStorage); runs field validations (required, unique incl. shop-scoped, regex, enum, length); create if no `createdAt`, else update **only dirty fields**; merges DB row back; flushes change tracking |
| `deleteRecord(record)` | `api.internal.<model>.delete(id)`; no hooks |
| `preventCrossShopDataAccess` | new record → stamp `shopId` from session; existing → throw if `shopId` ≠ session shop; no-op without shop tenancy |
| `record.changed(f)` / `changes()` | per-field dirty tracking; `onSuccess` code reads it |
| Action context | `{ api, logger, params, record, connections, session, trigger, request, reply, emails, config, currentAppUrl }` |
| `trigger.type` | `api`, `shopify_webhook`, `shopify_sync`, `shopify_webhook_reconciliation`, `background`, `scheduler`; code branches on it |
| `trigger.payload` | raw webhook body (params only holds mapped fields) |
| `options.timeoutMS`, `returnType`, `triggers` | per-action timeout; `triggers.scheduler` = crons; `triggers.shopify.{includeFields, shopifyFilter}` = webhook subscription shape |
| `ActionRun` / `ActionOnSuccess` | often used as **ambient globals** with no import — declare them globally |
| `logger` | pino-style `(obj, msg)`; Gadget logs an `error` key as `[object Object]` |

## Data client (`api.<model>.*`)

- Methods: `findMany`, `findFirst` (throws), `maybeFindFirst`, `findOne` (throws), `maybeFindOne`, `create`, `update`, `delete`,
  `deleteMany`, `bulkCreate`, `bulkUpdate`, custom model actions, global actions as `api.<name>(...)`.
- Query DSL: `filter` (`equals`, `in`, `notEquals`, `isSet`, `greaterThan…`, `AND`/`OR`/`NOT`, relation filters `shop:{id:{equals}}`),
  `sort`, `select` (nested, incl. relations), `first`/`after` cursors, `search`, `pageInfo.hasNextPage/endCursor`, `nextPage()`.
- `api.internal.*` bypasses permissions **and action logic**; `api.actAsSession` enforces them.
- `api.enqueue(action, params, {queue:{name,maxConcurrency}, priority, id, onDuplicateID, startAt, retries})`.
- `api.view(gelly)` / Gelly aggregates → replace with plain SQL.
- Ids are **numeric strings**. Relations come back as a bare id on Gadget; a naive port returns `{ id }`.

## Access control

- `accessControl/filters/**/*.gelly` (`where shopId == $session.shopId`) → one row filter **in the data engine**, not at call sites.
- `permissions.gadget.ts` roles (`shopify-app-users`, `unauthenticated`, custom) → role check on the action invoker.

## Frontend

- `@gadget-client/<app>` → a client over one RPC endpoint (`POST /api/rpc`) calling the same engine.
- `@gadgetinc/react` (`useFindMany`, `useFindOne`, `useAction`, `useGlobalAction`, `useFetch`; `live: true` → short polling or SSE).
- `@gadgetinc/react-shopify-app-bridge` (`Provider`, `useGadget`) → App Bridge session-token fetch + your own provider.
- `gadget-server/remix` error boundaries; Vite plugin config.

## Platform behaviour (no import — easiest to miss)

- Shopify OAuth install / reinstall / uninstall → `shopifyShop.install|reinstall|uninstall` actions.
- Token storage + renewal of **expiring offline tokens** (hourly access, single-use refresh).
- Webhook registration per enabled model, HMAC verify, payload → model `create/update/delete` action with `trigger.payload`.
- Webhook reconciliation (re-fetch missed changes) and the **Shopify sync engine** (`shopifySync.run/complete/error`).
- Bulk-operation webhooks → `shopifyBulkOperation.complete/fail/expire/cancel`.
- GDPR topics → `shopifyGdprRequest`; `shop/redact` must delete every shop-owned row.
- Billing: `appSubscriptionCreate` confirmation, `app_subscriptions/update` → subscription row.
- Session model + cookie for the embedded app; `connections.shopify.current*` resolved from the session token.
- Rate limiting (`GGT_TOO_MANY_REQUESTS`), per-action timeouts, background-action retries, the hosted log viewer.
- Env vars: `GADGET_ENV`, `GADGET_APP_URL`, `GADGET_PUBLIC_*` — code reads them; set equivalents.
