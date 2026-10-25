# Design brief — mid-turn account move (shared input for every architect, judge and verifier)

## The problem, in one paragraph

The operator runs four Claude Max accounts (next, next2, next3, next4; config dirs `~/.claude-next`,
`~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary`; each with its own macOS keychain OAuth item
`Claude Code-credentials-<sha256(dir)[:8]>`). Sessions are long-lived Claude Code 2.1.293 TUIs in kitty panes,
~36 live at once (S06: next 6, next2 2, next3 9, next4 19). Accounts must be re-balanced (strand-aware: put work
where weekly quota would otherwise expire unused) and recovered at limit walls. Today's mover (`cc-lr move` →
`lr-move-worker.sh` → `lr-handoff.sh --in-place` → `handoff-fire.sh --recycle`) waits for idle, types `/exit`,
relaunches `claude --resume <uuid>` on the target config dir. 2026-10-25 01:55 CDT the operator ordered every
active session onto next4 (84% weekly, 2 h to reset) and the lane queued them all. Operator: "There's nothing
stopping me from opening a new Kitty pane, entering a new Claude Code session and starting, so if we can do it
manually we can do it programmatically."

## Standing constraint that kills lazy designs

**Idle never happens.** Measured (S06, 20 most recent transcripts, 268 gaps): inter-turn gap p50 6.3 s; sessions
mid-turn 66.8% of wall time over the last 3 h; 11 of 20 sessions ≥99.8% mid-turn; 4 never ended a turn. Only 10 of
268 turn starts were the operator; the rest were task notifications (78), hook-forced continuations (64), Stop-hook
feedback (60), peer mail (52), /goal (3). Busy/goal rows in the move lane all-time: 149 rows → 5 moved (3.4%).
A design that waits for idle is a design that does not move.

## Frozen DoD for the design (what "winning" means)

A busy session (mid-turn, mid-tool-loop, background jobs, subagents, workflows, teammates, a live /goal) changes
billing account with **0 transcript forks, 0 lost turns, 0 killed background tasks**, and the change takes effect
**within 1 API call** of the order, under "idle never happens". Plus: a ps-free reconciler census.

## Measured facts (cite these; do not re-litigate)

- **P3** (notes/P-probes.md): a localhost proxy at `ANTHROPIC_BASE_URL` swapping the `Authorization` bearer on
  `/v1/messages` moved ONE live turn from next2 to next3 between tool calls: billed org `fb09ef51 → 1a71eca0`,
  turn completed, transcript linear.
