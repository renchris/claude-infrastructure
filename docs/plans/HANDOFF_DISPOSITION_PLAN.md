# /handoff Post-Fire Disposition Contract — close, or explicitly-open

**Scope (frozen, from the user's ask 2026-07-11):** after a handoff fires, the main session must
either (a) CLOSE itself when nothing remains, or (b) stay open ONLY with an explicit, concise,
zero-ambiguity declaration of WHY — drawn from a CLOSED reason taxonomy (open 2-way comms
before/during/after the fired session's run · ongoing user↔Claude discussion · open decisions ·
current/follow-on work) — plus, per reason, the exact condition that discharges it and the action
that then completes-and-closes the session exhaustively. 100th-percentile implementation; Fable
authorized for the contract wording.

## Phase 0 — Agent Team Orchestration

Sizing: ~250-350 LOC (1 command-doc rewrite + 1 helper script + bats) → lead + **1 teammate**.

| Role | Who / worktree | Scope | Est |
|---|---|---|---|
| Lead (THIS fired session, Fable 5 @ high) | `/tmp/wt-handoff-disposition`, branch `handoff-disposition` | § Contract wording in `commands/handoff.md` (rewrite step 7 + new § Post-fire disposition), zero-ambiguity acceptance test, merges, landing | ~120 doc lines |
| `disposition-helper` (Opus 4.8, worktree `/tmp/wt-hd-helper` off `handoff-disposition`) | `scripts/handoff-disposition.sh` (un-fakeable-reads helper, spec below) + `tests/handoff-disposition.bats` (repo convention) | ~200 LOC |

One wave; disjoint files; lead merges (ff/cherry-pick), gates, lands per § Constraints C2.
Pre-spawn checklist per `~/.claude/rules/agent-teams.md` (brief ≤150 lines, line ranges embedded,
"stop on issue, message lead" verbatim).

## Motivation (the gap, observed live 2026-07-11)

`/handoff` step 7 says self-close when "exhaustively nothing further" — but it is judgment-only,
emitted nowhere, and never re-evaluated. Observed: sessions fire a track and then linger open with
no stated reason (the ship-hardening fire from wt-pool-4 stayed open — correctly, the user was mid-
conversation — but the WHY was never declared, and nothing defines when that reason lapses). The
user's requirement: no ambiguity, ever, about why a post-handoff session is open and what
exhaustively closes it.

## Design — the Disposition Contract (lead refines wording; semantics are FROZEN)

**After EVERY fire (any mode, every track), and at the END OF EVERY SUBSEQUENT TURN until close,**
the firing session emits exactly ONE of:

- `🔚 DISPOSITION: CLOSE — nothing remains in this session.` → then `handoff-fire.sh self-close`
  AS THE TURN'S LAST ACTION (dirty-tree guard applies; never after `--recycle`).
- `⏳ DISPOSITION: OPEN — <R-CODE>: <specific instance> → closes when <discharge condition> → then <single next action>.`
  (one clause per live reason; multiple reasons = multiple clauses, worst-first)

**Closed reason taxonomy** (NO other reason may hold a session open; "just in case" / "might be
useful" is banned — if no reason fits, the session closes):

| Code | Reason | Discharge condition | On discharge |
|---|---|---|---|
| R-PING | awaiting back-channel from fired session(s) `<slug…>` — before (about to fire more tracks), during (decision-gate/blocker pings), or after (completion ping). Armed by `--notify-back`; pair with background `cc-await-ping` so discharge is event-driven, with its timeout as the fallback wake | ping arrives (or timeout → check fired-pane liveness via `cc-sessions`; dead peer → escalate to R-DECIDE) | process ping → re-emit disposition |
| R-USER | user is mid-conversation / a reply is plausibly incoming (the user's LAST message is unanswered, or they said "stay open") | user's message handled and no new reason opened; or user says "close it"/goes idle after an offered close | re-emit disposition |
| R-DECIDE | a named open decision / STOP-ASK the user must rule on | user rules | act on ruling → re-emit |
| R-WORK | named current/follow-on work THIS session owns (not delegated) | work done, verified, committed | re-emit |
| R-DIRTY | uncommitted in-scope changes in this worktree (self-close would refuse anyway) | task-clean commit | re-emit |

**Kill-switches:** user "close now" → CLOSE this turn (commit first if R-DIRTY; `--allow-dirty`
only on explicit user say-so). User "stay open" → standing R-USER until they release it.
**No Stop hook** — same rationale as the Session Close Protocol (advisory hooks are inert,
blocking hooks are an anti-pattern); this is command discipline plus the deterministic helper.

**Helper script `scripts/handoff-disposition.sh`** (un-fakeable reads; model adds only the
R-USER/R-DECIDE judgment): prints JSON + a one-line human summary of the MECHANICAL reasons —
`{dirty: <n paths>, mailbox_pending: [uuid…] (from ~/.claude/mailbox/), await_ping_running: bool,
fired_peers_alive: [name…] (cc-sessions ∩ this session's fired slugs, passed as args),
open_tasks: <n in_progress/pending from TaskList files if resolvable>}` — exit 0 = no mechanical
reason (close-eligible pending judgment), 1 = mechanical reasons exist. Bats-test each read
against fixtures. The command doc instructs running it before every disposition emission.

**Integration points** (all in `commands/handoff.md`): step 6 fire report gains a per-track
`notify-back?` column; step 7 is REPLACED by "§ Post-fire disposition" (the contract above);
§ 8 (two-way) cross-references R-PING arming; the readiness-gate list and the disposition
taxonomy must not drift apart (single table, referenced twice).

## Tasks
- T1 (lead): rewrite `commands/handoff.md` step 7 → § Post-fire disposition; wire step 6/§ 8
  cross-refs. The wording must pass the zero-ambiguity gate (below).
- T2 (teammate): `scripts/handoff-disposition.sh` + `tests/handoff-disposition.bats`
  (shellcheck -S warning green; macOS bash-3.2 safe — no mapfile/assoc arrays).
- T3 (lead, after merge): E2E demo both paths in a scratch fire: one fire that ends
  `DISPOSITION: CLOSE` + actually self-closes; one that stays `OPEN — R-PING …` and closes on the
  ping. Transcript excerpts into the plan's status log.

## Acceptance gates
1. **Zero-ambiguity test** on the contract text: every OPEN emission structurally forces
   (reason code) + (specific instance) + (discharge condition) + (next action); the taxonomy is
   closed; a reader can always answer "why is this session open and what ends that?" from the
   emission alone.
2. Helper: bats green; shellcheck green; exit codes as specced; degrades cleanly when
   cc-sessions/mailbox absent.
3. E2E (T3) both paths observed live, incl. the self-close (graceful, ≤180s watcher ceiling).
4. Landing verified by CONTENT (paths on origin/main) + stranded-sweep; see C2.

## Constraints
- **C1** Shared checkout `~/Development/claude-infrastructure` is READ-ONLY; dedicated worktrees only.
- **C2 CONCURRENT TRACK — ship-hardening** (`/tmp/wt-ship-hardening`, branch `ship-hardening`) is
  editing `commands/ship.md`, `CLAUDE.md`, `scripts/land-lock.sh`, `scripts/stranded-sweep.sh`,
  `tests/land-lock.bats`, `tests/stranded-sweep.bats` in this SAME repo. Your files
  (`commands/handoff.md`, `scripts/handoff-disposition.sh`, `tests/handoff-disposition.bats`,
  this plan) are DISJOINT — keep them so. **Land AFTER ship-hardening's locked flow reaches
  origin/main** (poll for `scripts/land-lock.sh` on origin/main) and land THROUGH it; if it
  hasn't landed within your session, land with manual last-moment tip re-fetch + content-verify
  + `git cherry` stranded sweep (the 2026-07-11 dfacccd drop is the incident you are guarding
  against — see `docs/plans/SHIP_LAND_HARDENING_PLAN.md` on branch `ship-hardening`).
- **C3** `~/.claude/commands/handoff.md` is a SYMLINK to the repo file (verified) — edit the repo
  side only; changes go live at once, so land only gated-green text.
- **C4** Taxonomy stays CLOSED. Any candidate 6th reason goes to the plan's status log as a
  proposal, never silently into the contract.

## Status log
- 2026-07-11 02:2x — plan created + committed on `handoff-disposition` by wt-pool-4 (next4);
  fired to next3 as Fable 5 @ high. Nothing implemented yet.
