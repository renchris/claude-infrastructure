#!/usr/bin/env bats
# The PANE-PARKED oracle + the third engagement state (item 7146aab37a9a).
#
# INCIDENT (2026-07-26T13:14, firing the team-orphan track): the typed launch line tripped zsh's
# `setopt CORRECT` and the pane parked at `zsh: correct 'go' to 'god' [nyae]?` — a single-key
# `read -k` prompt no automation can answer. claude never started. The engagement oracle is
# DISK-ONLY (a transcript with an assistant turn), so it cannot tell that apart from "claude booted
# and never ingested the brief": both are silence. The two have opposite remedies — the INC-4
# recovery for the latter is to RE-SEND the brief, which for a parked shell pastes the brief into a
# shell that then EXECUTES it.
#
# Worse, the disk oracle is slow (its find|grep over ~1000 MB of transcripts measures ~10 s per
# poll), so the "120 s" window is really 8-15 min and the 13:14 fire was killed mid-poll — it left
# NO row in handoffs.jsonl at all. The fail-loud verdict existed and never reached anyone. A pane
# read costs one bounded call and answers in seconds, which is the only reason the verdict lands.
#
# LAYOUT FACT the anchor rests on (measured here, via a real pty running `zsh -f -i`, 2026-07-30):
#   PS% c\bcd /tmp && claudenxt44 --effort max
#   zsh: correct 'claudenxt44' to 'claudenxt4' [nyae]?
# The shell's message occupies COLUMN 0 OF ITS OWN PHYSICAL LINE — never appended to the echoed
# command. `zsh: command not found: …` and `zsh: no matches found: …` land the same way (also
# measured). That is what makes a `^`-anchored pattern both sound and, per the prose test below,
# necessary.

setup() {
  # M11 — a test's environment is PINNED, not ambient (test-hermeticity-lint.sh binds every suite
  # that touches handoff-fire). capacity_gate reads the box's live loadavg and memory headroom and
  # exits 9 above its bars, which turns suites RED by machine load rather than by their subject —
  # a gate failing its own corpus. This suite extracts functions rather than running the whole
  # script, so it is not red-by-load today; the pin keeps that true if a test here ever grows into
  # a full fire. tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # hf_bounded is the timeout(1) wrapper; these suites extract functions rather than sourcing the
  # script, so a passthrough keeps the extracted behaviour byte-identical (fire-engagement.bats
  # pattern). Its own semantics are covered by tests/handoff-fire-it2-bound.bats.
  hf_bounded() { "$@"; }
  eval "$(grep -E '^FIRE_PARKED_RE=' "$HF")"
  eval "$(sed -n '/^pane_parked_reason() {/,/^}/p' "$HF")"
  # The FOURTH state's oracle + the enumeration it delegates to. Sourced rather than re-stated: the
  # dialog strings must have exactly one edit site, and tests/pane-modal.bats is what pins them
  # against the shipping binary. Extracting a copy here would let the two drift and both stay green.
  # shellcheck source=../hooks/lib/pane-modal.sh
  . "$REPO/hooks/lib/pane-modal.sh"
  eval "$(sed -n '/^pane_wedge_reason() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^assistant_turn_in() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^engagement_seen() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^composer_content() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^_paste_newlines() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^paste_readback_expect() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^paste_readback_ok() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^it2_paste_submit_verified() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^verify_engagement() {/,/^}/p' "$HF")"
  eval "$(grep -E '^BP_(START|END)=' "$HF")"

  SCREEN="$BATS_TEST_TMPDIR/screen"; : > "$SCREEN"
  SENDS="$BATS_TEST_TMPDIR/sends";   : > "$SENDS"
  # Fake it2: `session read` serves $SCREEN verbatim; `session send` RECORDS (so the abstain is
  # provable by absence). Nothing forks — a `&` in a bats fixture prints a spurious `not ok`
  # beside a passing body (memory: bats-background-job-fabricates-not-ok).
  #
  # A BRACKETED PASTE ALSO REDRAWS THE SCREEN, because the resend is verified now (a771a1611d28):
  # it2_paste_submit_verified reads the composer back before its CR, so a fake whose screen never
  # changes would make every re-send read as MANGLED and the positive control below would go green
  # on a withheld CR — a fixture asserting the opposite of what its name claims. The redraw is the
  # MEASURED shape (2026-08-24): a composer box holding `[Pasted text #1 +N lines]`, N = newline
  # count, never the payload.
  IT2="$BATS_TEST_TMPDIR/it2"
  { printf '#!/bin/bash\n'; printf 'SCREEN=%q; SENDS=%q\n' "$SCREEN" "$SENDS"; } > "$IT2"
  cat >> "$IT2" <<'SH'
if [ "$1 $2" = "session read" ]; then cat "$SCREEN" 2>/dev/null; exit 0; fi
if [ "$1 $2" = "session send" ]; then
  printf 'SEND\n' >> "$SENDS"
  shift 2; text=""
  while [ $# -gt 0 ]; do case "$1" in -s) shift 2 ;; *) text="$1"; shift ;; esac; done
  bps=$'\x1b[200~'; bpe=$'\x1b[201~'
  case "$text" in
    "$bps"*"$bpe")
      inner="${text#"$bps"}"; inner="${inner%"$bpe"}"
      nl="${inner//[!$'\n']/}"; b="$(printf '─%.0s' $(seq 1 100))"
      { printf '%s\n' "$b"
        if [ "${#nl}" -gt 0 ]; then printf '❯ [Pasted text #1 +%s lines]\n' "${#nl}"
        else                        printf '❯ [Pasted text #1]\n'; fi
        printf '%s\n' "$b"; } > "$SCREEN" ;;
  esac
  exit 0
fi
exit 0
SH
  chmod +x "$IT2"

  PROJ="$BATS_TEST_TMPDIR/projects"; mkdir -p "$PROJ/p"
  REG="$BATS_TEST_TMPDIR/reg";       mkdir -p "$REG"
  PANE="FAKEPANE-0000-0000-0000-000000000001"
  export FIRE_ENGAGE_TIMEOUT=1 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_TYPE_SETTLE=0.01
  export FIRE_PASTE_PREWAIT=0 FIRE_PASTE_PREIVL=0.01
}

