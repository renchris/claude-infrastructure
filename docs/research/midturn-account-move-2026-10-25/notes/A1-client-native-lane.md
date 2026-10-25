# A1 — Client-native lane: a per-session `CLAUDE_SECURESTORAGE_CONFIG_DIR` credential lane with a broker-owned routing table

Architect slot: A1-client-native-lane. Date 2026-10-25. Philosophy: **client-native first** (mechanism M6,
D-brief:105). No proxy sits in the request path. Every session reads its billing bearer from a session-private
credential lane that a broker rewrites; the unmodified Claude Code client adopts the rewrite at its next API
request through its own `wA()`→`Pl()` change-check. Byte offsets are into `/tmp/mtam/cc293-src.js`
(52,710,919 B, CC 2.1.293), re-confirmed by me where noted (`A1probe*.py` in `/tmp/mtam/`).

This document cites: D-brief, P-probes (P1–P9), S01, S05, S06, S07, S08, S09, S10, S12, S13, S14, G1, G2, G3, G4.
There is no I1/I2 note in the directory; the `env.set` question the brief tags "I2" is answered from S09 §5 and
my own read of `EIo` @11552107 (below).

---

## 0. One-paragraph mechanism

Each session is launched once through `lib/claude-launcher.zsh` with two env vars: its normal
`CLAUDE_CONFIG_DIR` (unchanged — transcript, `projects/`, `.claude.json` stay where the fleet expects them) and a
**session-private `CLAUDE_SECURESTORAGE_CONFIG_DIR` = `~/.reso/lane-broker/lanes/<sid>`** (the "lane"). `uw()`
@3737607 and `FF()` read that var on *every* credential call (G2 (a); confirmed `A1probe3.py`), so the lane owns
the keychain item name `Claude Code-credentials-<sha256(lane)[:8]>`, the `.credentials.json` fallback, the
`.storage-write.lock`, the refresh lock and every `mcp-refresh-*.lock` (S14 §1, G2 (a)). A **lane broker** daemon
owns a disk routing table `sid → billing_account` and keeps each live lane holding a **fresh, inference-only copy**
(`refreshToken:null`) of its billing account's current access token. A **move** is: take the lane's
`.storage-write.lock`, rewrite `claudeAiOauth` in the lane store to the target account's inference-only copy
(preserving `mcpOAuth` and every other blob key), bump the lane `.credentials.json` mtime. The next client build in
that process — the next tool-loop step, every subagent request, every side query (G3 §2) — runs
`j7()`→`Pl()`→`wA()`, sees the mtime change, calls `ox()` (clears the memo *and* zeroes the 30 s keychain cache,
S14 §5), re-reads the lane, and sends the target account's bearer. Measured end-to-end as **P4** (store swap,
no proxy, next request ≈4.5 s later carried the new org) and **P5/P6** (direct to api.anthropic.com and in the
real TUI). The process never exits; no transcript is copied; there is never a second writer.

---

## 1. Why client-native, not a proxy (the governing trade)

The proven mid-turn mechanisms are M6 (this lane) and M7 (a bearer-swapping `ANTHROPIC_BASE_URL` proxy)
(D-brief:105-106; P3 vs P4). They differ on one axis that decides everything downstream:

- **A non-`api.anthropic.com` base URL degrades the session and the degradation is latched at launch.** P2
  measured: without `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` the client drops tool search (24 inline tools,
  ~2× request bytes) and blanks `account_uuid`; *with* the override it restores `pi()`-gated paths but **not**
  `Of()`-gated ones — server-side message threads and Remote Control stay off behind any proxy (P2; S03; S09 §5,
  `Of()` @2000767, tether gate `ab()` @12362076 memoized). All non-inference endpoints (profile, usage, policy
  limits, bridge) bypass `ANTHROPIC_BASE_URL` anyway (hard-coded `BASE_API_URL`, S03; P-probes P2).
- **The lane keeps the client first-party.** Threads, Remote Control, tool search, large-context and every
  billing/usage header stay on. The cost is paid once per cross-org move as a `404 thread_not_found` replay
  (P5: one ≈225 ms round trip + one prefix re-create) — the client's own thread layer (`Hhe()` classifies 404
  `thread_not_found` @12372944, S09 §5) handles it and the transcript stays linear.

So the lane buys first-party fidelity. **The price it pays is weaker on-the-wire attribution** (there is no proxy
to read the response `anthropic-organization-id`); §10 answers that with disk-truth fingerprints plus the
utilization feed. That trade is the whole identity of this design versus the proxy design.

---

## 2. Components (files)

### 2.1 New files

