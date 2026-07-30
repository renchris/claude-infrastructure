YOU ARE THE GROUND-UP CAMPAIGN COORDINATOR (recycled successor #4, pane 71B42B48 — the SAME pane,
this was an in-place --recycle, so your mailbox and watcher key are unchanged). Your predecessor
recycled deliberately while IDLE at the cap with everything landed and content-verified on trunk.
Nothing lives only in the dead context.

Scope (frozen, unchanged): drive every open row of docs/plans/GROUND_UP_REBUILD_MAP.md to DONE via
one /ground-up handoff session per row — <=2 rebuilds in flight fleet-wide (DERIVED from the map,
never recalled), fire-time account policy, every completion verified by DISK before the next fire.

STEP 1 — ARM YOUR WAKE PATH IMMEDIATELY, as a Bash tool call with run_in_background=true:
  ~/.claude/bin/cc-await-ping 71B42B48-1331-4F60-8DA3-6849F2682CA2 --timeout 14400 --interval 15
**RE-ARM AFTER EVERY WAKE — single-shot; one wake makes you deaf.**
🚨 **DO NOT ALSO ARM ONE ON YOUR SESSION ID.** Earlier briefs said to; that instruction is WRONG and
is now a filed defect (backlog 6fe942c0eee5). Mailboxes are keyed on PANE uuid, so a session-id
watcher polls a file that can never exist and burns its whole 4h timeout on a void. Verified: no
`~/.claude/mailbox/<session-id>.md` ever exists. ONE watcher, on the pane uuid.

STEP 2 — arm the standing goal. **`/goal` DOES NOT EXIST** (verified absent from all five config
dirs; every payload this campaign shipped told its row to run it and it silently did nothing). Use:
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): every open row of docs/plans/GROUND_UP_REBUILD_MAP.md driven to DONE via one /ground-up handoff session per row — <=2 in flight, derived from the map, each completion verified by disk before the next fire. Runbook: docs/plans/GROUND_UP_DISPATCH.md"

STEP 3 — READ, before any other tool call: **docs/plans/GROUND_UP_DISPATCH.md, and inside the
"Coordinator handoff state — CURRENT" section read the "DELTA from coordinator #3" sub-block FIRST**
— it supersedes everything beneath it and carries the per-row pane/session/account table. Then
docs/plans/GROUND_UP_REBUILD_MAP.md (13 rows, the "What DONE means" ruling, the unowned-surface
rulings register, and the last ~5 Learnings — they are all about instruments producing false
verdicts). Then skills/ground-up/SKILL.md (the methodology you dispatch).

WHERE YOU ARE: **8 DONE (1,2,3,4,5,10,12,13) · 2 IN FLIGHT (7, 8) · 3 OPEN (11, 9, 6).** Remaining
order: **11 · 9 · 6 last.** **YOU ARE AT THE CAP — fire nothing until in-flight drops below 2.**
Rows 7 and 8 were verified alive by transcript CONTENT and both are landing steadily; their map cells
still read `open`, which is the known fresh-fire lag, so ADD them.

ROW 11 IS FIRE-READY — the payload is composed, corrected, and ON TRUNK at
`docs/ground-up-payloads/row11-worktree-warmpool.md`. It fires on account **next3** (freed when row
10 retired; row 7 holds `next`, row 8 holds `next4`, `next2` is yours). Fire with:
  scripts/handoff-fire.sh --split-right --follow --notify-back 71B42B48-1331-4F60-8DA3-6849F2682CA2 \
    --repo /Users/chrisren/Development/claude-infrastructure --worktree gu-worktree-warmpool \
    --account <FRESH read> --prompt-file docs/ground-up-payloads/row11-worktree-warmpool.md
Re-read the account fresh at fire time. Verify engagement by transcript CONTENT, never the script's
"birth" verdict — cold --worktree fires race the prompt auto-submit.

HOW YOU TALK TO THE ROWS — AND WHY IT MOSTLY DOES NOT WORK RIGHT NOW (read this before you rely on
a single message):
  ~/.claude/bin/cc-notify <pane-uuid> "COORDINATOR: <message>"
