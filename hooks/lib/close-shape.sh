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
# Env seam (tests): CC_VERDICT_WINDOW (default 0 = position-free — the verdict may sit at any
# non-blank, non-fenced line). It ships OFF on purpose, and that is measured rather than timid:
# only 1.1% of the 613 currently-compliant closes put the verdict at position <=3, so switching
# the window on at the same time as the template move would fail closes that are honest today.
# Move the placement via close_shape_template first, re-measure, THEN set the window. The fence
# skip added below is what makes turning it on possible later at all.
# shellcheck shell=bash

# THE PYRAMID LABELS ARE NO LONGER DEMANDED (CLOSE_SHAPE W3, measured 2026-08-23). Where a close
# has a real body above them they RESTATE it: `Outcome:` carries a novel fact 1 time in 7 and
# `Solution:` 2 in 7, for a median 89 words — against a close budget that was 120. Scored on
# whether the line changes the operator's next action they run 1/30, 0/30 and ~3/30, against
# `Good to close:` at 30/30. Their apparent 80/70/70% novelty was an artifact of the block BEING
# the whole close in a third of cases. Prose that says something the body does not is still
# welcome; a MECHANICAL DEMAND for it is what forced 88 words of restatement into the 71% of
# closes that already had a body. The verdict alone is kept, because it alone is not derivable
# from the rung — over 613 closes the rung predicts it only 73.4% of the time, 48 of 313 `✅`
# closes answer "no", and 17.6% carry no rung glyph at all, making it the only close decision in
# the message. Measurement: docs/research/close-shape-2026-08-23.md § M3.
#
# 'safe' is dropped from the verdict anchor DELIBERATELY, and it is load-bearing rather than
# cosmetic. hooks/operator-readout.sh:1254 renders `✅ SAFE TO CLOSE — nothing is left on this
# side.` at every certified close, and the Silver-Platter rule tells the model to reproduce a
# rendered block VERBATIM. Executed against the pre-W3 lib:
#     close_shape_missing "✅ SAFE TO CLOSE — nothing is left on this side."
#       → "Complication: Solution: Outcome:"     (i.e. the verdict half already PASSED)
# So the moment C/S/O stop being demanded, a close that merely RELAYS the certificate would
# satisfy the whole contract without answering anything. 0 of the 613 currently-compliant closes
# rely on the `safe` alternative.
_CS_VERDICT='good[[:space:]]+to[[:space:]]+close'

# close_shape_missing <msg> → prints the space-joined missing elements ('' when complete)
close_shape_missing() {
  printf '%s' "${1:-}" | awk -v v="$_CS_VERDICT" -v w="${CC_VERDICT_WINDOW:-0}" '
    # real(<lowercased line>, <anchor>) → 1 iff the anchor matches AND its value is an answer
    # rather than the template placeholder it was copied from (MENTION vs USE, above).
    # UNCHANGED byte-for-byte from the four-anchor version — the placeholder guard is still
    # load-bearing, and narrowing to one anchor must not quietly re-open the template bypass.
    function real(l, re,   rest) {
      if (!match(l, re)) return 0
      rest = substr(l, RSTART + RLENGTH)
      sub(/^[[:space:]]*:?[[:space:]]*/, "", rest)   # the verdict anchor stops before its colon
      sub(/[[:space:]]+$/, "", rest)
      return (rest ~ /^<.*>$/) ? 0 : 1
    }
    # FENCED REGIONS ARE SKIPPED — the same rule close_act_missing already applies. A close that
    # relays the rendered OPERATOR ▸ block verbatim (which the Silver-Platter rule REQUIRES) must
    # not thereby satisfy a contract it never answered in its own voice.
    BEGIN { n = 0; fence = 0; if (w !~ /^[0-9]+$/) w = 0 }
    { t = $0
      if (t ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
      if (t == "") next
      n++
      if (real(tolower(t), v)) { if (w + 0 == 0 || n <= w + 0) V = 1 } }
    END { printf "%s", (V ? "" : "good-to-close-verdict") }'
}

# close_shape_ok <msg> → rc 0 iff the close answers "good to close?"
close_shape_ok() {
  [ -z "$(close_shape_missing "${1:-}")" ]
}

# close_shape_template → the fill-in skeleton, shared by push (D6 reason) and pull (/wrap).
#
# 🚨 THE TEMPLATE MUST NOT CONTAIN A LITERAL '▶'. D7's close_act_missing matches on
# index(t, "▶") > 0 outside fences, so putting the marker in this skeleton would let a close that
# merely QUOTES the skeleton satisfy D7 vacuously — re-creating on the act surface exactly the
# MENTION-vs-USE defect the real() guard above was written to prevent. The S3 line therefore
# DESCRIBES the act slot and points at close_act_template, which already owns the marker.
# (The shape side stays guarded too: the verdict value below begins '<' and ends '>', so
# close_shape_ok "$(close_shape_template)" is still rc 1.)
close_shape_template() {
  cat <<'TPL'
<S1 line 1 = wrap-ledger READOUT's rung glyph and state clause verbatim, then YOUR one clause naming what the work was (or expanding the count the ledger could only count)>
Good to close: <yes — nothing of mine is open; follow-on: <filed ids, each expanded in plain English|none> | no — <what remains + who owns it>>
<S3, only when the operator must act: the run-this marker line, then the one literal command — see close_act_template>
<then AT MOST three supporting lines, one fact each: S4 what is now true against the frozen scope · S5 the sha or doc path that HOLDS what this close dropped · S6 what is theirs, NAMED not counted>
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
  # NO BACKTICKS IN THIS FORMAT STRING. It is single-quoted (so the ledger's own %s placeholders
  # survive), and a literal backtick inside it reads to shellcheck as a command substitution that
  # will not expand — SC2016, which this repo's land gate treats as RED. The block reason is plain
  # text shown to a model, never rendered markdown, so the backticks bought nothing anyway.
  # And percent signs are DOUBLED, not quadrupled: printf turns %% into one %. An earlier draft
  # carried %%%% through from a diff and rendered "73%%" to every blocked close.
  printf 'Origin-session close contract: this session wrote real work and the ledger reads %s, but the close is missing [%s]. A missing good-to-close-verdict means the close never answers "good to close?" — and that answer is NOT derivable from the rung: over 613 closes the rung predicts it only 73%% of the time, 48 of 313 closes reading complete-and-live answer NO, and 17.6%% carry no rung glyph at all. Put it on the SECOND line, directly under the rung and BEFORE any supporting detail — 90.7%% of closes bury it as the last line and the operator asks the question anyway. A missing line-1-rung means line 1 does not carry the ledger'\''s own rung glyph: run scripts/wrap-ledger.sh --machine, relay READOUT'\''s glyph and state clause verbatim, then add ONE clause of your own naming what the work was. Complication/Solution/Outcome are no longer required — where a close has a real body they restate it (Outcome is novel 1 time in 7) for a median 89 words; write them only if they say something the body does not. Shape:\n%s' \
    "$rung" "${missing:-the required close shape}" "$(close_shape_template)"
}
