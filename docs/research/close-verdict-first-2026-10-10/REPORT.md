**Decision: design A′, hardened. The verdict owns line 1 with its own glyph (✅ for yes, ❌ for no), the ledger's rung line moves verbatim to line 2, and the Stop hook refuses only a NO verdict under a line 1 that reads as done. Conviction: 88%.**

# CLOSE_VERDICT_FIRST: final synthesis

Date: 2026-10-10. Inputs: the five slots, `design.md`, `skeptic-false-fail.md` and `skeptic-operator-intent.md`, all in `docs/research/close-verdict-first-2026-10-10/`.

How this report was produced:
- I re-derived every corpus figure, re-implemented every fix in a scratch prototype, and replayed the prototype through the real hook. Scratch files are in `/tmp/cvf-report/`, and the patched copy of the hooks is in `/tmp/cvf-report-proto.wT0neA/repo`.
- I edited no tracked file and ran no git write.
- Every number below is labelled with the command that produced it (§5 lists them), or is marked as an estimate.

**How the 88% splits:**

| Part | Conviction | Basis |
|---|---|---|
| Shape: A′ over B and C | 87% | Slot-glance and design §0, unchanged by either skeptic |
| ❌ as the glyph for no | 75% | Unchanged |
| Hook narrowness: no false FAIL on an honest close, beyond the old-shape done-led no closes this change exists to refuse | 92% | 0 yes closes are refused, by construction and as measured. The Python port agrees with the bash lib on 725 of 725 closes. 19 must-not-fire fixtures pass through the real hook |
| Discounts | — | The bats suites were not run (cc-bats rc 75 under load). The D6-gated rate cannot be measured, because transcripts do not record the ledger rung |

## 1. The final design

### 1.1 What the rules and template teach

| Ledger rung | Verdict | Line 1 | Line 2 | Line 3 |
|---|---|---|---|---|
| ✅ | yes | `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids, each expanded\|none>` | READOUT's glyph and state clause verbatim, then your own clause in place of its tail | supporting line or nothing |
| ✅ | no | `❌ Good to close: no — <what remains + who owns it>` | the same rung line | supporting line |
| 👤 | yes | `✅ Good to close: yes — …` | `👤 My side is done & landed — <partition of the count>` | `▶ Run this:` |
| 👤 | no | `❌ Good to close: no — …` | the same 👤 line | `▶ Run this:` |
| ⛔ 🔧 📦 🚀 | — | **unchanged**: the rung line leads; there is no verdict slot | — | — |
| write-free turn, fired peer, assignee | — | unchanged; no contract applies | — | — |

- **A blank line under line 1** is recommended in `/wrap` and in the block reason, and never enforced.
- **The act window still fits.** The order is verdict (1), rung (2), ▶ (3), so `CC_ACT_WINDOW=3` holds with zero slack, as it does today.
- **The literal `Good to close: yes|no` is kept.** Five parsers match it case-sensitively: `bin/cc-pane-close:99`, `hooks/lead-crash-watchdog.sh:1382`, `bin/cc-husk-sweep:353`, `bin/dl:808` and `router.py:1372-1381`. Do not bold the value.

### 1.2 What the hook does with each shape

Measured by `bash /tmp/cvf-report/runall.sh`: the real hook, 41 cases on each side.

