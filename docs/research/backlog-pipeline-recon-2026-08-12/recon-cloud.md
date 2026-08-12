# RECON — can backlog work run end-to-end in Claude Cloud today?

Read-only. Measured 2026-08-12 ~08:40–09:00Z on the live box. Repo
`/Users/chrisren/Development/claude-infrastructure` (checkout at `0ffe96995`, **7 commits behind
`origin/main` `47cf3a8c3`**).

---

## ANSWER IN ONE PARAGRAPH

**Yes — the pipeline runs autonomously today, and it is running right now: six cloud sessions were
created by the launchd dispatcher between 03:41Z and 07:15Z, all six on real Anthropic VMs with the
repo attached, all six pushed to `origin`. It breaks at the very last stage.** Of the six, **one**
reached content-verified-on-trunk and its backlog row still failed to close
(`"backlog":"could NOT mark 0b4d4e8a1889 done (cc-backlog refused)"`); the other five are stuck at
land (3x bound-cut, 1x worktree conflict, 1x still waiting). Because a cloud claim is counted by the
dispatcher's **venue-blind concurrency ceiling**, those six unclosed claims now read `live_workers:6
/ ceiling:6 / free_slots:0`, and the dispatcher has fired **nothing at all — cloud or local — since
07:15Z**. So the honest answer to "without consuming a local session slot" is: it consumes **no
pane, no worktree, no local CPU for the *work*** — but it consumes **one of the six dispatcher
admission slots, indefinitely**, and the local *land* still costs a `/tmp` worktree and up to 900 s
of the launchd sweep.

---

## PIPELINE MAP — stage by stage

| # | Stage | Verdict | Evidence |
|---|---|---|---|
| 1 | **decide venue** | **BUILT + PROVEN** | `bin/cc-venue` (producer, W1) imports `bin/cc-eligible` as a module (`bin/cc-venue:_load_eligible`) so the report and the claim-gate refusal are one code object. Live store: 47 cloud / 242 local / 247 unlabelled of 536 open+blocked. |
| 2 | **admit** | **BUILT + PROVEN, currently WEDGED** | `bin/cc-dispatch:1910` appends `--venue cloud`; the `CC_DISPATCH_VENUE_ONLY=cloud` filter (commit `8e179c429`) parks the rest and COUNTS them. IDL 08:40:23Z: `venue-only=cloud parked 280 of 319`. **But** `bin/cc-dispatch:438 live_workers()` folds `.status=="claimed"` with **no venue filter** -> 6/6, `free_slots:0`, `deferred:318`, `fired:0`. |
| 3 | **create the cloud session** | **BUILT + PROVEN** | `bin/cc-offload up --via api` -> `scripts/cloud-create-api.py` two-call sequence (`GET /v1/environment_providers` then `POST /v1/sessions` with `environment_id` + `config.sources`), acceptance-gated at exit 5 unless `environment_kind==anthropic_cloud` **and** exactly 1 git source. **Six live creates today**, `~/.claude/logs/dispatch-fires.log`: `session_01VMwdAbwLif...`, `01Y8FCj2pk...`, `01Fe18fUex...`, `01CHL2GUxK...`, `01CCZcjYGJ...`, `01Ju5s2xRD...` — each logged `anthropic_cloud VM, repo ATTACHED`. |
| 4 | **execute + push** | **BUILT + PROVEN** | All six branches exist on `origin` with real shas (`git ls-remote`): `071751fd`, `28379a8a`, `4053f324`, `4e339f42`, `4ea70dda`, `6eb74d04`. |
| 5 | **detect completion** | **BUILT + PROVEN** | `scripts/cloud-return.sh` — RETURN-READY = conjunction of (pushed per `cc-cloud` state) AND (worker not running) AND (sha quiet >= `CC_RETURN_QUIET_S`=180 s). Driven from launchd, `scripts/autonomy-sweep.sh:622-638`, `timeout -k 10 900`, above the nothing-new early exit. `return.jsonl` has 46 rows incl. today's `waiting` / `land-cut` / `returned`. |
| 6 | **land** | **BUILT, UNRELIABLE** | `scripts/cloud-reconcile.sh --land` re-authors the VM's commits (the VM commits as `noreply@anthropic.com`) with `Cloud-session:`/`Original-commit:`/`Original-branch:` trailers. Today: **3 land-cuts + 1 refusal + 1 success** across 6 sessions. |
| 7 | **verify by content** | **BUILT + PROVEN** | `scripts/cloud-return.sh:355-357` — `git ls-tree` / `git show origin/main:<path>`, never by sha (the land re-authors, so the pushed sha never lands). `content_verified:true` on `session_01CCZcjYGJnLMuRQrFzaaqx7`. |
| 8 | **wake the originator** | **BUILT, STRUCTURALLY DEAD for dispatcher fires** | `scripts/cloud-return.sh:205-214 wake()`. **4 of 38 declarations carry `notify_back`** — and all 4 are hand-fired. Every dispatcher fire logs `no pane to wake (ITERM_SESSION_ID is unset) — this fire is FIRE-AND-FORGET ... UNMANAGED: custody OPEN but NOTHING will be woken`. |
| 9 | **route a gate refusal back** | **BUILT + PROVEN (once), then dead-ends** | `scripts/cloud-refusal-route.sh`. W3's live proof stands (VM pushed the lint's own remedy 56 s later). Today's refusal classified correctly (`arm=local-only`, `routed=originator`) and then: `"send":"the declaration names no notify-back target — nothing to wake"`. |
| 10 | **close the backlog row** | **BUILT, FAILED ON ITS ONE LIVE TRY** | `scripts/cloud-return.sh:365-378`. `return.jsonl` 08:15:43Z: `"backlog":"could NOT mark 0b4d4e8a1889 done (cc-backlog refused)"`. **Zero of the six items has a `done` event.** |
| 11 | **release the slot / retire** | **NOT BUILT** | Nothing calls `cc-cloud retire` — grep of `cloud-return.sh` / `cloud-reconcile.sh` / `autonomy-sweep.sh` finds only *reads* of `.retired`. **0 `.retired` markers exist on disk** across 38 declarations. |

**SPEC-vs-BUILT sweep:** every `bin/`, `scripts/`, `tests/` identifier cited in
`docs/plans/CLOUD_BACKLOG_PIPELINE.md` exists in the tree (0 misses). `CLOUD_OBSERVABILITY.md` cites
4 non-existent paths, all benign: `bin/cc-cloud-watch` (documented as deliberately deleted and
merged into `cc-cloud`), `bin/zsh` + `bin/time` (interpreter fragments), `bin/cc-panes` (stale
name). **Neither plan is prose-only. The pipeline is genuinely built.**

---

## THE FIRST BREAK

**Stage 10 feeding back into stage 2: the backlog row does not close, and an unclosed cloud claim
occupies the dispatcher's local concurrency ceiling.** Two facts compose into one dead-in-place
state.

**(a) The close failed and LATCHED anyway.** `scripts/cloud-return.sh:405-408`:

```
if [ "$landed_ok" -eq 0 ] && { [ "$wrc2" -eq 0 ] || [ "$wrc2" -eq 3 ]; }; then
  { printf 'outcome=returned\n...'; } >"$STATE/$id.returned"
