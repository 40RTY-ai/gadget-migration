# gadget-migration

Site: https://40rty-ai.github.io/gadget-migration/

A Claude Code skill for moving a [Gadget](https://gadget.dev) app (usually a Shopify app) onto your own cloud:
GCP, AWS, Azure, or any container + Postgres host. Distilled from a production migration of a Shopify app
(~800 stores) from Gadget to Google Cloud, Oct–Nov 2026.

## Install

```
/plugin marketplace add 40RTY-ai/gadget-migration
/plugin install gadget-migration@gadget-migration
```

Or copy `skills/migrating-off-gadget/` into `~/.claude/skills/` (personal) or `.claude/skills/` (one project).

## Use

Ask Claude to plan or run a migration off Gadget; the skill loads on its own. Start with the inventory:

```
skills/migrating-off-gadget/scripts/inventory.sh path/to/your-gadget-app
```

## What's inside

| File | For |
|---|---|
| `SKILL.md` | the approach, 9 phases with exit gates, parity checks, red flags |
| `surface-inventory.md` | every Gadget behaviour a port must reproduce |
| `shopify-takeover.md` | tokens, webhooks, sync, billing, GDPR |
| `traps.md` | ~40 production bugs as symptom → cause → fix |
| `providers.md` | capability slots → GCP / AWS / Azure / small hosts |
