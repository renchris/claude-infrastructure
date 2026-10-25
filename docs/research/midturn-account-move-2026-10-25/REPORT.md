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

## 0. Answer

**Yes: a live, busy Claude Code session can change which Max account pays, mid-turn, with no restart, no transcript
fork and no lost work — measured on this machine, three ways.**

- The client re-checks its credential store before **every** API request, on every inference path (main loop,
  subagents, classifier, compaction). Launch a session with `CLAUDE_SECURESTORAGE_CONFIG_DIR` pointing at a
  per-session "lane", change the lane, and the next API call bills the new account (P4, P5, P6 — including direct to
  api.anthropic.com and in the real interactive TUI).
- A mod hook can choose the lane **per request** (`turn.step` → `$.env.set`, P11), and a hot-reloaded mod can bind an
  **already-running** session to a lane at its next turn end, with no restart (P10). 40 of 42 live sessions already
  load such a mod.
- A localhost proxy swapping the bearer also works (P3) but is rejected: a single point of failure for every
  session, lost features, and the highest policy exposure.

**Recommended design** (judge-panel winner A4 with grafts, plus one amendment from the last probes): every session
gets a lane; a move is a journaled lane change adopted at the next API call (≤30 s in the worst case for the
recommended form); identity re-aligns at the session's next natural restart; the reconciler census goes ps-free
(3.3 ms vs 42 s `ps` timeouts). The amendment: since an account's refresh **revokes its previous access token at
once** (P9), lanes should **point at the target account's own store** rather than hold copied tokens. That needs no
token files (so the setup-token ruling is untouched) and no broker refreshing on the accounts' behalf; a first-wave
probe confirms it before anything is built on it.

**The catch, and the decision only the operator can make:** after a zero-restart move, Anthropic's servers see
requests whose bearer is one of the operator's accounts while the request metadata still names the original one,
until the session next restarts (P6). The 2026-11-12 Usage Policy adds "create multiple accounts, to … circumvent
product guardrails" without defining guardrails, and one panel architect declined to design this at all. The design
therefore lands everything **off** and asks first (§13). Today's restart-based mover moved 5 of 149 busy rows (3.4%);
the target is ≥99%.

