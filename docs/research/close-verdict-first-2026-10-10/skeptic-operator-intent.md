# Skeptic review: does design A′ fix what the operator saw? (operator-intent and glance lens)

Date: 2026-10-10. Target: `design.md` in this directory (design A′: the verdict owns line 1 with its own glyph, the rung moves to line 2, and a Stop-hook refusal named `verdict-first`). Method: read-only on tracked files. Scratch files are in `/tmp/cvf-skeptic-intent/`. Every number is labelled with the command that produced it, or marked as an estimate.

## Verdict

**SURVIVES-WITH-FIXES. Conviction: 85%.**

When a model follows the new template, A′ does fix the glance:
- the first mark on row 1 is a red ❌ for no and a green ✅ for yes, at any width;
- the verdict comes first;
- the rung and the act line keep their information and the 3-line window.

Four problems stop it from doing what the operator asked for by default:

1. **P1, fix-required.** The hook would not have caught the screenshot close itself. That session had already spent its `shape` budget, and `completion-assert.sh` timed out on that close anyway.
2. **P2, fix-required.** An old-shape 👤 no close still passes, and its first two rows look the same as a 👤 yes close.
3. **P3, fix-required.** The `✅ SAFE TO CLOSE` certificate still renders under ❌ closes. A third of today's certificate renders follow a no.
4. **P4, fix-required.** The rules still say ✅ means safe to close, and `/wrap` still says to copy the readout verbatim. So a ❌ close carries "✅ Complete … nothing to do" one row down, and a 👤 yes close is told both to use ✅ and not to.

P5 to P8 are minor.

## What holds

**The glance works on compliant closes.** These mockups use the design's own fixtures, rendered at the measured 57-column pane (`python3 -I /tmp/cvf-glance/render.py 55`). Row 1 differs in colour, and the verdict is never below row 1.
```
● ❌ Good to close: no — the FLEET_V2 programme still has      ● ✅ Good to close: yes — nothing of mine is open;
  two open steps, and pane 182 will mail this pane before        follow-on: none new.
  it lands its reconciler change; if this pane closes,
  that mail goes nowhere.                                        ✅ Complete & live on trunk — research gate row 15
                                                                 checked; the repo is unchanged.
  ✅ Complete & live on trunk — the reconciler is in act
  mode, cut over this session.
```

- **Pyramid order.** The answer comes first (the verdict, and on a no, what remains and who owns it), then the support (the rung), then the act. The order of the act window is unchanged: verdict on line 1, rung on line 2, `▶` on line 3. That has the same zero slack as today (design §1.1).
- **No information is lost.** The rung's glyph, its state clause and the work clause move whole to line 2. The ⛔ 🔧 📦 🚀 closes are untouched.
- **Parsers.** `bin/cc-pane-close:99` and `hooks/lead-crash-watchdog.sh:1382` use `re.search` without an anchor, so `❌ Good to close: no — …` still parses.
- **⛔ semantics are unchanged.** ❌ is not a rung glyph. One residual cost: ❌ and ⛔ are both red, so the operator may read ❌ as "needs me". That is acceptable, because a false alarm costs less than closing a pane that has to stay open.
- **The hook cannot undo a rendered close.** By the time a Stop hook blocks, the misleading close is already on screen, and the corrected one renders under it. So the rules text is the main lever and the hook is the backstop. That makes P1 matter more, not less.

## Problems

### P1 (fix-required): the hook would not have caught the screenshot close in production

**Evidence.**

- **The session's `shape` budget was already spent.**
  - The LEFT session (`44091255`, config root `~/.claude-next`) fired D6 `shape` at 10:27:56Z (count 1/2) and again at 11:12:16Z (count 2/2), according to `~/.claude/autonomy/idl.jsonl`.
  - Its latch file holds two `shape` lines and one `assert`. The file is `~/.claude/state/completion-assert/01f6789928c257a9.fired`; the key is the `shasum` of `$HOME/.claude-next|44091255-…|/Users/chrisren/Development/claude-infrastructure`.
  - The screenshot close came later, at 16:15:41Z.
  - The design puts `verdict-first` into `_d6_missing`, and keeps "the `shape` class, the latch, COMPLETION_SHAPE_MAX=2" unchanged (§3.5). With N=2 ≥ 2, the hook abstains `capped:shape:2>=2` (`hooks/completion-assert.sh:1377-1394`).
  - The design's replay ("LEFT verbatim: CUR PASS → PRO BLOCK") and its test T1 both start from a fresh latch, so neither can see this.
