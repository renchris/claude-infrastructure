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

# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE ACT LINE — CLOSE_SCANNABILITY W2 (measured 2026-08-23)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE CONTRACT. When the operator must DO something, exactly one line IS that act, near the top,
# and it is that line alone — not a sentence the act is welded into, and not three bullets.
#
# WHY THIS IS A DIFFERENT DEMAND FROM THE ONE ABOVE. The origin contract asks whether the close
# ANSWERS the operator's two standing questions. This asks whether the operator can FIND the thing
# to do without synthesising several lines. The evidence they are independent: the close that
# provoked this had a correct ⛔ rung, had the blocker in its supporting lines, and still drew
# "Whats blocked on me? Be explicit" — nothing was missing, nothing was hedged, and it was still
# unscannable.
#
# THE MEASUREMENT THAT SET EVERY PARAMETER HERE — docs/research/close-scannability-2026-08-23.md,
# 300 rung-carrying closes over 1,373 transcripts / 14 days / all four account roots:
#   · 63.3% of closes require an operator act; ONE of 190 states it at line 1; median line 6;
#     54.7% never state it as its own line at all.
#   · Outcome (whether the operator then ACTED, evidenced by a `<bash-input>` record): act on its
#     own line 35.4%, act not on its own line 9.4% — p=2.7e-05 (Fisher), measured WITHIN the 185
#     closes that all contain a command, so runnability is held fixed and position is doing the
#     work. Control: closes needing no act draw an ACTED reply 1.9%, so the signal is real.
#   · The cliff is is-a-line vs is-not-a-line. Lines 1-3 / 4-6 / 7+ are flat within noise, so this
#     matcher demands a WINDOW, not line 1. Line 1 is already owned by the rung; making the two
#     fight for one row would buy nothing measurable.
#   · The worst sub-case is the act welded INTO line 1 (ACTED 4.2%) — worse than a close with no
#     act verb at all. Being early is not the property that matters; being a line is.
#
# THE MARKER IS `▶`, AND IT WAS NOT INVENTED HERE (R7). The corpus already uses it for acts that
# are not commands — 81 occurrences, 19 distinct labels: `▶ Run this:` (40), `▶ Open this:` (6),
# `▶ Look here:` (6), `▶ Test it here:`, `▶ Reopen and tap:`, `▶ Reply with this to unblock it:`.
# So the plan's D3 — "a physical act has no canonical form" — is answered by what is already there
# rather than by a new glyph, and the 2026-08-01 screenshot-verified span form is reused byte for
# byte. NOTHING HERE IS A RENDERING CLAIM: this work measured position behaviourally (did the
# operator act), never colour or contrast. The fence regression is the standing reminder of what an
# unmeasured rendering claim costs.
#
# `ACT:` IS THE SECOND LEGAL SHAPE, for the 2.6% of act-required closes that contain no command at
# all — a physical/GUI sequence where a `▶` + inline span would be a lie, because there is nothing
# to paste. Label-anchored exactly like the four above, with the same placeholder guard.
#
# FENCED LINES ARE SKIPPED, AND DO NOT COUNT TOWARD THE WINDOW. Both halves are load-bearing:
#   · SKIPPED, or the matcher is bypassable — 13 of the 81 `▶` occurrences are the
#     ` ▶ cc-do   [N runnable]` row INSIDE the rendered `OPERATOR ▸` block, which sits fenced at the
#     top of a close as a verbatim paste. A naive matcher passes on that row at line 3 while the
#     close's real act is at line 11 (observed twice in the sample).
#   · UNCOUNTED, or compliance is impossible for the closes that do the right thing — that block is
#     ~8 lines and the Silver-Platter rule requires reproducing it verbatim, so counting it would
#     push every relaying close past any sane window.
#
# Env seam (tests): CC_ACT_WINDOW (default 3 — rung, one slack line, the act).
_CS_ACT_LABEL='^[^[:alnum:]]*act[[:space:]]*:'
_CS_ACT_MARKER='▶'

# close_act_missing <msg> [window] → prints 'act-line' when no act line is present, '' when one is
close_act_missing() {
  printf '%s' "${1:-}" | awk -v w="${2:-${CC_ACT_WINDOW:-3}}" -v lab="$_CS_ACT_LABEL" \
                             -v mk="$_CS_ACT_MARKER" '
    BEGIN { n = 0; fence = 0; ok = 0
            if (w !~ /^[0-9]+$/ || w+0 < 1) w = 3 }
    {
      line = $0
      if (line ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      t = line
      sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
      if (t == "") next
      n++
      if (n > w + 0) exit
      if (index(t, mk) > 0) { ok = 1; exit }
      l = tolower(t)
      if (match(l, lab)) {
        rest = substr(l, RSTART + RLENGTH)
        sub(/^[[:space:]]*/, "", rest); sub(/[[:space:]]+$/, "", rest)
        # An EMPTY value fails here, unlike the four labels above. There the answer may legitimately
        # sit on the next line; here the whole contract is that ONE line IS the act, so a bare
        # `ACT:` with the act underneath is precisely the shape being ruled out.
        if (rest != "" && rest !~ /^<.*>$/) { ok = 1; exit }
      }
    }
    END { printf "%s", (ok ? "" : "act-line") }'
}

# close_act_ok <msg> [window] → rc 0 iff an act line is present inside the window
close_act_ok() {
  [ -z "$(close_act_missing "${1:-}" "${2:-}")" ]
}

# close_act_template → the two legal shapes, shared by push (D7 reason) and pull (/wrap)
close_act_template() {
  cat <<'TPL'
<line 1 = the ledger rung readout, verbatim from wrap-ledger>
▶ Run this:
`<the one literal command — no placeholders>`
   …or, when the act has nothing to paste (a GUI/physical step):
ACT: <one imperative sentence — the whole act, even if it has sub-steps>
TPL
}

# close_act_reason <rung> <window> → the D7 block-reason sentence group. Deliberately does NOT
# restate D1/D2/D5's correctives (recon report-seams §6 G3: overlapping correctives teach nothing).
close_act_reason() {
  local rung="${1:-👤}" w="${2:-3}"
  printf 'Your close reads %s — the operator has to do something — but no single line IS that act inside the first %s line(s), so they have to read and synthesise to find it. Measured over 300 closes: when the act is its own line the operator acts 35%% of the time; when it is welded into a sentence, 9%%, and an act welded into line 1 is the worst case of all (4%%). Being early is not the property that matters; being a LINE is. Put the act on its own line near the top, in ONE of these two shapes (matched mechanically; fenced blocks are skipped, so relaying the rendered OPERATOR block verbatim neither satisfies this nor counts against it):\n%s' \
    "$rung" "$w" "$(close_act_template)"
}

# close_shape_reason <rung> <missing> → the D6 block-reason sentence group (one paragraph; does
# NOT restate D1/D3/D4's correctives — recon report-seams §6 G3: four overlapping correctives from
# one chain teach the model nothing).
close_shape_reason() {
  local rung="${1:-?}" missing="${2:-}"
  printf 'Origin-session close contract: this session wrote real work and the ledger reads %s, but the close is missing [%s]. End with the operator'\''s two answers, in this exact shape (labels are matched mechanically):\n%s' \
    "$rung" "${missing:-the required close shape}" "$(close_shape_template)"
}