| Close | HEAD | Final |
|---|---|---|
| **LEFT screenshot, verbatim** | PASS | **BLOCK `verdict-first`**, class `verdict` |
| **RIGHT screenshot, verbatim** | PASS | **PASS** |
| LEFT reshaped to A′ | BLOCK `line-1-rung` | PASS |
| `✅ Good to close: no — …` (wrong glyph) | PASS | BLOCK `verdict-first` |
| `Done and landed.` / `Good to close: no — …` | BLOCK `line-1-rung` | BLOCK `line-1-rung verdict-first` |
| Old-shape 👤 no: `👤 My side is done & landed …` / `Good to close: no — …` | PASS | **BLOCK `verdict-first`** |
| Old-shape 👤 no whose line 1 does not read as done (`👤 Waiting on you: …`) | no-close-tell | no-close-tell |
| Old-shape yes (✅ line 1, yes on line 2) | PASS | PASS: the yes path is not tightened |
| A′ no naming "still open" / "remain" / "pending" / "but …" | BLOCK hedge+shape | PASS ×4 |
| A′ no naming "is yours to approve", with no filed row | BLOCK hedge+handoff+shape | BLOCK handoff: D1 working as designed, the same as HEAD |
| 👤 A′ yes "…the two steps below are yours" + ▶ / 👤 A′ no + ▶ | BLOCK | PASS / PASS |
| 👤 A′ no with one extra line before ▶ | BLOCK shape+act | BLOCK act (zero slack, as today) |
| C-style single line `❌ … · ledger: ✅ …` | PASS | PASS |
| `✅ Good to close: yes, once pane 182's change lands.` | PASS | BLOCK hedge (the one new FAIL class) |
| `✅ Good to close: yes — with one thing still parked.` | BLOCK hedge | BLOCK hedge |
| Skeptic F1, F3, F5, F10, F13, F14 (honest yes forms) | PASS ×5, F10 BLOCK `line-1-rung` | **PASS ×6** |
| Mixed polarity (quotes another pane's no) | PASS | PASS |
| ⛔ rung, line 1 `Good to close: no — …`, no CLOSE token | BLOCK ledger | PASS no-close-tell |
| LEFT from a fired peer / `CC_VERDICT_FIRST=0` / `CC_CLOSE_SHAPE=0` | PASS | PASS ×3 |
| Session already holding 2 `shape` fires, then LEFT | PASS | **BLOCK, class `verdict` 1/2** |

### 1.3 Skeptic items: disposition

| Item | Disposition |
|---|---|
| FF-P1: "no loose ends" read as NO | **Folded.** A "no" counts only when punctuation or the line end follows it. Applied in both the lib and `CA_VERDICT_NO`. Leading dashes are stripped in a loop |
| FF-P2: D3 verdict branch has no switch; `with` and `after` false-fail | **Folded, with one deviation.** `with` and `after` are dropped. The `VYES && VNO` branch is deleted. The hedge branch sits behind `CC_VERDICT_FIRST`. I **kept `with one thing`** so the founding hedge still fires when it is written as a verdict line; it fires on 0 corpus closes either way. F3 and F13 pass (replay) |
| FF-P3: a done word followed by "?" or "no" | **Folded:** `complete(d)?([^a-z]\|$)` plus a negative-answer guard |
| FF-P4: "Yes, good to close." has no polarity | **Folded:** a yes or a negation before the anchor now counts |
| FF-P5 and Intent-P1: the shape cap starves the demand | **Folded.** New class `verdict` (`COMPLETION_VERDICT_MAX=2`), claimed only when `verdict-first` is D6's sole token and no conviction arm fired. Replayed with the latch already spent |
| FF-P6: the gate change skips every arm | **Accepted and recorded.** 6 of 5,283 anchored closes newly abstain (§4) |
| FF-P7: matcher agreement overstated | **Folded.** `CA_VERDICT_NO` is now used only by the gate. T24 pins the two known divergences |
| FF-P8: sibling reasons teach rung-on-line-1 | **Folded** for the D3 and D1 tails. The D4 and D5 "line-1 rung" wording stays, because those cases are ⛔, which keeps the rung on line 1 |
| FF-P9: `router.py` `OPENS_NO` | **Recorded** as risk R7. Out of scope |
| Intent-P2: old-shape 👤 no passes | **Folded, but narrowed.** `close_line_reads_done` strips a leading 👤 and matches the 👤 READOUT's own words, `my side is (done\|landed\|complete)`. The skeptic's glyph-only rule would refuse 266 👤-led no closes in 30 days. This version refuses 129: the "My side is done…" lines, which I sampled by hand and which read as done. The other 137 (`👤 Waiting on you: …`, `👤 I've written the install script, but you need to run it…`) do not read as done. Refusing them would be a position rule, which the frozen scope does not ask for and the false-FAIL ordering forbids |
| Intent-P3: `SAFE TO CLOSE` under ❌ | **Folded as `Scope (grown):`** in `hooks/operator-readout.sh` (§2.3). The verdict read costs 35 ms on the real 2.3 MB LEFT transcript |
| Intent-P4: rules line 9 and W4 | **Folded.** Line 9 becomes "A ✅ rung is an assertion…". W4 becomes "glyph and state clause verbatim, your clause in place of its tail" |
| Intent-P5: the verdict is not protected from withdrawal | **Folded** in R4 |
| Intent-P6: a no without a glyph | **Left as is.** Counted in F4 |
| Intent-P7: "directly under it" | **Folded** in K5: "goes next (a blank line between them helps)" |
| Intent-P8: "after written work" | **Folded** in R1: "this session" |

## 2. Implementation spec

The mechanical source is `/tmp/cvf-report/patch_final.py`. It applies §2.1 to §2.3 to a scratch copy and asserts that each OLD string occurs exactly once. Running it against HEAD `9abdc1843` gives:
- bare `shellcheck` rc 0 on all three files;
- `/bin/bash -n` OK;
- `pipefail-sigpipe-lint.sh --regen` reports `completion-assert.sh 5` on both HEAD and the patch, and no violation in `operator-readout.sh` or `close-shape.sh` on either.

### 2.1 `hooks/lib/close-shape.sh`

**L1.** Insert the three functions below before `# close_shape_ok <msg>` (`:103`). Put a block comment above them that cites the screenshot and says the hook judges the contradiction, never the position.

~~~bash
close_verdict_polarity() {   # <msg> → yes | no | mixed | none
  printf '%s' "${1:-}" | awk -v v="$_CS_VERDICT" '
    BEGIN { fence = 0; y = 0; n = 0 }
    { t = $0
      if (t ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      l = tolower(t)
      if (!match(l, v)) next
      pre = substr(l, 1, RSTART - 1); rest = substr(l, RSTART + RLENGTH)
      if (pre ~ /(^|[^a-z])(not|isn.t|aren.t)[ \t]+((yet|quite)[ \t]+)?$/) { n = 1; next }
      if (pre ~ /(^|[^a-z])yes[^a-z]+((it.?s|we.?re|this is|this session is)[ \t]+)?$/) { y = 1; next }
      while (sub(/^[ \t*_:?!.,`-]+/, "", rest) || sub(/^—/, "", rest) || sub(/^–/, "", rest)) { }
      if (rest ~ /^</) next
      if (rest ~ /^yes([^a-z]|$)/) { y = 1; next }
      if (rest ~ /^not([^a-z]|$)/ || rest ~ /^no[ \t]*([^a-z \t]|$)/) { n = 1; next }
      t2 = l; sub(/^[ \t*_#>`-]+/, "", t2); if (index(t2, "✅") == 1) y = 1
    }
    END { print (y && n) ? "mixed" : (n ? "no" : (y ? "yes" : "none")) }'
}

close_line_reads_done() {    # <line> → rc 0 iff the line LEADS with a done reading
  local s
  s="$(printf '%s' "${1:-}" | sed -E 's/^[[:space:]*_#>`-]+//; s/^👤[^[:alnum:]]*//')"
  printf '%s' "$s" | grep -iE '^(✅|complete(d)?([^a-z]|$)|done([^a-z]|$)|all done|safe to close|nothing (left |more |else )?to do|my side is (done|landed|complete)|yes[^a-z]+((it.?s|we.?re|this is)[^a-z]+)?(safe|good|fine|ok(ay)?)[^a-z]+to[^a-z]+close)' >/dev/null || return 1
  ! printf '%s' "$s" | grep -iE '^(complete(d)?|done|all done|safe to close)[^a-z]*(\?|(no|not)([^a-z]|$))' >/dev/null
}

close_verdict_not_first() {  # <msg> <line 1> → rc 0 iff verdict NO and line 1 reads as done
  close_line_reads_done "${2:-}" || return 1          # one-line test first: A′ closes skip the awk
  [ "$(close_verdict_polarity "${1:-}")" = no ]
}
~~~

- Output is drained with `>/dev/null`, never `grep -q`, because of the SIGPIPE trap documented at `completion-assert.sh:232`.
- A polarity of `mixed` or `none` means no demand.

**K3, the template at `:119-120`.** Replace the two lines with these, in this order:

~~~text
<S2 line 1, led by the verdict's own glyph — ✅ on a yes, ❌ on a no> Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
<S1 line 2 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
~~~

- The S3 line and the S4–S6 lines are unchanged.
- The template guard still holds (measured): `close_shape_ok "$(close_shape_template)"` gives rc 1, missing is `good-to-close-verdict`, polarity is `none`, and the template contains no `▶`.

**K4, `close_act_template` at `:216`:** `<lines 1-2 = the good-to-close verdict, then the ledger rung readout verbatim from wrap-ledger>`.

**K5, the `close_shape_reason` printf at `:243`.** Replace it whole. The new text carries no numbers and no backticks, and its `%` signs are doubled:

~~~bash
  local vf=""
  case " $missing " in
    *" verdict-first "*) vf=' A missing verdict-first means your verdict is NO but line 1 opens with a done reading (✅, complete, done, nothing to do, safe to close, my side is done), so the close reads as finished before the no is reached: put the verdict line first, led by ❌, and move the rung line under it. Naming what remains is not a hedge.' ;;
  esac
  printf 'Origin-session close contract: this session wrote real work and the ledger reads %s, but the close is missing [%s]. Lead with the answer: line 1 is the good-to-close verdict, led by its own glyph (✅ on a yes, ❌ on a no), and the ledger'\''s rung line goes next (a blank line between them helps), before any supporting detail. A missing good-to-close-verdict means the close never answers the question, and the rung cannot answer it for you: a ✅ ledger can still mean no, and a ✅ line above a no reads as yes at a glance. A missing line-1-rung means neither line 1 nor, under a verdict line 1, line 2 carries the ledger'\''s own rung glyph: run scripts/wrap-ledger.sh --machine, relay READOUT'\''s glyph and state clause verbatim, then add ONE clause of your own naming what the work was.%s Complication/Solution/Outcome are not required; write them only if they say something the body does not. Shape:\n%s' \
    "$rung" "${missing:-the required close shape}" "$vf" "$(close_shape_template)"
~~~

**L4, header comments** (the reasoning is in §4):

| Line | Change |
|---|---|
| `:19` | "…keeps sole ownership of the rung line (line 2 under a verdict, which owns line 1 — CLOSE_VERDICT_FIRST 2026-10-10)." |
| `:44-49` | Replace with the dated rationale from `patch_final.py` (§4, item 2) |
| `:60-62` | Re-dated figures, and the pointer `§ M3` becomes `§ R4` |
| `:71` | Prefix "(2026-08-23)" |
| `:175` | `CC_ACT_WINDOW (default 3 — verdict, rung line, the act)`. Comment only; not in `patch_final.py` |
| `:148` | "Line 1 is already owned by the verdict". Comment only; not in `patch_final.py` |

### 2.2 `hooks/completion-assert.sh`

**H1. Replace the `ca_first` loop at `:319-324`.** Precede it with a comment block, then:

~~~bash
CA_VERDICT_ANCHOR='good[[:space:]]+to[[:space:]]+close'
CA_VERDICT_NO='(^|[^a-z])(not|isn.t|aren.t)[[:space:]]+((yet|quite)[[:space:]]+)?good[[:space:]]+to[[:space:]]+close|good[[:space:]]+to[[:space:]]+close[^a-z]*(not([^a-z]|$)|no[[:space:]]*([^a-z[:space:]]|$))'
CA_YES_HEDGE='good[[:space:]]+to[[:space:]]+close[^a-z]*yes[^a-z]+(but|except|aside from|apart from|other than|once|until|pending|provided|as long as|if|with one thing)([^a-z]|$)'
ca_first=""; ca_second=""
while IFS= read -r ca_ln || [ -n "$ca_ln" ]; do
  ca_t="${ca_ln#"${ca_ln%%[![:space:]]*}"}"
  [ -n "$ca_t" ] || continue
  if [ -z "$ca_first" ]; then ca_first="$ca_t"; continue; fi
  ca_second="$ca_t"; break
done <<< "$MSG"
~~~

These definitions are inline because the gate runs before `_ca_source_close_shape` is defined at `:690`.

**H2. The close-tell gate at `:334`.** A negative verdict on line 1 is not a done-tell:

~~~bash
  { [ -n "$ca_first" ] && printf '%s' "$ca_first" | grep -iqE "$CA_SETTLED" \
    && ! printf '%s' "$ca_first" | grep -iqE "$CA_VERDICT_NO"; } || abstain "no-close-tell"
~~~

**H3. D3 at `:1055-1059`.** A verdict line 1 is judged by the text before the anchor plus the conditional-yes test. Every other line 1 goes through today's test, byte for byte:

~~~bash
if [ -n "$ca_first" ] && printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
  _ca_pre="$(printf '%s' "$ca_first" | awk -v v="$CA_VERDICT_ANCHOR" '{ l = tolower($0); if (match(l, v)) $0 = substr($0, 1, RSTART - 1); print; exit }')"
  if { printf '%s' "$_ca_pre" | grep -iE "$CA_SETTLED" >/dev/null \
       && printf '%s' "$_ca_pre" | grep -iE "$CA_RETRACT" >/dev/null; } \
     || { [ "${CC_VERDICT_FIRST:-1}" != 0 ] && printf '%s' "$ca_first" | grep -iE "$CA_YES_HEDGE" >/dev/null; }; then
    d3=1
  fi
elif [ -n "$ca_first" ] \
   && printf '%s' "$ca_first" | grep -iE "$CA_SETTLED" >/dev/null \
   && printf '%s' "$ca_first" | grep -iE "$CA_RETRACT" >/dev/null; then
  d3=1
fi
~~~

**H4. D6 at `:1262-1265`.** Widen the rung window under a verdict line 1, and add the new token:

~~~bash
    _d6_rl="$ca_first"
    if printf '%s' "$ca_first" | grep -iE "$CA_VERDICT_ANCHOR" >/dev/null; then
      _d6_rl="$ca_first
$ca_second"
    fi
    case "$_d6_rl" in
      *"$RUNG"*) : ;;
      *) _d6_missing="${_d6_missing:+$_d6_missing }line-1-rung" ;;
    esac
    if [ "${CC_VERDICT_FIRST:-1}" != 0 ] && command -v close_verdict_not_first >/dev/null 2>&1 \
       && close_verdict_not_first "$MSG" "$ca_first"; then
      _d6_missing="${_d6_missing:+$_d6_missing }verdict-first"
    fi
