You are the W3 session of the husk-pane long-term fix in ~/Development/claude-infrastructure. Work ONLY in your own worktree/branch (handoff-fire created it; never commit in the shared checkout — read .claude/CLAUDE.md there). W1 has landed on origin/main.

## Read first
- docs/research/husk-history-2026-10-24/FIX-DESIGN.md: §2 pane states (lines 95-106), D15 (line 166), §4 W3 (lines 382-396), §6 Done criterion 5 (lines 488-490).
- scripts/pane-close-retry.sh (its empty-queue exit ~:63-64, the rc-124 arm ~:310-313, pcq_remove ~:279); bin/cc-kitty-socket; the runner's exit records ~/.claude/run/pane-exit/<wid>.json with `tail`.

## Scope (frozen): the standing pane census of FIX-DESIGN §4 W3 exists and runs every drainer tick — scripts/pane-census.sh writes one row per tick to ~/.claude/logs/pane-census.jsonl classifying every fleet-registered pane still listed by kitty as running | held | deciding | kept[r] | unexplained | operator, pages once per (kitty pid, pane) when a pane is unexplained 2 ticks running or a hold is older than 6 h — proven by its bats suite (fixtures only) and one live dry read that prints the class counts without paging or touching any pane.
- Population (D15): panes registered in this kitty's lifetime (watchdog `registered session=… pane=N`) that `kitty @ ls` (via bin/cc-kitty-socket) still lists. READ-ONLY against kitty: `ls` only, never a close, focus or send.
- Called by scripts/pane-close-retry.sh before its empty-queue exit, bounded to 20 s, rc ignored. rc 124 becomes its own class in pane-close-retry.sh; read first_ts before pcq_remove.
- Size ~+80 code, ~+60 tests.

## Gates
/bin/bash -n; bare `shellcheck <changed files>`; each touched suite alone under `CC_BATS_WAIVER_REASON='husk W3' CC_BATS_MAX_ROOTS=0 env PATH="/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.claude/bin:/opt/homebrew/bin" bats tests/<suite>.bats`, printing its `1..N` plan line (a cc-bats deferral is not a result); the launchd-run script must also be exercised under /bin/bash 3.2 in its suite; `bash scripts/test-hermeticity-lint.sh`; `bash scripts/test-afunix-path-lint.sh`; `python3 scripts/bats-assert-liveness-fix.py tests/<suite>.bats`. The box runs at load 200-900: a red that also fails on origin/main's code is not yours.

## Constraints
- Never run commands that open a permission prompt nobody can answer: no heredoc file edits through Bash, no bare `git stash`, no `rm -r`, no `git reset --hard`. Use Edit/Write.
- Never close, kill or resume any pane; the census only reads. Tests use stubs and fixtures, never the live kitty.
- Land only through the project-local /ship (`bash scripts/ship-land.sh`, bare, never in a timeout), verify by content, converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, then the Session Close Protocol and self-close. The 7-day metric (Done criterion 5) is a standing observation, not this session's to wait for.
