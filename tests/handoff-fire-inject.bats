#!/usr/bin/env bats
# Regression guard for handoff-fire.sh RELIABLE LAUNCH-COMMAND INJECTION (INC ttys018, 2026-07-19).
#
# The incident: a fire's launch command `cd <cwd> && <launcher> … "$(cat <prompt-file>)"` was typed
# into a fresh split pane as a raw async_send_text char-stream, which raced the target zsh's ZLE
# (zsh-autosuggestions + zsh-syntax-highlighting per-keystroke widgets + `setopt CORRECT`). Characters
# transposed (`cd` → `ould ocd`), CORRECT held the mangled word at a [nyae] prompt, and the tail of
# the line — including the `"$(cat …)"` — spilled out of its quotes so the brief flooded the shell as
# raw commands. The launcher never started; the worker was left task-less.
#
# The durable invariants this file locks down (the 2 composed defenses in it2_type_verified):
#   1. BRACKETED PASTE — the command is sent wrapped in ESC[200~ … ESC[201~ (atomic literal insert,
#      no per-keystroke ZLE widget can corrupt it), never as a bare char-stream;
#   2. ECHO-VERIFY before submit — the pane is read back and the intact command confirmed on the input
#      line BEFORE any CR. The load-bearing safety property: a line that does NOT verify is NEVER
#      submitted (no Enter), so a mangled command can never execute.
# Plus: graceful degradation (final attempt falls back to a plain send, still echo-gated) and the
# multi-line RESEND helper (it2_paste_submit_verified) pastes-then-submits atomically (no
# line-by-line flood) after proving the composer holds exactly that paste.
#
# Functions are extracted from the real script (same technique as handoff-splitright.bats). REAL_IT2
# is stubbed with a fake it2 that RECORDS every `session send` as an event (CTRLU / CR / PASTE / PLAIN)
# and serves a configurable `session read` echo — "perfect" (echoes what was pasted), "garbage" (never
# matches → corruption), "corrupt-once" (garbage first read then good) and "only-plain" (matches only a
# plain send → drives the fallback). The mode is switched per-test via a file the mock reads.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # handoff-fire.sh bounds every external iTerm2 call (osascript / it2 CLI / iterm2 python) through
  # hf_bounded — a timeout(1) wrapper — because a wedged iTerm2 API blocks them indefinitely. These
  # suites EXTRACT individual functions instead of sourcing the script, so that helper is not in
  # scope and an extracted function would die with "hf_bounded: command not found". A passthrough
  # keeps the extracted behaviour byte-identical and deterministic; the helper's OWN semantics
  # (bound applied, expiry -> 124, set-but-empty disable seam) are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  EVENTS="$BATS_TEST_TMPDIR/events"; : > "$EVENTS"
  SCREEN="$BATS_TEST_TMPDIR/screen"; : > "$SCREEN"
  MODE_FILE="$BATS_TEST_TMPDIR/mode"; printf 'perfect' > "$MODE_FILE"
  FIRSTPASTE="$BATS_TEST_TMPDIR/firstpaste"; rm -f "$FIRSTPASTE"
  LASTTYPE="$BATS_TEST_TMPDIR/lasttype"; : > "$LASTTYPE"
  SEEN="$BATS_TEST_TMPDIR/seen"; rm -f "$SEEN"
  # ALLPASTES records EVERY paste (one per line) so a test can assert across attempts — the
  # per-attempt nonce is only checkable by comparing attempt N's wire against attempt N-1's.
  ALLPASTES="$BATS_TEST_TMPDIR/allpastes"; : > "$ALLPASTES"
  # RESIDUE drives the `residue` read-mode: a screen holding stale evidence of success (a copy of the
  # command left by an EARLIER failed attempt) while the real input line holds something else.
  RESIDUE="$BATS_TEST_TMPDIR/residue"; : > "$RESIDUE"

  FAKE_IT2="$BATS_TEST_TMPDIR/it2"
  # Expanding heredoc — bake the record paths in; the mock stays mode-driven via $MODE_FILE.
  cat > "$FAKE_IT2" <<SH
#!/usr/bin/env bash
EVENTS='$EVENTS'; SCREEN='$SCREEN'; MODE_FILE='$MODE_FILE'
FIRSTPASTE='$FIRSTPASTE'; LASTTYPE='$LASTTYPE'; SEEN='$SEEN'
ALLPASTES='$ALLPASTES'; RESIDUE='$RESIDUE'
SH
  cat >> "$FAKE_IT2" <<'SH'