~~~

- The token inherits every D6 gate: origin only, RUNG ∈ {✅, 👤}, positive write evidence, `contra_shape=0`, not an assignee, and `CC_CLOSE_SHAPE`.
- `command -v` makes it fail open when an older lib is installed.

**H5. The class choice at `:1376-1377`.** Add a comment that cites 37 of 78 sessions reaching the shape cap, then:

~~~bash
CLASS=assert; CLASS_MAX="$MAX"
if [ "$d6" -eq 1 ] && [ "$_d6_missing" = "verdict-first" ] \
   && [ "$d1" -eq 0 ] && [ "$d2" -eq 0 ] && [ "$d3" -eq 0 ] && [ "$d4" -eq 0 ] && [ "$d5" -eq 0 ]
then CLASS=verdict; CLASS_MAX="${COMPLETION_VERDICT_MAX:-2}"
elif [ "$d6" -eq 1 ]; then CLASS=shape; CLASS_MAX="${COMPLETION_SHAPE_MAX:-2}"
~~~

The `act` branch after it is unchanged. The IDL `arm` stays `shape`, and `class` becomes `verdict`.

**H6. Reason tails.**
- **D3 (`:1414`).** Replace everything from "if it is immaterial…" to the end with: `…if it is immaterial, leave it out entirely. Line 1 answers 'is it safe to close?' once, with no qualifier: a conditional yes (yes if…, yes once…, yes but…) is a no until the condition holds, so answer no and name the condition. A plain no that names what remains is not a hedge."` The phrase `ONE rung that actually governs`, pinned by bats `:497`, is kept.
- **D1 (`:1415`).** `re-close: line 1 states the rung (👤 when steps are yours)` becomes `re-close: the rung line reads 👤 when steps are yours`.

