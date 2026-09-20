#!/usr/bin/env bats
# W3 — SUBMISSION, as a fact read off the transcript rather than a phrase read off a screen.
#
# THE DEFECT THIS SUITE PINS. lr-fire-resume verified its injected prompt by waiting for the string
# `esc to interrupt` to appear on the pty — the TUI's "a turn is running" chrome. That is a SCREEN
# PHRASE, and it fails in both directions: it is width- and version-dependent (the same class as the
# `shift+tab to cycle` READY phrase, measured 0 hits in CC 2.1.260), and it cannot tell OUR prompt's
# turn from ANY turn — a harness notification turn satisfies it while the injected prompt sits
# unsubmitted in the composer. The cure is a per-run TOKEN carried in the prompt itself and looked
# for in the TARGET transcript, which is what lr-submit-probe.sh reads.
#
# The three verdicts are not three shades of one answer: `submitted` starts the engagement clock,
# `queued` means keep waiting behind a running turn, and `none` means act — and an UNREADABLE
# transcript is none of them, which is why it exits non-zero with empty stdout.

setup() {
  # Ambient-state pins (test-hermeticity ratchet). The subject is a read-only file scanner, but the
  # suite also greps handoff-fire.sh and lr-fire-resume.sh, whose gates read the operator's LIVE box:
  # handoff-fire's capacity_gate() (load/core, memory headroom) and capacity-admit's CC_ADMIT_GATE.
  # Both are pinned OFF here for the whole file, the shape tests/lr-fleet.bats:12-13 uses.
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Rule-5 seams: state that does NOT resolve under $HOME. Fixturing $HOME cannot redirect an
  # absolute /tmp default, nor a BARE NAME the subject executes off the operator's PATH — so without
  # these three the watcher cases below would read the operator's live account sweep and run their
  # deployed claude-accounts. ABSENT paths: every one of these sensors fails open on one.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/absent-heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROBE="$REPO/scripts/limit-recover/lr-submit-probe.sh"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # A fixture under $BATS_TEST_TMPDIR still inherits the RUNNER's CLAUDE_CONFIG_DIR, and every
  # limit-recover script resolves its library ladder through it — so an unpinned suite would read
  # the operator's live config dir. Pinned to the fixture, which holds no library at all.
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"

  CFG="$BATS_TEST_TMPDIR/target"; SLUG="-Users-x-thing"
  SID="aaaa1111-0000-4000-8000-000000000001"
  mkdir -p "$CFG/projects/$SLUG"
  TX="$CFG/projects/$SLUG/$SID.jsonl"
  T0="2026-09-19T21:02:00"
  TOK="run:aaaa1111:20260919T210200:9f3c2b71"
}

user_rec()  { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' "$1" "$2" >> "$TX"; }
enqueue()   { printf '{"type":"queue-operation","operation":"enqueue","timestamp":"%s","content":%s}\n' "$1" "$2" >> "$TX"; }

# ── the three verdicts ────────────────────────────────────────────────────────────────────────────

@test "probe: the token in a user record newer than t0 → submitted <ts>" {
  user_rec 2026-09-19T21:04:00.000Z "\"/limit-recover ingest /x $TOK\""
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "submitted 2026-09-19T21:04:00.000Z" ] || { echo "$output"; false; }
}

@test "probe: the token in a queue-operation enqueue → queued <ts> (typed, behind a running turn)" {
  enqueue 2026-09-19T21:03:00.000Z "\"/limit-recover ingest /x $TOK\""
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "queued 2026-09-19T21:03:00.000Z" ] || { echo "$output"; false; }
}

@test "RED-PROOF probe: a <task-notification> user record WITHOUT the token → none" {
  # The exact false positive. This record is a real type:"user" turn, newer than t0, and it makes the
  # session produce an assistant turn — everything today's oracle looks at. It is not our prompt.
  user_rec 2026-09-19T21:05:00.000Z '"<task-notification>A background task finished.</task-notification>"'
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ] || { echo "$output"; false; }
}

@test "probe: submitted OUTRANKS queued — both records exist for every prompt that lands" {
  enqueue  2026-09-19T21:03:00.000Z "\"ingest $TOK\""
  user_rec 2026-09-19T21:04:00.000Z "\"ingest $TOK\""
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$output" = "submitted 2026-09-19T21:04:00.000Z" ] || { echo "$output"; false; }
}

@test "probe: a record OLDER than t0 carrying the token is a PREVIOUS run's — none" {
  user_rec 2026-09-19T20:00:00.000Z "\"ingest $TOK\""
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$output" = "none" ] || { echo "$output"; false; }
}

@test "probe: the token ECHOED in an assistant turn is not a submission" {
  printf '{"type":"assistant","timestamp":"2026-09-19T21:06:00.000Z","message":{"role":"assistant","content":"I see %s in my brief"}}\n' "$TOK" >> "$TX"
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$output" = "none" ] || { echo "$output"; false; }
}

@test "probe: a SIDECHAIN user record is a subagent's, not this session submitting" {
  printf '{"type":"user","isSidechain":true,"timestamp":"2026-09-19T21:04:00.000Z","message":{"role":"user","content":"ingest %s"}}\n' "$TOK" >> "$TX"
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$output" = "none" ] || { echo "$output"; false; }
}

