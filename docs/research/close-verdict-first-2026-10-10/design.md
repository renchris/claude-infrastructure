# CLOSE_VERDICT_FIRST: the design to implement

Date: 2026-10-10. Inputs: all five slots in this directory (glance, ledger, hooks, corpus, docs), read in full, plus my own checks of the code they cite. Every number is labelled with the command that produced it, or as an estimate. Scratch instruments are in `/tmp/cvf-design/`. No tracked file was edited.

## 0. Decision

**Design A′: the verdict owns line 1, with its own glyph. The ledger's rung line moves, verbatim, to line 2. The Stop hook refuses only the contradiction: a NO verdict under a line 1 that opens with a done reading.**

- **Conviction: 85%** that this is the right design. The parts:
  - 85% on the shape itself (A′ over B and C).
  - 75% on ❌ as the glyph for no.
  - 90% that the hook rule is narrow enough to add no false FAIL on an honest close beyond the old-shape no closes the change is meant to refuse.
- **The yes case and the no case:**

  ```
  ❌ Good to close: no — <what remains + who owns it>

  ✅ Complete & live on trunk — <one clause naming what the work was>
  ```
  ```
  ✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>

  ✅ Complete & live on trunk — <one clause naming what the work was>
  ```

**Why A′ and not B or C.**
- **B (rung on line 1, done-words forbidden on a no).** Both rungs that D6 covers already read as done: `✅ Complete & live on trunk — nothing to do.` and `👤 My side is done & landed — …`. So under B the rung has to leave line 1 on a no anyway (slot-docs §0). Once it does, B is A′ on the no path and the status quo on the yes path. That leaves two shapes for the model to choose between. It also breaks the operator's request to lead with the answer "by default". And 640 of 1,724 yes closes (37.1%) open with neither ✅ nor a yes word (slot-corpus §3), so yes closes are not readable at a glance today either.
- **C (one combined line).** It puts a second green ✅ back inside the same wrapped paragraph and squeezes the rung into a suffix. Line 1 also grows to about three rows at the measured 57-column pane (slot-glance). The hook still **accepts** C-shaped lines, because rung containment on line 1 holds (replay `leftC`, §3.6). A model that writes C is not refused.

**How this departs from the slots, and why:**
1. **The literal `Good to close: yes|no` stays; slot-glance's `❌ Not good to close` does not.** Five consumers match the literal case-sensitively. Checked by reading each one:
   - `bin/cc-pane-close:99` `Good to close: (yes|no)` auto-closes husk panes.
   - `hooks/lead-crash-watchdog.sh:1382`.
   - `bin/cc-husk-sweep:353` `Good to close: ([a-z]+)`.
   - `bin/dl:808`.
   - `scripts/research-kit/router.py:1373,1379` (`^\W*…good to close:\s*no|yes`).

   `❌ Good to close: no — …` satisfies all five. `❌ Not good to close` would silently end auto-close. The colour of the glyph is the first cue (slot-glance §"The glance test"), so the identical first three words cost little. **The verdict value must not be bolded:** `Good to close: **no**` breaks the first two parsers.
2. **D3 on a verdict line uses a narrower rule than the hooks prototype.** Measured with `python3 -I /tmp/cvf-design/measure_d3.py`, over slot-glance's census of 5,216 closes, with each verdict line replayed as if it were line 1:

   | Verdict lines that would fire D3 | no lines (3,435) | yes lines (1,781) |
   |---|---|---|
   | D3 today | 1,175 (34.2%) | 215 (12.1%) |
   | hooks-slot prototype | 0 | 114 (6.4%) |
   | **this design** | **0** | **9 (0.5%)** |

   I read all 9 yes-line fires by hand. Every one is a conditional yes ("yes if you only wanted the commit…", "yes, once the rule lands", "yes, but not until the command below runs"), which is D3's own target. The prototype's 114 include honest lines such as "nothing of mine is still open" and "the two steps below are yours" under a 👤 rung.
3. **The floor drops a bare leading "yes".** With it, the floor refused closes that answer a different question before the verdict ("Yes, it's included. …", then `Good to close: no`). Without it the floor fires on 296 of 3,435 no closes (8.6%): 294 open with ✅ and 2 with "Done and landed." (`measure_d3.py`). "Yes" now counts only in the form `yes … safe/good/fine/ok to close`.
4. **The rung may sit on line 2 only when line 1 is a verdict line.** The prototype used a global `CC_RUNG_WINDOW`. Keying on the verdict line keeps today's line-1 strictness for every close that does not lead with a verdict.
5. **The token is named `verdict-first`, not `verdict-not-first`,** so the reason reads "the close is missing [verdict-first]". The kill switch is `CC_VERDICT_FIRST=0`.

## 1. The line-1 rule

### 1.1 What the template and rules teach

The rule applies where a verdict is already due: an origin close, ✅ or 👤, after real written work (the D6 population). "Line N" means the N-th non-blank line, as every arm counts it.