**Correction to design §3.5.** The rung-window relaxation and the gate change only move FAIL → PASS. The D3 conditional-yes branch adds a new FAIL class, and `CC_VERDICT_FIRST=0` silences it.

### 2.3 `hooks/operator-readout.sh` (`Scope (grown):`)

Insert this after the `CERT_WROTE` block at `:1635-1638`, with a comment block above it:

~~~bash
OR_VERDICT_NO=0
if [ "${CERT_WROTE:-2}" = "0" ] && [ "${CC_VERDICT_FIRST:-1}" != 0 ] && [ -n "$_or_tp" ] && [ -f "$_or_tp" ]; then
  _cvlib="$SCRIPT_DIR/lib/close-shape.sh"
  [ -f "$_cvlib" ] || { _cvt="$0"; [ -L "$_cvt" ] && _cvt="$(readlink "$_cvt")"
    _cvlib="$(cd "$(dirname "$_cvt")" 2>/dev/null && pwd)/lib/close-shape.sh"; }
  [ -f "$_cvlib" ] || _cvlib="$HOME/.claude/hooks/lib/close-shape.sh"
  # shellcheck source=lib/close-shape.sh
  # shellcheck disable=SC1091
  if [ -f "$_cvlib" ] && . "$_cvlib" 2>/dev/null && command -v close_verdict_polarity >/dev/null 2>&1; then
    _cvmsg="$(tail -c 524288 "$_or_tp" 2>/dev/null \
      | jq -cR 'fromjson? | select(.type=="assistant" and (.isSidechain != true))
                | ([.message.content[]? | select(.type=="text") | .text] | join("\n")) | select(. != "")' 2>/dev/null \
      | tail -1 | jq -r '. // empty' 2>/dev/null || true)"
    if [ -n "$_cvmsg" ] && [ "$(close_verdict_polarity "$_cvmsg")" = no ]; then OR_VERDICT_NO=1; fi
  fi
fi
~~~

Then add `&& [ "${OR_VERDICT_NO:-0}" != 1 ]` in three places:
1. the SAFE TO CLOSE condition at `:1137`, which then falls back to the existing `✅ live on trunk`;
2. the answer-first header reorder at `:1294`;
3. after `:1841`, as a new line: `[ "${OR_VERDICT_NO:-0}" = 1 ] && abstain "cert-verdict-no"`.

No function or variable name collides with the lib (checked with grep).

### 2.4 Doc passages, old → new

**Δ1** (from the design): wherever a slot-docs **C** draft says `<rung glyph> Good to close: yes` or "the rung glyph on a yes", write `✅ Good to close: yes` or "✅ on a yes". The OLD strings are slot-docs §4 verbatim; `/tmp/cvf-docs/tools/apply.py` verified each occurs once.

**`CLAUDE.rules.slim.10-session-close.md`** (deployed to `~/.claude/rules/10-session-close.md`):
- The complete final file is `/tmp/cvf-report/rules.final.md`.
- Loader units go from 30,334 to **30,334 (+0)**, measured by `python3 -I /tmp/cvf-report/rules_final.py` with `instruction_budget.parse`. The user tier is already in breach, so net ≤ 0 is required, and +0 meets it.
- All 6 strings pinned by `research-program-exemption-rules.bats` still match once, and so does the `priority … ⛔` ladder line.

The new lines, with each line number followed by its full new text:

~~~text
:8   - Close certificate: on a write turn whose ledger is ✅, `operator-readout.sh` prints `✅ SAFE TO CLOSE — nothing of mine is open`, computed from git. Read-only turns, unverifiable states and a close answering no get none.
:9   - **A ✅ rung is an assertion, not a vibe.** Claim it only with: clean tree · landed on trunk,
:22  - Origin close contract (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing ✅ or 👤 after written work this session leads with the verdict: line 1 `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or `❌ Good to close: no — <what remains + who owns it>`, line 2 the ledger's rung glyph (`line-1-rung`). A no under a ✅ or done-reading line 1 fails (`verdict-first`); naming what remains is no hedge, a both-ways answer is (D3). Assignees and fired peers are exempt; their close is the lead's harvest or the notify-back ping.
:96  (O2) delete the trailing sentence " A new deployed top-level directory is audited by `scripts/deploy-parity-assert.sh`, not the ledger." (CLAUDE.global.md:741 keeps it)
:129 ### The six slots, verdict first
:135 | S2 VERDICT, line 1 | `✅ Good to close: yes — …` or `❌ Good to close: no — …`, with the follow-on ledger | terminal close (`✅`/`👤`) after real written work |
:136 | S1 STATE, line 2 (1 if no S2) | the ledger's rung glyph and state clause, relayed, plus one clause naming what the work was | always |
:142 S1–S3 are the lines the operator scans; S4–S6 are at most three supporting lines. The act marker must fall within the first 3 non-blank, unfenced lines (`CC_ACT_WINDOW`=3), which is why verdict and state hold lines 1–2.
:146 The S1 line carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`). Neither it nor the verdict hedges, and nothing later withdraws either. If something is parked or is theirs, that is the rung (`📦` / `👤`); if it is immaterial, it stays out. A qualification goes in S2's `follow-on:` clause, beside the assertion.
:148 S2. The `Good to close:` line, in a form given under Origin close contract, first and never last. The rung does not imply it, and a rendered `✅ SAFE TO CLOSE` certificate neither replaces nor overrules it; an honest no satisfies the contract. `Complication:` / `Solution:` / `Outcome:` lines are optional.
~~~

