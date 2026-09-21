# A1 — the hook surface, re-partitioned. Is there a second (synchronous ∧ semantic) member?

**2026-09-21 · read-only · agent A1 of the jev-100p wave · repo `claude-infrastructure`**

> **Verdict in one line:** §3's two-member answer is *correct on its own population and wrong about
> the surface*, because that population is **18 of 89 hooks** — the ones that already instrument
> themselves. Re-partitioned over all 89, the cell has **one further member that matters**:
> `agent-teams-enforce.sh:693-698`, a hand-maintained 21-verb/22-verb keyword **count** that decides
> research-vs-implementation and can emit a **deny**. It is the only place in this repo where a
> keyword list over prose refuses a tool call. **Its base rate is unmeasurable today**, and that —
> not a Jev purchase — is the four-day deliverable.

---

## 0. What I actually re-ran, and where §3's number came from

```
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } > /tmp/idl.all
jq -r 'select(.hook)|.hook' /tmp/idl.all | sort | uniq -c | sort -rn
```

| | §3 (2026-09-18, 10.6 d) | this run (2026-09-21, wider archive) |
|---|---|---|
| rows carrying `.hook` | 154,439 | **151,116** |
| distinct hook names | **17** | **18** |

The extra name is `context-econ` at **7 rows**; `plan-agent-teams-default` sits at **10**. Both are
below any reasonable reporting floor, so 17-vs-18 is a rounding artifact and **§3's census
reproduces**. The row count moving *down* over a *wider* window is the archive rolling, not a
defect. (Note also that `/tmp/idl.all` holds **1,899,921** lines total — the vast majority carry no
`.hook` key at all. `select(.hook)` is doing real work; a naïve `wc -l` overstates the partition's
denominator by 12.6×. One line in the current `idl.jsonl` is also truncated and makes `jq` abort
without `2>/dev/null`.)

**Per-hook positive-class base rates, measured (this is what §3 does not print):**

```
anti-deference-nudge     n=5221   positive=133   rate=2.55%
completion-assert        n=4331   positive=247   rate=5.70%
dispatch-assert          n=5239   positive=18    rate=0.34%
goal-inert-watch         n=5244   positive=84    rate=1.60%
worker-claim-gate        n=877    positive=63    rate=7.18%
capacity-admit           n=1269   positive=764   rate=60.20%
```

## 🚨 1. The defect in §3's partition — the population is self-selected

`ls hooks/*.sh` → **89 hooks** (plus 33 in `hooks/lib/`). Only **18** ever write an idl row:

```
agent-teams-enforce  dispatch-assert  completion-assert  live-session-registry
plan-agent-teams-default  escalation-watch  context-econ  operator-readout
stop-failure-marker  anti-deference-nudge  boundary-handoff  session-continue
desk-brief-inject  waiting-recycle  goal-inert-watch  session-register
subagent-stop  validate-bash
```

**The other 71 hooks are structurally invisible to a partition computed from `idl.jsonl`.** That set
includes the two highest-traffic PreToolUse hooks in the fleet (`backup-before-write`,
`smart-bash-allowlist`) and every UserPromptSubmit nudge. §3 partitioned "154,439 hook decisions
across 17 hooks" — the decisions it could *see*, which is a fact about our instrumentation, not
about the surface. This is the same shape as
`.claude/rules/…#checker-population-rests-on-an-untested-belief`: **when a checker enumerates where
to look, falsify the sentence that justifies the enumeration.**

Worse for the specific question asked: `agent-teams-enforce.sh` *appears* in the list above, but it
logs only from its spawn-budget / lineage / claim-gate arms (`spawn-budget` 324, `spawn-lineage`
1,075, `worker-claim-gate` 877, `capacity-admit` 1,269). **The brief-classification arm — the only
keyword-list-over-prose decision in the file — writes nothing.** So even the hooks inside the
partition can have semantic arms the partition cannot see.

---

## 2. Ranked candidates

### Rank 1 — `hooks/agent-teams-enforce.sh:693-698` · research-vs-implementation keyword count

