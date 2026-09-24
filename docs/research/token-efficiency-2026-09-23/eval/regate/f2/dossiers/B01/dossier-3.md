# Dossier 3

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, always by emitting decision:block JSON and never by exit 2: an armed continuation sentinel (:1334/:1336, capped by CLAUDE_CONTINUE_MAX), the mechanical 🔧 arm for this session's own uncommitted files (which feeds that same path; off with CC_MECH_CONTINUE=0), the ship floor on 📦 and 🚀 (:1199; off with CC_SHIP_FLOOR=0), and the wake floor (:895; off with CC_WAKE_FLOOR=0), and a kill phrase in the last user message disarms all of them.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: every condition under which the Stop hook blocks

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).

The hook blocks only by printing `{"decision":"block",...}` JSON and then exiting 0. It never exits 2 in Stop mode. The exit-2 paths at :116 (`--why`) and :130 (`set|clear|status` with the lib missing) are CLI-mode errors and do not block a stop. At most one JSON object is emitted per Stop. With no sentinel file, the floors run in this order: mechanical arm → ship floor → wake floor (:1207-1226).

## Conditions (5)

| # | Emit line | Trigger (one sentence) | Disable / kill switch |
|---|---|---|---|
| 1 | **:1334 / :1336** (`mark_blocked continue` :1331) | **Armed continuation.** A sentinel for this cwd exists, because the agent ran `session-continue.sh set` or the mechanical arm (#2) armed it. The last user message has no kill phrase. The stored arming sid matches this session's sid, or either sid is unknown. `.count` is below the cap. The hook then blocks with "🔧 Loose ends remain" and the next step. :1334 is the same block with pending peer mail folded in and a `systemMessage` added. | `session-continue.sh clear`; a kill phrase in the last genuine user message (`KILL_RE` :350, checked at :1231: "…and stop", "no auto-continue", "just do X", "stop here", "come back to this", bare "stop"/"halt"); a sid mismatch clears it (:1248); the cap `CLAUDE_CONTINUE_MAX` (default 8, :1257), which allows the stop once `.count` ≥ MAX. `CLAUDE_CONTINUE_MAX=0` effectively disables the arm. |
| 2 | arms at :1073-1080 (`mechanical_arm` :940, called :1209), then emits via :1336 | **Mechanical 🔧.** There is no sentinel. `wrap-ledger.sh --machine` reports `RUNG=🔧`. `session_dirty_mine` attributes at least one uncommitted dirty file to this session's own transcript edits. The per-session mechanical budget (`${f}.mech`) is below `CC_MECH_MAX`. The hook then writes a "commit the N file(s) you edited" sentinel and falls through into the armed path, so it also passes #1's kill-switch, SID-BIND and cap checks. | `CC_MECH_CONTINUE=0` (:941); `CC_MECH_MAX` (default 2 arms/session, :1055); kill phrase (:953); a confirmed or argv-only team assignee and a fresh teardown marker both abstain; `clear` spends the mech budget outright (:261); plus everything in #1. |
| 3 | **:1199** (printed :1212, `mark_blocked ship-floor` :1211) | **Ship floor, 📦.** There is no sentinel and the mechanical arm did not arm. The ledger rung is 📦 (committed, not landed). `session_unlanded_mine` confirms the unlanded commits contain this session's own writes. The floor has not already fired for this HEAD sha in this session, and the per-session count is below the cap. The hook then blocks with "📦 SHIP FLOOR — /ship it". | `CC_SHIP_FLOOR=0` (:1101); `CC_SHIP_FLOOR_MAX` (default 2/session, :1164); kill phrase (:1103); assignee abstain (:1105-1110); teardown marker (:1111); it fires once per HEAD sha (:1174). |
| 4 | **:1199** (same emit path as #3) | **Ship floor, 🚀.** Same preconditions as #3, except the ledger rung is 🚀 (landed, but the live layer has breached its converge budget) and `session_writes_paths` shows this session wrote something. The hook then blocks with "🚀 SHIP FLOOR — run `scripts/deploy-live.sh`". | Same switches as #3. |
| 5 | **:895** (printed :1217, `mark_blocked wake-floor` :1216) | **Wake floor.** There is no sentinel, and neither the mechanical arm nor the ship floor fired. No inbox watcher is armed (`mailbox_wake_armed` false). The pane id is valid. At least one of these holds: this is the first attempt this session (`cnt`=0), mail is pending, or open `cc-custody` rows are attributed to this pane or cannot be attributed (:805). The attempt budget is not exhausted, the TTL since the last attempt has elapsed, and there is no kill phrase. The hook then blocks with "🔔 WAKE FLOOR — arm cc-await-ping". Under a live /goal it names the `--idle-scoped` form instead. | `CC_WAKE_FLOOR=0` (:604); `CC_WAKE_FLOOR_MAX` (default 2 attempts/session, :807); `CC_WAKE_FLOOR_TTL_S` (default 600 s between attempts, :808); kill phrase (:853). It also abstains in these cases: a pane-less/headless session (`CC_PANE_ID` set, `ITERM_SESSION_ID` unset, :656); a live /goal with mail already pending; a team assignee or a fresh teardown marker (that abstain is gated by `CC_WAKE_FLOOR_TEARDOWN`, default 1, :776); no jq or no mailbox lib (:605-606). |

## Notes
- Nothing blocks if `jq` is missing, or if `continue-sentinel.sh` fails to load (Stop mode exits 0 at :130).
- Counting by arm gives 4 (armed, mechanical, ship, wake). I counted 5 because the ship floor has two distinct triggers and messages (📦 vs 🚀).
- The cap path (:1260-1269) emits only a `systemMessage` and exits 0. It is not a block.


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|decision\\|exit 2\\|emit_\\|_MAX\\|=off\\|:-' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -300", "description": "Count lines and grep block-related lines"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
32:#   (c) CAP RE-ARM — a fresh `set` resets `.coun
2. `Bash: {"command": "sed -n 300,470p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read main flow section"}`
   →       # different words even though they earn the same refusal.
      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
    else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recog
3. `Bash: {"command": "sed -n 600,1000p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read wake floor and mech arm"}`
   → <persisted-output>
Output too large (29.9KB). Full output saved to: /Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-research-tokeff-regate/ed0607b0-78b8-4497-a880-345fa565fa97/tool-results/bufurvhts.txt

Preview (first 2KB):
# re-arm rather than a treadmill.
# Seams 
4. `Bash: {"command": "sed -n 1000,1346p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read mech, ship floor, main block"}`
   →   . "$swlib" 2>/dev/null || return 1

  # Ledger first: it is the cheap read, and a non-🔧 rung ends this immediately. The bare-📦 SILENT
  # idle is no longer waved through wholesale — that is the SHIP FLOOR's bounded job below (the
  # 2026-08-10 recon convicted the old blanket refusal as the load-b
5. `Bash: {"command": "sed -n 640,700p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 700,1000p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -n 'return\\|kill_switch\\|CC_\\|block\\|if \\|fi$' | head -120", "description": "Read wake floor returns and gates"}`
   →   #
  # THE DISCRIMINATOR IS THE WRITER'S ENV, NOT THE ADDRESS'S SHAPE. The spec wrote this abstain as
  # "pane-less", i.e. an EMPTY id — and the `_ouid` guard at the top of this function already returns
  # on that. But gap 1 did not land the empty-pane fallthrough it prescribed: `cc-pane-headless
6. `Bash: {"command": "sed -n 796,896p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 925,945p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read wake floor trigger and emit"}`
   →       return 0
    fi
  fi

  # Fire on the first idle of the session, any idle where mail is actually waiting, or any idle
  # while dispatched work THIS PANE OWNS (or that nothing can attribute away from it) has not
  # returned — the originator's one job while waiting is to be wakeable. A row a s
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; grep -n '^mechanical_arm\\|^ship_floor\\|^wake_floor\\|^wf_teardown_marked\\|^if \\[ ! -f \"\\$f\" \\]\\|cust=\\|cust_mine=\\|cust_unk=' session-continue.sh; sed -n 700,720p session-continue.sh; sed -n 766,796p session-continue.sh", "description": "L`
   → 551:wf_teardown_marked() { # → 0 = a fresh teardown marker names this session
603:wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
731:  local cust=0 cust_mine=0 cust_unk=0 _cb="" _cj="" _cc="" _custmsg=""
755:      cust_mine="${_cc%% *}"; cust_unk="${_
8. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r1 && cat > /tmp/tokeff-regate/f2/out/B01-r1/answer.md <<'EOF'\n# session-continue.sh: every condition under which the Stop hook blocks\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nThe hook blocks only by printin`
   → (Bash completed with no output)
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r1/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, always by emitting decision:block JSON and never by exit 2: an armed continuation sentinel (:1334/:1336, capped by CLAUDE_CONTINUE_MAX), the mechanical 🔧 arm for this sess`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
