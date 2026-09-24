# Dossier 1

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, always with a decision:block JSON and exit 0. They are: an agent-armed sentinel under the CLAUDE_CONTINUE_MAX cap (:1334/1336); the mechanical 🔧 auto-arm when this session left its own writes uncommitted (armed :1072, CC_MECH_CONTINUE/CC_MECH_MAX); the ship floor on 📦 own unlanded commits and on 🚀 not-live (both :1199, CC_SHIP_FLOOR/CC_SHIP_FLOOR_MAX); and the wake floor when no inbox watcher is armed (:895, CC_WAKE_FLOOR/_MAX/_TTL_S). The operator kill-switch phrase overrides all of them.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks a stop

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).

The hook always exits 0 on the Stop path. It never blocks by exit code: every block is a
`{decision:"block",reason:…}` JSON object printed to stdout. The only `exit 2` paths are the CLI
modes (`--why` at :116, a missing lib under `set|clear|status` at :130, a bad `clear` flag at
:216). A missing sentinel lib on the Stop path gives `exit 0`, which allows the stop. There are
**5 blocking conditions**, and one Stop emits at most one of them.

| # | Emit line | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | **1334 / 1336** (armed path) | A continuation sentinel armed with `session-continue.sh set "<step>"` exists for this cwd, and its continuation count is still under the cap. The block feeds `🔧 Loose ends remain — Next: <step>` back to the model, with any pending inbox mail folded in (1311-1325). | `session-continue.sh clear`. A kill-switch phrase in the last user message (`KILL_RE` :348, checked at :1230). SID-BIND auto-clear when the stored sid differs from the current one (:1248). The cap `CLAUDE_CONTINUE_MAX` (default 8, :1257-1269): at the cap it clears and allows. |
| 2 | **1072** arms the sentinel; the block is emitted at **1334/1336** | **Mechanical 🔧** (`mechanical_arm`, :940): no sentinel exists, `wrap-ledger.sh --machine` reads rung `🔧`, and `session_dirty_mine` finds 1 or more uncommitted dirty paths written BY THIS SESSION. The hook then auto-arms a "commit these N files" sentinel and falls through to the armed path. | `CC_MECH_CONTINUE=0` (:941). Kill switch (:952). Per-session budget `CC_MECH_MAX` (default 2, in `${f}.mech`, :1055-1069). `clear` spends that budget outright (:260). A confirmed or undeterminable team assignee is exempt (:970-983), and so is a teardown-marked session (:985). No jq, lib or ledger means it does not arm. The armed path's own guards (1) also apply. |
| 3 | **1199** (`ship_floor`, rung 📦) | Idle with no sentinel, the ledger rung is `📦` (committed, not landed), and `session_unlanded_mine` attributes the unlanded commits to this session's own writes. It fires once per HEAD sha. | `CC_SHIP_FLOOR=0` (:1101). Kill switch (:1103). Per-session cap `CC_SHIP_FLOOR_MAX` (default 2, :1164-1180). The same-HEAD-sha latch (:1174). Assignee (:1105-1111) or teardown (:1112) exemption. Not-mine attribution or no trunk means it abstains. |
| 4 | **1199** (`ship_floor`, rung 🚀) | Idle with no sentinel, the ledger rung is `🚀` (landed but the live layer is past its converge budget), and `session_writes_paths` shows this session wrote something. It demands `deploy-live.sh`. | Same as 3: `CC_SHIP_FLOOR=0`, kill switch, `CC_SHIP_FLOOR_MAX`, the per-HEAD-sha latch, assignee and teardown exemption. |
| 5 | **895** (`wake_floor`) | Idle with no sentinel, and no inbox watcher is armed (`mailbox_wake_armed` is false) for a pane with a valid inbox id. It fires on the session's first idle, whenever mail is pending, or whenever dispatched custody rows (`cc-custody`) owned by or unattributable to this pane are open. It demands a `cc-await-ping` arm (the `--idle-scoped` form under a live /goal). | `CC_WAKE_FLOOR=0` (:604). Kill switch (:852, where it emits only a systemMessage). Budget `CC_WAKE_FLOOR_MAX` (default 2, :807/838) and backoff `CC_WAKE_FLOOR_TTL_S` (default 600 s, :808/847). It abstains for a headless or pane-less session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, :656), for a live /goal with mail pending (:697), and for a team assignee or teardown-marked session (:776-798; that abstain is itself switchable with `CC_WAKE_FLOOR_TEARDOWN=0`). No jq, mailbox lib or pane id means it allows. |

Notes
- Floor precedence when no sentinel exists (:1207-1222): mechanical 🔧, then ship floor, then wake floor. The first one that fires wins. `mark_blocked` records which arm blocked in `${f}.blocked` (:333, :1211, :1216, :1331).
- Paths that only emit a `systemMessage` do not block: the cap reached (:1266), wake floor exhausted (:842), the kill-switch wake notice (:853), and the headless or goal-live or teardown abstains with pending mail (:659, :699, :792).
- The kill switch is not an env var. It is `kill_switch_active` (:391), a regex match (`KILL_RE` :348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt") against the last non-meta user message in the transcript.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|emit_\\|decision' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -150", "description": "Count lines and find block emissions in hook"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook
2. `Bash: {"command": "sed -n 100,340p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -v '^\\s*#' ", "description": "Read CLI modes and setup (non-comment lines)"}`
   → if [ "${1:-}" = "--why" ]; then
  _wt="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/why-tier.sh"
  [ -f "$_wt" ] || { _wtt="$0"; [ -L "$_wtt" ] && _wtt="$(readlink "$_wtt")"
    _wt="$(cd "$(dirname "$_wtt")" 2>/dev/null && pwd)/lib/why-tier.sh"; }
  [ -f "$_wt" ] || _wt="${CLAUDE_CONFIG_DIR:-$HOM
3. `Bash: {"command": "sed -n 340,1346p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -n -v '^\\s*#' | awk -F: '{ $1 = $1+339; print }' OFS=: ", "description": "Read Stop-path non-comment code with real line numbers"}`
   → <persisted-output>
Output too large (29.5KB). Full output saved to: /Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-research-tokeff-regate/b7291ac9-6cfb-4ecb-b537-e7432d715c5d/tool-results/b4azxoxxz.txt

Preview (first 2KB):
340:SC_SID="${cur_sid:-?}"
341:
348:KILL_R
4. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 560, "limit": 790}`
   → 560	    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
561	    [ "$(( now - mt ))" -le "$fresh" ] 2>/dev/null || continue
562	    # A sid-keyed hit needs no ownership check — the FILENAME is this session.
563	    [ -n "$cur_sid" ] && [ "$f" = "$tdir/$cur_sid.json" ] && return 0
564	    got="$(sed -n 's/.*"
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'exit [0-9]' $F; sed -n 40,99p $F | grep -n 'CC_\\|CLAUDE_\\|kill' | head; sed -n 426,545p $F | grep -v '^\\s*#'", "description": "Find exits, global kill switches, and mailbox/goal setup"}`
   → 37:# accidental non-zero exit could force a false continuation. Every actuation path ends `exit 0`.
114:  # LOUD, never a silent exit 0 — a pointer that resolves to nothing is the defect this tier closes.
116:  exit 2
127:  # never block on error (→ exit 0 allow); a CLI mode signals the failure to t
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r4 && cat > /tmp/tokeff-regate/f2/out/B01-r4/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nThe hook always exits 0`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r4/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, always with a decision:block JSON and exit 0. They are: an agent-armed sentinel under the CLAUDE_CONTINUE_MAX cap (:1334/1336); the mechanical 🔧 auto-arm when this session`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
