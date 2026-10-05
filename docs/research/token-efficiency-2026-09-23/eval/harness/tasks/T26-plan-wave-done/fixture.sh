#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — held-out (2026-10-04). Both W2 commits (schema + backfill) are on main
# and pushed, but PLAN.md still shows W2 in progress with its expanded file:line steps. The ask is to
# update the plan: W2 done with its real hashes, compacted (learnings + commits), Phase 0 updated, the
# W2 "Why:" rationale and W3 kept.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
mkdir -p "$FX/db"
cat > "$FX/PLAN.md" <<'EOF'
# Search plan

Scope (frozen): full-text search — tokenizer (W1), index table + backfill (W2), query endpoint (W3).

## Phase 0 — Orchestration

| Wave | What | Locus | Status |
|---|---|---|---|
| W1 | tokenizer | S (dispatched session) | done |
| W2 | index table + backfill | S (dispatched session) | in progress |
| W3 | query endpoint | S (dispatched session) | not started |

## W1 — Tokenizer (DONE 2026-09-03)

**Learnings:** lowercase before stemming; stemming first split "Running" and "running".
**Commits:** `5e4d3c2` (tokenizer).

## W2 — Index table + backfill (IN PROGRESS)

1. `db/001_index.sql:1-12` — `search_index(doc_id, term, freq)` with a primary key on (term, doc_id).
2. `db/backfill.sh:1-20` — tokenize every existing doc in batches of 500 and insert its terms.
3. Run the backfill once against staging and compare row counts with `docs`.
- Why: the query endpoint (W3) cannot rank without per-term frequencies, and scanning docs per query took 4 s at 50k docs.

## W3 — Query endpoint (NOT STARTED)

- `GET /search?q=` returns the top 20 doc ids by summed term frequency.
EOF
printf '#!/bin/bash\n# tokenize.sh — lowercase, split on non-letters, one term per line.\ntr "[:upper:]" "[:lower:]" | tr -cs "[:alpha:]" "\\n"\n' > "$FX/tokenize.sh"
chmod +x "$FX/tokenize.sh"
fx_commit "feat(w1): tokenizer" "2026-09-03T11:00:00Z"; fx_origin
printf -- '-- 001_index.sql — per-term frequencies for search (W2).\nCREATE TABLE search_index (\n  doc_id INTEGER NOT NULL,\n  term TEXT NOT NULL,\n  freq INTEGER NOT NULL,\n  PRIMARY KEY (term, doc_id)\n);\n' > "$FX/db/001_index.sql"
fx_commit "feat(w2): search_index table" "2026-09-15T10:00:00Z"
printf '#!/bin/bash\n# backfill.sh — tokenize every doc in batches of 500 and insert its terms (W2).\necho "backfill: 0 docs"\n' > "$FX/db/backfill.sh"
chmod +x "$FX/db/backfill.sh"
fx_commit "feat(w2): backfill existing docs in batches of 500" "2026-09-17T16:00:00Z"
git -C "${FX:?}" push -q origin main