| Ledger rung | Verdict | Line 1 (S2) | Line 2 (S1) | Line 3 |
|---|---|---|---|---|
| ✅ | yes | `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English\|none>` | READOUT's `✅` glyph and state clause verbatim, then one clause of your own naming what the work was | supporting line, or nothing |
| ✅ | no | `❌ Good to close: no — <what remains + who owns it>` | the same rung line | supporting line |
| 👤 | yes | `✅ Good to close: yes — nothing of mine is open; follow-on: …` | `👤 My side is done & landed — <your partition of the count, e.g. 1 runnable now, 1 needs your call>` | `▶ Run this:` (the command goes on the next row) |
| 👤 | no | `❌ Good to close: no — <what remains + who owns it>` | the same 👤 rung line | `▶ Run this:` |
| ⛔ 🔧 📦 🚀 | no verdict slot | **unchanged**: line 1 is the rung line, which already leads with a not-done answer (⛔ *is* the "no, needs you") | — | — |
| any | write-free turn, fired peer, assignee | unchanged; no contract | — | — |

- **Glyph:** ✅ for yes and ❌ for no; this two-valued colour carries the two-valued answer. ❌ is not a rung glyph (✅ ⛔ 🔧 📦 🚀 👤 📤). ⛔ is rejected because it means "need your call" (slot-glance).
- **Blank line after line 1:** recommended in the template and in `/wrap`, never enforced. Without it, line 2 is welded into the same rendered paragraph: 67.5% of line-2 verdicts today (slot-glance) and 83.4% on a 14-day proxy (slot-hooks). Blank lines do not count toward any window.
- **The act line still fits.** The order verdict (1), rung (2), ▶ (3) uses the same count as today's rung (1), verdict (2), ▶ (3). `CC_ACT_WINDOW=3` is unchanged and the slack is still zero, as it is today (replay `noA-person` / `noA-person-late`, §3.6).

### 1.2 How the ledger rung relates

The rung is evidence *for* the verdict, never the verdict. It is relayed on line 2 exactly as S1 already specifies: glyph and state clause verbatim, tail replaced with your own clause. A ✅ rung *permits* yes and never *implies* it (rules S2: "The rung does not imply it"). A non-✅/👤 rung forbids yes and has no verdict slot. D6 still checks that the glyph is relayed; the window is now "line 1, or line 2 under a verdict line 1".

### 1.3 What the hook accepts during the transition

| Close shape | Hook result |
|---|---|
| A′, yes or no (rung on line 2) | PASS |
| C-style single line `❌ Good to close: no — … · ledger: ✅ …` | PASS (rung contained in line 1) |
| Old shape, yes: `✅ Complete … ` / `Good to close: yes — …` | **PASS.** The yes path is not tightened at all. |
| Old shape, no, 👤 rung: `👤 My side is done & landed …` / `Good to close: no — …` | PASS. 👤 is not a done glyph, and blocking it would hit the ledger's own 👤 wording (113 hits, slot-corpus §3). |
| Old shape, no, line 1 opens ✅ / complete / done / nothing to do / safe to close (**the LEFT screenshot**) | **REFUSED: `shape` / `verdict-first`** |
| `✅ Good to close: no — …` (verdict first, but the wrong glyph) | REFUSED: `verdict-first`. The green glyph is the misread. |
| `Good to close: no — …` with no glyph, rung on line 2 | PASS. The hook judges shape and does not require ❌. |

## 2. Doc rule changes

Use the **C-variant** drafts in `slot-docs.md` §4. Their OLD strings were verified to occur exactly once (`/tmp/cvf-docs/tools/apply.py`). Apply one global delta, **Δ1**: wherever a C draft says `<rung glyph> Good to close: yes` or "the rung glyph on a yes", write `✅ Good to close: yes` / "✅ on a yes". Where my text below differs from the C draft, mine wins.

### 2.1 `CLAUDE.rules.slim.10-session-close.md` (deployed to `~/.claude/rules/10-session-close.md`)

- **R1** (line 22), final text:
  > - Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work leads with the verdict: line 1 `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or `❌ Good to close: no — <what remains + who owns it>`, line 2 the ledger's rung glyph (`line-1-rung`). A no under a ✅ or done-reading line 1 fails (`verdict-first`); naming what remains is no hedge, a both-ways answer is (D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.
- **R2** (lines 129-137): the C draft with Δ1. Heading `### The six slots, verdict first`. The rows:
  - `| S2 VERDICT, line 1 | ✅ Good to close: yes — … or ❌ Good to close: no — …, with the follow-on ledger | terminal close (✅/👤) after real written work |`
  - `| S1 STATE, line 2 (1 if no S2) | …unchanged… | always |`
  - `| S3 ACT, line 3 | … |`
- **R3, R4:** the drafts as written (identical for B and C).
- **R5** (line 148), final text:
  > S2. The `Good to close:` line, in either form given under Origin close contract, first and never last. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate (git facts only) neither replaces nor overrules it; an honest no satisfies the contract.
- **O1 and O2:** apply both offsets, which are required. **Measured** with `python3 -I /tmp/cvf-design/rules_measure.py` using `instruction_budget.parse`: loader units 30,334 → 30,477 (+143) without the offsets, and **30,334 → 30,320 (−14) with them**. The user tier is already in BREACH (60,696 > 60,000, slot-docs §2), and the slim files are one-in-one-out, so the net change must be ≤ 0. The strings pinned by `tests/research-program-exemption-rules.bats` and the `priority` ladder line survive in the patched file (grep, 1 match each).

### 2.2 `CLAUDE.global.md` (deployed to `~/.claude/CLAUDE.full.md`; not loaded, so no budget applies)

G0, G5: as drafted. G2, G3, G4, G6, G7: the C drafts with Δ1. G7 ends "Hence the verdict owns line 1 and its glyph: ✅ on a yes, ❌ on a no." **G1**, final text:

