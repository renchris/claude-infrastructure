# Dossier 5

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches (measured by grep and reading each hit): WRAP_CACHE (line 379; off, 0 or no disables the memo cache read and write), WRAP_RESIDENT (line 1160; only "off" skips count_resident_members) and WRAP_BUSY (line 2137; only "off" skips the session-busy and permission-pending probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured by `wc -l`)

**Kill switches: 3.** Measured by grepping for environment variables compared against off/0/no
(`grep -nE` for `= "off"`, `!= "off"`, `case ... in off|0|...`) and for the words kill/disable/switch.
I then read each hit in context.

| # | Variable | Line | Test | What it turns off |
|---|----------|------|------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The ledger memo cache. Blanking `WL_TRANSCRIPT` skips the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380, so the script neither reads nor writes the cache. The header calls this the benchmark's control arm: "Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write". The goal/transcript input survives because `GOAL_TRANSCRIPT` is copied at line 285, before the switch runs. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident-team-member sensor, `count_resident_members()` (lines 1159-1253, called at 2016). That covers the RESIDENT_MINE count, the member names and the RESIDENT_DIRTY_FILES shared-cwd dirt probe. The script reports RESIDENT_SRC=none instead. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The session-busy / permission-pending probe (sourcing `hooks/lib/session-busy.sh`, lines 2137-2162). BUSY, BUSY_STATE, BUSY_AGE, BUSY_SUSPECT and PERMPEND stay at their defaults set at lines 2134-2135: BUSY=0, BUSY_STATE=UNKNOWN, BUSY_SRC=none. |

## Notes
- Only `WRAP_CACHE` accepts `0` (and also `no`, `OFF`, `NO`). `WRAP_RESIDENT` and `WRAP_BUSY` match only the
  literal lowercase string `off`, so setting either one to `0` does NOT disable its section.
- These are not counted as kill switches. The other env vars are path, binary or timeout overrides:
  `WRAP_*_TIMEOUT_S`, `CC_*_BIN`, `WRAP_DOD_*`, `WRAP_LIVE_*`, `WRAP_CACHE_DIR`,
  `WRAP_CACHE_WAIT_*` and so on. `DRAIN_SCOPE` (line 942) is an internal variable
  computed at line 627 from the DoD scope, not an off-switch the caller sets.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -n '\\${\\?[A-Z_][A-Z0-9_]*' wrap-ledger.sh | grep -niE 'off|:-|== *\"?0|= *\"?0' | head -80; ls /tmp/tokeff-regate/f2/out/B10-r1/ 2>&1", "description": "Inspect script for env var switches"}`
   →     2444 wrap-ledger.sh
8:278:WL_TRANSCRIPT="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
13:335:  [ "${first:-}" = "#WLKEY $WL_KEY" ] || return 1
24:376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
29:386:    _wl_
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*(:-[^}]*)?\\}?\"? *(=|!=|==|-eq|-ne) *\"?(off|0|on|1|no)\"?|case \"\\$\\{?[A-Z_][A-Z0-9_]*' wrap-ledger.sh; echo ---; grep -nE '\\b(off|OFF)\\b' wrap-ledger.sh | head -60", "description": "Find env var comparisons`
   → 362:  [ "$WL_LOCK_HELD" -eq 1 ] || return 0
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
437:    case "$_wl_tries" in ''|*[!0-9]*) _wl_tries=4 ;; esac
439:    case "$_wl_ms_wait" in ''|*[!0-9]*) _wl_ms_wait=50 ;; esac
528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -niE 'kill|disabl|switch|opt.?out|_SKIP|NO_[A-Z]' wrap-ledger.sh | head -40; echo ---; sed -n 270,300p wrap-ledger.sh; sed -n 374,383p wrap-ledger.sh; sed -n 1150,1162p wrap-ledger.sh; sed -n 2125,2140p wrap-ledger.sh", "description": "Searc`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
553:  # shellcheck disable=SC1091
579:# shellcheck disable=SC1090,SC1091
699:  # shellcheck disable=SC1090,
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '=off|=0\\b|off\\)' wrap-ledger.sh | head; sed -n 1236,1250p wrap-ledger.sh; sed -n 1085,1100p wrap-ledger.sh | grep -n WRAP; sed -n 2140,2175p wrap-ledger.sh | grep -nE 'else|fi$|BUSY_SRC'", "description": "Check remaining context for s`
   → 52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCKED_SRC=error. An unresolvable sensor NEVER manufactures a
70:#   YOURS=0 + YOURS_SRC=none and the rung stays ✅ — an unknown session NEVER manufactures a 👤.
2
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && awk 'NR>=1155 && NR<=1270 && /^[a-z_]+\\(\\) *\\{|^\\}/ {print NR\": \"$0}' wrap-ledger.sh; grep -nE 'count_resident_members|_resident_dirty|RESIDENT_DIRTY_FILES=' wrap-ledger.sh | head", "description": "Locate resident function boundaries and ca`
   → 1157: }
1159: count_resident_members() {
1253: }
1258: _resident_member_sid() {
1268: }
1130:RESIDENT_MINE=0; RESIDENT_SRC="skip"; RESIDENT_MINE_NAMES=""; RESIDENT_DIRTY_FILES=""
1159:count_resident_members() {
1249:    RESIDENT_DIRTY_FILES="${RESIDENT_DIRTY_FILES:+$RESIDENT_DIRTY_FILES; }${nm}=${di
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r1 && cat > /tmp/tokeff-regate/f2/out/B10-r1/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured by `wc -l`)\n\n**Kill switches: 3.** Measured by grepping for`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r1/answer.md", "headline": "wrap-ledger.sh has 3 kill switches (measured by grep and reading each hit): WRAP_CACHE (line 379; off, 0 or no disables the memo cache read and write), WRAP_RESIDENT (line 1160; only \"off\" skips count_resident_members) and `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