**`CLAUDE.global.md`** (deployed to `~/.claude/CLAUDE.full.md`; not budgeted):
- **G2 to G6:** the C drafts with Δ1.
- **G7:** the C draft, ending "Hence the verdict owns line 1 and its glyph: ✅ on a yes, ❌ on a no."
- **G0 (`:519-521`):** append to the OLD text: "It reads git, never the task, so it is withheld under a close whose own verdict is `no` (`cert-verdict-no`), and the close's verdict line leads either way."
- **G8 (new, `:831`):** `- **✅ is a safe-to-close assertion, not a vibe.**` becomes `- **A ✅ rung is an assertion, not a vibe.**`
- **G1 (`:546-551`)**, new text:

~~~text
  closing genuine completion (✅/👤) after real written work this session must answer, mechanically
  matched, **two** things, **verdict first**: line 1 is the verdict, led by its own glyph —
  `✅ Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>` or
  `❌ Good to close: no — <what remains + who owns it>` — and line 2 relays the ledger's own
  **rung glyph** and state clause (`line-1-rung` accepts the glyph there). An honest no satisfies
  (the contract is that the question is ANSWERED; hedging stays D3's defect, and naming what
  remains is not a hedge). A no under a line 1 that opens with a done reading (✅, complete, done,
  nothing to do, safe to close, 👤 My side is done) is refused (`verdict-first`; kill switch
  `CC_VERDICT_FIRST=0`). § The close message S2 carries the measurement.
  🚨 **`Complication:` / `Solution:` /
~~~

**`commands/wrap.md`:**
- **W1 to W3:** the C drafts.
- **W4 (`:174-175`)**, new text: "Line 1 is the verdict, led by its own glyph: ✅ on a yes, ❌ on a no; leave one blank line under it. Line 2 is the rung readout's glyph and state clause, verbatim, with your own clause in place of its tail. An honest `❌ Good to close: no — <what remains + who owns it>` satisfies the contract; naming what remains is not a hedge, a both-ways answer is (D3)."

**Other files:**
- **`commands/are-we-done.md`** (`Scope (grown):`): A1 (the C draft with Δ1) and A2.
- **`hooks/lib/why-tier.sh`:** Y1 and Y3 as drafted. Y2 is items 1 and 2 of the C draft with Δ1, followed by the design's paragraph without numbers ("VERDICT FIRST, NEVER LAST. The rung does not decide the verdict — … refused as `verdict-first`."). Keep the `HEDGE —` prefix.
- **`docs/plans/STOPHOOK_MESSAGE_TIERING.md:552`:** T1, the C draft.

**Not edited:**
- `CLAUDE.global.slim.md`: grep finds no close-placement text in it. For the slim variant, the close rule *is* the rules file.
- `install.sh`, `core/`, `scripts/wrap-ledger.sh` (deferred to F2), `anti-deference-nudge.sh` (it reads the whole message), and the five literal-matching parsers.
- `scripts/limit-recover/lr_recon/**` and `settings.json`.

### 2.5 Switches, team, gate

**Switches:**
- `CC_VERDICT_FIRST=0` turns off every new FAIL and the certificate withholding: the `verdict-first` token, the D3 conditional-yes branch and `OR_VERDICT_NO`.
- `COMPLETION_VERDICT_MAX` (default 2) caps the new class.
- `CC_CLOSE_SHAPE=0` still disables D6 outright.

**Team** (each owns 5 files or fewer):
- **hooks-impl:** close-shape.sh, completion-assert.sh, operator-readout.sh, `tests/completion-assert.bats` with its fixtures, and `tests/operator-readout-research.bats`.
- **docs-impl:** the rules file, CLAUDE.global.md, wrap.md, are-we-done.md and why-tier.sh.
- **Lead:** the one-line STOPHOOK row.

**Land gate:**
1. bare `shellcheck` on the touched shell files;
2. `scripts/bash32-parse-lint.sh`;
3. `scripts/pipefail-sigpipe-lint.sh` (completion-assert must stay at 5);
4. `bin/cc-instruction-budget measure` on the rules file (≤ 30,334);
5. `bats tests/completion-assert.bats tests/operator-readout-research.bats tests/self-certifying-close.bats tests/why-tier.bats tests/research-program-exemption-rules.bats tests/wrap-ledger.bats`, asserting the `1..N` plan line and the ok count.

**Plan W3 correction:** grep the deployed `~/.claude/rules/10-session-close.md` and `~/.claude/CLAUDE.full.md`. `~/.claude/CLAUDE.md` carries no close rule.

## 3. Tests

**Fixtures.** `tests/fixtures/close-verdict-first/left.txt` and `right.txt` are byte copies of `/tmp/cvf-hooks/{left,right}.txt`.
- LEFT was extracted with jq from transcript `44091255-b12e-41c4-8aaa-0d4ddf21c6ec` at 16:15:41.992Z. sha256 `510e9145359d0df3c9a437f9696d6311f636bf4de4834ebfd67fd938a0e25aab`.
- RIGHT was extracted from `3bd7aa3b-…` at 16:15:38.550Z. sha256 `4f56250e485f9551959956dabc841561a24c60abddf03276e680a0877670625d`.

