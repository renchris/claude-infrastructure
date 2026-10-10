# Slot hooks: what a verdict-first close runs into, arm by arm

Question (c) of the close-verdict-first research. Scope: `hooks/completion-assert.sh` (close-tell gate, D3, D4,
D6, D7, latch/caps, exemptions, reason assembly), `hooks/lib/close-shape.sh`, `hooks/anti-deference-nudge.sh`,
`commands/wrap.md`, and how `tests/completion-assert.bats` drives D6. Read-only on tracked files. Scratch work is
under `/tmp/cvf-hooks/` and a hook copy under `/tmp/cvf-hooks-proto.HDiGpL/`.

## 0. Bottom line

1. **Today, both screenshot closes pass every arm.** Measured: `/tmp/cvf-hooks/replay.sh` replays the verbatim
   texts (found in transcripts `44091255-…` LEFT 16:15:41.992Z and `3bd7aa3b-…` RIGHT 16:15:38.550Z) through the
   real hook. The fixture is origin, ✅ ledger, positive write evidence and contra=0, so D6 is armed. Result for
   both: `abstained: ledger-clean`. No arm checks the verdict's polarity against line 1. Rule line 146 says
   "nothing later in the close withdraws it", and no hook enforces that sentence.
2. **Designs A and C, with today's hooks, falsely FAIL honest closes in three places.** All measured.
   - **D3:** an honest `Good to close: no — <what remains + who owns it>` on line 1 trips D3. CA_SETTLED matches
     `good to close` and CA_RETRACT matches `still open`, `remain`, `pending`, `yours` and `but`, which are the
     words the contract itself asks for. Measured on 14 days of real verdict lines (§3): **362 of 1,361 "no"
     verdicts (26.6%)** would trip D3 if moved to line 1 verbatim.
   - **The close-tell gate:** a `Good to close: no` line 1 now satisfies `CA_SETTLED`, so honest ⛔ closes that
     abstain today (`no-close-tell`) reach the ledger arm. They are then blocked with "your close reads as
     done/complete".
   - **D6 `line-1-rung`:** under A it fires on every correct close, because the rung has moved to line 2. Under C
     it fires whenever the verdict glyph replaces the rung glyph and no rung glyph is left anywhere on line 1.
3. **Design B passes today's hooks unchanged** as long as line 1 does not glue the ✅ to a retraction word. But B
   is exactly the shape D3 was built to call a hedge ("✅ … — but not good to close" → D3 fires, measured).
4. **One predicate refuses the LEFT close under every design:** `verdict polarity = no ∧ line 1 LEADS with a
   done-reading` (✅ / yes / complete / done / safe to close / nothing to do, anchored at the start of the line). I
   prototyped it as a new D6 token `verdict-not-first`, together with the three false-FAIL fixes. Measured: it
   blocks LEFT, passes RIGHT, and passes every honest A, B and C variant I wrote (§4). Proxy measurement: it would
   fire on **251 of 2,074** verdict-bearing messages over 14 days, 249 of them with a line-1 ✅. That is the LEFT
   class.
5. **A rendering fact that undercuts "line 2" as a slot.** In the LEFT raw text, line 1 and line 2 are separated
   by a single `\n`, and the TUI rendered them as one wrapped paragraph (the screenshot). Over 14 days, **1,542
   of 1,850 (83.4%)** line-2 verdicts sit behind a single newline (proxy scan, §3). The hooks count raw lines, but
   the operator sees rendered paragraphs. Design C (one line) is immune. A and B need a blank line or a hard
   break between S1 and S2, and the hooks cannot tell the difference today.

## 1. Method and instruments

