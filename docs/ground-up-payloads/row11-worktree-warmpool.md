YOUR TASK — a from-first-principles GROUND-UP rebuild of ONE subsystem: worktree & warm-pool
management (row 11) — where writers work. You were fired by the ground-up campaign coordinator.

Scope (frozen): a writer always gets an isolated, correctly-provisioned worktree, and no worktree
holding unlanded work is ever destroyed — with one named owner per artifact class, so disk drift has
a collector instead of a witness. Measured, landed, and verified by disk-truth acceptance reads.

STEP 0 — ARM YOUR WAKE PATH FIRST, BEFORE ANYTHING ELSE. Run this as a Bash tool call with
run_in_background=true, substituting YOUR OWN pane uuid from `~/.claude/bin/cc-notify --self`:
  ~/.claude/bin/cc-await-ping <YOUR-PANE-UUID> --timeout 14400 --interval 15
**RE-ARM IT AFTER EVERY WAKE — it is single-shot, and one wake makes you deaf.**
🚨 **USE THE PANE UUID, NEVER YOUR SESSION ID.** `cc-await-ping` accepts a session id without
complaint, but mailboxes are keyed on PANE uuid, so a session-id watcher polls a file that will never
exist and blocks its whole timeout on a void (backlog `6fe942c0eee5`; the tell is an ABSENT
`.seen` cursor). **This is not hypothetical — I censused it while composing this payload: 4 of 13
armed watchers fleet-wide were on session-id keys, including BOTH live rebuild rows, so both had
armed a watcher and still had no wake path.** Why it matters to you specifically: `mailbox-drain.sh`
is wired only to **SessionStart** and **UserPromptSubmit**, both session- or human-gated, so a row
inside an hours-long autonomous turn drains at NEITHER and never sees coordinator mail — my rulings
reach you only through the watcher you arm here. Verify it: after arming, confirm
`~/.claude/mailbox/<YOUR-PANE-UUID>.md` is the path being watched.

STEP 1 (one short command): arm your standing goal so you drive to DONE across recycles —
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): row 11 worktree & warm-pool — every writer
  isolated and provisioned, no worktree with unlanded work ever reaped, one owner per artifact
  class, proven by disk-truth reads. Rebuild per skills/ground-up/SKILL.md."
  NOTE: earlier payloads on this campaign said to run "/goal ...". THAT COMMAND DOES NOT EXIST —
  verified absent from all five config dirs. dod-persist.sh is the real mechanism (it is a symlink
  into the checkout, so it is live) and its output is re-injected at every SessionStart.

STEP 2: run /ground-up worktree-warmpool. Before any other tool call, READ: GROUND_UP_REBUILD_MAP.md
row 11 + the unowned-surface rulings register + the four most recent Learnings ·
skills/ground-up/SKILL.md · docs/plans/LAND_PIPELINE_V2.md (exemplar) ·
docs/plans/SESSION_LIFECYCLE_V2.md (row 2 — the strongest exemplar of a cell falsification done
right) · docs/WORKTREE_WORKFLOW.md.

[locate] your own worktree on branch gu-worktree-warmpool (base origin/main) of
claude-infrastructure. Commit ONLY here — NEVER in the shared checkout.

🚨 THE ONE HAZARD THAT MAKES THIS ROW DIFFERENT FROM EVERY OTHER ON THIS CAMPAIGN 🚨
YOUR SUBJECT IS A REAPER, AND THE BOX IS FULL OF LIVE WORK RIGHT NOW. "git worktree list" shows
~20 worktrees; several hold UNLANDED commits, including two live ground-up rebuilds and the
coordinator's own. scripts/worktree-gc.sh deletes worktrees and branches. Therefore:
  · NEVER point any test, probe, dry-run, or "just checking" invocation at a real worktree or a
    real branch. Build a throwaway git repo under your own temp dir and exercise the reaper there.
  · NEVER run worktree-gc.sh, git worktree remove, git worktree prune, or git branch -d/-D outside
    that throwaway repo — not even with a flag you believe is read-only.
  · Before any command that could mutate worktree state, say out loud which repo it targets.
  A destroyed worktree here loses another row's unlanded rebuild. There is no undo.

