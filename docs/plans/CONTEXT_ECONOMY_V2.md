---
status: complete
row: 8
subsystem: Context economy — when a session recycles
---

# CONTEXT ECONOMY V2 — first-principles rebuild of when a session recycles

**Row 8** of `GROUND_UP_REBUILD_MAP.md`. Methodology: the `ground-up` skill. Exemplar:
`LAND_PIPELINE_V2.md`. Prior design (treated as HYPOTHESIS, not fact):
`docs/research/context-econ-2026-07-20.md`.

**Scope (frozen):** a session recycles BEFORE it rots — p95 recycle at <75% context fill, zero
auto-compact walls hit — under the standing constraint that rot degrades decisions well before the
wall breaks the session. Measured, landed, and verified by disk-truth acceptance reads.

> **⚠ THE FROZEN SCOPE IS RETAINED VERBATIM ABOVE AND ITS METRIC IS FALSIFIED BELOW (§1.1).**
> Per the campaign rule, the DoD cell is the *prior session's hypothesis*. Phase 1 re-derived it
> from primary disk truth and **both halves fail**: one metric is unfalsifiable because its
> denominator is discarded, the other counts an event with zero observed instances and no proven
> emitter. §1.2 states the **corrected, falsifiable metric** the build is actually held to. The
> original line is never edited — it is the audit trail.

---

## Phase 0 — Agent Team Orchestration

**Team size: 0 teammates. This row is built solo, deliberately.** Recorded here because
`plan-conventions` makes Phase 0 mandatory for any plan with 2+ code-writing tasks, and the
justification for *declining* teammates is itself the decision that needs to survive.

| Consideration | Ruling |
|---|---|
| Deliverable size | ~600 LOC total across 1 new reader + 3 surgical hook edits + 3 bats suites. Below the 500-LOC-per-teammate split bar for any single unit. |
| File ownership overlap | Every target file is in row 8's exclusive ownership (`hooks/waiting-recycle.sh`, `hooks/boundary-handoff.sh`, `hooks/lib/context-econ.sh`, `hooks/session-continue.sh`, `bin/cc-ctx-audit`). Worktree isolation buys nothing when there is one writer. |
| Serialization requirement | M-1 (the reader) defines the record schema that M-2/M-3 (the producers) must emit. That is a **hard sequential dependency**, not a fan-out — `staged-skill-fanout-trap` in memory: N sequential stages ≠ N agents; when stages share state the fan-out is dominated. |
| Box contention | The campaign has ≥2 other live rebuilds and row 13 measured that panes cost ~1.6 cores each to draw. Spawning 3 teammates to serialize behind one schema is a pure load tax. |

**Build order (sequential, each landed before the next starts — never batched):**

```
B1  M-1 reader (bin/cc-ctx-audit) + schema  ──►  B2  M-2 durable denominator (context-econ.sh)
                                                      │
                                        B3  M-3 recycle-outcome record (both hooks)
                                                      │
                                        B4  M-4 graveyard take (cd064644)
                                                      │
                                        B5  map row + close
```

---

## §1 First principles — why the old frame cannot work

### 1.1 The frozen metric is falsified on both halves

