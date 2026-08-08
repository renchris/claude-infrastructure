#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are
#   invoked from those test subshells rather than from file scope (SC2329).
#
# scripts/cloud-websetup-drive.sh — the /web-setup account-linking driver.
#
# ── WHAT THIS SUITE IS ACTUALLY GUARDING ─────────────────────────────────────────────────────────
# The subject's first draft reported SUCCESS when the consent dialog appeared and no error followed.
# That is ABSENCE OF AN ERROR, and the subject's own header (T3) already named it as a trap that had
# been paid for once. A driver that records `.linked` off an absence writes a state file that later
# runs treat as proof, so one wrong inference becomes a permanent wrong fact about an account.
#
# So the property under test is a THREE-STATE one, and every test below exists to keep the three
# apart rather than to check that the happy path works:
#
#   rc 0  LINKED       the pane printed the literal `Connected as ` (confirmed live on next3:
#                      "Connected as renchris. Opened https://claude.ai/code")
#   rc 1  FAILED       an error was OBSERVED and named ("GitHub CLI not found", no window id, …)
#   rc 3  NOT-SUCCESS  the drive ran, nothing errored, and no verdict line appeared. INDETERMINATE.
#
# rc 3 having its own number is the whole design: a caller that cannot tell "broken" from "could not
# tell" will either retry a genuinely broken account forever or record a link that does not exist.
# `consent_prompt alone is NOT success` (below) is the regression test for the exact draft defect.
#
# ── HERMETICITY: NOTHING HERE MAY TOUCH THE OPERATOR'S TERMINAL ──────────────────────────────────
# The subject opens kitty windows and TYPES INTO THEM. A test that reached the real fleet would open
# panes on the operator's desk and send `/web-setup` into whatever matched — so every `kitten` call
# is routed through a PATH shim in $BATS_TEST_TMPDIR that records argv and opens nothing. `ps` is
# stubbed too, because the binary resolution walks the process tree and would otherwise find THIS
# session's own claude ancestor — making the resolution tests pass or fail depending on who ran them.
# $HOME, the state dir (CC_WEBSETUP_STATE) and accounts.json (CC_ACCOUNTS_JSON) are all fixtured.
#
# TERMINAL PINNED: setup() exports KITTY_WINDOW_ID. It is not read by the subject today, but this
# corpus has been bitten repeatedly by suites whose verdict depended on which terminal the operator
# happened to run them from; pinning it costs one line and removes the whole class.
#
# NO WALL-CLOCK: CC_WEBSETUP_SLEEP is exported EMPTY, which the subject honors as "never sleep".
# The NOT-SUCCESS arm would otherwise really wait out its poll window.
#
# DEAD-ASSERTION DISCIPLINE: bats bodies run under `set -eET`, and bash exempts `[[ ]]`, `(( ))` and
# `! cmd` from errexit — so a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). Every assertion below is POSIX `[ ]` with `|| false`, and every
# negative is `! …  || false`. `A && false` is NEVER used: it is and-absorbed and can never fail.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  SUBJECT="$REPO_ROOT/scripts/cloud-websetup-drive.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export KITTY_WINDOW_ID=1              # terminal PINNED, per the note above
  export CC_SPAWN_LOG=0                 # the pane-spawn census writes no row for a stubbed launch

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export KITTEN_LOG="$BATS_TEST_TMPDIR/kitten.log"; : > "$KITTEN_LOG"

  # kitten stub — records argv, opens NOTHING.
  #   @ ls        the remote-control precondition          (KITTEN_LS_FAIL=1 refuses it)
  #   launch      answers with a window id                 (KITTEN_LAUNCH_EMPTY=1 answers nothing)
  #   get-text    answers with KITTEN_TEXT — this is the ONLY input the three-state logic reads
  # Everything else (send-text, resize-window, close-window) is recorded and succeeds.
  cat > "$STUB/kitten" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${KITTEN_LOG:?}"
