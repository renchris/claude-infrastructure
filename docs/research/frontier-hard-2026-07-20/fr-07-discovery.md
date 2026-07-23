# AXIS 7 — Discovery & Self-Improvement Loop

> Frontier-discovery wave 2026-07-20, axis 7 of 13. Read-only research; all figures measured from
> disk/live state on 2026-07-20. Checkout was **6 commits behind `origin/main`** at read time.

## 1. The discovery loop as wired today

**Standing scanners (the only automated ones):** `bin/cc-discover` runs four critics — C1 frontier-hole
(`:147`), C2 plan-open (`:165`), C3 wiring-inert (`:206`), C4 gate-red (`:231`). Wired via
`launchd/com.claude.discovery.plist` (`StartInterval 3600`, `RunAtLoad false`), **activated
2026-07-20T00:19** (`~/.claude/autonomy/pending-activation/03-load-discovery-activate.sh.done`;
`launchctl list` confirms loaded). `com.claude.dispatcher` (900s) drains the backlog.
`bin/cc-digest:190-212` emits the D9 Inert-check into a morning digest;
`scripts/idl-abstain-alarm.sh:104-118` is the nightly alarm on the same predicate. Three lockstep
implementations of one predicate (`cc-discover:211`, `cc-digest:200`, `idl-abstain-alarm.sh:105`).

**Measured behavior (84 runs, 2026-07-19T06:47 -> 2026-07-20T07:34, from `~/.claude/autonomy/idl.jsonl`):**

| Critic | evals | fired | Note |
|---|---|---|---|
| frontier-hole | 84 | **0** | `FRONTIER_HOLES.md` contains **zero** `### H-N` headings; Open = `_(none)_` |
| plan-open | 83 | 1 | |
| wiring-inert | 84 | **0** | |
| gate-red | 83 | 1 | |

**Total automated fire rate: 2 / 336 = 0.6%.**

**Yield by provenance** (`backlog.jsonl`, 465 adds):

| Class | added | **claimed** | disposition |
|---|---|---|---|
| AUTO-CRITIC (plan-open/frontier-hole/wiring-inert/gate-red) | 400 | **10 (2.5%)** | 387 bulk-retracted 2026-07-19T01:37-01:41, evidence `"C2-unscoped flood retracted; scoped default landed 5f3ff0c"` |
| HUMAN/DESK (`desk-observed`, audit, session-sourced) | 65 | **54 (83%)** | 60 done, genuinely worked |

**A 33x actionability gap.** The critics' true net yield is ~3-13 real items from 400 adds. Every
high-value item is `desk-observed` — an LLM noticing during work, with file:line precision
(`"completion-assert.sh:42 emits MALFORMED IDL lines — raw %s interpolation of reason"`).

**What no current scanner can represent.** All four critics are **closed-world**: each re-reads a
registry the system already maintains (a ledger file, `find-plan.sh` output, its own IDL dispositions,
gate exit codes). None can produce a *new observation about the world*. Structurally invisible classes:
cross-subsystem design flaws, law-contradictions, rule rot, missing organs. Historical provenance
confirms this — the entire `G-*` gap ledger, the three "missing organs" (`synthesis.md:28-34`), Themes
A/B/C, and both Fable holes (`H-DSH-1/2`) came from **human-triggered research waves**, never from a
standing critic. `scripts/desk-invariant.sh:4-8` names itself "the one asset class the repo had ZERO
instances of" — found by the a17 hostile panel.

---

## 2. Frontier rows (ranked)

### FR-1 — Discovery is a detector population, not a generator; every unknown-unknown has been found by episodic human-triggered waves

| Field | |
|---|---|
| **Evidence** | 0.6% fire rate over 336 evals; 2.5% claim rate on 400 auto-adds vs 83% on 65 human/desk adds; all four critics read registries the system already writes (`cc-discover:147,165,206,231`); every missing-organ find traces to a wave (`synthesis.md:28-46`, `FRONTIER_HOLES.md:20-36`), none to `cc-discover` |
| **Why default-tier insufficient** | Not a bug — a **capability ceiling**. A critic is a program; a program detects only what it was written to detect. Adding C5, C6, C7 extends the closed world, never escapes it. The one process that has ever found a missing organ is *baseline-blind derivation over a system model* — currently episodic, expensive, human-initiated. Making derivation **standing** (cheap, scheduled, non-redundant across runs) is unsolved: you cannot dedupe against a registry of things you haven't thought of, and a naive scheduled panel re-derives the same top-10 findings forever. |
| **Solution-shape** | A *derivation* critic with a coverage memory: a seam registry (`FRONTIER_HOLES.md:38-42` is the seed — one row today) keyed on component-pairs with last-swept depth, driving a scheduled baseline-blind panel over never-swept or stale seams; novelty scored against the swept-set, not against the backlog. Generator-class: dissolves "how do we find X" for every X. |
| **Confidence** | **High** on the diagnosis (measured). **Medium** on solution-shape. |