| Path | Role |
|---|---|
| `scripts/lane-broker/lane-broker.py` | The broker daemon. Owns the routing table, follows each account's access token, performs lane rewrites (moves), serves limit-recovery and strand-aware rebalance. One process, launchd-less (on-demand like the CC daemon, S12 §1), re-entrant-safe. |
| `scripts/lane-broker/routes.json` → in `~/.reso/lane-broker/` | **Routing table, the attribution source of truth (R9).** `{sid: {billing_account, lane_dir, since_ts, epoch, reason}}`. Atomic write (tmp+rename). Append-only move journal beside it: `moves.jsonl`. |
| `~/.reso/lane-broker/lanes/<sid>/` | The lane dir itself (one per session), **outside the repo symlink farm**. Holds `.credentials.json` (0600), the keychain item is `Claude Code-credentials-<sha256(this path)[:8]>`, plus the CC-owned locks. |
| `scripts/lane-broker/lane-seed.py` | Idempotent: build/refresh a lane's inference-only blob from an account's live keychain item; preserve `mcpOAuth`. Sole writer of `claudeAiOauth` in a lane. |
| `scripts/lane-broker/token-follow.py` | Subscribes to each account's real keychain item mdat (and the existing `claude-accounts` fingerprint feed, G1 §0); re-copies the fresh access token into every lane routed to that account. |
| `scripts/limit-recover/lr_recon/proctable.py` | The ps-free census module (S07 §6), folded in; adds a routes.json join. |
| `hooks/lane-register.sh` | SessionStart hook: registers `sid → lane_dir` with the broker and triggers the first seed. Async, short timeout (S10 Part A). |
| `hooks/lane-identity-resync.sh` | *Optional* (operator decision D1): a no-op `/model` re-pin trigger to force a bootstrap restamp of `account_uuid` after a move. |

### 2.2 Changed files

| Path | Change |
|---|---|
| `lib/claude-launcher.zsh` | The fleet's single launch injection point (D-brief:94). Allocate the lane dir, export `CLAUDE_SECURESTORAGE_CONFIG_DIR=<lane>` (and the identity-arm `CLAUDE_CONFIG_DIR` if D1 chooses per-session dirs), seed the lane before exec, register with the broker. Kill-switch aware (§9). |
| `bin/cc-lr` | `move`/`rotate`/`recover` front doors call the broker instead of `lr-move-worker.sh` for **laned** sessions; laneless sessions fall through to the incumbent (§8 rollout). `--status` reads routes.json. |
| `scripts/limit-recover/lr_recon/observe.py` | `read_ps` → `proctable.read_table` when `LR_RECON_PSFREE=on`; attribution now from routes.json, not config_dir (R9). |
| `bin/claude-accounts` | Designated the **single native refresher** per account (it already polls/refreshes every ~20 s, G1 §0); publishes an access-token-changed signal the follower consumes. No behavioural change to its refresh logic. |
| `~/.claude/settings.json` (via numbered migration, never agent-edited, D-brief:91) | Register `lane-register.sh` on SessionStart; optionally `lane-identity-resync.sh`. |

---

## 3. Data flow

```
                claude-accounts (--local-refresh, ~20s)      <-- the ONE refresher per account
                   | rotates each account's real keychain item (holds the refresh token)
                   v
   account keychain items  Claude Code-credentials-<sha8(account dir)>   (next/next2/next3/next4; G1 §1)
                   |  mdat change / fingerprint feed
                   v
   token-follow.py  --re-copies-->  inference-only blob (refreshToken:null)
                   |
                   v  (under <lane>/.storage-write.lock)
   lane store   ~/.reso/lane-broker/lanes/<sid>/  { keychain item + .credentials.json }
                   |  read on every API request by:
                   v
   CC process (one per session)  --  j7()->Pl()->wA() @4668113/4668663/4658281 each EN() build (G3 §2)
     main loop (Son->Khe(EN) @12502370) | subagents (runQuery=L0, same path) | side queries (nG->EN)
                   |  first-party, direct to api.anthropic.com
                   v
   api.anthropic.com  -- bills the org behind the bearer the lane currently holds
                   |  response headers anthropic-organization-id, anthropic-ratelimit-unified-7d-*
                   v  (NOT seen by the broker; see §10 attribution)
   transcript .jsonl under CLAUDE_CONFIG_DIR (unchanged, one writer)

   lane-broker.py  owns routes.json  <--  cc-lr move/rotate/recover, strand rebalancer, limit watcher
                   ^
                   |  census join
   proctable.py (sysctl KERN_PROC_ALL)  -> pid/sid/lane -> routes.json -> billing account
```

Key coverage fact (G3 §2, re-traced there): **every inference path** rebuilds the client through `EN()` per
request and therefore runs the change-check first — main loop, in-process subagents (`runQuery=L0`→`Sl().callModel`
→`Son`→`Khe(EN)`), the auto-mode classifier (`nG`→`EN`), compaction, hooks, quota/count_tokens. The lane memo
`mn()`/`bA.value` is one slot per host (`Hye.of(F().host)`, S01 §1), so the *first* path to run `wA()` after a
swap updates the bearer for **all** in-process agents at once. The only inference-adjacent exception is the
`cache_touch` keepalive, whose client is cached ≤240 s (`jLn=240000` @9777402, G3 §2 row 4b) — see §11 F14.

---

## 4. The lane store: file-only vs keychain-primary, and why keychain-primary

On macOS the composite store is `zn() = M(b,T)` (keychain `b` first, plaintext `T` fallback; 3751307, S14 §2).
Two ways to own a lane:

- **File-only lane** (what P4/P5/P6 used): no keychain item; the client reads `.credentials.json`; a swap is an
  atomic file rewrite. Measured immediate (P4 ≈4.5 s). **Fatal flaw for production:** the first time the client
  itself does a `zn().mutate` on a *file-only* store — e.g. saving/refreshing an **OAuth MCP token** — `M.update`
  writes the keychain and then, because the keychain had no prior item, **deletes the file**
  (`if(i===null)await r.delete(o)` @3743013, confirmed `A1probe3.py`; S14 §6b). After that, keychain wins and every
  later file swap is silently ignored. G1 saw a live `mcpOAuth` (`motion-plus`) in the tertiary store, so this is
  not hypothetical.