# ── the refusal is not a verdict ──────────────────────────────────────────────────────────────────

@test "RED-PROOF probe: an UNREADABLE transcript is rc 3 with EMPTY stdout — never 'none'" {
  # predicate-refusal-is-not-a-negative: `none` licenses a re-CR into the pane. A refusal that
  # printed `none` would re-type into a session whose state was never read. --separate-stderr is
  # load-bearing here: bats folds stderr into $output by default, and the cause line the refusal
  # prints there would satisfy a naive "stdout is not empty" check.
  run --separate-stderr "$PROBE" "$CFG" "no-such-session" "$T0" "$TOK"
  [ "$status" -eq 3 ]
  [ -z "$output" ] || { echo "stdout was not empty: $output"; false; }
  [[ "$stderr" == *"NOT measured"* ]] || { echo "stderr: $stderr"; false; }
}

@test "probe: a missing token argument is usage (rc 2), not a measurement" {
  run "$PROBE" "$CFG" "$SID" "$T0"
  [ "$status" -eq 2 ]
}

@test "probe: a truncated FIRST line (tail starts mid-record) is skipped, not a parse abort" {
  printf 'estamp":"2026-09-19T21:03:30.000Z","message":{"role":"user","content":"ingest %s"}}\n' "$TOK" > "$TX"
  user_rec 2026-09-19T21:04:00.000Z "\"ingest $TOK\""
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "submitted 2026-09-19T21:04:00.000Z" ] || { echo "$output"; false; }
}

@test "probe: read-only — it mutates nothing it reads" {
  user_rec 2026-09-19T21:04:00.000Z "\"ingest $TOK\""
  before="$(shasum "$TX" | awk '{print $1}')"
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  run "$PROBE" "$CFG" "$SID" "$T0" "$TOK"
  [ "$status" -eq 0 ]
  [ "$(shasum "$TX" | awk '{print $1}')" = "$before" ]
}

# ── the expect program's structure: the acceptance greps ──────────────────────────────────────────

@test "ACCEPTANCE: 'esc to interrupt' is GONE from lr-fire-resume.sh (a screen phrase is not a fact)" {
  run grep -c 'esc to interrupt' "$FIRE"
  [ "$output" = 0 ] || { echo "still present: $output"; false; }
}

@test "ACCEPTANCE: 'shift+tab to cycle' is GONE from LR_RE_READY (0 hits in CC 2.1.260)" {
  run grep -c 'shift+tab to cycle' "$FIRE"
  [ "$output" = 0 ] || { echo "still present: $output"; false; }
}

@test "RED-PROOF: the expect program's post-inject block contains ZERO 'exit' statements" {
  # An `exit` before `interact` kills the TUI and the recovered session with it — the husk this whole
  # project exists to prevent. The block is everything from the inject arm to `interact`.
  # Comments are stripped FIRST: the block's own 🚨 comment names the forbidden statement, and a
  # word-match would convict the warning that exists to prevent it.
  run bash -c 'sed -n "/^  if {\$injected} {/,/^  interact\$/p" "$1" | grep -v "^[[:space:]]*#" | grep -cE "(^|[^_[:alnum:]])exit([^_[:alnum:]]|$)"' _ "$FIRE"
  [ "$output" = 0 ] || { echo "post-inject exits: $output"; false; }
}

@test "the expect program polls lr-submit-probe and never blind-CRs a quiet pty" {
  run grep -c 'LR_PROBE' "$FIRE"
  [ "$output" -ge 2 ] || { echo "the probe is not wired into lr-fire-resume: $output"; false; }
  run grep -c 'READY-NOT-SEEN' "$FIRE"
  [ "$output" -ge 1 ]
}

@test "handoff-fire's resume oracle takes a token" {
  run grep -c 'resume_engaged() { # \$1=target cfg  \$2=sid  \$3=baseline (UTC, %FT%T) \$4=submit token' "$HF"
  [ "$output" = 1 ] || { echo "resume_engaged signature: $output"; false; }
}

# ── the expect program, EXECUTED ──────────────────────────────────────────────────────────────────
#
# These four arms extract the real expect program and RUN it against a stub binary on a real pty,
# because the two things in doubt here are not greppable: whether a quiet pty makes the program ask
# the SCREEN before it types, and whether it can tell OUR prompt landing in the transcript from
# nothing landing at all. A grep for `lr_screen` would pass on a program that never reaches it.
# (The extraction + stub-on-a-pty shape is tests/lr-fire-resume-close-attrib.bats:35-60.)