| instrument | what it is | label |
|---|---|---|
| `/tmp/cvf-hooks/replay.sh <tag> <rung> <file> [hook]` | Builds a hermetic copy of the bats `setup()` (stub `WRAP_LEDGER_BIN` with `RUNG=<rung>`, empty `CC_FIRED_DIR`/`CC_REGISTRY_DIR`/custody, `AGENT_IDENTITY_LIB` → missing, `CC_BACKLOG_BIN` → `[]` stub, a transcript with one `Edit` tool_use so `session_writes_paths` returns 0). Runs the hook and prints the block/abstain line plus the IDL `arm`. | measured |
| `/tmp/cvf-hooks/rx.sh` | Runs `CLOSE`, `CA_SETTLED` and `CA_RETRACT`, extracted live from the hook, with `grep -iE` over sample lines (`/tmp/cvf-hooks/samples.txt`) | measured |
| `/tmp/cvf-hooks/scan2.py` | Reads every main-agent assistant text record that holds an **unfenced** `good to close` line, in transcripts touched in the last 14 days across the 5 stores (deduped by realpath; `subagents/` skipped; 1,960 files). It is a **proxy population**: it includes mid-turn texts and fired peers, and it is not gated to D6's origin/✅/👤/writes. | measured (proxy) |
| prototype `/tmp/cvf-hooks-proto.HDiGpL/hooks/` | A copy of `hooks/` with the patch in §4. Full diff: `/tmp/cvf-hooks/proto-final.diff`. | measured |

## 2. Mechanical map: every arm a close passes through, and what it reads

Order inside `completion-assert.sh`: kill-switch (:231) → MSG extraction (:258, last non-sidechain assistant
text) → ARM R relay (:278) → **close-tell gate** (:312-336) → GENUINE abstain (:338) → ledger read (:342-372) →
ledger terms set `contra`/`facts` (:707-892) → double-block yield (:899-950, which keeps `contra_shape`) → D2,
D1, **D3**, **D4**, D5 → **D6** (:1193-1271) → **D7** (:1273-1315) → `ledger-clean` abstain (:1319) →
**latch/cap per class** (:1323-1400) → **reason assembly** (:1402-1424).

| arm | input it reads | position-sensitive? | how verdict-first touches it |
|---|---|---|---|
| close-tell gate | `CLOSE` over the whole MSG; if that misses, `CA_SETTLED` over **`ca_first`** (first non-empty raw line, NOT fence-aware) | line 1 only on the fallback path | Under A and C every line 1 contains `good to close` and so matches CA_SETTLED, including `Not good to close` and `Good to close: no`. Honest ⛔/🔧 closes that carry no CLOSE token now pass the gate and reach the ledger arm. **False fire, measured:** `blk-A`/`blk-C` (⛔ rung, line 1 `Good to close: no — the keep-or-retire call … is open with you`) → BLOCK `arm=ledger` "your close reads as done/complete … BLOCKED ON YOU". The same content in today's order → `abstained: no-close-tell`. The ⛔ comment at :885-887 relies on that abstain ("a close whose line 1 actually IS the ⛔ rung carries no done-assertion, so it abstains at the close-tell gate"). |
| D3 hedge | `CA_SETTLED ∧ CA_RETRACT` over `ca_first` | line 1 only | Moving the verdict onto line 1 puts the contract's own "what remains + who owns it" words onto the line D3 reads. See the table below. |
| D4 offer | `CA_OFFER` over quote-stripped MSG, then `CA_WORKLEFT` over the non-offer lines | no | Neutral. The content is the same wherever it sits. |
| D1 handoff | `CA_HANDOFF` (`is yours`, `needs your`, …) over the whole MSG, then a `cc-backlog list --blocked` check for this sid | no | Neutral to order. But A and C push "who owns it" into one terse line, which raises the odds of `is yours` phrasing. D1 then fires unless the step is filed, which is D1's intended behaviour. |
| D5 placeholder | a line after a `run this`/`▶` line | adjacency | A verdict line containing "run this" marks the next line as a run line. This is not specific to the redesign. |
| D6 origin contract | (a) `close_shape_missing` = an unfenced `good to close` anywhere (`CC_VERDICT_WINDOW=0`); (b) `case "$ca_first" in *"$RUNG"*` (`line-1-rung`, containment) | (b) is line 1 | A: (b) fails on every correct close. B: unchanged. C: passes only if line 1 still contains the rung glyph somewhere. |
| D7 act line | `close_act_missing`: `▶` or `ACT: <value>` within the first `CC_ACT_WINDOW=3` non-blank, unfenced lines; RUNG=👤 only | yes, window 3 | A: verdict, rung, ▶ = exactly 3, so there is **zero slack** (measured: one supporting line before ▶ → `arm=act` BLOCK). B: verdict on line 2, ▶ on line 3, the same as today. C: ▶ at line 2, one line of slack. |
| latch/caps | message-hash latch; `assert` (COMPLETION_MAX=3), `shape` (COMPLETION_SHAPE_MAX=2), `act` (COMPLETION_ACT_MAX=2) | n/a | A new D6 token reuses the `shape` class, so it adds no new budget. Caveat: a close that trips both `verdict-not-first` and `line-1-rung` spends one shape fire, and the 2-fire cap leaves one retry. |
| exemptions | D6/D7 require `contra_shape=0`, RUNG ∈ {✅,👤} (D7: 👤), `! _ca_assignee`, positive writes (`session_writes_paths` rc 0), `oi_origin_class = origin` (fired peers out) | n/a | A predicate placed inside D6 inherits all of these, so fired peers, assignees, write-free sessions and contra=1 closes stay exempt. |
| reason assembly | one sentence-group per arm; D6 uses `close_shape_reason "$RUNG" "$_d6_missing"` | n/a | `close_shape_reason` currently says **"Put it on the SECOND line"**. That instruction produced the LEFT shape, so any design must rewrite it. |

