# Dossier 1

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 environment kill switches, all on by default: WRAP_CACHE (line 379; off/0/no/OFF/NO) disables the memo cache, WRAP_RESIDENT (line 1160; exact string "off") skips the resident-teammate count, and WRAP_BUSY (line 2137; exact string "off") skips the session-busy section.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches / off-switches in scripts/wrap-ledger.sh

Method: I grepped every `${VAR:-default}` expansion and every comparison against `off`/`0` in
/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`), then read the code around each hit.

## The 3 kill switches (all default `on`)

| # | Variable | Line | Values that switch it off | What it turns off |
|---|----------|------|---------------------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (`case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac`); the header comment at 276 names it the "Kill switch" | `off`, `0`, `no`, `OFF`, `NO` | **The ledger memo cache.** The switch blanks `WL_TRANSCRIPT`, the cache-key input. The guard at 380 (`[ -n "$WL_TRANSCRIPT" ]`) then skips building the key, so the cache is never read or written (per line 276: "never read, never write (the benchmark's control arm)"). A separate transcript input (lines 279-282) keeps the switch from changing what the script computes. |
| 2 | `WRAP_RESIDENT` | 1160 (`[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }`), inside `count_resident_members()` | `off` only (exact string) | **The resident-teammate check.** `count_resident_members()` returns early, so `RESIDENT_MINE` stays 0 and `RESIDENT_SRC=none`. The function never looks up the team config, reads the `ps` table, matches live members or reads their dirty files. The `RESIDENT_MINE -gt 0` branch at line 2017 therefore never fires. |
| 3 | `WRAP_BUSY` | 2137 (`if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then`) | `off` only (exact string) | **The session-busy section.** The script does not source `hooks/lib/session-busy.sh` or call `session_busy_live`. The BUSY/PERMPEND fields keep their initial values from line 2133: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

Only `WRAP_CACHE` accepts `0` or `no`. `WRAP_RESIDENT` and `WRAP_BUSY` react only to the exact string `off`; setting them to `0` does nothing.

## Checked and excluded (not env off-switches)
- `DRAIN_SCOPE` (line 942, `[ "${DRAIN_SCOPE:-0}" -eq 1 ] || ...`) does gate the close-floor check, but it is an internal variable. The script sets it at line 601 (`DRAIN_SCOPE=0`) and line 627 (from the DoD scope), which overwrites any environment value.
- `WRAP_TIMEOUT_BIN` (lines 763-770): a non-executable value "pins 'no bounder'" (the timeout wrapper). It is a test seam that takes a path, not an on/off switch.
- The other `WRAP_*` and `CC_*` variables (the `*_TIMEOUT_S`, `*_DIR`, `*_BIN`, `*_LIB`, `WRAP_LIVE_*` budgets, `WRAP_TRUNK`, `WRAP_SESSION_ID`, and so on) are paths, timeouts, thresholds or identity seams. None of them has an off value.

kill_switches = 3


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -nE '\\$\\{?[A-Z_]+[A-Z0-9_]*' wrap-ledger.sh | grep -nE '(off|OFF|:-1|:-on|= *\"?0\"?|== *\"?0|!= *\"?0|DISABLE|SKIP|NO_)' | head -80; ls /tmp/tokeff-gate/f2/out/B10-r5/ 2>&1", "description": "Scan script for env-var o`
   →     2444 wrap-ledger.sh
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
59:496:  # TRUNK was assigned that bogus ref, and the `[ -n "$TRUNK" ]` guards below then SKIPPED the
64:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && grep -noE '\\$\\{[A-Z_][A-Z0-9_]*:-[^}]*\\}' wrap-ledger.sh | sort -t: -k3 | awk -F: '{print $1\": \"$2\":\"$3}' | sort -u -k2 | head -80; echo ---; grep -nE 'WRAP_[A-Z_]+|_OFF|KILL|DISABLE' wrap-ledger.sh | head -60", "description": "List env var `
   → 388: ${CC_BACKLOG_BIN:-}
946: ${CC_BACKLOG_BIN:-$(command -v cc-backlog 2>/dev/null || true)}
857: ${CC_CONVICTION_EPOCH:-2026-09-08T17
1050: ${CC_CUSTODY_BIN:-}
388: ${CC_CUSTODY_DIR:-}
388: ${CC_DECIDE_BIN:-}
398: ${CC_MIGRATIONS_STATE:-}
1315: ${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrati
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && grep -nE '\"off\"|off\\||= *\"?0\"? *\\]|-eq 0' wrap-ledger.sh | head -40; echo ---; sed -n 270,282p wrap-ledger.sh; echo; sed -n 376,382p wrap-ledger.sh; echo; sed -n 1150,1162p wrap-ledger.sh; echo; sed -n 2125,2140p wrap-ledger.sh; echo; sed -n `
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
330:    if [ "$got" -eq 0 ]; then first="$line"; got=1; continue; fi
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
728:  if [ "$GOAL_EVALS" -eq 0 ]; then
949:  if [ "$CLOSED_MI
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && grep -nE 'WRAP_RESIDENT|WRAP_BUSY|RESIDENT_MINE|resident' wrap-ledger.sh | head -20; sed -n 186,190p wrap-ledger.sh; sed -n 760,770p wrap-ledger.sh", "description": "Check docs for resident/busy switches"}`
   → 4:# THE DEFECT it closes (G-P6-4): the resident Session-Close Protocol claims the readout is
186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
1093:# told the lead it still had residents, so the fleet's answer was a sweeper rather than the owner.
1130:RESIDENT_MIN
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && sed -n 2012,2022p wrap-ledger.sh; mkdir -p /tmp/tokeff-gate/f2/out/B10-r5 && cat > /tmp/tokeff-gate/f2/out/B10-r5/answer.md <<'EOF'\n# Kill switches / off-switches in scripts/wrap-ledger.sh\n\nMethod: I grepped every `${VAR:-default}` expansion and`
   →   if [ -n "$TRUNK" ]; then compute_live_layer; count_operator_steps; fi
  count_filed_undriven
  compute_close_floor
  sum_unconvicted
  count_resident_members
  if [ "$RESIDENT_MINE" -gt 0 ]; then
    # RANKED BESIDE THE CUSTODY ARM ABOVE, and one step below it, for the reason custody gives:
    # 
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r5/answer.md", "headline": "wrap-ledger.sh has 3 environment kill switches, all on by default: WRAP_CACHE (line 379; off/0/no/OFF/NO) disables the memo cache, WRAP_RESIDENT (line 1160; exact string \"off\") skips the resident-teammate count, and WRAP_BUSY`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