- **This happens often, not in one session.** Measured with a Python pass over the IDL plus its rotated `.gz` files, 2026-09-22 to 10-10:
  - 78 sessions drew a `shape` fire, and 37 of them (47%) reached the cap.
  - The cap then suppressed 45 later shape demands across 17 sessions.
  - Long-lived lead sessions spend the budget on earlier closes, and those are the sessions the operator asks "Good to close?".
- **The hook also timed out on that close.** The transcript records `hook_cancelled` for `completion-assert.sh` with `durationMs 5403` against `timeoutMs 5000`, at 16:15:47.450Z. `operator-readout.sh` timed out too: 10,187 ms against 10,000.
  - Over 14 days, the hook timed out on 1,811 of 9,877 Stop runs (18.3%; `DAYS=14 python3 -I /tmp/cvf-skeptic-intent/timeouts.py`).
  - Over 7 days: p50 was 697 ms and p90 5,050 ms, and 3.6% of runs took 4 to 5 s (`durations.py`).
  - The design adds about 10 to 20 forks on the D6 path (my estimate, counting the pipelines in §3.2 to §3.5) and did not measure latency.
- **The hook's own header predicts this failure:** "a shared counter let mid-wave convictions spend the budget before the terminal close it exists for ever arrived" (`completion-assert.sh:1336-1345`).

**Minimal fix.**
- Give `verdict-first` its own class, the way D7 got `act`. When `verdict-first` is the only token in `_d6_missing`, set `CLASS=verdict; CLASS_MAX=${COMPLETION_VERDICT_MAX:-2}`.
- Add test T1b: the LEFT close, with the latch pre-seeded with two `shape` lines, still fires `verdict-first`.
- In D6, call `close_line_reads_done "$ca_first"` (one line) before `close_verdict_polarity "$MSG"` (the whole message), so A′ closes skip the awk pass.
- Time CUR against PRO on the LEFT and A′ fixtures before landing.
- In §7, state that the hook fails open on about one Stop run in five, so the rules text carries the change.

### P2 (fix-required): an old-shape 👤 no passes, and looks like a 👤 yes

**Evidence.**
- **The design passes it.** The design accepts `👤 My side is done & landed …` followed by `Good to close: no — …` (§1.3), and T17 pins that result. `close_line_reads_done` only matches at the start of the line, and `👤 My side is done` does not start with a done word.
- **The glyph says nothing about the verdict, and the words read done.**
  - Measured over 30 days of main-chain closes, deduplicated by text (`python3 -I /tmp/cvf-skeptic-intent/ntd.py`): 258 of 3,269 no closes open with 👤, and 121 of those say "done" on line 1.
  - The glance slot's census found 👤 line-1 closes split 253 yes / 268 no.
- **At 57 columns, the first two rows are identical:**
  ```
  ● 👤 My side is done & landed — 1 runnable now, 1 needs      ● 👤 My side is done & landed — 1 runnable now, 1 needs
    your call.                                                   your call.
    Good to close: no — I re-run the census after your step      Good to close: yes — nothing of mine is open;
    lands.                                                       follow-on: none
    ▶ Run this:                                                  ▶ Run this:
  ```
- **The rules text and the hook disagree.** The design's R1 says "A no under a ✅ or done-reading line 1 fails". Both a model and the operator would read "My side is done & landed" as a done reading, but the hook passes it. The frozen scope also says "a line that reads as done".

**Minimal fix.**
- In D6, also add `verdict-first` when all three hold:
  - the polarity is no;
  - line 1 carries no verdict anchor;
  - line 1, after the same markdown strip, opens with the ledger's own rung glyph (`👤` or `✅`).
- Keying on the glyph avoids the "not landed" token ambiguity that slot-corpus warned about. The anchor guard keeps `👤 Good to close: no — …` legal.
- Flip T17 to expect a fire.
- Cost: one transitional block per old-shape 👤 no close, bounded by the cap. The proxy above puts that at no more than 258 in 30 days; the proxy is not limited to closes D6 can reach.

### P3 (fix-required): the `✅ SAFE TO CLOSE` certificate contradicts the ❌ above it