- **Keychain-primary lane (chosen).** The broker **pre-creates** the lane keychain item and keeps a synced
  `.credentials.json` beside it:
  - A client `zn().mutate` (MCP token refresh) now finds a prior item (`i!==null`), so it **updates** the keychain
    and **keeps** the file. mcpOAuth therefore lives naturally in the lane keychain item, written by the client,
    and the broker preserves it (read-modify-write only `claudeAiOauth`).
  - A swap writes the keychain item via `security add-generic-password -U` (S14 §2, same shape CC uses) **and**
    atomically rewrites the file. The file content is ignored while the keychain item exists (keychain-first), but
    `wA()` stats the file for mtime (S14 §5); bumping it forces `ox()`→`p0()` which zeroes the 30 s keychain cache,
    so the new keychain blob is adopted on the **next** request, not after a 30 s wait. The file doubles as the
    safe fallback if the keychain is ever locked.

This directly solves the brief's **mcpOAuth-in-the-lane** requirement: the client keeps and refreshes `mcpOAuth`
in the lane item; the broker never clobbers it (RMW under the lock preserves all non-`claudeAiOauth` keys, S14 §2:
"the blob is shared by many features").

**Lane hygiene (brief: 0600, O_NOFOLLOW refuses symlinks).** Correction to G2 (a), load-bearing: the
`refused-symlink`/`O_NOFOLLOW` path G2 cites lives in the **v5 file store** (5230540/5230757, `A1probe.py`), which
is **inert** in 2.1.293 (`Pmr()` returns undefined, S14 §3). The **live** plaintext backend read is
`se().readFileSync(r,{encoding:"utf8"})` with **no `O_NOFOLLOW`** (3750135, `A1probe2.py`) — it *follows* symlinks.
So the client will not refuse a symlinked lane file. Lane hygiene must therefore be **broker-enforced**, not
relied upon from the client:
  1. `lane-seed.py`/`lane-broker.py` open the lane file `O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW`, mode `0600`, and
     `lstat` the path (refuse if it is a symlink or not owned by `$USER`).
  2. The lane dir is created `0700`, owned by `$USER`, under `~/.reso/lane-broker/lanes/` (not the symlink farm;
     D-brief:93 notes `~/.claude` is a symlink farm — the lane deliberately is not).
  3. A swap writes to a temp file in the lane dir (same device) and `rename()`s it over the target, so the live
     file is never a partial write and the mtime always advances.

---

## 5. The move protocol, step by step (order → billing change) with timings

Pre-state: session `S` is live on account A; its lane `L=~/.reso/lane-broker/lanes/<sid>` holds A's inference-only
blob; routes.json says `S→A`. The broker is told "move S to B" (by the limit watcher, the rebalancer, or `cc-lr`).

| # | Step | Where | Timing (measured / estimated) |
|---|---|---|---|
| 1 | **Admit + journal.** Re-read routes.json, confirm `S→A`, confirm B is not limited and B's current access token is fresh (follower state). Append `moves.jsonl` `{sid, A→B, ts, epoch+1, reason}` **before** any write (R6 write-ahead). | broker | est <5 ms |
| 2 | **Build B's inference-only copy.** From B's live keychain item (read once, `-w`, never logged): `{claudeAiOauth:{accessToken:B.at, refreshToken:null, expiresAt:null, scopes:[…user:inference…], subscriptionType, rateLimitTier}}`. `expiresAt:null` → `JP()` treats it as never-expiring so `Pl` returns `not_needed` before any refresh (S14 §7). | lane-seed | est <20 ms (one `security` read) |
| 3 | **Take `L/.storage-write.lock`** (proper-lockfile shape: mkdir-atomic `.lock` dir, `realpath:!1`, retries 10×100–1000 ms, stale 15 s — same as CC, S14 §2). This serialises against a concurrent client `mutate` (mcpOAuth save). | broker | est 0–100 ms (lock contention rare) |
| 4 | **RMW.** Read the lane blob strict; replace **only** `claudeAiOauth` with step 2; keep `mcpOAuth` and all other keys. Write the keychain item (`security add-generic-password -U -a $USER -s <lane svc> -X <hex>`; argv fallback over 4,032 B, S14 §2). | broker | est <30 ms |
| 5 | **Atomic file rewrite.** Write the same blob to `L/.credentials.json.tmp` (O_NOFOLLOW,0600) and `rename()` over `.credentials.json` → mtime advances. | broker | est <5 ms |
| 6 | **Update routes.json** (`S→B`, epoch+1) atomically; release the lock. | broker | est <5 ms |
| 7 | **Adoption (the billing change).** The next `EN()` build in S — next tool-loop step, next subagent request, next side query — runs `wA()`; mtime changed → `ox()` (clears `bA` memo, `p0()` zeroes keychain cache, `sp()` emits) → re-read → keychain returns B's blob → `mn()` bakes B's bearer into the client → request sent on B. | CC process | **P4: ≈4.5 s** after the rewrite (bounded only by the gap to the next request; p50 inter-step gap 6.3 s, S06 §3). Within the DoD's "1 API call". |
| 8 | **First request on B (cross-org cost).** First-party threads are on, so the opening request carries `thread:{continue}` for a thread that lives on A's org → `404 thread_not_found` → client replays the turn as `create` on B. | server + CC | **P5: one ≈225 ms 404** + one conversation-prefix re-create (~6.1 K tokens, P3/P5). Transcript stays linear. |
| 9 | **Verdict** (§10): fingerprint(lane `claudeAiOauth.accessToken`) == fingerprint(B's live access token) AND S emitted a request after `since_ts` AND B's 7d-utilization moved. | broker + census | seconds–minutes (utilization lag) |

Total wall from order to billed-on-B: **≈5 s** (steps 1–7), i.e. within one API call of the order. Steps 1–6 are
all **before** the point of no return in the sense that routes.json is updated last; but note the real
irreversibility is cheap here — re-pointing back to A is another 5-step rewrite, no husk, no fork (contrast S05
§1.5 custody phases).

**In-flight request:** a request already streaming when step 5 lands finishes on A's bearer (headers captured once
per client, no per-chunk re-read, no abort; G3 §3). Billing is A up to and including that request, B from the next
client build. That is the single unavoidable "1 API call" boundary in the DoD and it is *inside* the budget.

