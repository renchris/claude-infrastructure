# Dossier 2

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches, each defaulting to on: WRAP_CACHE (line 379; off/0/no stops the memo cache from being read or written), WRAP_RESIDENT (line 1160; off skips the resident-teammate check) and WRAP_BUSY (line 2137; off skips the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment variables that act as off-switches. Each defaults to `on`.

| # | Variable | Line | Off values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. Line 379 blanks `WL_TRANSCRIPT`, and line 380 enters the cache block only when `MODE=machine` and `WL_TRANSCRIPT` is non-empty. So the cache is never read and never written. Line 276 calls this "the benchmark's control arm". The goal logic still sees the transcript, because `GOAL_TRANSCRIPT` is copied at line 285, before the blanking. |
| 2 | `WRAP_RESIDENT` | 1160 | exactly `off` | The resident-member check (`count_resident_members`, which feeds the `RESIDENT_MINE` 🔧 row). It returns early with `RESIDENT_SRC=none`, so live teammate processes are never counted. |
| 3 | `WRAP_BUSY` | 2137 | exactly `off` | The session busy/idle probe: sourcing `hooks/lib/session-busy.sh` and running `session_busy_live`. `BUSY_*` and `PERMPEND*` stay at their defaults, which means `BUSY_STATE=UNKNOWN` and `BUSY_SRC=none`. |

These variables look similar but are not kill switches:
- The `*_TIMEOUT_S` variables and `WRAP_CACHE_WAIT_*` / `WRAP_CACHE_LOCK_STALE_S` are tuning bounds.
- `WRAP_LIVE_BUDGET_*`, `WRAP_LIVE_ADDS_MAX` and `WRAP_LIVE_STALE_MAX` are thresholds.
- The `*_BIN`, `*_LIB`, `*_DIR` and `*_ROOT(S)` variables are path or test seams.
- `CC_DEPLOY_MAX_LAG_*` appears only in comments.
- `DRAIN_SCOPE` (line 942) is an internal variable, not a documented env switch.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '\"\\$\\{[A-Z_]+:-[^}]*\\}\" *(=|!=) *\"?(off|0|1|on)\"?|(= *\"?off\"?|!= *\"?off\"?)|:-on\\}|:-1\\}' $F | head -80", "description": "Search script for off-switch env vars"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -niE 'kill[ -]?switch|off-switch|disable' $F | head -60; echo ----; grep -noE '\\$\\{[A-Z_][A-Z0-9_]*:-[^}]*\\}' $F | sort -t: -k3 -u | head -150", "description": "List kill-switch comments and env defaults"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
553:  # shellcheck disable=SC1091
579:# shellcheck disable=SC1090,SC1091
699:  # shellcheck disable=SC1090,
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\boff\\b|\"0\"\\)|= *0 *\\]|:-0\\}|:-1\\}' $F | head -60; sed -n 270,285p $F; sed -n 374,382p $F; sed -n 1150,1165p $F; sed -n 2125,2150p $F", "description": "Inspect off-switch contexts"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
334:  [ "${got:-0}" -eq 1 ] || return 1
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT=
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\b(WRAP|CC)_[A-Z0-9_]+' $F | awk -F: '{print $2}' | sort | uniq -c; sed -n 383,400p $F; grep -n 'WRAP_CACHE\\b' $F", "description": "Enumerate env var references"}`
   →    6 CC_BACKLOG_BIN
   1 CC_BUSY_CUSTODY_OPEN
   2 CC_CONVICTION_EPOCH
   3 CC_CUSTODY_BIN
   1 CC_CUSTODY_DIR
   4 CC_DECIDE_BIN
   2 CC_DEPLOY_MAX_LAG_COMMITS
   3 CC_DEPLOY_MAX_LAG_HOURS
   5 CC_MIGRATIONS_STATE
   2 CC_PANE_ID
   1 CC_POSTLAND_DIR
   2 CC_SESSIONS_BIN
   4 CC_WF_PSTABLE_FILE
   
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 175,200p $F; grep -n 'CC_DEPLOY_MAX_LAG\\|WRAP_RESIDENT\\b\\|WRAP_BUSY\\b' $F", "description": "Read env seams header and deploy lag refs"}`
   → # ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   wri
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r6 && cat > /tmp/tokeff-regate/f2/out/B10-r6/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment variables that act as off-switches. Each defaults to `on`.\n\n| # | Variable | Line | Off values | What it turn`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r6/answer.md", "headline": "wrap-ledger.sh has 3 kill switches, each defaulting to on: WRAP_CACHE (line 379; off/0/no stops the memo cache from being read or written), WRAP_RESIDENT (line 1160; off skips the resident-teammate check) and WRAP_BUSY (line `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
