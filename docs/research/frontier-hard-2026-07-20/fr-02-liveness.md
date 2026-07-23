# AXIS 2 — Liveness & Causality Inference: as-wired state, escape classes, undecidable residue

_Frontier-discovery wave, 2026-07-20. Read-only investigation against the live fleet.
Prior corpus consumed (DELTA reported, not re-derived): `desk-audit-2026-07-18/{a18-liveness-attack,p03-idle-reap,p05-supervision,synthesis}.md`,
`FRONTIER_HOLES.md` (C-DSH-1 EXTENDED below), `desk-self-handoff-2026-07-19/panel-findings.md` (S1-S8),
`SESSION_AUTONOMY_RESEARCH.md` invariants 1/2/7._

## 1. System model as-of-today (post-delta, 144 commits since 2026-07-18)

**Signal sources** (the complete set any detector reads):

| Signal | Producer | Consumer | Failure property |
|---|---|---|---|
| `pid` + `kill -0` | OS | cc-classify:277, cc-board:97, supervisor:282 | authoritative for death; **silent on identity** (no lstart↔startedAt validation anywhere) |
| transcript last-*assistant*-ts | CC harness | cc-classify:69-74 | excludes `tool_result` (type=user) → "idle" ≠ "not working" |
| trailing unmatched `tool_use` | CC harness | cc-classify:113-132 (`tool_in_flight`) | **L-13 CLOSED** |
| `/tmp/cc-telemetry/<sid>.json` | `statusline.sh` (render-coupled) | supervisor:372, cc-board:76 | stops on non-render → false-stall by construction |
| `~/.claude/cc-registry/<pane>.json` | `session-register.sh` (one-shot, 3s kill) | cc-sessions:86-89 → cc-classify → cc-reaper | write-once; **additive-only healer** |
| git content-landed | git | cc-classify:242-262, reaper:143-157, supervisor:199-214 | **L-10 CLOSED** (cherry/patch-id + tree-diff) |
| `wait-contracts/*.json` OPEN | cc-wait | cc-classify:214-230 | **a17 S-3 CLOSED** |
| `cc-roles/desk` | handoff-fire (writer now exists) | classify:232-240, supervisor:104, reaper:119 | **L-7 addressing CLOSED** |
| `/tmp/cc-permission-pending/<sid>.json` | harness beacon hook | supervisor:337-367 | **new organ** — pierces S-3 for *permission* modals only |
| team `config.json` members | CC implicit-team | cc-classify:191-212 (`ps --agent-name`) | **L-4 still open** for in-process members |

**Inference chain:** `session-register` (+`cc-reconcile` backfill) → `cc-sessions` (dead-pid filter) → `cc-classify` (8-cause tree) → `cc-reaper` (re-verify + settle + checkpoint + `cc-teardown` identity-pin) ‖ `lead-supervisor` (telemetry sweep → page-only) ‖ `desk-invariant` (API-independent desk existence) ‖ `cc-board` (display join).

**Verified CLOSED since a18:** L-3 (self-scoped `handoff_fired` awk :102-110 + `startedAt/1000` :146), L-10, L-13, L-14-partial (`monthly spend limit|spend limit|billing` in :85), a17 S-3, SO-6 (`desk-invariant.sh` loaded, `com.claude.desk-invariant`), L-7-addressing. Daemons genuinely live: `com.chrisren.cc-reaper` (log fresh 07:39:40Z), `com.claude.lead-supervisor` (pid 20915), dispatcher, discovery, desk-invariant.

**Live fleet, measured 2026-07-20T07:41Z:** 26 live claude processes · 21 enumerated by cc-classify · 93 registry rows (74 dead-pid) · 91 telemetry rows (21 fresh, 70 stale ≥1h) · 174 standing pages · IDL 41 MB · supervisor `swept=90 findings=75`.

---

## 2. Frontier rows (ranked)

### F1 · Ground-truth predicates have no conformance test against the substrate they observe — and this one is wrong RIGHT NOW

