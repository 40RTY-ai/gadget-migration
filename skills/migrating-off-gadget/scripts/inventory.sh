#!/usr/bin/env bash
# Count the Gadget surface a repo actually uses, so the port only builds what is used.
# Usage: inventory.sh [repo-dir]   (default: .)   Needs: git or grep, plain bash.
set -euo pipefail
cd "${1:-.}"

files() { git ls-files 2>/dev/null || find . -type f -not -path './node_modules/*' -not -path './.gadget/*'; }
SRC=$(files | grep -E '\.(ts|tsx|js|jsx|mjs|gelly)$' | grep -vE '(^|/)(node_modules|\.gadget|dist|build)/' | grep -vE '\.(test|spec)\.' || true)
[ -z "$SRC" ] && { echo "no source files found"; exit 1; }

count() { # label, extended regex
  local n; n=$(printf '%s\n' "$SRC" | { xargs grep -lE "$2" 2>/dev/null || true; } | wc -l | tr -d ' ')
  printf '%-44s %5s files\n' "$1" "$n"
}

echo "== imports"
count "gadget-server"                       "from ['\"]gadget-server['\"]"
count "gadget-server/shopify"               "from ['\"]gadget-server/shopify['\"]"
count "gadget-server/remix"                 "from ['\"]gadget-server/remix['\"]"
count "@gadget-client/*"                    "from ['\"]@gadget-client/"
count "@gadgetinc/react"                    "from ['\"]@gadgetinc/react['\"]"
count "@gadgetinc/react-shopify-app-bridge" "from ['\"]@gadgetinc/react-shopify-app-bridge['\"]"
echo "== runtime helpers"
for f in applyParams save deleteRecord preventCrossShopDataAccess assert finishBulkOperation shopifySync abortSync globalShopifySync transitionState; do
  count "$f(" "\\b$f\\("
done
count "ActionRun/ActionOnSuccess (ambient ok)" ":\s*Action(Run|OnSuccess)\b"
echo "== data client"
for m in findMany findFirst maybeFindFirst findOne maybeFindOne create update delete deleteMany bulkCreate bulkUpdate; do
  count "api.<model>.$m" "api\.(internal\.|actAsSession\.)?[a-zA-Z]+\.$m\("
done
count "api.internal.*"                      "api\.internal\."
count "api.actAsSession.*"                  "api\.actAsSession\."
count "api.enqueue"                         "api\.enqueue\("
count "api.view (Gelly)"                    "api\.view\("
count "search: (full-text)"                 "\bsearch:\s"
count "live: true"                          "live:\s*true"
echo "== context keys"
for k in connections session trigger emails currentAppUrl config request reply; do
  count "ctx.$k" "[{,]\s*$k\s*[,}]|\.$k\."
done
count "trigger.type branch"                 "trigger\??\.type"
count "trigger.payload"                     "trigger\??\.payload"
count "connections.shopify.forShopId"       "shopify\.forShopId\("
count "connections.shopify.current"         "shopify\.current\b"
count ".rest( (REST Admin API)"             "\.rest\("
echo "== platform config"
count "triggers.scheduler (crons)"          "scheduler:\s*\["
count "triggers.shopify includeFields"      "includeFields"
count "timeoutMS"                           "timeoutMS"
count "GADGET_* env reads"                  "process\.env\.GADGET_"
echo "== models / access control"
printf '%-44s %5s\n' "schema.gadget.ts models" "$(files | grep -c 'schema\.gadget\.ts$' || true)"
printf '%-44s %5s\n' "gelly tenancy filters" "$(files | grep -c '\.gelly$' || true)"
printf '%-44s %5s\n' "route files (api/routes)" "$(files | grep -cE '^api/routes/.*\.(ts|js)$' || true)"
printf '%-44s %5s\n' "action files" "$(files | grep -cE '^api/(models/[^/]+/)?actions/.*\.(ts|js)$' || true)"
[ -f settings.gadget.ts ] && { echo "== settings.gadget.ts (enabled Shopify models + scopes)"; grep -nE 'enabledModels|scopes|apiVersion|type:' settings.gadget.ts | head -20; }
