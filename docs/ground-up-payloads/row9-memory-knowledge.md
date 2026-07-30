YOUR TASK — a from-first-principles GROUND-UP rebuild of ONE subsystem: memory & knowledge (row 9) —
what survives sessions. You were fired by the ground-up campaign coordinator.

Scope (frozen): durable knowledge earned in one session is still READABLE by the next one — persisted
under the anti-capture rules, and reachable within whatever budget the reader actually loads. Measured,
landed, and verified by disk-truth acceptance reads.

STEP 0 — ARM YOUR WAKE PATH FIRST, BEFORE ANYTHING ELSE. Run this as a Bash tool call with
run_in_background=true, substituting YOUR OWN pane uuid from `~/.claude/bin/cc-notify --self`:
  ~/.claude/bin/cc-await-ping <YOUR-PANE-UUID> --timeout 14400 --interval 15
**RE-ARM IT AFTER EVERY WAKE — it is single-shot, and one wake makes you deaf.**
🚨 **USE THE PANE UUID, NEVER YOUR SESSION ID.** `cc-await-ping` accepts a session id without
complaint, but mailboxes are keyed on PANE uuid, so a session-id watcher polls a file that will never
exist and blocks its whole timeout on a void (backlog `6fe942c0eee5`; the tell is an ABSENT `.seen`
cursor, not `seen=0`). **This is measured, not hypothetical: a census found 4 of 13 armed watchers
fleet-wide on session-id keys, including BOTH live rebuild rows — each had armed a watcher and still
had no wake path.** Why it matters to you specifically: `mailbox-drain.sh` is wired to **SessionStart
and UserPromptSubmit ONLY** (verified by parsing all five live `settings.json`), both session- or
human-gated, so a row inside an hours-long autonomous turn drains at NEITHER and never sees
coordinator mail. My rulings reach you through the watcher you arm here, or not at all. Verify it:
after arming, confirm `~/.claude/mailbox/<YOUR-PANE-UUID>.md` is the path being watched.

STEP 1 (one short command): arm your standing goal so you drive to DONE across recycles —
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): row 9 memory & knowledge — durable knowledge
  survives and stays READABLE within the reader's real budget, under anti-capture hygiene, proven by
  disk-truth reads. Rebuild per skills/ground-up/SKILL.md."
  NOTE: earlier payloads on this campaign said to run "/goal ...". THAT COMMAND DOES NOT EXIST —
  verified absent from all five config dirs, and it silently did nothing for every row that ran it.
  dod-persist.sh is the real mechanism (a symlink into the checkout, so it is live) and its output is
  what SessionStart re-injects.

STEP 2: run /ground-up memory-knowledge. Before any other tool call, READ: GROUND_UP_REBUILD_MAP.md
row 9 + the "What DONE means" ruling + the unowned-surface rulings register + the four most recent
Learnings · skills/ground-up/SKILL.md · docs/plans/LAND_PIPELINE_V2.md (exemplar) ·
docs/plans/SESSION_LIFECYCLE_V2.md (row 2 — the strongest exemplar of a cell falsification done right)
· docs/plans/OPERATOR_SURFACE_V2.md (row 10 — its alarm-polarity learning is load-bearing for you).

[locate] your own worktree on branch gu-memory-knowledge (base origin/main) of claude-infrastructure.
Commit ONLY here — NEVER in the shared checkout.

🚨 THE ONE HAZARD THAT MAKES THIS ROW DIFFERENT 🚨
YOUR SUBJECT IS AN UNTRACKED, APPEND-ONLY STORE WITH NO UNDO. `MEMORY.md` and **127 topic files** live
under `~/.claude-secondary/projects/<slug>/memory/` and are tracked by NO repository — git cannot
restore them. Therefore:
  · NEVER overwrite, truncate, reorder or `mv -f` any memory file. The global rule is INTEGRATE-only,
    and this exact class of mistake already destroyed 1,461 lines once (memory
    `append-only-store-safety-rules`: "archive never delete" is a property of the DESTINATION).
  · Exercise every compaction/dedupe/archive path against a COPY in your own temp dir. Never point a
    dry-run, probe, or "just checking" invocation at the real store — not even with a flag you believe
    is read-only.
  · Before any command that could mutate the store, say out loud which directory it targets.
  · The same applies to `skills/` and to other projects' memory dirs — there are memory stores for
    many projects under `~/.claude-secondary/projects/`, and you own the MECHANISM, not their content.