**Evidence.** CC 2.1.183 ships its real binary as `.claude-183/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. The argv0 predicate — `t0!="claude" && t0 !~ /\/claude$/ && t0 !~ /cli\.js/` — is duplicated verbatim in **three** independent ground-truth scanners: `cc-reaper:131-138` (`live_pane_count`), `cc-reconcile:81-86` (`live_claude_pids`), `claude-accounts:171` (Python, `concurrency()`). Measured: **13 matched, 13 skipped**. Exactly half the fleet is invisible to all three.

Consequences, each verified:
- `self_check` (reaper:204-227) computes `delta = live − enum` = 13 − 21 = **−8**; `delta ≤ tol(0)` → prints *"reaper sees all live panes"*. The P0-12b blind-spot detector — whose sole purpose is to detect that the reaper is blind — **cannot fire on this machine, and asserts health instead.** The check is one-directional: `enum > live` (ghost rows) has no branch at all.
- `cc-reconcile` — the ad37447 healer for a18 L-2 — skips every `claude.exe` pane, so it **cannot backfill the exact 2.1.183 cohort it exists to heal.**
- Quota/placement routing undercounts concurrency ~50%.

The repo *already knows*: `smoke-test.sh:180` documents "2.1.114+ ships as a Bun SEA binary (`bin/claude.exe`)". The knowledge sits one directory from three scanners that never got it. And `tests/cc-reaper.bats:73` sets `CC_REAPER_PS_BIN` to a **mock ps** — the selftest is hermetic, so it stays green forever while production undercounts. This is the repo's own memory law *fixture-shape parity with the real producer* ("shape-mismatched fixtures stay green while live fails") recurring in the liveness ground-truth layer.

**Why default-tier insufficient.** Default tier adds `|| t0 ~ /claude\.exe$/` in three files and closes the ticket. The generator problem is: *a self-observing system whose substrate upgrades underneath it has no mechanism to revalidate its ground-truth predicates* — identical in shape to the already-filed C-DSH-2 (`/exit` queue-semantics per CC version), which means this is a **class**, not an instance. The frontier question is what the general primitive looks like: a substrate-conformance suite that runs against the *real* installed layout at every binary bump, covering argv0 form, transcript path mangling, team-config shape, env-var names.

**Solution shape.** One `cc-substrate-conform` gate: (a) single shared predicate module — no duplication; (b) asserts against live `ps`/real install, never a mock; (c) bidirectional delta (`|live − enum|`); (d) wired into `cc-version-audit` so a binary bump *fails* until re-certified. Generalizes C-DSH-2 from `/exit` to every substrate assumption.

**Confidence: HIGH** (directly measured, 3 call sites, exact counts).

---

### F2 · The taxonomy has no terminal state — every state is re-derived from immortal evidence, forever

Three absorbing sinks, all live:

1. **`active`-forever (a18 L-1, still open at cc-classify:291-292).** `IDLE<0 → CAUSE=active` — never-reap, never-surface. Worse, I verified the branch is reached by **two disjoint predicates**: `lat` empty (genuine never-engaged orphan) *and* `lat > NOW` where `NOW` is frozen at script start (cc-classify:36) across a 7 s `--all` run. The two live instances today (`7AAFEBC2`, `83B0ABD2`, `idle=-2`) are the **hottest sessions on the fleet** — turns 2 s before sampling — yet both emit `"no readable assistant timestamp — cannot prove idle (fail-safe)"`. The detail string is false. So the fail-safe's common case *trains any operator or desk reading `cc-classify --all` to dismiss that string as noise* — which is precisely how the genuine orphan escapes. Frozen-`NOW` also biases idle monotonically: sessions late in the iteration get up to 7 s smaller idle than sessions early.
2. **`DEAD`-page-forever (supervisor:282-288).** A dead pid whose cwd isn't provably landed → `checkpoint_preserve` + `page DEAD`, **every 30 s sweep**. Measured: **23,933 `checkpoint` IDL rows across 62 sids in 4.5 h** (~88/min) — each a real `teammate-checkpoint.sh` git invocation. 19 standing pages, all with live cwds. `reap_clean` is the only exit and it requires `work_landed`; nothing ever *acknowledges* a death.
3. **`rate-limited`-forever (a18 L-6).** Still absorbing; `resets` text still unextracted at :85.

**Why frontier.** The routine reading is "three separate bugs." The structural reading: the state taxonomy `{active, owned-wait, coordination-hang, rate-limited, handed-off-lead, finished-*, crashed}` is a **pure function of current evidence, recomputed each sweep, with no persisted lifecycle**. There is no `ACKNOWLEDGED`, `TOMBSTONED`, or `RESOLVED`. So any state whose evidence is immortal (a telemetry row nothing GCs, a transcript that will never gain a record) is emitted forever — and the resulting volume is itself the failure: 41 MB IDL, 174 pages, 75 findings/sweep. **A detector firing 75 times per sweep is not a detector.** Alarm-fatigue here is not operator weakness; it is a mechanical consequence of statelessness.

**Solution shape.** Make the classifier's output a *transition*, not a *level*: persist `{sid, cause, first_seen, last_seen, ack_state}`; page only on transition; require positive tombstoning (evidence retired) to leave a terminal cause. Pairs with F1's bidirectional delta — both are "the observer must model its own history."

**Confidence: HIGH** (all three verified in code + measured live).

---

### F3 · C-DSH-1 attestation inherits the failure domain it attests — and covers only one of two residue bands

**EXTENDING the ledger entry, not re-deriving.** C-DSH-1 proposes `{state: WATCHING|COORDINATING|FIRING, ts, DoD, lifecycle}`, claimed to dissolve ≥8 holes. Two specification gaps:

**(a) Shared fate.** A write-before-act record authored by the desk is only trustworthy while the desk is healthy. For the states we most need decided — stunned, rotted, hung, never-engaged — the writer is exactly the component that has failed. A stale `WATCHING` record is *worse* than no record: it converts "unknown" into a confident false negative. This is SO-6's shape one layer up (the panel already named the analogous tension: "the model-confirm layer degrades with exactly the rot that triggers it"). **Required delta: the attestation must be a LEASE, not a flag** — `{state, ts, ttl, monotone_seq}` where expiry is evaluated by the *reader*, an expired lease is `UNKNOWN` (never `WATCHING`), and `monotone_seq` must strictly increase or the record is void. Additionally the FIRING/lifecycle transitions must be stamped by the **hook** (an out-of-model actuator) rather than written by the model, so the record survives model incapacitation.

**(b) The residue splits into two bands; attestation reaches only one.**

- **Band A — needs write-before-act (attestation solves).** In-model intent with no tool call: decided-to-wait, decided-done, planned-multi-step-with-clean-tree-between-steps. Today undecidable; a lease-based attestation makes them decidable *at instrumented choke points*.
- **Band B — needs an emitter the system does not control (attestation cannot reach).** (i) *Will-this-tool-return*: `tool_in_flight` proves a tool is running; nothing distinguishes a 12-min build from an infinite hang. The permission-beacon closes only the permission-gate sub-case (a real win — memory records `git reset --hard` hanging at exactly that gate). (ii) *Composer contents* — unsubmitted operator text. (iii) *Queued-but-unprocessed harness notifications* (L-14): the lead cannot take the turn that would drain them and nothing external can read the queue. (iv) *Background `Task` subagents*: **verified — no durable spawn ledger exists** anywhere under `~/.claude/autonomy/`; a desk with an in-flight researcher is disk-identical to an idle desk. (v) *Modal dialogs other than PermissionRequest* (AskUserQuestion, plan-accept).

Band B requires **upstream harness hooks** (`SubagentStart`, tool-heartbeat, modal beacon generalized). No amount of local engineering closes it. The frontier contribution is naming this ceiling precisely so the campaign is scoped honestly: **C-DSH-1 dissolves Band A; Band B is a capability ceiling and should be filed as an upstream ask, not a build item.**

**Confidence: HIGH** on the taxonomy; **MEDIUM** on whether a lease fully repairs (a) — the lease-holder still self-reports state *content*, only freshness is externally checkable.

---

### F4 · The observer's universe, its freshness signal, and its garbage collector share one failure mode

`lead-supervisor.sweep()` iterates `for f in "$TEL_DIR"/*.json` — **the supervisor's entire universe is "sessions that have ever rendered."** Telemetry is written by `statusline.sh`, which emits only on render (documented: "a session inside ONE long operation, or genuinely hung, renders ZERO times"). And GC is `cc-context:80` (`-mmin +360` on provably-dead rows) — invoked *per render*.

So: universe membership, liveness proxy, and reclamation all collapse when rendering stops. A never-rendering session is not "stale" — it is **absent**, and absence is silent. cc-board's P8 registry×telemetry join (`:105-131`, DIED-UNRENDERED / NO-RENDER?) is the *only* organ that converts that absence into a row, and it is display-only with no consumer. Meanwhile the coupling shows in the data: 91 telemetry rows vs 26 live processes, oldest surviving row **28 h** against a nominal 6 h horizon.

**Why frontier.** The system has correctly identified shared-fate coupling twice before (SO-6; `desk-invariant` as the API-independent observer). Nobody has applied the same lens *one layer down*, to the substrate: the three mechanisms look independent in the architecture diagram and are one mechanism in practice. The general primitive is a **fate-partition audit**: for each detector, enumerate what it reads, who writes it, and under what condition the writer stops — then assert no detector shares a stop-condition with its own subject. `reaper-horizon-lint` is the existing proof-of-concept that such constraints *can* be mechanically gated; it just gates the wrong (temporal) axis only.

**Confidence: MEDIUM-HIGH** (coupling verified in code; the 28 h row is unexplained — see §4).

---

### F5 · Damping is tuned-by-incident over a non-identifiable estimator

**Is it principled?** Exactly one relation is derived *and* gated: `reaper-horizon-lint` — *no reaper's horizon may be shorter than the supervisor's sweep × 10* — a genuine sampling constraint (evidence lifetime vs observer period), enforced by grep-over-source, with the anti-drift rule that the constant may not be re-declared. That is real.

**Everything else is tuned.** `IDLE_S=300 · SETTLE_S=600 · STALL_S=1800 · DEADLINE_S=900 · COORD_HANG_DEAD_REAP_S=7200 · GRACE_S=120 · PERMPEND_NOTICE_S=120 · STALE_S=900 · QUIET_S=120-300`. Some carry implicit relations (`SETTLE = 2×IDLE`, `DEADLINE = STALL/2`) that are **nowhere declared or gated** — precisely the drift the horizon-lint exists to prevent, one axis over.

The STALL?↔OK flapping class received **four exemption predicates in four days**: `3ceca7c` warm-transcript exemption → `9dfe98d` sticky ESCALATED → `1c324d9fcc32` void-keeps-notify-marker → `4052d02` registered-desk exemption. The pattern is uniform: observe a flap, add a carve-out. That is not damping; it is enumerating the exception set by discovery.

**The structural claim:** the oscillation is not a tuning failure. The supervisor estimates a latent binary (working vs hung) from telemetry age, and the map from latent state to proxy is **not monotone** — a healthy long turn and a genuine hang both render zero times (stated explicitly at cc-board:11-16, "AGE CANNOT TELL THEM APART"). No threshold on a non-identifiable proxy can separate them, so exemption-patching converges to enumerating every legitimate zero-render case, one incident at a time. Escapes require either a *direct* observation (F3's lease), or an explicit hysteresis/dwell model with a **declared FP/FN cost ratio** — currently nowhere stated, which is why there is no principled place to put the constant.

**Confidence: HIGH** (commit archaeology + the code's own admission of non-identifiability).

---

## 3. NOT-frontier (routine — routing)

| Item | Evidence | Route |
|---|---|---|
| **🚨 `teammate-auto-shutdown.sh` is mode 644 — DISARMED** | Sole non-executable hook of ~25 in settings.json (all others 755); invoked as bare command path in **all 5** config dirs → execve EACCES. Mode flipped 100755→100644 at Jul 19 23:51, the exact mtime of `01-reap-guard-insert-activate.sh.done`. The reap-guard activation disarmed the reaper it was hardening. Emits nothing on failure → invisible to the abstention monitor (a hook that never runs logs zero rows, identical to "no teammates idled"). Also **uncommitted** (`git diff` +16 lines) — a `git checkout` silently reverts the L-9 fix. | **P0 → operator now.** `chmod 755` + commit. Then: the *class* (unguarded C10 manual-edit mutation surface) belongs to F1's conformance gate. |
| argv0 regex missing `claude.exe` ×3 | §F1 | backlog; 3-line fix — but land the F1 gate with it |
| cc-classify:291-292 branch split + frozen-`NOW` | §F2.1 | backlog: split `lat`-empty from `lat>NOW`; clamp negative idle to 0; recompute NOW per entry |
| cc-reconcile additive-only never corrects a stale row (a18 L-11b) | `:125` `[ -f ] → continue` — a dead-pid row permanently shadows backfill | backlog: overwrite when row-pid dead AND a live pane holds that ITERM_SESSION_ID |
| 1 registry row whose pid is `-zsh` | measured | backlog: validate `comm` in reconcile |
| cc-notify has no `--sid` mode (a18 L-5, rank 6) | grep: no sid resolution | backlog (unchanged verdict) |
| L-6 wake-at-reset | `lr-reset-poller.sh:191` parses `resets_at_utc`; `limit-reset-safety-gate.sh:11` says nothing schedules | backlog: wire poller→launchd |
| IDL page/checkpoint volume | `page()` writes IDL *before* the damping check (:89 vs :93) | backlog: damp IDL writes with the notify damping |
| L-4 in-process team members invisible to `ps --agent-name` | unchanged at :191-202 | backlog; note it lands in F3 Band B |

---

## 4. Could not determine

- **Why the oldest telemetry row is 28 h** against `cc-context:80`'s 6 h dead-pid horizon. Two candidates — its pid is alive (so not "provably DEAD"), or the render-coupled GC isn't running — not separated. Load-bearing for F4's severity.
- Whether `claude.exe` vs `claude` argv0 tracks launcher (`claude-nextN`) vs direct invocation; did not trace launcher scripts. Determines whether F1 is 50 % or drifts.
- Whether CC invokes hook commands via `execve` or a shell wrapper. Mode 644 + bare-path command fails under both `execve` and `sh -c`, but a harness special-case would change the verdict. **Did not execute the hook** (live fleet, read-only). Operator should confirm before treating the P0 as settled — though the mode anomaly is independently a defect.
- Whether the supervisor's 75 findings/sweep are all DEAD or a DEAD/STALL? mix at a single instant; measured from the IDL tail (9,660 DEAD : 418 STALL? : 415 ESCALATED over the window), not one sweep.
- Advisory-compliance quality vs `used_pct` — still unmeasured (panel's open item; unchanged).
