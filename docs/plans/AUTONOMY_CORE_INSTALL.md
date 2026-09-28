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

## W2 — implement

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
