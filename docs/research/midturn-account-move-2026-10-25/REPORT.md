# Moving a live Claude Code session between Max accounts mid-turn — ground-up design

2026-10-25 · Claude Code 2.1.293 · ground-up rebuild of one subsystem (account move for limit recovery and
strand-aware rebalancing, plus the reconciler's ps-free census) · design only, no implementation.

Scope (frozen): a landed design report at `docs/research/midturn-account-move-2026-10-25/REPORT.md` that
(1) enumerates every mechanism by which a running session could change account mid-turn, (2) measures each with a
non-destructive probe on this machine, (3) picks a winner by judge panel, (4) gives an implementation wave table
sized for dispatched sessions with exclusive file ownership, and (5) files the operator decisions it cannot settle
at >90% conviction. Design target: a busy session changes billing account with **0 transcript forks, 0 lost turns,
0 killed background tasks, effective within 1 API call of the order**, under the standing constraint that **idle
never happens**.

<!-- §0 ANSWER is written after the judge panel; see below -->

## 1. The standing constraint: idle never happens

Today's mover (`cc-lr move` → `lr-move-worker.sh` → `lr-handoff.sh --in-place` → `handoff-fire.sh --recycle`)
waits for idle, types `/exit` and relaunches `claude --resume <uuid>` on the target config dir. It must wait,
because `/exit` kills the in-flight turn and two processes on one transcript fork it (P8). Measured from disk
(notes/S06, 20 most recent transcripts across the four stores, 268 inter-turn gaps):

| measure | value |
|---|---|
| inter-turn gap p10 / p50 / p90 | 0.0 s / 6.3 s / 1,573 s |
| share of wall time mid-turn (last 3 h) | 66.8% |
| sessions ≥99.8% mid-turn | 11 of 20 (4 never ended a turn) |
| turn starts the operator typed | 10 of 268 (the rest: task notifications 78, hook continuations 64, Stop-hook feedback 60, peer mail 52, /goal 3) |
| move-lane busy/goal rows → moved, all time | 149 → 5 (3.4%); already-idle rows 199 → 49 |
| tonight (06:38–06:54Z) | 1 of 9 busy rows moved, 0 of 4 goal rows; pane 194 read mid-turn on 67 of 67 snapshots |

The lead's own session also never moved: its batch census kept classifying it mid-turn while it sat idle for
~8 minutes (pane 314 report, 02:10 CDT). A design that waits for idle is a design that does not move.

## 2. Every mechanism, and what each one does to a live session

Measured on this machine with throwaway sessions (notes/P-probes.md) or read from the 2.1.293 source
(`/tmp/mtam/cc293-src.js`, byte offsets in the notes).

| # | Mechanism | Changes account mid-turn? | Fork? | What it loses | Evidence |
|---|---|---|---|---|---|
| M1 | Incumbent: wait for idle → `/exit` → `--resume` on target dir | no — waits; 3.4% of busy rows ever move | no | the wait itself; cache rewrite; 58–129 s outage per move | S05, S06 |
| M2 | Kill mid-turn → `--resume` on target with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` | yes | no (if the old process is dead first) | in-flight API stream; running background Bash and Monitor (killed, model re-runs them); in-process teammates; workflows marked stopped | **P7**, S04, S12 |
| M3 | Esc at a tool boundary → `/exit` → resume → typed "continue" | yes | no | as M2, and Esc+exit never auto-continues, so a keystroke is needed | S04 |
| M4 | Hook at a tool boundary triggers the mover | trigger only — no hook output reaches credentials or env | — | — | S10 |
| M5 | Rewrite the home account's keychain item | yes, but for every session of that dir | no | refresh-token collision logs an account out | S01, S10, G1 |
| **M6** | **Per-session credential lane: `CLAUDE_SECURESTORAGE_CONFIG_DIR` holding an inference-only copy; swap = atomic file rewrite** | **yes — next API call** | **no** | conversation cache re-created once on the new account; request metadata keeps the old account id | **P4, P5, P6**, S14, G2, G3 |
| **M7** | **Localhost router at `ANTHROPIC_BASE_URL`, bearer swapped on `/v1/messages`** | **yes — next API call; can also fail a 429 over before the client sees it** | **no** | tool search and identity unless `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1`; server threads and Remote Control always | **P1, P2, P3**, S03, S09 |
| M8 | M7 over `ANTHROPIC_UNIX_SOCKET` | likely | no | as M7, bootstrap skipped | S13 |
| M9 | `HTTPS_PROXY` + TLS interception | in principle | no | requires a trusted local CA — rejected | — |
| M10 | `apiKeyHelper` | API-key billing only, not the subscription | — | — | S05 graveyard (rejected 3×) |
| M11 | `CLAUDE_CODE_OAUTH_TOKEN` env | no — read at launch; nothing outside can change a running process's env | — | — | S01 |
| M12 | FD token | no — read once | — | — | S05 |
| M13 | `claude setup-token` per account | as the session's own credential: reduced scopes; as a router's injected token: works | — | needs a browser sign-in per account; **ruled out by `a90e1ac2597e`** | S13 |
| M14 | Plugin hook `$.env.set` changing the token env in-process | see notes/I2 | — | — | S09, I2 |
| M15 | `/login` in session | only at an idle prompt with a browser; rewrites the whole dir's item | — | — | S04 |
| M16 | Built-in `claude gateway` | enterprise/API billing, global upstream list | — | — | S11 |
| M17 | Background-session respawn / attach | no — the supervisor forces its own config dir | — | — | S12 |
| M18 | SDK-host `getOAuthToken` callback | SDK-hosted sessions only, not TUIs | — | — | S01, `Khe` |
| M19 | `CLAUDE_CODE_OAUTH_401_WAIT_MS` rotated-token poll | polls an env/FD nothing outside can change | — | — | S01 |
| M20 | New pane, new session on the target (the operator's manual move) | a new session, not a move | — | the conversation | — |
| M21 | Fork-and-retire (`--fork-session`, `/background`) | yes | **yes, by definition** | — | S12 |
| M22 | SIGSTOP at a tool boundary, resume on target, kill source | yes | no | as M2 | P7, P8 |

## 3. Measurements

All probes ran throwaway Claude Code sessions this session started itself, in hermetic config dirs; no live pane,
account keychain item or settings file was touched (method and raw numbers: notes/P-probes.md). Billing is read from
the response header `anthropic-organization-id` (next2 `fb09ef51`, next3 `1a71eca0`) and corroborated by the weekly
utilization header (0.02 vs 0.17, matching `claude-accounts` at 02:10).

| probe | what it showed |
|---|---|
| P1 | A subscription session honors a localhost `ANTHROPIC_BASE_URL`; the client retried a dead local hop 11–12 times rather than failing at once. |
| P2 | Behind a non-first-party host the client drops tool search (24 inline tools, 89 KB vs 49 KB request) and blanks `account_uuid`; `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` restores both. |
| P3 | **Router swap mid-turn:** one turn of three tool calls billed next2 for call 1 and next3 for calls 2–4. The turn completed; the transcript is linear (29 records, no branch, 3/3 tool results). |
| P4 | **Lane swap mid-turn, client-native:** rewriting the private credential file after call 1 made the CLIENT send next3's bearer on call 2. No keychain item was created. |
| P5 | Same as P4 straight to api.anthropic.com: the first call on next3 got a 404 (the server-side thread lives on next2's org), the client's thread layer re-sent it, and the turn finished on next3. |
| P6 | Same in the real interactive TUI (private tmux socket): calls after the swap billed next3, including an idle follow-up 26 s later. **`metadata.account_uuid` stayed next2's on every call** — confirmed in source by G3/G4: only `/login` re-keys identity. |
| P7 | Restart fallback: killing mid-turn and resuming on next3 with the interrupted-turn flag continued the same transcript, but the running background job died and the model re-ran it. |
| P8 | Two live processes resuming one session both wrote; the transcript branched, with no lock or warning. |
| P9 | Accruing: whether an account's own refresh revokes its previous access token (`/tmp/mtam/probe/revoke-watch.log`, ≈03:57 CDT). The design recovers either way (§4). |

Cache cost of a switch (P3, P5): the ~10.9K-token system/tool prefix was already warm on the target org; only the
conversation-specific prefix is re-created once, then caching resumes. That is the same order of cost as any resume.
Request coverage (G3): every inference path — main loop, in-process subagents, the auto-mode classifier, compaction
and side queries — rebuilds its client per request and so adopts a swap at its next call; only the cache keepalive
holds a client (≤240 s), and a request already streaming finishes on the old account.
