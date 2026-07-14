# SESSION_AUTONOMY — Research Convergence & Build Blueprint

**Status:** convergence of the Wave-2 design research (14 axes: 12 productive Opus workers a–m +
2 Fable adversarial j1/j2, all read-only), grounded in `docs/research/W0-W3_INTERVENTION_AUDIT.md`
(root causes R1–R6, detectors D1–D7). This doc is the blueprint the Agent-Teams build consumes and
the surface for the operator decisions in §5. Every primitive is cited to its axis + R#/D#.

---

## 0. Verdict (answer-first)

The autonomy layer is **buildable, and net-negative on quota+context by construction** — its
read/watch/poll machinery is entirely out-of-session (0 model quota), and its only quota-touching act
(injecting a turn) 1:1-replaces a human relay while preventing far larger context-rebuild and
re-run-wave wastes (axis m). But the two adversarial panelists (j1, j2) converge on one correction
that reshapes the build: **every naive primitive fails _silent/open_, and an autonomous actor keyed
off the audit's own catalog of mendacious signals (D1–D7) can _cause_ a W0-class incident**. So the
design law is **fail-loud, effect-verified, advisory-not-blocking, park-and-page by default** — and
the build order is **safe-docs-first → prove on W4 → runtime actors only to the extent the residual
justifies.** The productive axes independently satisfy this law (k's four-zeros audit, h's
one-shot-latched abstain-on-stale hook, b's bash-can't-close-a-live-pane split, m's 3 guards).

---

## 1. The converged architecture — 5 invariants (every axis obeys these)

1. **Verify the EFFECT, never the report/keystroke/spawn/config** (audit §7, restated by a, b, d, f,
   h, k independently). Concretely: dead-pid → DEAD even if telemetry looks fresh (a/P9); pane-gone
   asserted via `it2 session list`, not "shutdown_request sent" (D5); ack = a commit-sha in the
   branch, not a delivered `SendMessage` (f); the boundary number = payload `used_percentage`, never
   the statusline display offset (h; the §3b 2.3×-lie fix, `1b8d671`).
2. **Fail-loud / fail-abstain, never fail-silent-open** (j1's root pattern). Telemetry export is
   atomic (a/P1) and a stale/missing row on a *live* session is a LOUD fault, not silence (a/P3, j1
   #6); the boundary hook ABSTAINS on stale telemetry (h); the gate classifier defaults any doubt to
   STOP-ASK (c's asymmetric whitelist).
3. **Advisory, never blocking; boundary-gated, never mid-slot** (BUILD_LOG W2-rule-3; audit §4). No
   blocking Stop hook (banned). The boundary hook fires only at (a)∧(b)∧(c), one-shot-latched, and
   defers to `session-continue` when loose-ends are armed (h). "red-100% = warning not death" —
   fixtures-b2 ran >1h past it and completed.
4. **Plan-time schedule primary; runtime telemetry is advisory refinement** (j2's generator insight,
   realized by d+g). Lead burn is *predictable* (29→64→73% over a day) → succession is scheduled at
   plan time (`cc-wave-plan` placement + `context_budget` window-relative thresholds), and the
   boundary hook only *refines* the scheduled boundary — it does not carry the whole decision.
5. **The metric is paired and mechanical** (j2's Goodhart-bait fix, realized by k). Success =
   zero-unplanned-interventions **AND** zero-autonomy-caused-incidents, re-derived as k's **four
   independent zeros** (unplanned=0, signal-divergence=0, orphaned-intent=0, missed-fire=0) — never a
   bare count a silently-mis-recovering supervisor could game.

---

## 2. Central design decisions (resolving the adversarial tensions)

| # | Decision | Rationale (axis) |
|---|---|---|
| D-A | **Build order: docs-first.** Wave A = telemetry-v2 (a) + plan-template §8 (e) + gate-batching (c) + auditability floor (k P1/P2/P6) + E2E harness (i) — all near-zero new failure surface. Then **run doc_classifier W4 on them** as the free experiment. Wave B (boundary hook h) and Wave C (supervisor b) build only to the extent W4's residual justifies. | j2 (invert order; W4 is the experiment), matches PLAN spawn-wave W-a/W-b/W-c |
| D-B | **Default = park-at-boundary-and-page; auto-ACT only on effect-verified DEAD panes.** The supervisor is bash → it *cannot* call in-session tools, so it physically cannot improvise a close on a live pane (b). Live panes get DELEGATED advice via `cc-notify` (their own model executes the rail); only dead panes get DIRECT shell rails. | b (DIRECT/DELEGATED split), j2 (never auto-recover) |
| D-C | **Boundary-hook injection lands on the PROVEN `decision:block`+one-shot-latch fallback; `additionalContext` is probe-gated.** The advisory-vs-block distinction the plan assumed is source-contradicted on 2.1.207 — verify before relying (h/B1). The latch (keyed on configdir\|cwd + HEAD-sha) is what makes block advisory-not-looping. | h, m (guard #1) |
| D-D | **Supervisor = launchd `KeepAlive` daemon (5–10min sweep) + the existing 30s crash daemon; NEVER a standing Claude session.** launchd terminates the who-watches-the-watcher regress (RunAtLoad+KeepAlive); a standing session burns ~144 turns/day and recursively needs its own handoff. | b, m (cadence table) |
| D-E | **Teardown reconciliation: in-session lead teardown = `TaskStop` (the fire's rule, a harness tool the lead has); out-of-session supervisor teardown = `it2 session close` + confirm-gone.** `TaskStop` has no shell entrypoint, so the supervisor uses the proven `close_pane` and VERIFIES the pane is gone (D5). Both honor "teardown ≠ shutdown_request" (decorative). | f, b, D5 |
| D-F | **Widen the auto-compaction margin at the source**: the autonomy launcher profile sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`; the boundary hook fires at T≤73%. Never disable auto-compact (survival backstop). | h (Q3), j1 #1 |
| D-G | **The 3 ironic-failure guards are non-negotiable** (else the layer flips net-positive cost): one-shot latch (boundary), effect-verified debounce (supervisor false-positive), timeout-no-wake (`cc-await-ping`). | m |

---

## 3. Per-primitive build spec (organized by roster; cross-referenced)

### 3.1 `telemetry-v2` (axis a; owner: statusline.sh + bin/cc-context + new bin/cc-board)
- **P1 atomic export** — replace `>` truncate at `statusline.sh:56` with `.tmp`+`rename(2)` (pattern from `session-register.sh:57-62`); tmp inside `$TDIR`. Closes R1/R3, fixes j1 #6.
- **P2 sid-once guard** — compute `sid` once; empty → skip write (no `unknown.json` cross-corruption).
- **P3 stale-sweep on read** — `find -mmin +15` sweep in cc-context/cc-board, **exclude own sid**; hardened variant marks-stale-for-display + deletes only at long horizon OR `kill -0 <pid>` (avoids the fixtures-b2 long-turn false-negative).
- **P4 `cc-context --me`** — `sid=$CLAUDE_CODE_SESSION_ID` (EMPIRICAL: == telemetry filename on 2.1.207), fallback cwd-heuristic; gate on `[ -z "$CLAUDE_CODE_CHILD_SESSION" ]` (subagent var = parent id). Add `CC_TELEMETRY_DIR` override for E2E.
- **P5 export `config_dir`** — the telemetry→accounts join key, already computed at `statusline.sh:145-147`; ~zero cost.
- **P6 `cc-context --me --quota`** — fused read: config_dir→acct via accounts.json → `claude-accounts --json` (CACHE mode, 90s single-flight — never `--fresh`) → one line `ctx% · 5h% · wk% · fable% (↻h) · quota≤90s`. Answers "stay or go?" with no human relay.
- **P7 `bin/cc-board`** — operator all-sessions board (one glance replaces the 10 §1 relays). Spine = telemetry files; enrich with cached quota + rank footer. `watch -n5 cc-board`. Ships value telemetry-only; upgrades with P8.
- **P8 wire `session-register.sh` + carry `session_id`** — the registry is EMPTY today (only worktree-scoped `live-session-registry.sh` is wired); add `session_id` to the entry + wire on SessionStart (`settings.json`). Gives board name+pid-liveness+paneUUID. Closes R6/D4.
- **P9 stall-state column** — DEAD(`kill -0` fail)/STALE(mtime>15m,pid alive)/HANDOFF-DUE/LIMIT-RISK/OK; **effect-verified** (dead-pid→DEAD even if telemetry fresh). Display-only; action = supervisor.

### 3.2 `boundary-hook` (axis h; owner: new hooks/boundary-handoff.sh)
- Self-resolve via Stop-stdin `.session_id` → read own telemetry. Conditions **(a)** clean tree ∧ `.git/gate-green==HEAD` ∧ no-live-teammates · **(b)** BUILD_LOG-head (or plan status-head)==`git HEAD`, repo resolved via `--git-common-dir` · **(c)** `used_pct≥T` (≤73), **abstain if ts age>180s**.
- **One-shot latch** keyed `hash(configdir|cwd)-<HEADsha>` (mirrors `session-continue.sh:30-34`). **Compose-guard**: no-op if `session-continue` sentinel armed. Explicit Stop-array ordering.
- **Injection**: PRIMARY `additionalContext` **probe-gated**; FALLBACK proven `{decision:"block",reason}` + latch + `systemMessage` for human visibility. (D-C)
- **Build deps**: B2 `.git/gate-green=<sha>` marker (new /ship + commit step — doesn't exist); B3 stale-sweep (axis a owns); B1 additionalContext probe.

### 3.3 `supervisor` (axis b; owner: new scripts/lead-supervisor.sh + launchd plist)
- **Topology C**: launchd `KeepAlive`+`RunAtLoad` daemon, `while :; sweep; sleep 30`; **reuses** `lead-crash-watchdog.sh`'s registrar half (strip its per-session detached loop to registrar-only). Backstop tier = existing `team-orphan-reaper` 600s. Mutual re-bootstrap (every SessionStart re-arms the daemon; daemon re-arms sessions) closes the LaunchAgent-booted-out hole.
- **Recovery decision table** (each state → DIRECT-shell-on-dead / DELEGATED-inject-into-live): DEAD→checkpoint-then-respawn-from `refs/wip/LAST`; STALL→`cc-notify` advice (never force-close live); LIMIT-predicted→delegate; LIMIT-actual→respawn DIFFERENT account; MODAL-teammate→auto-deny (extend team-orphan-reaper); **MODAL-lead→PAGE** (§5 operator ruling).
- **Crash-path checkpoint gate** (the real gap): the graceful path checkpoints-before-remove; the crash path (`team-orphan-reaper archive`) does NOT — add `teammate-checkpoint.sh` on DEAD-lead per member worktree BEFORE any archive/remove (closes D1/D3).
- Detection LOGIC lives in axis h (D1–D7); b maps state→recovery only. Reboot ⟹ hand to `resume-sessions` skill, not respawn-loop.

### 3.4 `gate-batching` (axis c; owner: new scripts/gate-*.sh + template §8)
- **Asymmetric whitelist** (any doubt → STOP-ASK; false-negative catastrophic). 9 ruling classes C1–C9; pre-signable {C1–C5,C7}; conditional {C6 money-path=out-of-class-by-default, C8 go=couples axis d}; **C9 `/ship` = permanent exclusion + backstop**.
- **5-gate discriminator**: `G-cite` (grep BUILD_LOG citation — catches born-at-exit) + `G-shape` (model: accept/reject not choose-among) + `G-reversible` (model+tag) + `G-surface` (grep `GPL|license|money|schema|auth|migration|DROP|timeout` — catches escalation) + `G-manifest` (class∈manifest ∧ wave-id current). **G-cite/G-surface are un-fakeable greps.**
- **P1 registry** (docs) → **P2 wave-start manifest** (`scripts/gate-manifest.sh`, wave-id+expiry) → **P3 classifier** (`scripts/gate-classify.sh`, mirrors handoff-disposition split) → **P4 auto-stamp** (`Ratified-By: operator (pre-signed class Cn, manifest…)` trailer — the ledger j1 #7 demanded) → **P5 batched out-of-class gate** (ONE 6-slot message from 31bcd087) → **P6 /ship backstop** (`git log --grep 'pre-signed class' <last-ship>..HEAD` for veto) → **P7 per-wave expiry** (stale W3 manifest at W4 → all out-of-class).

### 3.5 `comms-hardening` (axis f; owner: new scripts/team-ruling.sh, merge-gate, team-teardown)
- **The reliable downward channel already exists, unused for lead↔teammate**: `cc-notify` submit-verified injection targets any pane by raw UUID = teammate `tmuxPaneId`. Both shipping recovery paths (crash-watchdog shutdown_request + orphan-reaper permission_response) write the DECORATIVE inbox → **reroute both onto cc-notify-to-pane**.
- **Two-tier: NOTIFY (best-effort cc-notify) vs BIND (durable ruling file + commit-trailer `Acked-Ruling:<id>` + fail-closed merge gate)** — absence-of-ack IS the delivery-failure detector. **Respawn-at-boundary over mid-stream correction** (auto-compaction wipes composer; briefs survive as files).
- Extend `handoff-disposition.sh --teammates` (lead's R-PING mechanical); TEAM-PING recipe in brief template; **mailbox GC** (new — unbounded today). Teardown = `it2 session close`+confirm-gone (D-E).

### 3.6 `auditability` (axis k; owner: new bin/cc-idl, cc-truth, cc-audit)
- Three lie-classes: **T1 signal-lie** (freeze reported+truth at decision time), **T2 ledger-lie** (independent-observer + tamper-evident chain + transcript reconciliation), **T3 should-have-fired** (coverage check over telemetry series, not decisions-taken).
- **P1 hash-chained IDL** at FIXED `$HOME/.claude/autonomy/idl.jsonl` (cross-account; `git hash-object` chain → tamper-EVIDENT) · **P2 dual-snapshot** (reported `used_pct` vs truth=transcript usage-sum, the `1b8d671` recipe; δ>5pt alarm) · **P3 supervisor independent-observer** (intent w/o matching effect = papering-over) · **P4 completeness** (greppable `[AUTONOMY:kind:sha8]` marker in the immutable transcript → omission detectable) · **P5 should-have-fired** (replay series vs boundary predicate) · **P6 durable series** (+ PreCompact snapshot) · **P7 `cc-audit --wave`** = the FOUR ZEROS (§1 invariant 5) · **P8 designed-gate classification** · **P9 `cc-idl --replay`** (one-command re-derive any decision from raw sources) · **P10 E2E for the guard itself**.

### 3.7 `quota-scheduling` (axis d; owner: new bin/cc-wave-plan)
- Static one-shot planner: wave DAG × `claude-accounts --json` → **greedy-decrement placement** (rank via score, assign argmax, decrement projected headroom — fixes the 90s-blindspot that piles a wave on one account), ≤2/account cap. **Fable window-straddle guard** (front-load early; else downgrade→opus-4-8; else BLOCKER — window closes 2026-07-15T00:00Z). **Infeasibility ladder** (relax CAP→serialize→BLOCKER+earliest-feasible-start). **3-signal limit-predict** (percent-not-tokens → advisory: S1 structural, S2 5h-survival, S3 burn-extrap; needs one-line `prev` patch to `claude-accounts --json`). Output = plan JSON + ready `handoff-fire.sh` lines + `fallback[]` for axis l. **LIVE: next3 weekly+fable-exhausted → only 3/4 routable.**

### 3.8 `runtime-contention` (axis l; owner: mostly EXISTS + small additions)
- **Already solved** (do not rebuild): concurrent-land (`land-lock.sh` + content-verify + `stranded-sweep`), succession legibility, worktree-remove guard. **Add**: A1 land×succession mutual-exclusion (self-close defers on held land-lock); A2 locked-pipeline auto-retry (non-ff push → bounded re-rebase, cap 3); **A3 shared-checkout commit guard** (PreToolUse-Bash hook blocks git commit/push in `~/Development/claude-infrastructure` — machine-enforce the prose rule; dfacccd root); B1 successor-pane exclusive claim (`mkdir /tmp/succession-claim-<S>`); C2 parallel worktree-add mutex; D1 account-slot lease (route-time claim, the 90s-cache TOCTOU) + D2 lease heartbeat+succession-transfer. **Blocker**: `worktree-pool.sh` is ABSENT here (the "warm pool" claim in handoff.md is reso-borrowed) — cold `git worktree add` is the live path.

### 3.9 `context-budget-discipline` (axis g; docs into template §8)
- **Telemetry-first, never transcript-estimate** (thinking=0 bytes persisted but live-counted; B8). **Window-relative threshold** (never fixed tokens — same 47% → opposite verdict 200K vs 1M). **On 1M the binding constraint shifts fill→ROT** → a rot detector (re-read counter, fill-independent; ledger-reread excepted). `context_budget:` plan field (`start_clean≤25/mid_soft 50/boundary_recycle 60/hard_handoff 75`). **Delegate implementation off the lead** (5818bac0 did 31 Write+22 Edit+214 Bash = 704KB — contradicts "lead lands glue"). Relay-byte budget (structured manifests, not prose).

### 3.10 `e2e-harness` (axis i; owner: new scripts/*-e2e.sh + autonomy-e2e.sh)
- 4 reuse patterns already in-repo: **P1** live-pane+fake-binary+assert-effect (`handoff-selfclose-e2e.sh`; **symlink** the platform binary, never copy — macOS AMFI; NOT CI-able, needs `$ITERM_SESSION_ID`); **P2** sandbox-HOME+synthetic-stdin (`test-overwrite-guard.sh`; CI-safe); **P3** fixture-corpus+assert-invariants (`plan-phase-scan-tests`; CI-safe); **P4** verify-before-promote firewall (`smoke-test.sh`).
- **Every primitive needs a NEGATIVE/anti-trigger fixture** — both marquee rescues (§3b, §3c) were OVER-firing; "a suite that only proves firing would have passed the 2.3×-gauge build." Umbrella `scripts/autonomy-e2e.sh` (P4); CI runs P2/P3, P1 pane suites **SKIP-loud** on headless. Wire as pre-commit/pre-`/ship` gate → regressions self-announce.

### 3.11 `plan-template §8` (axis e; owner: template-author → docs/proposals/)
**Structural finding:** `doc_classifier/docs/specs/C00-orchestration.md` runs §0–§7 and STOPS — every one
of §1–§7 is the **teammate** layer. "§8" is literally the next integer: the first section describing
the **lead/session** layer above teammates. R4 = "the spec ends where the session layer begins."
**§8 ≠ Phase 0** (Phase 0 = generic teammate orchestration; §8 = the 5 improvised-every-wave session
concerns). Today the whole session layer is one unstructured status string (`"W4 lead, Fable @ xhigh,
account next"`).
**9 elements** (each closes R4; each validated by *effect*, not config):
- **E1 lead-session placement** — account/launcher/model/effort as a structured row; validated by `ps -eo command | grep -- --effort/--model` (config file lies, D2).
- **E2 context budget + succession trigger** — the numeric `used_percentage` threshold this lead hands off at; §8 *declares* it, the boundary hook (h) *consumes* it.
- **E3 write-fence inter-wave handoff** — wave N+1 holds a write-fence (no worktree/spawn/integration-write) until `git merge-base --is-ancestor <priorStampSha> integration`. Prevents teammates branching off a pre-ratification base.
- **E4 placement-plan consumption** — a producer(d)→consumer(§8) data contract `{account,launcher,model,effort,cap≤2,window-expiry-ts}` + a staleness/recompute predicate (never live re-rank per spawn).
- **E5 back-channel topology** — the ping graph + ARM state (teammate→lead mailbox pull-verified; lead→orchestrator `cc-notify`+R-PING; orchestrator→lead countermand).
- **E6 gate-batching manifest** — the pre-signed ruling-class slot (references c).
- **E7 lead-session isolation** — each concurrent LEAD (wave-lead, orchestrator, overlapping successor) on its OWN worktree/branch — not just teammates (confirms l/A3).
- **E8 session-spawn-readiness checklist** — the session-layer analog of C00 §7 (`scripts/session-spawn-readiness.sh`): E3 fence cleared · E4 placement fresh · E2 threshold declared · E5 UUIDs registered · E6 manifest signed · E7 worktree isolated → a missing box HALTS the wave cut.
- **E9 telemetry binding + self-cost** — the `cc-context × claude-accounts` join (a) + the layer's own footprint ceiling (m).

**Deliverables (docs/proposals/, NEVER doc_classifier):** `C00-SECTION-8-TEMPLATE.md` (blank E1–E9 + the E8 checklist) + `W4-W5-SESSION-ORCHESTRATION.md` (filled: W4 = next/Fable@xhigh, succession ≥60% at green boundary, `spawn base 3bb2e08` write-fence, 10 teammates→W4-lead→orchestrator `99261468` R-PING; W5 = maybe Opus@max if the Fable window closed, single lead). **Index per-wave with a succession sub-row** (a lead spans waves; a wave spans leads — keep both).

---

## 4. Revised Phase 0 (build order & team shape) — supersedes the plan's roster shape

**Wave A (safe, docs + near-zero-failure-surface; build + prove on W4 first):**
- `telemetry-v2` (a) — statusline atomic export + config_dir + cc-context --me/--quota + cc-board + wire session-register. Single-owner: `statusline.sh`, `bin/cc-context`, new `bin/cc-board`, `hooks/session-register.sh`.
- `gate-batching` (c) — the whitelist + manifest + classifier + auto-stamp + /ship backstop. Single-owner: `scripts/gate-*.sh`, `commands/ship.md` extension.
- `template+budget` (e+g) — §8 template + context_budget discipline → `docs/proposals/`. Docs-only.
- `auditability-floor` (k P1/P2/P6) — IDL + dual-snapshot + durable series (the load-bearing floor; without it the days-later audit has nothing honest to read).
- `e2e-harness` (i) — the per-primitive harness + umbrella gate; consumes each primitive as it lands.

**Wave B (runtime refinement, after Wave A + a W4 residual read):**
- `boundary-hook` (h) — depends on telemetry-v2 (a) + the `.git/gate-green` marker. Probe additionalContext; land the block+latch fallback.
- `quota-scheduling` (d) — `cc-wave-plan` + the `prev` one-line patch. Feeds the template.

**Wave C (the riskiest, smallest scope justified by residual):**
- `supervisor` (b) — launchd daemon + recovery table + crash-path checkpoint. Consumes h's detectors + k's independent-observer.
- `runtime-contention` additions (l) — A3 guard first (protects everyone), then leases.

**Dependency spine:** telemetry-v2 → boundary-hook → supervisor (detectors consume telemetry); gate-batching + template + auditability-floor + e2e run parallel to Wave A; comms-hardening (f) slots with supervisor (reroutes its recovery channel). Worktrees per-member off this branch; single-owner-per-file (§3). Teammate teardown = `TaskStop`.

---

## 5. Operator decisions required (genuine rulings — the batched gate for THIS track)

1. **DoD framing** — is the target literally "zero human intervention for days," or j2's reframe
   "**batched, legible, park-until-gate**" (the operator already batches — "RATIFY ALL 7")? This
   changes whether the supervisor auto-recovers or only pages. **Recommendation: park-and-page +
   auto-recover only effect-verified DEAD panes**; measure with k's four zeros.
2. **MODAL-blocked lead** — the one residual non-zero-touch case (a live-but-modal-blocked lead has
   no sanctioned rail). **Recommendation: PAGE for unknown modals; auto-dismiss only the known-safe
   "resume from summary" prompt.** (b/blocker 1)
3. **C6 money-path two-person sign-off** — keep out-of-class (never pre-signable)? **Recommendation:
   yes** — data-integrity surface. (c/adversarial b)
4. **Build order** — approve docs-first (Wave A) + prove-on-W4 before building the supervisor? (D-A)
5. **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`** on the autonomy launcher profile — approve? (D-F)

## 6. Risk register (j1's ranked failure list → mitigation, all now owned)

| # | Failure | Mitigation | Owner axis |
|---|---|---|---|
| 1 | Auto-compaction beats the boundary hook (mid-turn, below boundary) | T≤73 margin + `AUTOCOMPACT_PCT_OVERRIDE=90`; supervisor pages at compact-threshold−margin regardless of boundary | h, b |
| 2 | Reboot/iTerm2 restart → data loss (worktrees at /tmp) + supervisor dead | worktrees OUT of /tmp; launchd `RunAtLoad`; reboot→`resume-sessions` | l, b |
| 3 | CC bump silently breaks fire/telemetry mechanics | E2E harness as MANIFEST-promotion gate (i); additionalContext probe (h) | i, h |
| 4 | API-incident storm → respawn-loop into the outage | circuit breaker: ≥2 accounts erroring → PARK + single poller | b, d |
| 5 | Account logout mid-wave (next3 ALREADY exhausted → 3/4) | pre-wave auth+routability gate; logout = designed-gate page | d |
| 6 | Telemetry silent-open (`\|\| true`, non-atomic, stale-as-live) | atomic export + stale-as-loud-fault + effect-verified liveness | a |
| 7 | Gate-batching silently absorbs out-of-class | auto-stamp trailer ledger + /ship retro-review + wave-expiry | c, k |

## 7. Empirical-resolve-at-build blockers (verify before trusting either doc)

- **B1** additionalContext-on-Stop on 2.1.207 — probe; land block+latch fallback until green. (h)
- **B2** no `.git/gate-green=<sha>` marker exists — add to commit/`/ship`. (h)
- **D2** per-member effort INERT vs settable — `ps -eo command \| grep -- --agent-name` on the FIRST build spawn is the arbiter, regardless of doc. Set LEAD effort correctly meanwhile. (audit D2; h/b/d/g/i/m all flag it)
- **team_name** required despite "deprecated" — always pass `session-<id>`; assert pre-spawn. (D7)
- **CLAUDE_CODE_SESSION_ID** == telemetry filename verified on 2.1.207; verify 2.1.114/2.1.183; P4 degrades to cwd-heuristic if absent. (a)
- **next3** logged-out/exhausted NOW — the "4 accounts" premise is already false; account-lease + pre-wave gate assume 3/4. (d, j1 #5)

---

_Provenance: 14-axis Wave-2 (a15d216 a · ad6e917 b · ab1486d c · a97a1ca d · aeee248 e[pending] ·
a20b151 f · a30eda6 g · a4534c4 h · adc3414 i · a8e98ed j1 · a175b5e j2 · aba397f k · a6381e9 l ·
a1e8697 m). Decomposition critic-revised 11→14 (ae984bf). All read-only; findings cited to R#/D# +
file:line in the source transcripts._