| field | value |
|---|---|
| **file:line** | `hooks/agent-teams-enforce.sh:693` (`IMPL_KEYWORDS`), `:694` (`RESEARCH_KEYWORDS`), `:697-698` (the two `grep -oEi \| wc -l` counts), `:701` / `:706` / `:719` (the three verdicts) |
| **what it matches today** | two hand-maintained alternation lists — 21 implementation verbs (`implement\|create.*file\|write.*code\|modify\|refactor\|add.*column\|schema\|migration\|…`) and 22 research verbs (`research\|explore\|investigate\|find\|search\|analyze\|audit\|verify\|check\|…`) — `grep -oEi` counted, then a **threshold over the counts**: `RESEARCH_COUNT > IMPL_COUNT && IMPL_COUNT <= 1` ⇒ allow; `RUN_BG && IMPL_COUNT >= 2` ⇒ **deny**; `IMPL_COUNT >= 2` ⇒ allow+nudge; else silent allow |
| **volume** | ~**904 Agent spawns / 30 d** (≈30/day) — the figure its own `:611` advisory cites |
| **measured base rate** | 🚨 **UNMEASURABLE. The arm emits no idl row and no log line.** Its three verdicts leave no trace anywhere on disk. This is the single most important finding in this document. |

**Why it is the strongest member.** It is the **only** decision in 89 hooks where a keyword list over
free prose can return `permissionDecision: "deny"`. Everything else that denies (`validate-bash`,
`rm-safe-allowlist`, `smart-bash-allowlist`, `keychain-guard`, `frontier-spawn-gate`) denies on a
parse, a path, a pid or a counter.

**Its own source confesses the precision failure.** `:676-690` adds a `RESEARCH_MARKERS` escape
hatch whose comment reads:

> *"Strong research-only markers override the keyword heuristic. Lead prepends any of these phrases
> to a research-only prompt to bypass false-positives (e.g. research about "schema", "migration
> mechanics", "Phase 0 patterns" was previously blocked because those words triggered the impl
> regex). Discriminator is the EXPLICIT marker, not the topic."*

That is a documented, shipped workaround for a matcher that cannot separate *writing a migration*
from *researching migrations* — and the workaround relocates the judgment onto the caller, who must
remember to type a magic phrase. A model reading the brief does not need the magic phrase.

**The 2–4 decomposed Jev questions** (never one "is this implementation?"):

1. `boolean` — "Will the agent receiving this brief **modify files in a repository**?"
2. `boolean` — "Does this brief name a **specific artifact the agent must produce by writing it**
   (a file, a commit, a migration), as opposed to a finding it must report?"
3. `boolean` — "Does this brief **only read, search, measure or summarise** existing material?"
4. `choice` — `{writes_code, writes_a_document_only, read_only_research, ambiguous}`

**Caller-side rule** (keeps the existing matcher as the floor — never replace a shipped deny with a
probability):
`deny` only where `RUN_BG ∧ IMPL_COUNT ≥ 2 ∧ p(q1) ≥ 0.85 ∧ choice == writes_code`;
`allow+nudge` where `IMPL_COUNT ≥ 2` but `p(q1) < 0.85` (converts today's hardest false positive from
a refusal into an advisory); and **a new arm today's matcher cannot have** — `allow+nudge` where
`IMPL_COUNT ≤ 1` but `p(q1) ≥ 0.85 ∧ ¬q3`, i.e. an implementation brief phrased entirely in research
verbs, which the count rule passes silently by construction.

**Four-day validation.**
*Corpus:* the `PROMPT` field is not stored anywhere, so **step 1 is instrumentation, not a Jev call**
— add `log_idl <verdict> impl=$IMPL_COUNT research=$RESEARCH_COUNT bg=$RUN_BG type=$SUBAGENT_TYPE`
plus a sha256 of the brief at `:701/:706/:719`. That alone answers "does this arm ever fire?" inside
24 h at ~30 spawns/day and is the cheapest possible refutation.
*Calls:* ~30/day × 4 days ≈ 120 live shadow calls (well inside 6 calls/min), at ~1–2k state tokens
each — **under $0.01 total**.
*Headroom = any of:* (a) the matcher denies a brief Jev calls read-only at p ≥ 0.85 (a false refusal
that cost a wave); (b) the matcher silently allows a brief Jev calls `writes_code` at p ≥ 0.85 (the
arm the count rule cannot express); (c) the `RESEARCH_MARKERS` hatch fires — every firing is a
caller working around the matcher, and its rate is the matcher's error rate measured for free.
*What counts as no headroom:* 0 disagreements at p ≥ 0.85 over 120 spawns, or a base rate of `deny`
that turns out to be literally 0 (in which case the arm is inert and the question is moot).

