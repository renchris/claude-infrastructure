# FR-09 — Adversarial failure-class census (patch-resistance)

**Axis 9 of 13, frontier-discovery wave · 2026-07-20 · READ-ONLY**
Baseline: `docs/research/desk-audit-2026-07-18/synthesis.md` G-* ledger (not re-derived).
Evidence: 40 memory incident files · 161 commits since 2026-07-17 · live residue in
`~/.claude/autonomy/{idl.jsonl,supervisor.log,regression.log,abstain-alarm.log,pages/}`.

## 0. Headline

The frontier signal is **not** that individual bugs are hard to fix. Measured over 45 `fix(` commits,
the fix *logic* is consistently sound, RED-proven, and regression-tested. The patch-resistant classes
all share one shape: **the repair is delivered through a path that cannot verify it took effect.**

The load-bearing measurement: `com.claude.lead-supervisor` daemon **pid 20915 has run continuously
since 2026-07-18 18:11:01** (`ps -eo pid,lstart`, ppid 1). `scripts/lead-supervisor.sh` has
**mtime 2026-07-19 13:27**. Five of the seven supervisor fixes landed *after* the daemon started and
have therefore **never executed**. The symptom persisted; the desk read persistence as "fix didn't
work" and filed more fixes. That loop produced the deepest chain in the census.

## 1. Failure-class recurrence table

| Class | Instances (dated) | Fixes applied | Recurred AFTER a fix? | Patch-resistant? |
|---|---|---|---|---|
| **C1 Stale-fix delivery (landed ≠ running)** | daemon pid 20915 30h-stale (07-20, measured); checkout 6 commits/18h behind origin (07-20, memory `deploy-lag`); dispatcher/discovery staged-never-`launchctl load` (07-19/20); waiting-recycle arm CFG-STRANDED → 0 shadow fires (07-19) | `ad37447` cc-reconcile · `scripts/desk-arm-live.sh` · `ACTIVATE-ENGINE.sh` · `bin/cc-blockers` | **YES** — each fix closed one layer, a new layer surfaced | **YES** — ≥3 independent staleness layers, no end-to-end running-vs-landed detector |
| **C2 False-cause / premise inheritance** | 3 wrong causal claims (07-16); it2-gate theory REFUTED as subshell artifact (07-19); "reaper DORMANT" premise false (07-19 `b4e3c35`); dispatch "correct wait state" was a masked bug (`bef587a`); firefighting already-fixed symptoms (07-20); **memory file itself encodes a refuted claim** (§2.4) | prose memory rules: `desk-read-transcript-before-asserting-why` (07-16), `desk-verify-fresh-before-mutating-backlog` (07-19), `deploy-lag` (07-20) | **YES** — ≥4 recurrences after the rule existed | **YES** — fix is prose discipline; repo's own injection-channel law says resident prose decays |
| **C3 tty / GUI-injection** | splitright −1719 double-fire (07-17 `d662845`); cold-`--worktree` auto-submit race (07-17, **still open**); ttys018 ZLE mis-inject (07-19 `24e98d9`); same root via AppleScript transport (07-19 `e4b245c`); focus-steal (07-19 `10e609a`); `as_tty` non-zero under load (07-19 `300a9c5`) | 6 fixes, all with regression tests | **YES** — one root cause, re-fixed per transport | **YES** — GUI-terminal automation has no delivery guarantee; each new surface re-imports it |
| **C4 Supervisor false-stall / page-evaluation** | `3384c73`→`9dfe98d` (8 min later, damping leaked)→`5c548b1`→`3ceca7c`→`7fe3468`→`4052d02`→`6488617`: **7 fixes in ~19h** | as listed | **YES**, 6×, each fix's own message cites the prior fix as insufficient | **PARTLY** — logic converged; residual persistence is C1, not bad logic |
| **C5 Registration / roster divergence** | reaper blind `2be82e97` (07-19) → `ad37447` → **RESURFACED 07-20** desk Δ1, cc-reconcile "present" vs cc-sessions disagree → `6488617` (**not in HEAD**) + open backlog `a60d62a215f1`; supervisor desk-exempt `4052d02` mirrors it | `ad37447`, `4052d02`, `6488617` | **YES** — explicit resurface, new edge | **YES** — identity asserted in ≥5 disagreeing stores; each fix reconciles one pair |
| **C6 Manual-enumeration fail-closed lints** | `reaper-horizon-lint` declaration fixes ×3: `6681cce` (waiting-recycle+handoff-fire), `524dadf` (cc-reconcile), `674bfee` (cc-value+cc-reconcile) | 3 | **YES**, 3× | **YES** — fail-closed lint over an open-ended growing set re-reddens on every new tool, by construction (`674bfee`: "landed after `$DECLARED` was last updated") |
| **C7 Conjunctive gate that never fires** | `waiting-recycle`: **0 Stage-2 fires in 5,399 evaluations, all-time**. Pre-fix `not-armed` 5,124 (94.9%); post-arm-fix the blocker migrated to `below-threshold-no-tell` (151 on 07-20), `recycle-machinery` (3→33), `live-team-hold`, `dirty-tree-hold` | `abecaad` arm-by-default · `4c249a9` go-live · `desk-arm-live.sh` | **YES** — symptom migrated across conjuncts | **YES** — clearing one conjunct promotes the next |
| **C8 Telemetry staleness / audit-substrate flood** | 96,233 of 99,632 IDL rows today (**96.6%**) are lead-supervisor; 75 findings re-recorded every ~35s sweep; IDL 41.3MB + one 9.6MB rotation | `b59f1cf` log-rotation; `7fe3468` telemetry GC (**not in HEAD**) | **YES** — rotation treats symptom, volume rose | **YES** while C1 holds — the GC fix cannot run |
| **C9 Page-residue accumulation** | 175 `.page` files: 72 from 07-15, 26 from 07-16, 47 from 07-19, 28 from 07-20 — 5-day-old pages never cleared | none found | n/a — never fixed | **Open, not yet patch-resistant** (untried) |
| **C10 Prose-rule bypass** | audit §C "PROSE-LOAD-BEARING"; ship content-verify, shared-checkout guard; empirical bypass land 07-18T03:20 (G-P9-4) | `land-verify.sh`, `payload-lint`, `cc-blockers --lint` fail-closed, resident-rule+actuator pattern | **Partly** — codified instances hold; uncodified ones recur (C2 is the live case) | **YES for uncodified**, NO once code-enforced |

