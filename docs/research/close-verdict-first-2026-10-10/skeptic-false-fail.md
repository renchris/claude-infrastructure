# Skeptic review (false FAILs and regressions): CLOSE_VERDICT_FIRST design A′

Date: 2026-10-10. Subject: `design.md` in this directory, tested on the designer's own prototype (`/tmp/cvf-design/proto/hooks/`). I copied that prototype over a `git archive HEAD` tree at `/tmp/cvf-skeptic-false-fail/repo`; the HEAD baseline is `/tmp/cvf-skeptic-false-fail/head`. No tracked file was edited and no git write was run. Every number below names the command or script that produced it.

## Verdict

**SURVIVES-WITH-FIXES. Conviction: 85%.**

**What the review confirms:**
- The design refuses its target, the LEFT screenshot close.
- It leaves the RIGHT close alone.
- It adds no false FAIL on any close that exists in the 30-day corpus.

**Problems found:**
- I built five honest closes that HEAD passes and the prototype blocks. They come from three causes (P1, P2, P4).
- Two claims in the design are wrong:
  - "The D3 changes can only move FAIL → PASS, so they need no switch."
  - "The refusal fires on no yes close." This was true *by construction* in `measure_d3.py`, not measured.

**Fixes:** each one is a line or two. On the 546-close validation set they keep all 296 of the design's target refusals and lose none (`fix/val.sh`, below).

**What I could not verify:** the existing bats suites. cc-bats refused every attempt with rc 75 at a load of 45–80 on 10 cores (`/tmp/cvf-skeptic-false-fail/bats-proto.out`). That is a deferral, not a result. My static audit of those suites is in §4.

## 1. Method and instruments (scratch, `/tmp/cvf-skeptic-false-fail/`)

| Instrument | What it does |
|---|---|
| `eval.sh <file> [rung]` | Sources the prototype lib. Lifts `CLOSE`, `CA_SETTLED`, `CA_RETRACT` and `CA_VERDICT_*` from the prototype hook by their `^NAME=` lines. Prints polarity, done-reading, gate (old→new), D3 (old→new), verdict-first, rung window (old→new) and the verdict/act tokens. |
| `replay2.sh` + `v/*.txt` | The design's own real-hook harness (stub ledger, origin pane, one Edit), repointed at my copies. It runs HEAD and the prototype end to end. |
| `tools/extract.py 30` | Pulls 30 days of closes from all 5 account roots, deduped by realpath, with subagents skipped. **Measured: 22,438 closes, of which 5,280 carry the verdict anchor (4,982 transcripts).** |
| `tools/scan.py` | A Python port of `close_verdict_polarity`, `close_line_reads_done` and the new D3. **Validated against the real bash functions** (`val/run.sh`): 546 of 546 closes agree (all 296 refusals plus 250 random), under both `en_CA.UTF-8` and `LC_ALL=C`. |
| `fix/fixlib.sh`, `fix/vno.sh`, `fix/val.sh` | Prototypes of the fixes below. Bare `shellcheck` returns rc 0. |

## 2. False FAILs: honest closes the prototype newly blocks

Each fixture below ran through the real hook (`replay2.sh`, rung ✅, origin session, one write). "HEAD" is today's hook; "PRO" is the prototype.

| Fixture (abridged) | HEAD | PRO | Cause |
|---|---|---|---|
| F1 `✅ Good to close — no loose ends; follow-on: none.` / blank / `✅ Complete & live on trunk — …` | PASS | **BLOCK shape [verdict-first]** | P1 |
| F5 `✅ Complete & live on trunk — …` / `Good to close: no loose ends, nothing of mine is open; follow-on: none.` | PASS | **BLOCK shape [verdict-first]** | P1 |
| F3 `✅ Good to close: yes — with the reconciler in act mode, nothing of mine is open; follow-on: none.` / rung | PASS | **BLOCK hedge** | P2 |
| F13 `✅ Good to close: yes — after this push nothing of mine is open; …` / rung | PASS | **BLOCK hedge** | P2 |
| F14 `✅ Good to close: yes — the pane that was not good to close at noon is fixed; …` / rung | PASS | **BLOCK hedge** | P2 |
| F10 `Yes, good to close. Nothing of mine is open; …` / blank / `✅ Complete & live on trunk — …` / `It now refuses a close that says Good to close: no under a ✅ line 1.` | BLOCK (line-1-rung) | BLOCK, missing = **[verdict-first] only** | P4 |
| F8 `Complete? No — Good to close: no; pane 182 owns the reconciler change.` / blank / rung | BLOCK | BLOCK [verdict-first] | P3 |
| Controls: LEFT verbatim / LEFT reshaped to A′ | PASS / BLOCK | BLOCK / PASS | (as the design claims) |

