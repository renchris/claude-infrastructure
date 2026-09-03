#!/usr/bin/env bats
# handoff-fire.sh — THE COMPOSER-CONTENT GATE (recycle-100p, 2026-08-22).
# Evidence + design: docs/research/recycle-100p-2026-08-22.md.
#
# WHY THIS SUITE EXISTS. The recycle chain's keystrokes judged only OWNERSHIP ("is this a CC
# pane") and never CONTENT. Measured consequence: /exit typed over a held operator draft MERGES
# into one text message — 30 events in 24 days, ≥8 of them swallowing a real in-flight operator
# message — and the blind CR nudge at +60s is what SUBMITS the hybrid. The /goal paste was the one
# injection with no read-back before its CR. These tests pin the three properties of the fix:
#
#   1. CONTENT IS PARSED, NOT ASSUMED. composer_content extracts the input box (between the last
#      two full-width border rows) as printable ASCII: the P2-measured screens — empty (glyph
#      only), fresh-with-placeholder (`Try "…"`), drafted, paste-into-draft — classify correctly,
#      and a boxless/torn screen is UNKNOWN (rc 1), never EMPTY.
#   2. THE DESTRUCTIVE KEYSTROKE IS PROOF-GATED. recycle_composer_gate refuses /exit over any
#      non-empty or unreadable composer; recycle_nudge_decision only ever answers `cr` for a
#      composer holding exactly the stranded /exit; it2_paste_submit_verified sends its CR only
#      when paste_readback_ok proves the composer holds exactly this paste and nothing else.
#   3. THE OLD BEHAVIOR IS THE RED-PROOF, and it is now a LOCAL MUTANT rather than a shipped
#      function. `it2_paste_submit` — the blind-CR primitive this suite used to import from the
#      script as its control — was deleted on 2026-08-24 (a771a1611d28) when its last caller, the
#      fire path's INC-4 brief resend, was migrated onto the verified form. The differential is
#      what mattered, not the import, so the mutant is defined in this file: on the same mismatch
#      fixture the blind form sends the CR and the shipped form withholds it. If someone
#      "simplifies" the verified form back to a blind CR, the rc-4 test is the one that goes red.
#
# THE READ-BACK IS NOT THE PASTE (measured 2026-08-24, live CC pane). Anything over 800 chars or
# 2 newlines — i.e. EVERY brief — is replaced in the composer by `[Pasted text #1 +N lines]`, so
# byte-equality would call every real resend MANGLED. paste_readback_ok therefore accepts the
# inline text OR that placeholder with N pinned to the payload's own newline count; the measured
# hybrid shape (`also fix the margin[Pasted text #1 +19 lines]`) matches neither, which is the
# property the fire path depends on.
#
# Hermeticity: KITTY_WINDOW_ID pinned off (memory: terminal-aware subjects make unpinned suites a
# function of the developer's terminal); every it2 access goes through a stubbed hf_bounded.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # Hermeticity seams (scripts/test-hermeticity-lint.sh): nothing here fires, but a fixtured $HOME
  # does NOT redirect an absolute /tmp default or a bare name resolved off the operator's PATH —
  # pinned to ABSENT tmpdir paths, where the sensors that read them fail open.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^emit_recycle_event() {/,/^}/p'          "$HF"
    sed -n '/^emit_goal_event() {/,/^}/p'             "$HF"
    sed -n '/^composer_content() {/,/^}/p'            "$HF"
    sed -n '/^recycle_composer_gate() {/,/^}/p'       "$HF"
    sed -n '/^recycle_nudge_decision() {/,/^}/p'      "$HF"
    sed -n '/^_paste_newlines() {/,/^}/p'             "$HF"
    sed -n '/^paste_readback_expect() {/,/^}/p'       "$HF"
    sed -n '/^paste_readback_ok() {/,/^}/p'           "$HF"
    sed -n '/^it2_paste_submit_verified() {/,/^}/p'   "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"

  # ---- stubs -------------------------------------------------------------------------------
  # hf_bounded is the ONLY transport the units touch:
  #   `session read`  → serves $SCREEN_FILE (the fixture screen; tests swap it between phases)
  #   `session send`  → appends the payload to $SENT_LOG (what the caller actually typed)
  SCREEN_FILE="$BATS_TEST_TMPDIR/screen.txt"
  SENT_LOG="$BATS_TEST_TMPDIR/sent.log"; : > "$SENT_LOG"
  hf_bounded() { # <bin> session <read|send> -s <sid> ...
    local verb="$3"
    if [ "$verb" = read ]; then cat "$SCREEN_FILE" 2>/dev/null; return 0; fi
    if [ "$verb" = send ]; then printf '%s\n' "SEND:$6" >> "$SENT_LOG"; return 0; fi
    return 1
  }
  composer_owned() { return 0; }        # ownership is composer_owned's OWN suite's subject
  _under_test() { echo true; }
  export BP_START=$'\x1b[200~' BP_END=$'\x1b[201~'   # read by it2_paste_submit{,_verified} from units.sh
  export FIRE_TYPE_SETTLE=0.01 FIRE_PASTE_PREWAIT=0 FIRE_PASTE_PREIVL=0.01

  # ---- fixture screens, from the MEASURED shapes -------------------------------------------
  B="$(printf '─%.0s' $(seq 1 100))"    # a full-width border row (U+2500 run)
  GLYPH='❯'                             # the composer prompt glyph (non-ASCII → invisible to the parse)
  mk_screen() { # $1..: composer rows (between the borders)
    { echo "scrollback noise"; echo "⏺ some reply"; echo "$B"
      for r in "$@"; do echo "$r"; done
      echo "$B"; echo "  (4) repo · statusline"; } > "$SCREEN_FILE"
  }
}

