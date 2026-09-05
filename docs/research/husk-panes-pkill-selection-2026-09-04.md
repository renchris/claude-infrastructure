# Five panes at a bare shell were not failed self-recycles — one `pkill -f` killed five sessions

**2026-09-04 · panes 144, 290, 296, 297, 298 · claude-infrastructure + reso**

## The answer

The operator read the five panes as sessions that "attempted to self-recycle by closing but never
opening". None of them did. All five were **SIGTERMed within 30 seconds by a sibling session's
`pkill -f "cc-await-ping"`**, typed to stand down its own inbox watcher before a recycle. On this
fleet a fired session's argv carries its whole brief, and the standard `--notify-back` trailer
contains the literal string `cc-await-ping`, so the pattern selected every fired peer on the box.
Each victim printed Claude Code's ordinary `Resume this session with:` line and dropped to its shell,
which is pixel-identical to a clean `/exit`.

The same mechanism had already fired twice — 2026-08-09 (`pkill -f "next dev" -P $$`, 3 sessions)
and 2026-08-25 (`pkill -f "cc-await-ping"`, 1 session + 3 watchers) — and each time the remedy was
keyed on the **spelling** (a gate-program clause, a trailing-flag clause, a forensic si_pid
recommendation later refuted). This time the fix is keyed on the **selection**.

## The chain, from the ledgers

| time (UTC) | fact | source |
|---|---|---|
| 12:19–12:21Z | pane 290 (`53f08288`) fires three self-retiring peers into panes 296/297/298 (W2a/W2b/W3 of BACKLOG_ZERO) | `~/.claude/logs/handoffs.jsonl` `self-retire-peer` |
| 17:27Z | pane 290 recycles → `b407a42a` (engaged in 10 s) | same, `recycle-engaged` |
| 18:xxZ | 296/297/298 reach their closes ("Good to close: yes"), arm `cc-await-ping`, idle; 290 is waiting on W2a's custody ("Good to close: **no**"); W2a (296) has a `ship-land.sh` running in the background | the four transcripts' last records |
| **19:03:43Z** | session `61f95511` (pane 280) runs `kill %1; pkill -f "cc-await-ping"; echo "watcher stood down"` before its own recycle | `~/.claude/logs/bash-commands.log` |
| 19:03:45–46Z | `ae76ad98` (pane 144) and `caf50833` (298) run SessionEnd `reason=other` | `~/.claude/logs/sessions.log` |
| 19:03:50–19:04:12Z | `b407a42a`, `ca5f4d59`, `a0851085`, `caf50833` recorded `class=CRASH cause=external-sigterm exit=143 signal=15` | `~/.claude/logs/claude-crashes.jsonl` |
| 19:03:45–59Z | three OTHER sessions' watchers (269, 248, 300) die too; one of them files backlog `1da6ceee8079` naming sender pid 81199 but no command | `~/.claude/autonomy/backlog.jsonl` |
| 19:04:04–08Z | `lead-supervisor` writes `reap … clean-completion-shipped-clean-worktree` for three of them — **after** the deaths, dropping telemetry rows only (`reap_clean` never signals anything) | `scripts/lead-supervisor.sh:580`, `idl.jsonl` |
| 19:04:41Z | pane 280 recycles itself successfully | `handoffs.jsonl` |

Join over 30 days of `bash-commands.log` × `claude-crashes.jsonl`: **95 pattern-kill commands, exactly
one with a Claude death inside 90 s — this one, four victims recorded** (the fifth, `ae76ad98`, ran under
`.claude-tertiary` without a close record and shows only as `reason=other`).

## What was refuted

- **"Failed self-recycle."** Zero `recycle-dead`/`husk-pane` rows for any of the five panes. Over the
  last 7 days the recycle rail engaged 87 of 93 attempts; the one `recycle-dead` was elsewhere. The
  self-close path's `husk-pane` alarm (typed `/exit`, pane close failed 4/4) fired 0 times in 30 days.
- **"The supervisor reaped them."** `reap_clean` drops a telemetry row and clears a page; it is written
  after `work_landed` finds a DEAD pid on a clean, landed worktree. It is a *consequence* of the death.
  It also mis-filed `b407a42a` as clean completion while that session had open custody — the predicate
  reads git state, not the session's own verdict — but that is a labelling defect, not a cause.
- **"The 88 abrupt-unknown deaths are more of the same."** 68 of 88 have <40 transcript records: headless
  probes, not panes. No kill commands sit beside their clusters.

## Why nothing stopped it