exp_setup() {
  command -v expect >/dev/null || skip "expect(1) not installed"
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  # `^' ||` as the end anchor, not a bare `^'`: the subject captures expect's rc and falls through to
  # a login shell, so its closing quote line is `' || lr_rc=$?`. A range whose START never matches
  # emits NOTHING, so a stale anchor fails LOUD on the -s check rather than extracting a wrong span.
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed" >&2; return 1; }

  STUB="$BATS_TEST_TMPDIR/stub"
  cat > "$STUB" <<'SH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }
echo "BOOTED"
: > "$LR_TEST_GOT"
while IFS= read -r line; do printf 'GOT:[%s]\n' "$line" >> "$LR_TEST_GOT"; done
exit 0
SH
  chmod +x "$STUB"
  export LR_TEST_GOT="$BATS_TEST_TMPDIR/got"

  # The screen stub. It prints fixture N on call N, then repeats the last one — so a test can say
  # "EMPTY while the prompt is being typed, then our own DRAFT sitting unsubmitted".
  IT2="$BATS_TEST_TMPDIR/it2"
  cat > "$IT2" <<'SH'
#!/bin/bash
n=0
[ -f "$LR_STUB_N" ] && n="$(cat "$LR_STUB_N")"
n=$((n + 1)); printf '%s' "$n" > "$LR_STUB_N"
f="$LR_STUB_DIR/$n.txt"
[ -f "$f" ] || f="$(ls -1 "$LR_STUB_DIR"/*.txt 2>/dev/null | tail -1)"
cat "$f"
SH
  chmod +x "$IT2"
  export LR_STUB_DIR="$BATS_TEST_TMPDIR/screens"; mkdir -p "$LR_STUB_DIR"
  export LR_STUB_N="$BATS_TEST_TMPDIR/screen-n"

  # Everything the program reads. The prompt-answering patterns are pinned to a string the stub never
  # prints, so NO arm fires and the QUIET arm is the only thing that can act — which is the subject.
  export LR_CFG="$CFG" LR_BIN="$STUB" LR_MODEL=m LR_EFFORT=high LR_SID="$SID" LR_ASIS=1 LR_WRAP=""
  export LR_PROMPT="/limit-recover ingest /x $TOK"
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" \
         LR_RE_TRUST="$never" LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" \
         LR_RE_OVERAGE="$never" LR_RE_READY="$never"
  # Seconds, not minutes: every bound the program reads is a seam for exactly this reason.
  export LR_QUIET_S=1 LR_SUBMIT_POLL_S=2 RCY_ENGAGE_TIMEOUT=3
  export LR_IT2="$IT2" LR_PANE=1
  export LR_SCREEN_WANT="$(printf '%s' "$LR_PROMPT" | LC_ALL=C tr -cd '[:print:]' | LC_ALL=C tr -d '[:space:]' | cut -c1-40)"
  # The two exec'd shell programs, taken from the subject itself rather than re-typed here.
  export LR_SCREEN_SH="$(sed -n "/^LR_SCREEN_SH=\"\$(cat <<'LRSCREENSH'\$/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"
  export LR_NOTE_SH="$(sed -n "/^LR_NOTE_SH=\"\$(cat <<'LRNOTESH'\$/,/^LRNOTESH\$/p" "$FIRE" | sed '1d;$d')"
  [ -n "$LR_SCREEN_SH" ] && [ -n "$LR_NOTE_SH" ] || { echo "helper-program extraction failed" >&2; return 1; }
  export LR_PROBE="$REPO/scripts/limit-recover/lr-submit-probe.sh"
  export LR_SUBMIT_TOKEN="$TOK"
  export LR_RUN_DIR="$BATS_TEST_TMPDIR/run"
  export LR_LIB_PATH="$REPO/scripts/limit-recover/lr-lib.sh"
}
screen() { # $1 = call ordinal, $2 = one of empty|menu|mine
  local b='────────────────────────────────' f="$LR_STUB_DIR/$1.txt"
  case "$2" in
    empty) printf '%s\n' "  chrome" "$b" " ❯ " "$b" " ? for shortcuts" > "$f" ;;
    # A REAL resume menu, drawn inside the box the TUI actually paints. The border runs matter: the
    # first version of this fixture had none, so the awk box parse exited 9 and the verdict was
    # UNKNOWN whether or not the `❯<ordinal>` detector existed — the case proved "the screen is not
    # EMPTY", never "a MENU was recognised", and deleting the detector survived. With the box
    # present the parse SUCCEEDS and reads the option lines as a draft, so the detector is the only
    # thing in the program that can produce MENU. Verified standalone on the extracted LR_SCREEN_SH:
    #   no box:   detector present MENU · detector deleted UNKNOWN   (both park — mutant invisible)
    #   this box: detector present MENU · detector deleted DRAFT     (the verdict changes)
    menu)  printf '%s\n' "  Resume a session" "$b" "  ❯ 1. Resume from summary" \
                         "    2. Resume full session as-is" "$b" "  ↑/↓ to select · enter to confirm" > "$f" ;;
    mine)  printf '%s\n' "  chrome" "$b" " ❯ $LR_PROMPT" "$b" " ? for shortcuts" > "$f" ;;
    # A composer holding text that is NOT ours — a human half-typed a command into this pane while
    # the recovery was in flight. Structurally identical to `mine`: same box, same border runs, same
    # prompt glyph. Only the CONTENT differs, which is the whole of the DRAFT / DRAFT-MINE split.
    other) printf '%s\n' "  chrome" "$b" " ❯ git status --porcelain # typed by someone else" "$b" " ? for shortcuts" > "$f" ;;
  esac
}
states() { jq -r '.state' "$LR_RUN_DIR/events.jsonl" 2>/dev/null | tr '\n' ' '; }
# The state alone cannot carry a verdict — READY-NOT-SEEN is the same word for MENU, DRAFT and
# UNKNOWN, which is exactly how the MENU claim went unproven. The DETAIL is where $sv is written.
details() { jq -r '.detail' "$LR_RUN_DIR/events.jsonl" 2>/dev/null | tr '\n' ' '; }

