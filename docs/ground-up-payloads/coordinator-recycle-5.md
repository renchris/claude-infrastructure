YOU ARE THE GROUND-UP CAMPAIGN COORDINATOR (recycled successor #5, pane 71B42B48 — the SAME pane, this
was an in-place --recycle). Your predecessor recycled deliberately at 39% while IDLE-WATCHING, with
everything landed and content-verified on trunk. Nothing lives only in the dead context.

Scope (frozen, unchanged): drive every open row of docs/plans/GROUND_UP_REBUILD_MAP.md to DONE via one
/ground-up handoff session per row — <=2 rebuilds in flight fleet-wide (DERIVED from the map, never
recalled), fire-time account policy, every completion verified by DISK before the next fire.

STEP 1 — ARM YOUR WAKE PATH. 🚨 **DO NOT HARDCODE A KEY — AND DO NOT USE THE PANE UUID.** The rule that
every earlier brief in this campaign got wrong: `mailbox-drain.sh` reads the SESSION-keyed box whenever
it knows its session id and writes a pane→session ALIAS, so **the canonical key MOVES once your pane is
drained**. Arm with the EXACT command the `🔔 WAKE FLOOR` Stop-hook message hands you (it calls
`mailbox_resolve_key` for you), as a Bash tool call with run_in_background=true. Verify with the lib,
never `pgrep`:
  bash -c '. ~/.claude/hooks/lib/mailbox-pending.sh; mailbox_wake_armed <KEY> && echo ARMED'
**RE-ARM AFTER EVERY WAKE** — single-shot. Predecessor ran ~2 h with FOUR watchers on a stale pane key
while reading UNARMED. Full account: DISPATCH "DELTA from coordinator #4" → the RETRACTION bullet.

STEP 2 — arm the standing goal:
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): every open row of docs/plans/GROUND_UP_REBUILD_MAP.md driven to DONE via one /ground-up handoff session per row — <=2 in flight, derived from the map, each completion verified by disk before the next fire. Runbook: docs/plans/GROUND_UP_DISPATCH.md"
(`/goal` DOES NOT EXIST — verified absent from all five config dirs.)

STEP 3 — READ, before any other tool call: **docs/plans/GROUND_UP_DISPATCH.md, and inside "Coordinator
handoff state — CURRENT" read the "DELTA from coordinator #4" sub-block FIRST** — it supersedes
everything beneath it and carries every finding below in full detail. Then GROUND_UP_REBUILD_MAP.md (13
rows, the "What DONE means" ruling, the unowned-surface rulings register, the last ~5 Learnings) and
skills/ground-up/SKILL.md.

WHERE YOU ARE: **9 DONE (1,2,3,4,5,8,10,12,13) · 1 IN FLIGHT (row 7) · 3 OPEN (11, 9, 6).**
Order: **11 (re-fire) · 9 · 6 last.** **In-flight is 1, so the CAP is NOT your blocker — the BOX is.**

🚨 YOUR FIRST ACTION: **RE-ARM THE ROW-11 RE-FIRE LOOP. IT DIED WITH YOUR PREDECESSOR'S SESSION.**
Row 11 died at 04:39Z with nothing landed (proven on three axes; backlog `b521cb445465`). Its payload on
trunk already carries its predecessor's Phase-1 findings, so the successor does not repeat them. The
fire is refused by the capacity gate (`exit 9`, load has been 3-6/core against a 2.0 ceiling). **Do NOT
build a load predictor — one raced and reported clear at 1.74/core when it was 2.24/core by the time it
could act.** Make the actuator the arbiter; the gate is atomic and refuses before side effects, so a
retry is free. Run this as a Bash tool call with run_in_background=true:

  cd /Users/chrisren/Development/.worktrees/gu-coordinator
  OUT=/tmp/fire-row11-b.log
  for i in $(seq 1 30); do
    bash scripts/handoff-fire.sh --split-right --follow \
      --notify-back 71B42B48-1331-4F60-8DA3-6849F2682CA2 \
      --repo /Users/chrisren/Development/claude-infrastructure \
      --worktree gu-worktree-warmpool-b \
      --account next3 \
      --prompt-file /Users/chrisren/Development/.worktrees/gu-coordinator/docs/ground-up-payloads/row11-worktree-warmpool.md \
      > "$OUT" 2>&1
    rc=$?
    if [ "$rc" != "9" ]; then echo "ATTEMPT=$i rc=$rc — ADMITTED or real error"; tail -12 "$OUT"; exit 0; fi
    echo "$(date -u +%H:%M:%SZ) attempt=$i rc=9 — refused before side effects, retrying"
    sleep 180
  done
  echo "EXHAUSTED — escalate: the box needs panes closed"

Use worktree **`gu-worktree-warmpool-b`** (the original name's branch+dir still exist, `ahead=0` and
clean — a fresh name avoids the collision with no destructive op). Account **next3** on WEEKLY headroom;
re-read fresh anyway. **Verify engagement by transcript CONTENT, never the script's `proof=marker`.**

THEN: rows 9 and 6 both have fire-ready payloads ON TRUNK
(`docs/ground-up-payloads/row9-memory-knowledge.md`, `row6-guardrail-hooks.md`) — nothing left to
compose. Fire row 9 when in-flight < 2 and the gate admits; row 6 last.

DERIVE IN-FLIGHT FROM THE MAP, NEVER FROM MEMORY:
  INFLIGHT=$(git show origin/main:docs/plans/GROUND_UP_REBUILD_MAP.md | grep -E '^\| [0-9]+ \|' | grep -cE 'REBUILDING|IN PROGRESS')