Implementation: 13 waves for dispatched sessions with exclusive file ownership, ≈13K lines, two of them
(census, attribution) policy-neutral and useful even if the answer is no (§12).

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
| M14 | Mod hook `$.env.set('CLAUDE_CODE_OAUTH_TOKEN')` | yes, next request [I] | no | the token sits in `process.env` and reaches every child the session spawns; the env token is pinned on 401 | I2 — rejected |
| M15 | `/login` in session | only at an idle prompt with a browser; rewrites the whole dir's item | — | — | S04 |
| M16 | Built-in `claude gateway` | enterprise/API billing, global upstream list | — | — | S11 |
| M17 | Background-session respawn / attach | no — the supervisor forces its own config dir | — | — | S12 |
| M18 | SDK-host `getOAuthToken` callback | SDK-hosted sessions only, not TUIs | — | — | S01, `Khe` |
| M19 | `CLAUDE_CODE_OAUTH_401_WAIT_MS` rotated-token poll | polls an env/FD nothing outside can change | — | — | S01 |
| M20 | New pane, new session on the target (the operator's manual move) | a new session, not a move | — | the conversation | — |
| M21 | Fork-and-retire (`--fork-session`, `/background`) | yes | **yes, by definition** | — | S12 |
| M22 | SIGSTOP at a tool boundary, resume on target, kill source | yes | no | as M2 | P7, P8 |
| **M23** | **Retrofit: a hot-reloaded `--plugin-dir` mod calls `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', lane)` from `session.start`** | at the session's next turn end | no | nothing; cannot reach a session that never ends a turn | **P10**, I2 |
| **M24** | **Per-request routing: the same mod sets the lane variable from `turn.step`, before every model request** | **yes — next API call** | no | nothing beyond M6 | **P11** |
| M25 | Live rebind through the settings `env` block | yes | no | rebinds every session at once (all four settings.json are one file); agents may not edit settings | G2 — rejected |
| M26 | Ordered `oauthAccount` rewrite + bootstrap-slot deletion to re-key identity in place | identity only | no | touches a config dir's shared `.claude.json`; write-once suppression and "poisoning" | G2-bootstrap — rejected |
| M27 | Re-home at the next natural restart (relaunch under the billing account's config dir) | no (closes identity later) | no, with a prove-death barrier | nothing extra | A4, SYNTHESIS §3.8 |

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
| P9 | **An account's own refresh revokes its previous access token at once.** next3 refreshed at 03:58:14 with 262 s left on the old token; the old token failed "OAuth token revoked" 8 s later and again 2 min later; the new one worked. Every COPY of an access token therefore dies at each source refresh (~every 8 h per account), and the client only retries an unchanged token twice (`wur=2`). |
| P10 | **Retrofit without restart:** a running TUI launched with a no-op `--plugin-dir` mod; the module was rewritten to call `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', <next3 lane>)` at `session.start`. It reloaded at the turn end (no consent prompt), and the next turn billed next3. 40 of 42 live interactive sessions already load the `accounts-readout` mod. |
| P11 | **Per-request routing from a hook:** a mod whose `turn.step` hook sets the lane variable from a route file. Flipping only the ROUTE FILE after call 1 billed calls 2–4 of the same turn to next3. No credential was written mid-turn. |

Cache cost of a switch (P3, P5): the ~10.9K-token system/tool prefix was already warm on the target org; only the
conversation-specific prefix is re-created once, then caching resumes. That is the same order of cost as any resume.
Request coverage (G3): every inference path — main loop, in-process subagents, the auto-mode classifier, compaction
and side queries — rebuilds its client per request and so adopts a swap at its next call; only the cache keepalive
holds a client (≤240 s), and a request already streaming finishes on the old account.

## 4. The design

Full specification: `notes/SYNTHESIS.md` (the panel synthesizer's document, critic-patched). This section states
what it decided, plus the amendment the last three probes (P9–P11) force, which ran after the panel had scored.

### 4.1 Verdict

**Winner: A4, the "lane now, re-home later" hybrid** (SYNTHESIS §1), with grafts from every runner-up:

- **The move** is a change of the session's *credential lane* — the store named by
  `CLAUDE_SECURESTORAGE_CONFIG_DIR` — which the unmodified client re-checks before every API request (`wA()` via
  `EN()` → `j7()` → `Pl()`, S01, G3). Nothing exits, so there is no fork, no lost turn, no killed background task,
  and billing changes at the next API call (P4, P5, P6, P11).
- **Rollout needs no restart.** A module inside the already-loaded `accounts-readout` mod binds each live session to
  its lane with `$.env.set` when it next ends a turn (P10); new launches are laned at birth by
  `lib/claude-launcher.zsh`.
- **Identity is re-aligned later**, at a restart the session was going to have anyway (recycle, crash revival,
  reboot resume, upgrade, manual resume): it relaunches under the billing account's config dir, and request
  metadata matches again (A4 → SYNTHESIS §3.8).
- **Grafts:** prove-death before any relaunch and an operator-only "restart now" fallback for sessions that never
  end a turn (A3); a first-hand utilization sensor from the mod's `session.measure` instead of a proxy (A2);
  broker-enforced lane hygiene (A1); a written policy gate before anything goes live (A5).
- **Rejected:** the bearer-swapping router (A2) — a correlated single point of failure for every session, feature
  loss behind a non-first-party host, and the highest policy exposure — and A3 as the primary mover, because it
  misses three of the four target clauses by construction and six of its load-bearing claims were refuted (§15).

Conviction **70%** that this is the right design to build (SYNTHESIS §1); whether to build it at all is the
operator's policy call (§13, first decision).

### 4.2 Amendment: point lanes at the account's own store instead of copying tokens into them

The synthesis specified **copy lanes**: each session gets a private lane holding an access-only copy of its billing
account's token (`refreshToken: null`), kept fresh by a broker that mirrors every source refresh and, for an account
no native session refreshes, runs the refresh itself (SYNTHESIS §3.3, §3.7). Two measurements taken after the panel
change the balance:

- **P9:** a refresh revokes the previous access token at once, so every copy dies at each source refresh. The client
  rebuilds and retries after a 401 but gives up after two attempts with an unchanged token (`wur=2` @12384870). A copy
  lane therefore works only if the broker re-mirrors within ≈2–3 s of every refresh (≈12 a day across the fleet), and
  a broker outage turns into fleet-wide 401s at the next refresh — the synthesis's fail-safe unbind (§3.11) exists
  for exactly this.
- **P11:** the binding hook can select the lane **per request**, from a route file, mid-turn.

That makes a simpler form available — **pointer lanes**: the session's lane variable points at the billing account's
**real** config dir (the exact path string, so the client resolves that account's own keychain item, refresh lock
and compare-and-swap save). A pointed session is, for credentials, one more native session of that account:

| | copy lane (SYNTHESIS default) | **pointer lane (recommended)** |
|---|---|---|
| tokens written by the mover | an access-only copy per session (keychain item + 0600 file) | **none** — the route file names a directory |
| ruling `a90e1ac2597e` ("no token files are ever created") | needs an exception (SYNTHESIS Q2) | **not implicated** |
| survives a source refresh (P9) | only if the broker re-mirrors within the 2-try retry window | **yes** — it reads the store that was just refreshed; a 401 re-reads it (`recovered_from_keychain`) |
| who refreshes an account with no native sessions | the broker, via the official binary (SYNTHESIS Q4) | **the pointed sessions themselves**, under the account's own lock |
| broker or mover death | lanes go stale at the next refresh → fail-safe unbind | sessions keep the last pointer, which stays valid |
| adoption after a move | next API call (file mtime clears both caches) | next API call, **or up to 30 s** while the per-session keychain read cache (`PK()` @3738325, one slot per host, `cPt=30000`) still holds the previous account |
| new hazard | — | a pointer change while a refresh of the old account is in flight inside the same process could save the rotated grant into the new account's item; guard: never re-point while the old account's token is within 6 min of expiry or its `.oauth_refresh.lock` is held |
| MCP sign-ins inside the session | copied from home, access part only (SYNTHESIS Q8) | the billing account's own |

The 30 s ceiling is irrelevant to rebalancing and to the pre-wall drain (§4.4); it matters only to a move made after a
session has already hit a wall, which ends its turn anyway (429s are not retried onto a new bearer, G3). **Wave W0
decides the form** with probe **P-P1**: a throwaway session pointed at a real account's store, moved mid-turn to
another real store, measuring adoption time, billing, the expiry guard, and that the only keychain writes are the
ordinary refreshes any session of that account performs. If P-P1 fails, the copy form ships exactly as SYNTHESIS
§3.3–§3.7 specifies (conviction 70% that P-P1 passes and pointer lanes ship).

### 4.3 How a move runs

1. An order — operator `cc-lr move`, the strand-aware rebalancer, or the reconciler at a wall — writes
   `~/.reso/lanes/requests/<id>.json`.
2. The lane broker (launchd, single writer per lane) admits it: the target account is not walled or unknown, the
   session's bound process is alive by single-pid checks (no `ps`), one actuator per session, cooldown.
3. It journals `prepared`, changes the lane (pointer: rewrites the route record; copy: §3.3 write order under the
   lane's storage lock), read-back verifies, journals `committed` with the commit time.
4. The session's next client build adopts it: next API call (≤30 s for a pointer under a warm keychain cache). A
   request already streaming finishes on the old account (G3). The first call on the new org takes one 404
   thread replay (≈225 ms, P5) and one re-creation of the conversation prefix.
5. A proof pass marks it `proved` (lane state + a post-commit request in the transcript + one holder + linear
   transcript) or loudly `SWAP-UNPROVEN` after 600 s — never silently reverted (SYNTHESIS §3.4, R19).

Order to commit: ≈2–5 s of mover time (estimate). Sessions the retrofit cannot reach (never ended a turn since
rollout — 2 of tonight's 9 busy sessions) move only at a turn end, at a natural restart, or on an explicit
`--restart-now` order (M2, with its losses).

### 4.4 Limit walls and strand-aware rebalancing

- **Pre-wall drain (primary):** the shed controller projects each account's 5-hour and weekly landing from the
  mod's `session.measure.rateLimits` (which reports the billed org after a move) and moves sessions off an account
  before it walls. A busy session moves in place, so the wall is never hit.
- **Reactive:** a capped turn ends (subscriber 429s are not retried onto a new bearer). The reconciler, now
  attributing the wall to the session's *billing* account, moves it and wakes it through the existing
  api-error rewake watchers; a `/goal` in `usage_limit_waiting` resumes on any message. Today's median from
  detection to engaged is 81 min (S05); the design target is one pass + seconds.
- **Rebalance:** the 2026-10-24 strand-aware design (`docs/research/account-rotation-100p-2026-10-24/`, components
  C1–C3, not yet built) with the lane as its actuator. The holds that existed only because of exit+relaunch
  (mid-turn, background job, subagents, goal-live, draft, focus) vanish; one-actuator, duplicate-session, intent and
  router holds stay. A move must pay for its cache re-creation (`b_wk × min(sink_h, 96) ≥ 10 × cost_pp`), 6 h
  cooldown, no filler sessions, no move-back after a reset. Automatic rebalancing is gated separately (§13).

### 4.5 Identity

Request metadata (`metadata.user_id.account_uuid`) comes from the session's config dir and an in-memory record, not
from the bearer (G4; P6 measured it unchanged after every zero-restart move). An in-place re-key exists only through
fragile paths (a model change, or rewriting a config dir's shared `.claude.json` — M26, rejected). So the design
models identity as `{home, billing, unknown}`, never asserts it, and closes the mismatch at the next natural restart
by relaunching under the billing account's config dir after proving the old process dead (R1) — the transcript is
cold-transplanted, the source retired only on confirm. Estimated mismatch window: median ≈19–20 h, p90 68–115 h
(launch-log renewal estimate, lower-side; accrues from the ledger).

### 4.6 The ps-free census

`lr_recon/proctable.py` replaces both `/bin/ps` reads: one `sysctl KERN_PROC_ALL` (3.3 ms for 2,167 rows at load
624, including the root-owned `login` pane roots that `proc_pidinfo` refuses), a `/dev` tty map (0.7 ms), and argv
through `KERN_PROCARGS2` on a bounded worker thread, claude processes first (9 ms for 93 processes;
0.5 s per call, 3 s per pass, at most 2 stuck readers). `/bin/ps` stalls because it walks every task's memory map
and threads with task ports — 2,200 processes and 6,600 threads — while every `ps` call timed out at 42 s in the 15
blind passes (97 `ps degraded` events in all: 92 in the current log plus 5 rotated; S07). An unreadable claude
argv makes only that row abstain. Modes `LR_RECON_PSFREE=off|shadow|on`, shadow by default; it switches on after
500 passes with zero field mismatches. It is an availability improvement, not a safety gate: moves use single-pid
checks (SYNTHESIS §3.10).

## 5. Policy and account safety

Primary texts (S08, retrieved 2026-10-25):

- **Consumer Terms** (effective 2025-10-08): no one-account clause; "You also must not … bypass[] any of our systems
  or protective measures." An Anthropic Claude Code team member, 2026-02-18: "it's not against terms of service to
  have multiple MAX accounts" (informal).
- **Usage Policy in force** (effective 2025-09-15): "Coordinate malicious activity across multiple accounts to avoid
  detection or circumvent product guardrails…".
- **Usage Policy effective 2026-11-12** (published): "…**or create multiple accounts**, to avoid detection,
  circumvent product guardrails…"; "Resell, proxy, or otherwise provide access to Claude through unauthorized
  means, including **services that route requests through consumer subscriptions** or misrepresent the product or
  client being used." Neither version defines "guardrails".
- **Claude Code legal page** (current): "developers may not collect, store, or intermediate Claude.ai credentials or
  session tokens" — its subject is third-party developers acting for their users. Subscriptions stopped covering
  third-party harnesses on 2026-04-04. One public ban is linked to a multi-account pooling proxy (TeamClaude #529,
  2026-10-07).

Exposure ratings (S08, conviction that it is NOT a breach of text in force today): restart on another of the
operator's own accounts — Low, 75% (65% after 2026-11-12); credential-store change under the official client —
Low-Moderate, 60%; a token-swapping proxy — Moderate-High, 45% (70% that Anthropic could cite a text against it).
What every zero-restart move adds that a restart does not: for hours, requests carry one account's bearer and the
other account's id in metadata (P6, G4). Whether the server treats that as anything is unknowable from the client.

One of the five panel architects (A5, "policy-minimal") **declined to design at all**: every mechanism that meets
the target "puts a copied subscription credential under a client logged into another account in order to stretch
limits", and the honest policy-minimal answer is a restart plus asking Anthropic. The pointer-lane amendment removes
the copying but not the underlying question. The design therefore ships every zero-restart switch **off**, and the
first decision (§13) is whether to ask Anthropic support in writing before turning it on, with a mandatory re-review
dated 2026-11-11 either way.

## 6. Invariants (SYNTHESIS §4, R1–R22)

R1 one writer per session at every instant (moves start no process; every relaunch proves the source dead first) ·
R2 content-verified writes (read-back fingerprints, never counts) · R3 a lane in an unknown state is never committed
· R4 timing-honest verdicts (order, commit and first-post-commit-request timestamps) · R5 unknown is never defaulted
to home; a degraded census makes one row abstain · R6 every admission check runs before the point of no return ·
R7 one actuator per session (the reconciler owns limited rows) · R8 each account's grant has exactly one holder; no
mover ever copies a refresh token · R11 intent + router admission, failing closed · R12 no filler sessions · R13 a
team moves as a unit · R14 per-version certification: arming is refused on an uncertified Claude Code build ·
R16 every helper that launches claude sets or unsets the lane variable explicitly · R18 never rewrite request
bodies, run a proxy, forge a 401, or rewrite identity records · R19 an unproven move is loud, never silently
reverted · R20 the binding module lands inert · R21 a refresh path always exists for every account · R22 bounded
external calls everywhere (`security`, `sysctl` argv reads, launchd kicks). (R9, R10, R15, R17: SYNTHESIS §4.)

## 7. Measured constants

| constant | value | source |
|---|---|---|
| inter-turn gap p50 / share of time mid-turn | 6.3 s / 66.8% | S06 |
| busy rows the incumbent ever moved | 5 of 149 (3.4%) | S06 |
| detection → engaged at a wall, today | median 81 min (n=19) | S05 |
| credential change-check | before every API request, every inference path | S01, G3 (`EN()` @8642899, `Khe` @12388136) |
| per-session keychain read cache | 30 s, one slot per host | `cPt` @3738137, `PK()` @3738325 |
| retries with an unchanged token after a 401 | 2 (`wur`) | @12384870 |
| access-token lifetime / refresh window | 28,773 s observed / last 5 min | P9, `JP` @4704535 |
| previous token after a refresh | revoked within 8 s | P9 |
| first call on a new org | one 404 thread replay ≈225 ms + one prefix re-create (6.2–8.4K tokens in probes) | P5, P3 |
| mod reload | at the next turn end; no consent prompt | P10 |
| live sessions loading `accounts-readout` | 40 of 42 | P10 census 03:07 CDT |
| census: `sysctl KERN_PROC_ALL` vs `/bin/ps` | 3.3 ms vs 42 s timeouts | S07 |
| cache keepalive client lifetime | ≤240 s | `jLn` @9777402, G3 |

## 8. Failure modes (selection; all 70+ with their structural answers: SYNTHESIS §6)

| observed mode | structural answer |
|---|---|
| busy session never idle → move queued forever (S06, tonight) | the move starts no process, so busy is irrelevant (§4.3) |
| two live writers fork a transcript (P8; 13 historical FAILED rows) | a move starts no process; every relaunch proves death and checks the background-session daemon first (R1) |
| `/exit` kills the in-flight turn; background jobs die (P7) | no exit on the move path; restart-now exists only on an explicit order |
| copied token revoked by its source's refresh (P9) | pointer lanes hold no copy; copy lanes re-mirror inside the retry window, fail-safe unbind otherwise |
| two stores holding one refresh token → `invalid_grant` logs an account out (S01, G1) | R8: no mover copies a refresh token; lanes never refresh (copy) or share the one real store (pointer) |
| pointer change during an in-flight refresh saves the rotated grant into the wrong account | never re-point inside the old account's last 6 min or while its refresh lock is held (§4.2) |
| a limit wall charged to the store account instead of the billing one (I1: `stop-failure-marker.sh:118-139`, `lr_recon/__main__.py:306-358`, `lr-handoff.sh:632-638`, …) | three-key attribution (home / billing(t) / identity); every BILLING consumer reads `billing_of` (W2, W5–W7) |
| `ps` blind at load 300–900 (97 events) | ps-free census; single-pid checks on the move path |
| broker dies | pointer: nothing goes stale; copy: lanes stale at the next refresh → module unbinds to home and pages |
| Claude Code upgrade moves an anchor (`wA`, `uw()`, `turn.step`, thread layer) | R14 per-version certification by the W0 probes; arming refused until re-certified |
| `/login` typed inside a laned pane makes the lane the grant holder | lane hygiene check pages on any lane carrying a refresh token; re-login runbook |
| mod hot-reload reaches ~40 sessions at once | the module lands inert; `bind.off` file switch; beat files prove inertness after every converge |

## 9. Rejected alternatives

| alternative | why |
|---|---|
| bearer-swapping router at `ANTHROPIC_BASE_URL` (A2, M7/M8) | single point of failure for every session with no fail-open; tool search and identity lost without an internal env override, threads and Remote Control lost regardless (P2); highest policy exposure and the one public ban |
| restart at a tool boundary as the primary mover (A3) | the mean wait to the next boundary is 421 s, 93% of tool time is in calls over 120 s; the turn is re-driven and background work dies (P7) — kept only as the explicit `--restart-now` fallback |
| rewriting an account's home keychain item (M5, including A4's "Arm T") | moves every session of that account and discards rotated grants → logs `next` out (verifier) |
| env-token through a mod (M14) | the token leaks into every child process's environment and is pinned on 401 |
| setup-tokens (M13) | ruling `a90e1ac2597e`; reduced scopes |
| apiKeyHelper, the built-in gateway, background-session respawn, `/login` | API billing / enterprise only / pinned config dir / human and idle only |
| in-place identity re-key (M26) | shared `.claude.json`, write-once suppression, poisoning; R18 |
| live rebind through settings `env` | rebinds every session at once; agents may not edit settings |
| body rewriting of any kind | R18: policy ("misrepresent the … client"), not technical, grounds |

## 10. Kill switches and rollback

Every switch defaults to the incumbent or the stock client (SYNTHESIS §8): `CC_LANE` (launchers arm no lane, default
off), `LR_LANE_BIND` (file `~/.reso/lanes/bind.off`, the real switch for live sessions, default present),
`LR_LANE_MOVE` (default off until the policy decision), `LR_LANE_FAILSAFE` (on), `LR_REHOME`, `LR_REBAL_LANE`,
`LR_MOVE_RESTART_NOW` (off and must also be passed per call), `LR_RECON_PSFREE` (shadow), `CC_BILLING` (on; with no
ledger row billing equals home, today's behavior), `LR_LANE_CERT_REQUIRED` (on). Rollback, in order: `cc-lane revert
--all` (billing back to home, no restart) → `touch ~/.reso/lanes/unbind-all` and wait until every beat reads
`lane_env:null` → set the off files → only then revert code (a module reload does not unset a value already set) →
`cc-lane gc`.

## 11. Acceptance criteria (disk reads; full list AC1–AC15: SYNTHESIS §9)

| claim | read that proves it |
|---|---|
| billing changed within one API call | ledger `committed` row + lane read-back + the first transcript record after the commit time; corroborated by `~/.reso/lanes/measure/<sid>.json` |
| 0 forks | transcript since the order: every record has ≤1 child; `cc-proctable --holders <sid>` == 1 at every pass for 600 s |
| 0 lost turns | no `[Request interrupted` and no unmatched `tool_use` in the window |
| 0 killed background tasks | same (pid, lstart) before and after; no killed/stopped task notification; `jobs/*/state.json` unchanged |
| credential safety | one refresh-token holder per account (`claude-accounts` local state `rt_fp`); `claude-accounts-lastgood-rejected.json` == `{}` |
| retrofit coverage | `cc-lane status --fleet --json`: ≥90% of live sessions that ended a turn since rollout are bound |
| busy-move rate | 7 days of busy/goal rows: ≥99% moved (today 3.4%) |
| census | `recon/shadow/ps-free.jsonl`: ≥500 passes, zero ppid/zombie/lstart/tty and zero claude-argv mismatches |

## 12. Implementation waves

Phase 0 — orchestration. **Execution locus: S (one dispatched `/handoff` session per wave, its own worktree, landing
only through the project-local `/ship`, converging with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`)**
for every wave except W9, which is **O** (a numbered migration the operator runs). Lead context budget: this section
plus each wave's returned JSON, ≤80K tokens; succession point after W3 (the first wave whose outcome depends on W0's
verdict). No file is owned by two waves (ownership from `notes/I1-account-attribution-inventory.md`). The four
limit-recover defect fixes landed in `bfe8025ff`, so their files are free. Waves land with every switch at its
default, so each land is inert until W9.

| wave | goal | exclusive files (abridged; full list SYNTHESIS §10) | deps | gate | kill switch | ≈LOC |
|---|---|---|---|---|---|---|
| **W0** | Certification probes on throwaway sessions: **P-P1 pointer lane on a real account store, mid-turn, with the expiry guard (decides §4.2)**; P-R1 retrofit from a home store; P-L1 copy-lane keychain form under a `security` stall shim (only if P-P1 fails); P-L4 re-home identity; P-S1 `session.measure` shape; P-L2 two lanes + a refresh. P-F1 (mid-turn bind from a hook) is **already passed by P11**. | new `tests/probes/lane/*`, new `lib/cc-upgrade-gate/check18_lanes.sh` (binary-parametric: anchors found by regex, so the ruled ≥2.1.301 upgrade re-certifies) | — | `python3 -I tests/probes/lane/run.py --all` | n/a (writes `~/.reso/lanes/cert/<ver>.json`) | 700 |
| **W1** | ps-free census in shadow | new `lr_recon/proctable.py`, `bin/cc-proctable`; `lr_recon/observe.py`, `store.py`, `fence.py` + tests | — | unittest (assert "Ran N"), shellcheck | `LR_RECON_PSFREE` | 900 |
| **W2** | three-key attribution API (home / billing(t) / identity) | new `scripts/lib/billing.py`, `lib/billing.sh`, `bin/cc-billing`, bats | — | `cc-bats` (assert `1..N`) | `CC_BILLING` | 650 |
| **W3** | lane broker, ledger, bind table, proof, GC, cert, CLI — inert. Pointer form drops the store/mirror/heal-guard modules (≈−1,000 LOC); copy form builds them per SYNTHESIS §3.3–§3.7 | new `scripts/limit-recover/lr_lane/*`, `bin/cc-lane`, staged launchd plist, staging migration | W0, W1, W2 | unittest; plist under `/bin/bash` 3.2 | `LR_LANE_MOVE` + broker unloaded | 1,400–2,400 |
| **W4** | launch-time arming + the binding module (`turn.step` per-request routing, `session.start` retrofit, beat, fail-safe, sensor) — inert | new `lib/cc-lane.sh`; `lib/claude-launcher.zsh`; new `mods/accounts-readout/hooks/lane-bind.ts`; `register.tsx` (registration only) + tests | W3 | `claude plugin validate/test`, `cc-bats` | `CC_LANE`, `bind.off` | 750 |
| **W5a** | `claude-accounts` + relogin: billing vs store census, lane-aware heal gate, R16 | `bin/claude-accounts`, `bin/cc-relogin`, `scripts/relogin-desharing-activate.sh`, `bin/cc-config-slot` + tests | W2, W3 | `cc-bats`, shellcheck | `CC_BILLING` | 1,000–1,250 |
| **W5b** | hooks, statusline and readouts by billing | `hooks/stop-failure-marker.sh`, `hooks/session-register.sh`, `statusline.sh`, `bin/cc-limited`, `bin/cc-context` and the other readers in SYNTHESIS §10 | W2 | `cc-bats`, shellcheck | `CC_BILLING` | 800 |
| **W5c** | limit-recover shell rows by billing; the `--restart-now` actuator | `lr-fleet.sh`, `lr-reset-poller.sh`, `lr-handoff.sh`, `lr-lib.sh`, `scripts/handoff-fire.sh`, `tests/lr-lib.bats` + tests | W1, W2, W4 | `cc-bats`, shellcheck | `LR_MOVE_RESTART_NOW` | 1,050 |
| **W6** | re-home at natural restarts (prove-death, background-daemon guard, cold transplant) | new `lr_lane/rehome.py`; `lr-fire-resume.sh`, `bin/reso-resume-one`, `scripts/boot-resume*.sh`, `bin/kitty-split-launch.sh`, `lr-transplant.sh` | W1, W3, W4 | unittest, `cc-bats` | `LR_REHOME` | 1,000 |
| **W7a** | move front door (`act=swap` for bound sessions) and new verdicts (lane state = target; one live transcript) | `bin/cc-lr`, `lr-move-worker.sh`, `lr-move-lib.sh`, `lr-move-batch.sh`, `lr-upgrade.sh` + tests | W1, W2, W3, W5c | `cc-bats` | `LR_LANE_MOVE` | 800 |
| **W7b** | reconciler: billing join, limit facts by billing, re-bill actuator (move + wake) | `lr_recon/{act,facts,census,plan,settle,__main__,types,evidence,report}.py`, new `billing_join.py` (decorates `SessionObs` after `observe()`; never edits `observe.py`, which W1 owns) + tests | W1, W2, W3 | unittest | `LR_LANE_MOVE` | 1,200 |
| **W8** | strand-aware rebalance with the lane actuator (burn meter, sink arm; donor arm separate) | `lr-shed.py`, new `lr_burn.py` + tests | W5a, W7a | `cc-bats` | `LR_REBAL_LANE` | 900 |
| **W9** | activation after the §13 decisions and a W0 PASS: load the broker, set defaults, runbook with the 2026-11-11 policy re-review | new `migrations/0080-lane-activate.sh`, `docs/runbooks/lane-move.md` | all | shellcheck, `bash -n` under `/bin/bash` 3.2 | everything in §10 | 150 |

Order: W0, W1, W2 in parallel → W3 → W4, W5a, W5b, W7b in parallel → W5c, W6 → W7a → W8 → W9. W1 and W2 are
policy-neutral (they improve today's restart-based mover too) and can land regardless of §13; W3 onward builds
the zero-restart path inert behind its switches. Total ≈12.4–13.4K LOC (estimate; the lower figure is the pointer form).

## 13. Operator decisions

Filed with `cc-decide` on 2026-10-25 (`cc-decide list --open` shows them). The synthesis listed nine questions (SYNTHESIS §11); the pointer
amendment makes two of them moot (refreshing accounts that only lanes bill to; copying MCP sign-ins), and the
policy and automatic-rebalance questions are one decision here.

1. **Switch a running session's paying account without restarting it?** — `69c31338d082` (class C, conviction 55%) — (a) build it,
   keep it off, ask Anthropic support in writing first and switch on after a yes or your explicit go; (b) on now
   for your orders and limit walls, automatic quota-spending rebalance only after a 2026-11-11 re-review;
   (c) never — restart-based moves only. Recommended: (a).
2. **How a lane holds the account, given your 2026-09-08 ruling that no token files are ever created** —
   `be5c5e83800f` (class C, conviction 70%) — (a) pointer lanes: no token copies anywhere, sessions use the target account's own stored
   login (needs W0 probe P-P1 on a real account store); (b) copy lanes: a private access-only copy per session in
   the keychain plus a 0600 file; (c) neither. Recommended: (a).
3. **Restart a session that never finishes a turn, to move it?** — `c7156c87c1b6` (class B, conviction 70%, default fires 2026-11-08) — default: wait for its
   first turn end or next natural restart; an explicit per-session `--restart-now` order restarts it at once, losing
   its in-flight turn and background jobs.
4. **Re-home moved sessions under their new account's folder** — `3e362e7d3be1` (class B, conviction 75%, default fires 2026-11-08) — default: automatically
   at every natural restart including a manual `--resume` (one-line notice), and also after 30 idle minutes.
5. The open packet `745e0fdc78e6` ("should all credential work wait for the next real weekly wall") was rechecked
   (conviction 80%):
   its premise — a sacrificial account and monthly logins — no longer holds, since lanes need neither and tonight's
   wall showed the relaunch path moving 1 of 9 busy sessions; recommendation: close it as superseded once W0
   passes. Related open packets `4ab193daae88`, `76a584cc935b` and `c9a05672e692` concern restart-based moves of
   idle or capped sessions and stand as they are.

## 14. Residual risks and accruing measurements

| risk | where it is read |
|---|---|
| the server's view of bearer ≠ metadata account | decision 1; any account-level 401/403 or account notice pages and triggers `cc-lane revert --all` |
| 2026-11-12 Usage Policy text | re-review dated 2026-11-11 in the W9 runbook |
| pointer lanes on real stores (≤30 s adoption, expiry guard) | W0 P-P1 → `~/.reso/lanes/cert/2.1.293.json` |
| mismatch window longer than the estimate | `cc-lane report --mismatch` (ledger `committed → rehomed`), weekly |
| sessions that never end a turn | `cc-lane status --fleet`: "unbound: no turn end since rollout" |
| `security` and `KERN_PROCARGS2` latency at load 600–900 | broker per-call durations; `recon/shadow/ps-free.jsonl` |
| a Claude Code upgrade moves an anchor | per-version certification (R14) |
| login cliffs next2 2026-10-31, next4 2026-11-02 | `cc-relogin` runbook; lane hygiene pages on a lane holding a refresh token |
| tertiary's stale `.credentials.json` (Oct 11) pins that dir's in-memory credential | operator housekeeping: rename it (it shares no live refresh token, G1) |

## 15. How this was produced

- **Research:** 14 read-only slots (2 workflows) over the extracted 2.1.293 source, the repo, disk telemetry, the
  web and repo history, then a completeness critic and 4 gap fills (G1–G4), then a second critic round with 4 more
  gap notes (3 committed), plus the inventory (I1) and the mod `env.set` study (I2). S02 stopped incomplete and fed
  no decision. One round-2 slot on the client's request attestation was flagged by a
  safety check; its output was not used and its note was not committed — the design forbids body rewriting on
  policy grounds and needs nothing from it.
- **Probes:** P1–P11, every one on a throwaway session started here (notes/P-probes.md); about $0.05 of model use.
- **Panel:** five architects (client-native lane; network router; restart perfected; lane + re-home hybrid;
  free-choice policy-minimal, which declined), four lens judges, totals A3 26 · A4 25 · A1 21.5 · A2 20.5 · A5 10
  (A3 won policy and build risk, A4 won robustness and operator outcome). Two skeptics per load-bearing claim of the
  top two: 11 claims (6 from A3, 5 from A4), none survived both skeptics unqualified; with the A1/A2 and brief claims,
  18 refutations are each dispositioned in SYNTHESIS §1.1. The synthesizer chose A4 over the
  totals because the frozen target excludes A3 by construction and six of A3's premises fell; a critic loop then
  patched the synthesis.
- **After the panel:** P9's result, P10's live census and P11 were measured, producing the pointer-lane amendment.

## 16. Sources

`notes/D-brief.md` (shared brief) · `notes/P-probes.md` (P1–P11) · `notes/SYNTHESIS.md` (full design) ·
architectures `notes/A1-client-native-lane.md`, `A2-network-router.md`, `A3-restart-perfected.md`,
`A4-identity-clean-hybrid.md` · research `notes/S01`–`S14`, `G1`–`G4`, `G2-bootstrap-resync-trigger.md`,
`G2-keychain-acl-write-feasibility.md`, `G2-org-identity-from-disk.md` · inventory `notes/I1-account-attribution-inventory.md`,
`notes/I2-plugin-env-set.md` · prior art `docs/research/account-rotation-100p-2026-10-24/REPORT.md`,
`docs/research/voluntary-inplace-switch-2026-09-22/`, `docs/research/claude-code-mods-2026-10-03/`.