⚠️ **Privacy, stated not buried.** The input is an agent-authored brief. Briefs in this fleet
routinely quote customer material — the resident mission board is itself pasted into briefs. A
shadow run must send a **redacted** brief (verbs + structure) or be restricted to spawns whose cwd is
this repo. This is a real constraint, not a formality.

---

### Rank 2 — `hooks/completion-assert.sh:250-273` · the `no-close-tell` gate

| field | value |
|---|---|
| **file:line** | `hooks/completion-assert.sh:255` (`CA_SETTLED`), `:256` (`CA_RETRACT`), `:271-273` (the gate: `grep -iqE "$CLOSE"` ∨ first-line `grep -iqE "$CA_SETTLED"`, else `abstain "no-close-tell"`) |
| **what it matches today** | a fixed token list — `✅\|safe to close\|good to close\|^[^A-Za-z]*yes\|complete\|all done\|nothing (left\|more) to do` — over the assistant's final message |
| **measured base rate** | **2,918 / 4,331 = 67.4% abstain `no-close-tell`**; hook-wide positive class **247 / 4,331 = 5.70%** |

Every one of D1–D7 sits *downstream* of this gate, so a miss here silently disarms seven arms at
once. The file documents two real misses in its own comments:

- `:266` — *"the real 2026-08-01 exchange answered 'Good to close?' with 'Yes — with one thing still
  parked.', which contains no CLOSE token at all and would abstain here as 'no-close-tell' — i.e. the
  D3 defect was structurally unreachable behind this gate."*
- `:1058` — a **13.5 h window** in which the hook emitted *"nothing at all (no-close-tell)"* and
  *"the one close that mattered could end without"* firing.

**Jev questions:** (1) "Is this message the author's **final report on a unit of work**, rather than
mid-task narration?" (2) "Does it **assert the work is finished**?" (3) `choice`
`{close_complete, close_handback, blocked_ask, midwork_progress}`.
**Caller rule:** run D1–D7 when `p(q1) ≥ τ ∨ CLOSE ∨ CA_SETTLED` — strictly widening, never
narrowing, so a Jev outage degrades to today's behaviour exactly.

**Why it is rank 2 and not rank 1.** Addendum 4 already sent **198 real closing messages** to Jev
under standard retention and the decision packet `c3752f5fca96` was actioned **`off`**. Re-opening
this input re-opens a privacy question that was closed *by evidence three days ago*. And the value
is ambiguous in a way rank 1's is not: widening the gate produces **more nags**, and `false-done`
already fires 247 times. Whether their absence would be noticed is exactly what Addendum 4 failed to
establish for the sibling arm.

---

### Rank 3 — `scripts/handoff-fire.sh:5678-5710` · `check_goal_arm` pre-arm validation

Not a hook (it is a pre-fire gate), included because it is the best **non-transcript** candidate on
the whole surface and the brief's envelope makes that decisive.