`hooks/validate-bash.sh` already denied *unscoped* pattern kills — but only when the pattern named one
of three gate programs (`bats|ship-land|postland-verify`), plus a trailing-flag clause added after the
2026-08-09 incident. `pkill -f "cc-await-ping"` names none of them and carries no trailing flag, so it
passed. The auto-mode classifier allowed it too: its boundary is "the target is a live Claude session",
and the text reads as killing a watcher. MEMORY `denylist-enumerates-spellings-not-the-class` describes
exactly this shape; MEMORY `pgrep-f-matches-agent-briefs` predicted the harm on 2026-07-29.

And the session that typed it had no alternative: `cc-await-ping` had no stop verb, `--recycle` does not
stand a watcher down, and the Bash tool's job control (`kill %1`) does not span tool calls. The
improvised spelling was the only one available.

## What changed

1. **`hooks/lib/kill-selection.py` + a SELECTION-keyed clause in `hooks/validate-bash.sh`.** For any
   `pkill` / `killall` / kill-fed `pgrep` in command position, the hook asks the real `pgrep` what the
   command would select and walks each victim's ancestry. Victims under the caller's own session (OWN)
   or under no session at all (UNOWNED — Dock, a hand-started server) pass untouched; a victim that is
   another live Claude session or lives inside one (FOREIGN) is denied, with the victims named from
   `cc-registry` and the remedy stated. Dynamic patterns (`$VAR`) abstain, as before. Seams:
   `CC_KILL_SELECTION_GATE=off`, `CC_KILL_GATE_SELF_PID`, `CC_REGISTRY_DIR`. Every denial is appended
   to `~/.claude/logs/kill-selection-gate.jsonl`, so the class is countable.
   The gate's own smoke run caught a defect before it shipped: a trailing `2>/dev/null` reached pgrep as
   a second pattern and convicted nine innocent shells. Redirections are now stripped as the shell's.
2. **`cc-await-ping --stand-down`** — the actuator the denial names. Signals only the watcher pids
   recorded in this inbox's own claim files, stamps each so its TERM trap reports
   `verdict=stood-down` (rc 0, no WAKE-PATH-DOWN mail), never touches another inbox.
3. **Tests**: `tests/pkill-scope.bats` § SELECTION (real fixture processes under a fake `claude`
   argv[0]; incident shape, own-subtree pass, every actuator spelling, killall by name, text-vs-execution,
   dynamic abstention, kill switch, the audit row) and `tests/cc-await-ping.bats` § --stand-down (by
   pid, this inbox only, rc 0, no alarm mail, plus a bare-TERM control that still reads as a kill).

4. **`bin/cc-husk-sweep`** — the recovery half, for the next time this class (or any external
   kill) leaves panes at a bare shell. It enumerates every pane whose shell has no claude beneath
   it, resolves the dead session three ways in order (the surviving `cc-registry` row, which is
   present exactly when SessionEnd did not run; the pane's scrollback, honouring that a resume
   line can be CUT OFF mid-print, as pane 144's was; the newest transcript for the pane's cwd
   across the four account stores), classifies the death from the crash log and the work left
   open from git and the session's own last "Good to close:", and with `--resume` types the
   PINNED launcher (`claude3 --resume <sid>`, never the pane's printed default-account
   `claude --resume`, which cannot see another store's transcript) echo-verified into each pane.
   Measured on the live box after the operator had hand-resumed four of the five: the one
   remaining husk (pane 144) resolved to `ae76ad98` / `claude3` / DONE via the transcript path.
   `tests/cc-husk-sweep.bats` (7) pins the resolution order, the account mapping, the verdicts and
   the never-default-account rule.

## Not changed, and why

- **The husk panes themselves are not closed by anything.** A pane holding `Resume this session with:`
  is the recovery affordance for a session that did NOT choose to exit; closing it would destroy that.
  The right outcome for a killed session is a resume, and preventing the kill is the fix.
- **`lead-supervisor`'s "clean-completion" label** on a session with open custody is a separate,
  smaller defect (predicate reads git, not the session's verdict); it changes no action.
- **The five victims' work.** W2a (`a0851085`, pane 296) holds three unlanded commits on
  `feat/backlog-zero-w2a` and was mid-`ship-land` when killed; W2b, W3 and the reso session had landed.
  Pane 290's lead (`b407a42a`) was waiting on W2a's custody. Recovery is a resume of 296 then 290.

## The generalisable lesson

A guard keyed on the spelling of the last incident enumerates the incidents already paid for. The harm
here was never "the pattern said bats" or "the flag trailed the pattern"; it was "the selection reached a
process that is not yours". That predicate is decidable *before* the act, with the same tool the act
would use — so the guard should run the selection, not read the text.