## 2. Fix-introduces-bug chains — count and character

**Six identified.** Characteristic: the fix is correct *and* re-imports the pathology it targets, at a
level the fix's own test cannot observe.

**2.1 `cc-bind` — the canonical instance (`1eebe07`).** The BIND tier's fail-closed ruling gate bound
its ack to a ruling **ID, not its CONTENT**, so a ruling could be silently rewritten post-ack and the
gate still printed PASS. The commit message is the sharpest self-diagnosis in the repo:

> "Your amendment exposed a hole in the tool I built to close the last one. … The orchestrator
> compensated BY HAND — 'ruling blob text verified verbatim' — which is the audit's own second-class
> relay (a human hand-verifying a blind automation, §1) **REAPPEARING INSIDE THE TOOL BUILT TO END IT**.
> **Fourth instance tonight of a check that cannot see the thing it guards.**"

Self-counted 4 instances of the blind-check class in one night, one of them inside the anti-blind-check tool.

**2.2 `cc-reaper` log() UTC (`b4e3c35`).** `log()` used bare `date '+…Z'` — local time under a literal
UTC marker. Every log line read ~7h stale, producing a **perpetual false "reaper DORMANT"**. The
observability layer added to prove liveness became the generator of a liveness false-alarm.

**2.3 Damping fix defeated by a sibling path (`3ceca7c` Fix A).** `3384c73`'s `.notified` marker was
being dropped by `void_page`, so every STALL?→void→re-STALL? cycle re-notified — the damping fix was
silently disarmed by a third code path 13h later.