| field | value |
|---|---|
| **file:line** | `handoff-fire.sh:5694` (multi-line refusal), `:5702` (leading-slash refusal), `:5709` (char-cap refusal). **Three arms, all structural.** |
| **what it enforces vs. what it checks** | CLAUDE.md requires a `/goal` condition to carry **three semantic parts** — *one measurable end state · the check that proves it · the constraint that must hold* — and warns that *"a condition naming an activity rather than an end state never terminates."* `check_goal_arm` tests **none of the three.** |
| **corpus, on disk, today** | **131 distinct filled real goal conditions**, recovered from our own `~/.claude/logs/bash-commands.log` + its `.gz` rotations (729 `--goal` occurrences; 140 distinct strings; 9 are unfilled templates). Min 22 / p50 231 / max 402 chars — every one fits Jev's 32k state ceiling ~80× over. |
| **measured base rate, by regex proxy** | names a printed proof (`` ` ``/`prints`/`rev-list`/`exit 0`): **48/131 = 36.6%**. Carries a constraint (`do not`/`never`/`without`): **51/131 = 38.9%**. Both sit in the tractable middle — neither ~0 nor ~1. |

**Jev questions:** (1) `boolean` "Does this describe a **state that is either true or false at a
single moment**, rather than an activity to perform?" (2) `boolean` "Does it name a **specific
command or output** whose result would settle it?" (3) `boolean` "Could a reader **with no tools**,
seeing only what the session prints, decide it?" (4) `boolean` "Does it state a constraint that must
hold?"
**Caller rule:** `emit_fire_refusal payload-goal-arm-activity` when `p(q1) < 0.30`; warn (never
refuse) when `p(q2) < 0.40`; the constraint arm is advisory only.

**Zero privacy exposure** — a goal condition is a sentence about our own build, written by an agent,
recovered from our own command log. It sends no transcript, no mailbox, no customer data. It is the
only candidate in this document that needs no redaction step.

⚠️ **Honest counterweight, and it is large.** CLAUDE.md's headline number — **434 of 641 goals
(67.7%) armed and never evaluated once** — is attributed there to sessions never reaching a Stop
(**414 of 434, 95%, died mid-turn**), *not* to malformed conditions. So this lever does not touch
that number. The failure it does touch is the other one: a goal that evaluates forever and never
clears. `goal-inert-watch` measures that at **84 / 5,244 = 1.6%** (65 `goal-inert:named`, 19
`goal-inert:blind`). Low, and only ~21 conditions/day are authored. Real, small, cheap.

---

### Rank 4 — `scripts/rules-hook-budget-lint.sh:80-96` · hook-vs-label

The lint's three refusals are **bodyless link** (`](.)`), **over budget** (>420 chars), and
**duplicate target** — all structural. The rule it exists to enforce is stated one tier up, in the
always-loaded rules file itself: *"Why the hook may not degrade into a label. `Empty vs no-surface —
two states look alike` names a topic and teaches nothing… the second is what belongs here."* **No
arm checks that.** A 350-char label passes the budget as cleanly as a 350-char rule.

**And I measured that the budget is orthogonal to the axis it is standing in for.** Over the 147
linkable bullets in `.claude/rules/agent-operating-lessons.md` (n=147, min 60 / p50 236 / p90 291 /
max 329 chars), the *shortest* stratum is uniformly rule-shaped:

```
 88  [Recovery needs hysteresis] one healthy sample re-arming kills every damping layer above
 98  [Burst vs aggregate] a daily rate hides a live burst ⇒ count over MINUTES; read 1/5/15 direction