### FR-2 — The D9 self-monitor observes 3% of the IDL, 7% of hooks, and 0% of the discovery loop that feeds it

| Field | |
|---|---|
| **Evidence** | `idl.jsonl` = 206,972 records. D9-visible (`.hook` AND `.disposition`) = **4 hooks / 6,285 records (3.0%)**: waiting-recycle 5,331, anti-deference-nudge 318, boundary-handoff 318, completion-assert 318. Invisible: lead-supervisor **199,528**, cc-discover 335, cc-dispatch 198, cc-wave-plan 39, cc-reaper 2, null-actor 597. **4 of 55 hook scripts (7.3%)** emit D9-visible records. `cc-discover:96-97` states the self-exemption *by design*: "Our records carry NO `.hook`/`.disposition`, so C3's inert-scan never counts them." Two exhaustive greps found **nothing** asserting cc-discover ran recently — no liveness monitor exists. |
| **Why default-tier insufficient** | The schema fix (emit `.hook`) is routine. The frontier part is the **denominator problem**: "is my observability complete?" has no computable answer — you cannot enumerate what you failed to instrument. Worse, the system is *currently sitting in the ambiguous state*: C1's 84/84 "0 candidates" is indistinguishable between "no open holes" (true today) and "the regex stopped matching the ledger format" (a live risk — `cc-discover:149` abstains only when the file is **absent**, never on "file present, zero headings of any shape"). D9 was built precisely to catch a check that stopped seeing reality, and it cannot see the check that would catch itself. |
| **Solution-shape** | Normalize actor->hook schema (routine); then the real item: a *coverage attestation* — every wired hook/daemon declares an expected eval cadence, and the monitor alarms on **absence of records**, not only on blind records. Absence-detection is the missing predicate class across all three D9 implementations. |
| **Confidence** | **High** (all figures directly measured). |

### FR-3 — Memory is write-mostly: nothing verifies a memory against live state, and nothing retires one