# ── THE ONE PLACE THESE CASES MEET A WALL CLOCK ───────────────────────────────────────────────────
#
# Two different problems live here and conflating them is what made this block unreliable.
#
# 1. `interact` NEVER RETURNS UNLESS STDIN IS AT EOF, and that is not a property of the subject.
#    The program deliberately ends EVERY path at `interact` — an `exit` there closes the master pty
#    and kills the resumed session, which is the husk this project exists to prevent (case 14 pins
#    the count at 0). So under bats the program terminates only if whatever stdin the RUNNER was
#    invoked with happens to be at EOF. Measured 2026-09-20 at load/core ~10: the same case ran to a
#    242 s outer bound and was killed — status 124 — with every behavioural assertion ALREADY
#    satisfied in its output, and returned in 70 s with status 0 once stdin was /dev/null. That is
#    the whole of the "green 4/4 in isolation, 16 reds across three contended runs" signature: the
#    verdict was decided by how bats was invoked. `</dev/null` is the cure, and it is load-invariant.
#
# 2. The program's own budget IS a wall clock — a quiet arm, a 1 s poll loop, and an `exec` per tick
#    — so on a contended box it legitimately takes minutes. A bound sized on a quiet box can only
#    ever convict the box (docs/lessons/bound-must-fit-the-band-not-the-bench.md, and the same
#    correction tests/cc-lr.bats took in 1b2676f4c). So the bound is SCALED by measured load/core,
#    and a kill is JUDGED only below 1.0/core — above that line the elapsed time is printed and the
#    case skips, because a timeout there carries no information about the subject
#    (docs/lessons/environment-falsifiable-precondition-must-skip.md).
#
# Every behavioural assertion stays in the CALLER and unconditional: they run whenever the program
# completed, at any load. Only the wall-clock verdict is banded.
lr_load_per_core() {
  /usr/bin/python3 -c 'import os; print("%.2f" % (os.getloadavg()[0] / (os.cpu_count() or 1)))' \
    2>/dev/null || echo 0
}
lr_expect_run() { # $1 = the QUIET-BOX budget in seconds; scales it to the box this is actually on
  local base="$1" lpc bound t0 t1 elapsed
  lpc="$(lr_load_per_core)"
  bound="$(LC_ALL=C awk -v b="$base" -v l="$lpc" 'BEGIN { m = int(l) + 1; if (m > 8) m = 8; printf "%d", b * m }')"
  t0="$(date +%s)"
  run timeout "$bound" expect -f "$EXP" </dev/null
  t1="$(date +%s)"
  elapsed=$((t1 - t0))
  echo "# expect: ${elapsed}s of a ${bound}s bound at load/core $lpc (quiet-box budget ${base}s)" >&3
  if [ "$status" -eq 124 ]; then
    if [ "$(LC_ALL=C awk -v l="$lpc" 'BEGIN { print (l < 1.0) ? 1 : 0 }')" = 1 ]; then
      echo "the program did not finish inside ${bound}s on a QUIET box (load/core $lpc) — a hang, not contention"
      echo "$output"; return 1
    fi
    skip "killed at the ${bound}s bound with load/core $lpc — above 1.0 a wall-clock verdict is a fact about the BOX, not the subject"
  fi
  [ "$status" -eq 0 ] || { echo "expect exited $status after ${elapsed}s at load/core $lpc"; echo "$output"; return 1; }
}

@test "RED-PROOF quiet arm: READY never matched, composer reads EMPTY → the prompt IS typed" {
  exp_setup
  screen 1 empty
  lr_expect_run 60
  grep -qF "GOT:[/limit-recover ingest /x $TOK]" "$LR_TEST_GOT" || { cat "$LR_TEST_GOT"; false; }
}

@test "RED-PROOF quiet arm: a PARKED MENU is quiet too → NOTHING is sent, and it says so" {
  # A blind CR here takes the menu default — on the resume menu that is "resume from summary",
  # which spends usage and loses the goal. This is the one case a bare `timeout { send \"\\r\" }`
  # could never survive.
  exp_setup
  screen 1 menu
  lr_expect_run 60
  [ ! -s "$LR_TEST_GOT" ] || { echo "something was typed: $(cat "$LR_TEST_GOT")"; false; }
  [[ "$output" == *"READY NEVER SEEN"* ]] || { echo "$output"; false; }
  [[ "$(states)" == *"READY-NOT-SEEN"* ]] || { echo "states: $(states)"; false; }
  # …and it parked because it RECOGNISED A MENU, which is a different fact from "not EMPTY". Without
  # this pair the case was satisfied by UNKNOWN, i.e. by the screen reader failing — see the fixture.
  [[ "$output" == *"the screen reads MENU"* ]] \
    || { echo "parked without recognising the menu: $output"; false; }
  [[ "$(details)" == *"screen reads MENU"* ]] \
    || { echo "the state log did not record the verdict: $(details)"; false; }
}

