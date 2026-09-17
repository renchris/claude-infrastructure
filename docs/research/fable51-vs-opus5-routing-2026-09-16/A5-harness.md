# A5 — What breaks in THIS harness if the default model becomes `claude-fable-5-1` at low/medium effort

Axis: harness/infrastructure blast radius only. Read-only investigation, 2026-09-16.
Every claim tagged MEASURED-THIS-SESSION / MEASURED-BY-US(prior, cited) / QUOTED(vendor) / ASSUMED.

**Headline.** The five things that break worst are NOT the seven behaviour deltas. They are the
routing, metering and probe paths that key on the string `claude-fable-5*` and today mean
"this is the expensive opt-in tier, treat it specially". Flip the default and every one of them
fires on every session — halving routable capacity, disarming recycle account re-picking, turning a
per-fire liveness probe into a ~$1/account charge, and throttling ordinary subagent spawns at 6.

---

## RANK 1 — BLOCKER. The Fable sub-cap is HALF the weekly cap, and every fire would route against it

- `scripts/handoff-fire.sh:9030` — `ranked_accounts()` does
  `case "$MODEL" in claude-fable-5*) kind=fable ;; esac`, then `claude-accounts --rank "$kind"`.
  So **every** fire / handoff / recycle would rank accounts on the Fable lane.
- `bin/claude-accounts:3481` — `f_eff = min(F["coupling"] * max(0.0, 1 - fable_pct/100), w_rem)`.
- `accounts.json:34` — `"coupling": 0.5`, with its own `_` note: *"coupling = fable_cap/weekly_cap
  per SSOT '<=50% of weekly usage limits'"*. (MEASURED-BY-US, config on disk.)
- `bin/claude-accounts:3483` — `if f_eff <= R["FABLE_FLOOR"]: return None, "fable-exhausted"`.
- `scripts/handoff-fire.sh:9038-9041` — rank exit 2 ("NO account routable") makes the caller
  **HALT rather than fire blind**.

MEASURED THIS SESSION (`claude-accounts --json`, 2026-09-16):

| acct | weekly % | fable % |
|---|---|---|
| next  | 94 | 7 |
| next2 | 100 | 76 |
| next3 | 6 | 0 |
| next4 | 40 | 13 |

Fable meters are near-idle **because Fable is opt-in today**. Under a default flip, fable_pct rises
with ordinary work against a denominator half the size, so `f_eff` is structurally `min(0.5·x, y)`
— a strictly tighter constraint than the general lane and never a looser one. `--rank fable` can
never return more routable accounts than `--rank general`; today both return 3 of 4
(MEASURED THIS SESSION), and `next2` is already `fable-exhausted` at 76%.

**Effect:** the fleet's dispatchable capacity is roughly halved, and the failure mode is a HALT
(`✗ claude-accounts: NO account routable for fable`), not a degrade. This is not a behaviour delta
you can prompt around.

## RANK 2 — BLOCKER. `frontier-spawn-gate.sh` would throttle ordinary Agent spawns at 6/session

`hooks/frontier-spawn-gate.sh` is `PreToolUse` on the `Agent` matcher (confirmed in the live
`~/.claude/settings.json`).

- `:37-40` — `case "$req_model" in fable|claude-fable-5*|"$fmodel") ;; *) exit 0 ;; esac`.
  The prefix arm exists deliberately (`:29-36`) so a pinned prior id cannot silently disarm the cap.
- `:50-51` — `cap = max_fable_spawns_per_session` → **6** (`model-config.yaml:692`).
- `:66-69` — at cap: **`exit 2`** with
  *"Do NOT retry: park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's
  wrap-up batch runs them."*

