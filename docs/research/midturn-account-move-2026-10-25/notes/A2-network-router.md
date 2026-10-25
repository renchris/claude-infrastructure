# A2 — Network-router architecture for the mid-turn account move

Architect: A2-network-router. Date 2026-10-25. Philosophy: **network path first**. Read-only study;
the only file written is this one. Every claim is cited to a note by filename and (where load-bearing)
a byte offset into `/tmp/mtam/cc293-src.js`. Two offsets re-verified in this run: the per-session
header const `iTt="X-Claude-Code-Session-Id"` @4273752, and the OAuth capability beta
`Zu="oauth-2025-04-20"` @1671759. Measured load during this run: 706/646/606 (`uptime`).

`Replaces:` nothing. This design uses **no setup-tokens and creates no token files**, so operator
ruling `a90e1ac2597e` is honored, not pended.

---

## 0. One-paragraph mechanism

Every Claude Code session is launched through `lib/claude-launcher.zsh` with
`ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`, `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` and
`CLAUDE_CODE_ATTRIBUTION_HEADER=0`. A single supervised localhost daemon, **lr-router**, receives
every `/v1/messages` (and `/v1/messages/count_tokens`, `/v1/models`, `HEAD /api/hello`) request the
client makes (S03 (1), (3): only these reach `ANTHROPIC_BASE_URL`; all identity/usage/bridge endpoints
bypass it to the hard-coded `BASE_API_URL`). The router keys each request on its
`X-Claude-Code-Session-Id` header (`iTt` @4273752 — per-session, constant across a move, S03 (2)),
looks up a per-session route `{session_id → account, since_t}` in an on-disk map, replaces the
`Authorization: Bearer` header (`Xcs()` @5435037, the account selector, S03 (2)) with that account's
**live** OAuth access token read read-only from the account's keychain item, preserves
`anthropic-beta: oauth-2025-04-20` (stripping it 401s, S03 (2); S08 §2.7), optionally rewrites
`metadata.user_id.account_uuid` to match the bearer (KWe @8876959, G4), and forwards to
`https://api.anthropic.com`. A **move** is a one-line atomic rewrite of that session's route entry; the
client's **next** request — the next tool-loop step, no restart, no exit, no interrupt — carries the
new bearer and bills the new account (measured end-to-end in P3: next2→next3 mid-turn, one process,
linear transcript). On a usage-limit 429 or a 401 the router re-reads, retries, and fails over to
another account before any byte reaches the client (S03 (4)). The router never refreshes and never
writes a credential, so it cannot provoke the `invalid_grant` erase (S01 §4, S09 §1.5): each account's
refresh is owned, as today, by that config dir's own official client.

This meets the frozen DoD (D-brief §"Frozen DoD"): a busy session changes billing account with 0
transcript forks (the client process is never touched — P3 transcript linear, P8 is the hazard we
never create), 0 lost turns (no `/exit`, no SIGTERM — contrast M1/M2, S05 §3), 0 killed background
tasks (nothing is killed — contrast P7), and the change takes effect within 1 API call of the order.

**The one honest precondition:** a session must have been *launched* behind the router. Base-URL
routing is fixed at launch and cannot be added under a running process (S09 §6.4; S04 §4). The ~36
sessions live tonight were not, so adopting the router costs **one** incumbent-style restart per
existing session (a planned one-time migration, §4.0). After that, a session never restarts again for
any future move, recovery or rebalance. New sessions get the router for free.

---

## 1. Why the network path, against the alternatives

| Mechanism | Mid-turn move? | Token-write hazard | Moves side endpoints too? | Launch-time env? | Verdict |
|---|---|---|---|---|---|
| **M7 localhost router, bearer inject (this design)** | YES, measured (P3) | **none** (read-only on creds) | no (inference only) | yes (1 migration) | **chosen** |
| M6 per-session `CLAUDE_SECURESTORAGE_CONFIG_DIR` lane | YES, measured (P4/P6) | only if the copy is refreshable; a safe copy needs a non-refreshable token, which without setup-tokens has no source | yes (whole credential) | yes (1 migration) | strong rival (§13; a hybrid is the real recommendation, Decision D1) |
| M8 `ANTHROPIC_UNIX_SOCKET` | likely | same as M7 | no | yes | rejected primary: bare socket treats claude.ai OAuth as no-auth unless `CLAUDE_CODE_OAUTH_TOKEN` is set, and flips features to thirdParty (S03 (1), `rl()` @4625893) |
| M5 keychain rewrite | yes but whole-dir | refresh collision → logout | yes | no | rejected (S01 §4; G1 §5) |
| M9 HTTPS_PROXY + custom CA | in principle | — | — | — | rejected: MITM + CA trust + SSRF guard (S03 (5)) |
| M16 built-in gateway | no (provider flip) | — | n/a (API billing) | restart | rejected: one global upstream, no per-session, strips `anthropic-ratelimit-*`, enterprise/API billing (S11) |
| M13 setup-tokens | yes | none | no | yes | rejected by ruling `a90e1ac2597e`; and unnecessary — live read works (§3) |
| M1 incumbent restart | no (waits idle) | — | yes | n/a | kept only for the §4.0 migration |

