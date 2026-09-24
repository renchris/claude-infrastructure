# Dossier 7

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches (found by grep and reading each hit). WRAP_CACHE (line 379; off, 0 or no) turns off the TMPDIR memo cache for both reads and writes. WRAP_RESIDENT (line 1160; only the literal "off") skips the resident-member check. WRAP_BUSY (line 2137; only the literal "off") skips the session-busy section.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).
Method: grep for every `${VAR:-...}` default and every `off`/`0` comparison, then read each hit in context.

**Count: 3 kill switches** (measured by the grep and read below).

| # | Variable | Line | Accepted "off" values | What it turns off |
|---|----------|------|-----------------------|-------------------|
| 1 | `WRAP_CACHE` | 379: `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | off, 0, no, OFF, NO | The memo cache under TMPDIR, so it is never read and never written. Blanking `WL_TRANSCRIPT` makes the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380 skip. As a result `WL_KEY` stays empty, and the cache-serve and single-flight lock at line 413 onward never run. The header comment at line 276 names it: "Kill switch: WRAP_CACHE=off\|0\|no ⇒ never read, never write (the benchmark's control arm)." Goal and transcript facts still read from `GOAL_TRANSCRIPT`, which is copied before the blanking (line 285), so only caching is affected. |
| 2 | `WRAP_RESIDENT` | 1160: `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | only the literal `off` | The resident-member check (`count_resident_members`). This check counts live team members/teammates this session spawned, using the team config and the process table. When switched off it returns early with `RESIDENT_MINE=0` and `RESIDENT_SRC=none`. |
| 3 | `WRAP_BUSY` | 2137: `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | only the literal `off` | The session-busy section, which sources hooks/lib/session-busy.sh and calls `session_busy_live` and `sb_permpend`. When off, the fields keep their defaults: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`, `PERMPEND=0`. |

Caveat: only `WRAP_CACHE` accepts `0`. For `WRAP_RESIDENT` and `WRAP_BUSY`, a value of `0` does NOT turn anything off, because the test is an exact string match against `off`.

## Considered and excluded (not off/0 switches)
- `WRAP_TIMEOUT_BIN` (lines 763-770): if you set it to a path that is not executable, it pins "no bounder", so commands run unbounded. This is a test seam that picks the timeout binary. It is not an off/0 switch.
- `DRAIN_SCOPE` (line 942): this gates the close-floor check, but the script derives it internally from the DoD scope (lines 601 and 627). It is not an environment input.
- The `*_TIMEOUT_S`, `WRAP_LIVE_*_MAX` and `WRAP_LIVE_BUDGET_*` variables are numeric thresholds and seams. None of them has an off value.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z_]+' /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh | grep -nE 'off|:-1|:-0|= *\"?0|== *\"?0|!= *\"?0|:-on' ; ls /tmp/tokeff-regate/f2/out/B10-r4/ 2>&1", "description": "Count lines and grep env variable sw`
   → Exit code 1
    2444 /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
37:400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
64:528:DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 
2. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]*:-[^}]*\\}' $F | awk -F: '{print $2}' | sort | uniq -c | sort -rn | head -60; echo ---; grep -nE '\"?off\"?|\\boff\\|' $F | head -60", "description": "List env vars with defaults and off-checks"}`
   →   10 ${WRAP_LIVE_TIMEOUT_S
   3 ${WRAP_RESIDENT_TIMEOUT_S
   3 ${SID
   3 ${CC_BACKLOG_BIN
   2 ${WRAP_TRUNK
   2 ${WRAP_SESSION_ID
   2 ${WRAP_LIVE_REPO
   2 ${WRAP_LIVE_BUDGET_MIN
   2 ${WRAP_LIVE_BUDGET_COMMITS
   2 ${WRAP_LAND_INFLIGHT_LIB
   2 ${WRAP_GATE_GREEN
   2 ${WRAP_DOD_FILE
   2 ${WRAP_
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -niE 'kill|disabl|switch|opt.?out|=0 ' $F | head -40; echo ---; grep -nE 'WRAP_(GATE_GREEN|LIVE_ADDS_MAX|LIVE_STALE_MAX|LIVE_BUDGET|LIVE_REPO|LIVE_ROOT|DOD_FILE|DOD_DIR|TIMEOUT_BIN|LIVE_TIMEOUT_S)' $F | head -40", "description": `
   → 52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOCKED=0 + BLOCKED_SRC=error. An unresolvable sensor NEVER manufactures a
70:#   YOURS=0 + YOURS_SRC=none and the rung stays ✅ — an unknown session NEVER manufactures a 👤.
2
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n '176,192p;270,285p;372,382p;1150,1162p;1270,1312p;2125,2140p' $F; echo ---; grep -noE '\\$[A-Z][A-Z0-9_]+' $F | awk -F: '{print $2}' | sort -u | tr '\\n' ' '", "description": "Read switch contexts and list all vars"}`
   → #   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (se
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'WRAP_CACHE\\b|WRAP_CACHE[^_]|WRAP_RESIDENT[^_]|WRAP_BUSY[^_]|WRAP_PROJECT_ROOTS|DRAIN_SCOPE' $F; sed -n '383,420p' $F", "description": "Trace WRAP_CACHE usage and cache gating"}`
   → 185:#                    WRAP_GOAL_TIMEOUT_S · WRAP_PROJECT_ROOTS ·
186:#                    WRAP_RESIDENT · WRAP_RESIDENT_TIMEOUT_S · CC_WF_TEAM_ROOTS ·
188:#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh; sed -n '760,776p;1120,1135p;2140,2175p' $F", "description": "Read timeout seam, resident header, busy section"}`
   → # fail-open default that mimics the healthy state is unfalsifiable by its own output (MEMORY.md
# fail-safe-default-mimics-the-healthy-state): before this, a bounded run and an unbounded one were
# byte-identical in every surface this script emits, which is why the degradation ran unseen.
# Seam: WR
7. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r4 && cat > /tmp/tokeff-regate/f2/out/B10-r4/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\nMethod: grep for every `${VAR:-...}` default `
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r4/answer.md", "headline": "wrap-ledger.sh has 3 kill switches (found by grep and reading each hit). WRAP_CACHE (line 379; off, 0 or no) turns off the TMPDIR memo cache for both reads and writes. WRAP_RESIDENT (line 1160; only the literal \"off\") skips`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
