YOUR TASK — a from-first-principles GROUND-UP rebuild of ONE subsystem: account/quota routing &
relogin (row 7). You were fired by the ground-up campaign coordinator.

Scope (frozen): zero work stranded by a login cliff, and routing decisions read LIVE quota rather
than a remembered one — under the standing constraint that cliffs are hard walls and the 4 accounts
are isolated from each other. Measured, landed, and verified by disk-truth acceptance reads.

STEP 1 (one short command): arm your standing goal so you drive to DONE across recycles —
  /goal row 7 account routing: zero work stranded by login cliffs, routing reads live quota,
  proven by disk-truth reads. Rebuild per skills/ground-up/SKILL.md.

STEP 2: run /ground-up account-relogin. Before any other tool call, READ: GROUND_UP_REBUILD_MAP.md
row 7 · skills/ground-up/SKILL.md · docs/plans/LAND_PIPELINE_V2.md (exemplar) ·
docs/plans/SESSION_LIFECYCLE_V2.md (row 2, DONE — the strongest recent exemplar of a cell
falsification done right).

[locate] your own worktree on branch gu-account-relogin (base origin/main) of
claude-infrastructure. Commit ONLY here — NEVER in the shared checkout.

YOU OWN: bin/claude-accounts, bin/cc-relogin*, the limit-recover skill, ~/.claude/model-config.yaml
as SSOT, the per-account launchers, and bin/cc-route (ruled yours — see the map's unowned-surface
register).
SEAMS NOT YOURS: fire-time ranking is consumed by row 2's handoff-fire; row 5's bin/cc-wave-plan is
a CONSUMER of your contract, not a co-owner. **cc-route's exit-code contract (0 plan · 2 usage ·
3 blind/no-data · 4 cliff) is PINNED by scripts/route-safety-gate.sh:33-50 and tests/cc-route.bats
— you may extend it, but changing an existing code silently breaks row 5.** Any seam dispute: ping
the coordinator, never decide alone.

PHASE 1 IS NOT OPTIONAL — three checks BEFORE you design anything:
  (a) RE-DERIVE YOUR ROW'S STANDING-CONSTRAINT CELL from primary disk truth. The cell is the PRIOR
      SESSION'S HYPOTHESIS, and on this campaign it has been falsified or renamed more often than
      confirmed (rows 2, 5, 8, 12, 13). State plainly in your plan whether you killed or confirmed
      it. Known anchor to re-verify rather than inherit: memory reference-claude-accounts-tooling
      records that `refreshTokenExpiresAt` anchors to the LAST INTERACTIVE /login and that no token
      refresh extends it — if true that makes a cliff a scheduled certainty, not a random event,
      and a system that cannot see the schedule cannot avoid the wall. Prove it from the credential
      store, do not quote the memory.
  (b) CHECK ACTIVATION/DEPLOY TRUTH for every mechanism your metric depends on. Derive, never
      inherit — every carried number on this campaign has decayed within the hour:
        git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main   # deploy lag
        for f in ~/.claude/autonomy/pending-activation/*-activate.sh; do \
          [ -e "$f.done" ] || echo "UN-RUN $(basename "$f")"; done
      Note the lag is a SAWTOOTH, not a state (GROUND_UP_DISPATCH.md explains why): it climbs
      while 0 of 33 postland stamps are green, then collapses out of band. Prefer an EFFECT-READ
      over the count when you want to know whether YOUR artifact is live:
      `[ -e ~/.claude/bin/<artifact> ]`. Also check whether each file you touch is a SYMLINK into
      the checkout (landing == deploying) or a SEPARATE REAL FILE — `~/.claude/CLAUDE.md` is the
      known exception, and `model-config.yaml` is yours to check before you assume either way.
  (c) SWEEP THE BRANCH GRAVEYARD before you build. The campaign-level sweep in GROUND_UP_DISPATCH.md
      named artifacts for rows 6, 8, 9, 10, 11 and 2 — **it named NONE for row 7, which is a
      known-incomplete pointer and NOT evidence that none exist.** Run it yourself for your paths:
        git log --all --oneline --diff-filter=A -- '<paths your row would create>'
        git for-each-ref --format='%(refname:short)' refs/heads | while read -r b; do \
          printf '%s %s\n' "$b" "$(git rev-list --count origin/main..$b 2>/dev/null)"; done | awk '$2>0'
      Take from fix/infra-perfection, NEVER from tm/growth (0 unique patches, drags a 6-branch
      nested chain). cherry-pick -x; say what you took and what you rejected on merits. GIVE THE
      SWEEP A POSITIVE CONTROL — assert it re-finds a file you already know exists before believing
      any negative. Two of the coordinator's three sweeps returned confident garbage at exit 0.

FOUR HARNESS TRAPS — each produced a WRONG VERDICT for someone on this campaign today:
  · NEVER pipe a test run into tail/head and read the exit code — that is the PIPE's status. It
    reported a clean exit 0 over two RED tests. Redirect to a file, read $? unpiped, key the
    verdict on the `not ok` COUNT.
  · A suite that tests a WRAPPER must not inherit that wrapper's env (cc-bats exports
    CC_BATS_ACTIVE=1 and a shim under test then short-circuits): 16/16 green plain, 14/16 through
    the shim, nothing naming the harness. Unset it in setup().
  · A HARDCODED DENOMINATOR is worse than a stale numerator. Row 8 divided every session by a 1M
    context window when the same model also runs at 200K, silently rescaling three findings by up
    to 5x while still producing plausible percentiles. Your row is full of ratios — % of quota, %
    of window, time-to-reset — so name the denominator for every one and prove the system durably
    records it.
  · `pgrep -f X` and any bare argv substring match will count processes that merely MENTION X,
    including test filenames and a guard's own command line. Match on the command position.

DoD (all four, or you are not done):
1. docs/plans/ACCOUNT_ROUTING_V2.md with the four load-bearing sections — measured constants WITH
   citations, failure-mode table (every observed mode → its structural answer), rejected
   alternatives with reasons, acceptance criteria as disk-truth reads.
2. Adversarially proven to the skill's Phase 4 bar: RED-proof every new test against a pristine
   pre-change tree recovered via git archive; a positive control beside every absence assertion;
   `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts under /bin/bash (the
   Bash tool runs zsh, so repros lie). Run gate corpora through bin/cc-bats — the box is shared
   with other live rebuilds. NEVER commit real credentials or tokens, and never print one into a
   plan, a test fixture, or a commit message.
3. Landed via the project-local /ship CONTINUOUSLY — never batch. Never add corpus work to the land
   path. RESOLVE CITED SHAS AFTER LANDING from origin/main via
   `git merge-base --is-ancestor <sha> origin/main` — ship-land rebases. Do NOT edit tracked files
   while a ship-land is in flight; it rebases and refuses on a dirty tree.
4. GROUND_UP_REBUILD_MAP.md row 7 updated with status + plan link + landed shas, landed too.

CONSUME OTHER ROWS' MECHANISMS FAIL-SOFT. DONE on this map means designed + landed + proven +
activation STAGED AND PLATTERED — it does NOT mean live. Assume anything you depend on may be
landed-but-inert, degrade cleanly, and say in your plan what your design does when the dependency
is dark. Check for existence evidence; never trust a status cell.

Every new mechanism ships with an env kill switch, never revert-as-plan.