---

## 6. Limit-recovery flow

Trigger: a response on S returns `429 rate_limit`, or the captured `anthropic-ratelimit-unified-*` headers show A
at the wall. The reconciler acts only on a genuine `rate_limit` tail (R, S05 §1.1).

1. The broker picks a target B with headroom (routes among the 4 accounts by current 7d/5h utilization).
2. Run the §5 move protocol S→B. Because adoption is at the **next request**, and after a 429 the client's own
   retry generator `Khe` (@12387081) rebuilds the client on the auth/ratelimit-class error (`A1probe3.py` gate
   @12388136) and retries a bounded number of times, the retry **adopts B's bearer** without any new turn. The cap
   is recovered **within one API call** of the move.
3. **"Owes a turn" (R, S05 §2.1 `hold:limited`).** A capped turn *ends* (the model stops), so a pure billing move
   lands S at rest on B, unanswered. This is a turn-continuity concern, not a billing one, and it is **orthogonal
   to this design**: reuse the incumbent nudge (a Stop-hook/`/goal` re-drive, or a one-line typed nudge through the
   existing actuator) to start the next turn on B. The DoD ("billing change in ≤1 API call, 0 lost turns") is met
   by the move; the nudge restores forward progress exactly as it does today.

No `/exit`, no resume, no husk: all 27 restart-intrinsic gates (S05 §2) are simply absent.

---

## 7. Strand-aware rebalance flow

Goal (D-brief:8-9): put work where weekly quota would otherwise expire unused.

1. **Signal.** Per account, the broker reads `anthropic-ratelimit-unified-7d-utilization` and the reset time. Two
   sources, no proxy needed: (a) the `claude-accounts --readout` feed (P-probes: next2 0.02, next3 0.17 corroborated
   live); (b) utilization headers are present on **every** inference response even with an inference-only token
   (S13 (a)). The broker computes, per account, **expiring-unused = (1 − utilization) × weekly_budget** weighted by
   `1/time_to_reset` — the account that will strand the most quota soonest is the magnet.
2. **Selection.** Rank live laned sessions by movability (all laned sessions are movable mid-turn — that is the
   point) and by strand benefit. Never launch filler sessions to burn quota (R12; vetoed 8f9618059700, D-brief:89).
3. **Execute.** For each selected session, run the §5 move protocol toward the magnet account. Each move is an
   independent atomic lane rewrite; there is no batch `/exit` storm, no slot semaphore of width 4 (S05 §1.4 W3), no
   two-snapshot idle wait (S06 §1a). The rebalancer paces itself only to respect the prompt-cache cost (one prefix
   re-create per move, P3) and to avoid moving a session twice within one turn.