ESC=$'\x1b'; BPS="${ESC}[200~"; BPE="${ESC}[201~"; CU=$'\x15'; CR=$'\r'
mode="perfect"; [ -f "$MODE_FILE" ] && mode="$(cat "$MODE_FILE")"
sub="${1:-}"; verb="${2:-}"
if [ "$sub" = session ] && [ "$verb" = send ]; then
  shift 2; text=""
  while [ $# -gt 0 ]; do case "$1" in -s) shift 2 ;; *) text="$1"; shift ;; esac; done
  if [ "$text" = "$CU" ]; then
    printf 'CTRLU\n' >> "$EVENTS"; : > "$SCREEN"; printf 'CTRLU' > "$LASTTYPE"
  elif [ "$text" = "$CR" ]; then
    printf 'CR\n' >> "$EVENTS"; printf 'CR' > "$LASTTYPE"
  else
    case "$text" in
      "${BPS}"*"${BPE}")
        [ -f "$FIRSTPASTE" ] || printf '%s' "$text" > "$FIRSTPASTE"
        inner="${text#"$BPS"}"; inner="${inner%"$BPE"}"
        printf '%s\n' "$inner" >> "$ALLPASTES"
        printf 'PASTE\n' >> "$EVENTS"; printf '%s' "$inner" > "$SCREEN"; printf 'PASTE' > "$LASTTYPE" ;;
      *)
        printf '%s\n' "$text" >> "$ALLPASTES"
        printf 'PLAIN\n' >> "$EVENTS"; printf '%s' "$text" > "$SCREEN"; printf 'PLAIN' > "$LASTTYPE" ;;
    esac
  fi
  exit 0
fi
if [ "$sub" = session ] && [ "$verb" = read ]; then
  case "$mode" in
    garbage)      printf 'zsh: correct ould ocd? [nyae]\n' ;;
    corrupt-once) if [ -f "$SEEN" ]; then cat "$SCREEN" 2>/dev/null; else : > "$SEEN"; printf 'ould ocd garbage\n'; fi ;;
    only-plain)   if [ "$(cat "$LASTTYPE" 2>/dev/null)" = PLAIN ]; then cat "$SCREEN" 2>/dev/null; else printf 'not-a-match\n'; fi ;;
    residue)      cat "$RESIDUE" 2>/dev/null ;;
    *)            cat "$SCREEN" 2>/dev/null ;;
  esac
  exit 0
fi
exit 0
SH
  chmod +x "$FAKE_IT2"

  # Fast timings for tests.
  export FIRE_TYPE_SETTLE=0.01 FIRE_TYPE_PRESETTLE=0.001 FIRE_TYPE_ATTEMPTS=4 FIRE_TYPE_READLINES=20

  # Extract the bracketed-paste markers + the helpers under test from the real script.
  eval "$(grep -E '^BP_(START|END)=' "$HF")"
  eval "$(grep -E "^FIRE_NOCORRECT_LINE=" "$HF")"
  eval "$(sed -n '/^_it2_type_line() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^it2_type_verified() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^_paste_newlines() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^paste_readback_expect() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^paste_readback_ok() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^it2_paste_submit_verified() {/,/^}/p' "$HF")"
  export FIRE_PASTE_PREWAIT=0 FIRE_PASTE_PREIVL=0.01

  CMD='cd /private/tmp/wt-x && claude3 --effort max "$(cat /tmp/fire-abc.txt)"'
}

set_mode() { printf '%s' "$1" > "$MODE_FILE"; }

# The verified paste reads the COMPOSER twice — a proven-empty pre-check, then the read-back — and
# this suite's fake it2 serves a raw echo of the wire, not an Ink input box. So composer_content is
# stubbed here rather than driven: its parse is another suite's subject entirely
# (tests/handoff-composer-gate.bats), and what these tests are about is the paste mechanics.
# The phase counter is a FILE because composer_content runs inside $(…) — a shell counter would
# increment in a subshell and every read would serve the pre screen forever.
stub_composer() {   # $1 = the read-back the SECOND read should show (space-stripped); pre = EMPTY
  CPOST="$1"; CPHASE="$BATS_TEST_TMPDIR/cphase"; : > "$CPHASE"
  composer_content() {
    echo r >> "$CPHASE"
    if [ "$(wc -l < "$CPHASE")" -le 1 ]; then printf ''; else printf '%s' "$CPOST"; fi
    return 0
  }
}

