# Dossier 8

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 environment kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the memo cache), WRAP_RESIDENT (line 1160; off skips the resident teammate check) and WRAP_BUSY (line 2137; off skips the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment-variable kill switches. Each one defaults to `on`, and setting it to `off` disables its section.

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276) | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It blanks `WL_TRANSCRIPT`, so the `--machine` cache block at line 380 (`[ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]`) never runs. The cache is then never read and never written. The header comment calls this "the benchmark's control arm". |
| 2 | `WRAP_RESIDENT` | 1160 (in `count_resident_members`) | `off` only | The resident-member check (RC-2). The function returns at once with `RESIDENT_SRC=none`, so live teammates of this session's team never become a 🔧 loose end. |
| 3 | `WRAP_BUSY` | 2137 | `off` only (`!= "off"`) | The session-busy probe, which sources `hooks/lib/session-busy.sh` and calls `session_busy_live`. BUSY, BUSY_STATE and PERMPEND keep their defaults (`BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). |

## Variables that look like switches but are not

- `DRAIN_SCOPE` at line 942 (`[ "${DRAIN_SCOPE:-0}" -eq 1 ] || …`) does gate the close-floor check. It is not taken from the environment, though. Line 601 always sets it to 0, and line 627 derives it from the frozen DoD text.
- The `WRAP_*_TIMEOUT_S`, `WRAP_LIVE_BUDGET_*`, `WRAP_LIVE_*_MAX` and the `*_BIN`/`*_DIR`/`*_LIB` path overrides are tuning knobs or test seams, not on/off switches. An invalid budget value falls back to the default and never becomes "unbounded" (comment at lines 1310-1312).


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(off|OFF|:-1|:-0|= *\"?0\"?|kill.?switch|Kill switch)' $F | grep -E '\\$\\{?[A-Z_]+' | head -80"}`
   →     2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${U
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{[A-Z_]+:-[^}]*\\}' $F | grep -vE 'TMPDIR|HOME|UID' | grep -nE '\"off\"|off\\)|off\\||!= *\"?0|= *\"?0\"?|-eq 0|-eq 1|-ne 0|on\\}|:-1\\}' | head -60; echo ---; grep -nE 'kill switch|kill-switch|off-switch|=off|=0 ' $F |`
   → 3:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
28:942:  [ "${DRAIN_SCOPE:-0}" -eq 1 ] || { CLOSE_FLOOR_SRC="n-a"; return 0; }
37:1160:  [ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }
58:2137:if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" 
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:?-[^}]*\\}' $F | sed 's/^[0-9]*://' | sort | uniq -c | sort -rn | head -80; echo; grep -nE 'WRAP_[A-Z_]+|CC_[A-Z_]+' $F | grep -vE '^\\s*[0-9]+:\\s*#' | head -60"}`
   →   10 ${WRAP_LIVE_TIMEOUT_S:-5}
   3 ${WRAP_RESIDENT_TIMEOUT_S:-5}
   2 ${WRAP_TRUNK:-}
   2 ${WRAP_SESSION_ID:-}
   2 ${WRAP_DOD_FILE:-}
   2 ${WRAP_CUSTODY_TIMEOUT_S:-5}
   2 ${WRAP_BACKLOG_TIMEOUT_S:-5}
   2 ${TRUNK:-none}
   2 ${SID:-}
   2 ${CLAUDE_SESSION_ID:-}
   2 ${CC_PANE_ID:-${ITERM_SESSIO
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nEi 'disabl|switch|opt.?out|= *0 ⇒|=0 ⇒|0 disables|off ⇒' $F | head -40; grep -n 'DRAIN_SCOPE' $F | head; sed -n 270,282p $F; sed -n 1150,1162p $F; sed -n 1276,1312p $F; sed -n 2125,2140p $F"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
498:  # again, so a repo with a perfectly good origin/main reported TRUNK=none ⇒ AHEAD=0 ⇒ UNLANDED=0
553: 
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_]+\\}?\"? *!?= *\"?(off|0|no|false)\"?|in +off|\\b(off|OFF)\\)' $F; sed -n 2140,2150p $F; sed -n 380,384p $F"}`
   → 379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
  if . "$_wl_sbl" 2>/dev/null && command -v session_busy_live >/dev/null 2>&1; then
    # shellcheck disable=SC2016   # single quotes deliberate: this is the CHILD shell's script,
    # and $1..$4 are its positional parameters
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r7 && cat > /tmp/tokeff-regate/f2/out/B10-r7/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment-variable kill switches. Each one defaults to `on`, and setting it to `off` disables its section.\n\n| # | Varia`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r7/answer.md", "headline": "wrap-ledger.sh has 3 environment kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the memo cache), WRAP_RESIDENT (line 1160; off skips the resident teammate check) and WRAP_BUSY (line 2137; off skips the session-bu`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