**2.4 Memory-layer capture of a refuted cause — the most consequential.** Memory
`desk-whack-a-mole-means-file-systemic-fix.md` records item `6d898339d690` as a validated success:
*"cc-reaper 5-min cron not effectively sweeping since 10:04Z … loop landed the fix (done 17:56); cron
resumed (sweep 18:06Z) … Full observe→file→land→self-heal loop closed."*

`b4e3c35` refutes this: the cron **never stopped**. Verified directly from
`~/.claude/logs/cc-reaper.log` — sweep-start stamps run a clean 6-min cadence
`… 10:31 10:36 10:42 10:47 10:53` then **jump to `17:55 17:58 18:05 18:11 18:18 …`**, resuming the same
cadence. That is exactly the PDT→UTC offset appearing the moment `date` → `date -u` took effect. The
"cron resumed at 18:06Z" is the *first true-UTC stamp*, not a resumption.

So the durable-learning artifact absorbed a false causal claim — inside the file whose subject is
systemic-fix discipline, and whose sibling rule (`desk-read-transcript-before-asserting-why`) exists to
prevent precisely this. **Memory is not immune to the class it documents, and nothing re-validates a
memory file against later refuting commits.**

**2.5 `e4b245c` — same root, new transport.** Fixing ZLE mis-injection on the split surface left the
`--tab`/`--window` AppleScript surface with the identical bug: *"Same ttys018 root cause, different
(AppleScript) transport."*

**2.6 `674bfee` — fail-closed lint self-reddening.** Fixing the lint by extending `$DECLARED` guarantees
the next tool re-reddens it.

## 3. Top patch-resistant classes — why per-symptom patching cannot close them

**① C1 Stale-fix delivery.** Three independent staleness layers, each invisible to every existing gate:
(a) shared checkout behind `origin/main`; (b) long-lived daemon holding pre-fix code; (c) C10
staged-but-never-loaded launchd jobs. Every gate — bats (85 suites), shellcheck, premortem — validates
the **file on disk**, never the **process in memory**. A fix can be landed, green, symlinked live, and
still be 30 hours from executing. Per-symptom patching cannot close this because *the patch itself is
delivered through the broken path*. Empirical proof: 5 of 7 supervisor fixes non-executing while their
symptom is measured live at ~6,840 page-rows/hour.

**② C2 False-cause inference.** The only fix ever applied is prose in a memory file. The repo's own
injection-channel law (audit P13) states resident-only rules decay and rot-resistance requires a
deterministic trigger on `UserPromptSubmit`/`PostToolUse.additionalContext`/`decision:block`. No such
trigger exists for causal claims. Worse, §2.4 shows contaminated conclusions get *written into memory*
and re-read as ground truth by successors — the class has a persistence mechanism the fix does not.

**③ C3 tty/GUI injection.** Root cause is substrate-level: typing a character stream into a live zsh
whose ZLE runs autosuggest + syntax-highlight widgets + `setopt CORRECT`. There is no delivery
guarantee and no ack. Six fixes each added verify/retry for *one observed* failure surface; the cold-fire
auto-submit race remains open. Any new surface re-imports it.

**④ C5 Registration/roster divergence.** Session identity is independently asserted in ≥5 stores
(`cc-registry`, `cc-sessions`, telemetry, `cc-roles`, it2 pane list) with no single source of truth.
Each fix reconciles one *pair*; with 5 stores there are 10 pairs, and the 07-20 resurface was a
previously-unreconciled pair (cc-reconcile "present" vs cc-sessions enumeration).

**⑤ C7 Conjunctive-gate non-firing.** 0 fires / 5,399 evaluations. Each fix clears the currently-dominant
conjunct and the next becomes dominant — measured migration `not-armed` → `below-threshold-no-tell`.
Fixing conjuncts one at a time cannot produce a fire; only end-to-end fire-rate as the acceptance
criterion can.

