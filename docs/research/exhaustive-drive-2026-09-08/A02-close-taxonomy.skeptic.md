# A02 — SKEPTIC: Taxonomy of closes that left drivable work

Wave exhaustive-drive 2026-09-08. Read-only. Every number below: **measured** = I ran it (command given);
**inferred** = derived. Instruments in
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/b418b97a-d3ec-4444-b993-4f29d55f425a/scratchpad/a02skep/{relex.py,nonidle.py}`
run over the axis's own `idle_classified.jsonl` (2,045 rows) and `session_class.json`.

## Verdict in one paragraph

The axis's **mechanical counts reproduce exactly** (2,045 idle · 1,035 EOF/1,010 human · FORM 460/242/63/607/673 ·
NAME_TELL 5 · gap median 40 min · backlog `d0afa40677ef` done 2026-08-21). Its **flagship receipt is false**: R-5 was
fixed on `origin/main` the day after the teammate's close (`c7b2d45090`, 2026-08-23); the axis grepped a 30-line file
in a local checkout frozen at 2026-08-16 over a line range (79-102) that does not exist — a vacuous zero. Its
**population is 24% non-closes** (490/2,045 API errors, `ok`, permission-decider verdicts, login stubs), not "2 of 88".
Its **hand-read verdicts are recorded nowhere** (`sample.txt` carries 0 TRUE/FALSE marks); my own read of 24 closes in the
C7-heavy strata gives 7/24 (29%; 7/20 = 35% net of noise) vs its 36–44%. Two headline numbers are misreads: the
"13.2% turn-text tell rate" counts `no-assistant-text` and `team-assignee` abstains as tells (real: 5 tells / 558
evaluations ≈ 0.9%, of which **3 fired** — 60%, not 4.8%), and "566 of 607 F4 are origin" is the count of ALL silent
origin closes (F4+F5); origin F4 is 167, of which 47 are noise and 54 carry an Edit/Write tool. The diagnosis
"prose findings have no store" survives (independently supported by reso commit `6841403fc9`'s body: "AXIS-4 ran and
nobody harvested it… thirteen findings exist in no store"), and the order of magnitude — several hundred idle closes a
month naming drivable work — is plausible. The specific remedies are weaker than stated.

## Numbers re-checked

| claim | claimed | re-checked (command) | holds |
|---|---|---|---|
| idle closes | 2,045 (1,035 eof + 1,010 human) | 2,045 / 1,035 / 1,010 — `relex.py` over `idle_classified.jsonl` | yes |
| FORM axis | 460/242/63/607/673 | identical recount from `cl` field | yes |
| NAME_TELL on close text | 5 / 2,045 | 5 — `/usr/bin/grep -iqE "$NAME_TELL"` per text, regex read from `hooks/dispatch-assert.sh` | yes |
| broad follow-on vocab | 610 (29.8%) → "122× gap" | **314 (15.4%)** with the regex the report quotes → ~63× | **no** |
| "no shipped arm" | 1,790 (87.5%) | 1,814 (88.7%) with TELLS/NAME_TELL/CA_HANDOFF only | yes (robust) |
| human-gap median / ≥30 m / ≥60 m | 40 min / 598 / 376 | 40.4 / 598 / 376 | yes |
| instrument noise | "at least 2 of 88" | **490 / 2,045 (24%)**: apierr 130 · oneword 131 · short<40 112 · notools-short 79 · decider 38; **10 of 88 sampled**; 459 of the 490 sit in C7, 363 in F5, 127 in F4 | **no** |
| R-5 "still unfixed 17 d" | `sed -n 79,102p … | grep -c contentBounds` → 0 | file is **30 lines** (range empty ⇒ vacuous 0); checkout HEAD `3f07ef517` = **2026-08-16**; `git show origin/main:lib/floor-plan/venueSvgData.ts` lines 118-135 validate `contentBounds` REQUIRED; `git log origin/main -- venueSvgData.ts` → `c7b2d45090 2026-08-23` ("contentBounds has been REQUIRED… nothing checked it… isVenueSvgData validated name/documentWidth/…") | **no — fixed next day** |
| backlog d0afa40677ef closed 2 d later | done 2026-08-21T15:06 | `grep d0afa40677ef ~/.claude/autonomy/backlog.jsonl` → `2026-08-21T15:06:54Z done` | yes |
| dispatch-assert turn-text tell rate | 13.2% (62/469), fires 4.8% | IDL today: 558 records — 496 `no-naming-tell`, 38 `no-assistant-text`, 19 `team-assignee:*`, **2 `discharged`, 3 fired** ⇒ tells 5/558 ≈ 0.9%, fire-on-tell 3/5 | **no (both numbers), conclusion stronger** |
| "607 F4, 566 origin-class" | 566 | origin-class F4 = **167** (47 noise; 54 with Edit/Write tool). 566 = all silent origin closes F4+F5 | **no** |
| origin silence | 68% | 68% gross; **49%** net of noise (261/528) | partly |
| F4 = "wrote tracked files" | 607 | 288 have Edit/Write; **319 are Bash-write only** (heuristic counts `python3 -c`, `mkdir`, `cp `, `rm `, `touch `) | over-inclusive |
| S6 "25% vs 44% — arms work" | 2/8 | 2/8 (1 is noise ⇒ 2/7); Wilson95 [0.07, 0.59] contains 0.44 | **not supported** |
| hand-read 36/85 TRUE | recorded in `sample.txt` | **0 TRUE/FALSE marks on disk**; my read: S7a 3/8 · S7b 2/8 (4 noise) · CONTROL 2/8 ⇒ 7/24 | unverifiable; my estimate lower |
| cited file:lines | dispatch-assert :8-14, :236; anti-def :154/157/170; CA_HANDOFF/CA_NEG | header :6-14, NAME_TELL ≈:236; :154/:157/:170; :775/:785 | yes |
| D6 gating explains silent-close exemption | guessed | `completion-assert.sh:250` abstains `no-close-tell` before D6 (:900+) is reached; D6 also requires ledger ✅/👤 + `session_writes_paths` positive | **confirmed** |

## The fail-direction number the axis never took

A mechanical "write turn + no glyph + no verdict" gate (R1/R2) fires at Stop, when idleness is unknowable. On a
300-transcript subsample (`nonidle.py`, seed 7, same corpus iterator): silent+write(any) closes split
**75 quick-human-reply (<10 min) : 44 idle-human : 42 EOF**; strict Edit/Write: **38 : 19 : 14**. Roughly half of
every fire would land on a live conversation the operator answered within minutes. Measured, n=300 files, 614 closes.

## Per recommendation

**R1 (store-or-silence at terminal close, 72%)** — REFUTED as stated. (a) Arm (i) "zero sentences asserting unfinished
state" is a lexicon by another name — the exact thing the axis condemns in R3. (b) Arm (ii) "≥1 store record since
turn-start" IS `dispatch-assert.sh:162 discharged_since` — "any verb" backlog event — which the same report calls
`gate-on-presence-is-cleared-by-any-string`. (c) The `follow-on: <ids|none>` clause already exists in CLAUDE.md S2 and is
matched by `close-shape.sh` (`good-to-close-verdict`, :243) — R1 adds nothing to D6 except population, which is R2.
(d) Its support (§2c 25% vs 44%) rests on 2/8 with Wilson [0.07, 0.59]. (e) Nag denominator ≈ 1:1 live:idle (above).
Fails toward NAGGING on live conversations; trains route-around via boilerplate "follow-on: none". Adjusted 25%.

**R2 (bind line-1-rung on silent origin closes, 55%)** — REFUTED on its numbers, diagnosis CONFIRMED. The D6 exemption is
structural (`no-close-tell` at :250), as the axis guessed. But the population is 167 origin F4, not 566; 54 after noise
and the strict write definition; and 49% (not 68%) of real origin closes are silent. A gate on "wrote + silent" fires
~1:1 on live vs idle stops. The honest alternative the report offers — "state that silent closes are exempt and accept
the hole" — is the one the evidence supports until a gate can key on something other than the phrase. Adjusted 35%.

**R3 (do not widen NAME_TELL; retire or leave, 85%)** — HOLDS, evidence corrected. Reach is 5/2,045 close texts and 5
tells / 558 turn evaluations today (0.9%), not 13.2%; fire-on-tell is 3/5, not 4.8%, so the "discharged by unrelated
writes" story is 2 events, not the mechanism's dominant mode — though `discharged_since` "any verb" (:165) is real.
Not widening = correct (denylist-enumerates-spellings). Removal alone fails toward SILENCE; leaving it costs ~0.3 s/Stop
(lead-measured). Adjusted 85% on "don't widen", 40% on "retire".

**R4 (peer-tier drain into cc-backlog, 65%)** — REFUTED on evidence, diagnosis PARTLY SUPPORTED. Both spot-checks now
show the finding WAS drained (R-5 fixed +1 d; d0afa40677ef closed +2 d): 0/2 permanent loss. The "~709/30 d peer leak"
therefore has no receipt of permanence; it is re-derivation cost of unknown size. Independent support for the diagnosis
exists (reso `6841403fc9` body, AXIS-4's 13 unharvested findings). Mechanism fails toward VOLUME (~24 rows/day into a
queue with 181 blocked) — the report says so itself and still assigns 65%. Adjusted 40% on diagnosis, 20% on mechanism.

**R5 (no lexical 'decision' arm, 88%)** — HOLDS. C4 hand-read 4/16 (my S7b/#13 read agrees: most are credential /
visual-sign-off / money gates). Write-time `--conviction/--receipt` gate is the right shape; fails toward silence by
design, accepted. Adjusted 85%.

## What the axis MISSED that its question required

1. **Whether the work was later done.** The taxonomy of "closes that left drivable work" needs the outcome axis
   (permanent loss vs re-derived vs harvested). Both spot-checks resolve to harvested within 1–2 days; the headline
   "83% invisible" is a statement about the close, not about the work.
2. **Population hygiene.** 24% of the denominator are not closes; the sample under-represents them by half (11%), so
   the C7 extrapolation (733) applies a real-close rate to a padded population. Net estimate ≈ 1,555 real closes × ~0.45
   ≈ 700, or ~550 at my read rate.
3. **The scoring record.** 36/85 exists only in the axis's context — "reasoning never committed and never written to a
   doc: NONE EXISTS" (CLAUDE.md). Unverifiable by construction.
4. **Stale checkout.** The R-5 receipt was taken in a checkout 23 days behind `origin/main` without checking HEAD date —
   `clean-worktree-cannot-distinguish-never-worked-from-landed` / `miss-is-not-absence`.
5. **The non-idle denominator** for any Stop-time gate (above): a Stop hook cannot see idleness, so every remedy's
   false-positive rate is set by live-conversation stops, which the axis never counted.
6. **IDL field semantics.** Subtracting `no-naming-tell` from total evaluations and calling the remainder "tells"
   folded 57 non-tell abstains into the numerator.
7. **"operator-typed" is a residual class** — 305/833 (37%) of it is noise, so it is the DIRTIEST tier, and its "cleanest
   22.9%" is a rate over a population one-third non-closes.
8. **Bash-write heuristic** (`python3 -c`, `mkdir`, `cp`) turns read-only analysis sessions into "write turns" — 319 of
   607 F4 rest on it.

## Failure directions, summarised

Every R1/R2-style mechanical gate errs toward nagging live conversations (~1:1); every R3/R5 restraint errs toward
silence on genuinely abandoned work, which is the wave's target defect. The evidence here does not license a new
Stop-time arm; it licenses a harvest audit (does a peer's named finding appear in a later commit/row within N days?)
before any producer is built.
