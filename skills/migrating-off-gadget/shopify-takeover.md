# Taking the Shopify connection off Gadget

The hardest part. Gadget owns OAuth, tokens, webhooks, sync and billing; do it per store, last, behind the bridge.

## Tokens (expiring offline tokens)

Shopify offline tokens are an hourly access token + a refresh token that works **once**: whoever renews retires the
other holder's pair. Two holders lock each other out. Rule: **exactly one side holds a live refresh token, and a live
pair is always stored somewhere durable.**

Take (moving a store to the new home):
1. Read Gadget's pair through the bridge; keep the new side's current pair aside.
2. Store Gadget's pair on the new side (KMS-encrypted) **before anything else changes**.
3. Gadget gives up that exact refresh token (409 = Gadget renewed since step 1 → restore, retry).
4. Renew on the new side to prove it (refused = a Gadget renewal in flight won → restore, retry).
5. Wait for any in-flight Gadget renewal; if Gadget holds a refresh token again, retry.
Every failed attempt restores the previous pair; a dead pair never overwrites a live one.

Give back (move to Gadget / failed move): renew first to prove the copy is live (never hand over a dead one) → stop
renewing → wait out in-flight renewals → hand over; on failure reclaim and stay.

Facts learned:
- A second, independent pair via token exchange does **not** invalidate the first. New installs can get their own pair
  from a session token; existing stores must hand off (you cannot mint a session token yourself: `invalid_subject_token`).
- Gadget renews on use, not on a timer; it can still renew mid-move. Self-heal: if Shopify refuses the new side's
  renewal, re-take Gadget's pair.
- Non-expiring (legacy) tokens must be converted before Shopify's deadline; dry-run first, hand back on failure, mark
  stores Shopify refuses as needing re-auth.
- Never print a token response, even in debugging; probe by status code.

## Webhooks

- Shopify allows several subscriptions per topic at different addresses: register the new home **in shadow** first.
- Carry Gadget's subscription shape: `includeFields` and `filter` from `triggers.shopify` (otherwise volume and cost jump).
- An `ensure-webhooks` routine per store: create missing, update drifted in place, and at decommission delete
  `*.gadget.app` subscriptions.
- Intake: verify HMAC, ack < 5 s, enqueue with a dedupe id (webhook id), dead-letter after N attempts.
- If using a cloud event-bus delivery (Pub/Sub, EventBridge), grant Shopify's publisher principal on the topic — missing
  grant = silently no webhooks.
- A webhook must run the **model action** Gadget would have run (`create`/`update` with `trigger.type = shopify_webhook`,
  changed fields only), not just upsert the row; `onSuccess` logic lives there.

## Shopify sync (replaces Gadget's sync engine)

- Full sync per store with Bulk Operations per model; poll by delayed re-enqueue; **stream** the JSONL (big catalogs OOM).
- Sweep rows Shopify no longer has; seed app-owned custom fields once from Gadget's copy.
- Daily incremental sync for every installed store covers missed webhooks (Gadget's reconciliation).
- Pin the Admin API version on the client; queries that need `unstable` (e.g. ShopifyQL) fail silently without it.

## Install / reinstall / uninstall

- Run `shopifyShop.create` before `install`; a returning store must run `reinstall` (an `ON CONFLICT DO NOTHING` insert skips it).
- Copy install state (`state.created`) with the shop; jobs gate on it.
- Count installed stores by state, never by `uninstalledAt` (empty for old uninstalls).

## Billing

- Moves once, per store, with the token. Test on a production store with a private $0 test plan: a dev/custom app
  cannot use the Billing API.
- `app_subscriptions/update` webhook → subscription row → plan limits; verify 0 Gadget calls.

## GDPR

- During dual-run, verify on the new home and forward compliance webhooks byte for byte; they must never 5xx.
- `shop/redact` deletes every shop-owned row: enumerate tables with a `shop_id` column from the catalog
  (`information_schema`), children first — a hard-coded list misses tables without an FK.