# An EMPTY composer box, in the measured shape composer_content parses (a body between two
# full-width U+2500 runs; the ❯ glyph is non-ASCII, so an empty box reads as empty). The resend
# path needs one: it2_paste_submit_verified pastes only into a composer it has PROVEN empty, and a
# screen with no box at all is UNKNOWN, which correctly refuses to type.
empty_composer_screen() {
  local b; b="$(printf '─%.0s' $(seq 1 100))"
  printf '%s\n' "$b" "❯ " "$b" > "$SCREEN"
}

screen() { printf '%s\n' "$@" > "$SCREEN"; }

# ---- the detector: TRUE positives (every shape a shell emits when it refuses to run) -----------

@test "parked: the live 2026-07-26 shape — zsh CORRECT's [nyae] prompt" {
  screen "PS% cd /wt && go mod download" "zsh: correct 'go' to 'god' [nyae]? "
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "correct 'go' to 'god'"
}

@test "parked: the launcher word itself failing to resolve (the un-shielded E1 shape)" {
  # `claude5` is the post-2026-08-01 spelling of "a launcher name that cannot resolve": the family
  # is claude/claude2/claude3/claude4, so 5 is the first free digit — the same idea the old
  # claude-next5 fixture carried. It must stay a NONEXISTENT name: claude4 is real now, and a
  # command-not-found fixture naming a live launcher models nothing.
  screen "PS% cd /wt && claude5 --effort max" "zsh: command not found: claude5"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'command not found: claude5'
}

@test "parked: NOMATCH refuses the whole line on an unmatched glob" {
  screen "PS% echo see scripts/*.md" 'zsh: no matches found: scripts/*.md'
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
}

@test "parked: history expansion refusing a '!' (bash printf %q leaves it unescaped)" {
  screen "PS% cd /wt/hello!world && claude4" 'zsh: event not found: world'
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
}

# bash orders the message differently — `bash: <cmd>: command not found` vs zsh's
# `zsh: command not found: <cmd>` (both measured on this box). A pattern written for zsh alone
# passes its own suite and is silently blind here.
@test "parked: a bash pane reports the same class (subject in the MIDDLE, not the tail)" {
  # Same unresolvable-name discipline as the zsh case above — `claude5`, not a live launcher.
  screen "$ cd /wt && claude5" "bash: claude5: command not found"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'claude5'
}

@test "parked: bash's no-such-file shape too" {
  screen "bash: /opt/missing/claude: No such file or directory"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
}

