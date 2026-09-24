# Dossier 8

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379, off/0/no turns off the machine-mode memo cache), WRAP_RESIDENT (line 1160, off turns off the resident-teammate RESIDENT_MINE check) and WRAP_BUSY (line 2137, off turns off the session-busy/permission-pending probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in scripts/wrap-ledger.sh

There are **3** environment-variable kill switches. Each defaults to `on` and turns off one section or check.

| # | Variable | Line | Test | What it turns off |
|---|---|---|---|---|
| 1 | `WRAP_CACHE` | 379 (documented at 276, 280) | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The per-transcript memo cache for `--machine` mode: it neither reads nor writes the cache. It blanks the cache-key transcript variable, so the `if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` cache block (line 380 on) never runs. The header calls it "the benchmark's control arm". `GOAL_TRANSCRIPT` is copied earlier (line 285) so that the goal term is not affected. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident-teammate check in `count_resident_members`: the `RESIDENT_MINE` census of team members whose process is still running. It returns early with `RESIDENT_SRC=none`, so no resident member can produce a 🔧. It only accepts the literal `off`. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The session-busy / permission-pending probe, which sources `hooks/lib/session-busy.sh` and calls `session_busy_live`. When it is off, `BUSY`, `BUSY_STATE`, `PERMPEND` and the related fields keep their defaults (`BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). It only accepts the literal `off`, and it is missing from the header's "Env seams" list (lines 181-189). |

Not counted: the timeout variables and path overrides (`WRAP_*_TIMEOUT_S`, `WRAP_CACHE_DIR`, `WRAP_SESSION_BUSY_LIB`, `WRAP_LIVE_*`, and others). They tune values or redirect paths, and none of them has an off or 0 value that disables a section.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; wc -l $F; grep -nE '(=|:-|:=)\"?(off|0|1|on)\"?|off\\b|kill.?switch|KILL' $F | grep -E '\\$\\{?[A-Z_]+' | head -80"}`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
400:      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?[A-Z][A-Z0-9_]+(:-[^}]*)?\\}?\"? *(=|!=|==) *\"?(off|0|no|OFF|1|on)\"?|case \"\\$\\{?[A-Z][A-Z_0-9]+(:-[^}]*)?\\}?\" in|kill.?switch|off-switch|=off' $F"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:ca
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -noE '\\$\\{[A-Z][A-Z0-9_]+:-[^}]*\\}' $F | sort -t: -k3 -u | awk -F: '{print $1\": \"$2}' ; echo ---; sed -n 270,285p $F; sed -n 375,382p $F; sed -n 1150,1162p $F; sed -n 2125,2140p $F; grep -n 'WRAP_[A-Z]*\\|_OFF\\|DISABLE' $F | `
   → 386: ${WRAP_SESSION_ID
946: ${CC_BACKLOG_BIN
1263: ${CC_SESSIONS_BIN
549: ${WRAP_LAND_INFLIGHT_LIB
2135: ${WRAP_SESSION_BUSY_LIB
563: ${WRAP_GATE_GREEN
688: ${SID
396: ${CC_PANE_ID
400: ${WRAP_CACHE_DIR
278: ${TRANSCRIPT_FLAG
1275: ${WRAP_LIVE_ROOT
588: ${WRAP_DOD_DIR
1315: ${CC_MIGRATIONS_STATE
175
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\"off\"|off\\)|off\\||\\boff\\b' $F | head -40; grep -nE 'WRAP_[A-Z_]+|CC_[A-Z_]+' $F | grep -E '(-eq|=) *\"?0\"?' | head"}`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
861:# `whyNotNow` (the hand-o
5. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B10-r7 && cat > /tmp/tokeff-gate/f2/out/B10-r7/answer.md <<'EOF'\n# Kill switches in scripts/wrap-ledger.sh\n\nThere are **3** environment-variable kill switches. Each defaults to `on` and turns off one section or check.\n\n| # | Variable | Line | Test |`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r7/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE (line 379, off/0/no turns off the machine-mode memo cache), WRAP_RESIDENT (line 1160, off turns off the resident-teammate RESIDENT_MINE check) and WRAP_BUSY (line 2137, off turns o`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