# What the composer SHOWS for a payload — the measured rule, mirrored here so a fixture cannot
# quietly disagree with the oracle it is testing (>800 chars or >2 newlines ⇒ placeholder).
readback_of() {  # $1 = payload → the space-stripped composer content CC would render
  local t="$1" nl; nl="$(_paste_newlines "$t")"
  if [ "${#t}" -gt 800 ] || [ "$nl" -gt 2 ]; then
    if [ "$nl" -gt 0 ]; then printf '[Pastedtext#1+%slines]' "$nl"; else printf '[Pastedtext#1]'; fi
  else
    printf '%s' "$t" | LC_ALL=C tr -cd '[:print:]' | LC_ALL=C tr -d '[:space:]'
  fi
}

@test "it2_type_verified: happy path — bracketed-pastes, verifies the echo, THEN submits" {
  set_mode perfect
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^PASTE$' "$EVENTS"
  grep -q '^CR$' "$EVENTS"
  # PASTE must precede CR (never submit before the command is on the line).
  [ "$(grep -nE '^(PASTE|CR)$' "$EVENTS" | head -1)" = "$(grep -n '^PASTE$' "$EVENTS" | head -1)" ]
}

@test "it2_type_verified: the command is wrapped in bracketed-paste markers, inner intact" {
  set_mode perfect
  # FIRE_NOCORRECT=0 isolates the launch line: with the disarm pre-line on, the FIRST paste is the
  # disarm line, not the command. What must hold is that the command survives the wire INTACT.
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  [ -f "$FIRSTPASTE" ]
  local wire; wire="$(cat "$FIRSTPASTE")"
  # Both bracketed-paste markers are present and the payload sits strictly between them.
  [ "${wire#"$BP_START"}" != "$wire" ]
  [ "${wire%"$BP_END"}" != "$wire" ]
  local inner="${wire#"$BP_START"}"; inner="${inner%"$BP_END"}"
  # The wire is the nonce anchor + the command, and the COMMAND SUFFIX IS BYTE-EXACT — the anchor
  # prefixes, it never rewrites (a prefix that mangled the command would be worse than no anchor).
  [ "${inner%"$CMD"}" != "$inner" ]
  [[ "$inner" =~ ^:\ hfv-[0-9]+-1-[0-9]+\;\  ]] || false
  # And what the terminal "echoed" (mock SCREEN) still carries the command intact.
  case "$(cat "$SCREEN")" in *"$CMD") : ;; *) false ;; esac
}

@test "it2_type_verified: SAFETY — a non-verifying echo is NEVER submitted (no CR), fails loud" {
  set_mode garbage
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -ne 0 ]                      # fail-loud
  ! grep -q '^CR$' "$EVENTS" || false      # the load-bearing invariant: no Enter on an unverified line
  grep -q '^PASTE$' "$EVENTS"              # it DID try (bracketed paste)
  grep -q '^CTRLU$' "$EVENTS"              # and scrubbed the mangled line
}

@test "it2_type_verified: recovers on retry when the first echo is corrupt" {
  set_mode corrupt-once
  # FIRE_NOCORRECT=0: otherwise the disarm pre-line consumes the single "corrupt" read and the LAUNCH
  # line would never exercise the recovery this test names.
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^CR$' "$EVENTS"                 # eventually submits after a clean re-verify
  [ "$(grep -c '^PASTE$' "$EVENTS")" -ge 2 ]   # took at least two paste attempts
}

@test "it2_type_verified: final attempt falls back to a plain send, still echo-gated" {
  set_mode only-plain
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^PLAIN$' "$EVENTS"              # degraded to an un-bracketed send on the last attempt
  grep -q '^CR$' "$EVENTS"                 # still only after echo-verify passed
  [ "$(grep -c '^PASTE$' "$EVENTS")" -ge 3 ]   # tried bracketed paste first (attempts 1..N-1)
}