**Evidence.**
- **Today, a third of certificate renders follow a no.** Measured over 30 days of main-chain transcripts (`DAYS=30 python3 -I /tmp/cvf-skeptic-intent/cert_vs_verdict2.py`): there were 43 distinct certificate renders (`hook_system_message` carrying `SAFE TO CLOSE`). Of those, 14 (33%) followed an assistant message whose verdict was no, 18 followed a yes, and 11 had no verdict.
- **Example:** session `623eaa45…` at 2026-10-02T05:00Z. The close was "✅ Complete & live on trunk… / Good to close: no. Groq billing, Gemini billing … are still yours." It was followed by `OPERATOR ▸ ✅ SAFE TO CLOSE — nothing of mine is open`.
- **Under A′ the same pair looks like this.** The certificate uses the yes template's own words, and it is the line closest to the prompt:
  ```
  ● ❌ Good to close: no — the FLEET_V2 programme still has
    two open steps, and pane 182 will mail this pane before
    it lands its reconciler change.

    ✅ Complete & live on trunk — the reconciler is now in
    act mode, cut over this session.

    OPERATOR ▸ ✅ SAFE TO CLOSE — nothing of mine is open
  ```
- **The design defers this.** It moves the fix to F1, yet calls F1 "advisory only, so it carries no false-FAIL risk" (§8).

**Minimal fix.**
- Pull F1 into this land as `Scope (grown):`.
- In the ✅ arm of `operator-readout.sh` (`:1137`, and the standalone path near `:1866`), fall back to the existing `✅ live on trunk` wording when the polarity of the last main-chain assistant text is no.
- Read only the tail of the transcript, because `operator-readout.sh` itself timed out at the screenshot close.
- If the lead keeps F1 out of this land, §7 risk 6 should state the measured rate, a third of renders, instead of saying only that the contradiction "remains".

### P4 (fix-required): the rules still say ✅ means safe to close, and `/wrap` still says copy the readout verbatim

**Evidence.**
- **Line 9 of the rules is not edited.** `CLAUDE.rules.slim.10-session-close.md:9` reads: "**✅ is a safe-to-close assertion, not a vibe.** Claim it only with: … frozen-DoD remainder 0 · no operator step this session created left unrun". A′ then requires two things that line forbids:
  - **A ✅ rung on line 2 under a ❌ verdict.** D6 `line-1-rung` enforces relaying it. Line 2 then asserts safe to close while line 1 says it is not. The glance slot named this conflict ("a rung ✅ sitting on a no-close contradicts the rule's own definition"), and the design leaves it unresolved.
  - **`✅ Good to close: yes` on a 👤 close** (R1 with Δ1). Line 9 forbids ✅ there, because an operator step is still unrun.
- **The design's W4 conflicts with S1.** W4 reads "Line 2 is wrap-ledger's rung readout, verbatim." S1 (`:144`) says to copy the glyph and state clause and replace the tail.
  - The screenshot close kept the tail ("— nothing to do.").
  - Measured (`ntd.py`): of the 261 no closes that open with ✅, 210 carry "complete" and 37 carry "nothing to do" on that line.
  - Under A′, that line sits one row under the ❌:
  ```
  ● ❌ Good to close: no — the FLEET_V2 programme still has
    two open steps, and pane 182 will mail this pane before
    it lands its reconciler change.
    ✅ Complete & live on trunk — nothing to do. The
    reconciler is now in act mode, cut over this session.
  ```

**Minimal fix.**
- **Line 9:** change the lead to "**A ✅ rung is an assertion, not a vibe.**" This adds about 1 loader unit (estimate). It scopes line 9 to the rung; R5 already says the rung does not imply the verdict.
- **W4:** change it to "Line 2 is the rung readout's glyph and state clause, verbatim, with your own clause in place of its tail."
- **Optional:** add the glance slot's `Ledger:` label to line 2; D6's containment test already tolerates it.
  - If it is adopted, `close_line_reads_done` must strip a leading `Ledger:`. Otherwise an old-shape `Ledger: ✅ Complete…` line 1 escapes the refusal.
  - The root fix is still F2: git-only wording for the ✅ readout.

### P5 (minor): the verdict, now the governing line, lost the "nothing later withdraws it" protection

**Evidence.** R4 moves the sentence "It does not hedge, and nothing later in the close withdraws it" onto the S1 line. Under A′ that is line 2, the support. Nothing now says the verdict line may not be withdrawn later, and D3 judges line 1 only. Under the Pyramid Principle, that protection belongs on the answer.