YOU OWN: scripts/worktree-gc.sh + tests/worktree-gc.bats, worktree provisioning, the warm-pool
SEMANTICS, and — PRE-RULED YOURS, so you do not spend a round trip asking (same pre-emptive ruling
the coordinator gave row 7 for bin/cc-route) — hooks/worktree-setup.sh (WorktreeCreate provisioner,
registered at settings-templates/settings.example.json:601) and hooks/git-worktree-guard.sh
(PreToolUse Bash/Write). Basis: the map's effect test — the effect is *a worktree is provisioned* /
*a live worktree is protected*, which is your subsystem verbatim — plus the binding row-2 precedent
that row 6 owns hook DISPATCH and permission rails, NOT an individual hook's semantics.
SEAMS NOT YOURS: worktree-gc CONSUMES hooks/live-session-registry.sh and the liveness oracles, which
are row 4's (DONE). Landing is row 1's. Claiming/creation at fire time is row 2's (DONE).
Any other seam dispute: ping the coordinator, never decide alone.

PHASE 1 IS NOT OPTIONAL — three checks BEFORE you design anything:
  (a) RE-DERIVE YOUR ROW'S STANDING-CONSTRAINT CELL from primary disk truth. The cell reads
      "107 GB observed drift; ownership per artifact-class". It is the PRIOR SESSION'S HYPOTHESIS
      and on this campaign it has been falsified or renamed more often than confirmed (rows 2, 5, 8,
      12, 13). DO NOT INHERIT THE NUMBER — I am deliberately not repeating it as fact. Derive it:
        du -sh ~/Development/.worktrees/* 2>/dev/null | sort -h | tail -25
        git worktree list | wc -l
        git -C ~/Development/claude-infrastructure count-objects -vH
      Then answer the question the number is a proxy for: WHICH ARTIFACT CLASS has no collector?
      Row 13's learning applies with full force — the named risk can be the wrong resource, and
      measuring all candidates before designing against any is cheaper than designing against a
      ghost. State plainly in your plan whether you killed or confirmed the cell.
  (b) CHECK ACTIVATION/DEPLOY TRUTH for every mechanism your metric depends on. Derive, never
      inherit — every carried number on this campaign has decayed within the hour:
        git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main   # deploy lag
        for f in ~/.claude/autonomy/pending-activation/*-activate.sh; do \
          [ -e "$f.done" ] || echo "UN-RUN $(basename "$f")"; done
      Lag is a SAWTOOTH, not a state (GROUND_UP_DISPATCH.md explains why). Prefer an EFFECT-READ:
      ~/.claude/scripts/worktree-gc.sh is a SYMLINK into the checkout, so for that file landing IS
      deploying — check each file you touch, because ~/.claude/CLAUDE.md is a known real-file
      exception where landing changes nothing a running session reads.
      Row 4's session-beat oracle is verified INERT (no ~/.claude/cc-beats, activation .done
      absent). You consume row 4 — consume it FAIL-SOFT and say what your design does when it is
      dark.
  (c) SWEEP THE BRANCH GRAVEYARD before you build. Your slice per GROUND_UP_DISPATCH.md is
      tests/git-worktree-guard.bats, marked present in fix/infra-perfection ✓ and tm/hygiene ✓.
      **THAT TABLE ENTRY IS CORRECT — I verified it with git ls-tree, absent from trunk and present
      in both branches.** Take from fix/infra-perfection with cherry-pick -x, per the standard
      campaign guidance; no override is needed for your row. The same patch also exists as
      rebase-duplicates along the nested tm/* chain (origin 12476a03, 2026-07-25 02:15 on tm/wtgc) —
      you do not need them.
        · 🚨 **READ THIS BEFORE YOU RUN ANY SWEEP — IT COST ME A FALSE FINDING THIS SESSION AND I
          ALMOST SHIPPED IT TO YOU AS FACT.** My first probe said the test was in NEITHER branch. It
          was a zsh bug, not a fact. In zsh, inside double quotes, `"$b:tests/foo"` parses `:t` as
          the **history/glob TAIL modifier**: with b=fix/infra-perfection it expands to
          `infra-perfection` + `ests/foo` = `infra-perfectionests/foo`, git fatals rc=128, and under
          the `2>/dev/null` that every sweep applies **that is indistinguishable from "file
          absent."** The two most common directories in this repo are the two worst hit —
          `tests/` (`:t` tail) and `hooks/` (`:h` head). `"$b:$p"` is SAFE (the `:` is followed by
          `$`, not a modifier letter), and `git ls-tree "$b" -- "$p"` is safe and is what I settled
          the truth with. This very likely explains the earlier coordinator's note that two of its
          three sweeps "returned confident garbage at exit 0". **Never trust a bare-absence result
          from a `"$var:path"` expression under zsh; assert your sweep re-finds a known-present file
          first, and prefer ls-tree.**
        · **THE FIX THAT TEST GUARDS IS NOT ON TRUNK — this is your headline take, and it survived
          the correction above because it was measured with commands that carry no `$var:` pattern.**
          12476a03 is
          NOT an ancestor of origin/main, and trunk's hooks/git-worktree-guard.sh has zero -C /
          target-repo / GIT_DIR handling (positive control: the same grep returns 21 branch/worktree
          hits, so the grep works). Read lines 29-48: it matches the LITERAL strings "git branch"
          and "git worktree remove", so `git -C <path> branch -D <branch>` and
          `git -C <path> worktree remove <path>` never match — and line 16 documents that it fails
          OPEN on non-match. The guard whose entire job is refusing destructive git aimed at a live
          worktree is bypassable in the -C form, with ~20 live worktrees holding unlanded work.
          The stranded suite is 6 @test cases covering exactly that bypass. It does NOT cover the
          2026-07-02 stdout-contract break that killed `claude -w` (hooks/worktree-setup.sh:21 still
          references its .bak from that day) — audit gap G-P9-9 in
          docs/research/desk-audit-2026-07-18/p09-ship-land.md:126 is a SEPARATE, still-open
          exposure. Fix both with the full proof bar; do not treat the cherry-pick as the fix.
      GIVE THE SWEEP A POSITIVE CONTROL — assert it re-finds a file you know exists before believing
      any negative. Two of the coordinator's three sweeps returned confident garbage at exit 0, and
      my own first pass on YOUR artifact returned "stranded nowhere" before an all-refs re-check
      with a control corrected it.

THREE MORE THINGS I VERIFIED THAT YOUR CELL DOES NOT SAY — confirm, do not inherit:
  · TWO OF YOUR FOUR NAMED CORE SURFACES DO NOT EXIST ANYWHERE. scripts/new-worktree.sh and
    .worktreeinclude are absent from the tracked tree, from the untracked shared checkout, and from
    the live ~/.claude layer. The global CLAUDE.md describes both conditionally ("where present",
    "on newer CC"). Decide, and say which in your plan: BUILD them, or CORRECT THE CELL. A cell that
    names phantoms is a defect in the map, and fixing it is in scope.
  · "WARM POOL BUILD" HAS NO STANDALONE ARTIFACT. The warm-pool logic lives inside
    scripts/handoff-fire.sh (row 2's file, row 2 DONE) and hooks/worktree-setup.sh. This is the
    M3 shape the map has already ruled on twice: you may own the semantics while the call site
    belongs to a closed row. **PING ME BEFORE YOU TOUCH handoff-fire.sh** — that file is the
    campaign's fire path and I am firing rows through it while you work.
  · hooks/git-worktree-guard.sh:52 uses `pgrep -f claude`, this campaign's known-wrong idiom — it
    matches any process merely MENTIONING claude, including the hook's own argv under ~/.claude.
    Here it fails toward "live", which is safe for data but expensive and fragile. Match on the
    command position. Related stale-audit trap: p09-ship-land.md:43 says scripts/worktree-gc.sh is
    "ABSENT in this repo (reso-only)" — it is PRESENT at 615 lines with a 288-line suite. That audit
    is 11 days old. Do not inherit it.

FIVE HARNESS TRAPS — each produced a WRONG VERDICT for someone on this campaign today:
  · **zsh eats `:t` / `:h` in `"$var:path"` as a glob MODIFIER, manufacturing false absences.**
    `"$b:tests/foo"` → basename($b) + `ests/foo` → git fatal rc=128, which `2>/dev/null` renders
    identical to "absent". `tests/` and `hooks/` are the worst-hit prefixes in this repo. Use
    `"$b:$p"` or `git ls-tree "$b" -- "$p"`. Full account in Phase 1 (c) — it cost me a false
    finding about YOUR artifact this session.
  · NEVER pipe a test run into tail/head and read the exit code — that is the PIPE's status. It
    reported a clean exit 0 over two RED tests. Redirect to a file, read $? unpiped, key the verdict
    on the `not ok` COUNT.
  · A suite that tests a WRAPPER must not inherit that wrapper's env (bin/cc-bats exports
    CC_BATS_ACTIVE=1 and a shim under test then short-circuits): 16/16 green plain, 14/16 through
    the shim, nothing naming the harness. Unset it in setup().
  · A HARDCODED DENOMINATOR is worse than a stale numerator — row 8 divided every session by a 1M
    context window when the same model also runs at 200K, rescaling three findings up to 5x while
    still printing plausible percentiles. Your row is full of sizes and ratios (GB per class, % of
    disk, worktrees per writer): name the denominator for every one and prove the system records it.
  · `pgrep -f X` and any bare argv substring match counts processes that merely MENTION X, including
    test filenames and a guard's own command line. Match on the command position.

DoD (all four, or you are not done):
1. docs/plans/WORKTREE_MANAGEMENT_V2.md with the four load-bearing sections — measured constants WITH
   citations, failure-mode table (every observed mode → its structural answer), rejected alternatives
   with reasons, acceptance criteria as disk-truth reads.
2. Adversarially proven to the skill's Phase 4 bar: RED-proof every new test against a pristine
   pre-change tree recovered via git archive; a positive control beside every absence assertion;
   `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts under /bin/bash (the Bash
   tool runs zsh, so repros lie). Run gate corpora through bin/cc-bats — the box is shared with
   other live rebuilds. Reaper tests target a throwaway repo ONLY (see the hazard block).
3. Landed via the project-local /ship CONTINUOUSLY — never batch. Never add corpus work to the land
   path. RESOLVE CITED SHAS AFTER LANDING from origin/main via
   `git merge-base --is-ancestor <sha> origin/main` — ship-land rebases. Do NOT edit tracked files
   while a ship-land is in flight; it rebases and refuses on a dirty tree, and the error names a
   "conflict" that is really a dirty-tree precondition.
4. GROUND_UP_REBUILD_MAP.md row 11 updated with status + plan link + landed shas, landed too. If you
   correct the phantom surfaces in your own cell, land that too and say so.

CONSUME OTHER ROWS' MECHANISMS FAIL-SOFT. DONE on this map means designed + landed + proven +
activation STAGED AND PLATTERED — it does NOT mean live. Assume anything you depend on may be
landed-but-inert, degrade cleanly, and say in your plan what your design does when the dependency is
dark. Check for existence evidence; never trust a status cell.

Every new mechanism ships with an env kill switch, never revert-as-plan. Ping me
(cc-notify 71B42B48-1331-4F60-8DA3-6849F2682CA2) at Phase 1 close, on any seam question, and at DONE
with your landed shas.
