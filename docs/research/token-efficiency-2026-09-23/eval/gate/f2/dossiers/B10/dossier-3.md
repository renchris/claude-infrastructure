# Dossier 3

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has three kill switches, all defaulting to on: WRAP_CACHE (line 379, off/0/no) stops the memo cache from reading or writing, WRAP_RESIDENT (line 1160, only "off") skips the resident-teammate check, and WRAP_BUSY (line 2137, only "off") skips the working-vs-idling section.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment-variable kill switches. Each defaults to `on`.

| # | Variable | Line | Values that disable it | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (`case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac`), documented at 276 | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache: it never reads and never writes the cache. The header calls this "the benchmark's control arm". It works by blanking the cache-key variable `WL_TRANSCRIPT`. The cache block at 380 only runs when that variable is non-empty. `GOAL_TRANSCRIPT` is captured at line 285, before the blanking, so the goal fact is still computed. |
| 2 | `WRAP_RESIDENT` | 1160 (`[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }`, in `count_resident_members`) | exactly `off` | The resident-teammate check (`RESIDENT_MINE`). This check counts this session's team members whose processes are still running and turns them into a 🔧 loose end. With the switch off, `RESIDENT_SRC=none` and the count stays 0. |
| 3 | `WRAP_BUSY` | 2137 (`if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then`) | exactly `off` | The ⏳ working-vs-idling section, which sources `hooks/lib/session-busy.sh` and calls `session_busy_live`. With the switch off, the busy fields keep their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

## Notes
- Only `WRAP_CACHE` accepts `0` or `no`. `WRAP_RESIDENT` and `WRAP_BUSY` compare against the literal string `off`, so setting them to `0` does **not** disable them.
- The other `WRAP_*` and `CC_*` variables are not off-switches. They are test seams, timeouts, budgets and caps, for example `WRAP_LIVE_BUDGET_*`, `WRAP_LIVE_*_MAX` and `WRAP_*_TIMEOUT_S`. None of them is compared against off or 0 to skip a section.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(:-[^}]*\\}|\\$\\{?[A-Z_]+).*(off|=.?0|\"0\")' $F | grep -nE 'off|\"0\"|= 0|=0|!= *\"?1' | head -80"}`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
1:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
3:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
4:534:  AHEAD="$(git rev-list --count "$TRU
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | grep -vE '\\$\\{(SID|TRUNK|HOME|PWD|n|u|evals|epoch)' | grep -oE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' | sort | uniq -c; echo ---; grep -niE 'kill.?switch|off-switch|=off|\"off\"|off\\)' $F | `
   →    2 ${CC_BACKLOG_BIN:-}
   1 ${CC_BACKLOG_BIN:-$(command -v cc-backlog 2>/dev/null || true)}
   1 ${CC_CONVICTION_EPOCH:-2026-09-08T17:00:00Z}
   2 ${CC_CUSTODY_BIN:-}
   1 ${CC_CUSTODY_DIR:-}
   2 ${CC_DECIDE_BIN:-}
   1 ${CC_MIGRATIONS_STATE:-}
   1 ${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/m
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 270,290p $F; sed -n 375,382p $F; sed -n 1150,1162p $F; sed -n 2125,2140p $F; grep -nE '(WRAP|CC)_[A-Z_]+.*(= *\"?0\"?|-eq 0|-le 0|disable)' $F | head; grep -niE 'disabl|opt.?out' $F | head -20"}`
   → #     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_CACHE[^_]|WRAP_RESIDENT[^_]|WRAP_BUSY[^_]' $F; grep -nE 'WRAP_LIVE_BUDGET|WRAP_LIVE_ADDS_MAX|WRAP_LIVE_STALE_MAX' $F | head; grep -nE '\\[ \"\\$\\{?(WRAP|CC)_[A-Z_]+\\}?\" (=|!=) ' $F | head"}`
   → 186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY va
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 170,200p $F; sed -n 1274,1312p $F; sed -n 1120,1135p $F; sed -n 2110,2124p $F"}`
   → #   drift (MEMORY.md make-the-actuator-the-arbiter).
#   FAIL DIRECTION: no transcript ⇒ `none`; unreadable/no-jq/lib-too-old ⇒ `error`; readable with
#   no goal records ⇒ `absent`. `absent` is a POSITIVE finding and is never manufactured from a
#   read that did not happen — the same law as YOURS_
6. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B10-r2 && cat > /tmp/tokeff-gate/f2/out/B10-r2/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment-variable kill switches. Each defaults to `on`.\n\n| # | Variable | Line | Values that disable it | What it turns of`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r2/answer.md", "headline": "wrap-ledger.sh has three kill switches, all defaulting to on: WRAP_CACHE (line 379, off/0/no) stops the memo cache from reading or writing, WRAP_RESIDENT (line 1160, only \"off\") skips the resident-teammate check, and WRAP_BUS`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