The router's distinctive win is **token safety**: it is a pure reader and injector. S09 §1.5 names the
two proven-safe refresh patterns (own grants, or refresh-less setup-tokens) and the one hazard (sharing
a client's refresh token). The router takes a third, cleaner path that none of the surveyed tools took:
it holds **no refresh token at all** and reads the **access** token live from the keychain item the
official client already maintains (G1: four independent live grants, each kept fresh by its own
sessions). No POST to the token endpoint ever originates from the router, so the single-use rotation
race (S01 §4.1, S09 #103325/#554, cswap #381) is structurally impossible for it.

---

## 2. Components (files)

### New files

- `scripts/limit-recover/lr_router/__main__.py` — daemon entry. stdlib only (`asyncio`/`http`), the
  same shape as the measured probe `proxy.py` (P-probes harness), hardened. Run as
  `python3 -I -m lr_router`.
- `scripts/limit-recover/lr_router/server.py` — the loopback HTTP listener (SO_REUSEADDR), connection
  handling, upstream forward to `https://api.anthropic.com` over the system CA set (no pin on the
  first-party inference path, S03 (5)).
- `scripts/limit-recover/lr_router/routing.py` — loads/watches `route-map.json`; resolves
  `session_id → account` (default = the session's launch/home account when unmapped).
- `scripts/limit-recover/lr_router/bearers.py` — per-account access-token cache. Reads
  `Claude Code-credentials-<sha256(dir)[:8]>` **read-only** via `security find-generic-password -a
  $USER -w -s <svc>` (item names mapped in G1 §1; naming confirmed S14 §1 `FF()` @3737556). TTL ~25 s
  (< the client's 30 s PK cache `cPt`, S14 §2); hard re-read on upstream 401. Never `-U`, never writes.
- `scripts/limit-recover/lr_router/ratelimits.py` — parses `anthropic-ratelimit-unified-*` from every
  200 response (the router is on the inference path, so it sees them first-hand; the field list is
  S03 (4)) into a per-account utilization/reset/overage state. This is the **strand sensor**.
- `scripts/limit-recover/lr_router/failover.py` — 401 re-read+retry and usage-limit-429 failover
  ranking.
- `scripts/limit-recover/lr_router/bodyrewrite.py` — optional `metadata.user_id.account_uuid` rewrite
  (G4); skipped on `x-claude-code-request-class: auto_mode|side_query` to avoid the `cch`
  ignore-opt-out exception (S03 (2) note, @5433456).
- `scripts/limit-recover/lr_recon/proctable.py` — the ps-free census module (S07 §6), drop-in for
  `observe.read_ps`.

### Runtime state (not committed), under `${LR_STATE_DIR:-$HOME/.reso/limit-recover}/router/`

- `route-map.json` — `{ "<session_id>": {"account":"next4","since":<epoch_ms>,"by":"cc-lr-move","intent":"..."} }`, written atomically (tmp+rename).
- `access.jsonl` — one line per forwarded `/v1/messages`: `{t, session_id, account, upstream_org, unified_7d, unified_5h, status, failover_from?}`. This is the **disk-truth billing verdict** (R4/R9).
- `health` — heartbeat `{pid, started, last_ok_ms, port}` for the watchdog.
- `disabled` — presence ⇒ pass-through (kill switch).

### Changed files

- `lib/claude-launcher.zsh` — the env injection point named in D-brief ("`lib/claude-launcher.zsh` is
  the launcher every session goes through"). Inject the three vars when `CC_ROUTER != off` **and** the
  router `health` heartbeat is fresh; otherwise launch direct (fail-safe for new sessions). Shipped via
  `/ship`.
- `bin/cc-lr` — `cmd_move` (`:1599`) writes a route order instead of queueing `lr-move-worker`, for
  sessions already behind the router; it keeps the incumbent restart path only for not-yet-migrated
  sessions (detected from the census). `cmd_rotate` (`:1918`) and `recover` (`:634`) likewise become
  route updates (§5, §6).
- `scripts/limit-recover/lr_recon/observe.py` — `read_ps` → `proctable.read_table` (S07 §6).
- The reconciler's account-attribution (`facts.py`, S05 §1.1; the ~68 files keying on `config_dir`,
  S05 §5 R9) reads `route-map.json` + `access.jsonl` as the source of truth for routed sessions.
- A numbered permission migration ships a per-user LaunchAgent plist for supervision (operator installs
  it; agents never edit launchd/settings — D-brief, and this worker's rules).

---

## 3. Data flow (one request)

1. Client builds a Messages client per request (EN @8641537 runs on every model call — S01 (2), G3
   §2 row 1; subagents too, G3 row 2) and POSTs `/v1/messages` to `http://127.0.0.1:<port>` carrying
   its config-dir home bearer in `Authorization`, `anthropic-beta: oauth-2025-04-20,…`, and
   `X-Claude-Code-Session-Id`.
2. Router reads `X-Claude-Code-Session-Id` (`iTt` @4273752) → `routing.resolve()` → target account A.
3. `bearers.get(A)` returns A's live access token (cached read of A's keychain item). Router sets
   `Authorization: Bearer <A>`, leaves `anthropic-beta` and the body intact except the optional
   `account_uuid` rewrite (`bodyrewrite`, default off — Decision D2).
4. Forward to `https://api.anthropic.com`. On the response: read `anthropic-organization-id`
   (= the billed org, the probe's ground truth, P-probes header) and `anthropic-ratelimit-unified-*`
   → `ratelimits.update(A)`; append one `access.jsonl` line; stream the body back unmodified.
5. **401** (A's token rotated/revoked between reads — P9 open, but see Retry loop in D-brief): hard
   re-read A's keychain (bypass cache) and retry once; still 401 ⇒ mark A down, fail over (step 6) or
   surface. The client never sees the 401 (its own Khe retry @12388136 is a backstop, not the primary).
6. **Usage-limit 429** (status `rejected` with a `representative-claim`, S03 (4)): re-issue the same
   body on the next-ranked healthy account and return *that* account's 200 — invisible to the client
   (S03 (4)). A bare transient 429 (no claim headers) is paced on the same account, not failed over
   (mirrors TeamClaude's split, S09 §3.2).

Side endpoints (profile, usage, policy_limits, telemetry, bridge, memory, files) never traverse the
router (S03 (3)); they keep the config-dir home bearer. Consequence, stated honestly (S03 bottom line):
the router moves **inference billing only**. The in-client usage meter and `/usage` panel keep showing
the home account (keyed on `Mn().accountUuid`, S03 (4)); the router's own `ratelimits` state is the
authoritative per-account view, and it is complete because every inference call is seen.

---

## 4. The move protocol (order → billing change) with timings

### 4.0 One-time migration (precondition, paid once per existing session)

Existing sessions are launched without the router. Migrate each with the incumbent restart
(`cc-lr move` → `lr-handoff --in-place` → recycle, S05 §1) **to its own current account** but now
behind the router (launcher injects the env). This pays the incumbent's idle-wait cost once; after it,
the session is a router client forever. Order the migration by strand (drain the accounts with least
at-risk quota first) to minimize disruption. This is the only restart the design ever requires.

### 4.1 Steady-state move (the DoD path)

| t | step | source |
|---|---|---|
| t0 | Operator order: `cc-lr move --sids S… --to A`. | bin/cc-lr cmd_move |
| t0 | **Admission**: `lr_intent_check` + router read, fail-closed (S05 §1.2 step 5; R6/R11). A rejected session is not routed. | invariant R6 |
| t0 | Atomic write of `route-map.json` entry `{S:{account:A, since:t0}}`; signal/mtime-bump the router. | routing.py |
| t0+≤1 s | Router adopts the new map (inotify/kqueue, or 1 s poll). | routing.py |
| t1 | S's **next** `/v1/messages` (mid-turn: the next tool-loop step; S06 tool-exec p50 3 s, inter-turn gap p50 6.3 s). Router injects A's bearer. | P3 |
| t1 (resp) | `anthropic-organization-id` = A's org → **billed to A**; logged to `access.jsonl`. | P3, R4 |

"Within 1 API call of the order" is literal: the first request after t0+≤1 s bills to A. No `/exit`, no
SIGTERM, no resume, no new writer (contrast every incumbent casualty in S05 §3). The move is reversible
at any instant by rewriting the entry (R6) — there is no point of no return before the upstream
response.

Cost of the switch (P3/P5): one re-creation of the conversation-specific cache prefix on A (~6 K
tokens), because the ~10.9 K system/tool prefix is already warm on A across sessions of this CC version;
caching resumes on the next call. Same order as a resume (D-brief P3/P5 cache). Server-side message
threads are **off** behind the proxy (`Of()` false, S03 (1); S09 §5), so there is no `thread_not_found`
replay (that only bit P5's direct-to-api path) — the move is *cheaper* behind the router than direct.

---

## 5. Limit-recovery flow

Replaces the incumbent reconciler's detect→move→prove loop (median 81 min, S05 §3) with a
request-boundary failover measured in one round trip.

1. `ratelimits` watches each account's `-7d`/`-5h` utilization and `-status` from live response headers.
2. A session on account X whose request returns `status: rejected` (usage-limit 429, carrying a
   `representative-claim` of `five_hour`/`seven_day…`, S03 (4)): `failover` re-issues the same body on
   the healthiest account Y and returns Y's 200. The client's turn continues uninterrupted; it never
   sees the wall. Then `route-map` for X's sessions is updated so subsequent calls go straight to Y
   (no repeated per-call failover, which would thrash caches — S09 §3.2).
3. The incumbent's `hold:limited` "owes a turn" rule (S05 §2.1) is moot: nothing exits, so there is no
   capped turn that must be re-nudged. The turn simply completes on Y.
4. If **every** account is `rejected`, the router forwards X's 429 unchanged (fail-closed to the real
   wall) rather than hide a genuine global limit — absence/exhaustion is loud (R5).

Honest caveat (S03 (4)): after a failover the client's in-client usage meter (keyed on the home
`accountUuid`) is wrong/blank. The router's `access.jsonl` + `ratelimits` state is the true meter.

---

## 6. Strand-aware rebalance flow

Goal (D-brief): put work where weekly quota would otherwise expire unused; never launch filler
sessions (vetoed decision `8f9618059700`, R12).

1. **Sensor:** `ratelimits` holds, per account, `7d-utilization` and `7d-reset` (seconds to the weekly
   reset), seen first-hand on every inference response. "At-risk-of-expiring-unused" score ≈
   `(1 − utilization) / time_to_reset`: high when much quota remains and little time is left.
2. **Arm:** periodically (default 10 min) or on `cc-lr rotate`, rank accounts by that score and, for
   each movable session (admission fail-closed, intent re-checked — R6/R11), re-point its route entry
   to the account with the most at-risk quota, subject to not over-concentrating (cap concurrent
   sessions per account to avoid a burst 429).
3. **Actuation** is a pure `route-map.json` rewrite — zero client disruption, so the "idle never
   happens" constraint (D-brief §standing constraint; S06: 0 of 7 busy/goal sessions moved tonight) is
   irrelevant: a mid-turn session is rebalanced exactly as cheaply as an idle one. This is the whole
   reason the network path beats the incumbent, whose 149 busy/goal rows yielded 5 moves (3.4 %, S06
   §1b).
4. Rebalance never creates a session and never kills one (R12/R2).

---

## 7. The ps-free reconciler census (S07), folded in

The router's watchdog and the move/rebalance admission both need a census of live claude processes and
their session binding. Under load 650–770 `/bin/ps` times out at 42 s and went blind for 15 passes
(S07 §5). The router therefore uses `lr_recon/proctable.py`:

- One `sysctl(KERN_PROC_ALL)` supplies pid/ppid/zombie/lstart/tty for all rows incl. root-owned kitty
  `login` pane roots, 3.3 ms for 2167 rows at load 624 (S07 §0, §4), no task port, no same-uid check.
- Args for claude-family rows only via `KERN_PROCARGS2` on a bounded worker thread (9 ms for 93 procs,
  S07 §2–§4); fail-closed rule: a claude-family row whose args can't be read marks the census degraded
  and the actuator abstains, never defaults to the healthy shape (S07 §6).
- Mode `off|shadow|on` with kill switch `LR_RECON_PSFREE=off` or `touch …/recon/ps-free.off` (S07 §6).

For the router specifically the census answers: (a) is session S's client process still alive (so a
dead route can be reaped); (b) is S a single writer (no duplicate/bg-split, R1) — the router refuses to
hold a route for a session that the census shows as two live holders; (c) which account each
not-yet-migrated session is on (so migration order is known).

---

## 8. Invariants R1..R14 (carried from S05 §5, re-expressed for the router)

- **R1 one writer per session uuid; no fork.** The client process is never restarted or duplicated;
  the router adds no writer (contrast P8, the incumbent's split-brain). Proven from the census
  (single holder) and the transcript (one leaf).
- **R2 no in-flight work destroyed.** No `/exit`, SIGTERM, or kill touches turns, subagents, jobs,
  lands, teams or drafts (contrast S05 §3, P7).
- **R3 no silent truncation; continuity content-verified.** No transcript copy exists to go stale
  (contrast A03 M1). The bytes are never touched; continuity is trivially the same file.
- **R4 verdict from disk/process facts.** "Billed to A from t0" is read from `access.jsonl`
  (upstream `anthropic-organization-id` per request) + `ratelimits`, never prose.
- **R5 absence is loud.** Router `health` stale ⇒ watchdog respawns and pages; keychain unreadable for
  A ⇒ A marked down, abstain, logged — never a silent default to the home account for a request the
  operator ordered to A.
- **R6 every refusal before the point of no return.** Admission (intent+router, fail-closed) runs
  before the map write; the map write is reversible; the only irreversible act is the upstream
  response.
- **R7 one actuator per session.** The router is the single actuator for routed sessions; the move
  lane and reconciler defer to it (as `cmd_switch` already defers to the lane today, S05 §1.1).
- **R8 credential safety.** The router never writes or refreshes a credential; a grant stays in one
  item (G1); nothing provokes `invalid_grant`/`jhr` (S01 §4). Keychain items are read `-w` only, never
  `-U`.
- **R9 one time-aware attribution source of truth.** `route-map.json` ("S billed to A since t") is the
  single source consumed by router, reconciler facts, usage sweep and verdict — replacing `config_dir`
  keying for routed sessions.
- **R10 bounded external calls under load.** ps-free census (R7 above); bearer reads cached and
  bounded; no kitty control-socket dependency anywhere (the router types nothing).
- **R11 operator authority.** Intent re-checked at admission; router admits fail-closed; narrow kill
  switches (§10); the router never types into a pane (it is pure network), so "no turn typed into an
  unowned session" is structural.
- **R12 no filler sessions.** Rebalance only re-points existing sessions; it never launches one.
- **R13 teams never orphaned.** A lead and its in-process/pane teammates share `process.env` and thus
  the same router (G2 (b)); each teammate carries its own `X-Claude-Code-Session-Id`, so the router can
  route a lead and its members together (policy follows the lead) or hold them as a unit. No member is
  killed (contrast S05 §2.1 `hold:teammate`).
- **R14 fail closed on binary drift.** The `account_uuid` body rewrite is pinned to the known KWe body
  shape (G4 @8876959); on an unrecognized body the router forwards unrewritten (never guesses). The
  env-var contract (base URL honored, `cch` suppressible) is pinned to 2.1.293 (S03); a version change
  re-runs the probe suite before the launcher injects.

---

## 9. Failure-mode table (every observed mode → structural answer)

| Observed mode (source) | Incumbent cause | Router's structural answer |
|---|---|---|
| Lost turn: `/exit` kills the in-flight turn, no output persisted (S05 §3; handoff-fire :20757) | restart | no restart; the turn runs to completion on the new bearer (P3) |
| Fork / two live copies, 13 FAILED (S05 §3; P8) | second writer | router adds no writer; census refuses a route for a dual-holder (R1) |
| Stranded, 12 (S05 §3) | watcher died, no relaunch | nothing to relaunch; a route is a map entry, not a process |
| Husk / half-moved / stale tombstone (S05 §2.1) | transplant + exit | no transplant, no tombstone, no retire |
| Killed background job; model re-ran it (P7) | SIGTERM | nothing killed; `run_in_background` markers survive |
| Killed subagents, `killed_inflight` unaudited (S05 §3) | recycle | subagents are in-process, untouched; each runs its own EN → picks up the route on its next call (G3 row 2) |
| Goal driving a move, `hold:goal-live` (S05 §2.1; S06: 4 rows never driven) | restart kills the goal | goal keeps running in-process across the re-point; no hold needed |
| Drafts, pasted blocks lost (S05 §2.1) | `/exit` merges/destroys | composer untouched |
| Never-moved busy session: 56/56, 67/67 mid-turn snapshots (S06 §2) | waits for idle that never comes | re-point is independent of turn state; no idle wait |
| `became-limited`, owes a turn (S05 §2.1) | capped turn ends unanswered | failover completes the turn on another account; no cap seen by client (§5) |
| Prompt-cache rewrite after a warm move (S05 §2.1; R11 cache cost) | account-scoped cache | unavoidable for any account change; bounded to one ~6 K prefix rebuild (P3) — threads-off makes it cheaper than direct |
| Composer-unknown / modal / focus / kitty-wedged holds (S05 §2.2) | typing into the pane | router types nothing; no pane I/O at all |
| ps degraded, 15 blind passes (S07 §5) | `/bin/ps` under load | ps-free census, 3.3 ms (§7) |
| Refresh-token collision / `invalid_grant` logout (S01 §4; S09 §1.5) | two holders of one refresh token | router holds no refresh token; reads access token only (R8) |
| 429 usage wall surfaced to user (S03 (4)) | client surfaces a subscriber 429 | router fails over before the client sees it (§5) |
| In-flight request keeps old bearer across a swap (G3 §3) | per-request bearer capture | expected and correct: billing is per request; the *next* request moves. The DoD counts from the next call |
| account_uuid ≠ bearer account after swap (P6, G4) | stock client never re-keys | optional body rewrite (D2); P6 shows billing follows the bearer regardless |
| Router dies mid-request | — (new SPOF) | §11; client dead-hop retry (P1, measured 11–12 retries) bridges a fast supervised restart |

---

## 10. Kill switches (env / files)

- `CC_ROUTER=off` (launcher) — new sessions launch direct to api.anthropic.com on their home account.
  Needs a (new) launch; does not affect running sessions.
- `touch $LR_STATE_DIR/router/disabled` — router goes to **pass-through**: forwards every request with
  the client's own home bearer, no swap. Instant, no relaunch. This is the safe fail-open *while the
  router lives*.
- `LR_ROUTER_BEARER_SWAP=off` — same as pass-through, via env (daemon restart).
- `LR_ROUTER_UUID_REWRITE=off` (default off) / `=on` — the `metadata.user_id.account_uuid` rewrite.
- `LR_ROUTER_FAILOVER=off` — surface 429s to the client as today (no hidden account-hop).
- `LR_ROUTER_REBALANCE=off` — freeze the strand arm; manual `cc-lr move` only.
- `LR_RECON_PSFREE=off` or `touch …/recon/ps-free.off` — revert the census to `/bin/ps` (S07 §6).
- `LR_MOVE_LANE=off` — the incumbent lane remains independently killable (R11; S05 §5).

---

## 11. SPOF — what happens when the router dies (the hard problem, answered honestly)

**True fail-open is impossible.** Once a client is launched pointed at `http://127.0.0.1:<port>`, a
*dead* router means the socket is gone and the client cannot reach api.anthropic.com at all — there is
nothing to fail open *to*. The only "fail-open" is a **live** router in pass-through mode
(§10), which bills each session to its home account. So death must be handled by making death short and
rare, not by degrading gracefully to the upstream.

Mitigations, in order of load-bearing-ness:

1. **Client dead-hop retry bridges a fast restart (measured).** P1: when the local hop was briefly
   dead, the client retried the 502 **11–12 times** before giving up. A supervised restart that
   rebinds in well under a second (SO_REUSEADDR, persisted map reloaded in ms) is therefore invisible
   to in-flight turns. This is the primary safety net and it is measured, not assumed.
2. **Supervision.** A per-user LaunchAgent with `KeepAlive` respawns on crash; the reconciler watchdog
   reads `health` every census pass (ps-free, §7) and SIGKILLs a wedged router so KeepAlive respawns
   it. Installed by the operator as a numbered migration (agents never edit launchd).
3. **Stateless restart.** All durable state is `route-map.json` (atomic) and the append-only
   `access.jsonl`; a fresh process reloads the map and resumes. No in-memory-only routing is lost.
4. **Blast-radius bound (Decision D5).** A single router is a correlated failure the incumbent never
   had: its death hits all ~36 sessions at once. The design supports **sharding** — N routers on N
   ports, sessions partitioned by account or hash, the launcher picking a port — so one crash touches
   only its shard. Recommend starting single and sharding if any crash is observed to exceed the
   client retry budget.

Residual: a hang longer than the client's ~11–12-retry budget (seconds) across a shard loses those
sessions' in-flight turns simultaneously. This is the genuine structural cost of putting the move on a
shared network component and it cannot be fully eliminated — only bounded (sharding) and made rare
(supervision). It is the single strongest argument for the securestorage-lane rival (§13, D1), whose
failure domain is per-session.

---

## 12. Acceptance criteria as disk-truth reads

All read-only; re-derivable at any time (R4).

1. **Move took effect within 1 call.** `access.jsonl`: the first line for `session_id=S` with
   `t ≥ route-map.since` has `account=A` and `upstream_org=`A's org (P-probes org map). The gap from
   `since` to that line's `t` is the move latency; expect ≤ one inter-turn gap.
2. **0 forks.** The session's transcript jsonl has one leaf (`A$` max-timestamp leaf, S04 §3;
   `readEveryBranch` finds no second branch). Census shows exactly one live holder of S.
3. **0 lost turns.** The turn spanning `since` has every `tool_use` paired with a `tool_result` and
   reaches `assistant end_turn` (the same `lru_at_rest` test the lane uses, S06 §0). No
   `[Request interrupted…]`/`pL`/`PT` marker (S04 §1) appears around `since`.
4. **0 killed background tasks.** Any `run_in_background` marker files the session wrote exist and
   advanced across `since` (contrast P7's absent marker).
5. **Billing ground truth.** For a window, `access.jsonl` grouped by `account` reconciles with each
   account's `-7d-utilization` trajectory in `ratelimits` (both come from the same response headers).
6. **Credential safety.** Each account's keychain item `mdat` moved only at refresh times driven by its
   own sessions (G1 method), never by the router; `claude-accounts-lastgood-rejected.json` stays `{}`
   (G1 §2). No new keychain item exists for the router (contrast a lane dir, S14 §1).
7. **Census health.** `recon/shadow/ps-free.jsonl` shows 0 ppid/zombie/lstart/tty mismatches before
   `on` (S07 §6).

---

## 13. Rejected alternatives (with reasons)

- **M6 securestorage lane as the *primary* mover** — not rejected so much as deferred to Decision D1.
  Its advantages over the router are real: it moves **every** endpoint (profile/usage/limits, not just
  inference — S03 bottom line, G2 answer), its failure domain is per-session (no SPOF), and its policy
  exposure is Low-Moderate 60 % vs the router's Moderate-High 45–70 % (S08 §4). Its costs: it needs a
  launch-time env too (same migration), it *also* leaves `account_uuid` stale (G2 (c)), and a safe
  in-S credential needs a **non-refreshable** copy whose only no-setup-token source is "move the grant"
  (logs out the source, G1 §5(a)) or an unproven second grant (E1, G1 §5(b)). The router sidesteps all
  three by reading live. **The honest recommendation is a hybrid** (D1).
- **M8 `ANTHROPIC_UNIX_SOCKET`** — bare socket + claude.ai OAuth is treated as no-auth unless
  `CLAUDE_CODE_OAUTH_TOKEN` is set, and flips features to thirdParty (S03 (1)). HTTP loopback is the
  clean lever.
- **M9 HTTPS_PROXY + custom CA** — MITM, CA trust, and the SSRF guard on the proxy-agent path (S03
  (5)). The loopback base-URL path needs none of it.
- **M16 built-in gateway** — one global ordered upstream, identity unused for routing, config read once,
  strips `anthropic-ratelimit-*`, and bills API/enterprise not Max (S11 §6).
- **M13 setup-tokens** — ruling `a90e1ac2597e`; and unnecessary (live read works, §3). Keeping them out
  also keeps `/api/oauth/usage` and profile working for the home account (setup-tokens 403 there,
  S13 §7).
- **M5 keychain rewrite / M1 restart** — the incumbent family; M1 kept only for the §4.0 migration.

---

## 14. Residual risks

1. **Policy exposure is the highest of any mechanism (load-bearing).** S08 rates a token-swapping proxy
   Moderate-High: 45 % an unambiguous breach of text in force today, 70 % citable, and the 2026-11-12
   AUP adds "Resell, **proxy**, … route requests through consumer subscriptions" plus the legal page's
   "intermediate Claude.ai credentials" (S08 §2.2, §2.4, §4 M2). One tool-linked ban exists (TeamClaude
   #529, 54 min after adding an account, S09 §1). Mitigations are real but not dispositive: localhost
   only, serves only the owner's four own accounts, forwards native CC traffic, no third party, no
   credential intermediation *to others*. This risk is structural to the network path and is the main
   reason D1 leans toward a hybrid with the lower-exposure lane. **Do not ship without an explicit
   operator go on S08 (Decision D4).**
2. **Feature loss behind a non-first-party host.** Server-side message threads and Remote Control are
   `Of()`-gated and stay off behind the proxy even with the assume flag (S03 (1); P2; S09 §5). Threads-
   off is a *benefit* for moves (stateless, no replay) but a loss for any session that relied on them;
   Remote Control is a genuine loss for RC users. The assume flag restores the `pi()`-gated set (tool
   search, ~half the request bytes, `account_uuid` population) — measured in P2.
3. **`cch` attestation.** Must stay suppressed (`CLAUDE_CODE_ATTRIBUTION_HEADER=0`) so a body rewrite
   can't invalidate a hash (S03 (2)). The auto-mode-classifier ignore-opt-out exception (@5433456) can
   still emit `cch` on side/classifier calls; `bodyrewrite` skips those by request-class. If the body
   is never rewritten (D2 default off), this risk is nil.
4. **Token freshness for a drained account.** The router reads an account's access token live; that
   token stays fresh only while ≥1 official session on that config dir refreshes it (S01 §2, within
   5 min of expiry). An account drained to 0 live sessions will, within ≤8 h, have no fresh token and
   cannot be a billing target — and filler sessions are vetoed (R12). Mitigation: the strand arm keeps
   at least a token-keeper session per account; otherwise a fully-drained account is temporarily
   un-targetable until a session relaunches on it. (Does not strand *credentials* — purely a
   target-availability limit.)
5. **P9 unknown (revoke-on-refresh).** If an account's own refresh revokes its previous access token
   (S09 cswap #381; P9 accruing), every router-cached bearer for that account 401s once per refresh
   event (staggered, <8 h apart per account). Cost: one 401 + hard re-read + retry per event (D-brief
   "Retry loop", `Khe()` @12388136). The design does not depend on the answer.
6. **account_uuid rewrite is lose-lose.** Off ⇒ a server-visible bearer/uuid mismatch (P6; S08 §4
   aggravating). On ⇒ moves toward "misrepresent the client" (Nov 12 AUP, S08 §2.2). Kill-switched
   (D2); default off because P6 shows billing follows the bearer anyway.
7. **In-client usage meter wrong after any move/failover** (S03 (4)); the router's log is the true
   meter. A cosmetic but real divergence operators must know about.
8. **Migration cost.** §4.0 pays one incumbent restart per existing session — with all the incumbent's
   idle-wait pain (S06), once. Under "idle never happens" this migration is itself slow; schedule it
   per account during that account's natural lulls, or accept that migration uses the lossy M2 restart
   for the few sessions that never idle.

---

## 15. Operator decisions I cannot settle at >90% conviction

### D1 — Primary steady-state mover: network router vs securestorage lane vs hybrid
- **Conviction:** 58 % that a **hybrid** (lane for the account *move*, router for *limit-failover* and
  *strand sensing*) beats router-only.
- **Options:** (a) router-only; (b) lane-only; (c) hybrid: lane owns per-session account identity +
  move (moves all endpoints, per-session failure domain, lower policy exposure), router owns the live
  utilization sensor and transparent 429 failover (the lane cannot fail over a request mid-flight).
- **Recommendation:** (c) hybrid. The lane's per-session failure domain and all-endpoint move (G2, S14
  §7) answer the router's two worst problems (SPOF §11, inference-only §3); the router's header-level
  sensor and failover (S03 (4)) answer the lane's two worst problems (no mid-flight recovery, stale
  usage). If forced to one, the lane — lower policy exposure (S08 §4) and no SPOF.

### D2 — Rewrite `metadata.user_id.account_uuid` to match the injected bearer?
- **Conviction:** 62 % that **off** is correct.
- **Options:** off (accept the mismatch); on (hide it).
- **Recommendation:** off. P6 shows billing follows the bearer with the mismatch present; rewriting
  adds the "misrepresent client" reading (S08 §2.2) and the `cch` entanglement (S03 (2)). Keep it
  kill-switchable and revisit only if bans correlate with the mismatch (S09 §8 open).

### D3 — `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` on?
- **Conviction:** 72 % on.
- **Options:** on (restore tool search, halve request bytes, populate `account_uuid`, P2) + attribution
  header off; off (simplest, no `cch` ever, but ~2× request bytes and no tool search, P2).
- **Recommendation:** on, with `CLAUDE_CODE_ATTRIBUTION_HEADER=0`. The request-size and tool-search win
  (P2: 89 KB→49 KB, 31.8 K→16.9 K input tokens) is large and recurs on every request.

### D4 — Run the migration at all, given policy exposure?
- **Conviction:** 50 % — this is a risk-appetite/legal call, not a technical one.
- **Options:** ship behind an explicit operator go after they read S08; ship the lower-exposure lane
  instead (D1); don't ship, keep the incumbent.
- **Recommendation:** do not ship the router arm without an explicit operator acknowledgement of S08 §4
  M2 (45–70 %) and the one tool-linked ban (S09 §1). If the operator wants the lowest exposure, take
  the lane (D1) and use the router only as a read-only sensor that injects no bearer (pure pass-through
  utilization logging — Low exposure, since it only reads headers).

### D5 — Single router vs sharded
- **Conviction:** 66 % single first, shard on evidence.
- **Options:** one router (simplest, correlated failure for all ~36 sessions); N sharded routers
  (bounded blast radius, more moving parts and a shard-assignment map).
- **Recommendation:** single router with supervision + persisted map (§11); instrument restart
  duration vs the measured client retry budget (P1); shard by account if any restart is observed to
  exceed it.

### D6 — Token-keeper policy for a drained account (vs the filler-session veto)
- **Conviction:** 70 % that "keep the last session on an account routed to that account" is acceptable.
- **Options:** (a) the strand arm always leaves ≥1 session billing to each account so its token stays
  fresh; (b) accept that a fully-drained account is un-targetable until a session relaunches there;
  (c) a dedicated keeper (rejected — borders the filler veto R12).
- **Recommendation:** (a) as a routing constraint (not a new session — so R12 holds), falling back to
  (b) when an account has no sessions at all.