`left.txt`, verbatim:
~~~text
✅ Complete & live on trunk — nothing to do. The reconciler is now in act mode, cut over this session.
Good to close: no — the FLEET_V2 programme still has two open steps, and pane 182 will mail this pane before it lands its change to the reconciler. If this pane closes, that mail goes nowhere.

What's still open, and who has it:
- **First live act-mode recovery:** it waits for an account to hit a limit after pane 182's fix lands. Then you or I run `cc-lr recover --limited` and watch it.
- **Pane 182's reconciler change:** I review the actual commit before it lands. That's mine.
- **After the first recovery closes clean:** you create the reconciler's zero-human switch (backlog be52a4c8a99f), and I unblock the two parked reconciler fixes. One is re-landing the early pane fix (backlog 005dd549c80f). The other, just filed, is the slow census scan that freezes under heavy load (backlog 457c166ed9d6).

Nothing is uncommitted and nothing is waiting to land. If you want this pane back, I can recycle it in place, and the successor will pick up from the decision log and the brief. The leftover hold worktree (`fix/lr-recon-hold-daa386b23`) is fully landed and can be cleaned up whenever.
~~~

`right.txt`, verbatim:
~~~text
✅ Yes, it's safe to close. This session has no open work.

Good to close: yes. Nothing of mine is open. Follow-on: none new.

- **Live ledger:** the worktree is clean, nothing is waiting to land, nothing is out with another session, and nothing filed is mine to finish.
- **Fresh test set item (1dcc10d88ee3):** this is the step to seal a fresh held-out test set, v5. A dispatcher grabbed it yesterday, even though it's waiting on more data. A later session parked it again with a count: 46 of the 400 needed unused regex-missed candidates exist so far. It's still waiting on that data and closes itself when the sealed set exists.
- **TrueMemory contract item (01e7de9219c0):** re-signing the TrueMemory 2.0 pilot contract stays blocked until the gate passes. You have nothing to do yet.

I restarted the peer-mail watcher, because the old one had expired.
~~~

`left-aprime.txt` is `/tmp/cvf-design/v/leftA.txt`:
- line 1 `❌ Good to close: no — the FLEET_V2 programme still has two open steps, …`;
- a blank line;
- `✅ Complete & live on trunk — the reconciler is in act mode, cut over this session.`;
- then LEFT's body.

**Conventions:**
- Load fixtures from files, never from heredocs inside `$( )`, which bash 3.2 lexes wrongly.
- Write negations as `if …; then false; fi`.
- Helper `_cvf <tag> <text> [rung]`: built from `mkledger`, `_d6_tr` and `run_ca`, it runs the hook as an origin session with one write.
- For 👤 cases, set `CC_BACKLOG_STUB_JSON` to a filed row.

| # | Case | Assert |
|---|---|---|
| T1 | **LEFT, verbatim** | fired; reason has `verdict-first`; IDL has `"arm":"shape"` and `"class":"verdict"` |
| T1b | Same session id: two shape-missing closes first (shape 2/2), then LEFT | fired; `"class":"verdict"` |
| T1c | `COMPLETION_VERDICT_MAX=1`: LEFT, then wrong-glyph | the second gives `capped:verdict:1>=1` |
| T2 | **RIGHT, verbatim** | not fired; IDL `ledger-clean` |
| T3 | `left-aprime` | not fired |
| T4 | `❌ Good to close: no — <r>.` / blank / `✅ Complete & live on trunk — x.`, for r = still open, remain…, pending…, yours to approve, but pane 182 lands first | no `hedge` in the IDL for any r |
| T5 | `✅ Good to close: yes, once pane 182's change lands.` | fired; `"arm":"hedge"` |
| T5b | `✅ Good to close: yes — with one thing still parked.` | fired; hedge |
| T5c | T5 with `CC_VERDICT_FIRST=0` | not fired |
| T6 | A′ yes with a parked follow-on; "nothing of mine is still open" | no hedge |
| T6b | Must not fire: F3 `…yes — with the reconciler in act mode…`, F13 `…yes — after this push…`, F14 `…the pane that was not good to close at noon is fixed…` | not fired |
| T7 | 👤 A′ yes "…the two steps below are yours" + ▶ on line 3 | not fired |
| T8 | 👤 A′ no + ▶ on line 3; CONTROL: one extra line before ▶ | not fired; CONTROL fired with `"arm":"act"` |
| T9 | `✅ Good to close: no — …` | fired; `verdict-first` |
| T10 | RUNG ⛔, line 1 `Good to close: no — the keep-or-retire call … is open with you.`, no CLOSE token | not fired; `no-close-tell` |
| T11, T12, T13 | LEFT from a fired peer, from a confirmed assignee, from a write-free session | no `verdict-first`; no `verdict-first`; no `Origin-session close contract` |
| T14 | Mixed polarity: a yes that quotes `"Good to close: no"` | no `verdict-first` |
| T15 | LEFT with `CC_VERDICT_FIRST=0`; LEFT with `CC_CLOSE_SHAPE=0` | not fired |
| T16 | Old-shape yes | not fired |
| T17 | **Flipped from the design:** `👤 My side is done & landed — 2 steps need you.` / `Good to close: no — …` / ▶ | fired; `verdict-first`; class `verdict` |
| T17b | `👤 Waiting on you: …` / `Good to close: no — …` | no `verdict-first` |
| T18 | C-style `❌ Good to close: no — … · ledger: ✅ Complete & live on trunk` | not fired |
| T19 | `The cutover landed.` / `✅ Complete…` / `Good to close: yes — …` | fired; `line-1-rung` (the window is not widened) |
| T20 | UNIT polarity | left→no · right→yes · left-aprime→no · template→none · fenced verdict→none · `Are we good to close? No —`→no · `❌ Not good to close`→no · `So it isn't good to close yet`→no · `Good to close: no loose ends…`→none · F1→yes · F10→yes · `nope`→none · `Good to close (no)`→none |
| T21 | UNIT `close_line_reads_done` | **Done:** `✅ Complete…`, `**✅ Complete**`, `✅️…`, `Done and landed.`, `Nothing left to do here.`, `Yes, it's safe to close.`, `👤 My side is done & landed —`, `👤 **My side is done**`. **Not done:** `❌ Good to close: no`, `Good to close: no`, `Yes, it's included.`, `📦 Done, but only on a branch`, `👤 Waiting on you:`, `👤 Wave 3 is finished…`, `Complete? No —`, `Safe to close: no —`, `Done? Not yet —`, `Completeness check: …` |
| T22 | UNIT template | `close_shape_ok` rc ≠ 0; missing = `good-to-close-verdict`; polarity = `none`; no `▶` |
| T23 | UNIT reason | `close_shape_reason ✅ verdict-first` contains `A missing verdict-first`; `… line-1-rung` does not; neither contains `613` or `73%` |
| T24 | AGREEMENT: `CA_VERDICT_NO` (lifted by its `^CA_VERDICT_NO=` line) matches ⇔ polarity is `no` | See the row list below this table |
| T25 | T1 and T20 under `LC_ALL=C` | identical output (measured: the md5 of the `unit.sh` output is the same in both locales) |
| T26 | `Done and landed.` / `Good to close: no — …` | fired; contains `verdict-first` |
| T27 | `tests/operator-readout-research.bats`: its mkrepo, DoD and write-turn harness, with a variant of `mktr` that sets the final text | LEFT text → no `SAFE TO CLOSE`, IDL `cert-verdict-no`; RIGHT text → renders; LEFT with `CC_VERDICT_FIRST=0` → renders (all measured by `cert.sh`). Also add a block-state case shaped like `self-certifying-close.bats` A, with LEFT text: the head line has no `SAFE TO CLOSE` (not replayed; see risk R8) |

