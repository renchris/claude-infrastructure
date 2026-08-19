# Does `/handoff` silently drop high-value information at every succession? — a two-round research wave

**Date:** 2026-08-19 · **Repo:** `claude-infrastructure`, worktree `.worktrees/handoff-capture`
**Plan:** `docs/plans/HANDOFF_HIGH_VALUE_CAPTURE.md` (R2 = the five questions, R4 = anti-goals,
R5 = definition of done)
**Subject file:** `commands/handoff.md` — the `/handoff` slash-command spec, 736 lines / 64,566 bytes
at `12e7e10ea`, symlinked live to `~/.claude/commands/handoff.md`. It was read but **never opened for
editing** by any agent in either round.

---

## 1. Headline verdict

**Change nothing in `commands/handoff.md`** — the verdict round 1 reached survives round 2 intact,
but on an almost entirely different evidence base: the incident that motivated the wave was a
**genuine, novel, n=1 capture** (not, as round 1 claimed, a retrieval failure over a 13-day-old
file), the work survives succession because sessions persist continuously — now demonstrated against
the only population that can falsify it — and **every reachable site for a new rule reaches fewer
authors than the unwritten convention it would replace.**

Scope qualifier, carried in the verdict rather than in a footnote: this is measured on the
**`--recycle` (same-pane) arm**, which is 96 of 694 succession-shaped ledger events (13.8%). The
new-pane fired-peer arm is structurally unmeasurable from today's instruments (§7 O1).

---

## 2. Provenance, method, and what decays

### 2.1 Method

Two rounds, read-only on tracked files throughout, adversarial by construction because the
operator's stated fear was a **false-positive change**, not a missed one.

| | agents | what they produced |
|---|---|---|
| **Round 1 — finders** | 9 (`A1`…`A9`) | bridge-corpus taxonomy · re-derivation hunt · recycle-path injection reach · reflex-vs-template · injection cost · adjacent-mechanism coverage · inherited SessionStart payload · failure modes from this file's own git history · machinery-findings census |
| **Round 1 — synthesis** | 1 (`SYNTHESIS-v1`) | verdict: change nothing |
| **Round 1 — adversarial** | 3 refuters + 1 completeness critic | all four returned **NEEDS-REVISION**; between them they refuted the synthesis's own headline |
| **Round 2 — gap-closers** | 6 (`G0`,`G1`,`G2`,`G3`,`G5`,`G6`) | adjudicate the pivotal disputed fact · the session that never hands off · prior art · the memory-pointer lever · which artifact the spec governs · make every negative control runnable and RUN it |
| **Round 2 — synthesis** | 1 (this document) | re-base the verdict on what survived |
| **Round 2 — adversarial** | 2 refuters | one returned **SOUND**, one **NEEDS-REVISION**; both left the recommendation standing |
| **Post-review corrections** | lead, in-session | six corrections applied to *this file* after the refuters read it — each marked inline with a ⚠️ block naming what was published, what is true, and who found it |

**Read the ⚠️ blocks.** Six published claims in this document were wrong and are corrected in place
rather than silently edited: the hazard-block magnitude (§R2.1), the `≤ ~30 lines` population
(§R2.3), the `e8c2435aa` date and the F5 verdict it inverts (§5 F5, §7 O4), a fourth "surviving
pillar" that was UNDECIDED (§4.1), a lever declared filed into a section that did not contain it
(§4.2 → F10), and the unexamined return direction (§7 O11). Three of the six were re-verified
independently by the lead against primary sources; the corrections are the most calibration-relevant
content here, because a wave that corrected itself twice will have residual errors of the same kind.

Round 2 was commissioned because the round-1 recommendation survived attack while several of its
**supports** did not. That asymmetry — a right answer resting on wrong reasons — is the reason this
document exists rather than a one-line "confirmed".

### 2.2 Facts with a short half-life — DATED, with decay mode and the re-derivation command

Round 1's primary evidence base lives in `/tmp` and in ring-buffered logs. **A reader more than a few
days out must re-derive these, not quote them.** The bridge corpus itself was measured decaying at
**23.6% per 9 days** (17 of 72 recorded `prompt_file` paths already gone from disk — A6 §4d).

| fact | value @ 2026-08-19 | decay mode | re-derive with |
|---|---|---|---|
| `/tmp/fire-*.txt` payload corpus | **123 files**, oldest 2026-08-14 | **total loss at reboot.** `kern.boottime` = Thu 2026-08-13 22:42:29 ⇒ the whole corpus is a **5.3-day** slice | `ls /tmp/fire-*.txt \| wc -l`; `sysctl -n kern.boottime` |
| `/tmp/*resume*.md` bridges | **6 files** | same reboot bound; **the smallest population in the wave** | `ls /tmp/*resume*.md \| wc -l` |
| `~/.claude/logs/handoffs.jsonl` | **1,007 rows**, 2026-08-10 → 2026-08-19 | **RING BUFFER — rows are DELETED.** Self-bounded to 1000, trimmed when >1200 (`scripts/handoff-fire.sh:9226`, `:9379`, `:9392`). The store is 27 days old (created 2026-07-23 by `9d722fb`); its 9-day window is a *designed trim*, not store youth | `wc -l ~/.claude/logs/handoffs.jsonl`; `head -1`/`tail -1` for the span. **Snapshot before re-running any chain analysis** |
| `prev_sid` succession chains | 96 non-null of 1,007 rows; window 2026-08-11T01:19:30Z → 2026-08-19T11:36:05Z | field first appears 2026-08-11; rows trimmed as above | `jq -r 'select(.prev_sid!=null)' …\| wc -l` |
| transcript corpus | 6,885–7,010 `.jsonl` realpath-deduped across **four** account roots | ~39-day retention; `cc-gc` prunes; **0.5–2%/day volatile** | `find -L ~/.claude{,-secondary,-tertiary,-quaternary}/projects -name '*.jsonl'` — **`-L` is mandatory**, see §2.3 |
| live CC binary | **2.1.220**, md5 `30e4d87fac9c8a6b97f4cf33397a3e30`, 256,908,272 B | auto-update replaces the image, and the minified identifiers rename (`Krt`→`_or`, `B$i`→`P0u` across 37 versions) | `ps -Ao pid,comm \| grep claude`; then re-run the G6 probe rather than re-reading a constant |
| harness truncation constants | preview `_or=2000`, trigger `P0u=1e4` | dies with the binary | `scratchpad/g6-control-L1.sh`, or the isolated `CLAUDE_CONFIG_DIR` probe (§4.3) |
| memory corpus | **1,242–1,303** topic files, **854 orphaned from their own index (68.8%)** across 32–34 real stores | grows ~275 files / 4 weeks | `scratchpad/g6-control-G3.sh` |
| `MEMORY.md` index fill (claude-infrastructure) | **23,523 / 25,000 chars (94.1%)**, 141/200 lines, **8 usable entry slots** | 8 slots ≈ days at the current write rate | `hooks/lib/memory-index-measure.sh` |
| `dod-persist.sh get "$PWD"` crosstalk | returns the *dod-crosstalk provenance* wave's scope, read **2026-08-19T12:54:26Z** | **LIVE-STATE READ — `last_recorded_scope` returns the store's newest line; a different answer next week.** Quote the timestamp and the row, never the bare claim | `scratchpad/g6-control-L3.sh` |
| token price / cache multiplier | $5/MTok, 2.00× cache-write | `model-config.yaml:151` — perishable | read the file |
| `/private/tmp/claude-501/…/scratchpad/` (all 20 wave artifacts + ~25 scripts + 3.3 MB of JSON) | present | **the same reboot-bounded store this wave measured decaying.** This document is the durable copy of the conclusions; the raw evidence is not durable | — |

Durable and safe to quote: git shas, tracked `file:line` citations, `~/.claude/logs/claude-crashes.jsonl`
(append-only, 239 rows, 2026-07-23 →), and memory topic files.

### 2.3 Three instrument corrections that changed answers — propagate these

1. **`find` without `-L` cannot see the memory or transcript layer.** Per-project `memory/` dirs are
   symlinks into a shared store; `~/.claude-next/projects` is a symlink to `~/.claude/projects`. A
   non-`-L` sweep reads a whole root as **0 files** and its null renders as a real absent population.
   Conversely, path-counting *with* `-L` inflates: the pivotal memory file resolves to **12 paths,
   one inode (`382381778`)** — a 12× inflation if you count paths (G0 §0). **Four stores, not five.**