@test "RED-PROOF submit poll: a user record carrying the run token → state 'submitted'" {
  exp_setup
  screen 1 empty
  # The record the probe must find. Dated far ahead so it is unambiguously newer than the t0 the
  # program captures at spawn — the test is about the TOKEN, not about clock resolution.
  printf '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"role":"user","content":"ingest %s"}}\n' "$TOK" > "$TX"
  lr_expect_run 60
  [[ "$output" == *"SUBMITTED"* ]] || { echo "$output"; false; }
  [[ "$(states)" == *"submitted"* ]] || { echo "states: $(states)"; false; }
}

@test "RED-PROOF submit poll: nothing in the transcript → ONE re-Enter, gated on OUR draft, then FAILED:submit" {
  exp_setup
  screen 1 empty          # quiet arm: safe to type
  screen 2 mine           # poll at the bound: our prompt is still sitting in the composer
  : > "$TX"               # …and nothing ever reaches the transcript
  lr_expect_run 90
  # exactly TWO lines reached the stub: the prompt, and the single re-Enter (an empty line).
  [ "$(wc -l < "$LR_TEST_GOT" | tr -d ' ')" = 2 ] || { cat "$LR_TEST_GOT"; false; }
  [[ "$output" == *"NOT SUBMITTED"* ]] || { echo "$output"; false; }
  [[ "$(states)" == *"FAILED:submit"* ]] || { echo "states: $(states)"; false; }
}

@test "RED-PROOF token oracle: a token that never reached the transcript is NOT engagement" {
  # The failure mode that makes this a strict oracle rather than a filter: the prompt never
  # submitted, so there is nothing for any turn to be an answer TO. Falling back to the wall-clock
  # test here would re-open the hole on exactly the runs where it matters.
  eval "$(sed -n '/^resume_engaged() {/,/^}/p' "$HF")"
  local slug="-Users-x-wt" s="resumed-sess" c="$BATS_TEST_TMPDIR/tgt"
  mkdir -p "$c/projects/$slug"
  printf '%s\n' \
    '{"type":"assistant","timestamp":"2026-09-19T21:06:40.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working on something else entirely"}]}}' \
    > "$c/projects/$slug/$s.jsonl"
  run resume_engaged "$c" "$s" "2026-09-19T21:00:00" "$TOK"
  [ "$status" -eq 1 ]
  # …and with no token the same fixture reads ENGAGED, which is the weaker pre-W3 behaviour kept
  # for a by-hand resume that carries no token at all.
  run resume_engaged "$c" "$s" "2026-09-19T21:00:00"
  [ "$status" -eq 0 ]
}

# ── the __recycle watcher, EXECUTED: the token has to ARRIVE ───────────────────────────────────────
#
# WHY THIS IS NOT A GREP. The assertion this replaces was
# `run grep -c 'RCY_SUBMIT_TOKEN="\${16:-}"' "$HF"` with an expected value of 1 — and the constant in
# it WAS the bug. recycle_fire hands the token to `detach` as the 15th argument after `__recycle`, so
# a watcher reading $16 read an argument nothing ever sends: the token arm was INERT on every run,
# and correcting the source turned the suite RED ("watcher does not parse $16: 0"). A literal pinned
# to a constant can only ever certify whatever is currently written — docs/lessons/
# stale-assertion-becomes-an-inverted-guard.md, the guard that ends up protecting the defect.
#
# So this drives the REAL watcher over the REAL argv shape instead. The token is handed over at the
# position the arming side writes it to, and the one line + ledger row that ONLY the token arm can
# produce (`SUBMITTED`, class `recycle-submitted`) must appear. No constant to drift against.

watcher_setup() {
  # The phase-aware `ps`, the pane stub and the terminal pin are tests/handoff-recycle-engagement.bats
  # :165-247's, trimmed to what a RESUME-mode watcher touches. Only the ROOT query (`-o pid= -t`)
  # advances the phase, so one state read is never answered out of two process tables.
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export PS_COUNT_FILE="$BATS_TEST_TMPDIR/ps-count"; rm -f "$PS_COUNT_FILE"
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in *pgid=*) printf '%s\n' "4242"; exit 0 ;; esac
c="${PS_COUNT_FILE:?}"
if [ "${args#*-o pid= -t}" != "$args" ]; then
  n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$c"
else
  n=$(cat "$c" 2>/dev/null || echo 0)
fi
phase=alive; [ "$n" -le "${PS_DEAD_CALLS:-2}" ] && phase=shell
case "$args" in
  *"-o pid= -t"*)   printf '100\n'; [ "$phase" = alive ] && printf '200\n' ;;
  *"-o tpgid= -t"*) printf '100\n'; [ "$phase" = alive ] && printf '100\n' ;;
  *"-o comm= -t"*)  if [ "$phase" = alive ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)     printf '100 1\n'; [ "$phase" = alive ] && printf '200 100\n' ;;
  *"pid=,comm= -g"*) printf '100 /bin/zsh\n' ;;
  *"-p 200"*)       printf '/Users/chrisren/.claude-220/node_modules/.bin/claude\n' ;;
  *"-p 100"*)       printf '/bin/zsh\n' ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  chmod +x "$SHIM/ps" "$SHIM/osascript"
  unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1; unset CC_TERM

  mkdir -p "$HOME/.claude/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOME/ccnotify-calls.log"\nexit 0\n' \
    > "$HOME/.claude/bin/cc-notify"
  PANE="RECY-PANE"; export STUB_PANE="$PANE"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-RECY-PANE}"
    else printf '%s\n' "${STUB_PANE:-RECY-PANE}"; fi
    exit 0 ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/cc-notify" "$HOME/.claude/bin/it2"
  CMDF="$BATS_TEST_TMPDIR/cmd.sh"; printf 'cd /tmp && claude-x\n' > "$CMDF"
  RUNDIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUNDIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$CC_PROJECTS_DIRS"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/absent-idl.jsonl"
}