Nuance that makes this partly survivable and partly worse: `:23` exits 0 when `.tool_input.model`
is EMPTY, so a bare `Agent({name})` with no model is untouched. But every path that names the model
explicitly is gated — and this repo's agents name it: `agents/deep-research.md:4 model: opus`,
`agents/frontier-derivation.md:5 model: opus`, plus the documented call-time `model: "fable"`
overrides in `commands/research.md:85`. If the flip is done by making `fable` the resolved default
of the `opus` family alias, or by pinning the id in briefs, a 10-subagent research wave
(`CLAUDE.md` default N=10) **denies spawns 7-10** and tells the agent to file frontier holes for
ordinary research. That is a cap designed for bounded discovery escalation being applied to routine
work, with a refusal message that is actively misleading.

REQUIRED COMPANION: the gate must distinguish "frontier ESCALATION above the default" from
"the default tier", i.e. gate on `req_model != default_model`, not on the fable family string.

## RANK 3 — BLOCKER (cost). Every fire's account probe becomes a Fable probe at ~$1/account

`scripts/handoff-fire.sh:9153-9157`:
```
probe_account() { local dir out probe_model="claude-haiku-4-5"
  case "$MODEL" in claude-fable-5*) probe_model="$MODEL" ;; esac
```
The comment below it is OUR OWN MEASUREMENT (MEASURED-BY-US, 2026-09-08, 2.1.260, recorded at
`:9166-9172`): *"four consecutive Fable 5.1 probes, one per account, each returned a result carrying
`"stop_reason":"end_turn"` ... and **~1 USD of cache creation**"*.

Today that is paid only on an explicit `--model fable` fire. Under a default flip it is paid on the
account probe of **every** fire and every recycle — up to 4 accounts per decision. A wave of 5 fires
is up to ~$20 in liveness probes alone, before any work. The haiku probe it replaces is ~free.

REQUIRED COMPANION: pin `probe_model` to haiku unless the fire is a genuine frontier ESCALATION.

## RANK 4 — BLOCKER. `--recycle` loses account re-picking fleet-wide