```
  closing genuine completion (✅/👤) after real written work must answer, mechanically matched,
  **two** things, **verdict first**: line 1 is the verdict, led by its own glyph —
  `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or
  `❌ Good to close: no — <what remains + who owns it>` — and line 2 relays the ledger's own
  **rung glyph** and state clause (`line-1-rung` accepts the glyph there). An honest no satisfies
  (the contract is that the question is ANSWERED; hedging stays D3's defect, and naming what
  remains is not a hedge). A no under a line 1 that opens with ✅ or a done reading is refused
  (`verdict-first`; kill switch `CC_VERDICT_FIRST=0`). § The close message S2 carries the measurement.
  🚨 **`Complication:` / `Solution:` /
```

Not edited in this land: `CLAUDE.global.md:704`, the ladder row "✅ … safe to close". It belongs to follow-on F2 (§7).

### 2.3 Everything else

- **`CLAUDE.global.slim.md` (deployed to `~/.claude/CLAUDE.md`): no edit.** It carries no close-placement text (grep). The slim variant's close protocol *is* the rules file. Adding a line would grow a tier that is already over budget. **Plan correction:** W3's "grep deployed `~/.claude/CLAUDE.md` for the new rule" would find nothing. Verify `~/.claude/rules/10-session-close.md` and `~/.claude/CLAUDE.full.md` instead.
- **`commands/wrap.md`:** W1, W2, W3 are the C drafts. **W4**, final text:
  > Line 1 is the verdict, led by its own glyph: ✅ on a yes, ❌ on a no; leave one blank line under it. Line 2 is wrap-ledger's rung readout, verbatim. An honest `❌ Good to close: no — <what remains + who owns it>` satisfies the contract; naming what remains is not a hedge, a both-ways answer is (D3).
- **`commands/are-we-done.md`: A1 (the C draft with Δ1) and A2.** This is **scope growth**; record it as `Scope (grown):`. The command is headed "the VERDICT FIRST" but emits the rung first, and leaving it would keep teaching the old shape. The A1 block, line 1: `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids | none>`; line 2: `<rung glyph> <state clause> — <one clause naming what the work WAS>`. Below the block: "On a `no`, line 1 is `❌ Good to close: no — <which check, and who owns it>`; the rung line stays line 2."
- **`hooks/lib/why-tier.sh`:** Y1 and Y3 as drafted. **Y2**: the C draft with Δ1 (item 1 `✅ Good to close: yes — …` or `❌ Good to close: no — …`), with its paragraph replaced by this text, which carries no corpus numbers:
  > VERDICT FIRST, NEVER LAST. The rung does not decide the verdict — a ✅ ledger can still mean no — and a ✅ line 1 above a `Good to close: no` on line 2 still reads as yes at a glance (operator screenshot, 2026-10-10: two closes side by side, both opening ✅; one answered no, and both read yes). A no under a line 1 that opens with ✅ or a done reading is refused as `verdict-first`.

  Keep the `HEDGE —` prefix, which `tests/why-tier.bats` pins.
- **`docs/plans/STOPHOOK_MESSAGE_TIERING.md:552`:** T1, the C draft.
- **No edit:** `core/` (outside the frozen scope; its gate accepts both shapes, slot-docs §1) and `install.sh` (it deploys the rules file by glob).

## 3. Hook changes

All code below is exactly what the prototype ran: `/tmp/cvf-design/patch.py` applied to a scratch copy (`/tmp/cvf-design/proto/hooks/`).
- **Measured:** bare `shellcheck` on both files rc 0 (the land gate's own invocation); `/bin/bash -n` (3.2) OK on both.
- **Unchanged:** the CA_SETTLED and CA_RETRACT values, D1, D2, D4, D5, D7, the latch, the caps, the classes and every exemption.

### 3.1 `hooks/lib/close-shape.sh`

**New functions,** inserted before `close_shape_ok`:

```bash
# close_verdict_polarity <msg> → yes | no | mixed | none   (CLOSE_VERDICT_FIRST, 2026-10-10)
close_verdict_polarity() {
  printf '%s' "${1:-}" | awk -v v="$_CS_VERDICT" '
    BEGIN { fence = 0; y = 0; n = 0 }
    { t = $0
      if (t ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      l = tolower(t)
      if (!match(l, v)) next
      pre = substr(l, 1, RSTART - 1); rest = substr(l, RSTART + RLENGTH)
      if (pre ~ /(^|[^a-z])not[ \t]+$/) { n = 1; next }
      gsub("—", " ", rest); gsub("–", " ", rest)
      sub(/^[ \t*_:?!.,`-]*/, "", rest)
      if (rest ~ /^</) next
      if (rest ~ /^yes([^a-z]|$)/) { y = 1; next }
      if (rest ~ /^(no|not)([^a-z]|$)/) { n = 1; next }
      t2 = l; sub(/^[ \t*_#>`-]+/, "", t2); if (index(t2, "✅") == 1) y = 1
    }
    END { print (y && n) ? "mixed" : (n ? "no" : (y ? "yes" : "none")) }'
}

# close_line_reads_done <line> → rc 0 iff the line LEADS with a done reading
close_line_reads_done() {
  printf '%s' "${1:-}" | sed -E 's/^[[:space:]*_#>`-]+//' \
    | grep -iE '^(✅|complete|done([^a-z]|$)|all done|safe to close|nothing (left |more |else )?to do|yes[^a-z]+((it.?s|we.?re|this is)[^a-z]+)?(safe|good|fine|ok(ay)?)[^a-z]+to[^a-z]+close)' >/dev/null
}
```

Notes on the two functions:
- **Polarity** reads unfenced lines only and skips the `<…>` placeholder (the same mention-vs-use guard as `real()`), so a quoted template returns `none`. Both polarities in one message give `mixed`, and `mixed` abstains: a false PASS is preferred to a false FAIL.
- **`close_line_reads_done`** is anchored at the start of the line after stripping markdown. So `❌ Good to close: no — … · ledger: ✅` and `👤 My side is done …` both read as not-done. The output is drained with `>/dev/null`, not `grep -q`, because of the SIGPIPE-under-pipefail trap the hook documents at `:232`.
- **Unit check, measured** (`bash /tmp/cvf-design/unit.sh`), with identical output under `en_CA.UTF-8` and `LC_ALL=C`:
  - Reads done: `✅ Complete …`, `**✅ Complete**`, `Done and landed.`, `Nothing left to do here.`, `Yes, it's safe to close.`, `- ✅ Safe to close`, `✅️` (with VS16).
  - Reads not done: `❌ Good to close: no`, `Good to close: no`, `👤 My side is done…`, `Yes, it's included.`, `📦 Done, but only on a branch`.

**Template** (K3, A′). It keeps the guard: `close_shape_ok "$(close_shape_template)"` is rc≠0 and `close_shape_missing` prints exactly `good-to-close-verdict`. Polarity is `none` and the template contains no `▶` (all measured, `unit.sh`):

```
<S2 line 1, led by the verdict's own glyph — ✅ on a yes, ❌ on a no> Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
<S1 line 2 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
<S3, only when the operator must act: …unchanged…>
<then AT MOST three supporting lines, …unchanged…>
```

The `/wrap` W4 prose tells the model to leave a blank line under line 1, so the template itself needs no blank line.

**Act template** (K4), line 1: `<lines 1-2 = the good-to-close verdict, then the ledger rung readout verbatim from wrap-ledger>`. The hyphenated "good-to-close" does not match the verdict anchor, which is deliberate.

**Block reason** (K5). The whole printf is replaced. It has no backticks, no corpus numbers and no literal non-placeholder verdict, so a close that pastes the reason still answers nothing:

```bash
  local vf=""
  case " $missing " in
    *" verdict-first "*) vf=' A missing verdict-first means your verdict is NO but line 1 opens with a done reading (✅, complete, done, nothing to do, safe to close), so the close reads as finished before the no is reached: put the verdict line first, led by ❌, and move the rung line under it. Naming what remains is not a hedge.' ;;
  esac
  printf 'Origin-session close contract: this session wrote real work and the ledger reads %s, but the close is missing [%s]. Lead with the answer: line 1 is the good-to-close verdict, led by its own glyph (✅ on a yes, ❌ on a no), and the ledger'\''s rung line goes directly under it, before any supporting detail. A missing good-to-close-verdict means the close never answers the question, and the rung cannot answer it for you: a ✅ ledger can still mean no, and a ✅ line above a no reads as yes at a glance. A missing line-1-rung means neither line 1 nor, under a verdict line 1, line 2 carries the ledger'\''s own rung glyph: run scripts/wrap-ledger.sh --machine, relay READOUT'\''s glyph and state clause verbatim, then add ONE clause of your own naming what the work was.%s Complication/Solution/Outcome are not required; write them only if they say something the body does not. Shape:\n%s' \
    "$rung" "${missing:-the required close shape}" "$vf" "$(close_shape_template)"
```

**Header comments** (K1 plus the 613 lines). These are given in §5.

### 3.2 `hooks/completion-assert.sh`: definitions and the second line (beside CA_SETTLED, `:317`)

```bash
CA_VERDICT_ANCHOR='good[[:space:]]+to[[:space:]]+close'
CA_VERDICT_NO='(^|[^a-z])not[[:space:]]+good[[:space:]]+to[[:space:]]+close|good[[:space:]]+to[[:space:]]+close[^a-z]*(no|not)([^a-z]|$)'
CA_VERDICT_YES='good[[:space:]]+to[[:space:]]+close[^a-z]*yes([^a-z]|$)'
CA_YES_HEDGE='good[[:space:]]+to[[:space:]]+close[^a-z]*yes[^a-z]+(but|with|except|aside from|apart from|other than|once|after|until|pending|provided|as long as|if)([^a-z]|$)'
ca_first=""; ca_second=""
while IFS= read -r ca_ln || [ -n "$ca_ln" ]; do
  ca_t="${ca_ln#"${ca_ln%%[![:space:]]*}"}"
  [ -n "$ca_t" ] || continue
  if [ -z "$ca_first" ]; then ca_first="$ca_t"; continue; fi
  ca_second="$ca_t"; break
done <<< "$MSG"
```

These are inline rather than sourced from the lib, because the gate (`:333`) runs before `_ca_source_close_shape` is defined (`:690`). Moving that helper is a refactor with its own risk ("helper position bounds reach"). A bats agreement test (T24) pins `CA_VERDICT_NO` ⇔ `close_verdict_polarity = no`, so the two matchers cannot drift apart.

### 3.3 The close-tell gate (`:333-335`)

A negative verdict on line 1 is not a done-tell:

```bash
  { [ -n "$ca_first" ] && printf '%s' "$ca_first" | grep -iqE "$CA_SETTLED" \
    && ! printf '%s' "$ca_first" | grep -iqE "$CA_VERDICT_NO"; } || abstain "no-close-tell"
```

This only restores today's population for messages that carry no CLOSE token. A ⛔ close led by `Good to close: no — …` abstains `no-close-tell`, as today's `⛔ …` line 1 does. Without this fix it is blocked by the ledger arm (replay `blk-A`: CUR BLOCK ledger → PRO PASS no-close-tell).

### 3.4 D3 (`:1055-1059`)

A verdict line 1 is judged by polarity. Every other line 1 goes through today's test, byte-for-byte:

```bash
if [ -n "$ca_first" ] && printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
  _ca_pre="$(printf '%s' "$ca_first" | awk -v v="$CA_VERDICT_ANCHOR" '{ l = tolower($0); if (match(l, v)) $0 = substr($0, 1, RSTART - 1); print; exit }')"
  if { printf '%s' "$_ca_pre" | grep -iE "$CA_SETTLED" >/dev/null \
       && printf '%s' "$_ca_pre" | grep -iE "$CA_RETRACT" >/dev/null; } \
     || printf '%s' "$ca_first" | grep -iE "$CA_YES_HEDGE" >/dev/null \
     || { printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_YES" >/dev/null \
          && printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_NO" >/dev/null; }; then
    d3=1
  fi
elif [ -n "$ca_first" ] \
   && printf '%s' "$ca_first" | grep -iE "$CA_SETTLED" >/dev/null \
   && printf '%s' "$ca_first" | grep -iE "$CA_RETRACT" >/dev/null; then
  d3=1
fi
```

On a verdict line 1, D3 fires for three things:
1. A hedge in the text *before* the anchor (`✅ Done, but one thing is parked. Good to close: yes`). This keeps today's catch.
2. A yes that is immediately qualified (`yes — with…`, `yes, once…`, `yes if…`). This is the founding shape written as a verdict.
3. Both polarities on one line.

D3 never fires on a no that names its remainder, and never on text after the verdict value: the `follow-on:` clause, "nothing … still open", "… are yours". The founding fixture `Yes — with one thing still parked.` has no anchor, so it still fires through the unchanged branch.

**D3 reason** (`:1414`): append ` On a verdict line, a conditional yes (yes if…, yes once…, yes but…) is a no until the condition holds: answer no and name the condition. A plain no that names what remains is not a hedge.` The phrase `ONE rung that actually governs`, pinned by bats `:496`, is kept.

### 3.5 D6 (`:1262-1265`)

The rung window moves under a verdict line 1, and the new token is added. Everything else in D6 (the gates, the exemptions, the `shape` class, the latch, COMPLETION_SHAPE_MAX=2) is unchanged:

```bash
    _d6_rl="$ca_first"
    if printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
      _d6_rl="$ca_first
$ca_second"
    fi
    case "$_d6_rl" in
      *"$RUNG"*) : ;;
      *) _d6_missing="${_d6_missing:+$_d6_missing }line-1-rung" ;;
    esac
    if [ "${CC_VERDICT_FIRST:-1}" != 0 ] && command -v close_verdict_polarity >/dev/null 2>&1 \
       && [ "$(close_verdict_polarity "$MSG")" = no ] && close_line_reads_done "$ca_first"; then
      _d6_missing="${_d6_missing:+$_d6_missing }verdict-first"
    fi
```

- **Inherited from D6:** origin only (fired peers out), RUNG ∈ {✅, 👤}, positive write evidence, contra=0, not a confirmed assignee, and `CC_CLOSE_SHAPE=0`.
- **Fail-open on an older lib:** `command -v close_verdict_polarity` means a stale lib (an older worktree or deploy) adds no demand.
- **Kill switch:** `CC_VERDICT_FIRST=0` silences only this token.
- **What stays the same:** the rung-window relaxation and the D3 and gate changes can only move FAIL → PASS, so no switch is needed for them. D7 is unchanged, and its zero slack is the same as today.

### 3.6 Replay evidence

Measured with `/tmp/cvf-design/runall.sh` and `run_person.sh`, which run the real hook over a hermetic copy of the bats `setup()`. Each case is an origin session with a stub ledger and one `Edit` tool use. CUR is HEAD; PRO is the prototype. In the 👤 rows a filed backlog row is present, which takes D1 out of the comparison: without it, D1 fires on CUR and PRO alike, as it does today.

| Fixture | CUR | PRO |
|---|---|---|
| **LEFT verbatim** (✅ line 1, verdict no on line 2) | PASS | **BLOCK shape (verdict-first)** |
| **RIGHT verbatim** (✅ line 1, verdict yes) | PASS | **PASS** |
| LEFT reshaped to A′ (`❌ Good to close: no — …`, blank line, ✅ rung) | BLOCK shape | PASS |
| A′ no naming "remain" / "yours" + "pending" / no glyph / docs-B wording | BLOCK hedge(+shape) | PASS ×4 |
| A′ yes, `follow-on: … parked` / "nothing of mine is still open … nothing pending" | BLOCK hedge | PASS ×2 |
| 👤 A′ yes "…the two steps below are yours" + ▶ on line 3 | BLOCK hedge+shape | PASS |
| 👤 A′ no + ▶ on line 3 / the same with one extra line before ▶ | BLOCK shape / shape+act | PASS / BLOCK act (as today) |
| C-style one line `❌ … · ledger: ✅ …` | BLOCK hedge | PASS |
| `✅ Good to close: no — …` (wrong glyph) | BLOCK hedge | BLOCK shape (verdict-first) |
| `✅ Good to close: yes, once pane 182's change lands.` | PASS | **BLOCK hedge** (the one new FAIL class; see §7) |
| Founding `Yes — with one thing still parked.` | BLOCK hedge+shape | BLOCK hedge+shape |
| Old-shape yes / old-shape 👤 no | PASS / PASS | PASS / PASS |
| ⛔ rung, line 1 `Good to close: no — …`, no CLOSE token | BLOCK ledger | PASS no-close-tell |
| Mixed polarity (quotes another pane's no) | PASS | PASS |
| `✅ Complete … — but NOT good to close: …` | BLOCK hedge | BLOCK hedge+shape |
| `Done and landed. …` / `Good to close: no — …` | BLOCK shape | BLOCK shape |
| Quoted template | BLOCK shape | BLOCK shape |
| LEFT from a fired peer / LEFT with `CC_VERDICT_FIRST=0` | — | PASS / PASS |
| `Good to close: no — but honestly it is fine to close.` | BLOCK hedge+shape | PASS (a residual false PASS; see §7) |

**The existing bats cases were not run on the prototype.** `bats --filter 'D3|D6|D7|close-shape|MENTION|CAP SPLIT'` over a `git archive HEAD` copy with the prototype overlaid returned cc-bats **rc 75 (REFUSED — a deferral, not a result)** on every attempt, at 1-minute load around 260. I did not use the waiver, because it writes under `~/.claude`. The implementer must run the touched suites and assert the `1..N` plan line plus the ok count.

## 4. Other surfaces

| Surface | Change | Why |
|---|---|---|
| `scripts/wrap-ledger.sh` | **None in this land** (F2, F3) | The frozen scope does not name it. A′ already removes the ✅ rung from line 1, which is the misread. The rewording (ledger slot, 92%) and the `SCOPE=met` evidence fix (85%) are correct but touch a different consumer set: the ladder doc at `CLAUDE.global.md:704`, the `operator-readout` closed vocabulary `scope_of`, and their tests. |
| `hooks/operator-readout.sh` | **None in this land** (F1) | It reads no assistant text today (grep: no last-assistant extraction). Withholding `✅ SAFE TO CLOSE` under a no verdict needs a new transcript read on the Stop path. The certificate fires only on write turns with ✅ and SCOPE met, as a grey systemMessage *below* the close. Under A′ the ❌ still leads, but the contradiction remains (see §7). |
| `commands/wrap.md` | **Yes:** prose W1-W4 (§2.3) | The template and the act template propagate automatically through `close_shape_template` and `close_act_template`. |
| `hooks/anti-deference-nudge.sh` | **None** | It reads the whole message, so position does not matter to it (slot-hooks §6). The template asks for the same "what remains + who owns it" content as today's line 2, now on line 1, so its count-not-content, bare-id and SOFTCALL triggers see the same text. |
| `cc-pane-close`, `lead-crash-watchdog`, `cc-husk-sweep`, `dl`, `router.py` | **None** | The literal `Good to close: yes\|no` is kept. `router.py`'s `^\W*` skips ❌ and ✅. |
| `scripts/measure-closes.py` `rung_of` | **None** (noted) | It takes the first rung glyph in the text. On a 👤 yes close in A′ it will read the verdict ✅ as the rung. That is measurement drift only, folded into F4. |

## 5. The 613-figure decision

Follows slot-corpus §4. The 2026-08-23 figures are stale in both directions:

| Figure | August | Now |
|---|---|---|
| Rung predicts the verdict | 73.4% | 83.5% |
| Verdict is the last line | 90.7% | 12.9% |
| Verdict at line ≤ 3 | 1.1% | 89.1% |

Source: `python3 -I /tmp/cvf-corpus/measure.py --days 30`, 5,017 verdict closes. The pointer `§ M3` in the lib does not exist; the figures are in § R4. The decision:

1. **The block reason carries no numbers** (§3.1 K5). Only the mechanism remains: "a ✅ ledger can still mean no, and a ✅ line above a no reads as yes at a glance".
2. **The header comment at `close-shape.sh:44-49` is replaced:**
   ```
   # Env seam (tests): CC_VERDICT_WINDOW (default 0 = position-free — the verdict may sit at any
   # non-blank, non-fenced line). It stays OFF by design: position is not what misleads the
   # operator. Re-measured 2026-10-10 over 5,017 verdict closes (2026-09-10..10-10, five account
   # roots): the verdict already sat at line 2 in 80.8% and at line <=3 in 89.1%, yet 264 of the
   # 1,315 closes opening with ✅ answered no — the ✅ line above the no is what gets misread. That
   # contradiction is refused by completion-assert D6 `verdict-first` (close_verdict_polarity +
   # close_line_reads_done); a window adds nothing for it and would fail the 10.9% of closes whose
   # verdict sits at line 4+, whose honesty is unmeasured. Instrument (re-run it, never quote these):
   # docs/research/close-verdict-first-2026-10-10/slot-corpus.md § 5. The 2026-08-23 figures this
   # replaces (613 closes, "1.1% at <=3") are in docs/research/close-shape-2026-08-23.md § R4.
   ```
3. **The paragraph at `:59-62` keeps its claim with re-dated figures:** "re-measured 2026-10-10, the line-1 glyph predicts it 83.5% (3,343/4,005), 264 of 1,315 ✅-led closes answer no, and 20.1% carry no rung glyph on line 1 (instrument as above); the 2026-08-23 figures are in close-shape-2026-08-23.md § R4". Change `§ M3` to `§ R4`.
4. **K1** (`:19`): "…keeps sole ownership of the rung line (line 2 under a verdict line 1, which owns line 1 — CLOSE_VERDICT_FIRST 2026-10-10)".
5. **The `0 of the 613` sentence at `:71-72`** (the `safe` anchor) stays, prefixed "(2026-08-23)". It is historical justification, not a live claim.
6. **The why-tier Y2 numbers go** (§2.3).
7. **Instrument:** the script is committed verbatim in `slot-corpus.md` §5 when this directory lands. Promoting it to `scripts/` is F4, not this land.

## 6. Tests

Add to `tests/completion-assert.bats`, using the suite's own seams: `mkledger`, `_d6_tr`, `run_ca`, `fired`, `_cs_lib`, `CC_BACKLOG_STUB_JSON`, and the fired-peer stamp.

- **Fixtures** go in `tests/fixtures/close-verdict-first/{left,right,left-aprime}.txt`. `left` and `right` are byte copies of `/tmp/cvf-hooks/left.txt` and `right.txt`, extracted with jq from transcripts `44091255-…` (16:15:41.992Z) and `3bd7aa3b-…` (16:15:38.550Z). `left-aprime` is `/tmp/cvf-design/v/leftA.txt`.
- Load fixtures from files, not heredocs inside `$( )`: bash 3.2 miscounts parentheses there.
- Write every negation as `if …; then false; fi`.

**Helper:** `_cvf <tag> <text> [rung=✅]`. It builds a `mkledger` stub (`DIRTY=0 … RUNG=<rung>`, `YOURS=1` when the rung is 👤), runs `_d6_tr` with one written path, then `run_ca … "cvf-<tag>"`. For 👤 cases, set `CC_BACKLOG_STUB_JSON='[{"session":"cvf-<tag>","title":"x"}]'` so D1 stays out.

| # | Case | Assert |
|---|---|---|
| T1 | **LEFT screenshot, verbatim** | fired; reason contains `verdict-first`; IDL `"arm":"shape"` |
| T2 | **RIGHT screenshot, verbatim** | not fired; IDL `ledger-clean` |
| T3 | LEFT reshaped to A′ (`left-aprime`) | not fired (proves the rung window and D3 polarity) |
| T4 | D3 does not convict an honest no on line 1: loop over `still open` / `remain; pane 182 owns the next` / `has a pending change` / `is yours to approve` / `but pane 182 lands first`, each `❌ Good to close: no — <r>.` + `✅ Complete & live on trunk — x.` | no `hedge` in IDL for any of them |
| T5 | A conditional yes on a verdict line: `✅ Good to close: yes, once pane 182's change lands.` | fired; IDL `"arm":"hedge"` |
| T6 | A yes verdict line with a parked follow-on and a negated remainder | no `hedge` |
| T7 | 👤 A′ yes "…the two steps below are yours" + ▶ on line 3, filed row | not fired |
| T8 | 👤 A′ no + ▶ on line 3, filed row; CONTROL: one extra line before ▶ | not fired; CONTROL fired, `"arm":"act"` (pins zero slack, unchanged) |
| T9 | `✅ Good to close: no — …` | fired, `verdict-first` |
| T10 | Gate: RUNG ⛔, line 1 `Good to close: no — the keep-or-retire call … is open with you.`, no CLOSE token | not fired; IDL `no-close-tell` |
| T11 | Fired peer (`ITERM_SESSION_ID=w0t0p0:43` + stamp) sends LEFT | output has no `verdict-first` |
| T12 | Confirmed assignee (`AGENT_IDENTITY_LIB` → a stub defining `agent_is_assignee(){ return 0; }`, plus anything `_ca_ai_source` requires) sends LEFT | no `verdict-first` |
| T13 | Write-free session (`mkfix`, no tool use) sends LEFT | no `Origin-session close contract` |
| T14 | Mixed polarity (yes verdict, quotes another pane's `"Good to close: no"`) | no `verdict-first` |
| T15 | SEAM: `CC_VERDICT_FIRST=0` with LEFT; `CC_CLOSE_SHAPE=0` with LEFT | not fired in both |
| T16 | Old-shape yes (`✅ Complete…` / `Good to close: yes — …`) | not fired (the yes path is not tightened) |
| T17 | Old-shape 👤 no (`👤 My side is done & landed…` / `Good to close: no — …` / ▶), filed row | not fired |
| T18 | C-style one line `❌ Good to close: no — … · ledger: ✅ Complete & live on trunk` | not fired |
| T19 | The window is NOT widened without a verdict line 1: `The cutover landed.` / `✅ Complete…` / `Good to close: yes — …` | fired, `line-1-rung` |
| T20 | UNIT `close_verdict_polarity`: left→no, right→yes, left-aprime→no, mixed→mixed, template→none, a verdict inside a ``` fence→none, `Are we good to close? No — …`→no, `not good to close`→no | exact strings |
| T21 | UNIT `close_line_reads_done`: the done and not-done lists in §3.1 | rc per row |
| T22 | UNIT template: `close_shape_ok` rc≠0 and missing = `good-to-close-verdict` (existing `:1657` still holds); polarity(template) = `none`; no `▶` | as stated |
| T23 | UNIT reason: `close_shape_reason ✅ verdict-first` contains `A missing verdict-first`; `close_shape_reason ✅ line-1-rung` does not; neither contains `613` or `73%` | grep |
| T24 | AGREEMENT: for a table of 12 lines, `CA_VERDICT_NO` (lifted from the hook by its `^CA_VERDICT_NO=` line) matches ⇔ `close_verdict_polarity` returns `no` | equality per row |
| T25 | LOCALE: T1 and T20 under `LC_ALL=C` | the same results (measured equal in `unit.sh`) |
| T26 | Done-led non-✅ line 1 (`Done and landed. …`) + verdict no | fired; contains `verdict-first` |

**Regressions that must stay green unchanged:**
- D3 `:491`, `:501`, `:512`, `:519`.
- D6 `:1272`-`:1325` (the token-name pins `good-to-close-verdict` and `line-1-rung` are kept).
- Close-shape `:1657`, `:1666`, `:1677`.
- CAP SPLIT `:1698`, `:1717`.
- D7 `:1758`-`:1936`.
- `tests/why-tier.bats` (`HEDGE —`), `tests/research-program-exemption-rules.bats`, `tests/wrap-ledger.bats` (the ladder line), `tests/cc-pane-close.bats`, `tests/lead-crash-pane-verdict.bats`.

**Gate:** bare `shellcheck` on the touched files, then `bats tests/completion-assert.bats tests/why-tier.bats tests/research-program-exemption-rules.bats`, asserting `1..N` and the ok count.

## 7. Risks, and what this deliberately does not do

**Risks:**
1. **One shape block per old-shape ✅ no close, until models adapt.** Sessions started before the deploy hold the old rules in context. The proxy upper bound is 296 of 3,435 no closes in 30 days (8.6%, `measure_d3.py`, all closes, not D6-gated). The real D6-gated rate is unmeasured, because the transcripts do not record the ledger rung. Each block costs one re-close, and the `shape` cap of 2 bounds it.
2. **New FAIL class: a conditional yes on a verdict line 1.** Proxy rate 9 of 1,781 yes lines (0.5%); 9 of 9 sampled are real conditionals. They are D3's target by the rule's own words, but today they sit on line 2 and pass.
3. **Residual false PASSes, stated:**
   - `Good to close: no — but honestly it is fine to close.` no longer trips D3.
   - A 👤 line 1 over a no passes. So does a no close with no CLOSE token anywhere, which is invisible behind the gate exactly as today.
   - Closes with a no verdict that are write-free, from fired peers, or from assignees are not reached.
4. **Two ✅ glyphs on a ✅-yes close** (the verdict and the rung). This is redundant, but both mean yes.
5. **A red ❌ might push models toward dishonest yeses.** The falsifier is the corpus yes:no ratio, re-run with slot-corpus's script about 14 days after deploy. Today's ratio is 1,724 : 3,289.
6. **The certificate contradiction remains** until F1 lands (`✅ SAFE TO CLOSE` under a ❌ verdict on write turns).
7. **Not verified:** the existing bats suites on the prototype (cc-bats deferral, §3.6), and the TUI's rendering of a single newline as one paragraph (inferred from one screenshot plus its raw text).

**What this deliberately does not do:**
- It does not require ❌ or any verdict position: no `CC_VERDICT_WINDOW`, no line-1 position check.
- It does not judge whether the verdict is right. That is a quality call; a deterministic hook judges shape.
- It does not touch wrap-ledger, operator-readout, `core/`, `CLAUDE.global.slim.md`, `scripts/limit-recover/lr_recon/**` or `settings.json`.
- It does not widen the close-tell gate, D7's rung scope or any cap.

## 8. Follow-ons (file as rows; none blocks this land)

- **F1 operator-readout:** in the ✅ certificate arms (`:1137` and the standalone path near `:1866`), read the last main-agent assistant text with the same jq as `completion-assert.sh:258`, and abstain `cert-verdict-no` when `close_verdict_polarity` = no. This is advisory only, so it carries no false-FAIL risk.
- **F2 wrap-ledger wording:** reword the five ✅ READOUT arms (`:2277`, `:2432-2441`) to git-only wording. Keep `RUNG=✅`. Update `CLAUDE.global.md:704`. Add a test that the default ✅ READOUT never matches `complete|nothing to do|safe to close` (ledger slot §6.1).
- **F3 `SCOPE=met` needs evidence:** a new value `unchecked`, accepted by `scope_of` in the same commit (closed-vocabulary lesson; ledger slot §6.2).
- **F4 instruments:** promote slot-corpus's `measure.py` to `scripts/measure-close-verdicts.py`; add `~/.claude-next4` to `measure-closes.py` ROOTS; make `rung_of` skip a verdict-anchored line 1.
- **Side finding, not ours:** a cold `cc-backlog list` takes 6-13 s against wrap-ledger's 5 s timeout, and the 👤 and filed-undriven checks then fall through to ✅ (ledger slot §7).