# The watcher's argv, written out in the SAME ORDER recycle_fire's `detach` line writes it, so the
# position under test is stated once and read by every case that drives the watcher.
watcher_argv() { # $1 = the submit token to hand over
  printf '%s\n' __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp OLD-SID "" "" "" \
                "$CFG" "$SID" "$T0" "" "$RUNDIR" "$1"
}

@test "RED-PROOF the watcher PARSES the submit token off the argv the arming side actually sends" {
  watcher_setup
  # our prompt lands, and a turn answers it — so the token arm has something to find and the run
  # ends CONFIRMED rather than on the dead path, keeping the assertion about the TOKEN.
  printf '%s\n' \
    "{\"type\":\"user\",\"timestamp\":\"2099-01-01T00:00:00.000Z\",\"message\":{\"role\":\"user\",\"content\":\"/limit-recover ingest /x $TOK\"}}" \
    '{"type":"assistant","timestamp":"2099-01-01T00:01:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"reading the salvage bundle"}]}}' \
    > "$TX"
  local -a argv; mapfile -t argv < <(watcher_argv "$TOK")
  run env HOME="$HOME" PATH="$SHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
      PS_DEAD_CALLS=2 RCY_ENGAGE_TIMEOUT=8 RCY_ENGAGE_INTERVAL=1 \
      RCY_BOOT_PANE_EVERY=1 RCY_BOOT_IVL_S=0.2 RCY_BOOT_WAIT_S=20 \
      bash "$HF" "${argv[@]}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the line and the row that ONLY the token arm can produce
  [[ "$output" == *"SUBMITTED in $PANE"* ]] || { echo "the token never reached the watcher: $output"; false; }
  grep -F '"class":"recycle-submitted"' "$HOME/.claude/logs/handoffs.jsonl" >/dev/null \
    || { echo "no recycle-submitted row"; cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
}

# ── the ARMING side: the token has to be PUT on the argv, and only when the prompt can deliver it ──

@test "RED-PROOF the arming side PUTS the token on the detach argv — captured, then FED to the watcher" {
  # D1 fixed the watcher's END of the wire; nothing asserted the arming end. Removing
  # "$RCY_SUBMIT_TOKEN_ARG" from recycle_fire's detach line survived 37 of 37 mutants, because every
  # other case hands the watcher an argv the TEST wrote. This one executes the REAL detach line with
  # a recorder in place of detach, then feeds the captured argv to the REAL watcher — so the two ends
  # are proved against each other rather than each against a constant of its own.
  watcher_setup
  printf '%s\n' \
    "{\"type\":\"user\",\"timestamp\":\"2099-01-01T00:00:00.000Z\",\"message\":{\"role\":\"user\",\"content\":\"/limit-recover ingest /x $TOK\"}}" \
    '{"type":"assistant","timestamp":"2099-01-01T00:01:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"reading the salvage bundle"}]}}' \
    > "$TX"
  dl="$(sed -n '/^  WATCHER_PID="\$(detach "\$log"/p' "$HF")"
  [ -n "$dl" ] || { echo "the detach invocation could not be located in $HF — the anchor is stale"; false; }
  case "$dl" in *__recycle*) ;; *) echo "extracted the wrong line: $dl"; false ;; esac

  ARGV="$BATS_TEST_TMPDIR/argv"
  cat > "$BATS_TEST_TMPDIR/arm.sh" <<'SH'
set -u
# drop detach's own two leading arguments (the log and "$0"); what remains IS the watcher's argv
detach() { shift 2; printf '%s\n' "$@" > "$ARGV_FILE"; echo 1234; }
log=/dev/null
tty=/dev/ttys999
cmdfile="$A_CMDF"
LAUNCH_DIR=/tmp
SID="$A_PANE"
rcy_old_sid=OLD-SID
RECYCLE_MARKER=""
FIRE_GOAL=""
PROMPT_FILE=""
RESUME_CFG="$A_CFG"
RESUME_LAUNCHER="$A_RUNDIR/launcher.sh"
RCY_SOURCE_SESSION="$A_SID"
RCY_T0="$A_T0"
RCY_SRC_TX=""
RCY_RUN_DIR_ARG="$A_RUNDIR"
RCY_SUBMIT_TOKEN_ARG="$A_TOK"
eval "$A_DETACH_LINE"
SH
  run env ARGV_FILE="$ARGV" A_CMDF="$CMDF" A_PANE="$PANE" A_CFG="$CFG" A_SID="$SID" \
      A_T0="$T0" A_RUNDIR="$RUNDIR" A_TOK="$TOK" A_DETACH_LINE="$dl" \
      bash "$BATS_TEST_TMPDIR/arm.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$ARGV" ] || { echo "the detach recorder captured no argv"; false; }

  local -a argv; mapfile -t argv < "$ARGV"
  local seen=0 a
  for a in "${argv[@]}"; do [ "$a" = "$TOK" ] && seen=$((seen + 1)); done
  [ "$seen" = 1 ] || { echo "the token appears $seen time(s) on the detach argv:"; cat "$ARGV"; false; }

  # …and the watcher, handed EXACTLY that argv, must read it. This is the half a position assertion
  # cannot make: an index is only correct relative to what the other end writes.
  run env HOME="$HOME" PATH="$SHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
      PS_DEAD_CALLS=2 RCY_ENGAGE_TIMEOUT=8 RCY_ENGAGE_INTERVAL=1 \
      RCY_BOOT_PANE_EVERY=1 RCY_BOOT_IVL_S=0.2 RCY_BOOT_WAIT_S=20 \
      bash "$HF" "${argv[@]}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"SUBMITTED in $PANE"* ]] \
    || { echo "the argv the arming side actually builds does not carry the token to the watcher: $output"; false; }
}
@test "RED-PROOF the arming gate SUPPRESSES a token the relaunch PROMPT cannot deliver" {
  # The 2-occurrence precondition is what makes this half safe to land before lr-handoff's: the
  # oracle reads "no user record carries this token" as NOT ENGAGED, so a token that lives only in
  # the launcher's export block — never in the prompt, never in the transcript — would convict every
  # healthy recycle. Lowering the gate to `-lt 1` survived the mutation pass in substance: nothing
  # executed it. This does, on both sides of the boundary.
  blk="$(sed -n '/^  RCY_SUBMIT_TOKEN_ARG=""$/,/^  fi$/p' "$HF")"
  [ -n "$blk" ] || { echo "the arming block could not be located in $HF — the anchor is stale"; false; }
  case "$blk" in *rcy_tok_n*) ;; *) echo "extracted the wrong span:"; printf '%s\n' "$blk"; false ;; esac

  L="$BATS_TEST_TMPDIR/launcher.sh"
  # ONE occurrence: the export only. The prompt cannot deliver it, so it must NOT be handed over.
  printf 'export LR_SUBMIT_TOKEN=%s\nexec claude-x --model m\n' "$TOK" > "$L"
  run bash -c 'RESUME_LAUNCHER="$1"; eval "$2"; printf "TOKEN=[%s]\n" "$RCY_SUBMIT_TOKEN_ARG"' _ "$L" "$blk"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"TOKEN=[]"* ]] \
    || { echo "a token the prompt cannot deliver was handed to the oracle: $output"; false; }
  [[ "$output" == *"does not carry this run's submit token"* ]] \
    || { echo "the fallback to the wall-clock oracle was SILENT: $output"; false; }

  # TWO occurrences — the export AND the prompt: the run is measured properly and says nothing.
  printf 'export LR_SUBMIT_TOKEN=%s\nexec claude-x --model m --prompt "/limit-recover ingest /x %s"\n' "$TOK" "$TOK" > "$L"
  run bash -c 'RESUME_LAUNCHER="$1"; eval "$2"; printf "TOKEN=[%s]\n" "$RCY_SUBMIT_TOKEN_ARG"' _ "$L" "$blk"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"TOKEN=[$TOK]"* ]] \
    || { echo "a launcher carrying the token in BOTH places was still degraded: $output"; false; }
  ! [[ "$output" == *"does not carry"* ]] || { echo "warned on a launcher that does carry it: $output"; false; }
}

