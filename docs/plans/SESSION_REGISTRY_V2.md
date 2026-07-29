---
status: open
---

# SESSION REGISTRY V2 — first-principles liveness & reaping architecture

**Scope (frozen):** the session registry & reaping subsystem achieves ZERO live-conversation reaps
and a reap decision no more than 60s stale, under the standing constraint that a live operator
conversation is NEVER reaped — measured, landed, and verified by disk-truth acceptance reads.

Status: DESIGN 2026-07-29 · owner session gu-session-registry-reaping · branch
`gu-session-registry-reaping` · row 4 of docs/plans/GROUND_UP_REBUILD_MAP.md

**Standing constraint that kills lazy designs:** *a live operator conversation is never reaped, and
the operator never announces presence.* Presence must be inferred from traffic the operator already
generates. There is no "ask the human" fallback and no quiet period — the box runs 12+ concurrent
sessions 24/7, and the reaper is a launchd daemon with no supervisor.

**Seam consumed, NOT redesigned:** pane-teardown mechanics (how a pane is actually closed —
`cc-teardown`'s actuation, effect-verify, tty-exclusivity, marker writing) belong to **row 2
(session lifecycle)**. This rebuild changes *what evidence a close requires* and *how fresh it must
be*; it does not change how the close is performed.

---

## Phase 0 — Agent Team Orchestration

**Decision: NO teammate wave. Single-session build.** The ground-up skill's Phase 4 defaults to
Agent Teams, and the global rule mandates them for 2+ code-writing tasks — but the deliverable here
is dominated by ONE shared contract (the beat schema + the freshness lease) threaded through five
files that all read and write it. Per the `staged-skill-fanout-trap` memory: *when stages share
state the fan-out is dominated; fan out over slices only.* There are no disjoint slices — every
file's correctness depends on the same two structures. Splitting would buy parallelism at the cost
of the seam that the whole design is. The build is ~400 LOC across 5 files, well under the 500-LOC
split threshold.

| Work | Files | Owner |
|---|---|---|
| Beat producer (write-side) | `hooks/session-beat.sh` (new), `hooks/session-register.sh` | this session |
| Beat reader + freshness lease | `hooks/lib/cc-beat.sh` (new) | this session |
| Decision freshness enforcement | `bin/cc-reaper`, `bin/cc-teardown` | this session |
| Registry truth (dead-row reaping) | `bin/cc-reconcile` | this session |
| Proof | `tests/session-beat.bats`, `tests/reap-freshness.bats` (new) | this session |

---

## §1 First principles — why the incumbent frame cannot hit 60s

The reaper must answer one question per session — *may this pane be closed?* — and the answer's
load-bearing half is **who drove the last turn** (the 2026-07-24 law: surface-state "idle + clean +
landed" is every live conversation's steady state between prompts, so WHEN/WHAT can never prove
done; only WHO can).

The incumbent answers it by **reconstruction**: at sweep time, for every session, re-derive the
answer by scanning the transcript, running git in the worktree, and shelling out to three foreign
binaries. Measured consequences, none fixable inside the frame:

- **The decision is a batch snapshot.** `cc-classify --all --json` is ONE call (`bin/cc-reaper:580`).
  Every session's disposition is frozen at sweep start; the reaper then loops, acting on each.
- **The sweep is unbounded.** `grep -c 'timeout ' bin/cc-reaper` = **0**. The sweep synchronously
  invokes `cc-reconcile`, `cc-backlog reap`, and `cc-inbox-guard` — the last being the exact binary
  whose unbounded fork caused the 5-day gate blockage ([[five-day-gate-blockage-rootcause]]). The
  reaper has become the cron carrier for three other subsystems' periodic work.
- **So the decision→act gap is unbounded.** Sweep duration p50 58s, **p90 403s, p99 2,099s, max
  55,659s (15.5 h)**; 16.5% of sweeps outlive their own 300s interval. A session classified at sweep
  start can be torn down 35 minutes later (p99) on evidence frozen 35 minutes earlier. **An operator
  who types during the sweep is invisible to the decision that closes their pane.**
- **The act-time re-verification is partial and asymmetric.** At act time the reaper re-reads git
  state (`work_landed`, :742) and successor liveness (:713) — but the *operator-presence* re-read
  exists for exactly ONE cause, `coordination-abandoned` (:681-705). **95% of all reaps ever
  performed (76/80) are `finished`/`finished-teammate`** — the two causes whose only independent
  act-time leg is a **static** `cc-fired` marker, not a presence read, and the two causes that
  reaped the two live operator conversations on 2026-07-24.
- **The one fresh presence read fails OPEN in three ways.** `cc-teardown:298-336` is the last line
  of defence. It skips when the lib is absent (`:316` WARN+skip), falls through when the transcript
  is unresolvable (`:321`, no else), and falls through when no interactive turn is visible (`:324`,
  no else). All three are *cannot prove presence ⇒ proceed to close* — the inverse of this repo's
  own absence-is-loud law. (Verified 2026-07-29: the lib IS present live, so this is a **latent**
  hazard, not a firing P0. It resolves through the shared checkout, whose branch varies.)
- **Neither presence belt has ever fired.** Across 1,872 sweeps and 168 teardown proposals:
  `belt-refuse` = **0**, teardown `rc=2` (REFUSE, the operator-adopted exit) = **0** (67 rc=10 DEFER
  + 21 rc=5 FAIL). The 2026-07-24 fix's two downstream legs are **unexercised in production** — their
  correctness is unproven, not proven. cc-classify's upstream §4.7 hold absorbs the cases.
- **The upstream decision is wrong more often than right.** cc-teardown refused **88 of 168**
  proposals (**52.4%**). The actuator's own gate is doing the majority of the deciding — a direct
  measure of how little the classify-time verdict is worth by the time it is acted on.

**The economic root.** The presence predicate is evaluated by *re-deriving it from the transcript*,
forever, by every closer, on every sweep — O(sweeps × sessions × transcript_bytes). Yet the fact is
known **for free, exactly once, at the instant the operator's prompt arrives**, by the session
holding that prompt. The incumbent throws that away and pays to rebuild it ~19,412 times (measured
classifications) to make 80 decisions.

### Conclusion — the inversion (two moves)

**Move 1 — ATTEST, don't reconstruct.** The session writes a tiny durable **beat** at the moments it
already knows the answer (hooks that already fire: SessionStart · UserPromptSubmit · Stop ·
SessionEnd). The interactive predicate runs **once per prompt, at write time**, on the prompt in
hand. A reap decision becomes an O(1) read of a few small files (~5 ms) instead of a multi-MB
transcript scan.

**Move 2 — LEASE the decision; the actuator refuses stale ones.** Every reap decision carries the
epoch it was made. `cc-teardown` **refuses** any decision older than `CC_REAP_DECISION_MAX_STALE_S`
(default 60). Freshness stops being something the sweep must *achieve* and becomes something the
actuator *enforces*.

Move 2 is what makes the 60s target structural rather than aspirational. It does not require the
sweep to be fast — it makes a slow sweep **reap nothing** instead of reaping wrongly. Staleness is
converted from a *safety* failure into a *liveness* failure, and the safe direction is the default.
Move 1 is what makes the sweep fast enough that the lease is satisfiable in the normal case (a ~5 ms
decision can always be re-taken immediately before the close).

*If the new design were the old one with bigger constants* — a shorter interval, a longer hold, more
retries — it would be Phase-1 work again. It is not: the decision's **cost model** and its
**validity model** both change. Nothing in v2 tunes a window.

Industry precedent: this is the lease/fencing-token pattern (Chubby, ZooKeeper ephemeral nodes,
Kubernetes node leases). Distributed systems abandoned "poll and reconstruct liveness" for
"heartbeat + bounded lease" for exactly this reason — a reconstructed verdict is stale by an amount
the reconstructor cannot bound, so the actuator must be the one to enforce freshness.

### Requirements (goal + invariants that SURVIVE the redesign)

- **R1** A reap decision is acted on within `CC_REAP_DECISION_MAX_STALE_S` (60s) of the evidence it
  rests on, or it is refused. Enforced at the actuator, not trusted from the caller.
- **R2** Zero live-conversation reaps. Operator presence within the hold window ⇒ REFUSE (never
  DEFER — a refusal is terminal, a defer retries next sweep).
- **R3** Absence of evidence is never evidence of absence. Cannot-prove-not-present ⇒ refuse **and
  surface**. (Carried from the fail-closed law; this is the direct fix for the three fail-opens.)
- **R4** R3 must not silently inert the reaper. A refuse-for-absence is gated on **existence
  evidence** that the beat system is live, and every such refusal is loud
  ([[absence-alarm-needs-existence-evidence]]). A world with no beats at all is a *detected*
  condition, never a silent 100%-abstain.
- **R5** Every external call in the sweep is bounded by absolute-path `timeout(1)`; a bound covers
  the failure mode it bounds. No unbounded foreign binary may sit in the decision path.
- **R6** Identity is (pid, lstart) — never pid alone (recycling), never argv (sampling;
  [[argv-is-sampling-cwd-is-durable]]), never a bare `ITERM_SESSION_ID` (tmux panes inherit the
  server's; [[tmux-panes-inherit-server-iterm-session-id]]).
- **R7** The registry is self-healing: a row whose (pid, lstart) is dead is pruned, and pruning is
  never itself a close.
- **R8** Every new mechanism ships with an env kill switch; never revert-as-plan.
- **R9** The beat is best-effort on the write side and **required** on the read side only under R4's
  existence gate — a hook that fails to beat must never cost a session (the fail-open contract of
  `session-register.sh:26-32` is kept verbatim for the producer).

---

## §2 Measured constants this design is built against

All re-derived from primary disk truth 2026-07-29 in this session; no handed-down counts
([[re-derive-handed-down-measurements]]).

| Constant | Value | Source (disk-truth read) |
|---|---|---|
| Registry rows | 25 | `ls ~/.claude/cc-registry/*.json \| wc -l` |
| **Registry rows with a DEAD pid** | **13 (52%)** | `kill -0` per row's `.pid` |
| Registry refresh after SessionStart | **never** (`startedAt` write-once) | `hooks/session-register.sh:69-84` |
| Sweeps (lifetime) | 1,872 | `sweep end:` lines, cc-reaper.log |
| Classifications | 19,412 | sum of `N classified` |
| Candidates | 206 | sum of `N candidates` |
| **Reaps (lifetime)** | **80** (0.4% of classifications) | sum of `N reaped` |
| Reap causes | finished 48 · finished-teammate 28 · coordination-abandoned 3 · handed-off-lead 1 | `reaped … [cause]` |
| **Reaps by a cause with NO fresh act-time presence read** | **76/80 (95%)** | causes × `cc-reaper:676-721` |
| Sweep duration | p50 **58s** · p90 **403s** · p99 **2,099s** · max **55,659s** | start→end pairs |
| Sweeps outliving their 300s interval | **309 (16.5%)** | duration > 300 |
| Inter-sweep gap | p50 301s (⇒ StartInterval 300) | end→start pairs |
| **cc-teardown refusals** | **88 of 168 proposals (52.4%)** | `teardown-refused` (67 rc=10, 21 rc=5) |
| **teardown rc=2 (operator-adopted REFUSE)** | **0 — never fired** | rc distribution |
| **reaper `belt-refuse`** | **0 — never fired** | cc-reaper.log |
| `suspend-defer` firings | 13 | cc-reaper.log |
| `timeout(1)` bounds in cc-reaper | **0** | `grep -c 'timeout ' bin/cc-reaper` |
| Foreign binaries in the sweep | 3 (cc-reconcile, cc-backlog, cc-inbox-guard) | `bin/cc-reaper:187-212` |
| Log lines that are one damped foreign line | 59,189 / 73,751 (**80%**) | cc-inbox-guard escalation line |
| Who-oracle cost (the thing being re-derived) | 55–171 ms per transcript (1–10 MB) | timed `ci_last_interactive_epoch` |
| Live transcripts <24h / mean size | 95 / 0.99 MB (max 6.5 MB) | 4 project roots |

**Reading of the cost line:** the oracle is *fast* — so slowness is NOT the oracle's fault, and
"optimize the scan" is not the fix. The sweep is slow because of unbounded foreign work (R5), and it
is *stale* because the decision is a frozen batch snapshot. These are two different defects with two
different answers; conflating them is what produced the suspend-guard (a 900s heuristic patching a
symptom of the second defect using a detector for the first).

---

## §3 The architecture — attest, lease, enforce

```
WRITE SIDE (per session, ~2 ms, fail-open)      READ SIDE (per decision, ~5 ms, fail-CLOSED)
────────────────────────────────────────        ───────────────────────────────────────────
SessionStart   → beat kind=start  who=auto      cc-reaper sweep:
UserPromptSubmit → beat kind=prompt             ├─ bounded (timeout) foreign work, OUTSIDE
     who=operator|auto  ← predicate runs        │  the decision path
     ONCE, here, on the prompt in hand          ├─ classify (cheap: beats, not transcripts)
Stop           → beat kind=stop   who=auto      └─ per candidate, IMMEDIATELY before acting:
SessionEnd     → beat kind=end    (tombstone)      re-read beat → stamp decided_at → call
                                                   cc-teardown --decided-at <epoch>
        ↓                                                        ↓
  ~/.claude/cc-beats/<sid>.json                    cc-teardown ENFORCES:
  {sid,pane,pid,lstart,t,kind,who,seq}             now - decided_at > 60s        ⇒ REFUSE (stale)
                                                   beat shows operator presence  ⇒ REFUSE (adopted)
                                                   beat unreadable + system live ⇒ REFUSE (R3/R4)
```

**Who asserts what** (the verdict inversion):

| Claim | v1 owner | v2 owner |
|---|---|---|
| "an operator drove the last turn" | every closer, re-derived per sweep from the transcript | **the session itself**, once, at prompt time (beat `who`) |
| "this session is alive" | `kill -0` on a write-once registry pid (52% dead rows) | **beat recency + (pid,lstart)**, self-healing |
| "this decision is still valid" | *nobody* — implicit, unbounded | **cc-teardown**, via the 60s lease (R1) |
| "the evidence was unreadable" | skip the belt, proceed to close | **REFUSE + surface** (R3), gated by existence evidence (R4) |
| "the sweep is healthy" | unbounded, 3 foreign binaries inline | bounded (R5); foreign work moved off the decision path |

**Why the lease is the load-bearing move.** It is the only mechanism here that makes the DoD's 60s
number *structurally* true rather than statistically likely. Without it, every latency improvement is
a probability argument ("sweeps are usually fast"), and the p99 tail — where the 2026-07-24 incident
lives — stays open. With it, the tail is closed by refusal: the worst case of a slow sweep is that
**nothing is reaped**, which costs one interval and violates nothing.

---

## §4 Component specifications

### 4.1 Beat producer — `hooks/session-beat.sh` (new) + `hooks/session-register.sh`

Single script, invoked from `UserPromptSubmit` and `Stop`. Writes
`${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json` atomically (tmp+mv, the registry idiom).

Schema (frozen — consumers in §4.2/§4.3 read exactly this):
```json
{"sid":"…","pane":"…","pid":1234,"lstart":"…","t":1753800000,"kind":"start|prompt|stop|end",
 "who":"operator|auto","seq":12}
```

- `who` is decided **at write time** by the same predicate as `hooks/lib/cc-interactive.sh`
  (isMeta/auto-traffic/tool_result excluded; image-paste counts as presence). The predicate is
  *extracted*, not reimplemented — one definition, two call sites.
- Inherits `session-register.sh`'s fail-open contract verbatim (§R9): background worker, hard
  timeout, unconditional `exit 0`. **A beat failure must never cost a session.**
- `pane` keeps the existing `ITERM_SESSION_ID` derivation but **must not be the identity key** —
  `sid` is (R6; tmux panes share the server's ID).
- Kill switch: `CC_BEAT=off` ⇒ producer no-ops (read side then hits R4's existence gate and
  surfaces loudly rather than silently reaping or silently abstaining).

### 4.2 Beat reader + lease — `hooks/lib/cc-beat.sh` (new)

Pure reader, no writes; jq/bash only; empty + non-zero on any miss (the `cc-interactive.sh`
contract, so a sourcing hook under `set -u` degrades to "unknown", never an error).

- `cb_last_beat <sid>` → the beat JSON, or empty+1.
- `cb_operator_age <sid>` → seconds since the last `who=operator` beat, or empty+1 (unknown).
- `cb_system_live` → **the existence gate (R4)**: 0 iff the beat dir exists AND at least one beat
  younger than `CC_BEAT_LIVE_MAX_S` (default 900) exists. This is what separates "this session has
  no beat" (suspicious → refuse) from "nothing beats at all, the producer is not deployed"
  (a *detected system condition* → surface, do not silently refuse everything forever).

### 4.3 Decision freshness — `bin/cc-reaper` + `bin/cc-teardown`

**Reaper (proposer):**
1. Move the three foreign invocations (`cc-reconcile`, `cc-backlog`, `cc-inbox-guard`) **off the
   decision path** and bound each with absolute-path `timeout(1)` (R5). They ride the reaper's
   cadence; they must not sit between a decision and its actuation.
2. Immediately before calling `cc-teardown` for a candidate — after checkpoint, after
   `work_landed` — **re-take** the presence read from the beat (O(1)) and stamp
   `--decided-at "$(date +%s)"`.
3. Extend the fresh act-time presence leg from `coordination-abandoned` **to every reapable cause**
   (this is the direct fix for the 95%/76-of-80 finding). With beats it costs ~5 ms, so the reason
   it was only on one cause — expense — is gone.

**Teardown (actuator, the enforcement point):**
4. New `--decided-at <epoch>`. Refuse (`exit 2`) when `now - decided_at > CC_REAP_DECISION_MAX_STALE_S`
   (default 60). **Missing `--decided-at` from an autonomous caller is itself a refusal** — otherwise
   the lease is opt-in and therefore not a lease. (Interactive/operator callers are exempt via the
   existing `--force-adopted` shape; the exemption is explicit and logged.)
5. Close the three fail-opens at `:316/:321/:324`: lib absent, transcript unresolvable, or no
   interactive turn visible ⇒ **REFUSE + surface**, gated by `cb_system_live` (R3+R4).
6. Kill switches: `CC_REAP_LEASE=off` (disable the freshness lease),
   `CC_REAP_DECISION_MAX_STALE_S=<n>` (widen it), `CC_BEAT=off` (disable the producer).

### 4.4 Registry truth — `bin/cc-reconcile`

Prune rows whose (pid, lstart) is dead (R6/R7) — the measured 52% garbage. **Pruning a registry row
is not a close** and must never actuate one; it is bookkeeping. Add a beat-vs-registry join so a row
that is present but has never beaten is *surfaced* (the existing spawn-death detector, now cheap).

---

## §5 Failure-mode coverage (every observed mode → structural answer)

| Observed (v1) | v2 answer |
|---|---|
| Live operator conversation reaped 12–14 min after last prompt (2026-07-24, ×2) | presence read is fresh at act time for **every** cause + the 60s lease bounds decision→act |
| Presence evidence frozen in a batch snapshot; sweep runs 2,099s p99 | decision re-taken immediately before actuation; stale decisions REFUSED by the actuator |
| 95% of reaps ride causes with only a *static* marker as their act-time leg | fresh beat read extended to all reapable causes (cheap enough now) |
| Belt skipped when the who-lib is absent (`:316`) | REFUSE + surface (R3), gated by existence evidence (R4) |
| Belt falls through when transcript unresolvable (`:321`) | same — cannot-prove ⇒ refuse |
| Belt falls through when no interactive turn visible (`:324`) | same — absence ≠ proof of absence |
| Both presence belts unexercised (0 firings / 1,872 sweeps) | v2 makes the fresh read the **normal** path, not a rare backstop ⇒ exercised every candidate; a never-firing leg is detectable as inert |
| Sweep unbounded; 3 foreign binaries inline; `cc-inbox-guard` caused a 5-day blockage | R5 absolute-path `timeout(1)`; foreign work off the decision path |
| Sweep 16.5% longer than its own interval; max 15.5 h | bounds + foreign-work removal; and a slow sweep now reaps *nothing* instead of reaping stale |
| Suspend-guard (900s) patching stale idle after machine sleep | subsumed: the 60s lease refuses across any sleep by construction. Guard is KEPT as defence-in-depth (it is strictly narrowing, and belt-and-braces on a P0 is cheap) |
| Registry 52% dead rows; write-once, never refreshed | beats refresh continuously; reconcile prunes on (pid,lstart) |
| pid recycling masquerading as liveness | (pid, lstart) identity, already the reaper's `a17 S-4` pin — now the registry's too |
| tmux panes share `ITERM_SESSION_ID` ⇒ registry-row collision | `sid` is the identity key; pane is an attribute |
| Reaper is the cron carrier for 3 subsystems; 80% of its log is foreign noise | foreign work bounded + off the decision path; the reaper's log becomes about reaping |
| A "no beat at all" world silently inerts the reaper (the R3 trap) | `cb_system_live` existence gate + loud surface (R4) — absence is *detected*, never assumed |

---

## §6 Rejected alternatives (and why)

- **Shorten the launchd interval / lengthen the interactive hold.** Parameter motion inside the
  broken frame. The 2026-07-24 reaps happened *within* the hold window's intent — the hold was
  evaluated against stale evidence. A longer hold makes the reaper more inert without making any
  decision fresher; a shorter interval multiplies unbounded sweeps. Explicitly forbidden by R5's
  ancestor law (fail-closed must never amplify).
- **Make the sweep fast (optimize the transcript scan).** Measured: the oracle is 55–171 ms — it is
  not the bottleneck. Optimizing it would leave the batch-snapshot staleness untouched, which is the
  actual defect. Rejected on measurement, not on principle.
- **A real daemon holding in-memory session state.** Would give sub-second freshness, but adds a
  supervised long-lived process to a fleet whose observability problem is already "is the daemon
  inert?" — and loses the crash-safety of disk truth. The beat files ARE the state; the filesystem
  is the daemon.
- **Have the operator announce presence** (a "keep alive" command / touching a file). Violates the
  standing constraint: the operator never announces, and any design requiring it fails silently the
  first time they forget. Presence must ride traffic they already generate.
- **Kill the reaper entirely; close panes only by hand.** Would achieve zero live-conversation reaps
  trivially — and reintroduce the 13+ finished-worker pile-up that T-P3-4 was built to solve.
  Rejected: the DoD is zero *live* reaps, not zero reaps.
- **Put the freshness check in the reaper only** (caller-enforced lease). A lease the caller can skip
  is not a lease; the whole 2026-07-24 class is "a caller's belief was wrong". Enforcement must sit
  at the actuator, which is why `--decided-at` is *required* from autonomous callers (§4.3.4).
- **Reuse `cc-registry` rows as the beat** (add a `lastBeat` field). Rejected on a measured hazard:
  `session-register.sh:75-84` rewrites the row **wholesale** at SessionStart, which is exactly why
  `cc-fired` markers were put in their own dir (`bin/cc-reaper:141-144`). A beat living in that row
  would be clobbered by the next tenant. Separate dir, separate lifetime.

---

## §7 Acceptance criteria (disk-truth reads — which file proves each claim)

Each row names the exact read. Narration is not acceptance.

| # | Claim | Disk-truth read |
|---|---|---|
| A1 | Beats are produced by live sessions | `ls ~/.claude/cc-beats/*.json \| wc -l` > 0 **and** ≥1 file with `.t` within 900s of now |
| A2 | The interactive predicate agrees at write time and read time | for ≥3 live sids: `cb_operator_age <sid>` vs `ci_last_interactive_epoch <transcript>` agree within one turn |
| A3 | **A stale decision cannot reap** | `cc-teardown <pane> --decided-at $(( $(date +%s) - 120 ))` ⇒ exit 2, and `cc-teardown.log`/stderr names `stale-decision` |
| A4 | **A fresh decision is not blocked by the lease** | same call with `--decided-at $(date +%s)` ⇒ lease passes (reaches the next gate; NOT exit 2 for staleness) |
| A5 | An operator-present pane is refused | beat with `who=operator, t=now` ⇒ `cc-teardown` exit 2 `operator-adopted` |
| A6 | Absence refuses rather than skips | beat dir readable + system live + target beat removed ⇒ exit 2 (**not** a proceed) |
| A7 | R4 holds: a beat-less world is detected, not silently inert | `CC_BEAT=off` + no fresh beats ⇒ `cb_system_live` non-zero **and** a surfaced page/log line, not a silent refuse-all |
| A8 | Decision→act gap ≤ 60s in production | `cc-reaper.log`: every `reaped` line carries `decided_age=<n>` with n ≤ 60; zero `reaped` lines lacking the field |
| A9 | **Zero live-conversation reaps** | no `reaped` line whose sid has a `who=operator` beat within `INTERACTIVE_HOLD_S` of the reap; cross-checked against `cc-close-attrib` |
| A10 | The sweep is bounded | `grep -c 'timeout ' bin/cc-reaper` > 0 for every foreign invocation; sweep p99 in the log falls below the 300s interval |
| A11 | Registry garbage is reaped | dead-pid row fraction < 10% (was 52%) via the `kill -0` census in §2 |

**Accruing (time-dependent, named per the ground-up close protocol):** A8/A9/A11 are population
reads — they need production sweeps after landing to accrue. The read is specified here so a
successor can execute it without re-deriving anything.

---

## §8 Bootstrap & rollout

1. Land the beat producer + reader FIRST, with the read side **not yet enforcing** — beats accrue
   while nothing depends on them. (`CC_BEAT` defaults on; no behavior change.)
2. Verify A1/A2 from disk (beats exist and agree with the transcript oracle).
3. Land the lease + fail-closed belts. Kill switches: `CC_REAP_LEASE=off`,
   `CC_REAP_DECISION_MAX_STALE_S=<n>`, `CC_BEAT=off`.
4. Land the reaper bounds (R5) and the reconcile prune (R7).
5. Read A3–A7 as fixture proofs; A8–A11 accrue in production.

**Deploy note (inherited, not this rebuild's blocker):** the postland verifier has no GREEN stamp
(hung on `tests/lead-crash-close-panes.bats`, red on `tests/postland-verify.bats`), so deploy is
fail-closed — **landed is not deployed**. The live `~/.claude` symlinks the shared checkout, so
landed files on `main` do go live for symlinked paths, but **brand-new files are never linked by the
per-file symlink dirs** ([[deploy-lag-checkout-behind-origin]]). `hooks/session-beat.sh` and
`hooks/lib/cc-beat.sh` are brand-new ⇒ they need `bash install.sh` (or a `--auto` deploy advance) to
go live. This is named EARLY per Phase 5 and platters as one operator command at close.

## Learnings (accumulate; never delete)

- 2026-07-29: the incumbent's every safety fix was a new *leg* on the same stale snapshot. Six
  independent legs (fired-stamp, successor-alive, suspend-guard, §4.7 hold, teardown belt, identity
  pin) all read evidence frozen at sweep start, so each new leg reduced the *rate* of the failure
  without touching its *mechanism*. The measurement that exposed it: 88 of 168 teardown proposals
  refused by the actuator — when the last gate overturns the majority of upstream decisions, the
  upstream decision is not a decision, it is a suggestion.