then ADD rows you fired whose cell still reads `open`, and SUBTRACT any you have proven dead.

HARD-WON RULES — the full account of each is in the DISPATCH delta; these are the ones that cost real work:
- **A PING IS A CLAIM; SO IS A MAP CELL.** Verify every DONE by disk: four load-bearing plan sections,
  map row updated, claimed test counts present, cited shas resolved from `origin/main` **BY SUBJECT**
  (ship-land rebases, so a local sha reads NOT-ancestor while its content is on trunk), and activation
  staged in **BOTH** the live queue and the repo SSOT — that last one blocked row 8's DONE until fixed.
- 🚨 **NEVER REPORT AN ABSENCE FROM A PATTERN YOU CHOSE WITHOUT FIRST PROVING THE PATTERN CAN HIT.** Your
  predecessor made **seven** selector errors, every one a confident false negative: guessed test
  filenames, greps for text it had not written, a stale mtime reported as 100 min of silence, a registry
  grep on the wrong name field, and an absence read where its OWN pane returned 0 hits. Pair every
  absence claim with a positive control that shares the first path segment's initial letter, plus a
  negative control. This is the single highest-yield rule on the campaign.
- **A STALL IS NOT A DEATH — but row 11 really died.** Require POSITIVE death evidence on three axes:
  pane absent from `it2 session list --json | jq -r '.[].id'` (with a control), no process whose **cwd**
  is that worktree (cwd, never argv — `pgrep -f` matches briefs), and no registry row. Then check for a
  successor transcript before concluding it did not recycle.
- 🚨 **NEVER PIPE `ship-land.sh`.** Run it `run_in_background=true`, unpiped, to a file, capture rc.
  Key the verdict on **per-artifact content on `origin/main` ONLY** — do NOT AND it with
  `ahead == 0`; that convicted a successful land because a later commit moved the counter.
- **THE INSTRUMENT IS THE USUAL CULPRIT.** zsh eats `:t`/`:h` in `"$b:tests/…"` (use `git ls-tree "$b"
  -- "$p"`); zsh ERRORS on an unmatched glob rather than passing it through; a piped test run reports the
  PIPE's rc; `1..N` must be reconciled or a timed-out run reads green; `pgrep` reported 0 for a watcher
  `ps` and the lib both confirmed alive.
- **DO NOT EDIT TRACKED FILES WHILE YOUR ship-land IS IN FLIGHT.** Memory files under
  `~/.claude-secondary/.../memory/` are untracked here and safe.
- **NEVER HAND-PATCH ANOTHER ROW'S SURFACE.** Rule the seam, hand over the evidence, stand back. Route
  work for CLOSED rows to the backlog, never into the closed row.
- **STOP CARRYING NUMBERS.** Deploy lag and load are sawtooths. Hand the deriving command.
- Commit only in this worktree (gu-coordinator on gu/coordinator); land continuously via
  `scripts/ship-land.sh`; content-verify after every land. Recycle at >=50%, or earlier if
  idle-watching, via `scripts/handoff-fire.sh --recycle --prompt-file <a brief like this>`.

OPERATOR-OWNED (C10) — re-surface in EVERY close block, exact commands, never paraphrased. Full block:
`~/.claude/hooks/operator-readout.sh --render`.
1. **The box is the campaign's blocker.** iTerm2 alone burns ~141% CPU (more than any Claude session);
   59 panes vs 38 registered sessions. Closing finished panes is the highest-leverage load reduction —
   but the 21 gap is an UPPER BOUND on candidates, NOT a verified kill list.
2. `bash ~/.claude/scripts/deploy-live.sh` — will REFUSE: 34 postland stamps, 0 green ever. That is the
   known deadlock (`da18f179ac50`, owned — do not reopen). Each attempt writes another page.
3. `CC_RELOGIN_WARN_H=120 cc-relogin next` — account `next` (row 7's) hits its login cliff
   2026-08-02T20:21Z. Plain `cc-relogin next` REFUSES in a 96-hour dead band (72h→168h) where
   `--relogin-status` says DUE but the tool declines: backlog `9d514681fb84`.
4. `/compact-memory` — MEMORY.md is ~730 bytes over its load limit, so its tail does not load; the
   dedupe/archive half is human-gated.

BACKLOG FILED BY COORDINATOR #4 (all with evidence): `ff839f1f8f38` cc-mail/cc-thread untracked + zero
callers · `ece77ba9dfe2` activation advertises an unlanded feature · `80321b2556e6` env-var activations
escape both health axes · `9d514681fb84` relogin dead band · `4ce34a4f703c` hook-wiring parity (row 6's
headline) · `00c8a786f8fd` wake_floor has no teardown-abstain gate · `99f87bf7a6f7` cc-teardown false
SUCCESS · `ae48044a004d` cc-teardown false FAIL · `b521cb445465` row 11's unexplained death.

KEEP VISIBLE, DO NOT DO YOURSELF: the first GREEN postland stamp (0 of 34 ever, `da18f179ac50`, owned).
Row 10's two closing seams (R-1 alarm-polarity lint wants a blocking diff-scoped run_gate slot; R-2
`operator-readout` registered in 4 of 5 config dirs — now measured: missing from `.claude-next`, which is
row 6's). R-1 install.sh launchd safety (`c13dad7d5dbe`) is backlog, NOT a campaign row.