`scripts/handoff-fire.sh:8765` inside `recycle_repick()`:
```
case "${MODEL:-}" in claude-fable-5*) return 0 ;; esac   # frontier pane: leave it where it is
```
Rationale on `:8758-8761` is correct TODAY — *"Fable rides a SEPARATE entitlement ... so a frontier
recycle is left exactly where it is."* If fable is the default, this early-return fires on every
recycle on the box, so `♻ recycle RE-PICK` never happens again and every recycled pane stays pinned
to the account it was on. That silently disables the use-it-or-lose-it rebalancing the ranker exists
for (and which `bin/claude-accounts:1715`'s `headroom / T**γ` scorer was built to express).

## RANK 5 — REQUIRED-COMPANION-CHANGE. The close contract is a LEXICAL demand on chat prose, calibrated on an Opus-5 corpus

Delta #3 ("LESS formatting in chat") and #5 ("denser prose") collide with three mechanical Stop-hook
demands that block:

- `hooks/lib/close-shape.sh:73` — `_CS_VERDICT='good[[:space:]]+to[[:space:]]+close'`. The close
  must contain that literal phrase with a non-placeholder value.
- `hooks/completion-assert.sh:1042-1046` — **line 1 must CONTAIN the ledger's rung EMOJI**
  (`case "$ca_first" in *"$RUNG"*) : ;; *) _d6_missing="… line-1-rung" ;;`).
- `hooks/lib/close-shape.sh:176-206` (`close_act_missing`) — when an act is required, a line
  carrying the literal `▶` or `^…act:` must appear within `CC_ACT_WINDOW` (default **3**)
  non-blank, non-fenced lines.

Enforcement is real: `hooks/completion-assert.sh:1158-1161` gives D6 class `shape`
(`COMPLETION_SHAPE_MAX`, default **2**) and D7 class `act` (`COMPLETION_ACT_MAX`, default 2), each
emitting `decision:"block"`, i.e. a forced extra turn.

The calibration is the load-bearing part. Every constant in these two files is derived from a
measured corpus of **this fleet's own closes** — 613 closes for the verdict rule
(`close-shape.sh:60-62`), 300 for the act-line position rule (`close-shape.sh:139-151`), 998 for the
deleted word cap (`CLAUDE.global.md` § close message). Those corpora were collected 2026-08-23;
`roles.lead_default` has been `claude-opus-5` since 2026-08-01 (`model-config.yaml:43,589`). So the
distribution the matchers were tuned against is an **Opus-5 output distribution** (MEASURED dates;
the model attribution is DERIVED from those dates, not stated in `docs/research/close-shape-2026-08-23.md`).

**Effect:** a model that writes denser, less-formatted chat would fail the glyph and the `▶` line
more often, costing up to 4 blocked stops per close, and — worse — every future re-tuning of those
matchers would be measuring a model that is no longer running.

## RANK 6 — REQUIRED-COMPANION-CHANGE. CLAUDE.md's own Fable carve-out COLLAPSES if Fable is the default

`CLAUDE.global.md:377-392` already anticipates 5.1 and writes the carve-out **keyed on the
default/frontier split**:

> *"Everything below stays in force on the default tier (`versions.opus_latest`); on a session
> running `frontier_access.model`, read the intent…"*

If `frontier_access.model` IS the default tier, both clauses fire on the same session and
contradict each other. The rule cannot be satisfied as written.

Quantified (MEASURED THIS SESSION, `wc -w` by line range on `CLAUDE.global.md`, 1005 lines /
14,999 words total):

| section | lines | words | share |
|---|---|---|---|
| Frontier Tier Routing | 301-304 | 209 | 1% |
| Communication Discipline | 370-420 | 964 | 6% |
| Session Close Protocol | 421-989 | 9,178 | **61%** |
| **all three** | | 10,351 | **69%** |

Communication Discipline opens *"Opus 5 runs long by default"* (`:372`) and cites the Opus 5
prompting guide at `:374`, `:409`, `:726` and `:998`. Session Close Protocol is 61% of the resident
budget and is entirely the corpus-derived close machinery above. So **~69% of the always-resident
instruction set is written against a model that would no longer be running**, of which the 6%
Communication Discipline block is explicitly documented as failing in the OPPOSITE direction on 5.1.

## RANK 7 — REQUIRED-COMPANION-CHANGE. Whole-file rewrites: the guard is ADVISORY, and the real write path routes around it entirely

Delta #7 ("whole-file rewrites for small edits") vs `hooks/backup-before-write.sh`:

- Matcher (live `~/.claude/settings.json`): `PreToolUse | Write|Edit|MultiEdit`.
- `:189-192` — the OVERWRITE GUARD is `additionalContext` prose and then **exit 0**. It backs up and
  warns. It does not block. Its own header at `:33-39` says so: *"Everything else here ends `exit 0`
  with an advisory `additionalContext`… That is exactly the shape that has failed for the MEMORY.md
  read limit twelve times."*
- The ONLY refusing branch is the memory-index budget, `:69-79`
  (`permissionDecision: "deny"` via `mib_verdict`), scoped to `MEMORY.md`.

**The escalation nobody has priced:** auto mode's standing session instruction routes ordinary file
changes through **Bash heredocs**, not Write/Edit. A `cat > file <<'EOF'` whole-file rewrite is
invisible to this matcher — no backup, no warning, no `~/.claude/backups/` copy to restore from.
This repo already has the measured precedent for exactly this class
(`.claude/rules/agent-operating-lessons.md`, cc-backlog `f5c3cfb86e2e`: *"a coverage test proves a
gate is reachable on the SURFACE it names, never that the traffic still crosses that surface"* — a
duplicate-worker lease was green for a month while every real edit went via `python3 - <<'PY'`).

So a default-model tendency toward whole-file rewrites lands on plan docs, `CLAUDE.global.md` and
memory files with the INTEGRATE-never-overwrite rule enforced by nothing but prose on the commonest
write path.

## RANK 8 — REQUIRED-COMPANION-CHANGE. The effort ladder, and the guard that is ALREADY red

`scripts/effort-parity-assert.sh` compares `effort_defaults.settings_floor` (today `high`,
`model-config.yaml:806`) against `effortLevel` in all five config dirs, and
`effort_defaults.default` against the zshrc launcher default.

MEASURED THIS SESSION (`bash scripts/effort-parity-assert.sh`, true rc **1**):
```
effort-parity-assert: SSOT floor=high launcher-default=high
  BELOW     .claude/settings.json            effortLevel=medium < floor high
  BELOW     .claude-next/settings.json       effortLevel=low    < floor high
  OK        .claude-secondary/settings.json  effortLevel=high  >= floor high
  BELOW     .claude-tertiary/settings.json   effortLevel=medium < floor high
  BELOW     .claude-quaternary/settings.json effortLevel=low    < floor high
  DRIFT     zshrc launcher  --effort default {CLAUDE_DEFAULT_EFFORT:-max} != SSOT high
```
Pre-existing, unrelated to any flip — but it is the instrument you would rely on.

The trap: adopting fable51 at `low`/`medium` means lowering `settings_floor` to match. That is not a
cosmetic edit — `settings_floor` is the only thing standing between "teammate panes, the IDE
extension and bare-binary calls" and whatever `effortLevel` happens to be on disk. Lowering it to
`low` makes 4 of 5 rows go green **and permanently disarms the only detector that can see an effort
collapse** — precisely when delta #4 (low effort suppresses search/retrieval) makes an effort
collapse most dangerous. `model-config.yaml:800-805` already records this exact failure once, in the
other direction: *"A guard that reds on the correct value trains you to ignore it."*

Also note the SSOT's own measured record contradicts choosing `low`:
`model-config.yaml:848-852` — `fable51_cheap: low` scored **6/36**, *"the lowest arm at EVERY
threshold (−4 vs medium). A cost tier, NOT a free win: keep it off grounding-heavy review; pair with
a search nudge (low suppresses retrieval)"*. `medium` and `high` both scored 10/36.
(MEASURED-BY-US, `docs/research/fable51-effort-sweep-2026-09-10/README.md`.)

## RANK 9 — REQUIRED-COMPANION-CHANGE. `cc-upgrade-gate` check 05 hardcodes BOTH the model and the effort

`lib/cc-upgrade-gate/check05_launcher.sh:122-126`:
```
case "$argv_main" in *"--model claude-opus-5"*)  : ;; *) miss="$miss model" ;; esac
case "$argv_main" in *"--effort high"*)          : ;; *) miss="$miss effort" ;; esac
case "$argv_main" in *"--permission-mode auto"*) : ;; *) miss="$miss permission-mode" ;; esac
```
→ `emit_result 05 launcher-resolution FAIL` (`:127-131`), and the PASS string at `:169` restates
both literals. The proposal breaks **two of the four** asserted properties. `cc-upgrade-gate` is the
13-check gate that certifies a CC binary bump, so this goes red and stays red until edited — and a
permanently-red upgrade gate is the same "trains you to ignore it" failure as above.

Related literal sites that would need the same manual edit (`claude-bump-models` cannot reach them —
`templates/model-classification.json`'s `update` list covers only `agents/*.md`, `README.md`, plans
and memory; NOT `bin/`, `scripts/`, `hooks/`, `lib/`):
`scripts/handoff-fire.sh:8711` (fallback literal), `scripts/limit-recover/lr-fire-resume.sh:245`,
`bin/reso-resume-one:389`, `bin/cc-route:276` + its selftest `:333` (already stale at
`claude-fable-5`), `bin/cc-wave-plan:866,936`.

## RANK 10 — REQUIRED-COMPANION-CHANGE. Delta #4 (answers from memory at `low`) has NO mechanical backstop

The Follow-On Gate F2 conviction protocol is the fleet's only mechanism that demands disk-truth
investigation. Its enforcement is **form-only**:

`bin/cc-backlog:1233-1245` (byte-identical twin at `bin/cc-decide:104-116`):
```
valid_receipt() { ... [ -f "$r" ] && return 0
  case "$r" in *" => "*) l="${r%% => *}"; o="${r#* => }"; ... [ -n "$l" ] && [ -n "$o" ] && return 0 ;; esac
  return 1; }
```
A receipt passes if it is an existing file path **or any string containing " => " with non-empty
sides**. `"grep foo bar => 3 hits"` passes without a single read having happened. The conviction gate
(`bin/cc-backlog:1982-1992`) likewise only range-checks an integer.

So the protocol that CLAUDE.md describes as *"mechanical, not prose"* is mechanical about the SHAPE
of the claim and blind to whether any retrieval occurred. Pairing a low-effort default with that is
the one combination the SSOT itself warns about (`model-config.yaml:834-836`: *"at `low` it calls
search and retrieval tools LESS (add a verification nudge for anything needing fresh information)"*).

REQUIRED COMPANION if `low` is adopted: the "search nudge" the SSOT prescribes, plus at minimum
requiring `--receipt` to resolve to an existing path (drop the free-text `=>` form) on
`needs-human` adds.

## RANK 11 — NOTE. Schema slots: an uncompelled `StructuredOutput` reads as NULL and buys a re-run

`model-config.yaml:141-153` already settles the 400 risk (the client demotes `tool_choice:{type:tool}`
to `auto` because thinking is always-on, so no request ever 400s) and names the residue:
*"`auto` does not COMPEL the StructuredOutput call, so a schema-bearing agent now depends on the
Workflow layer's validate-and-retry."* (QUOTED from our SSOT's read of the binary; the binary read
itself is MEASURED-BY-US 2026-09-03.)

The harness consumer is `scripts/limit-recover/lr-audit.py`, which keys its verdict on whether a
`StructuredOutput` tool_use exists in the agent's jsonl (`:326`, `:358-370`):
- validated but unjournaled → `COMPLETE_SALVAGED` (usable)
- absent → **`NULL`** → `commands/limit-recover.md:138-146` prescribes a re-run.

And `limit-recover.md:146`'s stall policy allows **AT MOST ONE re-fire**. So an elevated
schema-miss rate spends quota on re-runs and, at the second miss, convicts the REQUEST. This is
already live for the 5 fable roles (`workflow_judge`, `eval_judge`, `research_adversarial`,
`teammate_frontier`, `frontier_discovery`); a default flip extends it to all 13.

## RANK 12 — NOTE, and it is the one that makes the decision hard to REVERSE

Delta #6, thinking blocks are model-bound **one-directionally** (`model-config.yaml:153-157`):
5.1 reads earlier models' blocks; **no earlier model reads 5.1's**, and drops are SILENT unless the
client sends `thinking-binding-controls-2026-08-01` and you read `input_transformations`.

What moves a conversation across models in this fleet:
- `claude --resume` → `claude()` in `~/.zshrc:499,503` passes `--model "${CLAUDE_NEXT_MODEL:-claude-opus-5}"`,
  i.e. whatever the launcher's CURRENT default is, not what the session originally ran.
  `lib/cc-resume-shell.sh` does no model handling at all (grep: zero `model` hits).
- `handoff-fire.sh --recycle --resume-launcher` (`:8994-8996`) relaunches via a generated launcher.
- limit-recover transplant (`scripts/limit-recover/lr-fire-resume.sh:231`,
  `scripts/limit-recover/lr-handoff.sh:564`) — both already carry `claude-fable-5-1` arms.

**Forward flip is safe** (opus-5 blocks read fine on 5.1). **Rolling back is not**: after a flip,
every resume/recycle/transplant of a 5.1 session under an opus default silently discards its
reasoning, with no tell. The frontier fallback path has the same polarity today
(`frontier_access.fallback: claude-opus-5`, `model-config.yaml:509`) but touches ~5 roles; a default
flip makes it the whole fleet.

## RANK 13 — NOTE. The `~/.zshrc` cost warning becomes pure noise or pure silence

`~/.zshrc:489-491`:
```
if [[ " ${CLAUDE_NEXT_MODEL:-} $* " == *claude-fable-5* ]] && [[ -t 2 ]]; then
  echo "⚠️  Fable 5 session — ~2× Opus burn/token against the plan window. ..." >&2
```
Two mechanisms, two failures:
- Flip via `export CLAUDE_NEXT_MODEL=claude-fable-5-1` → the glob matches (it is a prefix glob) and
  the warning fires on **every interactive session**.
- Flip by changing the hardcoded fallback literal at `:499`/`:503` → `$*` is empty and
  `CLAUDE_NEXT_MODEL` unset → the warning **never fires again**, including on a genuine
  cost-conscious opt-in.

Same for `scripts/handoff-fire.sh:9276-9285` (`FABLE_EFFECTIVE=1` → prints the ~2× warning on every
fire). MEMORY.md `alarm-polarity-and-attention-budget`: *"an alarm that ALWAYS fires says as little
as one that cannot."*

## RANK 14 — NOTE. `claude-bump-models --apply` has no word boundary; the prefix hazard goes from ZERO exposure to live

`bin/claude-bump-models:133` — `sed -i.bump-bak "s|$OLD|$NEW|g" "$file"`. No boundary.
`scripts/claude-lint-models.sh:80` (the DETECTOR) does have one:
`grep -qE "${literal}([^-0-9]|\$)"`. So detection is safe and the FIXER is not.

`model-config.yaml:113-119` states the hazard and states the exposure: *"`claude-fable-5` is a strict
PREFIX of `claude-fable-5-1` … an `--apply` over any file already containing 5.1 would corrupt it to
`claude-fable-5-1-1`. Exposure is currently ZERO and that is a property of the CORPUS, not of the
tool."* A default flip proliferates 5.1 literals across the updatable corpus
(`agents/*.md`, `README.md`, plans, memory) and makes the corruption reachable on the next bump.

## RANK 15 — NOTE, and it CORRECTS a claim in our own CLAUDE.md

`CLAUDE.global.md:386-390` asserts: *"a Fable 5.1 pane at xhigh goes quiet while genuinely working
and quiet is what our stall/liveness surfaces read as stuck."*

Read against the code, that overstates the exposure. Every liveness sensor in this fleet is keyed on
something delta #1 does not touch:

- `hooks/lib/transcript-age.sh:24-42` — transcript **mtime**. Its own header: *"The session's JSONL
  is appended on EVERY message / tool event"*. A tool_use record is an assistant record; suppressing
  human-readable progress text does not suppress it.
- `scripts/lead-supervisor.sh:826-848` — STALL? is telemetry age (`STALL_S`, default **1800s**,
  `:137`) with an explicit **warm-transcript exemption**.
- `bin/cc-classify:985` — `CAUSE=active` on an *"in-flight tool call (unmatched trailing tool_use)
  — running, not idle (never-reap)"*, and `:894` fails safe to `active` when no timestamp is readable.
- `hooks/lib/session-busy.sh:16-22` — Q1 ("working or idling") reads the presence beat's `kind`
  field, written by `hooks/session-beat.sh` at UserPromptSubmit/Stop, not by chat output.
- `bin/cc-await-ping:485-508` — already carries the measured correction that beat AGE is a
  confounded liveness statistic and reports `seq`/`kind` instead.
- `hooks/waiting-recycle.sh` — context fill % and transcript MB, not prose volume.

None of these reads assistant TEXT. The residual real risk is a long **thinking** block with no
tool call for >1800s (thinking writes nothing to the transcript), and the SSOT says that is worst at
`xhigh`/`max` (`model-config.yaml:836-837`). **That risk runs INVERSE to the operator's proposal** —
low/medium makes it smaller, not larger. CLAUDE.md's sentence should be narrowed to name xhigh/max
and the thinking-block mechanism, not "quiet".

---

## Summary table

| # | Finding | file:line | Class |
|---|---|---|---|
| 1 | Fable lane is coupling 0.5 of weekly; all fires would rank on it; HALT on empty | handoff-fire.sh:9030 · claude-accounts:3481 · accounts.json:34 | BLOCKER |
| 2 | frontier-spawn-gate caps ordinary Agent spawns at 6, denies with a frontier-hole message | frontier-spawn-gate.sh:37-69 | BLOCKER |
| 3 | probe_account switches to the fable model: ~$1 cache creation per account per fire | handoff-fire.sh:9157 (+ measured note :9166) | BLOCKER |
| 4 | recycle_repick early-returns for fable → no account re-pick on any recycle | handoff-fire.sh:8765 | BLOCKER |
| 5 | Close contract demands rung glyph + "good to close" + `▶` line; Opus-5-calibrated corpus | close-shape.sh:73,176 · completion-assert.sh:1042,1158 | REQUIRED-COMPANION |
| 6 | CLAUDE.md's Fable carve-out is keyed on default-vs-frontier and collapses; 69% of resident words Opus-5-tuned | CLAUDE.global.md:377-392 | REQUIRED-COMPANION |
| 7 | OVERWRITE GUARD is advisory; Bash-heredoc writes bypass its matcher entirely | backup-before-write.sh:189-192 + settings matcher | REQUIRED-COMPANION |
| 8 | settings_floor lowering disarms effort-parity-assert (already rc=1 today) | effort-parity-assert.sh:92-97 · model-config.yaml:806 | REQUIRED-COMPANION |
| 9 | cc-upgrade-gate check05 hardcodes `--model claude-opus-5` AND `--effort high` | check05_launcher.sh:122-126,169 | REQUIRED-COMPANION |
| 10 | valid_receipt is form-only; no backstop for low-effort retrieval suppression | cc-backlog:1233 · cc-decide:104 | REQUIRED-COMPANION |
| 11 | Uncompelled StructuredOutput → lr-audit NULL → re-run, one re-fire max | lr-audit.py:326,358-370 · limit-recover.md:146 | NOTE |
| 12 | Thinking blocks one-directional ⇒ the flip is hard to ROLL BACK | model-config.yaml:153-157 · ~/.zshrc:499,503 | NOTE |
| 13 | zshrc + handoff-fire cost warnings become always-on or never-on | ~/.zshrc:489 · handoff-fire.sh:9276 | NOTE |
| 14 | claude-bump-models sed has no word boundary; prefix corruption becomes reachable | claude-bump-models:133 vs claude-lint-models.sh:80 | NOTE |
| 15 | Stall/liveness detectors are NOT text-keyed — CLAUDE.md overstates delta #1 | transcript-age.sh:24 · cc-classify:985 · lead-supervisor.sh:137,839 | NOTE (corrects our own doc) |

## What I could NOT determine

- Whether `versions.opus_latest` would also change. The whole blast radius pivots on the FLIP
  MECHANISM: (a) repoint the `opus` family alias, (b) change the zshrc literal, (c) export
  `CLAUDE_NEXT_MODEL`. Each hits a different subset of 1/2/13 above. Not specified in the task.
- The actual per-session Fable-meter burn rate under default-fable. The 0.5 coupling is config truth;
  the resulting exhaustion date is a projection I did not measure.
- Whether 5.1's whole-file-rewrite tendency actually manifests through Bash heredocs (the path that
  bypasses the guard) or only through the Write tool. Vendor delta list does not say; no local
  measurement exists.
- Blocked-stop rate under 5.1 for D6/D7. Determinable by running 5.1 headless over a close corpus
  and executing `close_shape_missing` / `close_act_missing` against its output — the libs are
  already hermetic (`CC_VERDICT_WINDOW`, `CC_ACT_WINDOW` seams).
