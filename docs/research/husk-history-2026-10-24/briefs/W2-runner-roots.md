You are the W2 session of the husk-pane long-term fix in ~/Development/claude-infrastructure. Work ONLY in your own worktree/branch (handoff-fire created it; never commit in the shared checkout — read .claude/CLAUDE.md there). W1 has landed on origin/main.

## Read first
- docs/research/husk-history-2026-10-24/FIX-DESIGN.md: §2 (lines 95-146), §4 W2 (lines 363-380), D13/D14 (lines 164-165), D2 ruling note in §7.
- W1's runner contract: bin/cc-pane-runner header (the `tail` states closed | hold:* | keep:<r>), and CC_PANE_RUNNER_OWNS_CLOSE = the runner's kitty window id.

## Scope (frozen): every fleet launch is rooted in bin/cc-pane-runner (FIX-DESIGN §4 W2, items W2.4-W2.7), with the shell-tail lint's allowlist exactly as the design lists it, proven by that lint run against the real tree and the touched suites green.
- W2.4: replace the `zsh -ic "$CMD || exec zsh -i"` roots with the runner argv shape (scripts/handoff-fire.sh:1326-1327 is the model) at scripts/boot-resume-launch.sh:258 and bin/cc-resume-layout.sh:1053, :1359; retire the doctrine at boot-resume-launch.sh:240-249; the lr argv fallback (scripts/limit-recover/lr-lib.sh:1342-1345) refuses rather than launching bare. Re-grep the line numbers first; they are from 2026-10-24.
- W2.5: typed relaunches become `exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash "$R"` (hf_resume_cmd_set in scripts/handoff-fire.sh, the sweep's typed resume in bin/cc-husk-sweep).
- W2.6: the fleet argv at bin/kitty-split-launch.sh:146-149 goes through the runner.
- W2.7: delete rr_close_on_clean_exit from bin/reso-resume-one (W1 already skips it under runner ownership).
- Lint: `git grep -nE '\|\| exec zsh -i|exec "\$\{SHELL' -- bin scripts lib` must equal the allowlist in FIX-DESIGN §4 W2 (re-derive the line numbers after your edits); add it to an existing lint script or a bats suite so it is enforced, not prose.
- Tests: invert tests/kitty-recovery-launch.bats:467, :493 and tests/handoff-recycle-pane-survives.bats as the design says.
- Operator-opened windows (D2, ruling 337e100f5c71) are OUT of scope: lib/pane-successor.sh defaults stay.

## Gates
/bin/bash -n on changed files; bare `shellcheck <changed files>`; each touched suite alone under `CC_BATS_WAIVER_REASON='husk W2' CC_BATS_MAX_ROOTS=0 env PATH="/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.claude/bin:/opt/homebrew/bin" bats tests/<suite>.bats` with its `1..N` plan line printed (a cc-bats deferral is not a result); `bash scripts/test-hermeticity-lint.sh`; `bash scripts/test-afunix-path-lint.sh`; `python3 scripts/bats-assert-liveness-fix.py tests/<suite>.bats`. tests/pane-289-replay.bats must stay 27/27. The box runs at load 200-900: a red that also fails on origin/main's code is not yours (run the control). `${lines[-1]}` reds under bash 3.2 in tests/kitty-fullscreen-guard.bats are pre-existing.

## Constraints
- Never run commands that open a permission prompt nobody can answer: no heredoc file edits through Bash, no bare `git stash`, no `rm -r`, no `git reset --hard`. Use Edit/Write.
- Never close, kill or resume a live session's pane; tests use stubs and fixtures only, never the live kitty.
- Land only through the project-local /ship (`bash scripts/ship-land.sh`, bare, never in a timeout), verify by content (`git ls-tree origin/main -- <paths>` + empty `git diff origin/main -- <paths>`), converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, then the Session Close Protocol and self-close.