**How often these occur today:** none of these shapes appears in the 30-day corpus, so they are not fatal.
- **P1:** of the 3,434 verdict lines whose value is "no", every one has punctuation after the word, never another word (`scan.py` follow-up count).
- **P2:** 9 of 1,800 yes verdict lines fire the new D3, and all 9 are real conditionals ("yes if…", "yes, once…", "yes, but not until…"). None uses `with` or `after`.
- **P2:** the both-polarities branch fires on 0 of 5,254 verdict lines.

They are still worth fixing, because A′ moves the verdict line onto line 1, where D3 and the done-reading test look. The current corpus therefore under-samples the future population.

### P1 (fix required). Polarity reads a YES phrased "no loose ends" as NO

**Mechanism.** `close_verdict_polarity` replaces the dashes with spaces (`gsub("—", " ", rest)`) before it tests `^(no|not)([^a-z]|$)`. After that, "no — pane 182 owns it" and "no loose ends" look the same. `CA_VERDICT_NO` in the hook has the same flaw (`…close[^a-z]*(no|not)([^a-z]|$)`).

**Why it matters.** The operator's own standing question is worded "…no loose ends or follow-on work?". A yes that echoes it is a natural sentence. P1 is the only path by which an honest close that **HEAD passes** gets the *verdict-first* refusal.

**Minimal fix.**
- **Lib:** a "no" counts only when punctuation follows it (after optional spaces) or it ends the line. Strip leading dashes in a loop instead of replacing every dash in the line:

  ```awk
  while (sub(/^[ \t*_:?!.,`-]+/, "", rest) || sub(/^—/, "", rest) || sub(/^–/, "", rest)) { }
  if (rest ~ /^yes([^a-z]|$)/) { y = 1; next }
  if (rest ~ /^not([^a-z]|$)/ || rest ~ /^no[ \t]*([^a-z \t]|$)/) { n = 1; next }
  ```
- **Hook:**

  ```bash
  CA_VERDICT_NO='(^|[^a-z])(not|isn.t|aren.t)[[:space:]]+((yet|quite)[[:space:]]+)?good[[:space:]]+to[[:space:]]+close|good[[:space:]]+to[[:space:]]+close[^a-z]*(not([^a-z]|$)|no[[:space:]]*([^a-z[:space:]]|$))'
  ```

**Measured on the fix:**
- With `/usr/bin/grep` (`fix/vno.sh`): every real "no" form matches under both UTF-8 and `LC_ALL=C` (9 of 9). Those forms are `no —`, `— no.`, `**no**`, `? No`, `not yet`, `❌ … no`, `isn't good to close yet` and `❌ Not good to close`. Neither "no loose ends" nor "no follow-on" matches.
- On the validation set, `fix/val.sh` keeps 296 of 296 refusals, loses 0 and gains 0.
- Add F1 and F5 to the design's test T4/T14 neighbourhood as must-not-fire cases.

### P2 (fix required). The D3 verdict-line branch adds a FAIL class without a switch, and two of its words are honest

**Mechanism.**
- §3.5 says "the rung-window relaxation and the D3 and gate changes can only move FAIL → PASS, so no switch is needed." That is false for D3. `CA_YES_HEDGE` and the `VYES && VNO` branch fire on line-1 verdict lines that today's D3 passes (F3, F13, F14, and the design's own `yes, once pane 182's change lands`). The design's §7.2 lists the conditional-yes class but never connects it to the kill switch.
- D3 has **no origin, peer, assignee or write gate**. `grep -n 'd3=' hooks/completion-assert.sh` shows only `:958 d3=0` and `:1058 d3=1`. The new branch therefore reaches fired peers, assignees and write-free Q&A sessions as soon as they lead with a verdict.

