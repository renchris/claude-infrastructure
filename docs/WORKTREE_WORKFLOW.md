# Running unlimited parallel Claude sessions safely through worktree isolation and autonomous launch

> Pyramid-structured (Minto). Governing thought first, then the four legs that prove it,
> evidence under each. Written 2026-07-02; artifacts referenced live in this repo
> (`commands/handoff.md`, `scripts/handoff-fire.sh`) and in `~/.zshrc` / per-project scripts.

## SCQA

- **Situation** — One machine, one repo, many concurrent Claude Code sessions: a lead, Agent-Teams
  teammates, and parallel handoff tracks, spread across 4 isolated billing accounts.
- **Complication** — Concurrent sessions on ONE checkout share the git index: bare commits sweep
  another session's staged files, `cannot lock ref 'HEAD'` races, shared-file clobber (observed
  repeatedly, 2026-06-01). Opening each new session was a manual, error-prone ceremony: create a
  worktree, pick a non-saturated account, remember model/effort ladders, open a pane, paste a prompt.
  The native shortcut is broken here (`claude -w` dies on repos with a `WorktreeCreate` hook), and
  the per-account launchers are zsh functions that no script can exec directly.
- **Question** — How do we run N parallel sessions safely without the per-session manual ceremony?
- **Answer** — Isolate every WRITER session in its own worktree, and automate the entire launch —
  surface, account, model, effort, prompt — down to one script call per session.

## Governing thought

**Every concurrent writer gets its own worktree, and every session launch is one command:**
`handoff-fire.sh` opens the pane, picks the account, composes model+effort, and auto-submits the
prompt — the same lifecycle Agent Teams gives teammates, generalized to peer sessions.

## 1 · Isolation policy decides WHERE work runs — conditional, never always-on

Always-worktree taxes the 90% single-session case (cold `.next` rebuild, gitignored-state
divergence, stale litter). The rule (SSOT: `CLAUDE.md` § Concurrent Sessions, synced in this repo):

- **Single session** → repo root, default branch. No worktree.
- **Read-only sessions** (research/audit/planning writing no tracked file) → share the root freely.
  Classify by *write footprint*, not intent.
- **2+ concurrent writers** → one worktree + branch EACH. Agent-Teams teammates are already
  worktree-isolated by the harness; peer sessions get theirs from the launch tooling below.

## 2 · Launch mechanics decide HOW a session starts — type into an interactive pane, never exec

Three traps make naive automation fail, and the tooling encodes all three
(memory `reference-parallel-session-launch-playbook`, paid for on 2026-07-02):

- **Worktree acquisition prefers the WARM POOL, colds-build as fallback.** Where the repo ships
  `scripts/worktree-pool.sh` (reso does, since 2026-07-02 eve), `handoff-fire.sh --worktree <slug>`
  CLAIMS a pre-provisioned slot (~3s: node_modules, codegen, `.env.local`, seeded DB all pre-built;
  claims are slot-locked and never run `git worktree add`, keeping the historical parallel-add races
  off the hot path). Cold fallback (no pool / custom `--base` for frozen fork refs): the spawner runs
  the fast, race-prone `git worktree add` serially and leaves the ~16-19s `pnpm install` to run
  INSIDE the pane, so N parallel setups overlap — wall-clock ≈ one setup, not N. (Historical note:
  `claude -w` was broken by the repo's `WorktreeCreate` hook printing human text — FIXED 2026-07-02,
  the hook now prints a plain path and claims from the pool; the explicit-path flow here remains
  preferred because the spawner needs the path to compose the typed command.)
- **Launchers are zsh functions/aliases** (`claude-next`, `-next2/3/4`, `claude-fable*`) carrying
  per-account `CLAUDE_CONFIG_DIR` isolation — they resolve ONLY in an interactive shell. So the
  spawner types the command into a fresh iTerm2 surface via osascript `write text`; it never execs.