case " $* " in
  *" @ ls "*)      [ "${KITTEN_LS_FAIL:-0}" = 1 ] && exit 1; printf '[]\n'; exit 0 ;;
  *" launch "*)    [ "${KITTEN_LAUNCH_EMPTY:-0}" = 1 ] && exit 0; printf '%s\n' "${KITTEN_WID:-7}"; exit 0 ;;
  *" get-text "*)  printf '%s' "${KITTEN_TEXT:-}"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$STUB/kitten"

  # ps stub — the process-tree walk (R2) must not depend on who ran the suite. PS_PPID defaults to 0
  # so the walk terminates after ONE level, which is what makes the fallback arm deterministic.
  cat > "$STUB/ps" <<'STUB'
#!/bin/bash
case " $* " in
  *" -o command= "*) printf '%s\n' "${PS_COMMAND:-/bin/bash -l}" ;;
  *" -o ppid= "*)    printf '%s\n' "${PS_PPID:-0}" ;;
esac
exit 0
STUB
  chmod +x "$STUB/ps"

  # A `claude` LAUNCHER WRAPPER on PATH. It exists only so the resolution tests can prove it is
  # never chosen: `command -v claude` finding this is exactly the R2 defect.
  cat > "$STUB/claude" <<'STUB'
#!/bin/bash
echo "WRAPPER-SHOULD-NEVER-BE-RESOLVED"
STUB
  chmod +x "$STUB/claude"
  export PATH="$STUB:$PATH"

  # The RECORDED binary in accounts.json (R2's fallback) and the RUNNING one (R2's primary).
  RECORDED_BIN="$BATS_TEST_TMPDIR/recorded/node_modules/.bin/claude"
  RUNNING_BIN="$BATS_TEST_TMPDIR/running/node_modules/.bin/claude"
  mkdir -p "$(dirname "$RECORDED_BIN")" "$(dirname "$RUNNING_BIN")"
  printf '#!/bin/bash\nexit 0\n' > "$RECORDED_BIN"; chmod +x "$RECORDED_BIN"
  printf '#!/bin/bash\nexit 0\n' > "$RUNNING_BIN";  chmod +x "$RUNNING_BIN"

  # accounts.json fixture — array shape, matching the live SSOT.
  CFG_NEXT="$BATS_TEST_TMPDIR/cfg-next";   mkdir -p "$CFG_NEXT"
  CFG_NEXT2="$BATS_TEST_TMPDIR/cfg-next2"; mkdir -p "$CFG_NEXT2"
  export CC_ACCOUNTS_JSON="$BATS_TEST_TMPDIR/accounts.json"
  cat > "$CC_ACCOUNTS_JSON" <<JSON
{
  "claude_bin": "$RECORDED_BIN",
  "accounts": [
    {"name": "next",  "config_dir": "$CFG_NEXT",  "launcher": "claude"},
    {"name": "next2", "config_dir": "$CFG_NEXT2", "launcher": "claude2"}
  ]
}
JSON

  export CC_WEBSETUP_STATE="$BATS_TEST_TMPDIR/state"
  export CC_WEBSETUP_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$CC_WEBSETUP_REPO"
  export CC_WEBSETUP_POLL_MAX=2
  export CC_WEBSETUP_SLEEP=            # set-EMPTY ⇒ never sleep. No wall-clock in this suite.

  READY='? for shortcuts'
  CONSENT='Connect Claude on the web to GitHub?'
  CONNECTED='Connected as renchris. Opened https://claude.ai/code'
}

# ── R1/R2: resolution ────────────────────────────────────────────────────────────────────────────

@test "resolution reads accounts.json for the config dir and the recorded binary — never the PATH wrapper" {
  # No claude anywhere in the process tree (PS_COMMAND is a plain shell), so R2 falls back to
  # accounts.json's recorded absolute path. The `claude` wrapper sitting first on PATH is the thing
  # a `command -v claude` implementation would pick, and picking it is the defect.
  export PS_COMMAND='/bin/bash -l'
  run "$SUBJECT" --resolve next
  [ "$status" -eq 0 ] || false
  [ "$output" = "account=next bin=$RECORDED_BIN config=$CFG_NEXT" ] || false
  ! printf '%s' "$output" | grep -q "$STUB/claude" || false
  ! printf '%s' "$output" | grep -q 'WRAPPER-SHOULD-NEVER-BE-RESOLVED' || false
}

