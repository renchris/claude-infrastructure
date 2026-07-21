# Resume Sessions — REFERENCE (mechanisms, gotchas, tooling internals)

Deep detail behind `SKILL.md`. Origin: the 2026-07-04 crash-recovery session that restored 9 sessions
across 4 accounts. Every gotcha below cost a real debugging cycle — trust them.

---

## 0. The tools (in `~/.reso/bin/`)

| tool | what it does |
|---|---|
| `reso-resume-one <acct> <wt> <sid> [branch]` | autonomous single-session resume: recreate reaped worktree, reset mouse reporting, auto-answer the summary prompt (expect, 240s), hand off to interactive |
| `reso-keepalive [interval_s]` | re-nudges only idle panes (from `/tmp/reso-keepalive-ids.txt`) every interval; skips working panes + decision-prompts |
| `reso-quota [--json\|--route general\|--route fable]` | COMPAT SHIM (2026-07-10) → `~/bin/claude-accounts` (claude-infrastructure/bin; adds `--rank`, `--relogin-info`, auth states, SSOT Fable window, fixed k counter; heals via headless `claude auth login`, never raw refresh-and-discard) |

`~/.reso/keepalive.log` = watcher activity. Backups of any overwritten tool: `~/.claude/backups/`.

---

## 1. Account & credential map (verified)

- 4 accounts: `next`=`.claude-next` (ichris96+claude), `next2`=`.claude-secondary` (chris.swe+claude),
  `next3`=`.claude-tertiary` (ren.chris+claude), `next4`=`.claude-quaternary` (chris.claudecode).
  `.claude` mirrors `.claude-next` (same account). Launchers: `claude-next`, `claude-next2/3/4`,
  `claude-fable`, `claude-fable2/3/4` (all in `~/.zshrc`; interactive-shell functions only).
- **OAuth token per account**: macOS Keychain item `Claude Code-credentials-<sha256(config-dir-path)[:8]>`,
  account **`chrisren`** (NOT "Claude" — that filter silently returns "item not found"). Read:
  `security find-generic-password -s "Claude Code-credentials-<hash>" -a chrisren -w` → JSON with
  `.claudeAiOauth.accessToken` + `.refreshToken`. From a `TOKEN=$(security …); curl …` compound command
  the curl-gate does NOT fire (it only inspects commands STARTING with `curl`).
- **Usage endpoint**: `GET https://api.anthropic.com/api/oauth/usage` with
  `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`. Returns `.limits[]` entries
  `{kind, percent(0..100 USED), resets_at, scope}`: `kind=session` (5-hour), `kind=weekly_all`,
  `kind=weekly_scoped scope.model.display_name=Fable` (weekly Fable). Plus `.extra_usage{is_enabled,
  used_credits}` (NOTE: API `is_enabled` reflects an ORG-level flag and can disagree with the UI toggle).