YOU OWN: `hooks/memory-nudge.sh` semantics, `commands/compact-memory.md`, `commands/harvest-skill.md` +
`hooks/harvest-skill-end.sh`, `commands/evolve-skill.md`, `scripts/find-plan.sh`, the plan-history
tooling in your graveyard slice, the anti-capture ruleset, and the memory-index READ BUDGET contract.
The hooks are **PRE-RULED YOURS** so you do not spend a round trip asking (the same pre-emptive ruling
given row 7 for `bin/cc-route` and row 11 for `hooks/worktree-setup.sh`): the map's deciding test is
EFFECT — the effect is *durable knowledge is persisted or lost*, which is your subsystem verbatim —
plus the binding row-2 precedent that row 6 owns hook DISPATCH and permission rails, NOT an individual
hook's semantics.
SEAMS NOT YOURS, and two of them will bite if you assume otherwise:
  · **`hooks/dod-persist.sh` is ROW 8's** — named verbatim in row 8's core-surfaces cell, and **row 8
    is IN FLIGHT right now**. Do not touch it. If you need something from it, ping me.
  · **The Context Stewardship constants in the global `CLAUDE.md` are ROW 8's** by a binding ruling in
    the register. You may edit the **Memory Hygiene / anti-capture** section; you may NOT restructure
    the file or touch row 8's sections, the worktree section, or the session-close section.
  · Landing is row 1's. Hook DISPATCH and permission rails are row 6's (scheduled LAST).
Any other seam dispute: ping the coordinator, never decide alone.

🚨 STRUCTURAL FACT #1, AND IT REDEFINES WHAT "LANDED" MEANS FOR YOU — YOUR SUBSYSTEM SPANS THREE
STORAGE DOMAINS AND ONLY ONE OF THEM IS LANDABLE HERE. All three verified this session:
  (1) **The memory store is untracked by any repo.** `git ls-tree -r origin/main` matches **zero**
      paths under a `memory/` directory (positive control: `commands/compact-memory.md` does match, so
      the selector works). The content lives only on this disk.
  (2) **The session index/search lives in a DIFFERENT REPOSITORY.** `~/.claude/bin/claude-search` is a
      symlink to `~/Development/claude-session-search/bin/claude-search`. It is not in
      claude-infrastructure at all, so this campaign's `/ship` cannot land a change to it. (Context:
      56 of 60 entries in `~/.claude/bin` are symlinks into the checkout and DO go live on the trunk
      fast-forward — this one points somewhere else entirely.)
  (3) **The mechanisms ARE tracked here**: `hooks/memory-nudge.sh`, `commands/compact-memory.md`,
      `commands/harvest-skill.md`, `hooks/harvest-skill-end.sh`, `commands/evolve-skill.md`,
      `scripts/find-plan.sh` — all verified present on origin/main.
  **SCOPE BOUND, binding:** your DoD may only require landing in claude-infrastructure. Work that
  belongs in `claude-session-search`, or a one-time repair of the untracked store, is a NAMED
  REMAINDER — platter'd with the exact command for its owner — never a blocker on your DONE. Say in
  your plan which domain each change lands in. Related known gotcha you inherit: `~/.claude/CLAUDE.md`
  is **NOT** a symlink into the checkout (it is a separate real file), so landing the repo copy changes
  nothing any running session reads — the same edit must be applied to the live copy, and your plan
  must say so or the change is inert by construction.

🚨 STRUCTURAL FACT #2 — YOUR HEADLINE TAKE, AND IT IS ROW 10'S RATIFIED LEARNING IN A NEW SURFACE.
**The only memory mechanism wired into the live loop is a modulo counter that never measures its
subject.** `hooks/memory-nudge.sh` is 44 lines, registered on **UserPromptSubmit only** (verified in
three config dirs), and its entire logic is `[ $((COUNT % INTERVAL)) -eq 0 ]` with
`INTERVAL=${MEMORY_NUDGE_INTERVAL:-12}` — then it emits a **fixed string**. It never stats `MEMORY.md`,
never reads the store, and takes no input from the subject it nudges about. The string it emits even
says *"If MEMORY.md is past its load warning, run /compact-memory first"* — delegating the measurement
to the model's judgment, unconditionally, every 12th prompt. **Nothing anywhere in the repo measures
the index against its limit** (I grepped for the limit as a symbol and as a number across
hooks/ bin/ scripts/ commands/ skills/; the only hits were prose). Row 10's learning applies verbatim:
*an alarm that ALWAYS fires and an alarm that CANNOT fire are the same alarm — both carry zero bits.*
Do not take my framing as your design; derive your own. But do not re-discover the fact.