@test "it2_type_verified: an empty command is refused (never blindly submits)" {
  run it2_type_verified "$FAKE_IT2" SID ""
  [ "$status" -ne 0 ]
  ! grep -q '^CR$' "$EVENTS"
}

@test "it2_paste_submit_verified: pastes the multi-line brief atomically then submits (no flood)" {
  composer_owned() { return 0; }          # ownership PROVEN — this test is about the paste mechanics
  local brief=$'first line of brief\nsecond line: run the gate\n<!-- marker HANDOFF-ENGAGE-x -->'
  stub_composer "$(readback_of "$brief")"
  run it2_paste_submit_verified "$FAKE_IT2" SID "$brief"
  [ "$status" -eq 0 ]
  # Exactly one PASTE then one CR — the brief never goes out as line-by-line commands.
  [ "$(grep -cE '^(PASTE|PLAIN)$' "$EVENTS")" -eq 1 ]
  grep -q '^PASTE$' "$EVENTS"
  grep -q '^CR$' "$EVENTS"
  [ "$(cat "$FIRSTPASTE")" = "${BP_START}${brief}${BP_END}" ]
}

# ---- D1: the echo-verify must not be satisfiable by evidence from an EARLIER failure -------------
# The defect (item b3d1a77c75ae): want= was a fixed, space-stripped substring searched over the WHOLE
# 500-line screen with no anchor to the current input line, so a copy of the command left in the
# scrollback by a previous failed attempt satisfied the check while the input line held a mangled
# fragment — and the CR then executed the fragment. Verification and the thing verified were
# different surfaces (memory: claimed-outcome-vs-checked-outcome).

@test "it2_type_verified: RED-PROOF — scrollback residue of THIS command never satisfies the verifier" {
  # The screen carries a full, intact copy of the command (an earlier fire into this pane) ABOVE a
  # wedged autocorrect prompt. The current input line is NOT the command. This is the incident shape.
  printf '%s\n%s\n' "$CMD" "zsh: correct 'go' to 'god' [nyae]?" > "$RESIDUE"
  set_mode residue
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -ne 0 ]                      # fails loud
  ! grep -q '^CR$' "$EVENTS" || false      # THE INVARIANT: residue must never buy an Enter
}

@test "it2_type_verified: POSITIVE CONTROL — that residue WOULD have passed the pre-fix predicate" {
  # Proves the RED-PROOF above is not vacuous: the pre-fix check was `grep -qF <space-stripped CMD>`
  # over the space-stripped screen, and this exact residue satisfies it.
  printf '%s\n%s\n' "$CMD" "zsh: correct 'go' to 'god' [nyae]?" > "$RESIDUE"
  local prefix_want screen
  prefix_want="$(printf '%s' "$CMD" | tr -d '[:space:]')"
  screen="$(tr -d '[:space:]' < "$RESIDUE")"
  printf '%s' "$screen" | grep -qF -- "$prefix_want"
}

@test "it2_type_verified: every attempt carries a DISTINCT anchor (attempt N-1 cannot satisfy N)" {
  set_mode garbage                         # never verifies → burns all attempts, recording each wire
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -ne 0 ]
  local total uniq
  total="$(grep -c . "$ALLPASTES")"
  uniq="$(sed -E 's/^(: hfv-[^;]*);.*/\1/' "$ALLPASTES" | sort -u | grep -c .)"
  [ "$total" -ge 2 ]                       # more than one attempt actually happened
  [ "$uniq" -eq "$total" ]                 # …and no two attempts shared an anchor
}

# ---- (c): spell-correction is disarmed BEFORE the launch command is typed ------------------------

@test "it2_type_verified: the disarm line is accepted BEFORE the launch command" {
  set_mode perfect
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  # Two accepted lines, disarm first: the CR that submits the launch line comes after the one that
  # submitted the disarm line, so CORRECT is already off when the launcher is read.
  [ "$(grep -c '^CR$' "$EVENTS")" -eq 2 ]
  grep -q 'unsetopt correct correct_all' "$ALLPASTES"
  [ "$(grep -n 'unsetopt correct correct_all' "$ALLPASTES" | head -1 | cut -d: -f1)" -lt \
    "$(grep -n -F "$CMD" "$ALLPASTES" | head -1 | cut -d: -f1)" ]
}