- **Token refresh — ⚠ NEVER call the endpoint directly** (protocol reference only:
  `POST https://platform.claude.com/v1/oauth/token`, grant_type refresh_token, client_id
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`). Refresh tokens MAY rotate (GH #54443 unanswered) — a
  raw POST that discards the response's new refresh_token can LOG THE ACCOUNT OUT. Stale idle
  tokens are healed via headless `CLAUDE_CODE_OAUTH_REFRESH_TOKEN=… claude auth login` (the
  binary persists possibly-rotated tokens to the keychain), which `claude-accounts` does
  automatically at k==0. Both usage + refresh endpoints rate-limit under load — retry with
  backoff; degrade gracefully.

---

## 2. Session discovery (Phase 1 scanner)

Iterate `~/.claude{,-next,-secondary,-tertiary,-quaternary}/projects/*/*.jsonl`. Skip dirs starting
`wf_` and files starting `agent-` / `journal.jsonl`. For each remaining `<uuid>.jsonl`: parse lines,
track `cwd`, `gitBranch`, the `{type:summary}` line, first real user message, and the **max message
`timestamp`** (this is the real last-activity — file mtime lies after a mirror touch). Dedup by session-id:
a sid present in both `.claude` and `.claude-next` = one `next` session (launcher = whichever store; `next`
if `.claude-next` present). Rank by max-timestamp desc. The reboot epoch (`sysctl -n kern.boottime`)
splits pre-crash (candidates) from post-reboot (recovery/new).

---

## 3. Worktrees

- Crashed/idle worktrees get **reaped** (dir gone; may even be deregistered from `git worktree list`).
  Recreate: `git worktree prune` then `git worktree add <path> <branch>` (branch survives the reaping;
  check `git show-ref --verify refs/heads/<branch>`). All resume-target cwds MUST exist or `cd` fails →
  `&&` short-circuits → claude never launches (the classic "stuck at a shell prompt" symptom).
- A freshly-recreated worktree lacks gitignored files (`.env.local`, `drizzle/db.db`). Fine for resuming
  a session (mostly read/reason); the session re-runs setup if it needs the app.

---

## 4. Terminal input — the load-bearing reliability rules

- **`it2 session send -s <session-id> "TEXT"`** (real path `~/Library/Python/3.11/bin/it2`) types text as
  keystrokes and is RELIABLE. It sends WITHOUT a newline → submit with a separate `it2 session send -s <id>
  $'\r'` (Ink Enter = **CR (\r)**, not \n). Send the CR twice (a long first line can be treated as a paste
  where the first CR only commits the paste).
- **`osascript … write text` is UNRELIABLE** for a running Claude TUI: it drops submits, and long text is
  treated as a bracketed paste that a trailing CR won't submit. Use it ONLY for pane management
  (create window/tab, split) and short control chars — never for message submission at scale.
- **Clearing the input draft**: Escape (char 27) + Ctrl-U (char 21) clears most; a stubborn multiline
  escape-sequence block needs Ctrl-C (char 3). The gibberish (`^[[<35;…M` = SGR mouse events;
  `^[[?27;3;1R` = cursor/DSR reports) leaks in because a crashed TUI left mouse-reporting ON; iTerm2's
  "mouse reporting was left on — turn it off?" announcement is the same root cause (harmless; `reso-resume-one`
  pre-resets mouse mode so fresh resumes don't leak).
- **Never steer a working session**: only nudge panes whose visible content lacks "esc to interrupt"
  (working) and lacks "Tab to amend"/"ctrl+e to explain"/"Esc to cancel" (at a decision prompt).
- **Proof of work = git commits**, not the TUI state (turns finish in seconds; a snapshot mislabels a
  just-finished session "idle"). `git -C <wt> log -1 --format='%h %cr'`.

---

## 4a. Source-level prompt suppression — the two blockers `expect` CANNOT answer (2026-07-11)

A headless `claude --resume` driven by `expect` (lr-fire-resume.sh / reso-resume-one) controls the
**PTY**. Two startup prompts live OUTSIDE the PTY, so no `expect`/`it2 send` can reach them — a human
had to click, which stranded the auto-fired `/limit-recover ingest` prompt (observed 2026-07-11, three
stacked modals). Both are now resolved at the SOURCE by `~/.claude/scripts/limit-recover/lr-preseed-env.sh`
(`<config-dir|account-alias> <worktree>`), called by lr-fire-resume.sh before the spawn; safe to call
from reso-resume-one too. Idempotent, fail-open:

1. **iTerm2 GUI modal** *"A control sequence attempted to clear scrollback history. Allow this?"* —
   Claude's TUI emits **CSI 3 J** on init; iTerm2 pops an NSAlert **sheet ABOVE the terminal** that
   freezes every keystroke. Fix = the documented iTerm2 default
   **`defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool true`**
   (iTerm2 then silently ignores CSI 3 J — no modal, scrollback kept). **Verified 2026-07-11 to apply
   LIVE to an already-running iTerm2 (no restart needed)** and to persist. The modal is a GUI overlay,
   NOT in the PTY — `expect`'s `send` and `it2 session send` both target the PTY, so neither can dismiss
   it; suppression is the only source fix. (iTerm2 binary: warning identifier `ClearScrollbackHistory`,
   advanced key `PreventEscapeSequenceFromClearingHistory`.)
2. **Folder-trust arrow-menu** *"Is this a project you trust?"* — appears when the resumed cwd is first
   opened under the TARGET account. Fix = pre-seed `projects["<cwd>"].hasTrustDialogAccepted = true` (the
   ONLY field Claude reads for the trust gate) in `<target-cfg>/.claude.json`. Key = `cd "$WT" && pwd -P`
   because Claude keys projects by Node `process.cwd()` = **realpath** (so a `/tmp/x` worktree keys under
   `/private/tmp/x` — logical would MISS). The helper also RAISES the one-time upsell seen-counts
   (`overageCreditUpsellSeenCount`/`subscriptionNoticeCount`/`remoteControlUpsellSeenCount`/
   `passesUpsellSeenCount`/`pushNotifUpsellSeenCount`/`autoPermissionsNotificationCount`, only if already
   present as ints) so those upsells don't render as a blocking select-menu at resume.
   **Concurrency (corrected):** the write is guarded by the SAME `.claude.json.lock` (proper-lockfile
   `<file>.lock` DIRECTORY, ~15 s stale-steal) that Claude itself takes — so it can NEVER clobber a
   concurrent same-account session's newer write (auth/session/MCP/cost state); if the lock isn't free
   fast, the seed is SKIPPED and the `expect` trust-handler answers the prompt. `os.replace` is atomic +
   mode-preserving → a partial/corrupt config is impossible. (Earlier framing "worst case = our seed is
   dropped, never corruption" was WRONG-DIRECTION — the danger was clobbering THEIRS; the lock closes it.)

The **fullscreen-renderer upsell** ("Try the new fullscreen renderer?") + terminal-query **escape
gibberish** ARE in the PTY, so lr-fire-resume.sh's `expect` layer still handles them (Down+CR = "Not now" =
option 2, order verified for CC 2.1.183 — RE-CHECK on any bump; mouse-reporting reset). CC env knobs in the
2.1.183 binary: `CLAUDE_CODE_NO_FLICKER`, `CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL`, `/tui fullscreen`.

**One-time machine preconditions (NOT per-resume; document, don't silently assume):**
- **osascript Automation grant** — lr-handoff.sh opens the pane via `osascript ... tell application "iTerm2"`.
  The first time the controlling process drives iTerm2 (or after a TCC reset / OS upgrade), macOS pops a
  system *"… wants to control iTerm2"* modal (osascript returns `-1743` until Allow). This is a GUI grant
  that can't be set without SIP off — grant it once (already granted on this machine; the 2026-07-11 splits
  succeeded). To go fully osascript-free later: drive the pane via the `it2` CLI / iTerm2 Python API or a
  headless tmux pane.
- **iTerm2-only launch path** — the pane is created via iTerm2 AppleScript (no `TERM_PROGRAM` guard). All
  resume targets run under iTerm2; Terminal.app has no scrollback modal, Ghostty/tmux differ. Add an
  iTerm2 precondition check only if portability is wanted.
- **Established account** — global `hasCompletedOnboarding`/theme wizard is NOT preseeded; safe because all
  4 accounts already have it. A brand-new/reset config would strand on the theme wizard (seed
  `hasCompletedOnboarding` if that ever changes).
- **Modal scope** — the iTerm2 pref suppresses ONLY the CSI 3 J scrollback modal. Sibling out-of-PTY iTerm2
  modals (profile-change, OSC 52 clipboard) have their OWN prefs and are NOT blockers today (Claude's TUI
  doesn't emit those); a future TUI change emitting them is a NEW modal needing its own pref.

## 5. The auto-continue gap (why sessions stall after /compact)

`--resume` on a large session shows the "Resume from summary / full / don't-ask" prompt (GitHub #46751 —
**non-configurable by design** in 2.1.183; no flag/env/setting). The only autonomous answer is to
auto-press Enter via `expect` (picks option 1 = summary = quota-cheap). `reso-resume-one` does this with a
240s timeout + `exp_continue` + a UI-ready match (`shift+tab to cycle`) so it works for both prompting
(large) and non-prompting (small) sessions.

**Resume-from-summary runs `/compact` and then DROPS the session-scoped `/goal` Stop-hook** → the session
sits idle instead of auto-continuing. Fix = re-engage with a continue-prompt (Phase 3) and/or run
`reso-keepalive` (Phase 4) for perpetual operation. To restore a true native loop, re-arm `/goal <cond>`
on the session (sends a Stop-hook that blocks stopping until the condition holds) — but a blanket loop on
a genuinely-done session invents busywork, so prefer the keepalive watcher (idle-only, decision-aware).

---

## 6. Router algorithm (now in `claude-accounts`; design→judge→5 adversarial verifiers, 0 failures)

> **2026-07-10 promotion deltas** (scoring math unchanged): the Jul-7 constant is GONE — the
> Fable deadline reads live from `~/.claude/model-config.yaml frontier_access.{active,end}`
> (the hardcode silently killed all Fable routing when the operator extended the window);
> `k` now counts ALL live claude processes per CLAUDE_CONFIG_DIR (argv[0]=claude match), not
> just `--resume` ones (2 vs 14 observed) — KMAX raised 4→8 in `~/.claude/accounts.json`;
> missing scoped-Fable limit = no entitlement (never "100% headroom"). Historical algorithm
> below is otherwise accurate.

Percents are 0..100 USED. Per account, from `.limits[]` + `.extra_usage`:

- **General** (Opus, draws weekly_all only): `score = RBR × SF × KF × CF`
  - `RBR = w_rem / T_week`; `w_rem = max(0, wTgt − weekly%/100)`, `wTgt = 0.98 if credits else 1.00`;
    `T_week = max(hours_to_weekly_reset − 0.5, 0.25)`.
  - `SF = clamp((0.85 − sess%/100)/(0.85 − 0.50), 0.05, 1)` (5-hour safety).
  - `KF = clamp(1 − k/4, 0.10, 1)` (concurrency spread; `k` = live sessions on the account).
  - `CF = credits ? (weekly<0.90 ? 1 : 0.5) : 1` (deprioritize $ spend).
- **Fable** (draws BOTH the Fable sub-cap AND weekly_all): `score = (f_eff/H)·JB × SF × KF × CF`
  - **coupling fix**: `f_eff = min(0.5·(1 − fable%/100), w_rem)` — 0.5 = fable_cap/weekly_cap; the naive
    `min(fable_rem, weekly_rem)` overstates fresh-account Fable headroom up to 2×.
  - `H = max(min(T_fable, H_jul7), 0.25)`; `H_jul7 = max(hours_to(2026-07-07) − 2, 0)`;
    `JB = 1.25 if T_fable > H_jul7 else 1` (single-tranche accounts whose weekly resets AFTER Jul-7).
- **Hard-exclude** an account if: `sess% ≥ 85` (5h cutoff; waive if 5h resets <0.25h) · `k ≥ 4`
  (rate-limit spread) · general `w_rem ≤ 0.005` · fable `f_eff ≤ 0.02` · fable & `H_jul7 ≤ 0`
  (window closed → no plan-feasible Fable; never auto-spend credits).
- **concurrency `k`**: count `claude … --resume <sid>` processes per `CLAUDE_CONFIG_DIR`, **deduped by
  `<sid>`** (expect wrapper + claude.exe are 2 processes / 1 session on different ptys — dedup by tty
  FAILS; dedup by the --resume session-id).

---

## 7. Operator policy (context for decisions)

- **Account priority**: routing/spend decisions come from `claude-accounts --rank general|fable`
  (live endpoint data) — never a remembered order. The historical spend order
  `next > next4 > next3 > next2` survives ONLY as the accounts.json array order (display + exact
  score-tie break), not as a routing rule.
- **Maximize exhaustion** of weekly-general AND weekly-Fable across all 4 before each reset (unused quota
  is DESTROYED at reset, not banked); minimize mid-task interruption (5h cutoff, rate-limit).
- **Fable** (`claude-fable-5`) plan-inclusion end = **SSOT `frontier_access.end` in
  `~/.claude/model-config.yaml`** (was 2026-07-07, operator-extended to 2026-07-14 on Jul-9 —
  the reason no date is ever hardcoded again) → drive Fable usage hard before it
  (credits-only after = unaffordable). Fable = a ~50% sub-cap of the shared weekly.
- Sessions are account-locked to where their transcript lives; relocating = copy the jsonl to another
  config dir's `projects/` (image-cache paths are absolute so they still resolve) — fragile; default is
  resume in place.

See also memory `reference-crash-recovery-resume-tooling.md`, `project-fable-window-maximize-usage-2026-07`,
`reference-cc-queue-steering-recycle-rebuild` (the it2-typed relaunch mechanism), and the recovery
dashboard `~/reso-crash-recovery-2026-07-04.md`.
