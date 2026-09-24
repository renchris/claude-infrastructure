#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — a plan whose W2 section is still marked IN PROGRESS although the
# W2 commit is on main (pushed). The ask is to record the landing in the plan.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
mkdir -p "$FX/src"
cat > "$FX/PLAN.md" <<'EOF'
# API hardening plan

Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3).

## Phase 0 — Orchestration

| Wave | What | Locus | Status |
|---|---|---|---|
| W1 | request logging | S (dispatched session) | done |
| W2 | rate limiter middleware | S (dispatched session) | in progress |
| W3 | structured error bodies | S (dispatched session) | not started |

**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).

## W1 — Request logging (DONE 2026-09-05)

**Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).

## W2 — Rate limiter middleware (IN PROGRESS)

- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
- Over the limit returns HTTP 429 with a `Retry-After` header.
- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.

## W3 — Structured error bodies (NOT STARTED)

- Every error returns `{"error": {"code": ..., "message": ...}}`.
- Start with the limiter's 429, then 400/401/404.
EOF
printf '#!/bin/bash\n# logger.sh — request logging (W1)\necho "log: $*"\n' > "$FX/src/logger.sh"
fx_commit "feat(w1): request logging" "2026-09-05T10:00:00Z"; fx_origin
cat > "$FX/src/limiter.sh" <<'EOF'
#!/bin/bash
# limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N".
state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir"
f="$state_dir/$1"; now=$(date +%s)
read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; }
tokens=$(( tokens + (now - last) )); [ $tokens -gt 10 ] && tokens=10
if [ $tokens -lt 1 ]; then echo "429 Retry-After: 1"; echo "$tokens $now" > "$f"; exit 1; fi
echo "$((tokens - 1)) $now" > "$f"; echo ok
EOF
chmod +x "$FX/src/limiter.sh"
fx_commit "feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)" "2026-09-12T15:00:00Z"
git -C "${FX:?}" push -q origin main