@test "it2_type_verified: the disarm line is itself echo-verified (never blindly submitted)" {
  set_mode garbage                         # nothing verifies
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -ne 0 ]
  grep -q 'unsetopt correct correct_all' "$ALLPASTES"   # it WAS attempted (else this asserts nothing)
  ! grep -q '^CR$' "$EVENTS" || false      # a mangled `unsetopt` is correctable too — it gets no Enter
}

@test "it2_type_verified: FIRE_NOCORRECT=0 disables the disarm line (a seam that cannot turn off is not a seam)" {
  # A seam can only be proven OFF against a tree where it can be ON: assert the feature exists first,
  # else this passes trivially on any tree that never had a disarm line.
  [ -n "$FIRE_NOCORRECT_LINE" ]
  set_mode perfect
  FIRE_NOCORRECT=0 run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^CR$' "$EVENTS")" -eq 1 ]
  ! grep -q 'unsetopt' "$ALLPASTES" || false
}

@test "the disarm line types no word zsh could offer to correct" {
  # Same discipline as handoff-fire-typed-cmd-correctable.bats: every COMMAND WORD must always
  # resolve. `unsetopt` and `true` are zsh builtins; arguments are exempt without CORRECT_ALL.
  [ -n "$FIRE_NOCORRECT_LINE" ]
  local w norm
  norm="${FIRE_NOCORRECT_LINE//[|;]/$'\n'}"      # split on every command separator
  for w in $(printf '%s\n' "$norm" | awk 'NF{print $1}'); do
    case "$w" in
      unsetopt|true) : ;;
      *) printf 'correctable command word in the disarm line: %s\n' "$w" >&2; false ;;
    esac
  done
}

# ---- D2: the RESEND is gated on POSITIVE proof that CC owns the pane -----------------------------
# The defect: the resend helper sent CR with no verification of any kind, on the assumption that the
# target is Ink's composer. verify_engagement calls it EXACTLY on the path where engagement was not
# observed — i.e. precisely when CC may never have taken the pane and the target is still a shell.
#
# THE HELPER CHANGED, THE PROPERTY DID NOT (a771a1611d28, 2026-08-24). The resend used to call
# `it2_paste_submit`: ownership-gated after b3d1a77c75ae, but content-blind — it pasted and pressed
# Enter without ever reading the composer back. It was migrated onto it2_paste_submit_verified and
# then DELETED, so these tests moved with it. Two consequences to read the assertions with: the
# ownership abstention now returns 2 rather than 1 (the verified form spends 1 on a failed send),
# and a proven-owned pane must ALSO read back before any CR.

@test "it2_paste_submit_verified: RED-PROOF — unproven ownership ABSTAINS (no paste, no CR) and is loud" {
  composer_owned() { return 1; }           # the pane is (or may be) still a shell
  local brief=$'run the gate\nthen land'
  run it2_paste_submit_verified "$FAKE_IT2" SID "$brief"
  [ "$status" -eq 2 ]
  ! grep -qE '^(PASTE|PLAIN)$' "$EVENTS" || false   # nothing is left sitting in a shell's buffer…
  ! grep -q '^CR$' "$EVENTS" || false               # …and above all, no Enter
  printf '%s\n' "$output" | grep -q 'ABSTAINED'     # named, never silent
}

@test "it2_paste_submit_verified: POSITIVE CONTROL — proven ownership pastes, reads back, submits" {
  composer_owned() { return 0; }
  stub_composer "$(readback_of brief)"
  run it2_paste_submit_verified "$FAKE_IT2" SID "brief"
  [ "$status" -eq 0 ]
  grep -q '^PASTE$' "$EVENTS"
  grep -q '^CR$' "$EVENTS"
}

@test "it2_paste_submit_verified: a proven-owned pane whose read-back DISAGREES gets no CR" {
  # The half the ownership gate never covered: CC owns the pane, and something else is in the
  # composer anyway. This is the fire path's own race — the operator typing into the pane the
  # resend is about to paste into — and it is why ownership alone was never enough.
  composer_owned() { return 0; }
  stub_composer "somethingelseentirely"
  run it2_paste_submit_verified "$FAKE_IT2" SID "brief"
  [ "$status" -eq 4 ]
  grep -q '^PASTE$' "$EVENTS"
  ! grep -q '^CR$' "$EVENTS" || false
}