### D3 against honest "no" lines (rx.sh, measured)

| line 1 | SETTLED | RETRACT hit | D3 |
|---|---|---|---|
| `Good to close: no — two steps still open` | 1 | `still open` | **FIRES** |
| `Good to close: no — two FLEET_V2 steps remain; pane 182 owns the next one.` | 1 | `remain` | **FIRES** |
| `Good to close: no — pane 182 has a pending change to the reconciler.` | 1 | `pending` | **FIRES** |
| `Good to close: no — the reconciler change is yours to approve.` | 1 | `yours` | **FIRES** |
| `❌ Not good to close — two FLEET_V2 steps remain …· ledger: ✅ …` | 1 | `remain` | **FIRES** (C) |
| `Good to close: yes — nothing of mine is open; follow-on: 1dcc10d88ee3 (… parked until 400 candidates exist)` | 1 | `parked` | **FIRES** (A and C: the follow-on clause now sits on line 1) |
| `Good to close: no — the FLEET_V2 programme still has two open steps, …` (LEFT's own line 2) | 1 | none | passes (`still has` is not in `still (needs\|to\|open\|parked)`) |
| `✅ Complete & live on trunk — nothing to do. …` (LEFT line 1) | 1 | none | passes |

Hook replay with the same content (measured, current hook): `A-left-remain`/`A-left-pending` → `arm=hedge+shape`;
`C-left-remain` → `arm=hedge`; `A-right-followon`/`C-right-followon` → `hedge(+shape)`;
`today-right-followon` (the same follow-on on line 2) → passes.

## 3. Corpus numbers that size each interaction (scan2.py, proxy, 14 days)

| quantity | value |
|---|---|
| messages with an unfenced verdict line | 2,074 (no 1,361 · yes 689 · mixed 0 · unparsed 24) |
| verdict position (non-blank unfenced line) | line 1: 42 · **line 2: 1,850 (89.2%)** · line 3: 103 · >3: 79 |
| line-2 verdicts behind a **single** newline (one rendered paragraph with line 1) | **1,542 of 1,850 (83.4%)** |
| verdict = no ∧ line 1 leads with a done-reading (the LEFT class) | **251** (249 lead with ✅) = 18.4% of "no" |
| verdict = no at line 2 with a consistent (non-done) line 1 | 962 |
| "no" verdict lines that would trip **unpatched** D3 if moved to line 1 | **362 / 1,361 (26.6%)** |
| "yes" verdict lines that would trip unpatched D3 if moved to line 1 | 48 / 689 (7.0%) |
| …"yes" lines still tripping the **patched** D3 (follow-on tail stripped) | 28 / 689 (4.1%). Examples: "yes — nothing of mine is still running; the two items below are yours". Per rule line 146 these are D3's own target ("if … is theirs, that IS the rung"), so firing on them is D3 working as designed. |

Note the drift: the lib header's "only 1.1% … put the verdict at position <=3" (2026-08-23) is now 1,995 of
2,074 (96.2%) on this proxy. The template move happened. `close_shape_reason`'s "90.7% bury it as the last line"
is stale for the same reason.

## 4. The predicate that refuses LEFT, plus the three false-FAIL fixes (prototype, measured)

The prototype diff is at `/tmp/cvf-hooks/proto-final.diff`. It has five parts:

1. **`close_verdict_polarity <msg>` → yes|no|mixed|none** (close-shape.sh). Unfenced lines only, with the same
   placeholder guard as `real()`. `not good to close` → no. After the anchor, the value (dashes, colon and bold
   stripped) starting `yes` → yes and starting `no`/`not` → no. A leading ✅ on an un-negated anchor line → yes.
   Both polarities → `mixed`, which abstains (a false PASS is preferred).
2. **`close_line_reads_done <line>`**: rc 0 iff the line, after stripping leading markdown, starts with
   `✅|yes|complete|done|all done|safe to close|nothing (left |more )?to do`. It is anchored at the start
   ("leads with"), so `No — … · ledger: ✅ Complete` and `❌ Not good to close … · ledger: ✅` both pass.
3. **New D6 token `verdict-not-first`**: `[ "$(close_verdict_polarity "$MSG")" = no ] && close_line_reads_done
   "$ca_first"`. It lives inside D6, so it inherits origin, ✅/👤, positive writes, contra=0 and not-assignee,
   with no new class, cap or latch. Kill switch: `CC_VERDICT_POLARITY=0`. The reason gets one sentence: "your
   verdict is NO but line 1 leads with a done/yes reading … lead line 1 with the no."
4. **`CA_VERDICT_NO`** = `(^|[^a-z])not good to close|good to close[^a-z]*(no|not)([^a-z]|$)`, used twice:
   - **gate:** a line 1 matching CA_SETTLED counts as a close only if it is NOT a negative verdict. This restores
     today's population exactly: a "no" line 1 is gated by the CLOSE tokens in the body, as today's "⛔ …" line 1
     is.
   - **D3:** fires only on a settled **non-negative** line 1. A "no" plus its reasons is an answer, not "asserts
     and withdraws".
5. **D3 strips the `follow-on:` tail** before CA_RETRACT. Rule line 146 sends qualifications there.
6. **`line-1-rung` window** behind `CC_RUNG_WINDOW` (1 = today, B and C; 2 = design A: the rung may sit on line
   1 or 2).

Replay results with the prototype (measured, `replay.sh … $P/hooks/completion-assert.sh`):

| case | today | prototype |
|---|---|---|
| LEFT verbatim (✅ line 1, verdict no) | PASS | **BLOCK `shape` (verdict-not-first)** |
| RIGHT verbatim (✅ line 1, verdict yes) | PASS | PASS |
| A-left / A-left-remain / A-left-pending / A-right / A-right-followon (`CC_RUNG_WINDOW=2`) | BLOCK (hedge/shape) | PASS ×5 |
| B-left (`No, not good to close — … Ledger: ✅ …`) / B-right | PASS | PASS |
| B-left-but (`✅ Complete … — but NOT good to close: …`) | BLOCK hedge | BLOCK shape (verdict-not-first: correct under B) |
| C-left / C-left-remain / C-right / C-right-followon | PASS / BLOCK / PASS / BLOCK | PASS ×4 |
| C-left-noglyph (`❌ Not good to close — … · ledger: clean & landed`, no ✅) | BLOCK line-1-rung | BLOCK line-1-rung (C must keep the rung glyph in a suffix, or D6 must accept it) |
| ⛔ blk-today / blk-A / blk-C | PASS / BLOCK ledger / BLOCK ledger | PASS ×3 (`no-close-tell`, the same as today) |
| D3 founding fixture `Yes — with one thing still parked.` | BLOCK hedge | BLOCK hedge (kept) |
| `Good to close: yes — with one thing still parked.` on line 1 | BLOCK hedge | BLOCK hedge (kept) |
| 👤, A: verdict / rung / ▶ | (shape) | PASS. With one extra line before ▶ → BLOCK `act` (zero slack) |
| 👤, C: verdict+rung / ▶ | — | PASS |

Residual false PASSes the patch opens (stated, not hidden): (i) `Good to close: no — but honestly it is fine to
close.` on line 1 no longer trips D3. That is a no-then-yes hedge, and it measured PASS. A narrow add-on is to
keep D3 when a negative verdict line also matches `(fine|safe|ok(ay)?) to close`. (ii) A "no" line 1 with no
CLOSE token anywhere is invisible to D6/D7 because they sit behind the gate. That is identical to today for
"⛔ …" and "👤 …" line 1s, so the patch does not widen it.

## 5. Per-design answers to (1)–(4)

| | **A. verdict on line 1, rung on line 2** | **B. rung stays on line 1, but a "no" may not lead with a done token** | **C. one combined verdict-first line 1** |
|---|---|---|---|
| (1) arms that would FALSELY FIRE on a correct new-shape close, with today's code | **D3** whenever the reason names what remains or who owns it (26.6% of real "no" lines; 7.0% of "yes" lines once follow-on moves up). **D6 line-1-rung** on 100% of compliant A closes. **Close-tell gate → ledger arm** on honest ⛔/🔧 "no" closes without CLOSE tokens (blk-A). **D7** has no slack: any extra line before ▶ fires. | None on a compliant B line, as long as it does not weld the done-reading to `but`/`still open`/etc. B-left (`No, not good to close — … Ledger: ✅ …`) passes today. A B line written as `✅ … — but not good to close` trips **D3**, which is arguably correct. | **D3** on reason words (C-left-remain, C-right-followon). **Close-tell gate → ledger arm** on ⛔ closes (blk-C). **D6 line-1-rung** if the ❌ replaces ✅ and no rung glyph is left on line 1 (C-left-noglyph). |
| (2) arm/predicate that must be added to REFUSE LEFT | Position alone would do it (`CC_VERDICT_WINDOW=1` in `close_shape_missing`). But it would also refuse RIGHT (verdict on line 3) and every line-2 close in the transition, which is the header's own warning against enabling the window before re-measuring. The minimum is the common floor: `polarity=no ∧ close_line_reads_done(line 1)` → D6 `verdict-not-first`. | **This is B's definition.** D6 token `verdict-not-first`: `close_verdict_polarity(MSG) = no ∧ close_line_reads_done(ca_first)`. | The same floor predicate. Optionally a stricter C check: line 1 must contain the verdict anchor (`close_shape_missing` with window 1). But that fails RIGHT ("✅ Yes, it's safe to close", because `safe` was deliberately dropped from the anchor), so ship the floor first. |
| (3) fate of the line-1-rung requirement | Must become "rung in line 1 **or 2**" (prototype `CC_RUNG_WINDOW=2`); otherwise every compliant close is blocked. Keep containment, not equality. | Unchanged (containment on line 1 still holds: `No — … · Ledger: ✅ Complete …`). | Kept as containment **only if the C template keeps the rung glyph in a suffix** (`· ledger: ✅ Complete & live on trunk`). If the design really replaces the glyph, D6 must accept "verdict glyph ∧ verdict=no" in place of the rung. That is a weaker check, because it gives up the 3/167 → enforced READOUT relay the comment at :1247 cites. |
| (4) act marker in the 3-line window | Fits with **zero slack** (verdict, rung, ▶). Measured: one extra line → D7 fires. Either raise `CC_ACT_WINDOW` to 4 or forbid anything between S2 and S3. | Same as today: rung, verdict, ▶ = 3. | Fits with one line of slack (line 1, ▶ at 2). |
| what else must change | `close_shape_reason` ("Put it on the SECOND line"), `close_shape_template` S1/S2 order, `close_act_template` line 1 text, `commands/wrap.md` ("Line 1 stays wrap-ledger's rung readout, verbatim" and the stale "must end with the operator's two standing answers"), the D3 reason ("Line 1 answers 'is it safe to close?' with no qualifier", which already reads as verdict-first) | `close_shape_reason` gains the `verdict-not-first` sentence. The template's S1 line gains "if your verdict is no, lead with the no". | As A, plus the D6 containment decision in (3). |

Common to all three: the **D3 polarity fix and the gate fix are needed by any design that puts a negative verdict
on line 1** (A, C, and B when B writes "No — …" with reason words, e.g. "No — two steps remain · ledger ✅" →
`remain` → D3). They are cheap, only move FAIL→PASS for negative-verdict line 1s, and are pinned in §4.

## 6. Other close readers

- **anti-deference-nudge.sh** reads the whole MSG, so position is irrelevant to it. Three content interactions
  get more likely when "what remains + who owns it" is compressed into line 1:
  - `CATEGORY_TELLS` fires on a count handed over without content (`two steps are yours`).
  - `SOFTCALL` (`your call|up to you|your approval`) without a ship verb sets `hard=1` → `genuine-blocker` abstain
    **and opens a class-B cc-decide packet as a side effect** (`open_packet_B`).
  - The opaque-id nudge counts 12-hex ids and is silenced only by a gloss shaped `id (`/`id:`/`id —`/`(id`. A
    `follow-on: be52a4c8a99f · ledger: ✅` suffix (design C) is not a gloss.

  LEFT itself carries `(backlog be52a4c8a99f)`, which is not in the gloss shape, while RIGHT's `(1dcc10d88ee3)`
  is. I did not replay this hook, so whether it fired on LEFT live is unverified.
- **commands/wrap.md** renders `close_shape_template` and `close_act_template` from the lib, so a template change
  propagates automatically. Its prose does not: "Line 1 stays wrap-ledger's rung readout, verbatim" and "the
  close message must end with the operator's two standing answers" (stale even today; the rule says line 2).
- **operator-readout.sh** (read only, not replayed): on a ✅ write-turn close with scope met it renders `✅ SAFE TO
  CLOSE — nothing of mine is open` (:1138). On LEFT's Stop that is a second mechanical YES beside a "no"
  verdict. It is outside this slot, but any verdict-first design leaves this certificate contradicting an honest
  no.

## 7. How the bats suite drives D6, and a replay test for both screenshot closes

Seams already in `setup()` (tests/completion-assert.bats:13-88):
- `AGENT_IDENTITY_LIB` → a missing file (not an assignee)
- `CC_FIRED_DIR` → an empty fixture dir (origin by absence)
- `CC_BACKLOG_BIN` → a stub that prints `${CC_BACKLOG_STUB_JSON-[]}`
- `CC_REGISTRY_DIR`, `CC_CUSTODY_DIR`, `PEER_OWNED_HOMES`, `CC_RESEARCH_REGISTRY` → empty
- `COMPLETION_STATE_DIR`/`COMPLETION_IDL` → per-test tmp

Helpers:
- `mkledger <tag> KEY=VAL…` (:1146) returns a stub path, and the caller exports `WRAP_LEDGER_BIN`
- `_d6_tr <out> <text> <paths…>` (:1257) writes a transcript with one `Edit` tool_use per path, which is the
  positive write evidence D6 needs
- `run_ca <tx> <cwd> <sid>` and `fired`

Fired-peer control: `ITERM_SESSION_ID=w0t0p0:42` plus `$CC_FIRED_DIR/42.json` (:1301). `ORIGIN_IDENTITY_LIB` and
`SESSION_WRITES_LIB` are overrides the suite does not need (it uses the real libs). `CC_PANE_ID` takes precedence
over `ITERM_SESSION_ID` in D6 (:1239).

Store the two closes as files rather than heredocs inside `$( )`. Bash 3.2 lexes heredoc bodies when it scans for
the closing paren (lesson `bash-32-counts-parens-inside-a-heredoc-it-never-runs`), and these texts contain
parentheses. Suggested `tests/fixtures/close-verdict-first/{left,right}.txt` are byte copies of
`/tmp/cvf-hooks/left.txt` and `right.txt` (extracted with jq from the transcripts above).

```bash
# ── VERDICT-FIRST — the 2026-10-10 side-by-side screenshot, replayed verbatim ───────────────────
CVF_FIX="$BATS_TEST_DIRNAME/fixtures/close-verdict-first"
CA_CLEAN_LEDGER=(DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 TRUNK=origin/main BLOCKED=0 CUSTODY_OPEN=0 FILED_MINE=0 RUNG=✅)
_cvf() { # $1=tag $2=text → runs the hook as an origin ✅ session that wrote a file
  WRAP_LEDGER_BIN="$(mkledger "$1" "${CA_CLEAN_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  : > "$BATS_TEST_TMPDIR/w.txt"
  run run_ca "$(_d6_tr "$BATS_TEST_TMPDIR/$1.jsonl" "$2" "$BATS_TEST_TMPDIR/w.txt")" "$BATS_TEST_TMPDIR" "cvf-$1"
}

@test "verdict-first: LEFT screenshot (✅ line 1, verdict NO on line 2) ⇒ FIRE shape verdict-not-first" {
  _cvf left "$(cat "$CVF_FIX/left.txt")"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'verdict-not-first'
  grep -q '"arm":"shape"' "$COMPLETION_IDL"
}
@test "verdict-first CONTROL: RIGHT screenshot (✅ line 1, verdict YES) ⇒ ABSTAIN ledger-clean" {
  _cvf right "$(cat "$CVF_FIX/right.txt")"
  [ "$status" -eq 0 ]; if fired "$output"; then false; fi
  grep -q 'ledger-clean' "$COMPLETION_IDL"
}
@test "verdict-first CONTROL: LEFT re-shaped to lead with the no ⇒ ABSTAIN" {
  _cvf leftfix "$(printf '%s\n%s\n\n%s' \
    'Good to close: no — keep this pane open: pane 182 will mail it before it lands its reconciler change.' \
    '✅ Complete & live on trunk — nothing to do. The reconciler is now in act mode.' \
    "$(sed -n '3,$p' "$CVF_FIX/left.txt")")"
  [ "$status" -eq 0 ]; if fired "$output"; then false; fi          # A needs CC_RUNG_WINDOW=2 (or the chosen D6 change)
}
@test "D3 does not convict an honest NO on line 1 (still open / remain / pending / yours)" {
  local r
  for r in 'two steps still open' 'two FLEET_V2 steps remain; pane 182 owns the next' \
           'pane 182 has a pending reconciler change' 'the reconciler change is yours to approve'; do
    rm -f "$COMPLETION_IDL"; rm -rf "$COMPLETION_STATE_DIR"
    _cvf "d3no-$RANDOM" "Good to close: no — $r.
✅ Complete & live on trunk — nothing to do."
    if grep -q 'hedge' "$COMPLETION_IDL"; then false; fi
  done
}
@test "D3 still convicts the founding hedge even on a verdict line" {
  _cvf d3yes "Good to close: yes — with one thing still parked.
✅ Complete & live on trunk."
  fired "$output"; grep -q '"arm":"hedge' "$COMPLETION_IDL"
}
@test "gate: a ⛔ close leading with 'Good to close: no' and no CLOSE token ⇒ no-close-tell, not ledger" {
  WRAP_LEDGER_BIN="$(mkledger cvfblk "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix 'Good to close: no — the keep-or-retire call on the v1 reconciler is open with you.
⛔ Blocked — need your call: keep or retire the v1 reconciler.')" "$BATS_TEST_TMPDIR" "cvf-blk"
  [ "$status" -eq 0 ]; if fired "$output"; then false; fi; grep -q 'no-close-tell' "$COMPLETION_IDL"
}
@test "verdict-first: a FIRED PEER sending the LEFT text is exempt" {
  export ITERM_SESSION_ID="w0t0p0:43"; unset CC_PANE_ID
  jq -n --arg c "$BATS_TEST_TMPDIR" '{paneUUID:"43", cwd:$c, selfRetire:true, closedAt:null}' > "$CC_FIRED_DIR/43.json"
  _cvf peer "$(cat "$CVF_FIX/left.txt")"
  if printf '%s' "$output" | grep -q 'verdict-not-first'; then false; fi
}
@test "verdict-first: mixed polarity (quotes a 'no' while answering yes) ⇒ no verdict-not-first" {
  _cvf mixed '✅ Complete & live on trunk — nothing to do.
Good to close: yes — nothing of mine is open; follow-on: none.
(The other pane answered "Good to close: no" because pane 182 is mid-change.)'
  if printf '%s' "$output" | grep -q 'verdict-not-first'; then false; fi
}
@test "verdict-first SEAM: CC_VERDICT_POLARITY=0 silences the token" {
  CC_VERDICT_POLARITY=0 _cvf ks "$(cat "$CVF_FIX/left.txt")"
  if fired "$output"; then false; fi
}
```

Negations are written `if …; then false; fi`, never a bare `! cmd`: bats does not fail a test on a `!`-negated command that is not the last line, which is why the existing suite uses this form (e.g. the D6 ABSTAIN cases). The mixed case's quoted `"Good to close: no"` sits inside ASCII double quotes. The polarity awk does not strip
quotes, so this case depends on `mixed` → abstain, which it does. Unit-level pins for the two lib functions
belong beside the D7 UNIT tests (:1758).

## 8. Suite run

`timeout 600 bats tests/completion-assert.bats` printed **`1..148`**, then `ok 1`, `ok 2` and `ok 3`, and was
killed at 600 s (rc 124). That is 3 ok and 0 not ok out of 148, so the suite did **not** finish. Machine load at
the time was 243 on 10 cores (`uptime`). Running serially was correct here (`command -v parallel` is empty). No
verdict on the suite can be drawn from this run.

## 9. Concerns and deviations

- The scan is a **proxy**: verdict-bearing assistant texts, not D6-gated origin closes. The 251 / 26.6% / 83.4%
  figures size the populations; they are not D6 fire rates. A D6-gated replay (origin ∧ ✅/👤 ∧ writes) over the
  same window would give the true blocked-close rate before shipping.
- Single newline = one rendered paragraph is inferred from one screenshot plus its raw transcript: LEFT has `\n`
  between lines 1 and 2, and the operator saw one wrapped paragraph. I did not test the TUI renderer myself.
- The `/tmp` paths are scratch and may be reaped. The load-bearing prototype is reproduced in §4 prose, and the
  full diff is at `/tmp/cvf-hooks/proto-final.diff`.
- No tracked file was edited and no git write was run.