- **The prompt travels by file** (`launcher "$(cat /tmp/fire-<slug>.txt)"`): command-substitution
  output is never re-expanded, so payload content is injection-safe verbatim; the typed line stays
  short and single-line.

Surfaces: `--split-right` default (⌘D — same view, same profile, like a teammate pane),
`--split-down`, `--tab`, `--window`; all fall back to a fresh window when none is open.

## 3 · Routing decides WHO runs it — account by live load, model+effort by SSOT ladder

- **Account** (4 isolated accounts = 4 quota pools): explicit choice wins; else static hint order
  `next2>next3>next4>next` re-ranked by the free draw-proxy — trailing-5h transcript count per
  config dir — because static hints go stale in the dangerous direction (measured: the favored
  account had 23 live sessions while another had 5). `--probe` adds a headless liveness check that
  walks the ranking and classifies rejections (rate-limited / auth-expired / model-unavailable).
- **Model + effort** (SSOT: `~/.claude/model-config.yaml`): Opus 4.8 @ **max** is the default lead
  ladder (xhigh is a certified regression on grounding-heavy work); Fable 5 runs a DIFFERENT ladder —
  **high** default, xhigh capability-sensitive, medium routine, never max (over-deliberates, burns
  the window). Flags append last-wins after the launcher's injected defaults, so overrides always
  stick; Fable is window-gated (`frontier_access.active`) with the API rejection as the hard gate.

## 4 · `/handoff` fire closes the loop — readiness-gated autonomy, wave-scale by default

- **Fire is the default close of `/handoff`**, gated by READINESS not permission: no open
  discussion/question/decision → it fires; anything open → it names the blocker, holds, fires after.
  "paste only" / "hold fire" always suppresses; the paste block remains the manual fallback.
- **Waves are first-class**: N handoff tracks → N sessions, one script call each, fired serially
  (installs overlap in-pane). Account spread is the LEAD's job for waves — auto-ranking can't see
  sessions that haven't started yet, so rank once and assign round-robin, ≤2 tracks per account.
- **Prompt composition is positional**: `ultracode` prepended opts the receiver into Dynamic
  Workflows (prompt-level keyword); a skill-backed slash command (`/goal …`) must be the payload's
  very FIRST line — the CLI never parses it; the receiving model dispatches a leading `/x` via its
  Skill tool.
- **Prior art**: this is the session-level analog of the Agent-Teams teammate lifecycle
  (`it2 session split -s <lead>` → `tmuxPaneId` in team config → shimmed force-close +
  checkpoint-first idle reaping). Fired sessions differ deliberately: they are PEERS on their own
  accounts, human-torn-down, never hook-reaped.

## Merge-back and teardown

Rebase onto the default branch + `--ff-only`, serialized, smallest-diff first; `git rerere` enabled
globally. Worktrees do NOT prevent semantic/lockfile/migration-journal conflicts — single owner per
shared file, serialize migration-generating sessions, gate every merge with the repo's typecheck +
lint. Rate-limited session? `/exit`, relaunch the SAME worktree on another account — worktrees are
account-agnostic, zero rework.

## Artifact map

| Concern | Artifact |
|---|---|
| Autonomous launch (spawner) | `scripts/handoff-fire.sh` (this repo; live at `~/.claude/scripts/`) |
| Handoff protocol + fire mode | `commands/handoff.md` (this repo; live at `~/.claude/commands/`) |
| Isolation rule (SSOT) | `CLAUDE.md` § Concurrent Sessions — Worktree Isolation (this repo, synced) |
| Per-account launchers | `~/.zshrc` (`claude-next*`, `claude-fable*`; not synced — contains account wiring) |
| Model/effort/window SSOT | `~/.claude/model-config.yaml` (not synced) |
| Per-repo worktree setup | `<repo>/scripts/new-worktree.sh` (repo-specific, e.g. reso) |
| Warm worktree pool (fast path) | `<repo>/scripts/worktree-pool.sh` — `claim <branch>` prints a provisioned path (repo-specific, reso) |
| Launch traps provenance | memory `reference-parallel-session-launch-playbook` |