- **P4/P5/P6**: client-native swap with NO bearer injection: launch with `CLAUDE_SECURESTORAGE_CONFIG_DIR=<private dir>`
  holding an inference-only copy (refreshToken null) of the account's claudeAiOauth in `.credentials.json`; atomically
  rewrite it with another account's copy; the client sends the new bearer on its NEXT request (`wA()` mtime
  change-check runs before every API request, S01/S14). Works in `-p`, direct to api.anthropic.com (one 404
  thread_not_found recovered by the client's thread layer), and in the real interactive TUI. No keychain item created.
- **P6**: after any zero-restart swap, `metadata.user_id.account_uuid` keeps the ORIGINAL account (next2) on every
  request, even after idle and in the interactive TUI. Bearer-account ≠ metadata-account until a restart on the
  target account's config dir. (G4 notes may refine this.)
- **P2**: behind a non-`api.anthropic.com` base URL the client drops tool search (24 inline tools, ~2× request
  bytes) and blanks account_uuid; `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` (internal, underscore-prefixed)
  restores `pi()`-gated features but not `Of()`-gated ones (server-side threads, Remote Control). All non-inference
  endpoints (profile, usage, policy limits, bridge) bypass ANTHROPIC_BASE_URL (hard-coded BASE_API_URL, S03).
- **P3/P5 cache**: a switch re-creates only the conversation-specific prefix once on the new org (the ~10.9K
  system/tool prefix was already warm there); caching resumes on the next call. Same order of cost as a resume.
- **P7**: restart fallback (SIGTERM mid-turn, `--resume` same uuid on another account with
  `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`): background Bash job killed; the model re-ran it. S04: Monitor tasks die;
  workflows marked stopped; in-process teammates die; background subagents auto-restart from transcript (≤48 h);
  /goal restored with counters reset; Esc-then-/exit never auto-continues.
- **P8**: two live processes on one transcript both write; the transcript branches; no lock across config dirs.
- **Retry loop** (`Khe()` @12388136, read by the lead): after a 401 the client runs its 401 handler, rebuilds the
  client (re-reading the store) and retries a bounded number of times; a token changed in the store between attempts
  is adopted. So a copied token that dies when its source refreshes costs one 401 + retry if the broker re-copies.
- **Refresh hazard** (S01, S05, S09): refresh tokens rotate and are single-use; two stores holding one refresh token
  → the second refresh gets invalid_grant → `jhr()` blanks that store (logout). Copies MUST be inference-only
  (refreshToken null). Whether a refresh revokes the previous ACCESS token is accruing (P9).
- **Sibling-login adoption** (lead read @32402506): the interactive host subscribes to credentials-changed-on-disk
  and runs `_adoptSiblingLogin()` (re-verify, managed-settings refresh, `loginCompleted()`) — flag
  `tengu_streamed_thimble` default on. It did not re-key account_uuid in P6.
- **Background sessions** (S12): supervisor is per config dir and always forces its own CLAUDE_CONFIG_DIR; respawn
  cannot change account; `/background` forks.
- **Built-in gateway** (S11): enterprise/API billing; global upstream list; not subscription; not session-aware.
- **Hooks** (S10): 33 events; no hook output touches credentials or process env; a hook can only trigger an
  external actor.
- **setup-token** (S13): 1-year inference-only token, no refresh token, needs a human browser sign-in per account.
  **Operator ruling `a90e1ac2597e` (2026-09-08): "drop long-lived setup-tokens entirely … No token files are ever
  created."** Any design using setup-tokens must state `Replaces: a90e1ac2597e — ruling pending`.
- **Policy** (S08, dated sources): owning several Max accounts is not forbidden (informal employee post 2026-02-18).
  Rotating own accounts to stretch limits: unaddressed; Usage Policy effective 2026-11-12 adds "create multiple
  accounts, to … circumvent product guardrails" (guardrails undefined). Subscription OAuth outside the official
  client is forbidden for third-party tools; current legal page: "developers may not collect, store, or intermediate
  Claude.ai credentials"; from 2026-11-12 "Resell, proxy … services that route requests through consumer
  subscriptions". S08 exposure ratings: restart-on-own-account Low (75% not a breach); keychain/store rewrite
  Low-Moderate (60%); token-swapping proxy Moderate-High (45% clear violation today, 70% citable). S09: one ban
  linked to a pooling proxy (TeamClaude #529, 2026-10-07, 54 min after adding the account).
- **Incumbent** (S05): 27 of 43 gates exist only because of exit+relaunch. Survive any design: prompt-cache rewrite,
  "owes a turn" nudge after a cap, one actuator per session, duplicate/bg-split handling, intent + router admission,
  account attribution. ~68 files key "account" on config_dir. Graveyard: C1 credential-flip design B′ (14%
  conviction, packet `745e0fdc78e6` still open: "wait for the next wall"), never built.
- **Census** (S07): one in-process `sysctl KERN_PROC_ALL` = 3.3 ms for 2,167 rows at load 624 vs `/bin/ps` timing out
  at 42 s (97 'ps degraded' events, 15 blind passes 22:43–22:56 CDT 2026-10-24). Args via `KERN_PROCARGS2` on a
  bounded worker thread; root `login` rows need KERN_PROC_ALL (proc_pidinfo EPERM).

## Operator rulings and constraints (binding)

- Never launch filler sessions to burn quota (decision 8f9618059700 vetoed). Accounts are interchangeable.
- Zero human-in-the-loop prompts is the goal; permissions arrive as numbered migrations the operator runs; agents
  never edit settings.json. Implementation runs as dispatched `/handoff` sessions, one per wave, each owning an
  exclusive file set; every new mechanism ships with an env kill switch.
- Land only via the project-local `/ship`; ~/.claude is a symlink farm over the repo checkout.
- `lib/claude-launcher.zsh` is the launcher every session goes through (env injection point at launch).

## Mechanism enumeration (every way a running session could change account; architects may add more)

| # | Mechanism | Mid-turn? | Evidence |
|---|---|---|---|
| M1 | Incumbent: wait idle → /exit → `--resume` on target config dir | no (waits) | S05, S06 |
| M2 | Kill mid-turn → `--resume` on target + `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` | yes, lossy | P7, S04, S12 crash-revival |
| M3 | Esc at a tool boundary → /exit → resume → typed "continue" | yes, lossy; Esc+exit never auto-continues | S04 |
| M4 | Hook-triggered boundary move (PostToolUse/PostToolBatch hook signals the mover) | trigger only | S10 |
| M5 | Rewrite the home account's keychain item | yes, but moves every session of that dir; refresh collision | S01, S10, G1 |
| M6 | Per-session credential lane (`CLAUDE_SECURESTORAGE_CONFIG_DIR`) + inference-only copy swap | YES, measured | P4, P5, P6, S14, G2 |
| M7 | Localhost proxy via `ANTHROPIC_BASE_URL`, bearer injection on /v1/messages | YES, measured | P3, S03, S09 |
| M8 | Same as M7 over `ANTHROPIC_UNIX_SOCKET` | likely yes | S13 (~4,026,914) |
| M9 | `HTTPS_PROXY` CONNECT + TLS interception (custom CA) | yes in principle | rejected: MITM + CA trust |
| M10 | apiKeyHelper | API-key billing only | S02/S05 graveyard (rejected 3×) |
| M11 | `CLAUDE_CODE_OAUTH_TOKEN` env | read at launch; env of a running process is not externally writable | S01 |
| M12 | FD token (`CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR`) | cached once | S05 G7 |
| M13 | setup-token per account | as client credential: reduced scopes; as injected token: works | S13; ruling a90e1ac2597e |
| M14 | Plugin hook `$.env.set` changing the token env in-process | unverified | S09; I2 (pending) |
| M15 | `/login` in session | idle + browser only; rewrites the dir's item | S04 |
| M16 | Built-in `claude gateway` | enterprise/API billing | S11 |
| M17 | Background-session respawn / attach | supervisor forces its own config dir | S12 |
| M18 | SDK host `getOAuthToken` callback / host-managed auth | SDK-hosted sessions only, not TUIs | S01, Khe @12388136 |
| M19 | `CLAUDE_CODE_OAUTH_401_WAIT_MS` rotated-token poll | polls env/FD that cannot change externally | S01 |
| M20 | New pane, new session on target (operator's manual alternative) | a new session, not a move | brief |
| M21 | Fork-and-retire (`--resume --fork-session`, `/background`) | forks by definition | S12 |
| M22 | SIGSTOP source at a tool boundary, resume on target, kill source | same losses as M2 | P7, P8 |

## Files

All research notes: this directory (`S01`–`S14`, `G*` gap fills, `P-probes.md`). CC 2.1.293 extracted source:
`/tmp/mtam/cc293-src.js` (52 MB, grep with byte offsets).