All figures re-derived this session from primary disk truth: **4,890 deduped session transcripts**
(the fleet's entire recorded history), deduped by realpath because `~/.claude-next/projects` is a
symlink to `~/.claude/projects` (memory `token-usage-from-transcripts` — the double-count trap).

**Half 1 — "p95 recycle at <75% context fill" is unfalsifiable, because the DENOMINATOR is
discarded.**

The fill percentage is `input_tokens / window * 100`. The numerator is durably recorded in every
transcript (`message.usage.*`). The **window is not recorded anywhere durable** — it lives only in
the ephemeral statusline telemetry `/tmp/cc-telemetry/<sid>.json`, which is wiped on reboot.

- Verified by an exhaustive `jq` path-scan for every scalar key matching `window|max_tok|limit`
  across a full transcript. **Two hits, both false positives**: `message.content.0.input.limit`
  (a tool call's own parameter) and `toolUseResult.tmux_window_name` (a tmux pane name).
- **Positive control** beside that absence assertion: the same scan returns all six
  `message.usage.*` keys, proving the scan finds keys that are present.
- Coverage: **74 telemetry files for 4,890 transcripts ⇒ 4,816 sessions (98.5%) have no
  recoverable fill denominator.**
- And the window genuinely varies **within one model** — live telemetry shows `claude-opus-4-8` at
  both `window:1000000` and `window:200000`. So the denominator cannot be imputed from the model
  id either.

⇒ Every constant the incumbent design is built on — `CC_CE_WALL=88`, `boundary T=73`,
`T_IDLE=35`, `T_BUSY=75` — is a percentage of a number the system does not durably record. The
metric was never measurable, and no threshold tuning could have made it so.

**Half 2 — "zero auto-compact walls hit" is vacuous, and the real wall is a different event.**

- **39 compaction events** across 4,890 transcripts, in 20 transcripts. **39 of 39 are
  `compactMetadata.trigger == "manual"`.**
- **Zero `"trigger":"auto"` bytes anywhere in the fleet**, and I found **no existence evidence
  that the harness ever emits `auto`** (the bundle was not locatable to positive-control the
  emitter). Per memory `absence-alarm-needs-existence-evidence`, an absence claim is only
  admissible where the producer's world is known to exist — so this row **does not claim "zero
  auto-compacts happened"**; it reports that the metric **counts an event with no observed
  instance and no proven emitter**. Either way it cannot discriminate a healthy fleet from a
  broken one.
- `autoCompactEnabled` is **unset** in all three live settings roots — the feature sits at its CC
  default and nothing in this repo configures it.

**The event that actually kills sessions is a hard API refusal, not a compaction.** Exact-match on
a bare assistant message equal to `prompt is too long` (case- and whitespace-normalised):

- **7 distinct sessions killed, 10 refusal events.**
- **6 of the 7 had ZERO compactions.** The 7th had one *manual* compaction that did not prevent
  the refusal. **Auto-compaction saved none of them.**
- The killed session's terminal state is *dead in place*: `076a1186` sat at its ceiling for ~2
  minutes emitting `Prompt is too long` to every turn — including to the operator typing
  "youre going to run out of context 1% left" — and never recovered.

**Detector hygiene, stated because it changed the number:** a loose `grep` for the phrase matched
**18** transcripts; exact-match on the bare API error yields **7** sessions. The difference is
prose *about* the error (including this very session's own analysis, which the first pass counted).
That is memory `detector-matching-its-own-skill-description` — *text is never evidence* — and it
is why the acceptance reader in §7 keys on an exact normalised equality, never a substring.

### 1.2 The corrected metric this build is held to

The frozen line is retained verbatim above. The build is held to this, which is falsifiable today:

> **AC-M: every recycle and every wall-hit is a durable, self-describing record carrying BOTH the
> fill numerator AND its denominator, such that p95 recycle fill is computable by one disk read
> over any period — and the fleet's wall-hit count for that period is computable from the same
> read.** Baseline for both today: **not computable at all.**

**Why this is the right correction and not a goalpost move.** The frozen DoD asks for a *fleet
property* ("p95 recycle at <75% fill"). A property cannot be delivered before it can be observed,
and 98.5% of the population has no observable value. Shipping a tuned threshold against an
unmeasurable target is precisely the failure this campaign exists to end. The corrected metric is
the *precondition* the frozen one presupposed — and once it holds, the frozen metric becomes a
report, not a hope.

### 1.3 The inversion

**The incumbent instruments the DECISION and never records the OUTCOME.**

`waiting-recycle.sh` has written **32,075 IDL records**. Every one describes its own evaluation.
Not one describes whether a session was saved or lost:

| Reading | Count | Meaning |
|---|---|---|
| `abstained` | 31,366 | did not act |
| `gc` | 713 | swept its own test pollution |
| `escalated` | 8 | paged the operator |
| `fired` | **3** | see below |

Of the 3 `fired` records, **2 are `busy-nudge:*` advisories** and **1 is the Stage-1 advisory**
(`reason:"waiting-recycle"`). The IDL reason string that would mean *a recycle actually executed*
is `stage2-live` (`hooks/waiting-recycle.sh:958`). **There are ZERO `stage2-live` records.**

> **`disposition:"fired"` is ambiguous across four different meanings** in one field —
> Stage-1 advisory (`:1015`), Stage-2 live exec (`:958`), Stage-2 shadow would-fire (`:972`),
> and the busy nudge (`:862`). Any consumer counting `fired` as "recycled" overstates by 3×.
> This is memory `claimed-outcome-vs-checked-outcome`: emit a structured verdict token a consumer
> can parse, not a word that means four things.

So: **the deterministic recycle has never once executed, in 31,366 evaluations.** And the outcome
it exists to prevent — a wall hit — is recorded by the *harness*, in the transcript, where
**nothing has ever read it**:

- `compact_boundary` readers in this repo: **0**
- `isCompactSummary` readers: **0**
- **positive control** — `used_pct` readers: **18**

⇒ **Rebuild as an OUTCOME READER first and a trigger second.** The reader is retrospective, so it
works over history the moment it lands; a decision-time instrument can only ever measure forward.

### Requirements (invariants that SURVIVE the redesign, per Phase 2 of the skill)

Sorted from MEMORY.md and the incident record into properties any design must keep. These are
numbered because §5 and §7 refer to them.

| # | Invariant | Source |
|---|---|---|
| **R1** | A metric needs a **producer**, and an absence claim needs **existence evidence** that the producer's world exists. | `absence-alarm-needs-existence-evidence`; row 2's M-2 |
| **R2** | **False-negative bias**: unknown ⇒ hold/legacy, never ⇒ fire. A zero must read as *unknown*, never as *safe*. | incumbent `context-econ.sh` contract; preserved |
| **R3** | Every new mechanism ships with an **env kill switch**; never revert-as-plan. | campaign rule |
| **R4** | A signal failure must **degrade to byte-identical prior behavior**, never cost the hook. | incumbent contract; preserved |
| **R5** | A record must be **self-describing** — carry the units/denominator needed to interpret it, so a later reader cannot mis-scale it. | **learned this session** (§1.1; and my own withdrawn M1/M4/M5) |
| **R6** | A **fixture/derived value must be classified by its producer's literal emission**, never by a shape or an assumed constant. | `fixture-vs-real-classifier-needs-a-producer`; `re-derive-handed-down-measurements` |
| **R7** | An append-only store needs a **bounded read with the cap inside the lock**; archive-never-delete is a property of the destination. | `append-only-store-safety-rules` |
| **R8** | A **verdict token must be parseable and unambiguous** — one word may not mean four things. | `claimed-outcome-vs-checked-outcome`; §1.3 |
| **R9** | Consume other rows' mechanisms **fail-soft**; check existence evidence, never trust a status cell. | campaign rule; row 4's inert oracle |

---

## §2 Measured constants this design is built against

Every row is a disk read taken **this session**. `n` is stated wherever it is not 1. Re-derive
before changing any of these (R6).

| # | Constant | Measured value | How / where |
|---|---|---|---|
| C1 | Session transcripts, fleet history | **4,890** (deduped by realpath) | `find` over the 3 real `projects` roots; `~/.claude-next/projects` is a symlink to `~/.claude/projects` |
| C2 | Transcripts with ≥1 compaction | **20** | byte-prefilter `grep -l compact_boundary` |
| C3 | Compaction events | **39** | `jq` over C2's files |
| C4 | Of which `trigger:"auto"` | **0** (39/39 `manual`) | `compactMetadata.trigger` |
| C5 | `"trigger":"auto"` bytes anywhere in fleet | **0** | raw `grep -l` over all C1 files |
| C6 | Sessions killed by a bare `Prompt is too long` | **7** (10 events) | exact normalised equality on assistant text |
| C7 | Of those, sessions auto-compaction saved | **0** (6/7 had zero compactions) | per-session `grep -c compact_boundary` |
| C8 | Loose-grep false-positive inflation for C6 | **18 files → 7 sessions** | prose *about* the error, incl. this session's own |
| C9 | Fill **denominator** recoverable per session | **74 / 4,890 = 1.5%** | telemetry file count vs C1 |
| C10 | Windows observed for ONE model (`claude-opus-4-8`) | **both 1,000,000 and 200,000** | `/tmp/cc-telemetry/*.json` |
| C11 | `waiting-recycle` IDL records | **32,075** | `.hook=="waiting-recycle"` |
| C12 | Of which an executed recycle (`stage2-live`) | **0** | `.reason=="stage2-live"` |
| C13 | `waiting-recycle` abstains | **31,366** | `.disposition=="abstained"` |
| C14 | Top abstain reason | **`not-armed` 26,067 (83%)** | `.reason` prefix census |
| C15 | Other abstains | `below-threshold-no-tell` 2,842 · `live-team-hold` 1,506 · `recycle-machinery` 510 · `disarmed` 291 · `dirty-tree-hold` 110 | same |
| C16 | `--live` arm markers present | **2** (cwd-hash keyed) | `~/.claude/state/waiting-recycle/live-*` |
| C17 | `--busy-force` arm markers present | **0** | same dir; ⇒ the BUSY regime can never exec |
| C18 | `boundary-handoff` IDL records | **2,173** | `.hook=="boundary-handoff"` |
| C19 | Of which fired | **0** (2,173/2,173 abstained) | `.disposition` census |
| C20 | `boundary-handoff` abstain reasons | `below-threshold` 2,012 · `gate-not-green-at-head` 78 · `stale-telemetry` 49 · `no-telemetry` 34 | `.reason` prefix |
| C21 | `cc-fired/*.json` records carrying any fill field | **0 of 135** | row 2's lifecycle store; `grep -l used_pct\|fill` |
| C22 | Repo readers of `compact_boundary` / `isCompactSummary` | **0 / 0** (positive control `used_pct`: **18**) | `grep -rl`, docs excluded |
| C23 | `session-continue` IDL records on this machine | **208**, last **2026-07-27T02:39:34Z** | `.hook=="session-continue"` — see §6 graveyard |
| C24 | Emitter for C23 on trunk / on deployed copy / on `fix/infra-perfection` | **0 / 0 / 9** | `grep -c` per ref ⇒ the telemetry ran in production and is now stranded |
| C25 | Live checkout deploy lag | **21 behind** `origin/main` | `rev-list --count HEAD..origin/main` |
| C26 | Row 8's owned hooks that are live symlinks | **5 of 5** | ⇒ for this row, **landing == deploying** (no activation step) |
| C27 | Staged activations / un-run | **23 / 12** | `pending-activation/*-activate.sh` vs `.done` |

**C4/C5 + C6/C7 together are the load-bearing pair:** the failure the design was built to prevent
(auto-compaction) has no observed instance, and the failure that actually happens (a hard refusal)
was invisible to every mechanism in the subsystem.

**Withdrawn constants (kept visible so no future reader re-derives them from my error).** My first
pass computed a peak-fill distribution (`p50=11.5% · p95=38.7% · max=97.7%`) and concluded the
wall sat at ~97% and that 3 of 7 kills were "low-fill" (17.1/29.6/33.8%). **All three claims are
WITHDRAWN**: they divided every session by a hardcoded 1,000,000, which C10 refutes. `e4f576f9`
refused at 170,616 tokens on `claude-sonnet-5` — **85.3% of a 200K window, a HIGH-fill kill.** The
"per-request oversize" mechanism I nearly built on that artifact does not exist in the evidence.
The token counts are sound; **the percentages were not, and that is exactly what R5 now forbids.**

---

## §3 The architecture — one recorder, one reader, no new thresholds

The incumbent's shape is *five thresholds feeding one actuator that has never fired*. V2 inverts
the dependency: **the outcome record is the primary artifact; triggers become consumers of it.**

```
                    ┌──────────────────────────────────────────────┐
   the harness  ───► │  DURABLE OUTCOME STORE (append-only, JSONL)  │ ◄─── M-3 recycle stamp
   (transcript)      │  every record self-describing: num + denom   │      (both hooks)
                     └───────────────────┬──────────────────────────┘
                                         │
                      M-1  bin/cc-ctx-audit  (the READER — retrospective)
                                         │
                    ┌────────────────────┼─────────────────────┐
                    ▼                    ▼                     ▼
            p95 recycle fill      wall-hit count        per-session verdict
            (AC-1)                (AC-2)                (AC-3)
```

Three properties this shape has and the incumbent cannot:

1. **Retrospective.** The reader works over all 4,890 historical transcripts the moment it lands.
   No soak period, no accrual, no "measurable for the first time going forward".
2. **Self-describing (R5).** Every record carries its denominator, so no consumer can mis-scale it
   — the error I made myself in Phase 1 becomes structurally unmakeable.
3. **No new actuator.** V2 adds **zero** new firing paths. The subsystem's problem was never too
   few triggers; it was 31,366 evaluations with no idea whether they helped.

---

## §4 Component specifications

### 4.1 M-1 — `bin/cc-ctx-audit` (the outcome reader) · NEW

The metric producer for AC-1/AC-2/AC-3 and the acceptance reader for §7.

- **Inputs:** the 3 real `projects` roots (deduped by realpath — C1's trap), plus
  `~/.claude/autonomy/recycle-events.jsonl` (M-3) for live-stamped denominators.
- **Per session it emits:** `sid · peak_input_tokens · window (or null) · peak_fill_pct (or null
  when the denominator is unrecoverable) · compactions{auto,manual} · wall_hits · terminal_state`.
- **`null` is a first-class value, never 0** (R2/R5). A session with no recoverable window reports
  `peak_fill_pct: null` and is **excluded from the p95**, with the exclusion count printed. A p95
  computed over an imputed denominator is the exact defect §1.1 documents.
- **Wall-hit detection** = assistant text, normalised (`ascii_downcase`, trimmed), **equal to**
  `prompt is too long`. Never a substring (C8).
- **Compaction classification** = `compactMetadata.trigger` verbatim, **never inferred** (R6).
  An unrecognised trigger value is reported as itself, not folded into `manual`.
- **Bounded** (R7): byte-level `grep -l` prefilter before any `jq`, so the 4,850 transcripts with
  no compaction are never parsed.
- **Kill switch:** `CC_CTX_AUDIT=off` ⇒ exit 0 silently (R3).
- **Exit contract** (R8, and memory `named-failure-vs-no-verdict` — a non-verdict is a THIRD
  state, not a red): `0` verdict produced · `2` usage · `3` **no data / denominator unrecoverable
  for the whole window** (explicitly *not* a failure of the fleet).

### 4.2 M-2 — durable denominator in `hooks/lib/context-econ.sh`

The one-field structural fix. `ce_sample` currently appends `"ts used_pct input_tokens"` —
**three fields, none of which is the window.**

- **Fix the evidence-destroying detector.** `context-econ.sh:77-80` detects a fill drop >2pt — the
  compaction signal — and responds by **truncating the history file**, which is the only trace.
  V2 emits one IDL record (`ce_log_drop`) *before* the truncation, carrying `from_pct`, `to_pct`,
  `drop_pct`, `input_tokens` **and the window**. The truncation is correct (the slope is poisoned);
  discarding the event is not.
- **Kill switch:** `CC_CE_DROP_LOG=off` (suppresses the record, never the sample).

> **⚠ CORRECTION TO THIS SECTION AS ORIGINALLY SPECIFIED — the 4th-column plan was wrong and was
> reverted during the build.** §4.2 first specified appending the window as a **4th `.hist`
> column**. That was written, run against the suite, and **reverted on merit**: `.hist` lives in the
> *same ephemeral* `/tmp/cc-telemetry/` directory as the telemetry JSON it samples, so a 4th column
> there is exactly as unrecoverable as the value it was meant to preserve — it buys **no
> durability at all** — while breaking two passing contract tests that pin the 3-field line
> (`tests/context-econ.bats` went 27/29). The denominator is therefore captured **only where the
> store is durable**: the IDL (`ce_log_drop`, here) and the recycle-outcome store (§4.3), both under
> `$HOME`. The refutation lives in the code header too, because the next reader will reach for the
> 4th column first. `CC_CE_DENOM` was specified as this section's kill switch and **does not exist**
> — there is no 4-column behaviour left to switch off.

### 4.3 M-3 — recycle-outcome record in both hooks

At the moment a recycle decision executes, both hooks already know `used`; neither records it
durably where a reader can find it.

- Append one self-describing record to `~/.claude/autonomy/recycle-events.jsonl`:
  `{ts, sid, hook, verdict, used_pct, input_tokens, window, trigger, mode}`.
- **`verdict` is a parseable token, not the overloaded `fired`** (R8/C12): exactly one of
  `advised · shadow-would-fire · executed · nudged`. This is the field that makes "did a recycle
  happen" answerable — today it is not (§1.3).
- **SEAM — not mine to redesign (R9).** Row 2 owns `cc-fired/<pane>.json` and the recycle
  *executor* (`handoff-fire --recycle`). V2 **does not touch either**: it writes its own store in
  row 8's own namespace and consumes row 2's contract unchanged. The reader joins on `sid` when
  row 2's record is present and **degrades to transcript-only when it is absent** — which is the
  fail-soft path, since C21 shows row 2's store carries no fill field today and may never.
- **Kill switch:** `CC_RECYCLE_LOG=off`. (Corrected from the `CC_RECYCLE_EVENTS=off` first specified
  here — that name is the *path* override, which `bin/cc-ctx-audit` also reads as `CC_CTX_EVENTS`;
  overloading one variable as both a path and an off-switch is how a kill switch stops working.)
- **Bounded** (R7): pruned to `CC_RECYCLE_MAX/2` (default 5000) on overflow, the same shape
  `ce_sample` already uses for `.hist`.
- **An empty verdict is refused** — a record with no interpretable meaning is worse than no record.

### 4.4 M-4 — graveyard take: `cd064644` (session-continue IDL telemetry)

See §6. Cherry-picked with `-x`, not rewritten.

### 4.5 What V2 deliberately does NOT change

Named so the next session does not read silence as an oversight:

- **No threshold is retuned.** `T_IDLE=35`, `T_BUSY=75`, `T=73`, `CC_CE_WALL=88` are all left
  exactly as they are. They are percentages of an unrecorded denominator (§1.1); *tuning them is
  the in-frame fix this rebuild exists to reject.* They become honest the moment M-2's denominator
  makes them checkable — that is a follow-on with data, not a guess now.
- **`--busy-force` is not armed** (C17). Arming the only regime that rides high is an operator
  C10 decision with fleet blast radius, and it must not be taken on a metric that cannot yet be
  read. Named as the §7 AC-4 accrual and in the operator platter.
- **`--live` is not broadened** (C14/C16). 83% `not-armed` is the *arming* root cause
  (memory `desk-self-handoff-trigger`), and memory `universalizing-a-mechanism-promotes-its-latent-leak`
  is explicit that arming a rare mechanism fleet-wide makes its lifecycle bugs the default. Not
  before the outcome store can show whether firing helps.

---

## §5 Failure-mode coverage (every observed mode → its structural answer)

| # | Observed failure mode | Evidence | Structural answer |
|---|---|---|---|
| F1 | Fill % is uncomputable — denominator discarded | C9 (98.5%), C10 | **M-2**: window written beside every sample; **M-1** reports `null`, never an imputed value (R5) |
| F2 | The metric counts an event with no observed instance | C4, C5 | **M-1** counts the event that *does* kill (C6) and reports compactions by literal trigger, so a future real auto-compact is visible the day it happens (R1) |
| F3 | The real wall — a hard `Prompt is too long` refusal — is unmeasured | C6, C7 | **M-1** exact-match detector, positive-controlled against prose (C8) |
| F4 | Auto-compaction is assumed to be the safety net; it saved none | C7 (6/7 zero compactions) | Design stops treating compaction as recovery; the recorded outcome is the refusal, not the compaction |
| F5 | `disposition:"fired"` means four different things | §1.3, `:862/:958/:972/:1015` | **M-3** `verdict` enum — one token, one meaning (R8) |
| F6 | The deterministic recycle has never executed | C12 (0 of 32,075) | Made *visible* rather than silently assumed working: M-1's `executed` count is the un-fakeable read. Arming stays an operator call (§4.5) |
| F7 | The compaction detector destroys its own evidence | `context-econ.sh:77-80` | **M-2**: emit the IDL record before truncating |
| F8 | A recycle records no fill | C21 (0 of 135) | **M-3**, in row 8's own store, joining row 2's fail-soft (R9) |
| F9 | `boundary-handoff` has never fired in 2,173 evals | C18–C20 | Diagnosed, not patched: 2,012 are genuinely below T=73; the threshold is a % of an unrecorded denominator (F1). Retuning before M-2 lands would be the in-frame fix |
| F10 | The BUSY regime — the only one that rides high — can never exec | C17 (0 busyforce markers) | Named as an operator C10 step, platter'd in §8, **not** silently armed (§4.5) |
| F11 | A landed telemetry emitter went dark when the checkout moved | C23/C24 | **M-4** cherry-pick; §6 |
| F12 | Handed-down percentages get re-derived wrong (I did it) | withdrawn M1/M4/M5, §2 | **R5** made a numbered invariant; M-1 emits `null` + an exclusion count so a mis-scale is structurally unavailable |

---

## §6 Graveyard sweep — what was taken and what was rejected

The sweep was given the mandated **positive control first**: it must re-find the known stranded
`tests/session-continue-telemetry.bats` before any of its other output is believed. **It did** —
present on `fix/infra-perfection` and `tm/hygiene`, absent from `origin/main` and from disk.

Row 8's paths yielded exactly **two** stranded artifacts:

| Artifact | Where | Verdict |
|---|---|---|
| `hooks/session-continue.sh` IDL telemetry + `tests/session-continue-telemetry.bats` (114 lines) — commit **`cd064644`** | `fix/infra-perfection` (+4 other branches) | **TAKE** |
| `docs/research/desk-audit-2026-07-18/reobserve-waiting-recycle.md` | `cc/reobserve-waiting-recycle` | **REJECT** — a research doc superseded by this session's own Phase-1 re-derive against a 4,890-transcript population; taking it would re-import the pre-correction frame |

**Why the take is unusually well-evidenced — it is production-proven, not merely plausible.**
Memory `parallel-stream-convergence-protocol` says adjudicate supersession by running the evidence,
not by reading intent:

- The live IDL holds **208 `session-continue` records** whose disposition vocabulary is *exactly*
  the stranded commit's — `armed{cli-set}` · `fired{continue}` ·
  `cleared{kill-switch,sid-mismatch,cli-clear,cap-reached}` (C23).
- Those records **stop dead at `2026-07-27T02:39:34Z`** — when the shared checkout moved off that
  branch.
- The emitter is present on `fix/infra-perfection` (**9** matches) and **absent from both trunk
  and the deployed copy** (C24).

⇒ This is not a rejected design. It ran in production, produced 208 records, and went silent for a
deploy reason. Taken with `cherry-pick -x`. Per the campaign ruling, taken from
`fix/infra-perfection`, **never `tm/growth`** (0 unique patches, drags a 6-branch nested chain).

**TWO THINGS THE TAKE COST, both worth recording — a stranded artifact is not drop-in.**

1. **The pick conflicted, and the naive resolution would have resurrected a bug.** `session-continue.sh`
   had diverged: trunk hoisted the kill-phrase detection into a shared `kill_switch_active()` so the
   **wake floor consults the same predicate** and can never block a stop the operator asked for. The
   picked commit carried its own **inline copy**. Resolution: keep trunk's structure and graft only
   the `log_idl cleared "kill-switch"` line — taking the branch's hunk wholesale would have restored
   a *second, drifting definition* of the one predicate that must never disagree with itself. Its
   `SC_SID` was likewise aliased to trunk's existing `$cur_sid` rather than re-parsed from the same
   stdin (two independent parses of one value is how they drift). Adjudicated per memory
   `parallel-stream-convergence-protocol` — by running *their* tests against the *merged* code:
   **30/30 green** across the picked suite and the pre-existing `session-continue.bats`.
2. **The artifact predates a rule that landed after it, and the gate correctly refused it.**
   `tests/session-continue-telemetry.bats` fixtures `CLAUDE_CONFIG_DIR` and both telemetry seams but
   left **`$HOME` pointing at the operator's live `~/`** — so every seam the hook defaults to `$HOME`
   read and wrote real state (my own first verification run appended to the live IDL before the gate
   caught it). `ship-land` went **GATE RED: test-hermeticity, exit 6**. Fixed in the suite — `export
   HOME="$BATS_TEST_TMPDIR/home"` plus the fixture dirs the hook reads — **never via the allowlist**,
   which the lint explicitly forbids and memory `trunk-rule-landed-mid-gate-is-a-real-red` explains:
   a rule that landed after your artifact makes it genuinely red, and retrying cannot clear it.
   Landed as a **separate commit** from the faithful `-x` pick, so history shows both the artifact as
   it was stranded *and* exactly what today's gate required of it.

---

## §7 Acceptance criteria — disk-truth reads, not narration

Each is a command whose output decides the claim. `<W>` is the window under test.

| # | Claim | Disk-truth read | Bar |
|---|---|---|---|
| **AC-1** | p95 recycle fill is computable | `cc-ctx-audit --p95-recycle-fill --since <W>` | exits `0` with a number **and** prints the excluded-for-no-denominator count; exits `3` (non-verdict, not red) when the whole window lacks denominators |
| **AC-2** | wall-hits are counted from disk | `cc-ctx-audit --wall-hits --since <W>` | reproduces **7 sessions / 10 events** over all-time (C6) |
| **AC-3** | compactions are classified by literal trigger | `cc-ctx-audit --compactions --since all` | **39 total, 39 manual, 0 auto** (C3/C4) — and any future `auto` appears as `auto`, never folded |
| **AC-4** | a live recycle stamps its own denominator | `jq -r 'select(.verdict=="executed")\|"\(.used_pct) \(.window)"' ~/.claude/autonomy/recycle-events.jsonl` | every `executed` row has a **non-null** `window`. **ACCRUING** — 0 rows until an exec path is armed (C17), which is an operator call |
| **AC-5** | the compaction event is no longer discarded | `jq -r 'select(.hook=="context-econ" and .reason=="fill-drop")' ~/.claude/autonomy/idl.jsonl` | ≥1 record after the next observed drop; **ACCRUING** |
| **AC-6** | the graveyard take is live | `git ls-tree origin/main -- tests/session-continue-telemetry.bats` **and** `grep -c CONTINUE_IDL hooks/session-continue.sh` | both non-empty / ≥1 |
| **AC-7** | every new mechanism has a kill switch | `for v in CC_CTX_AUDIT CC_CE_DENOM CC_RECYCLE_EVENTS; do grep -rq "$v" bin/ hooks/; done` | all present (R3) |

**Honest accrual note.** AC-4 and AC-5 are **time-dependent by construction** and are reported as
ACCRUING, not as green. AC-1/2/3/6/7 are provable the moment the code lands, because the reader is
retrospective (§3 property 1) — which is the whole reason the architecture was inverted.

---

## §8 Rejected alternatives (and why)

Recorded so none of these is relitigated.

| Rejected | Why |
|---|---|
| **Retune the thresholds** (lower `T`, raise `CC_CE_WALL` to the observed ~97%) | The wall figure I would have tuned to was **my own withdrawn constant** (§2) — a percentage of a hardcoded denominator. And a design that is the old one with different constants is the in-frame fix the `ground-up` skill says to reject outright (Phase 2). Retuning is available *after* M-2 makes percentages checkable. |
| **Arm `--busy-force` fleet-wide to make the recycle finally fire** | C17 shows the BUSY exec has never been armed, so arming it is a **first-ever** fleet-wide behavior change, gated on a metric that cannot yet be read. `universalizing-a-mechanism-promotes-its-latent-leak`: arming a rare mechanism makes its lifecycle bugs the default. Operator C10 step, platter'd — not an agent action. |
| **Build the fill-% metric on `input_tokens` alone** | It is an algebraic restatement of `used_pct` (`context-econ.sh:32-38`, |Δ|≤0.50pt) and resets on compaction. Note the *asymmetry*: that makes it useless as an independent **size** proxy (which is what `proxy-must-be-independent-of-what-it-supplements` forbids) but it is the correct **numerator** for fill. What it can never supply is the denominator — which is the actual gap (§1.1). |
| **Impute the window from the model id** | C10 refutes it directly: `claude-opus-4-8` runs at both 1,000,000 and 200,000 in this fleet. Imputation would silently mis-scale by 5× — the exact error §2 withdraws. |
| **A per-request "oversize turn" guard** | Built on my withdrawn M5. Once the denominator was corrected, `e4f576f9`'s "17% kill" resolved to **85.3% of a 200K window** — an ordinary high-fill kill. The mode does not exist in the evidence; building the guard would have been a mechanism with no failure to answer. |
| **Extend row 2's `cc-fired/<pane>.json` with a fill field** | It is row 2's file and row 2 is DONE. A seam dispute, and row 2 explicitly warns its record is read by `cc-reaper` (extended *additively* for that reason). Row 8 writes its own store and joins fail-soft (R9). |
| **An ML/scored recycle policy** | Unchanged from the prior design's reasoning and still correct: untestable in bats, unauditable in the IDL, and it re-introduces the "model must notice" failure the two-stage design killed. |
| **A new Stop-hook that blocks until the session recycles** | A Stop hook cannot reach the model except by blocking — the documented infinite-loop anti-pattern in the global CLAUDE.md. |
| **Delete the 31,366 abstain records to "clean up" the IDL** | They are the evidence base for C11–C15 and the only proof the mechanism was inert. `append-only-store-safety-rules` (R7): archive is a property of the destination. |

---

## §9 Dependency posture — what this design does when a dependency is dark

Per the campaign's fail-soft rule; each is verified, not assumed (R9).

| Dependency | Owner | Existence evidence taken | Behavior when dark |
|---|---|---|---|
| `handoff-fire --recycle` (the executor) | row 2 | present; live copy is a symlink | M-3 records the **decision** regardless; the `verdict` token distinguishes `advised` from `executed`, so a dark executor is *visible in the data* rather than silently conflated (F5) |
| `cc-fired/<pane>.json` | row 2 | 135 records, **0 carry fill** (C21) | reader joins when present, degrades to transcript-only when absent — the expected case |
| session-beat liveness oracle | row 4 | **INERT** — `~/.claude/cc-beats` absent, activation has no `.done` | never consulted by this row; no dependency taken |
| `bin/cc-bats` QoS chokepoint | row 13 | present on trunk | used for the corpus run; if absent, plain `bats` with the harness-trap guard of §10 |
| operator readout surface | row 10 | present | M-1 is a CLI; it does not write to row 10's surface. A board row for wall-hits is named as a follow-on for row 10, not built here |
| statusline telemetry `/tmp/cc-telemetry` | row 10 | 74 files live | M-2 reads `.window` when present; absent ⇒ `null` ⇒ `unknown` (R2), never a guess |
| deploy pipeline | row 1 | **21 behind** (C25) | **immaterial for this row**: all 5 owned hooks are live symlinks (C26), so landing == deploying. `bin/cc-ctx-audit` is NEW, so per memory `deploy-lag-checkout-behind-origin` a per-file symlink dir never links a brand-new file ⇒ it needs one `ln -s`, platter'd in the activation step |

---

## §10 Proof discipline (the Phase 4 bar, and the two harness traps)

Binding on every test this row lands:

- **RED-proof against a pristine pre-change tree** recovered via `git archive` — never a
  hand-edited approximation (`control-must-replay-the-real-artifact`). Pin the exact failure
  **point**, not `-ne 0`, and derive the pre-fix rev rather than naming a sha that a rebase moves
  (`red-proof-environment-and-ref-fragility`).
- **A positive control beside every absence assertion** (the §1.1 window scan and the §6 sweep
  both already carry one).
- **`|| false` on every non-final `[[ ]]`/`(( ))`** — they are errexit-exempt and therefore dead
  assertions (`bats-dead-assertions-errexit-exemptions`).
- **Re-run launchd-bound artifacts under `/bin/bash`** — the Bash tool runs zsh, so repros lie.
- **`BATS_TEST_TIMEOUT` is file-level only**; in `setup()` it is a silent no-op
  (`bats-runtime-cap-placement-and-borrowed-hermeticity`).

**Trap 1 — never read a piped test run's exit code.** `bats … | tail` yields the *pipe's* status,
not bats's; this reported a clean exit 0 over two RED tests. Redirect to a file, read `$?`
unpiped, and **key the verdict on the `not ok` COUNT** (`named-failure-vs-no-verdict`).

**Trap 2 — a suite that tests a wrapper must not inherit that wrapper's state.** `bin/cc-bats`
exports `CC_BATS_ACTIVE=1`, which makes a shim-under-test short-circuit its own re-entrancy guard
(16/16 green under plain bats, 14/16 through the shim, nothing naming the harness). Any suite of
mine run *through* something it also tests must `unset` that variable in `setup()` — see
`tests/qos-chokepoint.bats` for the fixed shape.

---

## §11 Operator-owned steps (C10 / classifier-terminal — staged, never agent-run)

Platter'd with exact commands per the silver-platter rule; both are genuine operator calls.

1. **Link the new reader into the live layer.** STAGED + PLATTERED as one idempotent script in both
   the live queue and the repo SSOT (verified byte-identical, so the D-v axis-2 parity check cannot
   report drift). Why an activation exists for this one artifact when row 8's five hooks need none:
   the hooks are live symlinks (landing == deploying), but `~/.claude/bin` is a **real directory of
   per-file symlinks** — verified, not assumed (`[ -L ~/.claude/bin ]` is false; `cc-bats` and
   `cc-blockers` are individual links) — and such a directory never links a file that did not exist
   when it was populated (memory `deploy-lag-checkout-behind-origin`).

   ```
   bash /Users/chrisren/.claude/autonomy/pending-activation/20-ctx-audit-activate.sh
   ```

   The script fail-closes if the source is missing or non-executable (a dangling symlink on `PATH`
   is worse than an absent command), is a no-op when already linked, and then **effect-reads** the
   deployed copy by running it — treating exit 3 as the legitimate non-verdict it is rather than a
   failure. It prints the `touch …done` line on success.

2. **◆ Decide whether to arm the BUSY exec** (C17: never armed; the only regime that rides high).
   A judgment call with fleet blast radius, deliberately *not* taken by this row (§4.5, §8). The
   data to decide it is what M-1 now produces.

---

## §12 Landed shas (resolved from origin/main AFTER ship-land's rebase)

Every sha below was re-resolved from `origin/main` and confirmed with
`git merge-base --is-ancestor <sha> origin/main`. This matters concretely: my local commits were
`f90dc779` / `a31407e0` / `d3850024`, and **none of those names a commit on trunk** — ship-land
rebases, and rows 3 and 13 both published pre-rebase shas that named nothing. Verify by CONTENT
(`git ls-tree origin/main -- <paths>` present **and** `git diff <sha> origin/main -- <paths>` empty),
never by `rev-list --count`, which a sibling's rebase can zero while your files never arrived.

| # | What | Landed sha | Paths |
|---|---|---|---|
| B0 | Design doc (this file) | **`44cabad7`** | `docs/plans/CONTEXT_ECONOMY_V2.md` |
| B1 | M-1 outcome reader + 19 tests | **`aee9f975`** | `bin/cc-ctx-audit`, `tests/ctx-audit.bats` |
| B2 | M-2 fill-drop record + 13 tests | **`2a337c48`** | `hooks/lib/context-econ.sh`, `tests/ctx-drop-record.bats` |
| B4a | M-4 graveyard take (faithful `-x` pick of `cd064644`) | **`c6418f21`** | `hooks/session-continue.sh`, `tests/session-continue-telemetry.bats` |
| B4b | M-4 hermeticity fix the gate required | **`12a3a8ef`** | `tests/session-continue-telemetry.bats` |
| B3 | M-3 recycle-outcome record + 12 tests | **`1a21099f`** | `hooks/lib/context-econ.sh`, `hooks/waiting-recycle.sh`, `hooks/boundary-handoff.sh`, `bin/cc-ctx-audit`, `tests/ctx-recycle-record.bats` |
| B5 | Map row + plan close-out + activation | *this commit* | `docs/plans/GROUND_UP_REBUILD_MAP.md`, this file, `docs/activation/pending-activation/20-ctx-audit-activate.sh` |

**Test totals.** 44 new tests (19 M-1 · 13 M-2 · 12 M-3), each RED-proved against a pristine
`git archive` tree at a **derived** rev: **19/19 RED · 8/13 RED** (the 5 green-on-both are named as
contract-preservation in the suite header) **· 12/12 RED**. Three are **mutation** proofs — they
invert exact-match→substring, null→0, and the verdict enum→one token, and each was verified to
*misbehave at rc=0* rather than crash, so they discriminate on behaviour rather than on absence.
Full regression across all six affected suites: **`1..196`, 196 ok / 0 not ok, exit 0**, reconciled
against the `1..N` header (an earlier run exited **124 with 11 tests never executed**, which the
`not ok` count alone would have read as green).

**Deploy posture:** row 8's five owned hooks are all live symlinks into the shared checkout
(C26), so for them **landing == deploying** — no activation step, and B4a's telemetry emitter goes
live on the next checkout fast-forward. Only `bin/cc-ctx-audit` needs the one `ln` in §11, because
`~/.claude/bin` is a per-file symlink directory.

## Learnings (accumulate; never delete)

- **A metric can fail in a third way: the DENOMINATOR is discarded.** Row 2 found "no producer"
  and row 5 found "cell falsified". Row 8's numerator was durably recorded all along; the *unit*
  was not. `input_tokens` is in every transcript; `window` is in a `/tmp` file with 1.5% coverage.
  Before trusting any percentage, find where **both** halves of the ratio are written.
- **I made the exact error the row is about, and the campaign's own rule caught it.** I divided
  4,890 sessions by a hardcoded 1M, published `p95=38.7%` and "43% of kills at low fill" to the
  coordinator, and nearly designed a per-request-oversize mechanism on it. What broke it was
  re-deriving one session's raw tokens (`170,616` on a 200K-window model = 85.3%, not 17.1%). The
  lesson is R5, now a numbered invariant: **a record must carry its own units**, because a
  consumer *will* assume a constant.
- **`disposition:"fired"` meaning four things is worth more than any threshold.** Two of three
  "fires" in the whole IDL were advisories. A single overloaded token made a mechanism that has
  **never executed once in 31,366 evaluations** look like it was working.
- **Auto-compaction is not the safety net this subsystem was designed around.** 39/39 compactions
  fleet-wide are manual, and 6 of 7 killed sessions had none. The terminal state is a hard
  `Prompt is too long` refusal that no compaction prevented — the session sits dead in place,
  answering the operator's own warning with the same error.
- **A loose grep for a failure string counts your own analysis of it.** 18 files matched
  `Prompt is too long`; 7 sessions actually hit it. My own transcript was in the difference.
  Exact normalised equality, always.
- **The strongest graveyard verdict is a store that still holds the artifact's output.** 208 live
  IDL records in the stranded commit's exact vocabulary, stopping the day the checkout left the
  branch, settled "take or reject" with no reading of intent at all.
- **"Make it durable" is a question about the STORE, not about the record.** The obvious fix for a
  discarded denominator was to write it next to the number — a 4th `.hist` column. Both live in
  `/tmp`. The fix looked complete, changed the format, broke two contract tests, and preserved
  nothing. Before adding a field to fix a durability problem, check the *directory*.
- **My own lint pass was weaker than the gate's and hid a hard RED.** I checked
  `shellcheck -S warning`; the gate runs at default severity, which includes INFO, where SC2329
  ("function never invoked" — it does not recognise `trap <fn>`) is fatal. Lint at the gate's own
  severity or the check is theatre. The same turn, I read "exit code 0" from a compound command
  whose last element was `tail` — the DoD warned about exactly this shape for test runs, and it
  applies verbatim to `ship-land`: **key the verdict on content (`git ls-tree`), never on a status
  that might belong to a different command.** `ship-land` had actually exited 6.
- **A new writer's DEFAULT PATH is a hermeticity decision, and reaching past
  `CLAUDE_CONFIG_DIR` to `$HOME` breaks every fixtured caller.** Both new stores defaulted to
  `$HOME/.claude/autonomy/…`, so their `mkdir -p` created directories under the *canary HOME* that
  `waiting-recycle.bats`' fixture-isolation test plants specifically to catch this — the one genuine
  failure in a 164-test run. A hook resolves its root from `CLAUDE_CONFIG_DIR`; anything it writes
  must too. The same bug had a second face: because the store is per-config-root, the **reader** was
  looking in only one of the three roots this box uses and would have missed two thirds of the
  denominators it exists to collect.
- **`rc=124` is a NON-VERDICT for the tests that never ran.** A 164-test run reported
  `152 ok / 1 not ok` and exited 124 — my own `timeout` firing, with **11 tests never executed**.
  Read as "153 of 164 passed" that is a green; read honestly it is a partial run whose remainder is
  unknown. Keying the verdict on the `not ok` count alone is not enough — the `1..N` header must be
  reconciled against the reported count, or a timeout silently becomes a pass
  (memory `gate-never-ran-vs-gate-red`, `named-failure-vs-no-verdict`).
- **A shared box makes the QoS band the dominant term in wall-clock.** With load at 73 on ~10 cores
  (a postland corpus plus two sibling rebuilds), a `bin/cc-bats` run sat in the background band at
  test 1 of 9 after 80 seconds — starved, not hung. Row 13's one-way ratchet working exactly as
  designed. The right response is to stop adding load and wait, not to bypass the chokepoint; but a
  reader of a slow suite needs to distinguish *starved* from *wedged* before reaching for a timeout,
  and `ps -o stat=` showing `SN` is the discriminator.
