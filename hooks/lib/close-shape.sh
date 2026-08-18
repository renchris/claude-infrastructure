#!/usr/bin/env bash
# hooks/lib/close-shape.sh — the ORIGIN-SESSION Pyramid close contract, in ONE place
# (CLOSE_INTEGRITY W1; operator /goal 2026-08-09).
#
# THE CONTRACT. When an ORIGIN session (operator-started — no originator to hand back to) finishes
# real written work and its ledger reads terminal (✅/👤), its close must answer the operator's two
# standing questions IN THE MESSAGE ITSELF:
#   1. "In Pyramid Principles, minimally and concisely put: what was our complication, our
#      solution, and our outcome?"  → three labeled one-liners: Complication: / Solution: / Outcome:
#   2. "Are we good to close now — all work complete, durable, deployed live, no loose ends or
#      follow-on work?"             → an explicit 'Good to close: yes — …' / 'Good to close: no — …'
#      (an honest NO satisfies the contract — the requirement is that the question is ANSWERED;
#      hedged both-ways answers are already policed by completion-assert D3 / anti-deference).
#
# WHY A LIB AND NOT PROSE IN TWO PLACES (final-response-shaping M4; live precedent
# commands/wrap.md): the same contract is PUSHED (completion-assert D6 blocks a shape-missing
# close) and PULLED (/wrap renders the template for the model to fill). Two copies of a
# load-bearing matcher rot apart invisibly (MEMORY.md uniform-error-ratio-indicts-the-model);
# this lib is the one code path, and scripts/wrap-ledger.sh keeps sole ownership of line 1.
#
# MATCHER CALIBRATION. Label-anchored and case-insensitive: the three labels may sit after list
# markers/bold ('**Complication:**', '- solution:') — the anchor tolerates a non-letter prefix and
# requires the colon, so prose merely CONTAINING the word ("the complication was…") does not
# satisfy it, and a paraphrase does not either. Deliberately deterministic — a Stop hook judges
# shape, never quality; quality stays with the model (prompt-for-form, hook-for-floor).
#
# MENTION vs USE (item 3b464e94b3ff, 2026-08-17). The anchors above matched the message ANYWHERE,
# and close_shape_template() emits lines that contain them — so a close that merely QUOTED the
# template (printed the skeleton, echoed /wrap's block, pasted D6's own block-reason back) matched
# all four anchors and PASSED without answering one of them. The template was its own bypass.
# THE DISCRIMINATOR IS THE VALUE, NOT THE LABEL: a label occurrence counts only when what follows
# its colon is not merely a bare <angle-bracket placeholder> (`^<…>$` after trimming). The fix is
# deliberately the SMALLEST one that can only move PASS→FAIL for the quoting case, because the
# defect is false-PASS-only and a false FAIL on an honest close is strictly worse:
#   · an EMPTY value still counts as answered — "Complication:" with the answer on the next line
#     passed before and passes now (narrowing that would be a new false-FAIL class, not a fix);
#   · the placeholder test is anchored at THE LABEL's own value, not at the end of the line, so
#     `Good to close: yes — …; follow-on: <none>` — a genuine close using the template's own
#     follow-on notation — is unaffected (the value starts with 'y', not '<');
#   · ANY occurrence answering is enough, so a close that quotes the template AND answers passes.
# One awk pass rather than four greps: the value test needs the text AFTER the anchor match, which
# grep -q cannot hand back.
#
# Env seam (tests): none needed — pure functions over $1.
# shellcheck shell=bash

_CS_COMPLICATION='(^|[^[:alpha:]])complication[[:space:]]*:'
_CS_SOLUTION='(^|[^[:alpha:]])solution[[:space:]]*:'
_CS_OUTCOME='(^|[^[:alpha:]])outcome[[:space:]]*:'
_CS_VERDICT='(good|safe)[[:space:]]+to[[:space:]]+close'

# close_shape_missing <msg> → prints the space-joined missing elements ('' when complete)
close_shape_missing() {
  printf '%s' "${1:-}" | awk -v c="$_CS_COMPLICATION" -v s="$_CS_SOLUTION" \
                             -v o="$_CS_OUTCOME"      -v v="$_CS_VERDICT" '
    # real(<lowercased line>, <anchor>) → 1 iff the anchor matches AND its value is an answer
    # rather than the template placeholder it was copied from (MENTION vs USE, above).
    function real(l, re,   rest) {
      if (!match(l, re)) return 0
      rest = substr(l, RSTART + RLENGTH)
      sub(/^[[:space:]]*:?[[:space:]]*/, "", rest)   # the verdict anchor stops before its colon
      sub(/[[:space:]]+$/, "", rest)
      return (rest ~ /^<.*>$/) ? 0 : 1
    }
    { l = tolower($0)
      if (real(l, c)) C = 1
      if (real(l, s)) S = 1
      if (real(l, o)) O = 1
      if (real(l, v)) V = 1 }
    END { m = ""
      if (!C) m = m "Complication: "
      if (!S) m = m "Solution: "
      if (!O) m = m "Outcome: "
      if (!V) m = m "good-to-close-verdict "
      sub(/ $/, "", m)
      printf "%s", m }'
}

# close_shape_ok <msg> → rc 0 iff all four elements are present
close_shape_ok() {
  [ -z "$(close_shape_missing "${1:-}")" ]
}

# close_shape_template → the fill-in skeleton, shared by push (D6 reason) and pull (/wrap)
close_shape_template() {
  cat <<'TPL'
<line 1 = the ledger rung readout, verbatim from wrap-ledger — never restated from memory>
Complication: <what made this work necessary — one line>
Solution: <what was built/changed, with the landed sha — one line>
Outcome: <what is now true that was not before — one line>
Good to close: <yes — complete, durable, deployed live, no loose ends; follow-on: <filed ids|none> | no — <what remains + who owns it>>
TPL
}

# close_shape_reason <rung> <missing> → the D6 block-reason sentence group (one paragraph; does
# NOT restate D1/D3/D4's correctives — recon report-seams §6 G3: four overlapping correctives from
# one chain teach the model nothing).
close_shape_reason() {
  local rung="${1:-?}" missing="${2:-}"
  printf 'Origin-session close contract: this session wrote real work and the ledger reads %s, but the close is missing [%s]. End with the operator'\''s two answers, in this exact shape (labels are matched mechanically):\n%s' \
    "$rung" "${missing:-the required close shape}" "$(close_shape_template)"
}