🚨 STRUCTURAL FACT #3 — THE CONDITION IS LIVE, RECURRING, AND THE LEDGER HAS CLOSED IT TWICE.
I am deliberately NOT giving you the byte count, because it decays within the hour — derive it:
  M=~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory/MEMORY.md
  wc -c "$M"        # vs the ~24.4KB read limit the backlog items name
  ls ~/.claude-secondary/projects/*/memory/*.md | wc -l
What is durable is the SHAPE, and it is the whack-a-mole signature: **two separate backlog items have
been opened and marked `done` for the same recurring condition** — `f71311d9ad79` ("MEMORY.md is
23.3KB vs a 24.4KB read limit — compact to <17.1KB") and `b0d889846885` ("MEMORY.md at 24.1KB
read-limit"), both status `done` — **and when I measured during this composition the file was over the
limit again, roughly an hour after a manual partial reclaim.** So the index tail is being silently
truncated at session start, right now, which means the newest learnings — including several landed by
this campaign today — are invisible to every session that starts. Two consequences worth designing
against: the remedy's effective half (`/compact-memory`'s dedupe/archive) is HUMAN-GATED, so the
condition regenerates faster than the loop that closes it; and **your own map cell cites
`b0d889846885` as "compaction backlogged" when that item is CLOSED** — a cell citing a closed item as
the reason its row is open. Correcting the cell is in scope. Memory
`memory-index-compaction-economics` and `whack-a-mole-means-file-systemic-fix` are the prior art;
re-measure both rather than inheriting them.

PHASE 1 IS NOT OPTIONAL — three checks BEFORE you design anything:
  (a) RE-DERIVE YOUR ROW'S STANDING-CONSTRAINT CELL from primary disk truth. The cell reads
      "anti-capture hygiene; index at read-size limit". It is the PRIOR SESSION'S HYPOTHESIS, and on
      this campaign such cells have been falsified or renamed more often than confirmed (rows 2, 5, 8,
      10, 12, 13 — six of eight closed rows). Ask specifically: is the binding failure the index SIZE,
      or is it that **nothing measures it**, or is it that **the writer's incentives and the reader's
      budget are set independently**? Test the anti-capture half too — sample real topic files against
      the SKIP list rather than assuming compliance. State plainly in your plan whether you killed,
      confirmed, or renamed the cell; a rename is a first-class outcome here.
  (b) CHECK ACTIVATION/DEPLOY TRUTH for every mechanism your metric depends on. Derive, never inherit
      — every carried number on this campaign has decayed within the hour:
        git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main   # deploy lag
        for f in ~/.claude/autonomy/pending-activation/*-activate.sh; do \
          [ -e "$f.done" ] || echo "UN-RUN $(basename "$f")"; done
      Lag is a SAWTOOTH, not a state (GROUND_UP_DISPATCH.md explains why). Prefer an EFFECT-READ over
      the count: for a per-file symlink into the checkout, landing IS deploying — check each file you
      touch, because `~/.claude/CLAUDE.md` is the known real-file exception above. Row 4's session-beat
      oracle is verified INERT (no `~/.claude/cc-beats`, activation `.done` absent). Consume anything
      you depend on FAIL-SOFT and say what your design does when the dependency is dark.
  (c) SWEEP THE BRANCH GRAVEYARD before you build. **Your slice, which I re-verified myself this
      session rather than trusting the campaign table:** `scripts/prune-plan-history.sh` and
      `tests/prune-plan-history.bats` are absent from trunk and present in `fix/infra-perfection`
      only; `tests/plan-version-sid.bats` is absent from trunk and present in **BOTH**
      `fix/infra-perfection` and `tm/hygiene` — **a correction to the campaign table, which shows "—"
      for your `tm/hygiene` column.** Take from `fix/infra-perfection` with `cherry-pick -x`. Do NOT
      treat the cherry-pick as the fix; a stranded suite is evidence a fix was never landed, so
      establish what it guards and whether that hole is still open.
      GIVE THE SWEEP A POSITIVE CONTROL — and read the two laws about controls in the traps below,
      because the naive version of this control provably does not work on this repo.

FIVE HARNESS TRAPS — each produced a WRONG VERDICT for someone on this campaign today:
  · **zsh eats `:t` / `:h` in `"$var:path"` as a glob MODIFIER, manufacturing false absences.**
    `"$b:tests/foo"` parses `:t` as the history TAIL modifier → basename($b) + `ests/foo` → git fatal
    rc=128 → and under the `2>/dev/null` that every sweep applies **that is indistinguishable from
    "file absent."** The two worst-hit prefixes are this repo's two most common: `tests/` (`:t`) and
    `hooks/` (`:h`). SAFE: `"$b:$p"` (colon followed by `$`), or `git ls-tree "$b" -- "$p"`, which is
    what I settled your slice with. The coordinator published a false correction to the graveyard
    table on this bad reading and had to retract it.
  · **TWO LAWS ABOUT CONTROLS, and they are halves of one thing.** (i) *A control must be able to fail
    the same way.* A positive control did NOT catch the zsh trap because its path began with `bin/`
    and `b` is not a modifier letter — so make your control share the first path segment's initial
    letter with the paths under test. Mine did: `scripts/find-plan.sh` for the `s`-paths,
    `tests/no-such-suite.bats` for the `t`-paths. (ii) *A control DECAYS on the next commit to the
    code it guards* (row 10's finding): pin the unfixed shape by what the FIX ADDS, not only by what
    the bug contains, and when a control starts failing suspect the CONTROL first — then fix it by
    making it STRICTER, because the loose version is what was hiding the defect.
  · NEVER pipe a test run into `tail`/`head` and read the exit code — that is the PIPE's status. It
    reported a clean exit 0 over two RED tests. Redirect to a file, read `$?` unpiped, and key the
    verdict on the `not ok` COUNT — **but reconcile the `1..N` header too**: row 8 hit a 164-test run
    that exited 124 with 11 tests NEVER RUN, which a not-ok count alone reads as green. A missing
    verdict is a THIRD state, not a pass.
  · A suite that tests a WRAPPER must not inherit that wrapper's env (`bin/cc-bats` exports
    `CC_BATS_ACTIVE=1` and a shim under test then short-circuits): 16/16 green plain, 14/16 through
    the shim, nothing naming the harness. Unset it in `setup()`. Also: `BATS_TEST_TIMEOUT` in
    `setup()` is a SILENT NO-OP — it is file-level only.
  · A HARDCODED DENOMINATOR is worse than a stale numerator — row 8 divided every session by a 1M
    context window when the same model also runs at 200K, rescaling three findings up to 5× while
    still printing plausible percentiles. **Your row is made of sizes and ratios** (KB per index, % of
    a read limit, entries per file, tokens per session start): name the denominator for every one and
    prove the system RECORDS it. Row 8's row-defining finding was that the denominator it needed is
    discarded — check yours is not.

DoD (all four, or you are not done):
1. `docs/plans/MEMORY_KNOWLEDGE_V2.md` with the four load-bearing sections — measured constants WITH
   citations, failure-mode table (every observed mode → its structural answer), rejected alternatives
   with reasons, acceptance criteria as disk-truth reads.
2. Adversarially proven to the skill's Phase 4 bar: RED-proof every new test against a pristine
   pre-change tree recovered via `git archive`; a positive control beside every absence assertion, per
   the two laws above; `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts under
   `/bin/bash` (the Bash tool runs zsh, so repros lie). Run gate corpora through `bin/cc-bats` — the
   box is shared with other live rebuilds. Store-mutating tests target a COPY only (hazard block).
3. Landed via the project-local `/ship` CONTINUOUSLY — never batch. Never add corpus work to the land
   path. RESOLVE CITED SHAS AFTER LANDING from origin/main via
   `git merge-base --is-ancestor <sha> origin/main` — ship-land rebases, so a local sha reads
   NOT-ancestor while its content is unambiguously on trunk. Do NOT edit tracked files while a
   ship-land is in flight; it rebases and refuses on a dirty tree, and the error names a "conflict"
   that is really a dirty-tree precondition. **Never pipe `ship-land.sh`** — the pipe's exit code
   masks a dropped land, and content-verify on `origin/main` afterwards either way.
4. `GROUND_UP_REBUILD_MAP.md` row 9 updated with status + plan link + landed shas, landed too —
   including the stale `b0d889846885` citation in your own cell.

CONSUME OTHER ROWS' MECHANISMS FAIL-SOFT. DONE on this map means designed + landed + proven +
activation STAGED AND PLATTERED — it does NOT mean live. Assume anything you depend on may be
landed-but-inert, degrade cleanly, and say in your plan what your design does when the dependency is
dark. Check for existence evidence; never trust a status cell. **And if you stage an activation, commit
it to the repo SSOT as well as the live queue** — an untracked live-only activation script is one `rm`
from unrecoverable, and a sibling row's DONE is blocked on exactly that gap right now.

Every new mechanism ships with an env kill switch, never revert-as-plan. Ping me
(cc-notify 71B42B48-1331-4F60-8DA3-6849F2682CA2) at Phase 1 close, on any seam question, and at DONE
with your landed shas.