105  [Name enlists you] a gate globbing `*redproof*` conscripts any file so named — grep globs BEFORE naming
```

So length neither predicts nor proxies label-ness — which is exactly why a char budget cannot
substitute for the judgment.

**Corpus:** 169 bullets in the rules file + ~167 lines of `MEMORY.md`, both on trunk, both zero-risk.
**Jev:** `boolean` "Does this sentence state a rule specific enough to act on without opening the
link?" + `boolean` "Does it only name a topic or a contrast?" + `choice {rule, label, mixed}`.
**Why rank 4:** the file has *already been cleaned* (190,960 → ~43K chars), so the surviving positive
class is plausibly near 0 — refutation (b) — and volume is one run per land, not per turn. The real
payoff is prospective (the *next* bullet), which no four-day run can measure.

---

## 3. Disqualified, each with the measurement that kills it

| hook / decision | why it is not a member |
|---|---|
| `hooks/lib/smart-bash-allowlist.py` (1,167 lines) + `validate-bash.sh` (2,031 lines) | **(c) structural.** It is a shell *parser* — `split_segments`, `strip_heredocs`, `extract_substitutions`, a verb table, a settings fence. And the polarity is fatal: a safety gate that fails open on a probability is strictly worse than a regex that fails closed. Jev returns 0–1; a deny needs a decision. |
| `dispatch-assert` | **(b) base rate 0.34%** (18 fired / 5,239; `no-naming-tell` 4,981 = 95.1%). Inert by construction. |
| `waiting-recycle` (109,990 rows, 72.8% of the partition), `session-continue`, `boundary-handoff`, `operator-readout`, `session-register`, `live-session-registry`, `stop-failure-marker`, `subagent-stop` | **(c)** — §3 is right. A fill %, a git read, a stamp, a pid, a turn counter. Re-verified: `stop-failure-marker` is 100% `fired` (587 `marker-appended` + 39 `marker-opened`) — it is an *emitter*, not a decider. |
| `capacity-admit` | 60.2% positive — the healthiest base rate on the board — but **(c)**: it is an arithmetic read of quota headroom. No model improves a subtraction. |
| `hooks/memory-nudge.sh` (542 lines) | **Makes no decision at all.** It emits one fixed 1,400-char `NUDGE` string on a turn counter (`nudge-${SID}.count`). The anti-capture list is *inside the emitted text*, addressed to the model — it is never evaluated by the hook. Not a candidate; not even a classifier. |
| `hooks/escalation-watch.sh` | An **aggregator** — it counts and renders classes (`handoff-alarm`, `announce-alarm`, `page`, `mail-deadletter`) that other components already decided. Its greps are in its `--selftest`, not its decision path. |
| `research-precognition-nudge.sh:20`, `handoff-intent-nudge.sh:40` | Single `grep -qiE` over the **operator's own prompt** — refutation **(a)**: the operator says "research X" or "handoff" in words the regex matches at high precision, and a miss costs one advisory line. 25 and 45 lines respectively; neither logs, so neither has a measurable rate. |
| `plan-agent-teams-default.sh:234`, `validate-plan-structure.sh:100-115` | Semantic-adjacent (*"does this plan have 2+ code-writing tasks?"*) over a non-private artifact — but **10 idl rows total** across the archive. No population to validate against. |
| `curl-gate-scope`, `relay-verbatim`, `push-critical`, `keychain-guard`, `harvest-skill-end` | **Zero `grep -qE` over prose** between them. Structural throughout. |
| Anything reading `~/.claude/projects/**` transcripts | **(e)** under this wave's standing refusal. Noted as a tension the wave should settle explicitly: Addendum 3/4 *did* send 198 real closing messages. A per-call live snippet the hook already holds is a different object from a bulk corpus export, and the envelope does not distinguish them. |

---

## 4. Adversarial self-pass — what a hostile reviewer would say I missed

**"You assumed the idl log is the surface, exactly like §3 did."** I did not, and that is §1 — but the
correction has a cost I should name: **for the 71 uninstrumented hooks I have no base rates at all**,
so rank 1 is ranked on *consequence* and *shape*, not on a measured positive class. That is a weaker
footing than rank 2's 5.70%, and I have said so rather than manufacturing a number. It is also
precisely why rank 1's four-day plan **starts with instrumentation and not with a Jev call**.

**"Your rank-1 base rate could be zero, which is refutation (b)."** It could. If `IMPL_COUNT ≥ 2 ∧
RUN_BG` has never once been true, the arm is inert and rank 1 collapses to rank 2. One `log_idl`
line settles it in 24 hours for zero dollars, which is a better trade than any measurement in this
document.

**"You never checked whether Jev's domain-reputation anchoring bites here."** I checked and it is the
one disqualifier that does **not** apply to ranks 1, 3 and 4: there is no reputable wrapper around
hostile content, because there is no wrapper — the payload is a bare sentence with no host, no URL
and no brand. It *would* bite a hypothetical arm judging fetched web content, and no such hook
exists on this surface.

**"You did not verify §3's raw number before building on it."** I did — §0. It reproduces to within
2.2% over a different window, and the 17-vs-18 discrepancy is a 7-row hook. Per
`[Probe the OLD binary too]`, a disagreement between two counts is not evidence until both arms are
run; both are run above.

**"Length p50=236 against a 420 budget means the budget never bites — so rank 4's lint is inert
anyway."** Correct, and stronger than I first had it: **max = 329 chars**, so *not one bullet in the
file is within 91 chars of the cap.* The over-budget arm has never fired on the current corpus. That
demotes rank 4 further than its own base rate does — it is a gate that is already unreachable, which
is the `[Alarm polarity]` failure, not a Jev-shaped opportunity.

---

## 5. VERDICT

**The surface is not closed, and the second member is `agent-teams-enforce.sh:693-698`.** §3's
partition reproduces exactly but was computed over the 18 hooks that instrument themselves, i.e. 20%
of the 89-hook surface, and the arm it missed is the single decision in this repo where two
hand-maintained verb lists and a count threshold over agent-written prose can **deny a tool call** —
with the file's own source carrying a shipped workaround (`RESEARCH_MARKERS`, `:676-690`) that exists
solely because the matcher cannot tell *writing a migration* from *researching migrations*. It is ~30
decisions/day, not 14,570, so §4 rank 1's "a hook runs unattended 14,570 times/day" framing does not
transfer and should not be reused; what carries it instead is blast radius — each spawn is a wave's
worth of work, and a false deny is paid in full. **But I will not recommend buying anything on it,
because its positive class has never been measured: the arm writes no idl row, no log line and no
trace of any kind.** The correct four-day move is therefore one line of instrumentation at `:701`,
`:706` and `:719` — which costs nothing, needs no Jev call, needs no privacy ruling, and either
produces the population that makes a 120-call shadow run meaningful or proves the arm inert and
closes the hook surface for good. If the wave wants a candidate that can be run *today* with zero
redaction and zero privacy exposure, take rank 3 instead: 131 real `--goal` conditions are already on
disk in our own command log, with base rates of 36.6% and 38.9% on the two clauses a regex can
proxy — small, honest, and the only item here whose corpus needs no ruling from anyone.

---

## Re-derive, never re-quote

```bash
# §0 — the partition, and the 18th name
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } > /tmp/idl.all
jq -r 'select(.hook)|.hook' /tmp/idl.all 2>/dev/null | sort | uniq -c | sort -rn

# §1 — the 71 hooks the partition cannot see
comm -23 <(ls hooks/*.sh | sed 's|hooks/||' | sort) \
         <(grep -ln 'idl-log\|idl_log\|idl\.jsonl' hooks/*.sh | sed 's|hooks/||' | sort) | wc -l

# §0 — per-hook positive-class base rate
jq -r 'select(.hook=="completion-assert")|"\(.disposition)\t\(.reason//"-")"' /tmp/idl.all \
  | sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn

# rank 3 — the 131-condition corpus, from our own command log (no transcript)
{ gunzip -c ~/.claude/logs/bash-commands.log.*.gz; cat ~/.claude/logs/bash-commands.log; } \
  | grep -oE -- "--goal [\"'][^\"']{20,400}[\"']" | sed -E "s/^--goal [\"']//; s/[\"']$//" \
  | sort -u | grep -v '<[a-z]' | tee /tmp/goals.real.txt | wc -l
grep -cE '`|prints|printed|rev-list|exit 0|reads ' /tmp/goals.real.txt   # 48
grep -cE 'do not|never |without ' /tmp/goals.real.txt                    # 51

# rank 4 — hook length distribution vs the 420 budget
grep -E '^- \*{0,2}\[' .claude/rules/agent-operating-lessons.md \
  | sed -E 's/^- \*{0,2}\[[^]]*\]\([^)]*\)[ —-]*//' | awk '{print length}' | sort -n \
  | awk '{a[NR]=$1} END{print "n="NR,"min="a[1],"p50="a[int(NR/2)],"p90="a[int(NR*0.9)],"max="a[NR]}'
```

**Method warnings for whoever re-runs this.** `zcat` returns empty on BSD (appends `.Z`) — use
`gunzip -c`. One row in the live `idl.jsonl` is truncated mid-write and aborts `jq` without
`2>/dev/null`. `idl.jsonl` rows are keyed `disposition`/`reason`, **not** `verdict` — a `.verdict`
query returns `null` on all 4,331 completion-assert rows and reads exactly like "this hook records
nothing."