@test "it2_paste_submit_verified: CC_FIRE_COMPOSER_GATE=off is a real escape hatch" {
  composer_owned() { return 1; }
  stub_composer "$(readback_of brief)"
  # Prove the gate is LIVE first — otherwise "the switch turned it off" is indistinguishable from
  # "there was never a gate", and this test would certify a tree with no gate at all.
  run it2_paste_submit_verified "$FAKE_IT2" SID "brief"
  [ "$status" -eq 2 ]
  : > "$EVENTS"; stub_composer "$(readback_of brief)"
  CC_FIRE_COMPOSER_GATE=off run it2_paste_submit_verified "$FAKE_IT2" SID "brief"
  [ "$status" -eq 0 ]
  grep -q '^CR$' "$EVENTS"
}

# ---- D2: the oracle itself -----------------------------------------------------------------------

# composer_owned composes three existing predicates; each is stubbed here so the OR-structure and the
# fail-closed default are what get tested. `ps` is stubbed on PATH so the tty leg runs against a
# synthetic process table — the shapes are the ones measured live on this box.
setup_oracle() {
  eval "$(sed -n '/^composer_owned() {/,/^}/p' "$HF")"
  # NON-VACUITY GUARD. Every "NOT proven" assertion below is `[ "$status" -ne 0 ]`, and a MISSING
  # function also exits non-zero (127) — so without this, the fail-closed tests would pass on a tree
  # where the oracle had been deleted, i.e. they would certify the very hole they exist to close
  # (verified: they did exactly that against the recovered pre-fix artifact).
  [ -n "$(declare -F composer_owned)" ]
  PSDIR="$BATS_TEST_TMPDIR/psbin"; mkdir -p "$PSDIR"
  PSTABLE="$BATS_TEST_TMPDIR/pstable"; : > "$PSTABLE"
  cat > "$PSDIR/ps" <<SH
#!/usr/bin/env bash
cat '$PSTABLE'
SH
  chmod +x "$PSDIR/ps"
  PATH="$PSDIR:$PATH"
  as_tty() { printf '%s' "${STUB_TTY-/dev/ttys002}"; }
  successor_pin() { return "${STUB_PIN-2}"; }        # default: UNPINNABLE (no registry row)
  pid_is_cc() { grep -qx "$1" "$BATS_TEST_TMPDIR/ccpids" 2>/dev/null; }
  : > "$BATS_TEST_TMPDIR/ccpids"
}

@test "composer_owned: registry pin (rc 0) alone PROVES ownership" {
  setup_oracle
  STUB_PIN=0
  run composer_owned PANE-1
  [ "$status" -eq 0 ]
}

@test "composer_owned: unpinnable + a live CC pid on the pane tty PROVES ownership" {
  setup_oracle
  printf '30556\n' > "$PSTABLE"; printf '30556\n' > "$BATS_TEST_TMPDIR/ccpids"
  run composer_owned PANE-1
  [ "$status" -eq 0 ]
}

@test "composer_owned: RED-PROOF — a BARE SHELL pane is NOT proven (the destructive case)" {
  setup_oracle
  # The measured shape of a wedged pane: login + two zsh + gitstatusd, no CC process anywhere.
  printf '27166\n27172\n27192\n27392\n' > "$PSTABLE"; : > "$BATS_TEST_TMPDIR/ccpids"
  run composer_owned PANE-1
  [ "$status" -ne 0 ]
}

@test "composer_owned: a PINNED-DEAD row does not convict when a live CC still owns the tty" {
  setup_oracle
  STUB_PIN=1                                        # row names a dead session…
  printf '30556\n' > "$PSTABLE"; printf '30556\n' > "$BATS_TEST_TMPDIR/ccpids"   # …but CC is live here
  run composer_owned PANE-1
  [ "$status" -eq 0 ]
}

@test "composer_owned: FAIL-CLOSED — an unresolvable tty with no pin is NOT ownership" {
  setup_oracle
  STUB_TTY=""                                       # bridge wedged / pane gone
  printf '30556\n' > "$PSTABLE"; printf '30556\n' > "$BATS_TEST_TMPDIR/ccpids"
  run composer_owned PANE-1
  [ "$status" -ne 0 ]
}

@test "composer_owned: an empty pane id is refused outright" {
  setup_oracle
  STUB_PIN=0
  run composer_owned ""
  [ "$status" -ne 0 ]
}