2. **JS counts UTF-16 code units; Python counts code points.** G6's first preview-verification pass
   showed 5/739 "failures", all off by one, all on payloads containing `📬`. Re-run slicing by
   `s.encode('utf-16-le')[:2n]` → **739/739**. Anyone re-deriving truncation numbers in Python will
   otherwise mis-convict every peer-mail payload (G6 §2.4).
3. **A regex that enumerates spellings is not a measure of a class.** A1's "only 7/51 succession
   bridges point at memory" reproduces exactly and is still wrong: the regex requires a path literal
   or `` `memory `` (space-backtick) and misses the corpus's house idiom `` Memory: `slug` ``
   (colon). Disk-verified against 1,245 real topic files: **31/51 = 61%** (G3 §1).

---

## 3. The five R2 questions, answered

### R2.1 — Is the machinery-findings gap real and recurring, or n=1?

**Answer: the motivating instance is n=1 and genuinely novel. A separate, cheap re-derivation class
is real and recurring (6 sessions / 3 repos / 8 days / 9 tool calls). The class the plan named is
carried, not dropped — but the measurement covers only the recycle arm.**

**(a) The motivating incident is n=1, and round 1's claim that it was already durable is refuted by
git, not by reading.** [MEASURED] Round 1 asserted the 2026-08-19 recycle finding *"was already in a
durable memory file 13 days before the incident."* It was not. The 08-19 failure mode is the log
line at `scripts/handoff-fire.sh:4856` — *"never reached a CONFIRMED shell prompt … NOT typing onto
an unconfirmed pane"*. `git log --all -S` on that literal returns one logical change,
`937772ee0` *"fix(recycle): the probe typed on 'I can't find CC'"*, authored 2026-08-06 21:10:18
-0700 (2026-08-07T04:10:18Z), an ancestor of `origin/main`.

> *Precision note this document owes its own adversary:* `git log --all -S` actually returns **five**
> shas — `937772ee0`, `9190c96fc`, `451eb423a`, `ee2823f08` (four rebase copies of one logical change,
> identical subject and author date) plus a `PostToolUse` checkpoint `47333f463`. G0 reported
> "exactly one introducing commit"; the accurate statement is **one logical change carried by four
> shas**. The conclusion is unaffected: the string did not exist before 2026-08-06 21:10 PDT.

That commit **is** the 2026-08-06 remedy — the memory file's 08-06 half prescribes it in words
(*"a probe that cannot positively confirm a shell prompt must REFUSE and print the manual command,
not type"*). So the chain is: 08-06 defect (probe types blindly) → 08-07 remedy lands → **08-19
defect is that remedy executing correctly and dying silent**. The 08-19 failure mode **could not have
existed before the fix, because the code that emits it did not exist.** It also *overturns* standing
durable memory: `handoff-recycle-watcher-race.md` (2026-07-14) says *"trust the armed-heartbeat
line"*; the 08-19 append says *"treat 'armed' as unverified."* A finding that overturns a standing
rule is by definition not that rule.

Durability sweep, five stores, all null before 2026-08-19T11:04:57Z: 1,303 distinct memory files ·
tracked `docs/` · all git refs · 12,290 backlog rows · decision packets. Negative control:
`sed -n '1,66p' <file> | grep -c '<08-19 signature>'` → **0**. Positive control: the same probe
re-run today **hits**. The motivating session ran its own version of this probe at
2026-08-19T11:04:25.595Z (transcript rec 1780) and got `(blank = nowhere)`; its glob reached
**1,264/1,303 = 97.0%** of distinct memory inodes (G0 §2).

**⇒ Plan R1's premise — *"that finding existed nowhere durable"* — STANDS. Do not edit the plan to
say otherwise.** The consequence cuts toward the verdict, not away from it: the one argument that
the incident revealed a *systemic retrieval* defect is refuted, and the incident returns to n=1,
which is exactly R4 anti-goal 2's overfit risk.

**One honest qualification no prior reading found** [MEASURED]: the specific finding is novel, but
its **class** was durable at n≥3 — backlog `03682fdd378c` (2026-07-31, closed 2026-08-07) records
`self-close --terminal` printing *"watcher armed + heartbeat verified"* and then failing; row
`0a61d1581a43` (2026-08-10) carries *"'armed' is unverified"* in a launchd context; plus the
07-14 memory entry. So a general rule about *verifying actuators* has an evidence base — and it is a
rule about actuators, not about handoff briefs.

**(b) A genuine, repeated re-derivation exists, and it costs one grep.** [MEASURED] Six successors
across three cwds and three repos open their session hunting for a `~/.claude/goals/` directory that
does not exist, all inside their first two tool-turns: `579d2a59`, `57ed607b`, `9d874911`,
`2ce746a2`, `84bde2e9`, `020aafc9` (A2 §4; `rg` over four transcript stores → 25 fleet-wide hits, 6
at turn 0-1, all six verified successors in the resolved chain set). The proven instance runs
**backwards**: predecessor `579d2a59` found the answer at t2 (`source ~/.claude/hooks/lib/goal-state.sh`
→ `goal_liveness`); successor `84bde2e9` re-ran the hunt at t0/t1 and found strictly less. **Total
cost: 9 tool calls, 6 instances, 8 days, 0 operator round-trips, 0 wrong actions** (A2 §4.4). By the
plan's own test — *"one grep is not the same finding as an hour"* — this is the one-grep kind.

The trigger is `bin/cc-await-ping:525`, which emits *"WHICH REPAIR APPLIES DEPENDS ON YOUR /goal, so
check before you act"*, describes two branches, and never names the check. That is an
`cc-await-ping` defect, not a `commands/handoff.md` defect (§5 L2).

**(c) The class IS carried by bridges — with the class-relevance contested and the contest
adjudicated.** [MEASURED, with a named dispute] A1 measured **43 of 51 succession bridges (84%)**
carrying a dedicated hazard/lesson block against **15 of 71 peer briefs (21%)**, and
**hand-adjudicated 18/18** on the independent non-drain-chain subset, quoting each alternate heading
(`BINDING RULINGS (do not re-litigate)`, `NON-NEGOTIABLE, because each was won by a rejection`, …).
Three chains **accrete** the findings: the 29-link drain chain grows its `TRAPS ALREADY PAID FOR`
block 14 → ~54 lines monotonically, with **1 drop across ~150 finding×link opportunities,
self-repairing at the next link** (A1 §5.1).

The category refuter split the same 51 by whether the bridge's own subject **is** the infra
machinery, and found carriage collapses on the population where the class is not tautological:
**2 of 9 product-work succession bridges (22%), both from one author lineage.** That split is real
and I do not dismiss it — but n=9, and G5 re-measured the underlying convention on the delivered
population: fire payloads carry a labelled hazard-block heading at a rate that is **robustly large
but instrument-dependent**, against controls `turso` 4 and `zzqx` 0.

> ⚠️ **Corrected post-review — do not quote a single figure here.** G5 published **64/123 (52%)** and
> called it "a floor, because the instrument keys on a heading". The re-base auditor could not
> reproduce it from G5's own published command (it yields **41/123 = 33%**), and no G5 script
> survives on disk. The lead re-ran it independently on the live population (**125** files,
> 2026-08-19, bash): `TRAPS` 37 · `LANDMINES` 19 · `HAZARD` 11 · `GOTCHA` 1 · `PITFALL` 0 ·
> `KNOWN FALSE` 0; union of all six = **58/125 (46%)**, union of `TRAPS|LANDMINES` = **56/125
> (45%)**; controls `turso` 4, `zzqx` 0. The "floor" justification is also **struck**: anchored and
> unanchored matching return the *identical* count (58), so heading-anchoring adds nothing and
> cannot license a floor claim.
> **What survives is the direction, not the magnitude:** across three independent instruments the
> range is **33–52%**, and every point in it is more than double the best available template site's
> reach (15.6%, §R2.2). The argument this evidence supports is comparative, and it does not need a
> precise number.

**Adjudication:** the class is carried at 33–52% (delivered artifacts, instrument-dependent) to 84%
(succession bridges), with **zero counter-examples in 18 independent hand-checked successions** —
A1 found no bridge that hit a tooling problem and omitted it. The category refuter's 2/9 bounds how
confidently that generalises to product-work repos; it does not establish a loss, because no
downstream cost was traced on any of the 9.

**(d) The expensive defect is the INVERSE one — but only for one content class.** [MEASURED, scope
corrected] 3 of 93 successors burn early turns correcting a **stale** claim the brief handed them
(`a52af81e → a742c92e`: *"the merged-gate **already** uses patch-id"*, ~5 tool calls; plus two more —
A2 §6). Round 1 promoted this to a pillar. The false-positive refuter demonstrated that all three
cases are **work-premise** claims (assertions about the current state of the repository, which goes
stale because the repository moves), whereas the content the plan proposed adding is **toolchain
hazard** (*zsh does not word-split in a `for` loop*), which A1 measured surviving ~150 finding×link
opportunities. **The staleness argument is therefore valid for work-premise content and unsupported
for hazard content.** It is an observation here, not a pillar.

**(e) Zero operator re-asks — bounded.** [MEASURED, null qualified] Across all 93 resolved chains,
successors posing an operator-facing question the predecessor already knew: **0** (one hit, a
genuinely new visual judgment). The evidence-quality refuter correctly bounds it: the instrument is
a nine-alternative literal phrase-match over the **first 8 turns**. The defensible statement is
*"not observed within 8 turns by literal phrase-match"*, not *"absent"*.

**Bound on everything in R2.1** [MEASURED]: `firing_sid` is never a session id — **273 of 277
non-null values are iTerm pane numbers, 0 are UUIDs** — so the 145 `self-retire-peer` + 453
`admitted` rows record *neither end* of their succession. A2 did not find "no re-derivation in fired
handoffs"; **it could not look** (A2 §0.3).

### R2.2 — Is a TEMPLATE the right lever at all?

**Answer: no — and round 2 adds a reason round 1 never had, which is that a template-shaped remedy
already exists, mandated mechanically, on the one path where a model does not author the brief.**

- **The reflex is built, wired and running.** [MEASURED] 333 of 333 memory topic files carry
  machine-readable `originSessionId:` provenance; 317 creations located in a transcript; median
  latency from evidence-in-hand to memory write **22.5 min** (p25 8.7, p75 57.3; N=277). ~95% happen
  with **no operator in the loop** (273/317 follow a machine/command/peer prompt), and
  adversarial-challenge-driven captures are **0 of 317** (A4 §1-§2). Actuated by
  `hooks/memory-nudge.sh` (UserPromptSubmit, every 12 prompts, wired at `~/.claude/settings.json:866`),
  firing **658** times against `commands/handoff.md`'s **149–183** injections.
  *Correction to round 1:* the cited `~/.claude/CLAUDE.md:89-105` is the **anti-capture filter**
  ("SKIP — do NOT encode…"), not a timing mandate. "Wired and running" survives; "mandated" was an
  over-read.
- **The reflex's own yield is 11.9%** (658 fires → 78 writes within 60 records) — the empty-ceremony
  failure R4 names, **already observed on the existing instrument** — and no instrument in this fleet
  can separate "correctly ignored" from "forgotten" (A4 §4). The claim is comparative, not laudatory:
  the reflex beats a template on every measured axis; it is not good.
- **A template already shipped, at the arm step.** [MEASURED — G2] The 2026-07-19 desk-self-handoff
  Fable panel prescribed `arm --brief <template>` which **hard-fails if no successor-brief template
  exists**, and it landed (`5d5e734`) — on the deterministic Stage-2 path where **no model authors a
  brief at all**. Prose in `commands/handoff.md` would be a second, weaker copy of a mechanism that
  shipped 31 days ago on the path that actually needs it.
- **A third carrier is in production and the file already requires it.** [MEASURED]
  `docs/plans/BACKLOG_DRAIN_24_7.md` §2.1 holds 48 dated entries across 67 `docs(drain)` commits, one
  per recycle, and `commands/handoff.md:121-123` already requires that plan to exist before a bridge
  may be emitted (A4 §5). The same recycle's machinery lesson is *also* in memory — captured twice,
  not zero times.
- **Cross-repo control:** in `reso` (a product repo where the machinery is *not* the work), ≥86 of
  678 memory files are CC-machinery subjects by filename alone, at a **median 3.8-minute** capture
  latency — faster than the infra repo (A4 §6). The "no home" premise fails in both populations.

**The two levers round 1 never enumerated, now adjudicated** (the critic was right that the question
was posed as a false binary):

- **Bridge-side memory pointer** — **REFUSED**, five independent ways (§6, G3).
- **Class-keyed write-time routing** — the measurement survives, the lever leaves scope (§5 F3).

### R2.3 — What is the cost side?

**Answer: the plan's own cost premise is quantitatively wrong. Cost cannot carry a "don't add"
verdict, and this section is published because it cuts against the recommendation.**

- **736 lines / 64,566 bytes** [MEASURED, re-verified this session: `wc -l -c commands/handoff.md`],
  ≈ **20,711 Claude tokens** (95% bootstrap CI 15,815–26,141), by regressing prompt-token deltas on
  injected body bytes over n=49 real injections (A5 §1). Explicit null: no offline Claude tokenizer
  exists on this machine, so this is a ±26% regression estimate, not a read-out.
- **It is NOT injected "on every invocation, by every session"** [MEASURED]: **149 injections over 40
  days = 3.73/day**, into **131 distinct sessions of 3,384 started in-window = 3.87%** (A5 §2,
  realpath-deduped census). Against succession events: 2.6% of `handoffs.jsonl` rows.
- One added line ≈ **33 tokens** = **$0.61–$1.72 per year**; a median commit (+9 lines) =
  **$8.58–$15.49/yr** (A5 §3, at Opus 5 $5/MTok and the *measured* cache regime — 99.9% of cached
  input is `ephemeral_1h`, so the multiplier is **2.00×**, not the 1.25× three of this repo's own
  cost documents use).
- Break-even against the fleet's own $0.208–$0.353 per forced turn: **one prevented turn every 5–15
  days** (A5 §5). The goal-hunt class alone is 9 calls / 8 days, so on pure economics a reliable fix
  would pay 17–29×.

**⇒ Plan R4 anti-goal 3's *justification* is refuted; its *rule* is not.** Strike the reason ("the
file is injected whole, every time" — false at 3.87% of sessions), keep the rule, which A7
(attention share: the bridge is 1.7% of a successor's first turn) and A8 (adoption; permanence)
independently re-found on attention rather than price. **Anyone re-opening this decision must not
re-argue it on cost.**

What the cost side *does* establish is a **routing rule**: compliance in this one file forms a ladder
— **script-enforced 100% (n=3) > duplicated into the always-resident `CLAUDE.md` 88% > prose-only in
`handoff.md` 43–73%** (A5 §4b) — and the `≤ ~30 lines` rule is violated on **5 of the 6 artifacts it
actually governs** (lead re-run, 2026-08-19: 22 · 31 · 44 · 44 · 57 · 60 lines).

> ⚠️ **Corrected post-review.** This was published as "violated **55/55** class-tagged payloads,
> median 11× the cap". Two defects, both found by the re-base auditor and both confirmed by the lead:
> the arithmetic is **51/55**, not 55/55; and — the load-bearing error — it was scored against
> `/tmp/fire-*.txt` payloads, which that rule **does not govern**. `≤ ~30 lines` sits at
> `commands/handoff.md:138`, inside the same sentence as the `:147` slot, so it binds Step 3's
> `/tmp/<slug>-resume.md` artifact only (§R2.5). Scoring a rule against a population it does not
> govern is the identical defect this wave convicted round 1 of at `:147`. On the **governed**
> population the violation rate is **5/6** — still bad, and now honestly attributed.

### R2.4 — What would a NET-NEGATIVE change look like?

**Answer: fifteen named failure modes, each with a worked example from real history.** Nine from this
file's own 32-commit log (A8 §7), five of the recommendation's own (§7 below), and one from prior art.
The load-bearing ones:

- **FM-6 · The marker survives, the substance dies.** 54/123 payloads emit `[locate]`; 12 carry the
  form the spec calls primary. *Any check keyed on a heading passes on a payload that lost the point.*
  **This failure mode fired in reverse on round 1's own instrument** — see §6 C3.
- **FM-7 · Prose here is an unfalsifiable claim with no expiry.** The 🚨 payload-shape block
  (`fe8e5277f`, 2026-07-10, 12 lines) stood **29 days** before `f33f17d30` measured two of its three
  load-bearing claims FALSE. **Zero of its 12 lines survive.** Its own commit message: *"A false
  mechanism in the spec regenerates the bug."*
- **FM-8 · Advisor/enforcer drift.** `b1a924370`: `hooks/validate-bash.sh` landed *denying* a pattern
  this file still MANDATED at three sites, ~11 days. `comm -12` shows **0 exact-line duplication**
  with `CLAUDE.md` — they paraphrase, so no textual sync check can see the drift.
- **FM-9 · A prose addition is not one commit.** `19d50adf3` (+75) required four corrective commits in
  25 hours and a fifth the next day: 75 lines cost **122 across 6 commits**. Price any addition at
  **1.6× its first diff.**
- **FM-10 · One-way ratchet.** 32 commits, 922 added / 186 deleted, **every one of the 31 transitions
  increases** — no commit has ever reduced this file, while the sibling `CLAUDE.md` *has* been
  compacted (393 → 329). "Trim it later" has no precedent here. [MEASURED, independently reproduced
  by two refuters]
- **FM-11 · Editorial gravity points at the transport.** All 198 lines added in the most recent era
  landed in fire-mechanics (185-712); **zero** in the Steps section. The "what to capture" contract is
  14 lines (`:137-150`) whose last surviving edit is 2026-07-18.
- **FM-13 · A "test" with no runner is prose in a lab coat.** The file declares three (`:724`, `:729`,
  `:733`); none is executed by anything.
- **FM-14 · The verification apparatus is pointed at the pipe, not the water.** 72 bats files cover
  handoff/fire/recycle and **not one asserts what a brief SAYS**; `scripts/handoff-fire.sh` has three
  pre-fire content checks, all about `/goal`. Round 1 called this "the strongest pro-change fact in
  the wave" and then never adjudicated it. **It is adjudicated in §4.2 below.**
- **FM-15 (new, from prior art) · A shipped instrument that never fires is indistinguishable from an
  absent one.** [MEASURED — G2 §4a] `0eed887`'s per-pid stderr capture ("the next crash *names* the
  mechanism, joinable by construction") is deployed correctly — live `~/bin/claude-latest` is
  byte-identical to `origin/main` (md5 `5f78f5b0f004b782256a8f3d8ad90c25`). Yet **1 of 203 CRASH rows
  joins a non-empty stderr log by pid**, and it is the `error-exit` row, not one of the 154
  `abrupt-unknown`; 3 of 6 `stderr_log` references already dangle. *The two halves have different
  half-lives, so the forensic instrument produces no forensics.* Every guard-shaped proposal in §5
  must be checked against this before it ships.

### R2.5 — Do adjacent mechanisms already cover it?

**Answer: yes — and round 2 strengthens this from "a coverage matrix" to "a control group and 27 days
of independent prior work".**

**(a) The coverage matrix.** A6 walked all 15 registered SessionStart hooks plus `cc-backlog`,
`cc-decide`, `handoff-disposition.sh`, memory (all account stores) and git, across a 14-row matrix.
**Exactly one class has no durable carrier outside the bridge: live ephemeral environment state**
(preview URL, dev-server port, restart command) — *and it should not have one*, because a durable
store would serve a stale port. A6 states its own bound: the matrix is closed over the mechanisms the
plan named, so it structurally cannot discover an unnamed carrier, and two were found by accident.

**(b) The control group — the session that never hands off.** [MEASURED — G1, the strongest new
evidence in the wave] Every round-1 corpus is conditioned on a bridge existing. G1 opened the
boundary with a **100% drop rate by construction**. In the identical 8.43-day window:

- `claude-crashes.jsonl` in-window rows: **61 → 37 ghosts** (no transcript ever existed;
  `claude_version:"?"` on all 37) **→ 15 one-shot headless probes** (first user message literally
  `Reply with exactly: ok` / `CLAUDEMD=YES if…`) **→ 6 correctly-classified clean exits →
  2 genuine working sessions.**
- Crash rate over the population that can hold context: **2 / 753 top-level sessions = 0.27%**.
  By transcript size: tiny ≤40 recs **15/356 = 4.21%**, small ≤200 **1/685**, mid ≤1000 **0/396**,
  large >1000 **1/95**. The signal lives in throwaway probes.
- **Both real crashes had already persisted everything, verified by content.** `39fe1ff9` died 6 min
  in with `bin/cc-wake-headless` uncommitted — a **PostToolUse checkpoint commit `67507172b`
  (`ts=20260813T053603Z`) fired in the same second as the transcript's last Write
  (`05:36:03.536Z`)**, and salvage commit `af0127d07` landed the bytes verbatim onto `origin/main`.
  `f8a9953b` (2.6 MB, 1,556 records) had run `ship-land.sh` **4×** in-session and written **three
  memory files** before dying — `landedness-over-commits-is-blind-to-staged-content.md`,
  `corrected-instrument-can-lie-again.md`, `refuted-open-row-remints-its-own-analysis.md` — all three
  on disk and all three in `MEMORY.md` today. *That is the plan's feared machinery-findings class,
  written to memory unprompted, by a session that never reached a `/handoff`.*
- Fire volume in the same window, two agreeing instruments: `handoffs.jsonl class:admitted = 398` and
  `pane-spawns.jsonl surface:split caller:it2-kitty = 397`. **Ratio ≈ 250 : 1.**

⇒ Plan R1's line *"Not because `/handoff` captures it — because it goes to commits, docs, backlog and
memory as it is produced"* was an n=1 assertion. **It is now tested against the only population that
can falsify it, and it holds.** And nothing in `commands/handoff.md` runs in a session that dies —
the lever is not weak here, it is structurally unreachable.

**(c) Prior art — 27 days, seven documents, zero proposals to touch this file.** [MEASURED — G2 §8,
a real null from an adequate instrument: all seven read in full plus
`/usr/bin/grep -n "commands/handoff"` across them] Every prescription lands in
`scripts/handoff-fire.sh`, `hooks/mailbox-drain.sh`, `hooks/lead-crash-watchdog.sh`,
`hooks/session-end.sh`, `hooks/waiting-recycle.sh`. **This is the verdict's strongest external
corroboration**, from a wave that included a Fable frontier panel.

It also convicts this wave of the phenomenon under study, precisely: round 1's own #1 lever (L1, the
SessionStart mailbox blob) was surfaced **verbatim** at
`docs/research/handoff-memory-review-2026-07-22.md:247-248` — *"a SessionStart mailbox-drain can
inject a stranded 200 KB+ inbox as one `additionalContext` blob — a candidate context-spike-at-birth"*
— 27 days earlier, and has grown since (mailbox files **73 → 589**, largest box **208 KB → 2.5 MB**).
**But it failed on retrieval, from a landed, committed, trunk-resident research document — the most
durable carrier this fleet has.** A bridge could not have carried it: the 07-22 session and this wave
share no succession chain. **The phenomenon under study is not *loss*, it is *unreachability*, and
this wave demonstrated it on the most durable store in the fleet.** That argues against any
content-into-the-bridge remedy and for retrieval levers.

---

## 4. Recommendation

# CHANGE NOTHING in `commands/handoff.md`.

Zero lines added, zero removed, no new section, no new "test", no guard. **No negative control is
owed**, because no change is proposed (R5 bullet 3 is conditional). Controls for the levers that were
*considered and refused*, and for the levers that live elsewhere, are recorded in §4.3 and §5 so a
re-opener does not re-mint them.

The frozen ask — *"improve `/handoff` to concisely capture relevant highest-value details… so we
don't lose it crossing into the new session"* — is answered: **on the arm we can measure, the
succession is not losing that class; the loss the plan cited was a real, novel finding captured on
the day it was measured; and the two mechanisms that would carry it further are already running.**

### 4.1 What this verdict rests on (three pillars attacked and surviving; a fourth demoted post-review)

1. **The class is carried, with zero counter-examples.** 33–52% labelled hazard blocks in delivered
   payloads (instrument-dependent — see the correction at §R2.1; the *direction* is what carries, not
   the magnitude) · 84% of succession bridges · **18-of-18 hand-adjudicated independent
   successions** · three chains accreting, 1 drop in ~150 finding×link opportunities · and A1 found
   **no** bridge that hit a tooling problem and omitted it. [MEASURED — A1 §3-§5, G5 §4]
2. **No reachable site beats the convention.** [MEASURED — G5 §4] Every candidate is a downgrade:
   | site | reach |
   |---|---|
   | Step 3 `:147` (status quo — governs `/tmp/<slug>-resume.md`) | **6 / 261 fires = 2.3%** |
   | re-nest `:147` under the paste-block bullet (0 added lines) | same 2.3% |
   | § Autonomous fire item 1 `:194` (new payload contract) | **15/96 recycle authors = 15.6%; 0 of 41 identifiable firing sessions** |
   | the 41 machine-composed dispatch briefs | **0%, structurally — no model in the loop** |
   Against a convention already running at 33–84%.
3. **A prose-only rule in this file has no runner and a one-way ratchet behind it.** The file declares
   three "tests" nobody executes (FM-13); `≤ ~30 lines` is violated on **5 of the 6 artifacts it
   governs** (see the correction at §R2.3); and in 32 commits **no commit has ever reduced this file**
   (FM-10) — 922 lines added, 186 deleted, all 31 transitions net-positive, independently reproduced
   by two refuters. An addition would be the eleventh prose-only edit, and the history predicts its
   outcome.

**Demoted post-review — this was published as a fourth surviving pillar and is not one:**

4. ~~**The work survives by continuous persistence, now with a control group.**~~ 2 real
   context-deaths in 8.43 days against ~493 succession events; both had persisted everything; the one
   uncommitted file was recovered verbatim onto trunk (G1 §3). **The recommendation refuter marked
   this UNDECIDED and over-claimed, and that is accepted:** n=2 is not a control group, and its
   recovery leg rests on a PostToolUse checkpoint mechanism this document's own open item O6 lists as
   unverified. A claim cannot be both an unverified open item and an attacked-and-surviving pillar.
   It is retained as **suggestive corroboration** — the direction is right and it is the only
   population that *could* falsify the persistence claim — but the verdict does not stand on it, and
   pillars 1–3 carry it without this one.

### 4.2 FM-14 adjudicated — the wave's strongest pro-change fact, answered

Round 1 called *"72 bats files cover handoff/fire/recycle and not one asserts what a brief SAYS"* the
strongest pro-change fact in the wave, then forward-referenced an adjudication that did not exist —
so the evidence, as presented, supported *"no PROSE change"*, not *"change nothing"*. Round 2 closes
it, on G5's population argument rather than on prose:

**A brief-content runner is refused because its negative control fails at the POPULATION level, not
at the assertion level.** A negative control would take one of the 59 hazard-block-less payloads and
show the new check catching it. It cannot: **41 of the 123 payloads have no model author** (machine-
composed dispatch briefs, median 7 lines), and A3 measured **0 of 41** identifiable firing sessions
with the spec in context. The rule could not have fired on the artifacts it is meant to catch.
Per R4's last anti-goal, **a guard that cannot fail is not shippable** — and a mandatory hazard
heading on a 7-line machine brief is the literal definition of R4's ceremony anti-goal.

The one site where a content check *would* reach every fire path — including the two A3 proved
structurally unreachable from `commands/handoff.md` — is **`scripts/handoff-fire.sh`**. That is a
script change, outside this wave's frozen scope, and it is filed as **F10** in §5.

> ⚠️ **Corrected post-review.** This paragraph originally ended *"it is filed in §5"* — and §5 did
> **not** contain it (F1–F9; grep for `content check` → 0 hits). The recommendation refuter named
> this as the single most important thing the document got wrong, and it is the identical defect
> this wave convicts round 1 of one paragraph earlier: routing the strongest pro-change fact to a
> destination that does not receive it. F10 now exists below, which is what "filed" has to mean.

### 4.3 The refused levers, with their controls, recorded so nobody re-mints them

| lever | why refused | control status |
|---|---|---|
| **Add a hazard/landmine content contract to the fire payload** (`:194`) | reach 15.6% / 0-of-41 vs a 52–84% convention; control fails at the population level (§4.2) | **unbuildable** — stated as such rather than claimed as an observed failure |
| **Re-nest `:147` under the paste-block bullet** (0 lines, fixes a real one-indent-level defect) | reach unchanged at 2.3%; the governed artifact is nearly extinct because Step 4 (`:152-156`) tells an autonomous fire to **"NEVER open Cursor"**, abolishing the resume.md's only reader | n/a — no behaviour to control |
| **Bridge-side memory pointer** (+2 lines in Step 3) | five independent refusals (§6 R3) | **specified and falsifiable, NOT RUN** (G3 §7): `bridge-memory-pointer-lint.sh` must exit 1 on `/tmp/fire-drain-recycle16.txt` (one cited slug, orphaned, never retrieved) and 0 on `fire-drain-recycle36.txt` (23 cited slugs, 0 orphaned). Cost if built: 2 lines × 149 injections/40 d = **$1.22–$3.44/yr**. G3 declined to build it because the lever dies before it earns a control, and says so rather than claiming an observed failure |
| **A brief-content runner** (bats over payloads) | §4.2 | population-level unbuildable |

---

## 5. Real findings, OUT OF SCOPE of the frozen ask — filable, not authorised

The wave measured several genuine defects in adjacent machinery. **Filing them is not doing them.**
Each is its own decision with its own gate; treating this section as a work order is FM-S5, the
scope-metastasis the Follow-On Gate exists to prevent. None of them is evidence for or against
changing `commands/handoff.md`.

**F1 · Peer mail is silently dropping most of a large drain, and the current-era drops are 100%
peer-authored.** [MEASURED, mechanism + rate + composition; remedy UNNAMED] The binary persists any
hook `additionalContext` over **10,000** units to a file and injects a preview of **(1000, 2000]**
units. Confirmed on the live 2.1.220 image (`_or=2000` @230276355, `P0u=1e4` @230268805, slicer
`xKr`), pinned to the exact character by an isolated zero-cost probe (9,999 whole · **10,000 whole** ·
**10,001 truncated**), and cross-checked against 33,788 real corpus items with **zero violations in
either direction**. `hooks/mailbox-drain.sh:134` sets `MAXLINES=0`, and `mailbox_take_n` advances
`.seen` over what went to **stdout**, not over what the model received.
*Sizing, re-versioned twice:* 10 events total, **2 since 2026-08-01** (0.051% of 3,942 sessions), most
recent 2026-08-19. July events are 75–100% machine chatter; **both 2.1.220-era events are 0%
machine-tagged — 11 and 15 peer-authored lines** reading *"STAND DOWN — you are a DUPLICATE fire on a
SHARED worktree … ~25 min of UNCOMMITTED, UNRECOVERABLE work"* and *"🚨 RUNAWAY DISPATCH LOOP … ~1,500
LOC, all uncommitted"*. Volume fell ~7×; density rose to 100%. **Caveats that keep it honest: n=2
events, arguably n=1 incident (both concern 2026-08-07), and the lines carry `[forwarded:…]` markers,
so fleet-level loss < per-session loss.**
*Control:* `scratchpad/g6-control-L1.sh` — **RUN, FAILED pre-fix on all three observables**: stdout
71,540 B vs the 10,000 trigger · `.seen` 600/600 · and end-to-end through the real binary,
`G6MSG-0400` absent from the 2,514-char delivered block. Runs against `CC_MAILBOX_DIR`, the drain's
own test seam; the live inbox was never opened.
*Before anyone fixes it:* G2 found the cursor semantics are richer than round 1 modelled —
`hooks/lib/mailbox-pending.sh:6-11` defines a **two-cursor** contract (`.seen` emitted / `.acked`
consumed, `acked ≤ seen ≤ lines`) and `mailbox-drain.sh:193-194` advances only `.seen` (`ack_now=0`).
**The open question is whether `mailbox_promote_acked` fires on turn-existence or on content-receipt.**
That is the probe, not a finding. **A lever whose remedy is unnamed is not decision-ready.**

**F2 · `hooks/dod-persist.sh` returns a foreign wave's frozen contract as binding.** [MEASURED,
reproduced live three times by three independent agents] `bash hooks/dod-persist.sh get "$PWD"` in
this worktree returns the *dod-crosstalk provenance* wave's scope under the frame *"THE CURRENT
CONTRACT — this is what binds you… Do NOT narrow it or declare done until ALL of it is met"*
(`hooks/dod-persist.sh:210`). Mechanism: **1 of 190 capture blocks store-wide carries a `toplevel=`
stamp, and 0 carry this worktree's**, so `dod_filter_for`'s lineage filter has nothing to key on and
fails open by design (`:186`). Already ticketed: backlog `4de3d0f9c0e1`, prerequisite 2.
*Related, and it is a subtraction from `commands/handoff.md`'s duties rather than an addition:*
**0 of 1,007 ledger rows carry a `dod` key**, so a fire that skipped Step 2's mandated freeze is
indistinguishable from one that made it. The precedented shape is to make the freeze a mechanical
step of the fire in `scripts/handoff-fire.sh`, or record `dod:absent` so the miss is visible.
*Correction round 1 owed and did not make:* L3's "17 KB per SessionStart" is a **produced** figure;
the harness truncation in F1 fires on this exact payload, so the **delivered** cost is ~6× smaller.
The mis-attribution defect is unaffected. And a deliberate **passing** control:
`Scope (frozen):` survives inside the delivered preview in **729/729** cases on 2.1.220 — benign by
ordering — while `dod-persist.sh:197`'s "LOSSLESS" comment remains false at **92.1% diverted**.
*Control:* `scratchpad/g6-control-L3.sh` — **RUN, FAILED pre-fix on both observables**, live read
dated 2026-08-19T12:54:26Z with the returned row quoted verbatim.

**F3 · Succession-apparatus findings are mis-filed outside their owning repo at 15× the product-fact
rate.** [MEASURED — category refuter §2b, with a mirrored control; NOT the cause of the motivating
incident] Files whose body names a succession-apparatus artifact
(`handoff-fire.sh|--recycle|cc-await-ping|self-retire|handoff-disposition|recycle-engaged|goal-state.sh|mailbox-drain`)
vs a mirrored product-artifact control: **apparatus facts filed outside the owning repo 21/85 = 25%;
product facts 6/384 = 1.6%.** The structural reason is real: the succession apparatus is the one
subsystem every session in every repo uses and only `claude-infrastructure` owns, so every session
outside it is a guest filing findings in its host's store. **The measurement stands; its status as
the cause of the 08-19 incident does not** (G0 refutes that — nothing was mis-retrieved, because the
finding did not exist to retrieve). It is a **memory-system write-time** lever, not a handoff-template
one. *Control specified by its author:* take the 21 apparatus files stranded in reso's store and
assert a post-fix write of the same class from a reso cwd lands in the infra store; a control
asserting only "a memory file was written" passes on the stranded case and pins nothing. **NOT RUN.**

**F4 · The memory index is a bounded index over an unbounded store, and 68.8% orphaned is its
designed steady state.** [MEASURED — G3 §8, via the repo's own `hooks/lib/memory-index-measure.sh`]
854 of 1,242 topic files orphaned; the claude-infrastructure index is at 23,523/25,000 chars and
141/200 lines ⇒ **8 usable slots**. Indexing that store's 195 orphans needs **33,191 chars = 1.3× the
entire cap**; the free headroom covers **4.5%** — before the other 33 stores' 661 orphans. Store
growth: **275 files in 4 weeks vs 8 slots.** ⇒ **A re-index pass is arithmetically impossible and a
one-shot besides.** The durable levers are eviction policy (`/compact-memory`, `cc-memory-rotate` —
both already exist) and retrieval. *Mitigating measurement, previously an unmeasured null:* orphaned
≠ unreachable — **155 distinct orphaned files were read or grepped in 14 days (18.1% of 856)** vs
164 indexed (42.2% of 389), and 13.8% of sessions grep the memory dir with no slug in hand.
Orphanhood costs ~2.3× in retrieval rate; it does not sever reach.

**F5 · `bin/cc-await-ping`'s WAKE-PATH-DOWN notice names a decision and never names the check.**
[MEASURED, and the premise may have moved] `bin/cc-await-ping:525` emits *"WHICH REPAIR APPLIES
DEPENDS ON YOUR /goal, so check before you act"*, then two branches and no check. It is the direct
trigger of R2.1(b)'s six goal-hunts. The check exists and discriminates:
`hooks/lib/goal-state.sh :: goal_live_condition` (verified in prior art at
`goal-in-handoff-2026-08-08.md:635`, and live: rc 0 with a live goal, rc 1 without; it fails **closed**
per `goal-state.sh:28-30`).
*Control:* `scratchpad/g6-control-L2.sh` — **RUN, FAILED pre-fix** (notice names the decision: 1 hit;
names a runnable check: 0 hits), **with the same-day falsifier PASSING**, which proves a remedy would
name a mechanism that exists and works, i.e. would not be FM-7.
> ⚠️ **Corrected post-review — this section previously deferred F5 pending a date join, on a wrong
> date. The join has now been RUN and it inverts the conclusion.** The text said
> `hooks/mailbox-drain.sh:352-353` landed **2026-08-15** (`e8c2435aa`) and that *"if all six hunts
> pre-date it, F5 is already fixed by a sibling and the residue is cosmetic."* Two corrections:
> (1) `e8c2435aa` is **2026-08-17**, not 08-15 — author *and* committer date, verified by the lead:
> `git log -1 --format=%ad --date=iso e8c2435aa` → `2026-08-17 00:02:05 -0700`.
> (2) The recommendation refuter ran the join against that corrected date: **all six goal-hunt
> sessions START AFTER the fix** (earliest 1 h 45 m later), and all six received WAKE-PATH-DOWN
> 4–12 times each.
> **Therefore F5 is LIVE, not cosmetic — the sibling fix did not close it, and open item O4 is
> CLOSED by this measurement.** F5 keeps its RUN-and-FAILED negative control above and remains the
> cheapest, highest-confidence filed item in the wave. This session observed the defect first-hand:
> the WAKE-PATH-DOWN notice it received at 05:33 named the decision and, exactly as measured, no
> check — the wave's own subject reproducing inside the wave.

**F6 · `CLAUDE.md` is injected twice, byte-identical.** [MEASURED, confirmed from inside two separate
sessions' own system prompts] md5 `10de4a19394fc5c4d7a342a76636d057`, 63,983 bytes each, for the
global and project copies; the binary emits one labelled block per memory *source* with no content
dedup. ≈ 18,300–29,900 tokens per session in **≥27.5%** of fleet transcripts (ceiling 66.6%,
unpinnable because 39.1% of transcripts belong to reaped worktrees). **3–13× the median bridge, for
zero information**, and entirely unrelated to `/handoff`.

**F7 · Prior-art recommendations that were never executed and have grown.** [MEASURED — G2 §4]
Of ~11 recommendations in `docs/research/handoff-memory-review-2026-07-22.md`: 4 implemented
(session-end reap — `cp-count` **1,941 → 14**, pid/id **93 → 14**; log rotation loaded; idl deadlock
resolved 72 MB → 10 MB; single-instance guard), 1 landed-but-inert (FM-15), 1 superseded, **2 never
touched and growing** (`refs/checkpoints` **1,842 → 5,628**, ~135/day; mailbox **73 → 589 files**,
~18/day), **1 never built** (the subagent-arming guard — 0 `isSidechain`/`--agent-id` hits in
`hooks/lead-crash-watchdog.sh`, live signature **47 of 203 CRASH rows** with `cause:no-transcript`),
1 partially re-invented without its evidence base (`config/store-bounds.manifest` exists at 47 lines
with **zero** entries for watchdog / `cp-` / mailbox / checkpoints), and **the doc's own PRIMARY —
pin the CC binary — neither taken nor re-tested** (`~/.claude-versions/current` → 2.1.114, a decoy;
the fleet runs 2.1.220, three releases past anything measured).
⚠️ **Correct the routing on the crash ledger before anyone uses it:** the 93%-false calibration is
**stale**, not a discount to apply — all 239 rows post-date the root fix `b026894`. The honest
decomposition is 36 `RECYCLE` · 47 `CRASH/no-transcript` (the never-built subagent guard) · 50
SIGTERM/SIGKILL · **residual ceiling 107** (~4/day). Do not quote 239; do not discount it by 93%.

**F8 · The `handoffs.jsonl` ring buffer defeats every "re-measure in two weeks" plan, and one
integer fixes it.** [MEASURED — G2 §5] Round 1's FM-S2 read the 9-day window as store youth; it is a
designed trim (`scripts/handoff-fire.sh:9226`, `:9379`, `:9392`). A researcher returning in two weeks
gets the **same ~9-day window over different rows**. The trim already computes what it discards
(`_hf_drop`, `:9389`) and nobody reads it. *And O1 is a four-site one-variable change:* `:9228-9230`
already says *"`FIRING_SID` is a PANE uuid… Prefer the CC session id (`SESSION_ID`)"*, yet all four
emitters pass `--arg fs "${FIRING_SID:-}"` (`:611`, `:687`, `:769`, `:9304`) with `SESSION_ID` in
scope. Ancestral defect: `HANDOFF_BACKCHANNEL_2026-07-10.md:25`.

**F9 · `~/.claude/logs/sessions.log` cannot say which session ended.** [MEASURED — G1 §4.2] 15,990
`Session ended` lines, **0** carry `sid=`. `e797317cd` fixes it and is an ancestor of `origin/main`,
but the live symlink target lacks the string — a **landed-not-live** state at measurement time. Until
it converges, the fleet cannot enumerate clean exits, and ~86% of those lines are phantoms from
`claude mcp list` subprocesses.

**F10 · The only site where a brief-content check could reach every fire path is
`scripts/handoff-fire.sh`, not `commands/handoff.md`.** [INFERRED from MEASURED reach — §4.2, A3
§2-§3, G5 §3a-§4] *Added post-review: §4.2 declared this filed and §5 did not contain it.* Every
site inside the spec file is reach-bounded — `:147` reaches 2.3% of fires, `:194` reaches 15.6% of
recycle authors and **0 of 41** identifiable firing sessions, and the 41 machine-composed dispatch
briefs have no model in the loop at all. `handoff-fire.sh` is the one component every path executes,
so a check there is the only version of this idea that is not born unfalsifiable.
**Filed, explicitly NOT recommended, and it must clear three gates before anyone builds it:**
(i) a negative control that RUNS — take a payload with no hazard block and show the check catching
it, which is exactly what could not be done from inside the spec file;
(ii) an answer to whether a 7-line machine-composed dispatch brief should be *required* to carry a
hazard heading at all, since mandating one there is R4's ceremony anti-goal in its literal form;
(iii) the R2.1 test this wave applied to everything else — evidence of a **re-derivation** the check
would have prevented, not merely an omission it would have flagged. The wave found no such
re-derivation attributable to a missing hazard block, which is why this is filed rather than
recommended. Whoever picks it up inherits the burden of proof, not a mandate.

---

## 6. What was REFUTED along the way

A reader cannot calibrate the surviving claims without seeing the wave correct itself. Round 1's
recommendation survived; **six of the things holding it up did not.**

| # | Round-1 claim | Verdict | Why |
|---|---|---|---|
| **R1** | §1/§3 headline — *"the one loss the plan cites was already in a durable memory file 13 days before the incident"*, and §3 *"the correction that reframes the whole wave"* | **STRUCK** | All three refuters refuted it independently; G0 settled it by git. The pivotal memory file has two halves written 13 days apart about **opposite branches of the same probe**; the 08-19 half was appended by the motivating session itself at 2026-08-19T11:04:57Z; and the failure mode it describes is emitted by code that landed 2026-08-07 as the 08-06 remedy — chronologically impossible as prior art. **Round 1 read the file's frontmatter and two of its sentences and did not read past line 65 of 101.** Plan R1's premise stands; the incident is n=1 |
| **R2** | §3 *"the 08-06 entry predicted the 08-19 recurrence in writing"* [tagged MEASURED] | **STRUCK** | Both quoted "predictions" are about the other branch: *"treat that line as a mis-fire"* refers to `→ recycled (no CC was running): typed relaunch into <id>`, which the 08-19 case never printed; *"the next unmodelled **wrapper** reproduces it exactly"* — the 08-19 case involves no wrapper. A9 had listed this as its own kill-condition; the synthesis promoted a flagged judgment to MEASURED in its headline and dropped the kill-condition. **This is the specific defect this round was told not to repeat** |
| **R3** | §L4 *"memory retrieval: the actual cause of the motivating incident"* | **STRUCK as the cause; the underlying statistics survive** | Retrieval delivered the **file** (the session had written its own index line 32.5 h earlier and typed the absolute path); it could never have delivered the **finding**, which did not exist. Every index line pointing at that file describes the 08-06 branch and its tell. The 68.8% orphan rate, the 94.1% index fill and the project-key partition are separate measurements and stand — as F3/F4, not as a diagnosis of this incident |
| **R4** | §4 argument 2 — *"the slot exists at `:147` and its vocabulary has ZERO corpus uptake (0/122) ⇒ spec text does not transmit"* | **REFUTED on its stated ground, SUSTAINED on a different one** | `:147` is a **sibling** of the paste-block bullet, not a child (indent proof: lines 139/140/147/149 are all `indent=3`), so it governs `/tmp/<slug>-resume.md`, not the fired payload. Re-measured on the governed population the number **reverses to 6/6 = 100%** on the exact heading string, 4/6 on the literal word `landmine`, 6/6 on the locator triple. A1's method line is *"grep -lF over all 122 payloads"* — it never ran on the 6. **But the governed artifact is produced for 6 of 261 fires (2.3%)**, because Step 4 tells an autonomous fire to *"NEVER open Cursor"* — the prescription outlived its reader. The lever dies harder, on reach rather than on transmission |
| **R5** | §2 R2.3 / §4 argument 3 — *"the strictest independent measure of a prose-only content rule is 9.8%"* (the self-locate full form) | **RETIRED as a compliance figure** — and the two refuters who touched it **contradicted each other**; adjudicated here | The evidence-quality refuter reproduced the arithmetic exactly (12/123; strict form 10/123 = 8.1%). The false-positive refuter attacked the **predicate** and won: `commands/handoff.md:729-732` states *"branch is the cross-clone fallback"*, so counting a payload that used the file's own sanctioned fallback as non-compliant measures something the file does not require — and of the 54 `[locate]`-carrying payloads, **0 fail to orient the reader** (50 say "worktree", 47 name the repo, 49 name a branch/HEAD). **Adjudication: the arithmetic is right and the predicate is wrong; only one refuter tested predicate-against-rule.** FM-6 — *the marker survives, the substance dies* — **fired in reverse, on round 1's own instrument.** What survives as prose-rule evidence: `≤ ~30 lines` at **0/55** (unattacked) and the compliance ladder's shape |
| **R6** | §4 argument 4 — *"a change that moves content INTO the brief moves the staleness number up"* [pillar] | **DEMOTED to a bounded observation** | All three staleness cases are **work-premise** claims that the tree outran; the content under discussion is **toolchain hazard**, which A1 measured surviving ~150 finding×link opportunities with one self-repairing drop. n=3 does not license the transfer |
| **R7** | §5 L1 headline — *"peer mail is silently dropping ~90% of a large drain"*, *"the wave's biggest actual loss"*, rate **22.2%**, *"permanent"* | **SIZING REFUTED, then re-versioned in the opposite direction** | The 22.2% is the rate over **sessions with any `additionalContext`** (3,242) and belongs nowhere near a peer-mail count whose denominator is all sessions; peer mail is **10 events / 0.149%**, of which 722 of the 732 truncations are the benign DoD class. 7 of 10 events are in one July week and the 539-message case is ~77% machine chatter. **But** the two 2.1.220-era events are **0% machine-tagged** — volume fell ~7×, density rose to 100%. *"Permanent"* → *"un-redeliverable by the drain"* (the harness writes the full payload to a file and announces its path; 731/731 still on disk). Net: **live, low-frequency, high-density, remedy unnamed** |
| **R8** | §5 L2 — *"the single highest expected-value item in the wave"* | **RANKING REFUTED, finding survives** | Measured value: 9 tool calls / 8 days / 0 operator round-trips / 0 wrong actions — by the plan's own test, the one-grep kind. It is the highest-**confidence** and cheapest item, not the highest-value. And a sibling fix may already have closed it (F5) |
| **R9** | §4 argument 1's *"91% of real recycle bridges carry machinery-caution content"* | **REFUTED as stated** | The regex `silently\|blind\|no verdict\|reads as\|looks green` scores 78/123 loose vs 55/123 strict; the 28 loose-only matches are work-domain prose (*"Revenue record **silently** lost"*, *"do not bless **blind**"*). `turso` at 4/122 controls that the instrument functions, not that it discriminates. **A1's 18/18 hand-adjudication is what argument 1 should have led with** — it survived every attack |
| **R10** | A1 §3 contrast 3 — *"only 7/51 succession bridges point at the memory store; this is the sharpest gap this axis found"* | **REFUTED — a regex artifact** | Disk-verified against 1,245 real topic files: **31/51 = 61%**; `fire-drain-recycle36` alone cites 23 real memory files. A succession bridge is the densest memory-citation artifact in the fleet. Round 1's synthesis and all three refuters propagated the 7/51 at 0-of-4 attention; the critic then built its top gap on it. **Correct A1 §3 in place if it is ever re-read** |
| **R11** | The completeness critic's sizing of the never-hands-off channel — *"~1.5% of ~3,384 sessions ≈ 50 events, the same order as the 96-row corpus"* and *"a session that dies mid-work drops 100% of what it held"* | **REFUTED in both halves** | 0.27% (2/753), and 4 of 4 cases examined lost zero work |
| **R12** | FM-S2's reading that the corpus is shallow because the store is young | **REFUTED, and the caveat gets stronger** | `handoffs.jsonl` is 27 days old with a 1000-row trim. The right statement is not *"we haven't observed long enough"* but *"the observation is continuously deleted"* — and it is fixable by one integer (F8) |

Two round-1 claims were attacked hard and **could not be broken**, and they are worth naming because
a survived attack is a result: **the file CAN reach its author** (`579d2a59` had the spec body
injected **twice**, including line `:147` which names the motivating incident's exact class — so the
honest number is **coverage, 15.6% of recycle authors, not incapacity**), and **cost cannot carry the
verdict** (§R2.3, published against the recommendation's own convenience).

---

## 7. What remains OPEN, and what would settle each

| # | Open question | What would settle it |
|---|---|---|
| **O1** | **Do new-pane `/handoff` successions lose more than recycles?** 598 of 694 succession-shaped events (145 `self-retire-peer` + 453 `admitted`) are structurally unlinkable — `firing_sid` is a pane number in 273/277 cases. **This is the single largest bound on the verdict.** | The four-site one-variable fix in F8 (`SESSION_ID` instead of `FIRING_SID` at `handoff-fire.sh:611`, `:687`, `:769`, `:9304`), plus preferring `registry:<uuid>` over `marker:<token>` in the engagement proof (9 of 109 proofs are UUIDs today). Then re-run A2's chain method — **but snapshot `handoffs.jsonl` first**, or the ring trim returns the same 9-day window over different rows |
| **O2** | **Do authoring sessions routinely hold machinery findings that reach no artifact at all?** This is the plan's hypothesis as literally written, and **no instrument in either round tested it.** A1's is bridge-to-bridge; A2's is successor-side; G1's is crash-side (and returns 0 for n=2) | Sample N≈30 authoring sessions; diff findings present in the transcript against findings present in (bridge ∪ memory ∪ `cc-backlog` ∪ plan). ⚠️ **A single-store probe manufactures phantom losses** — A1 nearly filed one before finding the fact in `cc-backlog` as row `7da9c4451540` |
| **O3** | **Does the product-work / cross-repo succession split hide a real loss?** Carriage falls to 2/9 on product-work succession bridges, both from one author lineage — but no downstream cost was traced on any of the 9 | Trace the 7 product-work bridges with zero apparatus content to their successors and hunt the re-derivation. Measurable in the corpus already collected, **while it survives the next reboot** |
| **O4** ✅ **CLOSED** | ~~Is F5 already fixed?~~ **Answered post-review, and it inverted.** `e8c2435aa` is **2026-08-17**, not the 2026-08-15 this table asserted (`git log -1 --format=%ad --date=iso e8c2435aa` → `2026-08-17 00:02:05 -0700`), and on the corrected date **all six goal-hunt sessions start AFTER the fix** (earliest +1 h 45 m), each receiving WAKE-PATH-DOWN 4–12×. | **Settled. F5 is LIVE, not cosmetic.** The date join was run by the recommendation refuter and the date independently re-verified by the lead. See the correction block at F5 in §5 |
| **O5** | **Did the two 2.1.220-era peer-mail drops cause a wrong action?** The plan's own test — *hunt the re-derivation, not the omission* — is **unmet for F1 in both rounds** | Trace the two receiving sessions' subsequent behaviour. A traced wrong action moves F1 from "live and small" to "live and expensive"; a third 2.1.220-era event whose dropped region is machine chatter collapses the composition finding |
| **O6** | **How wide is the PostToolUse checkpoint-commit mechanism?** G1's §3.1 rescue depended on a checkpoint firing in the same second as the last Write. Its coverage — which repos, which tools, what happens to a session dying at tool 24 of 25 — was **never established**. This is the most load-bearing unverified assumption under R2.5(b) | Audit `refs/checkpoints` (5,628 refs) by repo and by cadence, against sessions that died mid-turn |
| **O7** | **Does `mailbox_promote_acked` gate on turn-existence or content-receipt?** Decides whether F1 is a real permanent loss or a bounded one | Read the promotion's own predicate; re-specify F1's control against `.acked` after a Stop fold rather than `.seen` after a drain |
| **O8** | **Were the un-executed prior-art recommendations dropped or consciously rejected?** F7's aggregate is G2's strongest claim and it checked the tree, not the decision record | `cc-decide` / `cc-backlog` / commit messages for an explicit won't-fix on the version pin, the subagent guard, the mailbox GC or the `refs/checkpoints` pruner. **The cheapest way to falsify F7 and it was not run** |
| **O9** | **Do the 90% non-compliances with `[locate]` and `≤30 lines` cost successors anything?** If not, they are ceremony rules (R4 anti-goal 1) and this file's defect is **over**-specification — which flips the direction of any future edit from add to subtract | Hunt the re-derivation for the non-compliant payloads: did any successor have to re-locate its worktree? A8 measured the omission and explicitly did not hunt the cost. Note FM-10: nothing has ever been removed from this file |
| **O10** | **Is the attention-crowding hypothesis real** (more lines ⇒ lower compliance with existing rules)? | Requires an A/B. **No observational corpus can supply it.** Treat as permanently open unless someone runs it |
| **O11** *(added post-review)* | **The RETURN direction was never examined.** Both rounds measured succession *outward* — what a predecessor hands its successor. Nothing measured what a fired peer hands **back**: `--notify-back` pings, `cc-custody` discharge, the peer's own close. The re-base auditor found 0 hits for `notify-back` / `custody` / `originator` across this document, while `docs/research/succession-observability-2026-08-01` — cited here for its prior-art null — explicitly covers that direction. **The null this document harvested from prior art does not cover the population prior art was actually about.** | Re-read `succession-observability-2026-08-01` for the return-direction findings, then apply R2.1's own test to it: does a lead re-derive what a returning peer knew but did not report? Note this wave's own instance: the fired peer (this session) was told its status would be reported as UNREPORTED if it never pinged — i.e. the mechanism already models return-path loss, and nobody measured whether it works |

---

## 8. DoD check against plan R5

- ✅ **R2's five questions answered with cited evidence** — file:line, corpus counts with their
  commands, measured numbers, git shas (§3), with every load-bearing claim tagged MEASURED or
  INFERRED and every unreachable question answered as unreachable with its blind spot named.
- ✅ **A recommendation, and it is "change nothing in `commands/handoff.md`"** (§4) — defended on
  **three** attacked-and-surviving supports (a fourth was published as surviving and is demoted to
  corroboration post-review, §4.1), with the tempting-but-false supports explicitly struck (§6) and
  the refused levers' shapes and controls recorded so a re-opener does not re-mint them (§4.3).
- ✅ **No change ⇒ no negative control owed for the file.** Controls exist and were **RUN and FAILED
  pre-fix** for three of the elsewhere-levers (F1, F2, F5) and **specified-but-not-run** for two (F3,
  the refused memory pointer) — each labelled, none claimed as observed when it was not.
- ✅ **Failure modes extended beyond R4** — fifteen, each with a worked example.
- ✅ **Findings durable in `docs/research/`** — this document. The plan's status log is updated
  separately, IN PLACE.

**Two plan edits this document authorises, and one it forbids:**

- **Strike R4 anti-goal 3's justification**, keep its rule (§R2.3).
- **Add the arm-scope qualifier** to any restatement of the verdict (§1).
- **Do NOT edit R1 to say the finding was already durable.** It was not (§3 R2.1(a), §6 R1).
