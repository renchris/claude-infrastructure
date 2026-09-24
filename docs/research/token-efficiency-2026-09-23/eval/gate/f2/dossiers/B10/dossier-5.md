# Dossier 5

## Brief
```
In /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has 3 kill switches: WRAP_CACHE at line 379 (off/0/no turns off the memo cache read and write), WRAP_RESIDENT at line 1160 (only literal "off"; skips the resident-member check) and WRAP_BUSY at line 2137 (only literal "off"; skips the busy/idle and permission-pending probe). Counted by grep and by reading each in context.

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches / off-switches in scripts/wrap-ledger.sh

File: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).

Method (measured): `grep -nE '\$\{?WRAP_[A-Z_]+|[Kk]ill.?switch|:-on\}'`, a grep for `"off"`/`off|`/`:-1}`/`disable`,
and a list of every `${VAR` env reference in the file, then reading each candidate in context.

**kill_switches = 3**

| # | Variable | Line | Test as written | What it turns off |
|---|----------|------|-----------------|-------------------|
| 1 | `WRAP_CACHE` | 379 (documented at 276, 279-281) | `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` | The memo cache for the ledger. Blanking `WL_TRANSCRIPT` means the `[ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]` block at line 380 never builds a cache key, so the cache is never read or written. The header at line 276 says: "Kill switch: WRAP_CACHE=off\|0\|no => never read, never write (the benchmark's control arm)". The transcript used as an input is copied to `GOAL_TRANSCRIPT` at line 285, before the blanking, so the switch does not change the ledger's content. |
| 2 | `WRAP_RESIDENT` | 1160 | `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | The resident-team-member check in `count_resident_members()`, called at line 2016. When it is off, the function skips the `ps` scan and the per-member `session_dirty_mine` probe, so `RESIDENT_MINE` stays 0 and `RESIDENT_SRC=none`. The rung arm at line 2017 (`RESIDENT_MINE -gt 0`) then never fires. |
| 3 | `WRAP_BUSY` | 2137 | `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | The WORKING vs IDLING section (the `session_busy_live` probe through `hooks/lib/session-busy.sh`, plus the `sb_permpend` permission-pending probe). When it is off, the defaults from lines 2133-2134 stay in place: `BUSY=0`, `BUSY_STATE=UNKNOWN`, `BUSY_SRC=none` and `PERMPEND=0`. |

## The accepted values differ between the switches

- `WRAP_CACHE` is the only one that accepts `off`, `0`, `no`, `OFF` or `NO`.
- `WRAP_RESIDENT` and `WRAP_BUSY` are tested only against the literal lowercase `off`. Setting them to `0`, `no` or `OFF` does **not** disable their sections. All three default to `on`.

## Not counted (they are not on/off switches)

- `WRAP_*_TIMEOUT_S` (lines 710, 796, 883, 958, 1063/1081, 1182/1245/1265, 1536-1861, 2144), `WRAP_CACHE_WAIT_TRIES`/`_MS`, `WRAP_CACHE_LOCK_STALE_S`: these are numeric bounds.
- `WRAP_LIVE_STALE_MAX` (1278), `WRAP_LIVE_ADDS_MAX` (1283), `WRAP_LIVE_BUDGET_*` (1284, 1309): these are thresholds.
- `CC_CONVICTION_EPOCH` (857): a date cutoff.
- Path and seam overrides such as `WRAP_TRUNK`, `WRAP_DOD_*`, `WRAP_GATE_GREEN`, `WRAP_LIVE_REPO`/`ROOT`, `WRAP_*_LIB`, `WRAP_TIMEOUT_BIN`, `WRAP_PROJECT_ROOTS`, `CC_*_BIN`/`DIR`, `WRAP_SESSION_ID` and `WRAP_TRANSCRIPT`: these redirect inputs and do not disable anything.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; ls -la /tmp/tokeff-gate/f2/out/B10-r1/ 2>&1; grep -nE '(:-|=)\"?(off|0|1|on)' /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh | head -80", "description": "Size file, check out dir, grep switch patterns"}`
   →     2444 /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
52:#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
53:#   unreadable store ⇒ BLOC
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\\$\\{?WRAP_[A-Z_]+|[Kk]ill.?switch|off-switch|:-on\\}' $F", "description": "Find WRAP_* env vars and kill-switch mentions"}`
   → 69:#   Session id: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable. Unresolvable ⇒
83:#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
260:#   · ABSENT KEY ⇒ NO CACHE. Not "cache with a default": no `--transcript`/$WRAP_TRANSCRIPT, an

3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE '\"off\"|=off|off\\||:-1\\}|:-on\\}|:-yes\\}|\"0\" \\]|= 0 \\]|-eq 0 \\] && return|disable' $F | grep -v '^\\s*#' | head -60; echo ---; grep -noE '\\$\\{[A-Z][A-Z0-9_]*' $F | sed 's/.*\\${//' | sort | uniq -c | sort -rn | awk '`
   → 276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
280:# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
553:  # shellcheck disable=SC
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; grep -nE 'CC_CONVICTION_EPOCH|CC_POSTLAND_DIR|WRAP_LIVE_STALE_MAX|WRAP_LIVE_ADDS_MAX|LIVE_STALE_MAX|LIVE_ADDS_MAX' $F; echo ---; sed -n 270,285p $F; echo; sed -n 374,392p $F; echo ---; sed -n 1150,1162p $F; echo ---; sed -n 2120,2160p $`
   → 851:# old rules and is judged by them (CC_CONVICTION_EPOCH, default the landing hour; `ts` on a row is
857:CONVICTION_EPOCH="${CC_CONVICTION_EPOCH:-2026-09-08T17:00:00Z}"
1278:LIVE_STALE_MAX="${WRAP_LIVE_STALE_MAX:-200}"
1283:LIVE_ADDS_MAX="${WRAP_LIVE_ADDS_MAX:-600}"
1683:      if [ "$_crc" -ne 0 ]
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 1236,1248p $F; grep -n 'count_resident_members\\|RESIDENT_SRC\" = \"none\"\\|RESIDENT_MINE\" -gt' $F | head; sed -n 2160,2175p $F; grep -n '__WRAP_\\|_WL_OFF\\|NO_[A-Z]*:-' $F | head", "description": "Check call sites and remaini`
   →     # ONLY a SHARED cwd. An owned worktree is the member's own tree and its dirt is nobody else's
    # problem to surface here; the closer already holds on it with full information.
    [ "$cwd" = "$PWD" ] || continue
    msid="$(_resident_member_sid "$pane")" || continue
    tp="$(_wl_find_transcr
6. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh; sed -n 2008,2024p $F", "description": "Read resident call site context"}`
   →     else
      RUNG="🔧"; READOUT="🔧 Loose ends — ${CUSTODY_OPEN} dispatched session(s) have NOT returned (cc-custody list --open --cwd .); await them ARMED (cc-await-ping), then collect+land and \`cc-custody return\` — or \`cc-custody abandon <token> --why …\`."
    fi
  else
  if [ -n "$TRUNK" ]; t
7. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B10-r1/answer.md", "content": "# Kill switches / off-switches in scripts/wrap-ledger.sh\n\nFile: /tmp/tokeff-gate/f2/tree/scripts/wrap-ledger.sh (2444 lines, measured with `wc -l`).\n\nMethod (measured): `grep -nE '\\$\\{?WRAP_[A-Z_]+|[Kk]ill.?switch|:-on\\}'`,`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B10-r1/answer.md (file state is current in your context — no need to Read it back)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B10-r1/answer.md", "headline": "wrap-ledger.sh has 3 kill switches: WRAP_CACHE at line 379 (off/0/no turns off the memo cache read and write), WRAP_RESIDENT at line 1160 (only literal \"off\"; skips the resident-member check) and WRAP_BUSY at line 2137 (only `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
