# FR-11 — Context Economy & Knowledge Continuity (frontier-hard axis, 2026-07-20)

READ-ONLY audit. Every claim below is a live read (file:line, disk measurement, or transcript scan)
taken 2026-07-20. Delta-mandate honored: extends `desk-audit-2026-07-18/p16-continuity.md`
(which is *physical* continuity — power/reboot/network — a disjoint axis from this one),
a19 D-9..D-12, and FRONTIER_HOLES C-DSH-1/2.

---

## 1. The fuel + continuity model as-of-today

### 1.1 Threshold ladder — who enforces what

| Fill | Name | Enforcer | Event | Live status (measured) |
|---|---|---|---|---|
| 25% | `ROT_FLOOR` (`waiting-recycle.sh:96`) | waiting-recycle | PostToolUse:Bash | active only as a floor on behavioral rot-tells |
| 55% | `CC_WR_T` (`waiting-recycle.sh:95`) | waiting-recycle (in-session, desk-only, arm-gated) | PostToolUse:Bash | **DORMANT** — 230/230 recent IDL evals `abstained not-armed` |
| 73% | `CC_BOUNDARY_T` (`boundary-handoff.sh:54`) | boundary-handoff (advisory `decision:block`, latched) | **Stop** | wired on all 4 config dirs; healthy-dormant (1 eval `below-threshold:25<73`) |
| 73% | `CC_SUP_T` (`lead-supervisor.sh:37`) | lead-supervisor (out-of-session daemon) | 5–10 min sweep | **PAGES only** — RULING #1 (`lead-supervisor.sh:4`); cannot drive a live pane |
| ~80% | two-tier inversion point (`panel-findings.md:61-67`) | — | — | **NOT IMPLEMENTED** — no `80`, no hard/soft-zone branch anywhere in `waiting-recycle.sh` |
| 90% | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` design law D-F (`SESSION_AUTONOMY_RESEARCH.md:138`) | launcher profile | harness-internal | **NOT SET** — the `claude-next` shell function exports only `DISABLE_AUTOUPDATER` / `CLAUDE_CONFIG_DIR` / `CLAUDE_CODE_TASK_LIST_ID`; zero `AUTOCOMPACT` refs outside docs |

### 1.2 Do they compose? — **In design yes; in fact no.**

As a *ladder* the design is coherent: 55 (in-session, cheap, reversible) < 73 (advisory at a clean
Stop) < 80 (inversion: prefer imperfect recycle) < 90 (survival backstop). Margins are deliberate and
D-F/D-G reason about them explicitly.

In *operation* the ladder is a paper artifact:

- **Three of six rungs are inert**: 55 dormant (not-armed), 80 never built, 90 never set.
- **The two live rungs (73×2) read a gauge that is blind for ~half of live sessions** (§1.3).
- The one rung that genuinely fires — the harness's own auto-compact — is the only one *not*
  downstream of that gauge, which is precisely why cc-board observes deaths at 76/86/97% with no
  intervening advisory. The deaths are not a policy failure; they are a **measurement** failure.

### 1.3 The gauge is turn-boundary-coupled (the load-bearing defect)

`~/.claude/statusline.sh:58` is the **sole** writer of `/tmp/cc-telemetry/<sid>.json`
(`settings.json` `.statusLine.command`; `bin/cc-context:29` — "statusline exports on each turn
boundary"). Both fuel hooks read it and abstain when stale (`AGE_MAX=180s`,
`boundary-handoff.sh:99`, `waiting-recycle.sh:97`).

Measured now — 36 telemetry rows, **5 fresh / 31 stale**; splitting stale by pid liveness:

- **14 LIVE sessions with stale telemetry** (16 are dead-session litter).
- Worst offenders: pid 74316 @ **44% fill, 1168 min (19.5 h) stale**; pid 44245 @ **46%, 1484 min
  (24.7 h)**; pid 80761 @ 22%, 1705 min (28.4 h).

A session in a long turn (Agent-Team lead awaiting teammates, deep-research subagent, long build)
never reaches a turn boundary → no statusline render → the gauge **freezes**. This is the exact
`trigger == failure` shape `boundary-handoff.sh:9-12` (B-1) names for the Stop event, now measured on
the telemetry producer itself: **the fuel gauge stops updating precisely during the turns that burn
the most fuel.** Those 14 sessions will `abstain "stale-telemetry"` at every hook, permanently, and
ride to auto-compact with zero advisory, zero recycle, zero DoD capture.

### 1.4 What crosses a boundary today (succession state)

| State | Carrier | Status |
|---|---|---|
| Frozen DoD | `dod-persist.sh` SessionStart re-inject (`:108-117`) + PreCompact capture (`:118-138`); wired **all 4 config dirs** (SessionStart + PreCompact) | closes a19 D-12 *architecturally*; see §2 FR-2 for the empirical result |
| DoD → recycle successor | `waiting-recycle.sh:434` `dod-persist get` → Stage-2 brief | deterministic (good) — but `get` = `last_recorded_scope` = `Scope (frozen):` **only**; grown lines excluded |
| Hard constraints (3-6) | `handoff.md:68` — "the one deliberate duplication" | intact |
| Re-derivable watch state | `waiting-recycle.sh:452-455` explicit "FIRST ACTION — re-derive from DISK" directive | intact and correct |
| `/goal` over-cap | `check_goal_length` (`handoff-fire.sh:461-476`, wired `:1060`) | **a19 D-11 CLOSED** |
| Decision state ("why we ruled X") | — | **no carrier** |
| Learned-this-session facts contradicting disk | — | **no carrier** |
| Successor comprehension | `verify_engagement` (`handoff-fire.sh:356-405`) | verifies **delivery**, not possession |

**Minimum sufficient brief — principled split.** *Must cross* (not re-derivable): frozen DoD +
authorized growth; decision state and its rationale; learned-this-session facts that contradict what
disk says; in-flight roster **with intent**. *Re-derivable*: watch state (`cc-board`), owned waits
(`~/.claude/wait-contracts`), git/worktree/merge state, backlog claims, quota.

Today's bridge sits **above** the minimum on re-derivable state (the explicit re-derive directive is
better than copying) and **below** it on the two rows with no carrier. The bridge is a *pointer*
protocol that assumes disk is authoritative; the residue that never reached disk — why a decision was
made, which signals are known-false-positives — has no home at all. That is the structural source of
post-handoff scope-amnesia, not the DoD leg (which is now carried).

---

## 2. Ranked frontier rows

### FR-11-1 — Succession has a delivery receipt, never a possession proof
| | |
|---|---|
| **Problem** | Nothing can establish that a successor *possesses* the mission before the predecessor is destroyed. |
| **Evidence** | `verify_engagement`/`engagement_seen` (`handoff-fire.sh:356-405`) confirm a marker string appears in the successor's transcript — receipt/liveness only. a19 **D-10** shows the obvious fix is already known-broken: `/goal`'s evaluator is Haiku-tier and **tool-blind**, judging the working model's own claims, so a self-asserted "I have the mission" passes ("blind-tier fox reads the wolf's report"). Repo-wide grep: no attest/quiz/restate-DoD mechanism exists. |
| **Why default-tier insufficient** | The two natural designs are each structurally foreclosed: an **in-band** verifier is a model reading the successor's claims (D-10 shape); an **out-of-band** verifier (bash) cannot judge semantic comprehension. Worse, `--recycle` is exit+relaunch **in the same pane** — there is no predecessor/successor overlap window in which a proof could be demanded. Escaping needs a mechanically-checkable possession predicate *plus* a re-architected exit sequence; neither is on any worklist. |
| **Solution shape** | Possession *token*: predecessor computes `H = hash(durable-DoD content ‖ N named disk facts)`; successor must emit `H`, computable only by actually reading the named artifacts → checkable in bash, immune to D-10. Requires either two-pane overlap or an out-of-session arbiter that holds the exit until `H` lands. **Cannot cover**: retrieval ≠ comprehension; tacit "why"; anything not yet on disk (exactly the §1.4 no-carrier rows). It raises the floor from *delivery receipt* to *artifact-read receipt* — not to *mission understood*. |
| **Confidence** | HIGH (mechanism absence measured; D-10 pre-establishes the failure of the naive fix) |

### FR-11-2 — Authorized scope growth is 100% lossy; the ledger records the baseline, never the deltas
| | |
|---|---|
| **Problem** | Follow-On Gate growth never reaches the durable DoD, and the failure is invisible because the baseline looks healthy. |
| **Evidence** | **0** occurrences of `Scope (grown)` across **every transcript in every project** — the rule has been resident since 2026-07-18 and `dod-persist.sh:55-63,130-137` carries dedicated capture code that has never had an input. Separately, **5/5** durable-DoD captures are `manual-set`; **PreCompact has produced zero**. Root cause located: `extract_scope` filters `.type=="assistant" or "user"` (`:47`), but in the desk's own project 34 of 62 `Scope (frozen)` occurrences are `.type=="attachment"` — dod-persist's *own* SessionStart re-injections, invisible to its extractor. |
| **Why default-tier insufficient** | Both ends are built and correct; the model simply never emits the line. This is the **same model-diligence root** the Fable panel identified for the 0/2419 recycle non-fire ("the ARM step, not the fire") — a class the default tier has now failed at twice with a correct mechanism in place. It also produces **generational decay**: a recycled successor receives its DoD as an attachment, never re-states it, contributes nothing at its own PreCompact — so the durable file silently ages to the last generation that happened to *type* the line, while continuing to look fresh. |
| **Solution shape** | Make scope mutation self-recording rather than narrated — the gate that *authorizes* growth writes it (tool-call-side capture), not the model that *announces* it. Plus: extend `extract_scope` to attachment records, and make `get` return frozen + grown. |
| **Confidence** | HIGH (measured, zero-instance) |

### FR-11-3 — Memory is captured but not retrieved at decision time
| | |
|---|---|
| **Problem** | Sessions relearn the same lessons because the knowledge layer is load-at-start pointers, with nothing binding an entry to the moment it should fire. |
| **Evidence** | `MEMORY.md` = 40 lines / 14 KB / 38 index entries + 39 topic files / 208 K total — comfortably **under** the 200-line / 46 KB compaction trigger, so the *unbounded-growth* worry is **REFUTED** at current scale (anti-capture list + human-gated `/compact-memory` are holding). The failure is retrieval: the index is a title list a session must *choose* to open. The memory corpus itself records repeated relearning of one class — `desk-read-transcript-before-asserting-WHY`, `desk-verify-fresh-before-mutating-backlog`, `whack-a-mole → file-the-systemic-fix` are each "I did this wrong again" captures. |
| **Why default-tier insufficient** | The default response is "write it down better" — already done, and demonstrably not the binding constraint. The hard problem is *conditional surfacing*: binding a durable fact to the tool-call/decision context that should trigger it, without re-loading the corpus and without the model having to remember that the memory exists. That is a retrieval-architecture question, not a capture-hygiene one. |
| **Solution shape** | Retrieval-triggered memory — index entries carry machine-matchable trigger predicates (tool name, path glob, command shape) and a hook surfaces the ≤1 matching entry at the call site, rather than 40 titles at SessionStart. |
| **Confidence** | MED-HIGH (size claim measured; retrieval claim inferred from the repeat-capture pattern) |

### FR-11-4 — Context is not a plannable resource; quota is
| | |
|---|---|
| **Problem** | Waves are placed by quota headroom with **zero** context dimension. |
| **Evidence** | `cc-wave-plan` plans `{account, model, effort, fire_line}` from a live quota SSOT with spread-aware placement and a hard cliff (exit 4) — and contains **no** context term. Repo-wide: no `context_budget` / `ctx_budget` outside two prose docs. A wave can therefore place work on a session with 15% remaining runway, and nothing notices. |
| **Why default-tier insufficient** | Quota is a *measured balance* — readable, decrementing, forecastable. Context runway is not: the context cost of a task is not knowable a priori (it depends on files touched, tool-output volume, retries), and §1.3 shows the *current* fill isn't even reliably observable. Making context a first-class placement input is planning under genuine uncertainty with an unreliable sensor — categorically unlike the quota problem the existing planner solved. |
| **Solution shape** | Unified fuel ledger where a placement decision consumes both quota and *estimated* context, with runway as a first-class cliff condition — plausibly the generator-class item, and a natural extension of C-DSH-1's write-before-act lifecycle record. |
| **Confidence** | MED (absence measured; "generator-class" is a judgment) |

### FR-11-5 — The durable DoD is worktree-keyed, but the work is worktree-fanned
| | |
|---|---|
| **Problem** | The DoD carrier covers exactly the one surface where it is least needed. |
| **Evidence** | `dod_file_for` hashes `git rev-parse --show-toplevel` (`dod-persist.sh:37`), which for a **linked worktree returns the worktree path**. Live: `wt-abstain-alarm → d9bfd6f0…`, `wt-auditability-floor → 19f2991c…`, `wt-autonomy-100 → 160baba9…` — **none of these files exist**; only 2 DoD files exist on disk, both non-worktree. Every Agent-Teams teammate and every Mode-B/C handoff into a fresh worktree starts with an **empty** durable DoD. |
| **Why default-tier insufficient** | Borderline — the *mechanism* fix (key on `--git-common-dir`, or inherit the parent's DoD at worktree creation) is identified engineering. The frontier residue is the policy question it exposes: a teammate's DoD is a *narrowed* slice of the lead's, so naive inheritance over-scopes it and per-worktree isolation under-scopes it. Scope **derivation** across a fan-out boundary has no design. |
| **Confidence** | HIGH on the defect (measured); MED that the policy half is frontier |

---

## 3. NOT frontier — identified work, route to backlog

| Item | Evidence | Route |
|---|---|---|
| **Telemetry staleness (P0)** | 14 live sessions blind, worst 19.5–24.7 h stale (§1.3) | **Fix first — it gates every other conclusion here.** Known path: derive fill from the session JSONL (which *is* appended during a long turn, unlike the statusline render) inside the PostToolUse hook, instead of reading statusline's export. Ordinary engineering. |
| **Two-tier hard zone unimplemented** | Panel-ruled `panel-findings.md:61-67`; no `80`/hard-zone branch in `waiting-recycle.sh` | Build to the existing ruling: relax S1-untracked/S4/S6 above 80, keep S3+S5 absolute, distinct ALARM instead of silent abstain. |
| **`AUTOCOMPACT_PCT_OVERRIDE=90` unset** | D-F ruled + operator-approved; absent from the `claude-next` launcher | One-line launcher export. Until then the 73% margin is computed against an unverified constant. |
| **waiting-recycle dormant** | 230/230 `abstained not-armed` | Arm-by-default landed (`abecaad`); Stage-2 still SHADOW pending `arm --live`. Operator-gated (C10). |
| **Memory corpus size** | 40 lines / 208 K, under threshold | No action — explicitly refuted as a problem. |
| **a19 D-11 (`/goal` >4000)** | `check_goal_length` `handoff-fire.sh:461-476` | **CLOSED** — do not re-derive. |

**Ordering note for lead**: FR-11-1..5 are stated on the assumption that the fuel policy is
*measurable*. It currently is not. Fixing telemetry staleness is a prerequisite to knowing whether
the 55/73/80/90 ladder composes at all — several rows above may re-rank once the gauge is honest.

---

## 4. Could not determine

- **Whether the PreCompact DoD path has ever had a valid opportunity.** Zero PreCompact captures is
  measured, and the attachment-record blind spot is proven — but I could not establish how many
  auto-compacts have actually occurred since the hook was wired (2026-07-18/19). "Broken" vs
  "correct-but-never-exercised" is therefore **partially** resolved: the extractor demonstrably
  misses attachment-borne scopes (a real defect), but assistant-borne scopes exist in many
  transcripts and *would* be captured.
- **The true auto-compact threshold.** With D-F unset, the harness default governs and I could not
  read it. Deaths observed at 76/86/97% are consistent with either a non-90 default *or* stale
  `used_pct` at death time — most likely the latter, but not separable from disk.
- **Whether `Scope (grown)` is unemitted because the gate never PASSes, or because it PASSes and the
  model omits the line.** Both produce zero occurrences; distinguishing them needs transcript-level
  reasoning about follow-on decisions I did not attempt.
- **Whether an out-of-session arbiter can hold a pane's exit** (needed for FR-11-1's proof window).
  `handoff-fire --recycle` arms a detached watcher *before* `/exit` precisely because the interrupt
  SIGKILLs the process group — whether that watcher could gate relaunch on a possession token is a
  design question I could not settle read-only.

---

## 5. Adversarial self-pass (integrated above; recorded for audit)

Three assumptions I attacked with real reads rather than reasoning:

1. *"You assumed `used_pct` is trustworthy — every threshold reads it."* → **Assumption broken.**
   Measured 31/36 stale; then refused to stop there and split by pid liveness, finding 14 genuinely
   blind live sessions vs 16 harmless dead rows. This became the report's load-bearing finding and
   demoted several apparent "frontier" rows to "unmeasurable until fixed".
2. *"You assumed the knowledge layer grows without bound."* → **REFUTED.** 40-line index / 208 K
   corpus, under threshold; anti-capture + human-gated compaction are working. Reframed FR-11-3 from
   a size problem to a retrieval problem.
3. *"You assumed dod-persist being wired means D-12 is closed."* → **Half-refuted.** Wired on all 4
   dirs (verified via `jq` over each `settings.json`), but 5/5 captures are `manual-set` and the
   extractor provably misses attachment records — architecturally closed, empirically unproven.