**T24 rows** (measured with `/usr/bin/grep -iE` against the awk polarity function):
- **14 rows agree:** 9 no forms (`no —`, `❌ … no —`, `— no.`, `**no**`, `? No —`, `not yet`, `❌ Not good to close`, `isn't good to close yet`, upper-case `NO`), plus `yes — nothing…`, `yes — no follow-on`, `no loose ends`, the template, and `nope`.
- **2 divergences are pinned:** `Good to close (no)` (grep matches, awk gives none) and `yes — … not good to close …` (grep matches, awk gives yes). Both affect only the gate, and only in the abstain direction.

**Must stay green unchanged:**
- completion-assert bats: D3 `:491`, `:501`, `:512`, `:519`; D6 `:1272-1325`; close-shape `:1657`, `:1666`, `:1677`; CAP SPLIT `:1698`, `:1717`; D7 `:1758-1936`.
- Other suites: `why-tier.bats` (`HEDGE —`), `research-program-exemption-rules.bats`, the ladder parity tests in `wrap-ledger.bats`, `cc-pane-close.bats`, `lead-crash-pane-verdict.bats`, and test A in `self-certifying-close.bats`.

No existing completion-assert or operator-readout fixture carries a no verdict (grep), so neither the new token nor the certificate withholding can fire on them.

## 4. Corpus numbers, re-derived, and the 613 decision

Window: the 30 days to 2026-10-10T17:32Z, across five account roots, deduplicated by realpath, main chain only.