**Minimal fix.**
1. Drop `with` and `after` from `CA_YES_HEDGE`. Measured: they account for 0 of the 9 corpus fires. "yes — with X in act mode" and "yes — after this push" describe the past; they are not conditions.
2. Delete the `VYES && VNO` branch. It catches nothing in the corpus (0 of 5,254 lines), and F14 shows its one real effect is a false FAIL. Its only plausible target ("yes if…, no if…") is already caught by the `if` in `CA_YES_HEDGE`.
3. Put the remaining `CA_YES_HEDGE` branch behind `[ "${CC_VERDICT_FIRST:-1}" != 0 ]`, so the one kill switch silences every FAIL the land adds. Correct the §3.5 sentence.
4. Add a test: `✅ Good to close: yes — with the reconciler in act mode, nothing of mine is open` must not fire hedge. Add a second test pinning that `CC_VERDICT_FIRST=0` silences T5.

### P3 (minor). The done-reading test counts a leading NEGATIVE answer as done

`close_line_reads_done` returns true for each of the following (`eval.sh`, fixtures `c/p_*.txt`):
- `Safe to close: no — …`
- `Safe to close? No — …`
- `Complete? No — …`
- `Done? Not yet — …`
- `Safe to close — not yet.`
- `Completeness check: 2 of 5 rows are still open.` (`complete` has no word end)

**When this costs anything.** Only when line 1 also carries the anchor (which widens the rung window) or the rung glyph. Otherwise `line-1-rung` blocks the close on both HEAD and PRO (F8 is BLOCK on both), and the only harm is a reason that says "your line 1 opens with a done reading" when it does not.

**Frequency.** Measured: 0 of 5,280 anchored closes have such a line 1 (`scan.py` line-1 census).

**Fix.**
- Use `complete(d)?([^a-z]|$)`.
- Reject a done token that a `?` or `no`/`not` immediately follows:

  ```bash
  ! printf '%s' "$s" | grep -iE '^(complete(d)?|done|all done|safe to close)[^a-z]*(\?|(no|not)([^a-z]|$))' >/dev/null
  ```

  (In `fix/fixlib.sh`: the six probes above flip to not-done, the LEFT close still reads as done, and 0 of 296 refusals are lost.)

### P4 (minor). A yes in "Yes, good to close." form has no polarity, so a quoted no flips the close to NO

**Mechanism.** The verdict value is read only *after* the anchor, so `Yes, good to close.` / `Yes — good to close.` / `**Yes, we're done and good to close.**` return polarity `none`. Measured: 27 corpus closes have a yes-before-anchor verdict that reads as `none`.

**Effect.** Any unfenced mention elsewhere in such a close turns the whole message into polarity `no`. Examples: "pane 182 said Good to close: no", or this feature's own implementer describing it. `close_line_reads_done("Yes, good to close.")` is true, so verdict-first fires. F10 shows it: on PRO it is the **only** missing token, on a close that is otherwise exactly the A′ teaching with the verdict first.

**Frequency.** Measured: 0 corpus occurrences today.

**Fix.** In polarity, check the text before the anchor symmetrically:
- `pre ~ /(^|[^a-z])yes[^a-z]+((it.?s|we.?re|this is|this session is)[ \t]+)?$/` gives y.
- Widen the existing negation to `(not|isn.t|aren.t)[ \t]+((yet|quite)[ \t]+)?$`. This also catches the corpus's "So it isn't good to close yet." (1 instance), which reads as `none` today.

## 3. Regressions and arm interplay

### P5 (minor). verdict-first draws on the `shape` cap, so it can starve the terminal close's demand

- **The cap.** verdict-first joins `_d6_missing`, and therefore class `shape` with `COMPLETION_SHAPE_MAX=2` per session.
- **Measured** (`scan.py`): the 296 refusals come from 92 sessions; 48 had ≥2, 33 had ≥3, and 19 had ≥5.
- **The risk.** It is a session habit: leads repeat the shape every turn. So two refusals before the model adapts spend the whole shape budget. A later terminal close that omits its verdict or rung then abstains `capped:shape:2>=2`. The CAP SPLIT commentary (`completion-assert.sh` latch block) exists to prevent exactly that: a terminal demand starved by a counter the earlier turns spent.
- **Mitigation.** The re-close after a refusal has a new hash and normally complies, so the real rate depends on how often models revert. That is unmeasured.
- **Fix (optional).** Give verdict-first its own class (`verdict`, with `COMPLETION_VERDICT_MAX=2`), or charge it to `shape` only when it is the sole missing token. If neither is done, state the trade-off in §7.

### P6 (minor). The close-tell gate change skips every downstream arm