@test "resolution prefers the RUNNING process's binary over the recorded one" {
  export PS_COMMAND="/usr/local/bin/node $RUNNING_BIN --permission-mode auto"
  run "$SUBJECT" --resolve next2
  [ "$status" -eq 0 ] || false
  [ "$output" = "account=next2 bin=$RUNNING_BIN config=$CFG_NEXT2" ] || false
  ! printf '%s' "$output" | grep -q "$RECORDED_BIN" || false
}

@test "an account absent from accounts.json resolves to no config dir and FAILS the drive (rc 1)" {
  export KITTEN_TEXT="$READY"
  run "$SUBJECT" --account nosuchacct
  [ "$status" -eq 1 ] || false
  printf '%s' "$output" | grep -q 'FAILED — no config dir' || false
  ! grep -q 'launch' "$KITTEN_LOG" || false
}

# ── the three states ─────────────────────────────────────────────────────────────────────────────

@test "SUCCESS: 'Connected as ' in the pane ⇒ rc 0 and a .linked state file" {
  export KITTEN_TEXT="$READY
$CONNECTED"
  run "$SUBJECT" --account next
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q "next: LINKED" || false
  [ -f "$CC_WEBSETUP_STATE/next.linked" ] || false
  grep -q 'connected-as-observed' "$CC_WEBSETUP_STATE/next.linked" || false
  grep -q 'launch --type=window' "$KITTEN_LOG" || false
}

@test "NOT-SUCCESS: the verdict line never appears ⇒ rc 3, and NO .linked is written" {
  # A pane that reached its composer and then said nothing at all. Nothing errored; nothing was
  # confirmed. This must be its own answer — folding it into rc 0 records a link that was never
  # made, folding it into rc 1 convicts a possibly-healthy account.
  export KITTEN_TEXT="$READY"
  run "$SUBJECT" --account next
  [ "$status" -eq 3 ] || false
  printf '%s' "$output" | grep -q 'NOT-SUCCESS' || false
  printf '%s' "$output" | grep -q 'INDETERMINATE' || false
  ! [ -f "$CC_WEBSETUP_STATE/next.linked" ] || false
}

@test "the consent prompt ALONE is NOT success — it is rc 3, and consent is sent exactly once" {
  # THE REGRESSION TEST for the draft's defect. The dialog appearing means the flow got somewhere;
  # it does not mean the link was made. The draft returned 0 here and wrote .linked.
  export KITTEN_TEXT="$READY
$CONSENT"
  run "$SUBJECT" --account next
  [ "$status" -eq 3 ] || false
  ! [ -f "$CC_WEBSETUP_STATE/next.linked" ] || false
  # Two \r sends are expected in total: one submitting /web-setup, one answering the consent
  # dialog. A third would mean the consent branch re-fired each poll and would be answering
  # whatever prompt came next.
  [ "$(grep -c 'send-text' "$KITTEN_LOG")" -eq 3 ] || false
}

@test "ERROR: 'GitHub CLI not found' ⇒ rc 1 — a DIFFERENT code from NOT-SUCCESS" {
  export KITTEN_TEXT="$READY
GitHub CLI not found"
  run "$SUBJECT" --account next
  [ "$status" -eq 1 ] || false
  printf '%s' "$output" | grep -q 'FAILED' || false
  ! [ -f "$CC_WEBSETUP_STATE/next.linked" ] || false
}

@test "ERROR: a launch that yields no window id ⇒ rc 1 and nothing is typed" {
  export KITTEN_TEXT="$READY
$CONNECTED"
  export KITTEN_LAUNCH_EMPTY=1
  run "$SUBJECT" --account next
  [ "$status" -eq 1 ] || false
  printf '%s' "$output" | grep -q 'no window id' || false
  ! grep -q 'send-text' "$KITTEN_LOG" || false
}