## 4. NOT-frontier — classes closing under normal patching

| Class | Evidence of closure |
|---|---|
| **Timestamp/timezone** | Post-`b4e3c35` sweep: **123** correct `date -u` uses vs **2** remaining bare-`date` instances, both benign (`reaper-e2e.sh` explicit `TZ=UTC` fixture; `prune-backups.sh` human-readable local log, no `Z` literal). Class genuinely closed. |
| **False-cliff / quota misread** | `bef587a` (bound wave to `MAX_SPAWN`) holds — live IDL 07-20: `cc-dispatch` `action:"passed" detail:"backlog empty"`, `fired 0 abstained 0 failed 0`. Verified not a false negative: `cc-backlog list --json` = 3 blocked + 1 claimed, no dispatchable items. Queue genuinely drained. |
| **Operator-facing notify damping** | Damping works at the delivery layer: **179** `.notified` markers against **47,417** DEAD page-evaluation rows today. The operator channel is *not* flooded; only the audit substrate is (C8). The 07-18 damping fixes achieved their actual goal. |
| **Inert-hook dormancy (partial)** | `abstain-alarm.log` DORMANT-100 hooks crossed to non-zero: 07-19 `anti-deference-nudge` 5 fires, `boundary-handoff` 1, `completion-assert` 2; 07-20 `completion-assert` 10. Detection→fix loop worked. (Caveat: `anti-deference-nudge` and `boundary-handoff` are back to 0 fires / 119 abstains on 07-20 — watch, don't yet call closed.) |
| **Planned hardening series** | `reap-safety` t1–t4 (`14a514a`,`43651cf`,`50dce02`,`f019710`) + `ba3ea52` P0-17 are a sequential plan checklist, not recurrence. Correctly *not* a failure class. |
| **Fixture-shape parity** | One instance (cc-dispatch `fire_line` array-vs-string), rule captured, no recurrence in 161 commits. |

## 5. Could-not-determine

- **Whether bash's incremental script-reading partially applied edits to running daemon 20915.** Bash reads scripts by byte offset, so editing a running script can apply *fragments* or corrupt control flow rather than cleanly upgrading. Either outcome is unsafe; I could not determine which occurred. This makes C1 potentially worse than "fix didn't run."
- **The 07-20 07:45Z discontinuity** in `supervisor.log` (`swept=92 findings=75` → `swept=37 findings=20`). Could be telemetry GC, daemon reload, or session churn. Not resolved; if a reload, it partially invalidates the "never executed" window's tail.
- **Whether `~/.claude/autonomy/pages/` has any consumer or GC.** 175 files, oldest 07-15. Audit G-P2-3/G-P1-6 flagged "alarm dirs unread"; I found no reader but did not exhaustively prove absence.
- **`cc-bind` current live behavior.** `1eebe07` is 2026-07-14, before this census's baseline; no post-07-17 instances. Included as a chain exemplar only, not as an active recurrence.
- **Whether `never-stuck-gate`'s 2 failing legs are fixable or permanently C10-pinned.** Live run today: `19 met · 2 failed ⇒ THE INVARIANT IS BROKEN` — identical to the audit's G-P4-1 reading. Both failures are `C10-PEND` (`cc-value` not deployed; `lr-reset-poller` not loaded), i.e. the gate is red *because activation is human-only*. If that is structural, this gate can never go green by agent action and its RED carries no incremental signal — a measurement worth resolving, since `regression.log` 07-19 already reports RED(7) including this gate.

## 6. One-line verdict

Per-symptom patching is working well on *logic*; it is failing on *reaching the running system and
staying true afterwards*. The highest-leverage frontier target is a *running-vs-landed attestation
primitive* — one mechanism answering "is the behavior executing right now the behavior that was landed
and tested?" — which would dissolve C1, most of C4, C8, and the deploy-lag/daemon-staleness incident
class, and whose absence is why the other classes keep regenerating.