# ── 1. the parse ─────────────────────────────────────────────────────────────────────────────

@test "empty composer (glyph only) reads EMPTY" {
  mk_screen "$GLYPH "
  run composer_content it2 sid
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "fresh-session placeholder (P2 measured) reads EMPTY — anchored whole-row only" {
  mk_screen "$GLYPH Try \"create a util logging.py that...\""
  run composer_content it2 sid
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "a real draft that merely STARTS with the placeholder shape reads as a DRAFT" {
  mk_screen "$GLYPH Try \"x\" then run the deploy"
  run composer_content it2 sid
  [ "$status" -eq 0 ]; [ -n "$output" ]
}

@test "operator draft reads back verbatim (space-stripped)" {
  mk_screen "$GLYPH I also think VIP Deck 1 needs more margin top"
  run composer_content it2 sid
  [ "$status" -eq 0 ]
  [ "$output" = "IalsothinkVIPDeck1needsmoremargintop" ]
}

@test "paste-into-draft (the P2 mangle shape, two rows) reads as the concatenated hybrid" {
  mk_screen "$GLYPH DRAFT-XYZZY" "/goal PASTE-INTO-DRAFT"
  run composer_content it2 sid
  [ "$status" -eq 0 ]
  [ "$output" = "DRAFT-XYZZY/goalPASTE-INTO-DRAFT" ]
}

@test "stranded /exit reads as exactly /exit" {
  mk_screen "$GLYPH /exit"
  run composer_content it2 sid
  [ "$status" -eq 0 ]; [ "$output" = "/exit" ]
}

@test "boxless / torn screen is UNKNOWN (rc 1), never EMPTY" {
  { echo "some scrollback"; echo "no borders here"; } > "$SCREEN_FILE"
  run composer_content it2 sid
  [ "$status" -eq 1 ]
}

@test "unreadable pane (empty read) is UNKNOWN (rc 1)" {
  : > "$SCREEN_FILE"
  run composer_content it2 sid
  [ "$status" -eq 1 ]
}

# ── 2. the /exit gate ────────────────────────────────────────────────────────────────────────

@test "gate: proven-empty composer admits /exit (rc 0)" {
  mk_screen "$GLYPH "
  run recycle_composer_gate it2 sid 0 1
  [ "$status" -eq 0 ]
}

@test "gate: held draft refuses (rc 1) and names the draft" {
  mk_screen "$GLYPH ship it after lunch"
  run recycle_composer_gate it2 sid 0 1
  [ "$status" -eq 1 ]
  [ "$output" = "shipitafterlunch" ]
}

@test "gate: unreadable box refuses as UNKNOWN (rc 2) — typing needs the affirmative" {
  : > "$SCREEN_FILE"
  run recycle_composer_gate it2 sid 0 1
  [ "$status" -eq 2 ]
}

# ── 3. the nudge decision ────────────────────────────────────────────────────────────────────

@test "nudge: exactly-/exit composer → cr" {
  mk_screen "$GLYPH /exit"
  run recycle_nudge_decision it2 sid
  [ "$output" = "cr" ]
}

@test "nudge: empty composer → retype (typed-but-lost /exit)" {
  mk_screen "$GLYPH "
  run recycle_nudge_decision it2 sid
  [ "$output" = "retype" ]
}

@test "nudge: merged draft+/exit (the swallowed-message class) → hold, NEVER cr" {
  mk_screen "$GLYPH (at what point do we want to self-recycle?)/exit"
  run recycle_nudge_decision it2 sid
  [ "$output" = "hold" ]
}

@test "nudge: unreadable screen → unknown, NEVER cr" {
  : > "$SCREEN_FILE"
  run recycle_nudge_decision it2 sid
  [ "$output" = "unknown" ]
}

# ── 4. the verified paste ────────────────────────────────────────────────────────────────────

# Phase-swapping stub: pre-check reads serve $PRE_FILE, later reads serve $POST_FILE. The phase
# counter is a FILE, not a shell var — composer_content invokes hf_bounded inside $(…), so a shell
# counter would increment in a subshell and every read would serve the pre screen forever (found
# by running it: the happy-path read-back saw the empty pre screen and reported MANGLED).
phased_hf_bounded() {
  local verb="$3"
  if [ "$verb" = read ]; then
    echo r >> "$READS_FILE"
    if [ "$(wc -l < "$READS_FILE")" -le 1 ]; then cat "$PRE_FILE"; else cat "$POST_FILE"; fi
    return 0
  fi
  if [ "$verb" = send ]; then printf '%s\n' "SEND:$6" >> "$SENT_LOG"; return 0; fi
  return 1
}

# Three-phase sibling of the above, for the post-paste POLL: read 1 serves the empty pre screen,
# reads 2..$TORN_READS serve a frame caught MID-REPAINT (no input box between two borders, so
# composer_content returns rc 1 = UNKNOWN), and every read after that serves the settled composer.
# File-scope, one-liner at the call sites, for the same reason phased_hf_bounded is: an inline
# multi-line function body inside a @test defeats bats-assert-liveness.py's depth tracking and
# every statement after it reports as a dead non-final assertion.
torn_hf_bounded() {
  local verb="$3" n
  if [ "$verb" = read ]; then
    echo r >> "$READS_FILE"; n="$(wc -l < "$READS_FILE")"
    if   [ "$n" -le 1 ]; then cat "$PRE_FILE"
    elif [ "$n" -le "${TORN_READS:-2}" ]; then cat "$TORN_FILE"
    else cat "$POST_FILE"; fi
    return 0
  fi
  if [ "$verb" = send ]; then printf '%s\n' "SEND:$6" >> "$SENT_LOG"; return 0; fi
  return 1
}

@test "verified paste: happy path — empty pre, exact read-back, CR sent (rc 0)" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE"; mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH /goal reply with DONE"
  hf_bounded() { phased_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "/goal reply with DONE"
  [ "$status" -eq 0 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 2                       # paste + CR, nothing else
  tail -1 "$SENT_LOG" | grep -q $'SEND:\r'                       # the CR came LAST
}

@test "verified paste: occupied composer → rc 3 HELD, NOTHING sent" {
  mk_screen "$GLYPH half-typed operator thought"
  run it2_paste_submit_verified it2 sid "/goal x"
  [ "$status" -eq 3 ]
  [ ! -s "$SENT_LOG" ]
}

@test "verified paste: read-back mismatch → rc 4 MANGLED, paste sent but CR WITHHELD" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE"; mk_screen "$GLYPH "
  # the operator raced in between paste and read-back — hybrid on screen
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH also fix the margin/goal reply with DONE"
  hf_bounded() { phased_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "/goal reply with DONE"
  [ "$status" -eq 4 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 1                       # the paste only
  ! grep -q $'SEND:\r' "$SENT_LOG"                               # NO CR — the whole point
}

@test "verified paste: unreadable screens → rc 2, NOTHING sent" {
  : > "$SCREEN_FILE"
  run it2_paste_submit_verified it2 sid "/goal x"
  [ "$status" -eq 2 ]
  [ ! -s "$SENT_LOG" ]
}

# ── 5. RED-PROOF: the old path submits the same mangle the new path withholds ────────────────

@test "mutant control: a BLIND paste-submit sends a CR on the identical mismatch fixture" {
  # The pre-fix behavior, verbatim and local: ownership gate, bracketed paste, unconditional CR.
  # It MUST send the CR on a fixture the shipped form refuses — that differential is the whole
  # claim. If the rc-4 test above fails instead, the verified path regressed to exactly this.
  blind_paste_submit() {                                         # the DELETED it2_paste_submit
    local it2="$1" id="$2" text="$3"
    composer_owned "$id" || return 1
    hf_bounded "$it2" session send -s "$id" "${BP_START}${text}${BP_END}" >/dev/null 2>&1 || return 1
    hf_bounded "$it2" session send -s "$id" $'\r' >/dev/null 2>&1
  }
  mk_screen "$GLYPH also fix the margin"
  run blind_paste_submit it2 sid "/goal reply with DONE"
  [ "$status" -eq 0 ]
  grep -q $'SEND:\r' "$SENT_LOG"                                 # blind CR: sent regardless
}

@test "no blind paste primitive survives in the script — the mutant is test-local only" {
  # The ratchet: scripts/typed-send-lint.sh dropped this function's grandfather line in the same
  # commit, and a re-added blind helper would be a NEW violation. Keyed on the definition, so a
  # comment naming the history (there is one) cannot satisfy or break it.
  ! grep -qE '^it2_paste_submit\(\)' "$HF"
}

# ── 4b. the read-back oracle: what a MULTI-LINE brief actually shows ─────────────────────────
# Fixtures are the MEASURED screens (live CC pane, tmux 120x40, 2026-08-24), not invented shapes.

@test "readback: a 20-line brief reads back as the PLACEHOLDER, and that is a match" {
  local brief; brief="$(printf 'line %s of the brief\n' 1 2 3 4 5 6 7 8 9 10)"   # 9 newlines
  run paste_readback_ok "$brief" '[Pastedtext#1+9lines]'
  [ "$status" -eq 0 ]
}

@test "readback: the placeholder's line count is PINNED — a different N is a mismatch" {
  local brief; brief="$(printf 'line %s of the brief\n' 1 2 3 4 5 6 7 8 9 10)"   # 9 newlines
  run paste_readback_ok "$brief" '[Pastedtext#1+8lines]'
  [ "$status" -ne 0 ]
}

@test "readback: a >800-char single-line paste reads back as the count-less placeholder" {
  local long; long="$(printf 'X%.0s' $(seq 1 900))"
  run paste_readback_ok "$long" '[Pastedtext#1]'
  [ "$status" -eq 0 ]
  run paste_readback_ok "$long" '[Pastedtext#1+3lines]'          # …and only that form
  [ "$status" -ne 0 ]
}

@test "readback: the MEASURED hybrid (draft + placeholder) is a MISMATCH — the whole point" {
  local brief; brief="$(printf 'line %s of the brief\n' 1 2 3 4 5 6 7 8 9 10)"
  run paste_readback_ok "$brief" 'alsofixthemargin[Pastedtext#1+9lines]'
  [ "$status" -ne 0 ]
}

@test "readback: a short ≤2-newline paste still verifies as its own text (the /goal shape)" {
  run paste_readback_ok "/goal reply with DONE" "/goalreplywithDONE"
  [ "$status" -eq 0 ]
  run paste_readback_ok "/goal reply with DONE" "/goalreplywithDONEandshipit"
  [ "$status" -ne 0 ]
}

# ── 4c. the SCROLLED-TAIL regime the 120-column measurement could not see (2026-08-25) ────────
# The composer is height-capped (~10 body rows) and scrolls to the cursor, which after a bracketed
# paste sits at the END. At 120 cols an 800-char payload fits and the head stays on screen; in the
# FORTY-column split-right panes these fires actually target it does not, so composer_content can
# only ever return a TAIL and byte-equality rejected a pristine paste for that whole population.
#
# The fixture is the REAL failing payload, not an invented one: the `--goal` condition of the fire
# at 2026-08-25T21:30:18Z into pane 49 (`goal-arm verdict=mangled`, CR withheld). The operator
# submitted the composer by hand and the goal that landed is byte-identical to it, so the paste was
# pristine and the oracle was blind. The read-back began at stripped offset 76, measured off the
# MANGLED line's own 80-char excerpt.
_hf_goal_payload_20260825() {
  printf '%s' "/goal docs/research/SPATIAL_CV_TOOLING.md is landed on origin/main carrying a scored comparison and exactly one recommendation, including an explicit verdict on whether anything beats Opus 5 plus a screenshot — proven by printing the scored table and running git merge-base --is-ancestor HEAD origin/main; do not modify any tracked file outside docs/research/; full brief in the prompt above, DoD at docs/plans/HUMAN_SEO_VISUAL_REBUILD.md section W2"
}
_hf_strip() { printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | LC_ALL=C tr -d '[:space:]'; }

@test "readback: the pane-49 payload shown as its SCROLLED TAIL verifies (RED before the fix)" {
  local text want got
  text="$(_hf_goal_payload_20260825)"; want="$(_hf_strip "$text")"
  got="${want:76}"                                   # the head scrolled off, exactly as measured
  [ "${got:0:12}" = "comparisonan" ]                 # pins the fixture to the logged excerpt
  run paste_readback_ok "$text" "$got"
  [ "$status" -eq 0 ]
}

@test "readback: TRANSPORT truncation drops the TAIL, and that stays a MISMATCH" {
  # The opposite truncation direction: bytes lost in flight leave the HEAD on screen. Accepting it
  # would submit a half-pasted payload, which is why the tail form is anchored and not a substring.
  local text want
  text="$(_hf_goal_payload_20260825)"; want="$(_hf_strip "$text")"
  run paste_readback_ok "$text" "${want:0:200}"
  [ "$status" -ne 0 ]
}

@test "readback: a draft PREPENDED to the payload is still a mismatch under the tail form" {
  local text want
  text="$(_hf_goal_payload_20260825)"; want="$(_hf_strip "$text")"
  run paste_readback_ok "$text" "alsofixthemargin${want}"        # longer than want ⇒ no tail match
  [ "$status" -ne 0 ]
}

@test "readback: a tail shorter than the floor proves nothing and is a mismatch" {
  local text want
  text="$(_hf_goal_payload_20260825)"; want="$(_hf_strip "$text")"
  run paste_readback_ok "$text" "${want: -20}"
  [ "$status" -ne 0 ]
  PASTE_TAIL_MIN=8 run paste_readback_ok "$text" "${want: -20}"  # …and the floor is what refuses it
  [ "$status" -eq 0 ]
}

@test "readback: a long tail of a DIFFERENT payload is a mismatch" {
  local text
  text="$(_hf_goal_payload_20260825)"
  run paste_readback_ok "$text" "$(_hf_strip 'some entirely different brief that happens to be comfortably longer than the sixty-four character floor')"
  [ "$status" -ne 0 ]
}

@test "readback: newlines are counted CC's way — \\r\\n and lone \\r each count ONCE" {
  run _paste_newlines "$(printf 'a\nb')"; [ "$output" = 1 ]
  run _paste_newlines "a"$'\r\n'"b"$'\r'"c"; [ "$output" = 2 ]
  run _paste_newlines "no newlines here"; [ "$output" = 0 ]
}

@test "verified paste: a real BRIEF pastes and submits against the placeholder read-back" {
  # The end-to-end property the fire-path migration depends on: byte-equality would have refused
  # this, because the composer never shows the brief.
  local brief; brief="$(printf 'line %s of the brief\n' 1 2 3 4 5 6 7 8 9 10)"   # 9 newlines
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH [Pasted text #1 +9 lines]"
  hf_bounded() { phased_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "$brief"
  [ "$status" -eq 0 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 2
  tail -1 "$SENT_LOG" | grep -q $'SEND:\r'
}

@test "verified paste: brief pasted ONTO a draft that raced in → rc 4, CR WITHHELD" {
  local brief; brief="$(printf 'line %s of the brief\n' 1 2 3 4 5 6 7 8 9 10)"
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH also fix the margin[Pasted text #1 +9 lines]"
  hf_bounded() { phased_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "$brief"
  [ "$status" -eq 4 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 1
  ! grep -q $'SEND:\r' "$SENT_LOG"
}

# ── 7. THE READ-BACK IS POLLED, NOT SAMPLED (2026-09-03) ─────────────────────────────────────
# Live failure: 2026-09-03T19:15:19Z, pane 213, a 572-char single-line `/goal` payload on the
# --recycle path. verdict=mangled, CR withheld, and the goal the operator then submitted by hand
# is byte-identical to what handoff-fire pasted. The post-paste side took ONE sample 0.5 s after
# the send — at the exact moment the just-engaged successor is repainting — while the pre-paste
# side has always polled for 30 s. 5 mangles in 94 arms, 3 of 62 recycles against 2 of 26 fresh
# fires: mode-independent and stochastic, which is what a transient read looks like and what a
# geometry mismatch (deterministic per width, 94aa89bc6) does not.
#
# The acceptance predicate is UNCHANGED. These cases pin that the extra chances only buy time —
# a genuine mangle still spends every try and still gets no CR.

@test "read-back: a TORN frame right after the paste is RE-READ, not convicted (RED before the fix)" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  TORN_FILE="$BATS_TEST_TMPDIR/torn.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH /goal reply with DONE"
  # a frame caught mid-repaint: no input box between two borders ⇒ composer_content rc 1
  printf 'half-drawn assistant output\nno box on screen yet\n' > "$TORN_FILE"
  hf_bounded() { torn_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "/goal reply with DONE"
  [ "$status" -eq 0 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 2                       # paste + CR
  tail -1 "$SENT_LOG" | grep -q $'SEND:\r'                       # the CR came LAST
}

@test "read-back: FIRE_PASTE_READBACK_TRIES=1 restores the single sample (a seam that can turn off)" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  TORN_FILE="$BATS_TEST_TMPDIR/torn.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH /goal reply with DONE"
  printf 'half-drawn assistant output\nno box on screen yet\n' > "$TORN_FILE"
  hf_bounded() { torn_hf_bounded "$@"; }
  FIRE_PASTE_READBACK_TRIES=1 run it2_paste_submit_verified it2 sid "/goal reply with DONE"
  [ "$status" -eq 4 ]
  ! grep -q $'SEND:\r' "$SENT_LOG"
}

# The verdict half of this one is a TRUE control — cases 17 and 34 assert it and pass on BOTH
# sides of the fix, which is what pins that polling did not loosen the acceptance predicate. The
# try-count assertion below is new behaviour and is RED pre-fix; both live in one case so a reader
# cannot separate "still refuses" from "actually spent the budget it claims to spend".
@test "read-back: a PERSISTENT hybrid spends every try and still gets no CR" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH also fix the margin/goal reply with DONE"
  hf_bounded() { phased_hf_bounded "$@"; }
  FIRE_PASTE_READBACK_TRIES=4 run it2_paste_submit_verified it2 sid "/goal reply with DONE"
  [ "$status" -eq 4 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 1                       # the paste only
  [ "$(wc -l < "$READS_FILE")" -eq 5 ]                            # 1 pre-paste + 4 read-back tries
  ! grep -q $'SEND:\r' "$SENT_LOG"                                # final: a negation lives only here
}

# The recycle path DESTROYS the session that ran the fire, so every stderr line these branches
# print reaches nobody — verified on the 19:15 instance, whose firing transcript contains zero
# "MANGLED" lines. The ledger row is the only durable record, so it has to carry the observation.

@test "read-back: a MANGLE records WHAT it saw, for the ledger (RED before the fix)" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE";  mk_screen "$GLYPH "
  SCREEN_FILE="$POST_FILE"; mk_screen "$GLYPH also fix the margin/goal reply with DONE"
  hf_bounded() { phased_hf_bounded "$@"; }
  local rc=0
  FIRE_PASTE_READBACK_TRIES=2 it2_paste_submit_verified it2 sid "/goal reply with DONE" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  [ "${FIRE_PASTE_LAST_READBACK:-}" = "alsofixthemargin/goalreplywithDONE" ]
}

@test "read-back: an UNREADABLE screen is recorded as such, not as empty content" {
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; TORN_FILE="$BATS_TEST_TMPDIR/torn.txt"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  SCREEN_FILE="$PRE_FILE"; mk_screen "$GLYPH "
  printf 'half-drawn assistant output\nno box on screen yet\n' > "$TORN_FILE"
  TORN_READS=99                                                   # the screen never settles
  hf_bounded() { torn_hf_bounded "$@"; }
  local rc=0
  FIRE_PASTE_READBACK_TRIES=2 it2_paste_submit_verified it2 sid "/goal x" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  [ "${FIRE_PASTE_LAST_READBACK:-}" = "<unreadable>" ]
}

@test "read-back: a HELD composer records the draft it deferred to" {
  mk_screen "$GLYPH half-typed operator thought"
  local rc=0
  it2_paste_submit_verified it2 sid "/goal x" 2>/dev/null || rc=$?
  [ "$rc" -eq 3 ]
  [ "${FIRE_PASTE_LAST_READBACK:-}" = "half-typedoperatorthought" ]
}