**Minimal fix.** In R4, write "Neither it nor the verdict hedges, and nothing later in the close withdraws either." That is about 5 more words, which fits inside the design's −14-unit headroom (estimate).

### P6 (minor): a no without a glyph is accepted, and its first coloured mark is green

**Evidence.**
- `Good to close: no — …` with the ✅ rung on line 2 passes (§1.3).
- At 57 columns, its only coloured mark is the green ✅ on row 4:
  ```
  ● Good to close: no — the FLEET_V2 programme still has
    two open steps, and pane 182 will mail this pane before
    it lands its reconciler change.
    ✅ Complete & live on trunk — the reconciler is now in
    act mode, cut over this session.
  ```
- Yes and no also share their first three words. That is the glance slot's reason for preferring "Not good to close".

**Minimal fix.** Leave the hook as it is: requiring ❌ would be a false FAIL. Count glyph-less no verdicts on line 1 in the 14-day re-measure (F4), and tighten only if they turn out to be common.

### P7 (minor): the block reason says "directly under it", while `/wrap` says leave a blank line

**Evidence.**
- K5 says "the ledger's rung line goes directly under it". W4 says "leave one blank line under it". The always-loaded rules file says neither.
- 67.5% of closes today run line 2 into line 1's paragraph (slot-glance).
- A blocked model reads K5, so it will run them together.

**Minimal fix.** Change K5 to "the ledger's rung line goes next (a blank line between them helps)".

### P8 (minor): "after written work" reads as this turn; the hook means this session

**Evidence.**
- D6 tests write evidence across the whole session: it calls `session_writes_paths` at `completion-assert.sh:1229`, not `session_writes_paths_turn`.
- The rules say read-only turns carry no readout (lines 34 and 99).
- The screenshot close came on a read-only turn: one Bash call between "Good to close?" and the close, in a session that had written files earlier. A model can conclude that the rung line is not due on that turn, and then draw a `line-1-rung` block on exactly the turn this design targets.
- The problem predates this design.
- The token `line-1-rung` now refers to line 2. K5's sentence explains this, so no rename is needed.

**Minimal fix.** In R1, write "after written work this session". That is 2 more words.

## Receipts

All scratch files are in `/tmp/cvf-skeptic-intent/`.

| Instrument | What it measured |
|---|---|
| `cert_vs_verdict2.py` (`DAYS=30`) | Certificate renders against the preceding verdict: 43 distinct renders; 14 after a no, 18 after a yes, 11 with none. |
| `timeouts.py` (`DAYS=14`) | `completion-assert` timeouts: 1,811 of 9,877 Stop runs. |
| `durations.py` (7 days) | `completion-assert` durations: p50 697 ms, p90 5,050 ms; 18.0% of runs at 5,000 ms or more, and 3.6% between 4,000 and 5,000 ms. |
| `ntd.py` (30 days) | 3,269 no closes. 261 open with ✅ (210 of them say "complete", 37 "nothing to do"). 258 open with 👤 (121 of them say "done"). |
| `lead.py` (30 days) | 3 no closes have ✅ on line 1 without leading with it. The design's floor regex matches 263 no-close line 1s. 6 "Landed…"-style openings miss it, and most of those are already blocked by `line-1-rung`. |
| `idl_all.jsonl` | Concatenation of `~/.claude/autonomy/idl.jsonl` and its rotated `.gz` files, 2026-09-22 to 10-10. Source of the shape-cap counts (78 / 37 / 45 / 17) and of the LEFT session's two `shape` fires. |
| `m/*` | Mockup sources, rendered with `/tmp/cvf-glance/render.py 55`. |

- **Transcript evidence:** `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/44091255-b12e-41c4-8aaa-0d4ddf21c6ec.jsonl`. The records at 16:15:02 to 16:15:52Z show the user's "Good to close?", a single Bash call, the close, and three `hook_cancelled` (`timedOut: true`) records, for `completion-assert`, `session-continue` and `operator-readout`.
- **Not verified:** I did not run the design's prototype or its bats suites. The latency the design adds is an estimate, not a measurement.

**Overall: SURVIVES-WITH-FIXES (P1, P2, P3, P4 required; P5 to P8 minor). Conviction: 85%.**
