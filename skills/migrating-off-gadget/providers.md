# Capability slots → provider

The playbook names **slots**, never products. Pick one column, fill the slots, and every other file in this skill
applies unchanged. The GCP column is what was actually run in production; the others are the equivalent service.

| Slot | What it must do | GCP (proven) | AWS | Azure | Small / self-host |
|---|---|---|---|---|---|
| **Container runtime** | Run one image as web + worker, scale 1..N, min instances ≥1 (no cold start on Shopify's 5 s webhook budget), per-request timeout ≥ your longest action | Cloud Run (CPU always on, min 2) | ECS Fargate / App Runner | Container Apps | Fly.io, Railway, Render, k8s |
| **Postgres** | Managed PG with PITR **before** real data lands, private network only | Cloud SQL (private IP) | RDS / Aurora PG | Flexible Server | Neon, Supabase, Crunchy |
| **Job queue** | HTTP push or pull, per-task delay (`startAt`), named/deduped tasks, retries with backoff, ≥3 priority queues | Cloud Tasks (high/default/low/bulk) | SQS (+ delay) or EventBridge Scheduler one-shots | Service Bus / Storage Queues | Postgres queue (`SKIP LOCKED`, pg-boss, graphile-worker) |
| **Cron** | Fire N schedules (UTC) at an authenticated internal endpoint | Cloud Scheduler (OIDC) | EventBridge Scheduler | Container Apps Jobs / Logic Apps | in-process scheduler under a DB lease |
| **Secrets** | Versioned values, read at boot, no trailing newline | Secret Manager | Secrets Manager / SSM | Key Vault | Doppler, 1Password, Infisical |
| **KMS** | Envelope-encrypt Shopify tokens at rest | Cloud KMS | KMS | Key Vault keys | libsodium + one sealed root key |
| **Cache / locks** | Short-lived locks + cache; **keys namespaced per environment** | Memorystore Redis | ElastiCache | Azure Cache for Redis | Upstash, or PG advisory locks |
| **Webhook intake** | Public HTTPS, HMAC verify, ack < 5 s, hand off to queue | Cloud Run route (or Pub/Sub topic via Shopify's GCP delivery) | ALB route (or EventBridge partner source) | Front Door route (or Event Grid) | same app route |
| **Staff/admin gate** | Identity-aware proxy in front of internal pages | IAP on global LB | ALB + Cognito / Verified Access | Front Door + Entra | Cloudflare Access, Tailscale |
| **CI identity** | Keyless deploy from CI | Workload Identity Federation | GitHub OIDC → IAM role | Federated credentials | deploy token |
| **One-off ops job** | Run a script/SQL inside the private network with the app's image | Cloud Run Jobs | ECS RunTask | Container Apps Job | `fly machine run`, `railway run` |
| **IaC** | Everything above in code | Terraform | Terraform / CDK | Terraform / Bicep | Terraform or the host's config file |

## Choosing

- Shopify webhooks need a warm instance: anything that scales to zero must keep `min ≥ 1`.
- If the host has no managed queue, use a Postgres queue first. It obeys per-store lanes natively (a claim can skip full lanes);
  an HTTP push queue cannot, and needs a 429 bounce from the runner (see traps.md → queue starvation).
- Per-shop lanes (`queue: {name: "shop:<id>:…", maxConcurrency}`): Postgres queue (pg-boss / graphile-worker) handles
  them directly. SQS FIFO with `MessageGroupId = <shop>:<lane>` gives concurrency 1 per lane only; for >1, use a Postgres queue.
- Delays: SQS caps `DelaySeconds` at 15 min and visibility at 12 h. For a later `startAt`, use an EventBridge Scheduler
  one-shot that enqueues at the time, or keep delayed jobs in a Postgres table polled every minute.
- Queue deadline, visibility timeout and runtime request timeout must all be ≥ the longest `timeoutMS`; test it.
- Connection pool ≥ concurrent requests per instance × instances, under the DB's max connections; use a pooler
  (RDS Proxy, PgBouncer, Cloud SQL connector) once instances × pool gets close to that limit. Drain on SIGTERM.
- Shopify event-bus delivery: GCP Pub/Sub needs `roles/pubsub.publisher` for Shopify's service account on the topic;
  AWS uses an EventBridge partner event source you associate with a bus. Both are configured in `shopify.app.toml`.
- Co-locate runtime and Postgres in one region; a private-network hop is ~1 ms, a public one turns every N+1 into seconds.
- Never share one cache/Redis between environments without a per-environment key prefix.