@test "NOT parked: bash's benign startup chatter is not a refusal" {
  # `bash -i` without a tty always prints this; it is noise, not a wedge. It shares the `bash: `
  # prefix and begins with `no `, so a loose pattern reads it as a parked pane on every fire.
  screen "bash: no job control in this shell" "PS$ "
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

# ---- the detector: FALSE positives it must refuse ----------------------------------------------

@test "NOT parked: a working claude session's screen" {
  screen "╭─ claude ─────────────────╮" "│ > working on the task    │" "╰──────────────────────────╯"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# THE ANCHOR TEST. This repo's OWN briefs quote the wedge string as prose, and the INC-4 re-send
# pastes the brief INTO the pane — so an unanchored grep reads our backlog text back as proof of a
# wedge and fails a healthy fire. Both lines below carry the literal signature mid-line.
@test "RED-PROOF: brief prose QUOTING the wedge is not evidence of a wedge (anchor is load-bearing)" {
  screen \
    "TASK — handoff-fire WEDGES on zsh autocorrect — a fired session can hang at 'correct go to god [nyae]?'" \
    "the operator screenshot shows the pane sits at 'zsh: correct go to god [nyae]?' and never launches" \
    "RELATED: a fire that looks fired but never engages; grep for zsh: command not found in the pane"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "POSITIVE CONTROL: an UNANCHORED pattern really would fire on that prose" {
  # Proves the test above discriminates rather than passing vacuously: strip the '^' and the same
  # screen trips. If this ever stops failing-over, the anchor stopped being what protects us.
  screen "the pane sits at 'zsh: correct go to god [nyae]?' per the screenshot"
  FIRE_PARKED_RE="${FIRE_PARKED_RE#^}"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
}

@test "NOT parked: an unreadable/empty screen is UNKNOWN, never parked (fails open)" {
  : > "$SCREEN"
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

@test "NOT parked: missing it2 bin or pane id is a clean no-op" {
  screen "zsh: correct 'go' to 'god' [nyae]? "
  run pane_parked_reason "" "$PANE"
  [ "$status" -ne 0 ]
  run pane_parked_reason "$IT2" ""
  [ "$status" -ne 0 ]
}

# ---- the THIRD STATE in verify_engagement ------------------------------------------------------

@test "verify_engagement: a parked pane returns 2 (not 1) and names the reason" {
  screen "zsh: correct 'go' to 'god' [nyae]? "
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "the brief"
  [ "$status" -eq 2 ]
}

# CC_FIRE_COMPOSER_GATE=off in the next two tests ISOLATES this change from 0e03861c, which landed
# independently while this was in flight and makes the resend helper abstain unless composer_owned()
# proves a live CC session owns the pane (that helper is it2_paste_submit_verified since
# a771a1611d28; 0e03861c added the gate to the blind it2_paste_submit it replaced). That gate is STRICTLY STRONGER as a safety net (a positive
# oracle, fail-closed on "unknown", where this one only fires on "provably parked") and it is the
# reason the resend is now safe in general. But with it ON, both tests below would pass whether or
# not this change existed — an over-determined assertion proving nothing about the code under test.
# Pinning it off leaves the parked short-circuit as the only variable. The two are complementary,
# not redundant: theirs stops the harmful paste, this one stops the WAIT — without it a parked fire
# still burns the whole engagement window and then reports the generic "never engaged" with a
# recovery instruction that is wrong for a pane where the launcher never ran.
@test "verify_engagement: ABSTAINS — a parked pane is never re-sent the brief" {
  # The load-bearing safety invariant: the brief pasted into a shell is EXECUTED as a script
  # ($(…) runs, a bare glob refuses the line, a '!' raises event-not-found). Proven by ABSENCE of
  # any send — the fake it2 records every one.
  export CC_FIRE_COMPOSER_GATE=off
  screen "zsh: correct 'go' to 'god' [nyae]? "
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" 'brief with $(id -un) in it'
  [ "$status" -eq 2 ]
  [ ! -s "$SENDS" ]
}

@test "POSITIVE CONTROL: a NOT-parked never-engaged pane DOES still get the INC-4 re-send" {
  # Proves the abstain above is conditional, not a blanket removal of the recovery — same call,
  # same corpus, only the screen differs. The screen is an EMPTY COMPOSER because that is INC-4's
  # own ground truth (memory cold-worktree-fire-autosubmit-race: the session sat at an empty
  # prompt, never having read the brief) and because the verified resend types only into one.
  export CC_FIRE_COMPOSER_GATE=off
  empty_composer_screen
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "$(printf 'the brief\nline two\nline three\nline four\n')"
  [ "$status" -eq 1 ]
  [ "$(grep -c SEND "$SENDS")" -eq 2 ]   # the paste AND the CR — a withheld CR is not a re-send
}

@test "the re-send is VERIFIED: a composer that is NOT empty gets the paste withheld too" {
  # The gap the parked/wedged short-circuits never covered: CC owns the pane, it is not parked and
  # not wedged, and the composer holds an operator's unsubmitted draft. Pasting there appends to
  # the draft and the CR submits the hybrid — the measured mangle class (recycle-100p 2026-08-22).
  # The recovery is forgone, loudly; the draft is not destroyed.
  export CC_FIRE_COMPOSER_GATE=off
  local b; b="$(printf '─%.0s' $(seq 1 100))"
  printf '%s\n' "$b" "❯ half-typed operator thought" "$b" > "$SCREEN"
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "the brief"
  [ "$status" -eq 1 ]
  [ ! -s "$SENDS" ]
  printf '%s\n' "$output" | grep -q 'HELD'
}

# ---- the FOURTH STATE: claude STARTED, and stopped on a modal (backlog 75c2e3e2bde7) -----------
#
# The exact inverse of everything above. PARKED means the shell refused the launch, so no session
# exists and the remedy is "clear the pane and re-fire". WEDGED means the session booted and is
# holding on a dialog, where that remedy DESTROYS a live session. Both are silence on disk, both
# leave a live pane, and `ps` cannot tell them apart — only the screen carries the difference.

modal_screen() {
  screen \
    "│ New MCP server found in this project: ms365          │" \
    "│ 1. Use this MCP server                               │" \
    "│ 3. Continue without using this MCP server            │"
}

@test "wedged: the MCP-approval dialog is named" {
  modal_screen
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
  [ "$output" = "mcp-trust-modal" ]
}

@test "the two oracles do not overlap: a shell wedge is PARKED and not wedged" {
  screen "zsh: correct 'go' to 'god' [nyae]? "
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

@test "the two oracles do not overlap: a modal is wedged and not PARKED" {
  # Load-bearing in the direction the caller branches on: were the modal to also satisfy
  # FIRE_PARKED_RE, verify_engagement would short-circuit to 2 first and print "clear the pane,
  # then re-fire" at a pane holding a live session.
  modal_screen
  run pane_parked_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

@test "NOT wedged: an unreadable/empty screen is UNKNOWN, never wedged (fails open)" {
  : > "$SCREEN"
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

@test "NOT wedged: missing it2 bin or pane id is a clean no-op" {
  modal_screen
  run pane_wedge_reason "" "$PANE"
  [ "$status" -ne 0 ]
  run pane_wedge_reason "$IT2" ""
  [ "$status" -ne 0 ]
}

@test "FAIL-OPEN: the modal lib absent ⇒ never wedged, and never an error" {
  # The deploy-lag branch. handoff-fire.sh guards its source, so an un-globbed hooks/lib leaves
  # pane_modal_reason undefined — that must cost the verdict, not the fire.
  modal_screen
  unset -f pane_modal_reason
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
}

@test "verify_engagement: a wedged pane returns 4 (not 1, not 2) and names the modal" {
  modal_screen
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "the brief"
  [ "$status" -eq 4 ]
}

@test "verify_engagement: ABSTAINS — a wedged pane is never re-sent the brief" {
  # THE SAFETY INVARIANT THIS STATE EXISTS FOR, and it is stronger than the parked one. A startup
  # dialog is a single-key prompt, so the paste's own bytes become ANSWERS — and the two dialogs
  # reachable here are workspace-trust and MCP-approval, i.e. the ones the research classifies as
  # security boundaries that must reach a human. Proven by ABSENCE of any send.
  export CC_FIRE_COMPOSER_GATE=off
  modal_screen
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" 'brief with $(id -un) in it'
  [ "$status" -eq 4 ]
  [ ! -s "$SENDS" ]
}

@test "verify_engagement: the abstain holds on the PRE-RESEND path too (timeout 0)" {
  # The guard above and this one are DIFFERENT LINES, and only this configuration reaches the
  # second. A red-proof found it: deleting the pre-resend abstain entirely left the whole suite
  # green, because at any non-zero timeout the in-loop check returns 4 on the first iteration and
  # the post-loop guard is never evaluated. An invariant no test can reach is an invariant nobody
  # is holding — and the path this exercises is the live one whenever the loop times out on a pane
  # that has only just rendered its dialog.
  export CC_FIRE_COMPOSER_GATE=off
  FIRE_ENGAGE_TIMEOUT=0
  modal_screen
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" 'brief with $(id -un) in it'
  [ "$status" -eq 4 ]
  [ ! -s "$SENDS" ]
}

@test "RED-PROOF: plan prose naming a dialog is not evidence of a wedge" {
  # The defect prior art cfdd9fc3 actually shipped, in this file's own idiom: an agent reading the
  # plan that documents these dialogs has their text on screen. Note this screen carries the header
  # AND an option — the conjunction alone does NOT refuse it, and this exact fixture is what proved
  # that while the suite was being written. The ANCHOR is what refuses it.
  screen \
    "§9.2 — each spawned session renders New MCP server found in this project and BLOCKS there" \
    "the operator answered 1. Use this MCP server, which is session-scoped and persists nothing"
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "POSITIVE CONTROL: without the anchor that same prose really would fire" {
  # Proves the test above discriminates rather than passing vacuously. `.*` in front of each pattern
  # re-permits a mid-line match — the exact equivalent of stripping the `^` from FIRE_PARKED_RE in
  # this file's sibling control above. Same screen, same call; only the anchoring differs.
  screen \
    "§9.2 — each spawned session renders New MCP server found in this project and BLOCKS there" \
    "the operator answered 1. Use this MCP server, which is session-scoped and persists nothing"
  # shellcheck disable=SC2034  # read by pane_modal_reason, sourced from hooks/lib/pane-modal.sh
  CC_MODAL_MCP_HEADER=".*New MCP server found"
  # shellcheck disable=SC2034  # same — the seam's consumer is in the lib, not in this file
  CC_MODAL_MCP_OPTION=".*Use this MCP server"
  run pane_wedge_reason "$IT2" "$PANE"
  [ "$status" -eq 0 ]
  [ "$output" = "mcp-trust-modal" ]
}

@test "verify_engagement: engagement still wins over a modal-looking screen (0 beats 4)" {
  # Same authority rule as the parked case: the disk oracle owns SUCCESS, the pane oracle only ever
  # short-circuits a failure. An agent that engaged and later rendered dialog text is not wedged.
  { printf '{"type":"user","message":{"role":"user","content":"hi MARK ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}\n'
  } > "$PROJ/p/s.jsonl"
  modal_screen
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "the brief"
  [ "$status" -eq 0 ]
}

@test "verify_engagement: engagement still wins over a parked-looking screen (0 beats 2)" {
  # Residue on screen must never override real proof on disk — the disk oracle stays authoritative
  # for SUCCESS; the pane oracle only ever short-circuits a failure.
  { printf '{"type":"user","message":{"role":"user","content":"hi MARK ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}\n'
  } > "$PROJ/p/s.jsonl"
  screen "zsh: correct 'go' to 'god' [nyae]? "
  run verify_engagement "$PROJ" "MARK" "$REG" "$PANE" "$IT2" "the brief"
  [ "$status" -eq 0 ]
}

# ---- the mechanism itself, against a real zsh --------------------------------------------------

@test "MECHANISM: bare word spell-prompts, 'nocorrect' shields it (real zsh, positive-controlled)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  local rc="$BATS_TEST_TMPDIR/rc.zsh"
  { printf 'setopt CORRECT\n'; printf 'claudenxt4() { :; }\n'; } > "$rc"
  # `zsh -f` = no operator rc (hermetic); a PIPED line is read by the line editor, which is what
  # arms CORRECT — `zsh -ic '<cmd>'` does NOT reproduce it (argv is not a ZLE line).
  local bare shielded
  bare="$(printf '%s\n' "source $rc" 'claudenxt44 --effort max' | zsh -f -i 2>&1 || true)"
  shielded="$(printf '%s\n' "source $rc" 'nocorrect claudenxt44 --effort max' | zsh -f -i 2>&1 || true)"
  # POSITIVE CONTROL first: without the shield the prompt MUST appear, else this test is vacuous.
  printf '%s' "$bare" | grep -q "correct 'claudenxt44'" \
    || { echo "harness did not reproduce the wedge — test would be vacuous"; false; }
  # And with it, the wedge is gone — degraded to a clean, non-blocking failure.
  ! printf '%s' "$shielded" | grep -q '\[nyae\]' || false
  printf '%s' "$shielded" | grep -q 'command not found' || false
}

@test "MECHANISM: 'nocorrect' still expands the launcher alias and passes the env prefix" {
  # The reason `nocorrect` beats quoting: quoting suppresses correction AND alias expansion, so a
  # quoted 'claude2' would simply not resolve. And --in-place's CLAUDE_ISOLATION_SKIP=1 must
  # still reach the process.
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  local rc="$BATS_TEST_TMPDIR/rc2.zsh" out
  { printf 'setopt CORRECT\n'
    printf 'claudenxt4() { printf "RAN:%%s\\n" "$CLAUDE_ISOLATION_SKIP"; }\n'; } > "$rc"
  out="$(printf '%s\n' "source $rc" 'nocorrect CLAUDE_ISOLATION_SKIP=1 claudenxt4' | zsh -f -i 2>&1 || true)"
  printf '%s' "$out" | grep -q 'RAN:1' || { echo "got: $out"; false; }
}