fi
```

The latch condition reads `landed_ok` and the wake rc — **`done_note` is not in it**, and `wrc2==3`
means *"there was no one to wake"*. So `session_01CCZcjYGJnLMuRQrFzaaqx7` landed, content-verified,
discharged custody, failed to close its row, woke nobody, and wrote `.returned` — after which
`handle()` short-circuits at line 240 (`already returned`) on **every future sweep, forever**. The
failure is unretryable by construction and is recorded in exactly one place a human never reads.

**The refusal itself is CONTENTION, not policy — which makes it worse, not better.** Reproduced
read-only against a byte copy of the store (`CC_BACKLOG_FILE=/tmp/... cc-backlog done 0b4d4e8a1889
--evidence ...`) -> **rc 0, 1.96 s**. There is no `done`-side guard in `bin/cc-backlog:1134
cmd_transition` (every guard there is `claim`/`reopen`/`unblock`-side). The IDL at 08:14-08:15Z shows
~100 `lead-supervisor` DEAD-page writes in the same two seconds. `scripts/cloud-return.sh:371`
swallows the reason with `>/dev/null 2>&1` — the exact "caller mutes its callee's non-verdict" shape
this repo has already paid for.

**(b) The ceiling is venue-blind.** `bin/cc-dispatch:438-445`:

```
live_workers() { ... | jq -er '[.[] | select(.status=="claimed")] | length' ... }
```

No venue predicate. Its header (`bin/cc-dispatch:434`) justifies this as *"the ceiling exists to stop
DISPATCH exhausting quota by its own spawning"* — true of quota, **false of the capacity claim the
migration was made for**. `CLOUD_BACKLOG_PIPELINE.md:162` says routing to cloud is a **CAPACITY**
decision — *"what cloud uniquely spares is this box's CPU, RAM, pane and worktree"* — yet the
admission arithmetic charges an off-box session against the same six slots as a local pane.

**(c) Self-healing cannot fire.** The header promises the ceiling self-heals via `cc-backlog reap`.
For a cloud claim the liveness oracle is `cc-cloud is-offbox` — `bin/cc-cloud:682-688`:

```
cmd_is_offbox() { [ -f "$STATE/$id.decl" ] || return 1; [ -f "$STATE/$id.retired" ] && return 1; return 0; }
```

Two file-existence tests. **No completion notion.** All six of today's sessions return `OFFBOX-LIVE`
right now; with 0 `.retired` markers on the box, they will return `OFFBOX-LIVE` forever. `reap` never
reopens, and the `UNRESOLVED_MAX_S` -> BLOCK escape (`bin/cc-backlog:717`) applies only to an
**unresolved** probe — this probe resolves, confidently, to *alive*. The wedge has no timeout.

**Net:** `fired:0, deferred:318` at 08:40:50Z, and every subsequent pass identical. The migration
did not move the backlog to the cloud; it moved six items to the cloud and then stopped the
dispatcher.

---

## MEASURED

**Eligibility of the 536.** Folded from `~/.claude/autonomy/backlog.jsonl` by last-event (1,905 ids
total; 1,369 done):

| bucket | count |
|---|---|
| open + blocked | **536** (327 open, 209 blocked) |
| `venuePlan=cloud` | **47** |
| `venuePlan=local` | **242** |
| **no label at all** | **247** |

Unlabelled dominates because `cc-venue run` is **open-only** (`bin/cc-venue` verb table: *"it is
open-only, because routing informs a dispatch and blocked work reaches none"*), so all 209 blocked
rows are structurally unroutable, and newly-added rows wait for the next producer pass.
`CC_DISPATCH_VENUE_ONLY=cloud` parks an unlabelled row too (absence of a plan is not evidence of
eligibility) — hence the IDL's `parked 280 of 319`.

Recorded local-refusal classes over the 242: `ineligible-box` 149, `ineligible-branch-banking` 23,
`ineligible-spawn-rail` 22, `ineligible-visual` 17, `ineligible-deep-history` 13,
`ineligible-offbox-lane` 9, premise arms 8, `ineligible-github` 1.

**So the cloud-addressable share of the live backlog is 47/536 ~= 8.8%** (47/327 ~= 14% of *open*).
The plist's own note calls this inherent: *"Raising the migrated share means changing what the VM can
reach, never loosening the predicate."*

**Historical successful cloud runs — 4 full round trips, all real, all content-verified:**

| session | date | landed artifact |
|---|---|---|
| `session_013H8jXq4Njbg68rKdsJ8ter` (next) | 2026-08-11 | `docs/research/cloud-w2-roundtrip-2026-08-11.md` — goal MET |
| `session_017ga3J7cGNKkq4AMBmd3rrE` (next3) | 2026-08-11 | `docs/research/cloud-w2-return-rails-2026-08-11.md` — **item `e9a745a7ffb9` marked done**, custody discharged, pane 348 woken |
| `session_01HEudSuWY9hLk2Y5jqqX7Nr` (next3) | 2026-08-11 | W3 refusal loop: real hermeticity lint -> routed -> VM amended in **56 s** -> `9270197a8` + `67dca77aa` |
| `session_01CCZcjYGJnLMuRQrFzaaqx7` (next) | **2026-08-12** | 5 paths incl. `scripts/wrap-ledger.sh` — content-verified, **but `done` refused** |

Only **one** of the four (`017ga3J7`) is a complete dispatch-to-close circuit, and it was hand-fired
with a `notify_back`. **No dispatcher-fired cloud item has ever closed its own backlog row.**

**Today's six, current state:**

| session | item | branch on origin | return outcome |
|---|---|---|---|
| `01VMwdAbwLif...` | `abab60591342` | `071751fd` | `waiting` (quiet 106 s) |
| `01Y8FCj2pkJ...` | `75869b41c9d9` | `28379a8a` | `waiting` (quiet 109 s) |
| `01Fe18fUex...` | `3709b1649792` | `4053f324` | `land-cut` (SIGTERM) |
| `01CHL2GUxK...` | `df2b6a40a5dc` | `4e339f42` | **`land-refused` rc 65** |
| `01CCZcjYGJ...` | `0b4d4e8a1889` | `4ea70dda` | `returned` — **close refused** |
| `01Ju5s2xRD...` | `bae42607ff13` | `6eb74d04` | (fired 07:15, not yet returned) |

All six claims carry `venue=cloud role=dispatcher` (verified in the event log) — the venue plumbing
is correct end to end; it is the *ceiling* that ignores it.

---

## AUTH

**Present and working. Not a blocker.**

- **What it needs:** an OAuth bearer from the account's own keychain item + config dir, resolved
  through `~/.claude/accounts.json` via `claude-accounts --relogin-info` as the arbiter of identity
  (`scripts/cloud-create-api.py`, `account_row()` — *"never hardcoded, never written, never
  logged"*). Plus `anthropic-version: 2023-06-01` (omitting it 400s) and
  `anthropic-beta: ccr-byoc-2025-07-29` for the `/v1/sessions` cloud-environment endpoint.
- **Second, separate credential:** the **GitHub App must be installed on the account**, and that is
  *necessary but not sufficient* — the App authorizes the ACCOUNT; only `config.sources` authorizes
  the session's git proxy. `scripts/cloud-websetup-drive.sh --status` drives `/web-setup` per account
  with zero human input.
- **Proved live, read-only, this session:**
  `python3 scripts/cloud-create-api.py --account next --verify session_01CCZcjYGJnLMuRQrFzaaqx7`
  -> `{"environment_kind":"anthropic_cloud","sources":1,"accepted":true,...}`, rc 0.
- **Quota is not the ceiling either:** `claude-accounts` — next 1%/48%, next3 1%/8%, next4 17%/44%,
  next2 4%/52%; all four healthy, all four pacing *behind*.
- **TLS caveat, already handled:** this python3 ships `cafile=None`, so `urlopen` would raise
  `CERTIFICATE_VERIFY_FAILED`; `tls_context()` names `certifi` then `/etc/ssl/cert.pem` and never
  downgrades to unverified.

---

## THE INTERLOCK (commits `8e179c429` + `9d2e50e34`) — and its live state

- **What it is:** `CC_DISPATCH_DECIDE_ONLY=on` held as a deliberate pause *while*
  `CC_FIRE_CLOUD=on` + `CC_DISPATCH_VENUE_ONLY=cloud` were set, until the **deployed** binary could
  be *proved* to honour the new filter.
- **Why it existed:** the flip was first attempted as a pure config change and **fired 2 LOCAL
  panes**. `~/.claude/bin/cc-dispatch` is a per-file symlink into the shared checkout, which trailed
  `origin/main`; the running program had never heard of `CC_DISPATCH_VENUE_ONLY`. *A shell program
  silently ignores an env var it does not implement — there is no arity error.* It saw only that the
  pause was lifted. **Landing a filter does not make it enforce; the enforcing store is the live
  symlink, not trunk.**
- **What flips it:** step 3 is a **positive control, not a version check** — run one pass with the
  filter set against a queue that HAS local rows and assert the IDL carries
  `venue-only=... parked N of M`; absence of that record is the bleed's signature, because a filter
  that is not there looks exactly like a filter with nothing to do.
- **Live state: DISCHARGED.** `~/Library/LaunchAgents/com.claude.dispatcher.plist` (mtime Aug 11
  20:22 local) no longer exports `CC_DISPATCH_DECIDE_ONLY`; its header records the control passing at
  `venue-only=cloud parked 272 of 315 ... fired 0 local panes`. **That discharge is landed on
  `origin/main` but is NOT in this checkout** (7 commits behind) — so the working tree's plist still
  reads *"DECIDE_ONLY IS STILL ON"*. A redeploy from this checkout would re-arm the pause.

---

## TOP 10 FINDINGS

1. **`bin/cc-dispatch:438 live_workers()` counts `.status=="claimed"` with no venue predicate — so
   six off-box sessions saturate the six-slot local ceiling.** IDL 08:40:49Z: `reason:"at-ceiling",
   free_slots:0, ceiling:6, live_workers:6`; summary `fired:0, deferred:318`. This is the single
   highest-leverage line in the whole pipeline and it directly contradicts
   `CLOUD_BACKLOG_PIPELINE.md:162` ("cloud is a CAPACITY choice").
2. **A fully successful cloud round trip failed to close its backlog row and latched anyway.**
   `~/.claude/autonomy/cloud/return.jsonl` 08:15:43Z: `content_verified:true`, `goal:"MET"`,
   `custody:"discharged"`, `backlog:"could NOT mark 0b4d4e8a1889 done (cc-backlog refused)"`.
   `scripts/cloud-return.sh:405-408` latches on `landed_ok` + wake-rc only, so
   `scripts/cloud-return.sh:240` will `already returned` it forever.
3. **The `done` refusal is contention, not policy.** Reproduced rc 0 in 1.96 s against a store copy;
   `bin/cc-backlog:1134 cmd_transition` has no `done`-side guard. `scripts/cloud-return.sh:371`
   discards the reason with `>/dev/null 2>&1`, so the one fact needed to diagnose it was destroyed
   at the call site.
4. **`bin/cc-cloud:682-688 cmd_is_offbox()` is two file-existence tests with no completion notion**,
   and **nothing anywhere calls `cc-cloud retire`** (0 `.retired` markers across 38 declarations). So
   `cc-backlog reap`'s cloud oracle answers *alive* forever, the ceiling cannot self-heal, and
   `UNRESOLVED_MAX_S` never applies (it bounds *unresolved*, not *resolved-alive*).
5. **Every dispatcher-fired cloud session is born un-wakeable.** launchd has no `ITERM_SESSION_ID`,
   so `bin/cc-offload` logs `no pane to wake ... UNMANAGED: custody OPEN but NOTHING will be woken`.
   **4 of 38 declarations carry `notify_back`, all hand-fired.** `scripts/cloud-return.sh:208`
   returns rc 3, which the latch treats as success — and W3's refusal router dead-ends the same way:
   `refusal-route.jsonl` `{"routed":"originator","send":"the declaration names no notify-back target
   — nothing to wake"}`.
6. **The land is the flakiest stage: 3 land-cuts + 1 refusal + 1 success across 6 sessions today.**
   The cut is correctly read as a non-verdict (`scripts/cloud-return.sh:300-313`, 124/137/143 ->
   `land_rc=-1`), but the outer bound is `timeout -k 10 900` in `scripts/autonomy-sweep.sh:632` and
   the land's own bound is also 900 s — the outer necessarily fires first, so a slow land can only
   ever be cut. `session_01CCZcjY...` burned three passes (06:50, 07:05, 08:13) before landing.
7. **A refused land strands a `/tmp` worktree that blocks every retry.** `<id>.land-refused` rc 65:
   *"local `claude/fire-20260812T041557Z-41314-1` is CHECKED OUT in a worktree
   (`/private/tmp/.desk-land-...`) — a real conflict someone owns. NOT forcing."* Two such
   `.desk-land-*` worktrees are live on the box now. Nothing reaps them, and the router correctly
   classifies this `arm=local-only` — i.e. the VM cannot fix it and the originator does not exist.
8. **The producer's decision is sound and the numbers are stable: 47 cloud / 242 local / 247
   unlabelled of 536.** `bin/cc-venue` imports `bin/cc-eligible` as a module rather than
   re-deriving, so report and gate cannot drift; the gate fails OPEN and the producer fails CLOSED,
   deliberately. **The addressable cloud share is ~8.8% of open+blocked, and that is inherent** —
   the shallow 50-commit clone, no `gh`, no `~/.claude`.
9. **Auth is not a blocker, on any axis.** Live `--verify` returned
   `environment_kind:anthropic_cloud, sources:1, accepted:true` on account `next`; all four accounts
   are at 1-17% of the 5 h window and pacing behind weekly. The historically hard part — bundle
   sessions getting `sources:[]` and a 403 from the git proxy — is closed by
   `scripts/cloud-create-api.py`'s two-call `/v1/sessions` create with an exit-5 acceptance gate.
10. **Both plan docs are BUILT, not prose.** Every `bin|scripts|tests` identifier in
    `CLOUD_BACKLOG_PIPELINE.md` resolves; `CLOUD_OBSERVABILITY.md` has 4 misses, all benign
    (`cc-cloud-watch` deliberately deleted, `bin/zsh`/`bin/time` interpreter fragments,
    `bin/cc-panes` stale). **The gap is not missing mechanism — it is that the last two stages have
    never once run unattended to completion.**

---

## ADVERSARIAL PASS — what I checked because it would have refuted the above

- **"Maybe the dispatcher stopped for a different reason (kill-switch, capacity gate, quota)."**
  Refuted: the plist has no `DECIDE_ONLY`, `launchctl list` shows `com.claude.dispatcher` status 0,
  all four accounts are far from any limit, and every one of the last 318 decision rows names
  `reason:"at-ceiling"` explicitly. The ceiling is the binding constraint.
- **"Maybe `cc-backlog done` structurally refuses a cloud-claimed item."** Refuted by reproduction on
  a store copy (rc 0) and by reading every guard in `cmd_transition` — all are claim/reopen/unblock
  side. This *strengthens* the finding: an unreliable-and-unretried close is worse than a principled
  refusal.
- **"Maybe the claims lack `--venue cloud`, so reap will false-dead them and re-fire duplicates."**
  Refuted: all six claim events carry `venue=cloud role=dispatcher`. The plumbing is right; the
  hazard is the opposite one — the cloud oracle is *too* permissive and never lets go.
- **"Maybe the wedge times out on its own."** Refuted: `UNRESOLVED_MAX_S` bounds an *abstaining*
  oracle. `is-offbox` does not abstain; it answers *alive* from a file that nothing deletes.

## BLOCKERS / UNCERTAINTIES named

- I did not determine **which** concurrent writer made `cc-backlog done` return non-zero at
  08:15:43Z — the reason was discarded at the call site (`>/dev/null 2>&1`). Circumstantial: ~100
  `lead-supervisor` DEAD-page IDL writes in the same 2 s.
- I did not run `cc-venue run` or `cc-eligible sweep` (both re-derive with `cc-premise` over 327
  items; `run` is dry-by-default but slow). The 47/242/247 split is folded from the store's own
  `venue` events, which is what those tools wrote.
- Whether `cloud-return`'s single-flight lock should bar a second land of the **same branch** is
  still open per `CLOUD_BACKLOG_PIPELINE.md` §7.2 — two concurrent lands on one branch have already
  been observed, and it ended well by luck.