@test "several accounts: an OBSERVED error outranks an INDETERMINATE one, in either order" {
  # `nosuchacct` FAILS (rc 1, a named cause); `next` reaches its composer and says nothing (rc 3).
  # The run must report 1 — the answer that carries information — regardless of which came first.
  export KITTEN_TEXT="$READY"
  run "$SUBJECT" --account nosuchacct --account next
  [ "$status" -eq 1 ] || false
  : > "$KITTEN_LOG"
  run "$SUBJECT" --account next --account nosuchacct
  [ "$status" -eq 1 ] || false
}

@test "several accounts, none of them erroring: the run is INDETERMINATE (rc 3), not a failure" {
  export KITTEN_TEXT="$READY"
  run "$SUBJECT" --account next --account next2
  [ "$status" -eq 3 ] || false
  ! [ -f "$CC_WEBSETUP_STATE/next.linked" ] || false
  ! [ -f "$CC_WEBSETUP_STATE/next2.linked" ] || false
}

# ── state (correction 4) ─────────────────────────────────────────────────────────────────────────

@test "an already-linked account is a NO-OP: rc 0, and no pane is launched at all" {
  mkdir -p "$CC_WEBSETUP_STATE"
  printf '2026-08-08T00:00:00Z connected-as-observed\n' > "$CC_WEBSETUP_STATE/next.linked"
  export KITTEN_TEXT="$READY"        # would be rc 3 if it drove
  run "$SUBJECT" --account next
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q 'already linked — no-op' || false
  ! grep -q 'launch' "$KITTEN_LOG" || false
}

@test "--force re-drives an already-linked account" {
  mkdir -p "$CC_WEBSETUP_STATE"
  printf '2026-08-08T00:00:00Z connected-as-observed\n' > "$CC_WEBSETUP_STATE/next.linked"
  export KITTEN_TEXT="$READY
$CONNECTED"
  run "$SUBJECT" --force --account next
  [ "$status" -eq 0 ] || false
  grep -q 'launch --type=window' "$KITTEN_LOG" || false
}

@test "the state dir is an env seam honored SET-INCLUDING-EMPTY: empty ⇒ stateless, drives anyway" {
  # `${VAR:-}` cannot tell unset from set-to-empty, so a seam written that way cannot express "off".
  # Empty here means no reads and no writes — which is why the pre-seeded .linked below is ignored.
  mkdir -p "$BATS_TEST_TMPDIR/state"
  printf 'x\n' > "$BATS_TEST_TMPDIR/state/next.linked"
  export CC_WEBSETUP_STATE=
  export KITTEN_TEXT="$READY
$CONNECTED"
  run "$SUBJECT" --account next
  [ "$status" -eq 0 ] || false
  grep -q 'launch --type=window' "$KITTEN_LOG" || false
  printf '%s' "$output" | grep -q 'state=<stateless>' || false
}

@test "--status reads the state dir and drives nothing" {
  mkdir -p "$CC_WEBSETUP_STATE"
  printf '2026-08-08T00:00:00Z connected-as-observed\n' > "$CC_WEBSETUP_STATE/next.linked"
  run "$SUBJECT" --status
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -qE '^next +linked' || false
  printf '%s' "$output" | grep -qE '^next2 +none' || false
  [ ! -s "$KITTEN_LOG" ] || false
}

# ── preconditions are their own answer (rc 2), never a per-account failure ───────────────────────

@test "kitty remote control refused ⇒ rc 2, distinct from both FAILED and NOT-SUCCESS" {
  export KITTEN_LS_FAIL=1
  export KITTEN_TEXT="$READY
$CONNECTED"
  run "$SUBJECT" --account next
  [ "$status" -eq 2 ] || false
  printf '%s' "$output" | grep -q 'remote control is refused' || false
}