| Field | |
|---|---|
| **Evidence** | 39 topic files, 208 KB, `MEMORY.md` 40 lines / 14 KB (~30% of the 46 KB `/compact-memory` threshold — **the retirement organ's trigger has never fired**). 12 files touched on 2026-07-19 alone. Enforcement of the anti-capture list = `hooks/memory-nudge.sh:38` — `UserPromptSubmit` `additionalContext` every 12 prompts, **advisory, with zero validation of what gets written**. `/compact-memory` (`commands/compact-memory.md:22-30`) is human-gated, size-triggered, and SAFE-AUTO archives only entries **self-declared** RESOLVED/DONE with no pending tail — it never checks a claim against the world. **Live stale instance (verified):** `desk-autonomy-dormancy-staged-not-loaded.md` and its `MEMORY.md` index line assert the dispatcher/discovery spine is "BUILT but INERT ... never launchctl-loaded". Both were activated hours later (`02-*.done` 2026-07-19T23:51, `03-*.done` 2026-07-20T00:19; `launchctl list` confirms both loaded). The memory is unchanged and **still injected into every session's context**. Counter-verified *not* stale: `cc-blockers-board.md`'s "both PARKED for operator land" — `feat/autonomy-100` and `feat/board-runnable-commands` remain unlanded. **Second class — dangling references:** all 6 `memory/*.md` paths cited by hooks/skills are unresolvable in this project (`agent-teams-enforce.sh:33,59` -> `feedback-agent-team-models.md`; `plan-agent-teams-default.sh:44` -> `agent-teams-hardened-playbook.md`; 4 more in skills). Two exist only under the *reso* project; four exist nowhere. These are injected as authoritative `"Rule: memory/X.md"` pointers to nothing. |
| **Why default-tier insufficient** | Cheap staleness detection is genuinely hard: a memory asserts a fact about the world, and re-verifying it generally costs as much as the original discovery. The tractable subset — memories whose claim reduces to a **checkable predicate** (a path exists, a job is loaded, a branch landed, a commit is in `origin/main`) — is not identified anywhere, and no schema distinguishes checkable claims from judgment claims. |
| **Solution-shape** | A `verify:` frontmatter field carrying an executable predicate for the checkable subset + a sweep that flips a memory to `SUSPECT` on predicate-fail (never auto-deletes — File Update Rule). Dangling-ref lint is routine and immediate. |
| **Confidence** | **High** on the mechanism gap and both live instances. **Medium** on what fraction of memory is predicate-checkable. |

### FR-4 — The self-improvement organs are unread dead-letter queues — the exact pathology `autonomy-sweep.sh` was built to fix, unfixed one layer up

| Field | |
|---|---|
| **Evidence** | `~/.claude/skills-pending/_candidates.jsonl` = **7 records, all `status:"unreviewed"`, oldest 2026-07-01 (19 days)**. Zero drafts ever produced. Sole reader is the human-invoked `/harvest-skill`. **The records are also corrupt**: `harvest-skill-end.sh:25` does `SELECT message_count \|\| '\|' \|\| commands_run \|\| '\|' \|\| files_changed` then splits on `\|` — but `commands_run` holds shell text containing `\|` and `&&`, so fields mis-split (observed: `commands_run` holds a git command string; `files_changed` holds another). `evolve-skill` has fixtures for `pyramid-principle` only — never applied to an operational skill. `scripts/autonomy-sweep.sh:2-5` names this exact pathology for the escalation dirs ("the escalation lattice terminated NOWHERE — every layer wrote durable evidence into dirs with no reader") and built the sweep. **No equivalent sweep exists for the self-improvement layer.** |
| **Why default-tier insufficient** | Building a sweep is routine (-> route). The frontier residue: the *reason* these stayed human-gated is Invariant 6 (self-mod is C10, human-only). So the self-improvement loop is **capped by construction** at "propose to a human who never comes". Whether a bounded self-modification envelope exists that preserves C10's safety intent while letting the loop actually close is a real design question, not a build task. |
| **Confidence** | **High** on the dead-letter measurement and the corruption bug. **Medium** on the C10-envelope framing. |

---

## 3. NOT frontier — routing

| Item | Evidence | Route |
|---|---|---|
| `harvest-skill-end.sh:25` field-split corruption | 7/7 records unusable | **Backlog P1** — `desk-observed`; select fields separately or emit JSON |
| 6 dangling `memory/*.md` refs in hooks/skills | none resolve in this project | **Backlog P1** — add a lint to the gate; fix or repoint each |
| Actor->hook IDL schema normalization | 97% of IDL invisible to D9 | **Backlog P1** — mechanical; unblocks FR-2's real work |
| `_candidates.jsonl` sweep/reader | 19-day-old unread queue | **Backlog P2** — mirror `autonomy-sweep.sh` |
| C1 format-drift guard (abstain when ledger present but zero headings of any shape) | `cc-discover:149` abstains only on absent file | **Backlog P2** — small, closes a real blind spot |
| Rule->actuator compilation itself | **Already underway, hand-built**: `dod-persist.sh` compiled R1 (frozen DoD, was NONE); `/wrap` + `wrap-ledger.sh` + `completion-assert.sh` compiled R2 (was "does not exist", p13 §1); `agent-teams-enforce.sh:76-88` compiled R8 brief-cap (was NONE); `desk-assert` compiled the read-transcript-before-asserting-why rule (15ed671); `task-quality-gate` made repo-aware (6d5a270) | **Not frontier as a program** — it's executing. Route continued per-rule compilation to the backlog. |
| The `p13` "compile the constitution" thesis as a whole | 5 of 21 rules converted in 2 days | **Downgrade from frontier.** The generator-class residue is narrower and stated below. |

**Important delta vs the wave brief's hypothesis:** the brief proposed "compile the constitution into
actuators" as the candidate generator-class item. **The measurement refutes the framing.** Compilation
is already the active program and is converging fast (5 of p13's 21 rules gained actuators in 48h).
What is *not* underway, and what no one can currently answer, is: **which rules are compilable at all,
and what is the compiled fraction?** There is no index of rules->actuators; `p13 §1` is a hand-built
snapshot, already stale. And some rules are irreducibly model-side (Follow-On Gate F1 "net-positive
under the operator's standing values" cannot become a predicate). A decidability triage —
*compilable / partially-compilable / irreducibly-judgment* — is the genuine frontier residue here, and
it is a sub-question of FR-2's denominator problem, not a separate program.

---

## 4. Could not determine

1. **What actually invokes `cc-discover` every ~16-17 min.** The loaded plist declares
   `StartInterval 3600`; `launchctl print` confirms 3600s. Observed gap histogram over 84 runs: mode
   **16 min (37x), 17 min (16x)** — matching the dispatcher's 900s cycle plus runtime, but
   `bin/cc-dispatch` contains no invocation (verified against `origin/main` too). No crontab, no other
   plist, no hook or script reference. **This is itself an FR-2 datum**: nothing in the system asserts
   or records the discovery loop's own cadence, so a 3.7x deviation from the declared schedule went
   unobserved and is unattributable from disk.
2. **Whether C3 has ever been correct.** It fired 4 times historically (4 `wiring-inert` adds) but 0
   times in 84 recent runs, while only 4 of 55 hooks are even visible to it. Its true-positive rate is
   unmeasurable with the current denominator.
3. **What fraction of the 39 memory files carry checkable predicates.** Two claims verified by hand
   (one stale, one current); a full sweep was out of budget.
4. **Deploy lag:** the shared checkout is **6 commits behind `origin/main`**. All file:line citations
   are against the checkout; a landed-but-undeployed fix to any cited line is possible (the
   `deploy-lag-checkout-behind-origin` failure mode).