# ── the poll's DEFAULT interval, which no test could see because every test overrides it ──────────

@test "RED-PROOF the watcher's DEFAULT poll interval polls once a second, not once per five" {
  # RCY_ENGAGE_INTERVAL's default was 5 before W3 and is 1 now, and the mutation pass put it back
  # without a single case noticing: every watcher case passes the variable as a knob, so the only
  # value production ever uses is the one nothing executes. The default is not a tuning — it is the
  # QUANTUM of `rcy_t`, the one number the recycle-engaged ledger row carries about how long
  # engagement took, and it is also the latency added to every recovery before the first look.
  #
  # Asserted by COUNTING REAL POLLS, not by grepping the literal: a count is what the default MEANS,
  # and it is load-invariant (a loop count, never a wall clock). The seam is `$0` — the probe is
  # resolved as `$(dirname "$0")/limit-recover/lr-submit-probe.sh`, so invoking the real script
  # THROUGH A SYMLINK re-points that one sibling at a counting stub while HF_DIR (which resolves the
  # link) keeps every other sibling pointed at the real tree. Same mechanism as
  # docs/lessons/symlinked-0-splits-sibling-sources.md, used deliberately.
  watcher_setup
  : > "$TX"                                   # nothing ever submits → the loop runs to its bound
  HFLINK="$BATS_TEST_TMPDIR/hf"; mkdir -p "$HFLINK/limit-recover"
  ln -s "$HF" "$HFLINK/handoff-fire.sh"
  ln -s "$REPO/scripts/lib" "$HFLINK/lib"
  ln -s "$REPO/scripts/limit-recover/lr-lib.sh" "$HFLINK/limit-recover/lr-lib.sh"
  POLLS="$BATS_TEST_TMPDIR/probe-calls"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nprintf "none\\n"\n' "$POLLS" \
    > "$HFLINK/limit-recover/lr-submit-probe.sh"
  chmod +x "$HFLINK/limit-recover/lr-submit-probe.sh"

  local -a argv; mapfile -t argv < <(watcher_argv "$TOK")
  # RCY_ENGAGE_INTERVAL is UNSET here, deliberately — that is the whole subject of the case.
  run env -u RCY_ENGAGE_INTERVAL HOME="$HOME" PATH="$SHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
      PS_DEAD_CALLS=2 RCY_ENGAGE_TIMEOUT=4 \
      RCY_BOOT_PANE_EVERY=1 RCY_BOOT_IVL_S=0.2 RCY_BOOT_WAIT_S=20 \
      bash "$HFLINK/handoff-fire.sh" "${argv[@]}"
  [ "$status" -eq 1 ] || { echo "$output"; false; }   # never engaged — the dead path, as intended
  [ -s "$POLLS" ] || { echo "the probe was never resolved through the symlinked \$0 — the seam is stale"; false; }
  local n; n="$(wc -l < "$POLLS" | tr -d ' ')"
  # 4 s of window at one poll a second = 4 polls; at five seconds a poll it is exactly 1.
  [ "$n" -ge 4 ] || { echo "the 4s engagement window was polled $n time(s) — the default interval is coarser than 1s"; false; }
}

