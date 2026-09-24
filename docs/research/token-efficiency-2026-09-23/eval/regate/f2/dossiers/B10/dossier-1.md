# Dossier 1

## Brief
```
In /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh, which environment variables act as kill switches or off-switches (a variable that, when set to off/0, disables a section or check)? For each give the variable, the line, and what it turns off. numbers: {"kill_switches": <how many>}.
```

## Returned headline
wrap-ledger.sh has three env kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the memo cache), WRAP_RESIDENT (line 1160; only "off" skips the resident-member count) and WRAP_BUSY (line 2137; only "off" skips the session-busy probe).

## Returned numbers
`{"kill_switches": 3}`

## answer.md
# Kill switches in /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh

Three environment variables act as off-switches. All three default to `on`.

| # | Variable | Line | Off value(s) | What it turns off |
|---|----------|------|--------------|-------------------|
| 1 | `WRAP_CACHE` | 379: `case "${WRAP_CACHE:-on}" in off\|0\|no\|OFF\|NO) WL_TRANSCRIPT="" ;; esac` (documented as a "Kill switch" at line 276) | `off`, `0`, `no`, `OFF`, `NO` | The ledger memo cache. It blanks `WL_TRANSCRIPT`, and the whole cache block at line 380 (`if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]`) is guarded by that variable, so the cache is never read or written. The comment calls this "the benchmark's control arm". |
| 2 | `WRAP_RESIDENT` | 1160: `[ "${WRAP_RESIDENT:-on}" = "off" ] && { RESIDENT_SRC="none"; return 0; }` | `off` only | The resident-team-member count (`count_resident_members`). The function returns early with `RESIDENT_SRC=none`, so there is no team-config lookup and no `ps` scan. |
| 3 | `WRAP_BUSY` | 2137: `if [ "${WRAP_BUSY:-on}" != "off" ] && [ -f "$_wl_sbl" ]; then` | `off` only | The session-busy probe: sourcing `session-busy.sh` and running `session_busy_live`. The BUSY/PERMPEND fields stay at their defaults (`BUSY_STATE=UNKNOWN`, `BUSY_SRC=none`). |

Only `WRAP_CACHE` accepts `0` (and `no`). `WRAP_RESIDENT` and `WRAP_BUSY` test for the literal string `off`, so setting either of them to `0` does NOT disable anything.

## Not counted, and why
- `DRAIN_SCOPE` (line 942: `[ "${DRAIN_SCOPE:-0}" -eq 1 ] || ...`) looks like a switch, but it is an internal variable. Line 601 sets it to 0 and line 627 derives it from the DoD scope. It is not read from the environment, since line 601 overwrites any inherited value.
- `WRAP_TIMEOUT_BIN` (lines 763-770): setting it to a non-executable path pins "no bounder", which disables timeout bounding. That is a path seam, not an off/0 switch.
- The `*_TIMEOUT_S`, `*_MAX` and `*_BUDGET_*` variables are tuning values, not on/off switches.

Method: I read the script and grepped it for `:-on`, `off`, `:-0` and `-eq` patterns and for every `${VAR}` expansion, then read the code around each hit.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && wc -l wrap-ledger.sh && grep -nE '\\$\\{?[A-Z_][A-Z0-9_]*' wrap-ledger.sh | grep -nE 'off|=.?0|:-' | head -80; ls /tmp/tokeff-regate/f2/out/B10-r5/ 2>&1", "description": "Inspect script size and env var usage"}`
   →     2444 wrap-ledger.sh
8:278:WL_TRANSCRIPT="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
13:335:  [ "${first:-}" = "#WLKEY $WL_KEY" ] || return 1
24:376:  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
25:379:case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
29:386:    _wl_
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '(:-on|:-1\\}|off\\||\"off\"|=.?0\"? *\\]|-eq 0|:-0\\}|\\bOFF\\b|disable|kill)' wrap-ledger.sh | grep -vE '_bounded' | head -80", "description": "Find on/off style env checks"}`
   → 136:#   DESCENDS from live HEAD) or T1H (an OFF-BOX hermetic green with no on-box RED). Neither reads
276:# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
279:# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
330: 
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE 'DRAIN_SCOPE' wrap-ledger.sh | head; sed -n 270,282p wrap-ledger.sh; sed -n 374,384p wrap-ledger.sh; sed -n 1150,1162p wrap-ledger.sh; sed -n 2125,2150p wrap-ledger.sh; grep -oE '\\$\\{[A-Z_][A-Z0-9_]*' wrap-ledger.sh | sort | uniq -c | `
   → 597:# captures (the same line hooks/dod-persist.sh:210 injects as "THE CURRENT CONTRACT"). DRAIN_SCOPE=1
601:DOD_SCOPE=""; DRAIN_SCOPE=0
627:case "$DOD_SCOPE" in *[Bb][Aa][Cc][Kk][Ll][Oo][Gg]*|*[Dd][Rr][Aa][Ii][Nn]*) DRAIN_SCOPE=1 ;; esac
923:# CLOSE_FLOOR=1 ⇒ this session's CURRENT CONTRACT is abou
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && grep -nE '\\$[A-Z][A-Z0-9_]*\\b' wrap-ledger.sh | grep -oE '\\$(WRAP|CC)_[A-Z0-9_]*' | sort -u | tr '\\n' ' '; echo; sed -n 1270,1312p wrap-ledger.sh; grep -niE 'seam|=off|=0 ' wrap-ledger.sh | head -30", "description": "Check threshold vars and `
   → $CC_BACKLOG_BIN $CC_CUSTODY_BIN $CC_DECIDE_BIN $CC_MIGRATIONS_STATE $CC_WF_PSTABLE_FILE $WRAP_LIVE_REPO $WRAP_SESSION_ID $WRAP_TIMEOUT_BIN $WRAP_TRANSCRIPT 
# ── LIVE LAYER — the ENFORCING store, one edge past trunk (the 🚀 rung; see the header) ──
LIVE_REPO="${WRAP_LIVE_REPO:-$HOME/Development/claud
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/scripts && sed -n 178,192p wrap-ledger.sh; sed -n 760,780p wrap-ledger.sh; grep -nE 'WRAP_RESIDENT[^_]|WRAP_BUSY[^_]' wrap-ledger.sh", "description": "Read header seams and timeout seam"}`
   → #   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (see compute_live_layer).
#
# Env seams (tests): WRAP_TRUNK (the repo-local, non-test seam is `git config claude.trunk`) · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
#                    WRAP_
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B10-r5 && cat > /tmp/tokeff-regate/f2/out/B10-r5/answer.md <<'EOF'\n# Kill switches in /tmp/tokeff-regate/f2/tree/scripts/wrap-ledger.sh\n\nThree environment variables act as off-switches. All three default to `on`.\n\n| # | Variable | Line | Off value`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B10-r5/answer.md", "headline": "wrap-ledger.sh has three env kill switches: WRAP_CACHE (line 379; off, 0 or no turns off the memo cache), WRAP_RESIDENT (line 1160; only \"off\" skips the resident-member count) and WRAP_BUSY (line 2137; only \"off\" skips th`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
