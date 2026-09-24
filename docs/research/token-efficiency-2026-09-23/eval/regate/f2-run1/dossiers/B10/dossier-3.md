# Dossier 3

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has three environment kill switches, each defaulting to on. WRAP_CACHE (line 379; off, 0 or no, any case) turns off the memo cache. WRAP_RESIDENT=off (line 1160) skips the resident-teammate check. WRAP_BUSY=off (line 2137) skips the session-busy and permission-pending probe.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

Three environment variables act as off-switches. Each defaults to `on`.

| # | Variable | Line | Off value(s) | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` | The `--machine` ledger memo cache. Setting it blanks `WL_TRANSCRIPT`, the cache-key input, so the cache is never read and never written. The header calls this "the benchmark's control arm". The transcript still reaches the goal term through `GOAL_TRANSCRIPT` (line 285), so the facts reported do not change. |
| 2 | `WRAP_RESIDENT` | 1160, in `count_resident_members()` | `off` only | The resident-member check (RESIDENT_MINE): it counts this session's team members whose processes are still running, and those members would otherwise show up as a 🔧 loose end. With the switch off, the function returns early with `RESIDENT_SRC=none`. |
| 3 | `WRAP_BUSY` | 2137 | `off` only (the test is `!= "off"`) | The session-busy and permission-pending probe, which sources `hooks/lib/session-busy.sh` and calls `session_busy_live` and `sb_permpend`. With the switch off, the fields keep their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

## Excluded
- `DRAIN_SCOPE` (line 942) looks like a gate, but the script sets it internally (line 601 sets it to 0, line 627 derives it from the DoD scope). It is not read from the environment.
- The `*_TIMEOUT_S` variables, `WRAP_CACHE_*` tuning knobs and `*_BIN`/`*_LIB` overrides are bounds and test seams. None of them disables a section.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*(:-[^}]*)?\\}?\"? *(=|!=|==) *\"?(off|0|1|on)\"?|(off|0)\\)' $F | head -80"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
225:#   FAILURE 1 (9adc5120) — benchmarked SEQUENTIALLY (60 → 27 git, "2.22×") and shipped as a
371:  now="$(date +%s 2>/dev/null || echo 0)"
432:    # add to a Stop that is already the felt-lag hot spot (3.7 s p50). 750 ms ≈ the uncached co
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\"\\$\\{[A-Z_][A-Z0-9_]*:-[^}]*\\}\"|case \"\\$\\{[A-Z_]+' $F | grep -vE '\\$\\{(HOME|TRUNK|PWD|TMPDIR|CLAUDE_CONFIG_DIR)' | head -80; grep -niE 'kill.?switch|off-switch|=off|=0 ' $F | head -60"}`
   → 376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
436:    _wl_tries="${WRAP_CACHE_WAIT_TRIES:-4}"
438:    _wl_ms_wait="${WRAP_CACHE_WAIT_MS:-50}"
464:TRUNK="${WRAP_TRUNK:-}"
549:_wl_lil="${WRAP_LAND_INFLIGHT_LIB:-$(
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\boff\\b' $F | head -40; grep -n 'DRAIN_SCOPE' $F | head; sed -n 270,285p $F; sed -n 372,382p $F; sed -n 1150,1162p $F; sed -n 2125,2140p $F"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
861:# `whyNotNow` (the hand-o
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_RESIDENT[^_]|WRAP_BUSY[^_]|WRAP_CACHE[^_]' $F; sed -n 1140,1148p $F; sed -n 2146,2175p $F"}`
   → 186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY va
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r2 && cat > /tmp/tokeff-regate/f2/out/B10-r2/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThree environment variables act as off-switches. Each defaults to `on`.\n\n| # | Variable | Line | Off value(s) | What it turns off |\n|---`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r2/answer.md", "headline": "wrap-ledger.sh has three environment kill switches, each defaulting to on. WRAP_CACHE (line 379; off, 0 or no, any case) turns off the memo cache. WRAP_RESIDENT=off (line 1160) skips the resident-teammate check. WRAP_BUSY=off`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