# ── deviation 3, executed: the re-Enter is gated on OUR draft, never on "a draft" ─────────────────

@test "RED-PROOF re-CR gate: a composer holding SOMEONE ELSE'S text is never submitted on our behalf" {
  # The author's own declared deviation from the spec — the spec says "a screen read shows the prompt
  # text sitting in the composer", the implementation demands DRAFT-MINE — and the only safety
  # property in this file that no case exercised: widening the gate to `DRAFT-MINE || DRAFT` survived
  # the mutation pass, because every existing case shows the screen EMPTY, a MENU, or our own prompt.
  #
  # What the widened gate does is press Enter on a stranger's half-typed line. In the pane this runs
  # in, that line is a shell command or a slash command someone was composing, and submitting it is a
  # write into a live session on behalf of a person who never pressed the key.
  exp_setup
  screen 1 empty          # quiet arm: the composer is clear, so our prompt IS typed
  screen 2 other          # at the poll bound: a human's text is sitting there instead
  : > "$TX"               # …and nothing of ours ever reaches the transcript
  lr_expect_run 90
  # exactly ONE line reached the stub — our prompt. The re-Enter was NOT sent.
  [ "$(wc -l < "$LR_TEST_GOT" | tr -d ' ')" = 1 ] \
    || { echo "a CR was sent over someone else's composer text:"; cat "$LR_TEST_GOT"; false; }
  [[ "$output" == *"the composer reads DRAFT, not our prompt — NOT re-sending Enter"* ]] \
    || { echo "the refusal did not name what it saw: $output"; false; }
  # …and the run does NOT record a re-CR it never sent
  [[ "$(states)" != *"SUBMIT-RECR"* ]] || { echo "states claim a re-CR was sent: $(states)"; false; }
}

# ── the refusal, one layer up: a predicate that REFUSES must not read as a clean "no" ─────────────

@test "RED-PROOF an UNREADABLE transcript is NOT MEASURED in the expect program either, never 'none'" {
  # Case 8 pins the shell probe's end of this: rc 3, empty stdout, a cause line on stderr. Nothing
  # pinned the CONSUMER's mapping of it, and mapping `unreadable` to `none` in the Tcl survived the
  # mutation pass — so the distinction the probe's own header calls load-bearing died one layer up,
  # silently, exactly where it costs something.
  #
  # `none` is the one verdict that LICENSES A KEYSTROKE. Read a refusal as `none` and the program
  # presses Enter into a pane whose transcript it could not read, and then records FAILED:submit —
  # a measured negative for a question that was never answered. NOT MEASURED is neither a failure
  # nor a success and must say so (memory predicate-refusal-is-not-a-negative;
  # predicate-error-exit-is-indistinguishable-from-false).
  exp_setup
  screen 1 empty          # quiet arm: our prompt IS typed
  screen 2 mine           # …and our own draft is sitting there, so a `none` reading WOULD re-CR
  # The refusal, induced the way case 8 induces it: a sid with no transcript under $LR_CFG.
  export LR_SID="no-such-session-for-the-probe"
  lr_expect_run 90
  [ "$(wc -l < "$LR_TEST_GOT" | tr -d ' ')" = 1 ] \
    || { echo "a keystroke was sent on the strength of a refusal:"; cat "$LR_TEST_GOT"; false; }
  [[ "$output" == *"submission NOT MEASURED"* ]] \
    || { echo "the refusal was not reported as unmeasured: $output"; false; }
  [[ "$(states)" == *"INDETERMINATE:submit"* ]] || { echo "states: $(states)"; false; }
  [[ "$(states)" != *"FAILED:submit"* ]] \
    || { echo "a refusal was recorded as a measured submission failure: $(states)"; false; }
}
