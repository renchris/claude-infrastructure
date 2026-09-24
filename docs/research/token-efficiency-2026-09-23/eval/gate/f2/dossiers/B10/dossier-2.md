# Dossier 2

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off/0/no turns off the --machine memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-team-member check) and WRAP_BUSY (line 2137; off turns off the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

**3 environment variables act as off-switches.** Each defaults to `on`, and the matching value turns a section off.

| # | Variable | Line | Off value(s) | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` | **The memo cache for the `--machine` ledger.** The switch blanks `WL_TRANSCRIPT`, and the cache block at line 380 needs `MODE=machine` and a non-empty `WL_TRANSCRIPT`. So the script never reads or writes a cached ledger. The comment calls this "the benchmark's control arm". The transcript still reaches the goal term through `GOAL_TRANSCRIPT` (set at line 285, before the blanking), so the facts do not change. |
| 2 | `WRAP_RESIDENT` | 1160, in `count_resident_members()` | `off` (exact match) | **The check for resident team members (RC-2).** The function returns at once with `RESIDENT_SRC=none`. No running teammate processes are counted, so `RESIDENT_MINE` and its 🔧 loose-end rung never fire. |
| 3 | `WRAP_BUSY` | 2137 | `off` (exact match) | **The session-busy probe.** It skips sourcing `hooks/lib/session-busy.sh` and calling `session_busy_live`. The BUSY fields keep their defaults (`BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`), and the custody arm that reads them sees nothing. |

## Excluded, and why
- `DRAIN_SCOPE` (line 942): the script sets it itself (`DRAIN_SCOPE=0` at 601, then `=1` at 627 when the DoD scope mentions backlog or drain). It is not read from the environment, and setting it to 1 turns a check on, not off.
- `WRAP_LIVE_STALE_MAX` (1278) and `WRAP_LIVE_ADDS_MAX` (1283): these are scan-size caps. Past the cap the answer becomes `?`. They are not off-switches.
- `WRAP_LIVE_BUDGET_*`, `WRAP_*_TIMEOUT_S`, `WRAP_CACHE_*` tunables, `CC_CONVICTION_EPOCH`: these are thresholds, timeouts and dates.
- `WRAP_LIVE_REPO`, `WRAP_LIVE_ROOT`, `WRAP_GATE_GREEN`, `WRAP_*_LIB`, `CC_*_BIN`: these are test path seams (listed at lines 181-188). They are not switches.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(off|OFF)\\b|:-[01]\\}|= *\"?0\"?|!= *\"?1\"?|== *\"?0\"?' $F | grep -E '\\$\\{?[A-Z_]{3,}' | head -80", "description": "Grep wrap-ledger.sh for off-switch variables"}`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{[A-Z][A-Z0-9_]*:-(on|off|1|0|yes|no)\\}' $F; echo ---; grep -niE 'kill.?switch|off-switch|opt.?out|disable' $F | head -40", "description": "Find env vars with on/off defaults and kill-switch mentions"}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
942:  [ "${DRAIN_SCOPE:-0}" -eq 1 ] || { CLOSE_FLOOR_SRC="n-a"; return 0; }
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; ret
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\"off\"|\\boff\\)|off\\|' $F; echo ---; grep -noE '\\$\\{?[A-Z][A-Z0-9_]{2,}' $F | sed 's/.*[{$]//' | sort | uniq -c | sort -rn | awk '{print $2}' | tr '\\n' ' '", "description": "List off comparisons and all uppercase variabl`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
2137:if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_LIVE_ROOT|WRAP_LIVE_REPO|WRAP_GATE_GREEN|WRAP_LIVE_ADDS_MAX|WRAP_LIVE_STALE_MAX|CC_CONVICTION_EPOCH|DRAIN_SCOPE|WRAP_LIVE_BUDGET|WRAP_CACHE\\b|WRAP_RESIDENT\\b|WRAP_BUSY\\b|WRAP_LAND_INFLIGHT_LIB|WRAP_SESSION_BUSY_LIB' $F`
   → 83:#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
91:#   PAST the converge budget is news: WRAP_LIVE_BUDGET_COMMITS (25) or WRAP_LIVE_BUDGET_MIN (360,
181:# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · 
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n '270,290p;374,382p;1150,1162p;1272,1290p;2125,2140p' $F; grep -nE 'LIVE_STALE_MAX|LIVE_ADDS_MAX' $F", "description": "Read context around each switch"}`
   → #     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss
6. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B10-r6 && cat > /tmp/tokeff-gate/f2/out/B10-r6/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\n**3 environment variables act as off-switches.** Each defaults to `on`, and the matching value turns a section off.\n\n| # | Variable | Line | `
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r6/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379; off/0/no turns off the --machine memo cache), WRAP_RESIDENT (line 1160; off turns off the resident-team-member check) and WRAP_BUSY (line 2137; off turns off the session`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