4. **Hysteresis.** A session is not moved back within `REBALANCE_MIN_DWELL_S` (est 300 s) to avoid cache thrash
   (the better-ccflare `session`-strategy thrash, S09 §3.1 #240).

Because "idle never happens" (D-brief:16-22; S06: 0 of 7 busy/goal sessions moved tonight; 56/56 `mid-turn`
snapshots), the rebalancer's value is precisely that it does **not** wait for idle — it rewrites a lane under a
running turn.

---

## 8. Rollout for sessions launched before the lane env existed

The lane binds at launch; env cannot be changed in a running process (G2 (b); S05 §4.4; S13 §8: a local env-token
session "cannot be re-pointed mid-flight from outside"). So:

- **New launches** (every session through `lib/claude-launcher.zsh` after the migration) are laned from birth. The
  laneless population drains as sessions naturally end/relaunch.
- **Laneless live sessions are detected, not coerced.** The census (§12) marks a session laneless when its args/env
  carry no `CLAUDE_SECURESTORAGE_CONFIG_DIR` (KERN_PROCARGS2 env block, S07 §6 — the lane *path* is not a secret, so
  it may be read; argv/env are never logged) or it is absent from routes.json. A laneless session **cannot** be
  moved mid-turn by this design; it keeps the incumbent restart move (`cc-lr move` → M1) or, at a genuine cap, the
  keychain-swap-of-its-own-dir fallback (M5, whole-dir, with the §11 refresh hazards). No session is restarted
  *merely* to acquire a lane — that would cost a turn and violate the DoD.
- **Opportunistic re-lane.** When a laneless session reaches a turn boundary for some *other* reason (a natural
  resume, an operator relaunch, a crash revival S12 §4), the launcher wraps the relaunch in a lane. Over a day of
  ~36 sessions this converges without any forced loss.
- A session that was launched with a lane but whose lane dir is missing (operator wiped `~/.reso`) fails **loud**
  (R5): the broker refuses to claim it and the census marks `lane-missing`, never silently treating it as account A.

---

## 9. Kill switches (env) and operator authority

Every new mechanism ships a narrow-first switch (D-brief:91; R11):

| Switch | Effect | Needs restart? |
|---|---|---|
| `LANE_BROKER=off` | Launcher stops injecting `CLAUDE_SECURESTORAGE_CONFIG_DIR`; new sessions are classic single-account. Broker exits. | new sessions only |
| `LANE_BROKER_MOVE=off` | Broker runs (token-follow keeps lanes fresh) but refuses all moves; sessions stay on their launch account. | no |
| `LANE_BROKER_REBALANCE=off` | Strand rebalancer off; limit-recovery still moves. | no |
| `touch ~/.reso/lane-broker/freeze` | Hard freeze: no lane writes at all (follower and mover both idle); lanes hold their last blob. | no |
| `LANE_IDENTITY_RESYNC=off` | Disable the optional D1 bootstrap-restamp arm. | no |
| `LR_RECON_PSFREE=off` / `touch …/recon/ps-free.off` | Census falls back to `/bin/ps` (S07 §6). | daemon restart / no |

Intent is re-checked before each move (R11, S05 §1.4 intent gate); the router admits fail-closed; no turn is ever
typed into an unowned session. The broker reads `.claude/rules/*.md` traps at startup where relevant.

---

## 10. Attribution and acceptance criteria as disk-truth reads

The incumbent's verdict keyed on `P2: process env CLAUDE_CONFIG_DIR == target` and `P3: transcript under the target
store` (S05 §1.7). **A no-restart lane move fails both by construction** — the config dir and transcript never move.
So attribution is redefined (R4, R9): **"session S is billed to account B from time t"** is read from disk as:

1. **routes.json** `S→B` with `since_ts=t`, epoch monotone. (The single source of truth; R9.)
2. **Lane fingerprint match** (no secret printed): `sha256(lane S .credentials.json .claudeAiOauth.accessToken)[:16]`
   `==` `sha256(B's live access token)[:16]` — the same fingerprint scheme `claude-accounts` already persists
   (G1 §0). Proves S *will send* B's bearer next.
3. **Liveness of adoption**: the session emitted ≥1 request after `t` (its transcript `.jsonl` grew / a new usage
   record appeared after `t`). Proves the swap was *reached* by a client build.
4. **Utilization corroboration**: B's `anthropic-ratelimit-unified-7d` moved after `t` (from the response-header
   capture or `claude-accounts --readout`). This is the only *server-derived* confirmation and it lags; it is a
   cross-check, not a gate.

**Residual, stated plainly (R5 "absence is loud"):** without a proxy there is no per-request `anthropic-
organization-id` on disk, so true server-side billing attribution is corroborated (utilization) not proven per
request. An **observer-only** localhost proxy would give it but would turn off threads + Remote Control (P2/S03) —
rejected (§13). A session whose fingerprint does **not** match any account, or whose lane is missing, is marked
`attribution-unknown` and abstained on, never defaulted to a guess.

Acceptance criteria (all disk reads, re-derivable any time — R4):
- `routes.json[S].billing_account == B` and `epoch` increased.
- lane fingerprint == B's fingerprint.
- lane `.credentials.json` is a regular file, `0600`, owned by `$USER`, not a symlink (lstat).
- lane keychain item exists with suffix `sha256(lane)[:8]`; no account-dir keychain item was written.
- `moves.jsonl` has the matching `A→B` record with a timestamp before the routes.json mtime.
- census join (pid→sid→routes.json) agrees with routes.json for every live laned session.

---

## 11. Invariants carried from the incumbent (R1..R14, mapped from S05 §5)

- **R1 One writer per sid; no fork.** The process never exits and no transcript is copied; P8's two-writer hazard
  cannot arise (no second `--resume`). Enforced structurally, not by a split-brain lock.
- **R2 No in-flight work destroyed.** Turns, subagents, bg jobs, lands, team members, drafts all live across a lane
  rewrite (S10 Part B: every item a restart kills is kept). Subagents re-read the lane on their own next request
  (G3 §2).
- **R3 No silent truncation; continuity verified.** No copy to truncate. Continuity is trivially the same bytes
  (same transcript file); the §10 liveness read proves the turn continued.
- **R4 Verdict from disk/process facts, re-derivable.** §10. Re-defined off the dead P2/P3.
- **R5 Absence is loud.** `lane-missing`, `attribution-unknown`, follower-stale all abstain and page; never a silent
  default to the launch account.
- **R6 Every refusal before the point of no return; journal first.** `moves.jsonl` is written before any store
  write (step 1); a move is cheaply reversible (re-point).
- **R7 One actuator per session.** The broker is the sole lane writer; it claims `sid` by (lane lock + routes epoch)
  and the census refuses two owners.
- **R8 Credential safety.** The lane holds an **inference-only** copy (`refreshToken:null`) — never a refresh token
  — so it can never provoke rotation or the `invalid_grant` erase (`jhr` @4654023); every CC lock is taken in CC's
  order (`.storage-write.lock`); heal/relogin (`claude-accounts`, `cc-relogin`) act only on account dirs, never on
  lanes; no token is printed. A grant lives in exactly one refreshable holder per account (§12).
- **R9 One time-aware attribution source of truth.** routes.json, consumed by the router, the reconciler facts, the
  usage sweep and the verdict. Replaces the config_dir keying in ~68 files (S05 §0.4, L4) for laned sessions.
- **R10 Bounded external calls under load 300–900.** No `ps -ax` (S07); the census is one `sysctl` (3.3 ms). Lane
  writes are local keychain/file ops; the follower polls on mdat-change, not a tight loop; every broker wait is
  budgeted.
- **R11 Operator authority.** Intent re-checked per move; fail-closed router; the §9 switches; no unowned typing.
- **R12 No filler sessions.** The rebalancer only moves existing work (D-brief:89).
- **R13 Teams never orphaned.** A teammate is its own process (S10 Part B); the launcher lanes each teammate too
  (G2 (b): `H()` @36021704 forwards `CLAUDE_SECURESTORAGE_CONFIG_DIR` to pane teammates), so a lead's move does not
  touch members' billing, and a member's account follows its lead's policy via its own route.
- **R14 Fail closed on binary drift.** The broker pins CC 2.1.293 (BUILD 2026-10-07, GIT_SHA 3abc54a9) and the
  offsets in §0/§4; on an uncertified `claude.exe` it refuses to lane new sessions and pages.

---

## 12. Failure-mode table (every observed mode → structural answer)

| # | Observed mode (source) | Structural answer in this design |
|---|---|---|
| F1 | `/exit` kills the in-flight turn, no output persisted (S05 §2.1; handoff-fire:20757) | No `/exit`. In-process lane rewrite. |
| F2 | Subagents killed by recycle (S05 §2.1; `killed_inflight`) | Process lives; subagents adopt the lane on their next request (G3 §2). |
| F3 | Background Bash jobs die with the exit (P7; S10) | Process lives; jobs untouched. |
| F4 | "Background work is running" exit modal stalls the move (S05 §2.1) | Never raised (no exit). |
| F5 | Draft / `[Pasted text #N]` destroyed or merged by `/exit` (S05 §2.2) | Never typed into; preserved. |
| F6 | `hold:goal-live` — a `/goal` re-drives mid-move (S06: 4 held tonight) | Goal keeps running in-process across the rewrite; no hold needed. |
| F7 | Husk / half-moved / stale tombstone / stranded / fork (S05 §3) | None exist: no transcript copy, no retire, no second writer, no relaunch. |
| F8 | Prompt-cache rewrite on the new org (S05 §2.1 `hold:warm-cache`; R11) | One prefix re-create per move (P3 ~6.1 K tokens), accepted; rebalancer paces + hysteresis (§7). |
| F9 | `became-limited` / owes a turn (S05 §2.2) | Billing move in ≤1 call; nudge restores the turn (§6), orthogonal. |
| F10 | Refresh-token rotation → `invalid_grant` → `jhr` blanks the store (S01 §4; S09 §3.6 #381; D-brief P refresh hazard) | Lanes are inference-only (`refreshToken:null`); the broker never refreshes; exactly one refresher per account (`claude-accounts`). No new sharing is created (contrast G1 §5: a keychain *copy* would). |
| F11 | Revoke-on-refresh: source refresh revokes the old access token (P9 accruing; S09 #381) | The follower re-copies B's fresh access token on mdat-change *before* the old one is used; the backstop is `Khe` 401→rebuild→retry (@12388136; D-brief P Retry loop): one 401 + retry adopts the re-copied token. Design does not depend on P9's answer. |
| F12 | Account with no native refresher (brief) | `claude-accounts --local-refresh` is the designated single refresher for every account, live sessions or not (G1 §0); the follower trails it. If an account truly has no refresher and no refresh token, its lanes 401 at access-token expiry and the broker routes those sessions off it (fail-loud), never minting a setup-token (ruling a90e1ac2597e). |
| F13 | mcpOAuth lost on a fresh lane / clobbered by a swap (brief; G2 (a)) | Keychain-primary lane (§4): the client writes/refreshes `mcpOAuth` into the lane item; the broker RMW preserves it. A fresh lane is seeded with a copy of the account's `mcpOAuth` at launch. |
| F14 | `cache_touch` keepalive client cached ≤240 s (G3 §2 4b) | A keepalive POST may bill the *old* account for ≤240 s post-move. It is a keepalive, not a model generation — a minor attribution smear, logged, not a correctness bug. (Optional: the broker can bump the lane mtime a second time to shorten it; not worth it.) |
| F15 | In-flight streaming request finishes on the old bearer (G3 §3) | Accepted and inside the DoD: billing is old-account up to that one request, new from the next build. This is the "within 1 API call" boundary. |
| F16 | `404 thread_not_found` on the first cross-org request (P5) | Client thread layer replays as `create` (`Hhe()` @12372944); one ≈225 ms round trip; transcript linear. |
| F17 | Stale `.credentials.json` pins the memo (Case B; next3/tertiary; S14 §5) | Every swap does an atomic rewrite → mtime always advances → `ox()` → immediate adoption. The stale **account-dir** tertiary file (G1 §3) is a separate operator cleanup, not a lane. |
| F18 | Symlinked lane `.credentials.json` followed by the live plaintext backend (my read, `A1probe2.py`; corrects G2) | Broker enforces `O_NOFOLLOW`+`lstat`+`0600`+owner on every lane write; the client's live backend does **not** refuse symlinks (v5 O_NOFOLLOW is inert), so hygiene is broker-side. |
| F19 | 30 s keychain cache delays adoption (S01 §3 Case A) | Avoided: file-present + mtime bump → `ox()`→`p0()` zeroes the cache; adoption is the next request (P4 ≈4.5 s). |
| F20 | Identity mismatch: `account_uuid` keeps the launch account (P6; G4) | See §14 D1. Default: accept (bearer bills correctly); optional resync arm. |
| F21 | `ps` census goes blind 15 passes at load 650–770 (S07 §5) | `sysctl KERN_PROC_ALL` census (§13 below), 3.3 ms vs 42 s timeouts. |
| F22 | A client `mutate` migrates a file-only lane to the keychain and deletes the file (@3743013) | Keychain-primary lane (§4): prior item exists, so `update` keeps the file. |
| F23 | Lane rebind impossible in a running process (G2 (b)) | Accepted: lanes bind at launch; rollout is launch-time (§8); no live rebind attempted. |
| F24 | Settings-env live rebind would hit every session (shared `~/.claude/settings.json`; G2 (b)) | Not used. The lane is a launcher env var, never a settings-env value. |

## 13. The ps-free reconciler census (S07, folded in)

The reconciler census is `lr_recon/proctable.py` (S07 §6), unchanged in substance:
- One `sysctl(CTL_KERN,KERN_PROC,KERN_PROC_ALL)` → pid, ppid, zombie bit, lstart, tdev for all ~2,167 rows in
  **3.3 ms** at load 624 (vs `/bin/ps` timing out at 42 s; 97 ps-degraded abstains, 15 blind passes, S07 §5). It has
  no uid check, so it supplies lstart/tty for the **root-owned `login` pane roots** that `proc_pidinfo` EPERMs on.
- tty from a `/dev/tty*` `st_rdev` map (0.7 ms). Args from `KERN_PROCARGS2` on a **bounded worker thread**,
  claude-family first (~93 procs, 9 ms), per-call deadline `ARGS_CALL_S=0.5`, budget `ARGS_BUDGET_S=3.0`,
  `STUCK_MAX=2`. Fail-closed: an unread claude-family arg marks `ps-args` degraded and abstains, never renders
  `(comm)` (S07 §6).
- **Fold-in for this design:** after building the proc table, the census joins **pid→sid** (registry row /
  `--record-id` in args) **→ routes.json → billing account** (R9). Billing attribution no longer comes from the
  config dir. A laned session absent from routes.json, or whose lane fingerprint is stale, is marked degraded and
  abstained (R5). The lane path, if read from the KERN_PROCARGS2 env block, is treated as data and never logged
  (the env block can hold credentials, S07 §6).
- Shadow→on rollout and the `LR_RECON_PSFREE` / `ps-free.off` kill switch are exactly S07 §6.

---

## 14. Rejected alternatives

| Alt | Why rejected |
|---|---|
| **Bearer-swapping proxy (M7)** | Works mid-turn (P3) but a non-first-party base URL latches off server-side threads + Remote Control for the session's life (P2/S03/S09 §5 `Of()`), and all non-inference endpoints bypass it anyway (S03). The brief asks for client-native. Kept only as a laneless fallback idea, not used. |
| **Observer-only proxy for attribution** | Would give per-request `anthropic-organization-id` on disk, but still forces the non-first-party degradation (P2) — same latch. Not worth losing threads/RC for a verification nicety; §10 uses fingerprints + utilization instead. |
| **File-only lane (P4 shape)** | A client `mutate` (mcpOAuth) migrates it to the keychain and deletes the file (@3743013); later swaps silently ignored. §4. |
| **Keychain swap of the account's own dir (M5)** | Moves *every* sibling session on that dir (G2, S05); creates refresh-token sharing (G1 §5) → rotation/`invalid_grant` erase. The lane's whole point is per-session isolation. |
| **Copying a refreshable credential into the lane** | Two holders of one refresh token → first refresh rotates, the other gets `invalid_grant`, `jhr` blanks it (S01 §4; S09 §3.2/§3.6). Lanes are inference-only only (R8). |
| **setup-token per account (M13)** | Would remove even the follower dependency (1-year inference token), but is vetoed by operator ruling `a90e1ac2597e` (D-brief:69). This design does **not** use setup-tokens, so it carries no `Replaces:` tag. |
| **Plugin `$.env.set` to swap `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_BASE_URL` in-process (M14)** | `EIo` @11552107 does write `process.env` (confirmed `A1probe2.py`; S09 §5), and SmelterLabs measured it per-request on 2.1.286. But it needs `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` + a plugin loaded at launch, an env token pins out `/login` and disables the store watch (S13 §6/§8), and it still leaves the identity mismatch. The lane is simpler, needs no plugin, and keeps the store path live. Noted as an alternative in-process trigger only. |
| **Per-session `CLAUDE_CONFIG_DIR` for everyone** | Cleanest for identity (lets the broker rewrite each session's `oauthAccount`) but moves the transcript out of the account `projects/` and breaks the config_dir=account assumption in ~68 files (S05 L4). Deferred to operator decision D1. |

---

## 15. Residual risks

1. **Identity mismatch (P6/G4).** After a lane move, `metadata.user_id.account_uuid` keeps the launch account
   (`iL()` stamped at launch wins in `KWe` @8876727; adopt paths only *null* it, never restamp; G4). The server
   effect is unknown (G4/S08 open). Bearer billing is correct regardless. Handled by D1.
2. **Policy exposure (S08).** Keychain/store rewrite rated Low-Moderate (60% not-a-breach today); rotating own
   accounts to stretch limits is unaddressed and gets worse under the 2026-11-12 AUP ("create multiple accounts …
   circumvent product guardrails", undefined). One tool-linked ban exists (TeamClaude #529, S09). This design is
   the *unmodified official client reading its own accounts' tokens, first-party, no third-party component on the
   wire* — the weakest-exposure shape short of the incumbent restart (S08 M1<M3<M2). It is an operator risk
   acceptance, D3.
3. **Attribution lag.** No per-request org header on disk (§10); corroboration via utilization lags seconds–minutes.
4. **Follower race on revoke-on-refresh (F11).** A tight window where a lane holds a just-revoked access token; the
   401→retry backstop bounds the cost to one failed request, but under a pathological refresh storm a session could
   see a few 401s before the follower catches up. Bounded by `Khe`'s retry count.
5. **Binary drift.** All offsets are 2.1.293-specific; an auto-update invalidates them (R14 refuses, but that itself
   halts laning until re-certified).
6. **`cache_touch` ≤240 s old-account keepalive smear (F14).** Cosmetic attribution only.

---

## 16. Operator decisions I cannot settle at >90% conviction

**D1 — Identity consistency.** Accept the P6 `account_uuid` mismatch (lane-only, all probes did this and worked) vs
add a resync arm. Conviction the mismatch is server-side harmless today: **~55%** (G4/S08 both leave it open).
Options: (a) **accept** — ship lane-only, monitor `anthropic-*` responses and S09-style ban signals, add an arm
only if a signal appears; (b) **per-session `CLAUDE_CONFIG_DIR`** + external `oauthAccount` rewrite (picked up ~1 s,
`Mn()` follows; but `iL()` still wins until a bootstrap restamp) — deep refactor of the config_dir=account
assumption (~68 files); (c) **forced bootstrap restamp** via a no-op `/model` re-pin hook after each move
(`lane-identity-resync.sh`) so `tCs`→`ot()` restamps `iL()` from the live bearer (G4 lists `/model` among bootstrap
triggers) — unproven and adds a turn-boundary action. **Recommendation: (a) now, (c) behind
`LANE_IDENTITY_RESYNC` as an experiment**, (b) only if the server proves to gate on `account_uuid`.

**D2 — Lane backend.** Keychain-primary (chosen, §4) vs file-only (P4). Conviction keychain-primary is correct for
a fleet that uses OAuth MCP servers: **~75%**. Options: keychain-primary (robust to client `mutate`, creates a
lane keychain item); file-only (P4-pure, "no keychain item" per P4, but F22 breaks it the first time an MCP token
saves). **Recommendation: keychain-primary**, unless the operator confirms *no* session ever uses an OAuth MCP
server, in which case file-only is a hair cleaner on policy optics.

**D3 — Policy risk acceptance.** Conviction this scheme is not a breach of the text in force on 2026-10-25:
**~60%** (S08 M3). Options: run it (own accounts, official client, first-party, no proxy); run it only for
limit-recovery (not voluntary rebalance); don't run it, keep the incumbent. This is the operator's legal call, not
a technical one. **Recommendation: run limit-recovery now; gate rebalance behind an explicit opt-in given the
2026-11-12 AUP ambiguity.**

**D4 — Rollout of laneless sessions.** Conviction that opportunistic drain (no forced relaunch) is right: **~70%**.
Options: drain only (§8); or force-relaunch laneless sessions into lanes during a quiet window (costs each a turn).
**Recommendation: drain only**; the DoD forbids a forced lost turn.

**D5 — Follower cadence.** Conviction that mdat-subscribe + a slow timer backstop beats a fixed poll: **~70%**.
Options: subscribe to each account keychain mdat and re-copy on change (plus a 60 s safety timer); or a fixed fast
poll. **Recommendation: subscribe + 60 s backstop**, reusing the `claude-accounts` feed (G1 §0) so no new keychain
read cadence is added.

---

## 17. Notes and offsets cited

D-brief (problem, DoD, M1–M22, measured P-facts); P-probes P1–P9; S01 §1–§5 (store/`wA`/`Pl`/`Jf`/`Nk`,
`zn()` @3751307, `cPt=30000`, refresh hazards); S05 §1–§5 (incumbent gates, graveyard, R-invariants);
S06 (idle-never-happens, mid-turn 0.668, 56/56 snapshots); S07 §1–§6 (ps-free census); S08 §3–§4 (exposure
M1<M3<M2); S09 §1–§6 (prior art, refresh races, `env.set` `EIo`, `thread_not_found` @12372944, `Of()` @2000767);
S10 Part A/B (hooks can trigger not implement; what a restart kills); S12 §6 (bg supervisor pins config dir);
S13 §1–§11 (setup-token inference-only, 401 with env token, ruling a90e1ac2597e); S14 §1–§7 (lane store, keychain
`FF()`, `M.update` delete-on-migrate @3743013, inference-only swap protocol); G1 §1–§5 (four independent grants,
one refresher per account, tertiary stale file); G2 (a)/(b)/(c) (lane coverage, teammate/bg forwarding, identity
leak, v5-store O_NOFOLLOW is inert); G3 §1–§6 (every inference path runs the check; in-flight finishes on old
bearer; `cache_touch` ≤240 s); G4 (only /login + bootstrap restamp `iL()`; `KWe` @8876727).
My own re-confirms (`/tmp/mtam/A1probe*.py`): `uw()`/`FF()` @3737607; live plaintext `readFileSync` **no**
`O_NOFOLLOW` @3750135 vs inert v5 `O_NOFOLLOW` @5230540; `M.update` `if(i===null)await r.delete(o)` @3743013;
`EIo` env.set @11552107; `Khe` rebuild gate @12388136.
