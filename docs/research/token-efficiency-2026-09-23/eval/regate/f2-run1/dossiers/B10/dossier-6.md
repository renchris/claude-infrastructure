# Dossier 6

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 environment kill switches: WRAP_CACHE (line 379, off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160, literal "off" skips resident team-member counting) and WRAP_BUSY (line 2137, literal "off" skips the session-busy probe). Only WRAP_CACHE also accepts 0. Found by grep plus reading each hit in context.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches / off-switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, `wc -l`)

**kill_switches = 3** (measured: grep for `off` / `0` comparisons against env variables, then read each hit in context)

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|----------|------|-----------------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented as "Kill switch" at line 276) | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It sets `WL_TRANSCRIPT=""`, so the cache block (line 380, `[ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]`) is skipped: no cache read and no cache write. This is the benchmark's control arm. Goal liveness still gets the transcript through `GOAL_TRANSCRIPT` (line 285), which is captured before the blanking. |
| 2 | `WRAP_RESIDENT` | 1160 (in `count_resident_members`; also listed among the env seams at line 186) | literal `off` only | Resident team-member counting. It returns early with `RESIDENT_SRC="none"`, so the team config, ps table, per-member dirty-file and cc-sessions probes are all skipped. |
| 3 | `WRAP_BUSY` | 2137 | literal `off` only | The session-busy section. `session-busy.sh` is not sourced and `session_busy_live` is not called, so BUSY, BUSY_STATE, BUSY_SUSPECT and PERMPEND keep their defaults (`0` / `UNKNOWN`, `BUSY_SRC=none`). |

Notes:
- `WRAP_RESIDENT` and `WRAP_BUSY` compare only against the exact string `off`. Setting them to `0` does NOT disable anything. Only `WRAP_CACHE` accepts `0`.
- Left out on purpose:
  - `DRAIN_SCOPE` (line 942) looks like a gate, but it is an internal variable. Line 601 sets it and line 627 derives it from the DoD scope, so it is not an environment switch.
  - The `WRAP_*_TIMEOUT_S`, `WRAP_*_BIN`/`CC_*_BIN`, `WRAP_*_LIB` and threshold variables (`WRAP_LIVE_*_MAX`, `WRAP_LIVE_BUDGET_*`) are tuning or path seams, not on/off switches.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*' /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh | grep -nE 'off|\"0\"|=0|:-1|:-on|OFF' ; ls /tmp/tokeff-regate/f2/out/B10-r8/ 2>&1", "description": "Count lines and grep candidate env switches"`
   → Exit code 1
    2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
64:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
65:529:DIRTY=0; [ "$DIRTY_N
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{?[A-Z][A-Z0-9_]*(:-[^}]*)?\\}?' $F | awk -F: '{print $2}' | sort | uniq -c | sort -rn | head -80; echo ---; grep -nE '\\$\\{[A-Z_][A-Z0-9_]*:-[^}]*\\}' $F | grep -vE 'HOME|TMPDIR' | head -60", "description": "List env`
   →   22 $SID
  20 $TRUNK
  15 $LIVE_REPO
  13 $PWD
  13 $HOME
  12 $LIVE_ADDS
  10 $WL_DIR
  10 $LIVE_ROOT
  10 $HEAD_SHA
  10 ${WRAP_LIVE_TIMEOUT_S
   8 $LIVE_SHA
   7 $WL_FILE
   7 $LIVE_SRC
   7 $LIVE_LAG
   7 $LIVE_AGE
   7 $FILED_SRC
   7 $CUSTODY_MINE
   7 ${LIVE_LAG}
   6 $WL_LOCK
   5 $YOURS
  
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\boff\\b|\"0\"\\)|= *\"?0\"?\\b.*(WRAP|CC_)|(WRAP|CC)_[A-Z_]*[^A-Z_].{0,20}(off|disable|kill)' $F | head -40; echo ---; grep -nE 'DRAIN_SCOPE' $F | head; echo ---; sed -n 1,80p $F | grep -nE 'WRAP_|off|kill|disable'", "desc`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
861:# `whyNotNow` (the hand-o
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n 270,285p $F; echo ...; sed -n 374,384p $F; echo ...; sed -n 1150,1162p $F; echo ...; sed -n 2125,2140p $F; grep -nE 'WRAP_(RESIDENT|BUSY)\\b' $F", "description": "Read context around each kill switch"}`
   → #     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r8 && cat > /tmp/tokeff-regate/f2/out/B10-r8/answer.md <<'EOF'\n# Kill switches / off-switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, `wc -l`)\n\n**kill_switches = 3** (measured: grep for ``
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r8/answer.md", "headline": "wrap-ledger.sh has 3 environment kill switches: WRAP_CACHE (line 379, off/0/no turns off the memo cache), WRAP_RESIDENT (line 1160, literal \"off\" skips resident team-member counting) and WRAP_BUSY (line 2137, literal \"off\`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
