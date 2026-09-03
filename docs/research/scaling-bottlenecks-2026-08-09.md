# The true bottlenecks: 15 → 150+ concurrent sessions on the fixed M1 Max — verdict and drive plan

**Date:** 2026-08-09 (evening; same day as the crash root-cause arming and the S6 program's own corrections)
**Method:** 13-axis research wave (3 adversarial) over the open gaps ONLY — built on, not re-deriving, `crash-rootcause-2026-08-09.md`, `CONCURRENCY_PROGRAM.md` §S6/S6-UPDATE/S6-DOD, and the four same-day measurement docs. Per-axis evidence: `scaling-bottlenecks-2026-08-09/` (00–13; every number below carries its axis tag).
**Scope (frozen):** identify the true bottlenecks behind "lags out, then crashes" and the path from 15+ to 150+ concurrent sessions, no hardware purchase.

---

## 1 · The verdict

**"Lag" and "crash" are two different bottlenecks, and neither is what the program ranked first this
afternoon. The published wall order (render → memory → ptys → load) inverts: at the real design point
(150 resident / ~10 active) the walls are MEMORY (with three unbudgeted terms) and ACTIVE-SESSION
LOAD — render and ptys are not walls at all. Two fleet-self-imposed caps (router KMAX=32, account
quota ≈ 4 sustained-active) bind before any kernel limit. The crash term is real, orthogonal, and
NOT closed: the one armed guard is running stale bytes, and five other control-plane mechanisms are
staged-inert — the sixth recurrence of "detection ships, actuation waits."**

All three adversarial axes and the two measurement axes converged on the inversion independently
(01, 09, 10, 13). The generating defect of the old ranking: the four walls were priced in
incompatible machine states (render at 150-all-visible, load at 150-all-idle), each against its own
alarm floor rather than a failure point, using constants of which the FIFTH same-day instrument
artifact was still live (09/13: `render-census.sh` sums **iTerm2** CPU on a **kitty** fleet — "107%
of the render floor" was a ratio between two emulators, one absent).

## 2 · The corrected walls, ranked

| # | Wall | Corrected number | Binds at | Axis |
|---|---|---|---|---|
| 1 | **Memory — composite** | session arrival cost **340 MB** (paired differential, n=1,194 transitions; the process itself is 235–270 MB, the rest helpers) — not 232 MB. Usable denominator **38–42 GB**, not 45. | **N≈103–132 resident** before the unbudgeted terms below | 01, 09 |
| 1a | └ **MCP children (absent from every budget)** | **~507 MB/session** measured today (22 `chrome-devtools-mcp` procs / 5.1 GB at 10 sessions; two node procs >2 GB) | ~49 GB at 150 — **forecloses 150-resident on its own** unless MCP is consolidated/lazy for resident sessions | 08 |
| 1b | └ **claude.exe self-bursts (unbudgeted)** | 54 processes exceeded **4 GB** in 11 days, max **41 GB**, ramp up to ~8 GB/min ⇒ ~3 events/hour at 150 resident. Trigger unknown — top open follow-on. | any single event erases the burst margin | 01 |
| 1c | └ toolchain bursts (the crash igniter) | D3's 15% segment bar = **19.9 GB of anon at panic packing** — the entire S6.2 remainder; and S6.2's "19 GB left for bursts" recomputes to **−4 GB** at the corrected constant | ~1 cold compile | 05, 01 |
| 2 | **Active-session load** (the felt daily ceiling) | **2.5–5 runnable threads per genuinely-active session** (measured 27→44 load at 9 active), not 1.6 (a mixed-fleet average) | **~4–8 concurrent active** on the load-20 gate — matches the felt ~12–15-session pain and all 127/127 historic gate refusals | 09 |
| 3 | **Fleet-self-imposed caps** | router `KMAX=8` × 4 accounts — **refuses the 33rd session** (proven on the shipped binary; `handoff-fire.sh:5266` turns rc 2 into HALT). oauth refresh herd: one credential/expiry instant per ~37 sessions, rotating tokens ⇒ a losing racer logs out the whole account, and `heal()` refuses to run while sessions are live ⇒ can never fire at 150. git shared store crosses `gc.auto` (6700 loose) within hours at 15×. `.claude.json`: 171 KB whole-file rewrite, no lockfile. | 32 · any refresh instant · hours · races now | 07, 08 |
| 4 | **Account quota (active half only)** | residency ≈ free; 4 Max accounts sustain ~~**~3.9 concurrent active 24/7**~~ → **6.2–11.0 measured** (~654 active-h/week); 10 active affordable ~39% of the week. ~~**68% of quota cost is cache-read at median ~200K contexts ⇒ halving context ≈ +50% active capacity** — bigger than a fifth account.~~ 🚨 **STRUCK 2026-08-24 — REFUTED by measurement; see §2a.** | active work, not residency | 07 |
| — | **NOT walls** (each with evidence) | render (idle panes 0.001 cores; occluded windows free; unit = drawn OS window ~0.05 cores; corrected wall 226–440 all-visible-all-active panes; sane 150-topology = 0.4–0.6 cores) · ptys (~30%, 1/pane+16 static) · pid-wrap (REFUTED: 923 pids/s ⇒ wrap every 108 s, live-observed; the panic correlation was a 2%-prior coincidence) · Mach ports (incident #0 re-explained as WindowServer CPU serialization — amplifier gone under kitty) · fd/kqueue/logd/disk/Spotlight/FS | — | 02, 08, 09 |

### 2a · CORRECTION 2026-08-24 — the quota row's cache-read premise is refuted, and with it the "halving context" lever

*(Sites: the rank-4 row above — still line 36 — and the standing-policy bullet formerly cited as
`:150`, which this insertion pushed into **§5 P2**. Chase the section, not the number; every external
citation of `:150` predates 2026-08-24.)*

🚨 **The struck clause in rank 4 is wrong, and it was standing policy for 15 days.** Rank 4 priced the
quota wall with **cache-read at 68% of cost** (axis 07's composition: cache-read 68.0% / cache-write
18.0% / output 14.0% at ~200K median contexts) and derived from that a headline lever — *halve the
context, gain +50% active capacity, bigger than a fifth account*. Seven days later a direct meter
experiment measured the exchange rate instead of modelling it, and the premise does not survive.

| | This doc (2026-08-09, axis 07) | `usage-telemetry-100p-2026-08-16/exchange-rate.md` (measured) |
|---|---|---|
| cache-read price | 0.10× multiplier, **68% of quota cost** | Opus-5 **0.000 pp/Mtok** (p95 ≤ 0.0017 over ≥590M tokens); ≥590M tokens per weekly pp |
| what costs | context volume | **output** (1.282 pp/Mtok) and **cache-creation** (0.105) |
| the prescription | *"halving context ≈ +50% active capacity"* | R1: *"Stop treating long cached context as quota-expensive… it authorises **more** context"* |
| method | composition model over token counts | NNLS over 265 ≥2 h intervals / 4 accounts, R²=0.82, CV RMSE 1.63 pp vs sd 2.13; independently replicated on the disjoint 5-hour bucket (128 intervals, R²=0.54, same zero on cache-read) |

**The decision (filed 2026-08-24, class A — measurement supersedes an unvalidated composition model).
The measured rate governs; the halving lever is dead; the two docs now cite each other.** Rationale
in three parts, the third being why this is a ruling and not another measurement request:

1. **The refutation does not depend on the disputed point estimate.** `exchange-rate.md`'s own
   abstentions table is honest that cache-read is *a bound, not a point* — `corr(out, cr) = 0.936`,
   `cond(X) = 23,556`, and the free and API-list-priced hypotheses both fit (R² 0.813 vs 0.797); the
   A6 verifier (`orchestration-units-2026-08-19/A6-VERIFY-quota-economics.md` §C6) correctly called
   the finder's "confirmed free" an overclaim on exactly that ground. **It does not matter here,
   because 68% fails under both hypotheses.** Priced at API list — the alternative that fits nearly
   as well, weights `5·in + 25·out + 6.25·cc + 0.5·cr` from finding #15 — account `next`'s realised
   80 pp cycle (6.47B tokens, 5.44B of them cache-read, ~1.0B cache-creation, 22–31M output) puts
   cache-read at **~28% of dollar cost** (27–30% across the published ranges), not 68%
   *(DERIVED-HERE from that doc's published figures; a bound-check, not a new measurement)*. So the
   lever is worth **0% under the measured fit and ≤ ~+16% under the list-price alternative** — and
   even that is an upper bound, since halving the window does not halve cache-creation. Never +50%.
2. **Rank 4's "~3.9 concurrent active 24/7" was priced with the same broken composition, so it too
   was wrong — but do not simply divide it out.** N7 corrects it to 3.9 / 0.32 = **12.2** under the
   free hypothesis; the list-price hypothesis would give ~5.4. The figure that owes nothing to either
   is A6 §C4's model-free derivation, **6.2–11.0 sustainable working units fleet-wide**, which
   brackets both and is what rank 4 now carries. Three independent derivations converging on ~9–12 is
   the strongest result in that wave.
3. **Why a ruling, not a re-measurement.** `orchestration-units-2026-08-19.md` N7 marked this REFUTED
   on 2026-08-19 and closed with *"needs a filed decision, not another measurement"*; that wave's
   completeness critic (`Z-completeness-critic.md` G15) then observed that **the synthesis named the
   contradiction and filed nothing**, leaving live-but-refuted guidance invisible to every sensor.
   A third measurement would not have changed that. This block, the reciprocal citation added to
   `exchange-rate.md`, and the status flip on prior-art row 55 ARE the filing.
   Class **A**, not C as G15 guessed: `cc-decide`'s taxonomy reserves C for human-only hard blocks
   (C10 self-mod, C6 money-path, permission denial), and this is an agent ruling on evidence with no
   value fork for the operator. Packet `758827c8333e` was opened, **but this session ran dispatched
   on an ephemeral box, so its `~/.claude/autonomy/decisions/` does not survive** — the durable trail
   is this commit and this block, which is the form the close protocol's evidence tier actually
   reads back (`git show <sha>`).

⚠️ **This does NOT weaken context stewardship — it removes a justification stewardship never rested
on.** The global `CLAUDE.md` § Context Stewardship is argued entirely from the **context-window
ceiling** (a hard `Prompt is too long` API refusal with no auto-compaction safety net) and from
decision rot, never from quota; grep confirms the 68% figure never reached it. Recycle at the right
moment for those reasons. Do not trim a context to save quota — per R1 that trade buys ≤16% of token
volume at ≤1/12 weight and spends the quality-positive direction to get it.

**Still open (not resolved by this decision):** which of the two fits is true. `exchange-rate.md`
§"What would falsify my headline" #3 specifies the experiment that separates them — replay a very
large cached context many times with near-zero output; predicted ≈ 0 pp under the measured fit,
~1 pp per 2B cache-read tokens under API-list. That probe would move the ≤+16% bound to a point, but
it cannot revive +50%, which both hypotheses already exclude.

**Downstream carriers of the struck figure**, corrected or annotated with this block:
`memory-econ-rearchitecture-2026-08-10/prior-art.md` row 55/56 (a LIVE-status ledger — flipped).
~~Left as dated audit records of what was believed on their date, not corrected:
`jcode-due-diligence-2026-08-11.md:53`, `jcode-due-diligence-2026-08-11/bottleneck-audit.md:73`,
`jcode-due-diligence-2026-08-11/ranked-levers.md:36,:54`.~~

### 2b · SUPERSEDED 2026-08-29 — the "dated audit records" disposition was wrong, and it missed the origin

The struck sentence above was a deliberate call, and it is **reversed**. Two defects:

1. **It missed the ORIGIN.** The lever was not born in this file. It was born in
   `scaling-bottlenecks-2026-08-09/07-accounts-api.md` **§6.4**, *"The largest quota lever is context,
   not accounts"* — the subdoc that produced the 68/18/14 composition and that every other carrier,
   including §2a's own row 4, cites as its source. §2a struck the derived rows and left the premise
   generating them untouched, so a reader following the citation trail arrived at live, unqualified
   guidance. It is now struck at source: **§6.4 + the new §6.4a**, with §3's composition line
   relabelled as what it is (an API-list `$eq` split, never a share of the weekly limit).
2. **"Dated audit record" was the wrong classification for prescriptive text.** It fits a verdict
   row recording what was believed (`jcode-due-diligence-2026-08-11.md:53`). It does **not** fit a
   **ranked-lever table that tells a reader what to do**: `ranked-levers.md:36` ranked L7 **#1** and
   said *"Do this first, whatever is decided about jcode"*, justified by the now-dead *"only lever
   that moves both axes"*; and `:108` issued a live **stop-work order** — *"nothing else in this
   ranking is worth building until it is settled"* — resting on a 5-minute cache-TTL figure that was
   `CLAIMED` by one file and measured false five days later (~3600 s; `hooks/cache-expiry-warning.sh:6-16`).
   A recommendation is not made inert by having a date on it.

Corrected 2026-08-29, all by strikethrough-plus-dated-note so every original claim stays readable:
`07-accounts-api.md` §3, §6.4, §6.4a, §7 · `jcode-due-diligence-2026-08-11.md:53, :129 (+ table
note), :258` · `jcode-due-diligence-2026-08-11/bottleneck-audit.md:73` ·
`jcode-due-diligence-2026-08-11/ranked-levers.md:36, :54, :102, :108`.

**Not re-scored, and named rather than done:** whether L7 still ranks #1 on the resident axis alone
once its quota half is removed. Its score `(18 × 0.95)/1 = 17.1` uses an `18` the row's own
arithmetic (`148 − 132 = 16`) does not derive, so a re-score must first recover what the 18 was.
That table now carries a provisional-ranking banner.

### 2c · COMPLETED 2026-09-02 — the two prior sweeps both missed a live site in THIS file

§2a struck the lever at rank 4 (`:36`) and in the standing-policy list; §2b chased it to its origin
and through the jcode cluster. Both then declared the propagation complete. **Neither looked at §4
of the file they were editing**, where the same two refuted numbers were still standing as
prescriptive text: `~3.9 sustained 24/7` presented as a co-binding quota constraint, and
*"cheaper contexts"* named as part of *"the real '15 sessions lag' fix"* — the lever's own
conclusion, in the section a reader reaches for when they want to know what to do. Corrected above,
in the block and in the note beneath it.

**Why both sweeps missed it, which is the transferable part.** Both worked by following
*citations* — grep the quoted premise, chase what cites it, strike each carrier. §4 quotes nothing.
It **restates** the finding in the summary's own words: no `68%`, no `halving`, no citation to
`07-accounts-api` for a grep to land on. A citation-following sweep is structurally blind to a
paraphrase, and a document's own summary section is exactly where paraphrases live. **The rule this
yields: after striking a finding, re-read the whole of every file you edited — the summary and
"what this means" sections first — before you claim the propagation is complete.** Proximity is not
coverage; §2a's edit at `:36` and the live text at `:179` were 143 lines apart in one file.

Also corrected 2026-09-02, same convention (original text kept readable, dated note attached), for
the two derived carriers still quoting the cache-read-priced `3.9` with no correction:
`memory-econ-rearchitecture-2026-08-10/bottleneck-refute.md` (the one-line verdict at `:7` and the
ranked constraint table at `:52` — a table with a *"Binds at"* column is prescriptive under §2b's
own test) and `mcp-memory-groundup-2026-08-10/02-provenance.md:203`. The latter is genuinely a
dated side-by-side of what each wave believed, so it keeps its row intact and takes only a footnote
— the narrow case §2b's *"dated audit record"* classification does fit.

**Sweep basis, so a fourth pass knows what was actually checked.** `git grep` over `origin/main`
for `3.9 (concurrent|sustained)`, `68% of (quota )?(cost|spend)`, `halving context`,
`halve the context`, `shrink context`, `cheaper contexts`, and `smaller contexts` across
`docs/`, `hooks/`, `bin/`, `scripts/`, `commands/`, `skills/`. Every remaining hit is now either
struck, corrected, a footnoted audit record, or the correction text itself. The live policy layer
was clean before any of the three passes (`hooks/cache-expiry-warning.sh` has always told sessions
that shrinking context does not save quota) — only the docs were stale, throughout.

### 2d · COMPLETED 2026-09-03 — §2c's own sweep regex could not match three of the four sites it missed

The fourth pass found **four** live prescriptive carriers of the refuted `~3.9`, all of which §2c's
"Sweep basis" above had declared clean. Corrected here, same convention:

| Site | Why it was still live |
|---|---|
| `memory-econ-rearchitecture-2026-08-10.md:40` | §1 **verdict**, rung 3 — the parent doc of the axis §2c *did* correct. Its subdoc was fixed; its own summary was not. |
| `memory-econ-rearchitecture-2026-08-10/bottleneck-refute.md:119` | §5 summary item 4, in the **same file** as the `:7` and `:57` sites §2c corrected. |
| `jcode-due-diligence-2026-08-11/ranked-levers.md:20` | the **Why it matters** paragraph — the file's load-bearing claim. §2b struck this file's citation-carrying rows (`:44`, `:62`, `:110`, `:116`) and stopped. |
| `jcode-due-diligence-2026-08-11/ranked-levers.md:125` | the last **Unknowns** bullet, same file. |

**The transferable part, and it sharpens §2c rather than repeating it.** §2c diagnosed
*paraphrase-blindness* and prescribed re-reading every file you edited. Correct, but insufficient:
three of these four sites were unreachable by §2c's **own published grep terms**, which required a
literal space and only the adjectives `concurrent|sustained`. Measured against the text:

- `~3.9 active 24/7` — a **different adjective**; `3.9 (concurrent|sustained)` cannot match it.
- `quota sustains ~3.9` / `active` — the phrase is **line-wrapped**, and `grep` is line-based.
- `~3.9-sustained-active` — **hyphenated**, so the space in the pattern fails.

Only `ranked-levers.md:20` matched the regex, and it survived because that file had been assumed
finished by §2b. **The rule: a propagation sweep must grep the bare NUMBER (`3\.9`, `68%`) and read
every hit, never a number-plus-expected-wording pattern.** A regex carrying the phrasing you
remember is a citation-following sweep wearing a grep's clothes — it inherits exactly the blindness
§2c named, because a paraphrase changes the adjective, the hyphenation and the line breaks first.
The bare-number sweep over `docs/ hooks/ bin/ scripts/ commands/ skills/` now returns no unstruck
prescriptive carrier; every remaining hit is a strike, a footnoted audit record, or correction text.

**No conclusion moved in any of the four.** Each is a quota bound that binds *later* than believed,
and all four documents rank quota behind burst ignition and CPU load, so a later-binding quota
strengthens the verdict it appears in. This is a number correction, not a re-ranking.

---

**Felt lag, precisely (12):** turn-end lag is **3.7 s p50 / 7.7 s p90** and 92% of it is ONE call —
`cc-backlog list --blocked --json` (2.1 MB store, ~60 jq forks) inside the Stop readout. Chronic CPU
load never stalls the machine (control tonight: load 53, 0% idle, 21 sessions, max event-loop stall
13 s); **all 91 whole-machine stalls in 47,108 sentinel samples occurred during compressor-segment
ramps** — the felt "lags out, THEN crashes" is the ramp's first perceptible symptom, ~4.5 min before
death, and a specific storm detector (not a death predictor: 82 of 91 stalls were on a day the box
survived).

## 3 · The crash side is NOT closed (05, 10)

| Mechanism | State measured tonight |
|---|---|
| compressor-sentinel SIGSTOP actuator | **ARMED but running STALE bytes** — the live process (04:36) holds fd on the 08-07 script (inode-verified); the parent-breaker (`cb21783b`, today 16:40) is on disk, not in the process. Operator restart FILED (`36c3107a9dc3`; my `launchctl kickstart` was classifier-denied). Until then the armed actuator is the version whose own successor commit says "freezing the horde changed nothing." |
| Wave C cold-compile admission (0006) | **Registered in 0 of 5 config dirs** (c10 migration staged, unratified) — the "LANDED" chokepoint executes on no command. AND (G4) it guards `PreToolUse(Bash)` while the Aug-9 storm ignited from **Edit/Write-driven invalidations** of a long-lived `next-server` — it binds the Aug-5 shape, not Aug-9's. Needs ratification AND re-aim. |
| reso `workerThreads` generator kill | set in **0 of 3** eligible apps (tasks filed: `d60fd1f9c375`, `0e4f795b3a20`) |
| devserver-gc | observe-only by design (`898f8eafb809`, blocked) |
| mailbox-wake-arm (0007) / boot-resume plist | unregistered / shipped-unloaded |
| ramp abort sensor | `capacity-ramp.sh:46` reads a **dead sentinel as pct=0 = healthy** — fails green |
| sentinel at scale (10) | trip base-rate 91/4 days; at design-point margin ≈ 0 ordinary jest/pnpm/tsc (all comm=node, >40 MB) enters the cohort, and **no SIGCONT sender exists anywhere in the tree** — frozen legit work would wedge sessions and retain RSS. Precondition for wider arming: replay the 91 trip snapshots through `select_stop_targets` offline to count would-be casualties. |
| Static residency (good news) | residency itself does not spend segments: 34.5 GiB anon today → **0.22%** of segment limit, swap 0. The crash term stays burst-shaped. |

**Meta-finding:** six mechanisms staged-not-enforced is the fleet's own documented generator
(crash doc §5.1) recurring at program scale. The consolidated remedy is ONE class-C ratification
decision — opened this session (see §6).

## 4 · What the walls mean for the target

```
150 RESIDENT on-box:   REACHABLE only with (a) MCP consolidation/lazy-spawn for resident
                       sessions (~0.5 GB/session back — the single biggest lever on the box),
                       (b) the 340 MB constant held (recycle discipline; age is NOT the enemy —
                       equilibrium age 3.7 h contributes ≤35 MB), and (c) bursts bounded
                       (ratified+re-aimed 0006, workerThreads, sentinel current).
                       Otherwise the honest on-box ceiling is ~100–130 resident.
ACTIVE concurrency:    ~4–8 sustained is what BOTH the box (load slope 2.5–5) and the quota
                       (~3.9 sustained 24/7; 10 for ~39% of the week) support. This is the real
                       "15 sessions lag" fix: fewer simultaneously-ACTIVE turns, cheaper turns,
                       cheaper contexts — not fewer resident sessions.
                       ^^ STRUCK IN PART 2026-09-02 (§2c). The ~4–8 CONCLUSION STANDS, but on
                          the box alone: the quota half (~3.9) was priced off the refuted
                          cache-read composition and measures 6.2–11.0, so quota no longer
                          binds here — and "cheaper contexts" is the dead lever itself.
150+ TOTAL:            residency on-box + the active half split between on-box actives and
                       OFF-BOX sessions. Off-box is 2 small fixes away (06): the payload pushes
                       to an invented branch name (vendor allows only the session's current
                       branch — `git switch -c` first, the fix the repo documented and never
                       carried into the payload) and fires skip the existing preflight. 54.5%
                       create → ~91%/fire with 3 retries; 128 backlog items already eligible.
                       Per-session token draw (T3) still unmeasured — the honest off-box number
                       until then is ~10, not 110.
```

**Correcting the ACTIVE-concurrency line (2026-09-02, §2c).** Read it as: **~4–8 sustained, bound
by the BOX** — the load slope of 2.5–5 runnable threads per genuinely-active session against the
load-20 gate (§2 r2). The quota is no longer a co-binding constraint at that level: rank 4's
`~3.9 sustained 24/7` was priced off the cache-read-at-68% composition that §2a refuted, and the
model-free replacement is **6.2–11.0** (`orchestration-units-2026-08-19/A6-VERIFY-quota-economics.md`
§C4), which sits at or above the box's own ceiling. `10 for ~39% of the week` is unaffected and
stands. And the prescription's third term, *"cheaper contexts"*, **is the struck lever** — it is
`+50% capacity by halving context` in summary form, and it dies with it. The surviving two terms are
the right ones and are now better-founded, not worse: **fewer simultaneously-ACTIVE turns** (the box
constraint) and **cheaper turns** (output and cache-creation are the classes the meter actually
charges, at 1.282 and 0.105 pp/Mtok). Context volume is not a term in the quota at all.

**Render/headless correction:** hidden/occluded windows being free means plain kitty tabs already
deliver the "headless" render win with zero build. Wave E's substrate matters for a different
reason than the program thought: **33 pane-less sessions already run in this fleet and are already
invisible** — the registry keys on kitty's reusable small-integer window ids (a fake pane UUID),
subagents share pids, and the headless-precondition "PASS" leaked a pane id into its own probe
child (03). The substrate spec (03: 15+8 edits, identity = session-id + pid,lstart + beat
freshness; wake = migration 0007 + FIFO user-message) is CORRECTNESS work for the fleet that
already exists, not render work.

## 5 · The drive plan (dependency order)

**P0 — free, this week, no decisions** *(each item's evidence axis in parens)*
1. Operator: restart the sentinel job — FILED `36c3107a9dc3` with the exact command (05).
2. Guard or remove `setup-task-symlinks.sh` from SessionStart — today it burns ~4 s CPU / ~800
   forks per session start, is killed by its own `timeout: 5`, and its output is discarded; 2,155
   task dirs, 97% empty. Cutting it cannot regress a thing (04).
3. Take the `cc-backlog --blocked` fold off the Stop path (cache or async) — **~3.4 s of felt lag
   back per turn-end**; compact `backlog.jsonl` (12).
4. Land the wrap-ledger transcript-keyed memo (key = `session_id ⊕ stat -f '%m %z' transcript`,
   2.25 ms; absent-key ⇒ no cache): 1,260 → 216 ms and 133 → 19 git per Stop; fixes the withdrawn
   memo's staleness defect by re-scoping the key, not by fingerprinting stores (04).
5. Fix `render-census.sh`: add the kitty arm, stop charging 100% of WindowServer (4 displays + a
   browser at 73% CPU) to terminal render (02, 09).
6. Add the 5-line freshness check to `capacity-ramp.sh breach()` so a dead sentinel reads DEAD (10).
7. Adopt `bash script.sh` over `./script.sh` for fresh-inode invocations (worktree setup, spawned
   tools): first-exec assessment is 121 → 2.9 ms, inode-keyed (hardlinks share it; copies re-pay).
   NOT a hook-path win — same-inode re-exec is already free (11, 04).

**P1 — the one decision + its preconditions**
- **⛔ Class-C packet (opened this session): ratify the staged c10 migrations** — 0006
  cold-compile admission + 0007 mailbox-wake-arm + boot-resume plist + `DEVGC_ACT=1` — the
  six-mechanism staged-inert gap in one decision. Preconditions attached: the 91-snapshot offline
  replay (bounds sentinel false-positive casualties before wider arming) and the 0006 re-aim at the
  Edit/Write ignition shape (05, 10).
- Build the sentinel's SIGCONT/unfreeze arm — an actuator with no release path is a freeze
  machine at design-point margins (10).

**P2 — the capacity builds (unblocked, parallelizable)**
- **MCP consolidation** for resident sessions (shared daemon or spawn-on-first-use): recovers
  ~0.5 GB/session — the difference between ~100 and 150+ resident (08).
- **KMAX re-derivation**: key the router cap on ACTIVE sessions (its real risk), not resident
  count; today one integer refuses the 33rd session. Also fix `concurrency()` failing OPEN on ps
  timeout — it disarms both KMAX and heal()'s rotation gate (07).
  **DONE 2026-08-13** → `docs/plans/ACCOUNT_ROUTING_V2.md` §15. `KMAX` is now the ACTIVE cap (8,
  unchanged) and `KMAX_RESIDENT` (40) the resident one, selected per row by the INSTRUMENT that
  charged it (`k_src` / `k_cap`, shared with the KF denominator). `concurrency()` returns `None`
  on an unreadable `ps` and all three gates refuse on UNKNOWN — the third being
  `handoff-fire.sh`'s pre-fire sweep, which re-spells the rotation gate as `(.k // 0)` and was not
  in 07 §6.5's count.
- **oauth herd**: jitter refresh within an account + let heal() run with live sessions (08).
- **off-box**: the `git switch -c` payload fix + preflight call + 3-retry wrapper; then measure T3
  per-session draw before claiming any number above 10 (06).
- ✅ **DONE 2026-08-13** (`61e39ef3`, backlog `1c45598a91be`) — **Wave D re-termed** (now
  evidence-backed): admission keys on ACTIVE concurrency (ceiling ~8) with a memory term that can
  actually bind (compressor/swap-aware — 0 of 127 refusals ever came from memory). The design
  point's "~10 active" finally gets its enforcement (09, 13, 07). Shipped as `segments` (50%,
  provisional and re-derivable from its own rows) + `active` (8) + `reserve-active` (1, on proven
  presence) in `scripts/lib/capacity-admit.sh`, with the mid-turn census in
  `scripts/lib/spawn-presence.sh`; D7 closed by decision rather than by waiver. Details and the
  three corrections the build produced: `docs/plans/CONCURRENCY_PROGRAM.md` §S6.6-LANDED. **This
  closes the F3 half that a SPAWN gate can close and no more** — axis 10's thundering-herd path is
  a *wake* of existing residents, which no spawn gate sees by construction, so wake-side damping
  remains open and unowned.
- ~~Standing policy: **context stewardship IS capacity** — median turn context ~200K, 68% of quota
  cost is cache-read; halving context ≈ +50% sustainable active work (07).~~
  🚨 **STRUCK 2026-08-24 — see §2a.** Measured Opus-5 cache-read is **0.000 pp/Mtok**, so this
  bullet's premise and its lever are both refuted, and `exchange-rate.md` R1 gives the opposite
  advice (*re-reads are ~free; only output and cache-creation cost*). Context stewardship remains
  standing policy on its own grounds — the hard `Prompt is too long` ceiling and decision rot — but
  it is **not** a quota lever. Replacement standing policy: **quota is spent by what you EMIT, not
  by what you re-read**; the sustainable-active figure is A6 §C4's model-free **6.2–11.0**, not the
  cache-read-priced 3.9.

**P3 — prove it (only after P1+P2):** D1 ramp 19→40→80→150 with the fixed abort sensors;
D8 re-specified (cold compile at ≥80 needs its synthetic-spawn contradiction resolved, 05);
oauth/KMAX/gc watched at each stage per 08's flip conditions.

## 6 · Instrument corrections this wave adds to the series' ledger

1. `render-census.sh` sums iTerm2 on a kitty fleet (the FIFTH same-day artifact) — and separately
   charges all of WindowServer to render (02, 09).
2. CC transcripts repeat `message.usage` once per content block — **dedup on `message.id` or
   overcount ~2.1×** (bit axis 7's own first pass) (07).
3. Transcript-span session age is length-biased by `--resume` (34.6 h vs a true 3.7 h equilibrium —
   would have manufactured an age effect) (01).
4. Hooks run in PARALLEL (observed live + vendor doc) — `hook-chain.sh`'s serial model would turn
   max() into sum() and double turn-end lag if ever "fixed" (12, 04).
5. The felt-lag replay rig must pin `CLAUDE_CONFIG_DIR` (not `$HOME`) — sessions here run
   config-rooted at `~/.claude-tertiary` (04); and `relay-verbatim.sh` false-fires on greps that
   merely contain `cc-do` (12).

## 7 · Filed / opened this session

| What | Where |
|---|---|
| Sentinel stale-bytes restart (operator, exact command) | backlog `36c3107a9dc3` |
| Class-C c10 ratification decision (0006+0007+boot-resume+DEVGC_ACT, with preconditions) | `cc-decide` packet (this session) |
| MCP resident-session memory consolidation | backlog (this session) |
| Off-box payload `switch -c` + preflight fix | backlog (this session) |
| claude.exe 4–40 GB burst trigger identification | backlog (this session) |
| Everything else in §5 | this doc + the per-axis artifacts; the S6 program (scale-150 session) owns intake — notified |

**Residuals, named honestly:** the claude.exe self-burst trigger (01, no argv in the historic
sampler); WindowServer's true per-pane slope under a closed-browser control (02, operator-gated);
whether kitty enjoys the Developer-Tools exec exemption (11, one settings toggle to test); T3
off-box token draw (06); the Write/Edit event rate (04's one unmeasured rate).