| Figure (all closes) | Value | Command |
|---|---|---|
| Verdict closes (`good to close:` with a value) | **5,013** (yes 1,719 · no 3,290 · other 4), from 4,982 transcripts | `measure.py` |
| No closes whose line 1 leads with ✅ (the screenshot defect) | **264 / 3,290 (8.0%)** | `measure.py` |
| ✅-led closes that answer no | **264 / 1,308 (20.2%)** | `measure.py` |
| Rung predicts verdict (line-1 glyph) | **3,337 / 4,001 (83.4%)**; no rung glyph on line 1: 1,008 / 5,009 (20.1%) | `measure.py` |
| Verdict position 1 / 2 / 3 / 4+ | 32 / **4,050 (80.8%)** / 385 / 546 (10.9%); at line ≤3: 4,467 (89.1%); last line: 645 (12.9%) | `measure.py` |
| Closes with the anchor anywhere (the hook's population, as a proxy) | 5,283 of 22,446 closes; polarity yes 1,814 · no 3,452 · none 17 · mixed 0 | `extract.py` + `final_scan.py` |
| **`verdict-first` refusals** (proxy: rung taken from the line-1 glyph; not D6-gated) | **425** = 294 ✅-led + 129 "👤 My side is done…" + 2 "Done and landed." That is 12.3% of no closes, and **0 yes closes** | `final_scan.py` |
| The same, with the skeptic's glyph-only 👤 rule | 562 (266 of them 👤-led) | an earlier `final_scan.py` revision |
| Sessions behind the 425 | 116, of which 47 have 3 or more. With a cap of 2, at most 184 blocks fire (estimate: 425 minus 241 beyond the cap) | `final_scan.py` follow-up |
| D3 (final) on verdict lines replayed as line 1 | no lines: **0 / 3,456**; yes lines: **9 / 1,829**, all conditionals; `with one thing` adds 0 | `final_scan.py` |
| Honest no closes with no CLOSE token that newly abstain at the gate | **6 / 5,283** | `final_scan.py` |
| Python port vs the real bash functions | **725 / 725 agree** (all 425 refusals plus 300 random), under both UTF-8 and `LC_ALL=C` | `val_run.sh` |

**The 613 decision.** The 2026-08-23 figures are stale in both directions: "verdict on the last line" went from 90.7% to 12.9%, and "verdict at line ≤3" went from 1.1% to 89.1%. Their committed instrument never reproduced them. The decisions:

1. The block reason carries no numbers, only the mechanism (§2.1, K5).
2. The header at `:44-49` gets a dated rationale with three points:
   - position is not what misleads the operator;
   - the verdict already sits at line 2 in 80.8% of closes;
   - 264 of 1,308 ✅-led closes answer no.

   It names the instrument: `slot-corpus.md` §5, committed with this directory, sha256 `c526422b…66dee3`. It sends readers looking for the August figures to `close-shape-2026-08-23.md § R4`.
3. Lines `:60-62` get the re-dated 83.4%, 264/1,308 and 20.1%, and the pointer `§ M3` becomes `§ R4`.
4. The `:71` sentence "0 of the 613" stays, prefixed "(2026-08-23)", as history.
5. why-tier Y2 drops every number.
6. `CC_VERDICT_WINDOW` stays 0. A window of 3 would fail the 10.9% of closes whose verdict sits at line 4 or later, and whether those closes are honest is unmeasured.

## 5. Evidence receipts (scratch, in `/tmp/cvf-report/`)

1. **Verdict census:** `python3 -I measure.py --days 30 --json rows.json`, run at 2026-10-10T17:32Z. Output in `measure.out`.
2. **Anchored-close census:** `python3 -I extract.py 30 anch30.jsonl`, which reuses `measure-closes.py`'s `extract_closes` and adds `~/.claude-next4`. Then `python3 -I final_scan.py anch30.jsonl scan30.jsonl`.
3. **Hook replays:** `bash runall.sh` runs the real hook, HEAD against the final version, 41 cases each, with hermetic stubs (an origin pane, one Edit, a stub ledger and a stub backlog). Output in `runall.out`.
4. **Lib unit probes:** `bash unit.sh` and `bash unit-repo.sh`, 33 probes each. The prototype lib and the patched tree give identical output, and the output is the same under `LC_ALL=C`.
5. **Hook timing:** `bash timing.sh`, 7 runs per cell, at a load of about 200 on 10 cores, harness overhead included. A refusal costs about 140 ms more; a passing close costs nothing measurable.

   | Fixture | HEAD median | Final median |
   |---|---|---|
   | LEFT | 737 ms | 874 ms (blocks) |
   | `left-aprime` | 1,033 ms (blocks) | 826 ms |
   | RIGHT | 620 ms | 606 ms |
6. **Certificate replay:** `bash cert.sh`, on operator-readout's standalone certificate path.
   - HEAD prints SAFE TO CLOSE under LEFT.
   - The final version abstains with `cert-verdict-no` under LEFT, renders under RIGHT and under "ok", and renders under LEFT when `CC_VERDICT_FIRST=0`.
   - Reading the verdict takes 35 ms on the real 2.3 MB LEFT transcript, cut at 16:15:53Z.
7. **Rules budget:** `python3 -I rules_final.py` reports +0 loader units.

## 6. Residual risks

| # | Risk | Detail |
|---|---|---|
| R1 | **The hook fails open on about one Stop run in five** | Skeptic-intent measured `completion-assert` timing out on 1,811 of 9,877 runs over 14 days, and the screenshot close itself was `hook_cancelled`. A block also renders under the misleading close, not in place of it. So the rules text and the template carry the change, and the hook is the backstop. The `verdict` class closes the cap hole, not the timeouts |
| R2 | Transitional blocks | Proxy upper bound: 425 refusal-shaped closes in 30 days, at most 184 blocks after the cap. The D6-gated rate is unmeasured. Each block costs one re-close |
| R3 | New FAIL class | A conditional yes on verdict line 1: 9 of 1,829 yes lines in the proxy. D3 has no origin or peer gate, so it also reaches peers and assignees who lead with a verdict. `CC_VERDICT_FIRST=0` silences it |
| R4 | False PASSes, accepted | <ul><li>`❌ … no — but honestly it is fine to close`</li><li>a no without a glyph</li><li>a no under a 👤 line 1 that does not read as done</li><li>openers such as `1. ✅`, `• ✅`, 🎉, ✔️, `Ledger: ✅`, "All landed.", "Shipped."; `line-1-rung` refuses these only where it applies</li><li>forms the polarity reads as none: `nope`, `(no)`, a table cell, a value on the next line</li><li>a fired peer that `oi_origin_class` cannot prove to be a peer (it then counts as origin and inherits the demand)</li></ul> |
| R5 | Gate abstain | 6 of 5,283 honest no closes with no CLOSE token now skip D1 to D7 |
| R6 | ❌ may push models toward dishonest yeses | Falsifier: the yes:no ratio, 1,719 : 3,290 today. Re-run `measure.py` 14 days after deploy |
| R7 | Research relay arm | Under A′, a no reply inside a certifying or certified research program opens "no", so `router.py` `relay_violations` requires it to cite an escape, a freshness flip or an accepted change. That is the arm's own rule. The population is narrow, and the arm is not changed |
| R8 | Ledger wording and certificate block path | Line 2 still reads "✅ Complete … nothing to do" under a ❌ until F2. The certificate's block-state path is specified but was not replayed; only the standalone path was |
| R9 | Not verified | The bats suites: cc-bats returned rc 75 under load, and its waiver writes under `~/.claude`, which this run may not touch. The claim that the TUI renders a single newline as one paragraph is inferred from one screenshot. The implementer must run the §2.5 gate |
| R10 | Budget edge | The rules file sits at exactly +0 loader units, so any later addition needs an offset |

## 7. Follow-ons (file as rows; none blocks this land)

- **F2, wrap-ledger wording.**
  - Make the ✅ READOUT git-only at `:2277` and `:2432-2441`.
  - Update the ladder at `CLAUDE.global.md:704`.
  - Add a test that the default ✅ READOUT never matches `complete|nothing to do|safe to close`.
- **F3, `SCOPE=met` needs evidence.** Add a new value `unchecked`, accepted by `scope_of` in the same commit.
- **F4, instruments.**
  - Promote `measure.py` and `final_scan.py` into `scripts/`.
  - Add `~/.claude-next4` to the `measure-closes.py` ROOTS.
  - Make `rung_of` skip a line 1 that carries the verdict anchor.
  - At 14 days, count no lines without a glyph and 👤-led no lines that do not read as done.
- **Side finding:** a cold `cc-backlog list` takes 6 to 13 s against wrap-ledger's 5 s timeout, after which 👤 falls through to ✅ (slot-ledger §7).

**Record in the plan as `Scope (grown):`** `hooks/operator-readout.sh` and its test, `commands/are-we-done.md`, `hooks/lib/why-tier.sh`, and the STOPHOOK table row.

---

**Delivery note.** `REPORT.md` was **not written**. The Write tool refused it with "Subagents should return findings as text, not write report files", and I did not work around that refusal, so the full text above is the deliverable. The caller should save it unchanged as `/Users/chrisren/Development/.worktrees/close-verdict-first/docs/research/close-verdict-first-2026-10-10/REPORT.md`. No tracked file was changed and no git write was run. The scratch artifacts the report cites are in `/tmp/cvf-report/` and `/tmp/cvf-report-proto.wT0neA/`; `/tmp` may be cleaned.

Saved unchanged by the lead from the workflow result on 2026-10-10 (commit af48c4a7f).