Row 7 = `9B38FF36-4CE8-4622-9F9E-A340A4916CAA` · row 8 = `8D689C3D-C642-440A-906E-091E3663B2C8`.
🚨 **THE CHANNEL IS STRUCTURALLY ONE-WAY MID-TURN.** `hooks/mailbox-drain.sh` is wired to only
**SessionStart + UserPromptSubmit** in all five live config dirs — both session- or human-gated — so a
row inside an hours-long autonomous turn drains at NEITHER. AND both live rows armed their own
watchers on their SESSION ids, so neither has a working wake path either. Net: a ruling you send
mid-turn is **write-only**. Consequences you must internalise: `pgrep -fl cc-await-ping` proves a
watcher RUNS, never that it can fire; `verdict=delivered` from a send proves nothing; prove with
`cc-notify --receipt <uuid> <line>` and treat `seen=0` as **NOT TOLD**; and **never read a row's
silence as agreement.** Avoid backticks in message bodies (shell substitution silently drops words).
Operator fix that restores the whole loop is in the block at the end.
**OUTSTANDING:** row 7 asked whether it may add one `com.claude.relogin` row to
`launchd/fleet.manifest` (bumping row 12's hardcoded `[ $n = 21 ]` to 22). **I ruled APPROVED with
four bounds** — declare state `staged` not enabled · count bump in the SAME commit, RED-proofed,
reason in commit + plan · additive only, do not touch row 12's verdict vocabulary/schema/exclusions ·
consume the fleet alarm FAIL-SOFT since `18-fleet-activate.sh` is C10-pending. Basis: row 12's own
learning that existence evidence comes from a DECLARATION, so declaring a supposed-to-run daemon IS
row 12's design, and its "claims coverage that does not exist" exclusion does not reach a job with a
real producer and cadence. **The ruling is on disk but was still `seen=0` at recycle — RE-CHECK THE
RECEIPT and do not report row 7 as told until acked>=1.** Low risk: row 7 pre-committed to exactly
the action I approved, so silence yields the approved outcome — but that is luck, not design.

HARD-WON RULES — each has cost this campaign real work:
- **A PING IS A CLAIM.** Verify every DONE by disk: plan doc carries its four load-bearing sections,
  map row updated, claimed test counts actually present, and cited shas verified **BY CONTENT** —
  then resolve the sha from origin/main **BY SUBJECT**. Row 10's sha-drift trap: ship-land rebases, so
  `merge-base --is-ancestor` returns 1 on a local sha whose content is unambiguously on trunk.
- **GREP FOR THE SYMBOL, NEVER THE CLAIM — AND READ THE HIT.** I produced two false negatives this
  session by grepping a *paraphrase* of a claim instead of its concept. `mailbox_close_disposition`
  returns comments documenting its own absence; `cc-blockers:355` still matches the old inverted
  pattern but `:354` carries an `alarm-polarity-ok:` marker. Always pair a grep with a positive
  control — and with a NEGATIVE control (a path you know is absent) too.
- 🚨 **THE INSTRUMENT IS THE USUAL CULPRIT, AND THE SHELL CAN FABRICATE AN ABSENCE.** In zsh (the
  Bash tool's shell), `"$b:tests/foo"` parses `:t` as the history TAIL modifier → `infra-perfection` +
  `ests/foo` → git exits 128 → and under the `2>/dev/null` every sweep applies, that is
  **indistinguishable from "file absent."** `tests/` (`:t`) and `hooks/` (`:h`) are this repo's two
  most common directories. SAFE: `"$b:$p"` (colon followed by `$`), `git ls-tree "$b" -- "$p"`, or a
  hardcoded ref:path. **I published a false correction to the campaign graveyard table on this bad
  reading and retracted it** (`deabc75b`; SSOT fix `88e0d349`). Full account: GROUND_UP_DISPATCH.md
  "Method note 2" + the map Learnings. Other live instrument traps: a test run piped into `tail`
  reports the PIPE's exit code; a suite run through the wrapper it tests inherits `CC_BATS_ACTIVE=1`;
  `pgrep -f X` counts processes that merely MENTION X (I reproduced this live — it matched a bats
  suite because `tests/ship-land.bats` was in its argv, and a session whose argv carried a whole
  payload); `payload-lint` RED-flags a missing back-channel that `--notify-back` materialises at fire
  time (expected — do not "fix" it); and `sort` dies with "Illegal byte sequence" on UTF-8 unless you
  set `LC_ALL=C`.
- **TWO LAWS ABOUT CONTROLS, and they are halves of one thing.** (a) *A control must be able to fail
  the same way* — a positive control did NOT catch the zsh trap because its path began with `bin/`
  and `b` is not a modifier letter; make the control share the first path segment's initial letter
  with the paths under test. (b) *A control DECAYS on the next commit to the code it guards* (row
  10's finding, on the map): pin the unfixed shape by what the FIX ADDS, and when a control starts
  failing, suspect the CONTROL first and then make it STRICTER.
- **STOP CARRYING NUMBERS.** Deploy lag is a SAWTOOTH, not a state. Any payload field a rebuild could
  compute in one command must BE that command.
- **DERIVE IN-FLIGHT FROM THE MAP, NEVER FROM MEMORY:**
    INFLIGHT=$(git show origin/main:docs/plans/GROUND_UP_REBUILD_MAP.md | grep -E '^\| [0-9]+ \|' | grep -cE 'REBUILDING|IN PROGRESS')
  then ADD rows you fired whose cell still reads `open`.
- **THE FIRE GATE:** in-flight < 2 (derived) AND then let handoff-fire's OWN capacity gate decide. The
  runnable-threads term is ADVISORY ONLY — it duplicates that gate, is stricter, and starved this
  campaign for an hour. The gate is live and default-ON (ceiling 2.0/core) and refuses a net-new fire
  with `exit 9` BEFORE any side effect, so ALWAYS capture rc: `rc=$?; [ "$rc" = 9 ] && …`.
  `--recycle` is exempt.
- **A STALL IS NOT A DEATH.** Rows froze 20+ min and recovered alone. Require POSITIVE death evidence
  (pid gone, pane gone, registry row gone) — never re-fire on silence.
- **DO NOT EDIT TRACKED FILES WHILE A ship-land IS IN FLIGHT** — it rebases and refuses on a dirty
  tree, and the error names a "conflict" that is really a dirty-tree precondition. Commit first, then
  hands off until it prints ✓/✗. Lands are SECONDS now (pipeline v2 took the corpus off the land
  path), but land-lock contention is real and queueing behind 2-3 sibling lands is normal and
  HEALTHY. Memory files under `~/.claude-secondary/.../memory/` are NOT tracked by this repo, so they
  are safe to edit during a land.
- Commit only in this worktree (gu-coordinator on gu/coordinator). Land continuously via
  `scripts/ship-land.sh`. The stranded-sweep reporting ~150 commits across ~880 branches is peers'
  expected WIP — never cherry-pick it; only your own dropped land matters.
- **NEVER hand-patch another row's surface.** Per the row-10 precedent, a defect in a row's territory
  gets fixed by that row with the full proof bar. Rule the seam, hand over the evidence, stand back.
- Recycle at >=50% context, or earlier if idle, via
  `scripts/handoff-fire.sh --recycle --prompt-file <a brief like this one>` (--prompt-file is REQUIRED
  even for a recycle). Compose row payloads durably under `docs/ground-up-payloads/` — never `/tmp`
  (does not survive) and never under `docs/plans/` (the plan-structure hook demands `status:`
  frontmatter, which would put a non-plan into find-plan.sh --list-open).

LANDED BY COORDINATOR #3, all content-verified on trunk: `34e91fd8` row 11 payload · `deabc75b`
retraction of my own false finding · `88e0d349` zsh trap into both campaign SSOTs · `e6c93e69`
handoff delta · `d8413cbe` payload STEP 0 wake-path fix.

OPERATOR-OWNED (C10, classifier-blocked to agents) — re-surface in EVERY close block, point at the
exact command, never paraphrase. 11 activations un-run. Full block:
`~/.claude/hooks/operator-readout.sh --render`.
1. Highest leverage, verified un-run and NOT CONFIRM-gated (it dry-runs what it would reap first):
   bash ~/.claude/autonomy/pending-activation/10-lead-crash-orphan-close-activate.sh && touch ~/.claude/autonomy/pending-activation/10-lead-crash-orphan-close-activate.sh.done
   Arms LCW_ORPHAN_CLOSE=1, switching on `cc-teardown --assignee-of` (whose own census found 134/134
   assignee panes carry no registry row). Three independent row-2 findings converge on this step.
2. **NEW — restores the coordinator→row channel** (see the one-way-channel block above):
   CONFIRM=1 bash ~/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh
3. Account `next` hits a LOGIN CLIFF at 2026-08-02T20:21Z (~90h from 19:45 on 07-29) and six
   refreshes provably do not move that wall, so it needs an interactive login: `cc-relogin next`.
   Read it off `claude-accounts --relogin-status`; `--login-status` returns EMPTY at rc=0 because a
   `login_warn_h` filter caps it at 72h, and the default view's `↻week` column is a QUOTA reset, a
   different axis entirely.
4. `MEMORY.md` had grown past its 24.4KB load limit, silently hiding six of today's learnings
   including row 10's. I reclaimed 1,498 bytes by shortening over-long index lines losslessly (detail
   already lives in the topic files) — every entry loads again, but headroom is only ~105 bytes, so
   the next entry re-hides the tail. The structural fix is `/compact-memory`, whose archive/dedupe
   half is human-gated: operator's call.

KEEP VISIBLE, DO NOT DO YOURSELF: the first GREEN postland stamp (0 of 33 ever; cc-backlog
da18f179ac50, already owned — do not reopen). The six suites failing in 18 of 33 stamps —
deploy-parity · desk-arm-live · desk-recycle-durable · lr-team-audit · session-continue ·
waiting-recycle — three of which are row 8's surfaces; row 8 has been told. R-1 install.sh launchd
safety (c13dad7d5dbe) is backlog, NOT a campaign row. Row 10's two closing seams: R-1
alarm-polarity-lint wants a blocking diff-scoped run_gate slot (row 1's `scripts/ship-land.sh`), R-2
`operator-readout` is registered in 4 of 5 config dirs and no alarm covers a hook's own wiring
(row 6's).
