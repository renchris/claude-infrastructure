---
status: done
---

# Autonomy core — a modular, cross-platform install for outside users

Scope (frozen): an outside user on macOS, Linux or WSL2 gets this repo's self-managing, long-running
layer (the "autonomy core") in ONE command or ONE pasted prompt, without the full macOS+kitty install;
the full install is unchanged. First real user: a friend on Windows via WSL2 Ubuntu.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:** W1 (audit + design) **S** — one dispatched session, which also runs W2.
  W2 (implement + test + docs) **S** — same dispatched session; it may use in-session teammates (T) for
  independent files, per the agent-teams skill.
- **Lead's context budget + succession point:** the dispatched session recycles (`--recycle`) at ~60%
  fill after committing and updating the status log below; the originating session does not own this work.

## Why

README § Install supports only the whole setup, on macOS with kitty (daemons, LaunchAgents,
`accounts.json`). There is no core-only path and no Linux/WSL2 path, so the repo cannot yet do what it
was made public for: let others use it modularly or whole, as close to one click as possible. On
2026-09-28 a first-time user asked "do you use /goal? is that how you keep agents running longer?", and
the only answer available was a hand-written prompt telling his agent to rebuild small versions of our
hooks — which is the gap.

## W1 — portability audit + design (docs only)

- Candidate core, each kept or cut with a one-line reason: a slim portable excerpt of `CLAUDE.global.md`
  (autonomy, frozen DoD, Follow-On Gate, close contract, context stewardship); `hooks/session-continue.sh`
  (auto-continue); `hooks/completion-assert.sh` (false-done gate); `scripts/wrap-ledger.sh` + `/wrap`;
  `/handoff` as a single-pane variant (no kitty/it2); `hooks/backup-before-write.sh`; `/goal` guidance.
- For each: every macOS-only or fleet-only dependency (launchd, kitty/it2, BSD-vs-GNU tools, bash 3.2
  assumptions, `~/.claude-*` multi-account, mailbox, identity overlay) and whether the core version
  stubs it, degrades cleanly, or must be rewritten.
- Output: § W1 findings below, with the chosen core list and the install shape.

### W1 findings (2026-09-28)

**Verdict: every candidate is rewritten, none is copied.** The fleet versions are large and entangled
(`session-continue.sh` 1,468 lines sourcing 7 `hooks/lib/` files; `completion-assert.sh` 1,287 lines, 9
libs; `wrap-ledger.sh` 2,649 lines, 6 libs), and 42-63 lines in each reference fleet-only stores
(mailbox, `cc-custody`, `cc-backlog`, `cc-decide`, `accounts.json`, `~/.claude-*`). Stubbing that many
seams would ship dead code to outsiders; a small rewrite that keeps each mechanism's contract is less
code and testable in a throwaway HOME.

| Candidate | Kept as | Cut (fleet-only) |
|---|---|---|
| `CLAUDE.global.md` excerpt | `core/CLAUDE.core.md`, rewritten portable: frozen DoD, drive to done, net-positive follow-ons, close readout, context stewardship, `/goal` template | every `cc-*` store, handoff-fire, accounts, Fable ladder, mission board |
| `hooks/session-continue.sh` | `core/hooks/continue.sh`: agent-armed "next step" sentinel, bounded (default 8), `set/clear/status` via `autonomy continue` | mailbox delivery, ship floor, custody, resident teammates, IDL log |
| `hooks/completion-assert.sh` | `core/hooks/completion-gate.sh`: a "done" claim is blocked once per git state while tracked changes are uncommitted or commits are unpushed | origin close contract, peer-owned, close-shape, custody |
| `scripts/wrap-ledger.sh` + `/wrap` | `autonomy ledger` + `core/commands/autonomy-wrap.md`: rungs 🔧 / 📦 / ✅ from live git, plus armed continuation | 🚀 live layer, ⛔/👤 from backlog/decision stores, residents |
| `/handoff` | `core/commands/autonomy-handoff.md`, single pane: writes a bridge doc, the user runs `/clear` and pastes one line | handoff-fire (kitty/it2/iTerm panes), accounts, notify-back |
| `hooks/backup-before-write.sh` | `core/hooks/backup-before-write.sh`: copy before a Write replaces a file, 14-day prune, `autonomy restore` | memory-index budget, plan-conventions injection |
| `/goal` guidance | text only (native Claude Code feature): template + the measured evidence below | — |