- `! grep CA_VERDICT_NO "$ca_first"` makes a message abstain `no-close-tell` when it has no CLOSE token and line 1 is a no verdict.
- That skips the ledger arm (the design's intent), but also D1, D2, D4, D5, D6 and D7.
- **Measured:** 6 of 5,280 anchored closes (30 d) newly abstain. All 6 are of the form "Good to close: no — two decisions are yours…" (`scan.py` gate replay). This weakens existing gates slightly; the weakening is real but small.
- **Fix:** accept it and record the count in §3.3. The current text says only that it "restores today's population".

### P7 (minor). T24's claim "the two matchers cannot drift apart" is overstated

`CA_VERDICT_NO` (grep, any match on the line) and `close_verdict_polarity` (first anchor on the line, punctuation stripped) already disagree on real shapes:

| Line | grep | awk |
|---|---|---|
| `Good to close (no)` | no | none |
| `Good to close: yes — … not good to close …` | no | yes |
| `isn't good to close` | miss | miss (miss in both; no disagreement) |

An "equality per row" table can only hold the rows on which they agree.

**Fix:** list the known divergences in T24, or have the gate and D3 call one polarity function.

### P8 (minor). Sibling block reasons still teach the rung on line 1

| Reason | Text that conflicts with A′ |
|---|---|
| D3 | "Pick the ONE rung that actually governs … Line 1 answers 'is it safe to close?'" |
| D1 | "re-close: line 1 states the rung (👤 when steps are yours)" |
| D4 | "…which then IS your line-1 rung" |
| D5 | "ask for it as your line-1 rung" |

- This causes no false FAIL, because the window accepts the rung on line 1 or 2.
- But when D3 and verdict-first co-fire on a C-style ✅ no line, one block reason carries two placements that compete.
- **Fix:** reword the D3 tail (and, cheaply, the D1 tail) to "line 1 is the verdict, answered once; the rung goes under it."

### P9 (minor). Not in the design's §4: the research relay arm keys on the first line

- In `scripts/research-kit/router.py`, `relay_violations` blocks a reply whose first line matches `OPENS_NO` (`^\W*(…|good to close:\s*no)`, re.I) unless it cites escape, freshness or accepted.
- Under A′, every honest no opens "no". Today the old shape opens ✅, which `OPENS_YES` matches.
- The arm sits above D6 and blocks in its own `relay` class. It applies only to a research program in the certifying or certified state, after a routed completeness question, so the population is narrow.
- **Fix:** record it in §4. The arm's own rule ("only an event moves the answer") is arguably still right; it is outside this land's scope.

### Checked and found sound

**Static checks.**
- **Shellcheck:** bare `shellcheck` (the land gate's invocation) returns rc 0 on both prototype files and on HEAD.
- **bash 3.2:** `/bin/bash -n` passes on both files, and `scripts/bash32-parse-lint.sh` reports "2 script(s) parse under bash 3 — clean".
- **SIGPIPE ratchet:** `scripts/pipefail-sigpipe-lint.sh --regen` gives `hooks/completion-assert.sh 5` on both prototype and HEAD. The new `printf | grep -iqE` adds no ratchet violation.

**Tools in the hook's environment.** The hook's `awk` is `/usr/bin/awk` 20200816, which works byte by byte. Its `grep` is BSD 2.6.0 (my zsh `grep` is ugrep, but bash does not inherit that function). `[^a-z]` folds case under `-i`, so `GOOD TO CLOSE: NO` matches and `YES — no` does not.

**The design's corpus numbers reproduce:**
- 296 refusals: 294 ✅-led and 2 "Done and landed." (`scan.py`).
- Every one of the 296 has exactly one anchor line with a no-plus-punctuation value.
- 30 of 30 randomly sampled refusals are genuine no verdicts under a ✅ line 1. Most are mid-programme leads ("I still hold custody of W5b2's shadow watch").
- D3 on verdict lines: 9 of 1,800 yes lines and 0 of 3,454 no lines.

**Exemptions hold.** The verdict-first token sits inside D6's `_d6_ok && _ca_source_close_shape` block, so it inherits:
- the origin, assignee, write-evidence, `contra_shape=0` and RUNG ∈ {✅, 👤} gates;
- fail-open via `command -v close_verdict_polarity`.

**Caveat on the "origin" gate.** `oi_origin_class` treats an unproven peer as origin. A fired peer that is misclassified (for example, one whose brief arrived mid-turn) therefore inherits the new demand on its own "no" closes. Origin, contract and A′ teaching are unchanged by this; I report it because it widens the reach.

**Consumers.**
- `bin/cc-pane-close:99`, `bin/cc-husk-sweep:353`, `hooks/lead-crash-watchdog.sh:1382`, `bin/dl:808`, `router.py`, `core/hooks/completion-gate.sh` and `drain-peer-findings.py finding_of` are all position-free. Each parses `❌ Good to close: no — …`.
- `research-kit-built-states.bats` lifts the region `_ca_rp_lib … if [ "$d4" -eq 1 ]`, which does not contain the changed lines (prototype lines 1113–1146 versus D3 at 1065).

## 4. Existing bats: static audit (estimated; not run)

- **Not run.** `runbats.sh` retried `bats tests/completion-assert.bats tests/completion-assert-assignee-shared-cwd.bats` every 30 s and got rc 75 (REFUSED) on every attempt; see `bats-proto.out` for the count. I did not use the waiver, because it writes under `~/.claude`.
- **Why I expect them to stay green** (from grep over `tests/completion-assert.bats`):
  - No fixture has the anchor on line 1. The anchor appears only on later lines, at `:1295`, `:1673` and `:1684`. So the gate, D3-branch and rung-window changes are never exercised.
  - No fixture carries a no-polarity verdict, so verdict-first cannot fire.
  - The pinned strings survive: `Origin-session close contract`, `good-to-close-verdict`, `line-1-rung`, `ONE rung that actually governs`, and the template guard. The new template's line-1 value `<yes … | no — <…>>` still matches `^<.*>$`.
  - No test pins `close_act_template` text, the 613 figures or "SECOND line".

**Estimate:** 157 of 157 stay green. The implementer must still run the suites and assert the `1..N` plan line plus the ok count, as the design already requires.

## 5. Bypasses: done-reading NO closes that slip past the predicate (false PASS)

| Probe (`eval.sh`) | Result | Note |
|---|---|---|
| `**✅ Complete**`, `## ✅`, `> ✅`, `✅️` (VS16), lowercase `good to close: no`, `Good to close — no`, `Good to close: **no**`, `Good to close: not yet` | **refused** | — |
| Verdict hidden in a fenced block | refused anyway | The existing `good-to-close-verdict` token, because fences are skipped |
| "Not yet" with no anchor | refused anyway | The same existing token |
| `All landed.` / `Shipped.` / `Finished —` / `Landed on trunk…` / `It's done…` / `Everything is landed` | slips past the predicate | Under rung ✅ these lack ✅ on line 1, so `line-1-rung` refuses them anyway. They are bypasses only outside D6. |
| ✅ on line 1 but not first: `📦→✅ **…landed…**`, `Landed and content-verified. Ledger reads ✅` | **bypass** | Measured: 2 of 5,280 anchored closes |
| `1. ✅`, `• ✅`, `+ ✅`, `\| ✅ … \|`, `🎉 …`, `✔️ …`, `🟢 …` openers | bypass | Not stripped and not in the list |
| `Good to close: ❌ no`, `nope`, `Good to close (no)`, `\| Good to close \| no \|`, value on the next line, `not yet good to close` | bypass (polarity `none`) | Measured: 18 anchored closes have polarity `none` without a yes-before-anchor form; I read them, and 1 is a missed no (`isn't good to close yet`, fixed by P4) |

The design states that it prefers a false PASS to a false FAIL, and these bypasses fit that ordering. The cheap closes are adding `•` and `+` to the strip set and taking P4's negation widening. I recommend neither as required.

## 6. Required fixes, in order

1. **P1:** a "no" counts only when punctuation follows it, in both the lib and `CA_VERDICT_NO`; strip leading dashes in a loop.
2. **P2:** drop `with` and `after`; delete the `VYES && VNO` branch; put the hedge branch behind `CC_VERDICT_FIRST`; correct §3.5.
3. **P3, P4** (cheap, recommended): reject a done token followed by `?`/no; read a yes or negation placed before the anchor.
4. Add F1, F3, F5, F10, F13 and F14 as must-not-fire bats cases, and add P3's probes to T21.
5. **P5–P9:** record them in §3.3, §4 and §7, or apply the optional fixes.

**Conviction: 85%** that with fixes 1–2 the design adds no false FAIL on an honest close beyond the intended class (old-shape ✅-led no closes).
- **Evidence for:** fixtures, real-hook replay, and a 30-day corpus validated against the real functions.
- **Discounted for:**
  - the bats suites not run;
  - the D6-gated rate is unmeasured, because transcripts do not record the ledger rung;
  - the corpus under-samples a future in which verdicts sit on line 1.
