# Dossier 7

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 environment off-switches: WRAP_CACHE at line 379 (off, 0 or no turns off the memo cache), WRAP_RESIDENT at line 1160 (off skips the resident-teammate count) and WRAP_BUSY at line 2137 (off skips the session-busy probe); found by reading the script with grep/sed.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches / off-switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).
Method: grep for `${VAR:-...}` defaults and for `off` / `0` comparisons, then read the surrounding code (measured with grep/sed).

Three environment variables work as off-switches:

| # | Variable | Line | Test | What it turns off |
|---|----------|------|------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented at 276: "Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write (the benchmark's control arm)") | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The ledger memo cache. Setting it blanks `WL_TRANSCRIPT`, which is the cache key. The cache block starting at line 380 (`if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]`) is then skipped, so no cache file is read or written. The transcript as an input (`GOAL_TRANSCRIPT`, line 285) is captured before this line, so the switch changes only the caching, not the answer. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident-teammate count, `count_resident_members`. The function returns straight away with `RESIDENT_SRC=none`, so it does not scan the team config, the `ps` table or the dirty state of teammate worktrees. Only the literal `off` works. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The session-busy probe. `session-busy.sh` is not sourced and `session_busy_live` is not run, so the fields stay at their defaults from line 2133: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`. The permission-pending fields `PERMPEND` and `PERMPEND_AGE` also stay at 0. Only the literal `off` works. |

Count: **3**.

Notes:
- Only `WRAP_CACHE` also accepts `0` or `no`. `WRAP_RESIDENT` and `WRAP_BUSY` turn off only on the exact string `off`. With `0`, both sections still run.
- One related variable is not counted. `WRAP_TIMEOUT_BIN` (lines 763-769) set to a non-executable path forces "no bounder", meaning commands run without a timeout. It is a test seam that takes a path, not an off/0 switch.
- The `*_TIMEOUT_S`, `*_DIR`, `*_BIN`, `*_LIB` and budget variables are value overrides, not switches.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -nE '\\$\\{?[A-Z_]+' wrap-ledger.sh | grep -nE '(off|OFF|\"0\"|= *0|:-1|:-on|DISABLE|SKIP|NO_)' | head -80; ls /tmp/tokeff-gate/f2/out/B10-r4/ 2>&1", "description": "Search script for env-var off-switches"}`
   →     2444 wrap-ledger.sh
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
59:496:  # TRUNK was assigned that bogus ref, and the `[ -n "$TRUNK" ]` guards below then SKIPPED the
64:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' wrap-ledger.sh | sort -t: -k3 -u | sort -n; echo ---; grep -nE 'WRAP_[A-Z_]+|_OFF|DISABLE|KILL' wrap-ledger.sh | head -60", "description": "List env vars with defaults and WRAP_ vars"}`
   → 278:${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}
376:${WRAP_CACHE_LOCK_STALE_S:-30}
379:${WRAP_CACHE:-on}
386:${WRAP_SESSION_ID:-}
396:${CC_PANE_ID:-${ITERM_SESSION_ID:-}
400:${UID:-0}
400:${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}
436:${WRAP_CACHE_WAIT_TRIES:-4}
438:${WRAP_CACHE_WAIT_MS:-50}
549:${WRAP_LAND_INFL
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && grep -nE '\"off\"|off\\||\\boff\\b' wrap-ledger.sh | head -40; echo ---; grep -nE '\\$\\{?[A-Z][A-Z0-9_]*(:-[^}]*)?\\}?\"? *(=|!=|-eq|-ne) *\"?0\"?' wrap-ledger.sh | head; echo ---; sed -n 270,282p wrap-ledger.sh; sed -n 1150,1162p wrap-ledger.sh; `
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
861:# `whyNotNow` (the hand-o
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/scripts && sed -n 380,386p wrap-ledger.sh; grep -nE 'WRAP_RESIDENT[^_]|WRAP_BUSY[^_]|WRAP_BUSY$' wrap-ledger.sh; sed -n 760,770p wrap-ledger.sh; grep -nE 'WL_TRANSCRIPT' wrap-ledger.sh | head", "description": "Check cache gating and switch docs"}`
   → if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]; then
  _wl_ms="$(_wl_stat_ms "$WL_TRANSCRIPT")" || _wl_ms=""
  if [ -n "$_wl_ms" ]; then
    # Every input that can change the answer, in one string. The seams are the ones the header's
    # "Env seams" line lists — a caller that overrides one 
5. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B10-r4/answer.md <<'EOF'\n# Kill switches / off-switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\nMethod: grep for `${VAR:-...}` defaults and for `off` / `0` comparisons, then r`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r4/answer.md", "headline": "wrap-ledger.sh has 3 environment off-switches: WRAP_CACHE at line 379 (off, 0 or no turns off the memo cache), WRAP_RESIDENT at line 1160 (off skips the resident-teammate count) and WRAP_BUSY at line 2137 (off skips the session`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