**Portability rules the core obeys** (checked by the tests): bash 3.2 (macOS `/bin/bash`; no assoc
arrays, `mapfile`, `${x,,}`); no `sed -i`, `stat`, `date -d/-j`, `readlink -f`; JSON via `jq` when present
else `python3` (Ubuntu/WSL ship python3, not jq; macOS 15+ ships jq); git optional (the gate and ledger
abstain outside a repo). No launchd, kitty, `osascript`, multi-account or mailbox anywhere.

**Install shape.** A separate root `install-core.sh`, not `install.sh --profile core`: `install.sh` is a
1,514-line fleet installer whose global guards (worktree/stale refusal, accounts seed, git hooks,
LaunchAgents) run before any option could branch, so a profile flag would thread through all of it;
leaving it untouched makes the full install's `--dry-run` diff empty by construction. The installer is
**self-contained**: sources live in `core/`, and `core/build.sh` embeds them as quoted
heredocs (a bats test fails when the embedded copy drifts), so one curl'd file and one sha256 pin
everything, with no second fetch and no ref argument. Target `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`:
files under `autonomy-core/`, `/wrap` and `/handoff` into `commands/` (a foreign file of that name is left
alone), the rules as a marker-delimited block in `CLAUDE.md`, and three hook entries merged into
`settings.json` (backed up once to `settings.json.before-autonomy-core`, plus a timestamped copy on every
change). Refuses when the full install is present; `--uninstall` reverses every step. It verifies itself
by driving each installed hook with fixture JSON and reading `settings.json` back, and fails closed.

## W2 — implement (DONE 2026-09-28)

Landed `a1623fd0d` (public projection `d4ba67f0`): `install-core.sh`, `core/` (hooks, `autonomy` CLI,
rules, commands, `build.sh`), `tests/install-core.bats` (16 tests, clean HOME and config dir; covers a
python3-only PATH for the stock Ubuntu/WSL2 case, GNU userland first on PATH as a Linux proxy, merge,
idempotency, uninstall, refusal over the full install). README § Quick start pins the installer to the
public commit and its sha256 `4e611c1f…4ac1`. Full-install `--dry-run` output (throwaway HOME,
`--config-dir`) is byte-identical to origin/main's.

Learnings:
- The land gate selects suites by file-name STEM: `core/commands/wrap.md` pulled in the fleet's
  `wrap-*`/`handoff-*` suites, two of them red on trunk for reasons outside this diff
  (`handoff-selfclose.bats` "inventory: silent when nothing is pending", since `89eba66e0`, whose eval'd
  function now calls an undefined `transcript_for_sid`; `wrap-ledger-memo.bats` "six CONCURRENT cold
  callers", 96 vs a ≤32 bound at load ~24, because the 750 ms single-flight wait is shorter than one
  compute on a loaded box, reproduced on `89eba66e0~1` too). Sources are now `autonomy-*.md`,
  installed under their real names.
- Under bash 3.2, a mid-test `[[ ]]`, `!` or `&&`-chain does not fail a bats test; the dead-assertion
  arm caught all of them, and each now ends in `|| false`.
- Not done: a real WSL2 run. The Linux path is covered by the python3-only and GNU-userland tests,
  not by a Linux kernel; Docker was not running on this machine.

Original brief:

- `install.sh --profile core` (or a separate `install-core.sh`) — macOS, Linux, WSL2; idempotent; backs
  up and merges `settings.json`; never touches the full install's paths or behaviour.
- A clean-HOME bats test that installs the core and exercises each hook once (fixture JSON on stdin).
- README "Quick start: autonomy core": the one command, and a one-prompt variant a user pastes into
  Claude Code that reads the pinned repo and runs the installer.

## /goal evidence to carry into the docs (measured 2026-09-28, all four accounts' transcripts)

506 goals armed; 330 never evaluated (the session handed off or ended mid-turn before a Stop); 176
evaluated, 154 met (88%); 18 met goals first caught a premature stop (1-5 times typically). Template:
`<measurable end state> — proven by <command the session prints>; do not <constraint>`. Anti-example:
`continue until 100.00 complete and correct at 100th percentile absolute perfection implementation`
(45 evaluations over 27.6 h, ruled impossible). Method: scan `goal_status` attachments in
`~/.claude*/projects/**/*.jsonl*`, deduplicated by real path.

## Status log

- 2026-09-28 — plan created; W1+W2 dispatched as one session.
- 2026-09-28 — W1 findings written; W2 landed `a1623fd0d`, live-converged, and published to the public
  repo (`d4ba67f0`); the raw pinned URL's sha256 matches `git show origin/main:install-core.sh`.
  README quick start added in a follow-up commit.
