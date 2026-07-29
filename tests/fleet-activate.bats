#!/usr/bin/env bats
# 18-fleet-activate.sh — the ONE C10 operator command that brings the launchd fleet to its DECLARED
# state (DAEMON_FLEET_V2 §4.5). These tests NEVER invoke real launchctl: a fixture `launchctl` on
# PATH records every argv and emulates the domain semantics, and CC_FLEET_LAUNCHCTL_BIN is pinned at
# it as well — belt AND braces, because a PATH miss here would mutate the operator's real fleet.
#
# The fixture is an ORACLE, not a recorder: `bootstrap` on a label that still carries the disabled
# bit returns the real `Bootstrap failed: 5: Input/output error`, exactly as launchd does. So the
# enable-before-bootstrap ordering test has teeth beyond argv order — get the order wrong and the
# fixture FAILS the load. A CONTROL test below proves that oracle actually bites (else every ordering
# assertion would be vacuous).
#
# `|| false` on every non-final [[ ]] / (( )) / ! / A && B: bats bodies run under `set -eET` and bash
# exempts those forms from errexit in any but the last position, making them DEAD. `[ ]` is live.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/docs/activation/pending-activation/18-fleet-activate.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/Library/LaunchAgents"   # hermetic: never the live ~/
  U="$(id -u)"

  # fixture checkout: `.git` as a FILE, which is what a linked worktree has (the script's gate is -e)
  FR="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FR/launchd"; : > "$FR/.git"

  export LC_STATE="$BATS_TEST_TMPDIR/lcstate"; mkdir -p "$LC_STATE"
  : > "$LC_STATE/loaded"; : > "$LC_STATE/disabled"
  export LC_LOG="$BATS_TEST_TMPDIR/launchctl.argv"; : > "$LC_LOG"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  stub_launchctl
  export PATH="$BIN:$PATH"
  export CC_FLEET_LAUNCHCTL_BIN="$BIN/launchctl"
}

stub_launchctl() {
  cat > "$BIN/launchctl" <<'STUB'
#!/bin/bash
# fixture launchctl — records argv, then emulates gui-domain semantics from $LC_STATE.
printf '%s\n' "$*" >> "$LC_LOG"
sub="${1:-}"; shift 2>/dev/null || true
lbl() { printf '%s' "${1##*/}"; }                                  # gui/501/com.x → com.x
has() { grep -Fqx "$2" "$LC_STATE/$1" 2>/dev/null; }
add() { has "$1" "$2" || printf '%s\n' "$2" >> "$LC_STATE/$1"; }
del() { grep -Fvx "$2" "$LC_STATE/$1" > "$LC_STATE/$1.tmp" 2>/dev/null; mv -f "$LC_STATE/$1.tmp" "$LC_STATE/$1"; }
case "$sub" in
  print-disabled)
    # literal shape of the real emission, tabs included, WITH unrelated `=> enabled` rows so a
    # label-only grep in the subject would false-positive here rather than in production.
    echo "	disabled services = {"
    echo "		\"com.apple.Siri.agent\" => disabled"
    while IFS= read -r l; do [ -n "$l" ] && printf '\t\t"%s" => disabled\n' "$l"; done < "$LC_STATE/disabled"
    while IFS= read -r l; do [ -n "$l" ] && printf '\t\t"%s" => enabled\n' "$l"; done < "$LC_STATE/loaded"
    echo "	}"
    ;;
  print)
    if has loaded "$(lbl "${1:-}")"; then echo "	state = running"; exit 0; fi
    echo "Could not find service \"$(lbl "${1:-}")\" in domain for gui" >&2; exit 113 ;;
  enable)  del disabled "$(lbl "${1:-}")"; exit 0 ;;
  disable) add disabled "$(lbl "${1:-}")"; exit 0 ;;
  bootout)
    if has loaded "$(lbl "${1:-}")"; then del loaded "$(lbl "${1:-}")"; exit 0; fi
    echo "Boot-out failed: 3: No such process" >&2; exit 3 ;;
  bootstrap)
    p="${2:-}"; b="${p##*/}"; l="${b%.plist}"
    # THE TRAP, reproduced: a label still in the disabled database refuses to bootstrap, with a
    # message naming neither cause nor cure.
    if has disabled "$l"; then echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; fi
    add loaded "$l"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN/launchctl"
}

mkplist() { # <label> — a real, plutil-lintable plist whose Standard*Path sits under the fixture HOME
  cat > "$FR/launchd/$1.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>/usr/bin/true</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>StandardOutPath</key><string>$HOME/.claude/logs/$1.out.log</string>
  <key>StandardErrorPath</key><string>$HOME/.claude/logs/$1.err.log</string>
</dict>
</plist>
PL
}

manifest() { printf '%s\n' "$@" > "$FR/launchd/fleet.manifest"; }
disabled() { printf '%s\n' "$1" >> "$LC_STATE/disabled"; }
loaded()   { printf '%s\n' "$1" >> "$LC_STATE/loaded"; }

act()  { run env CC_REPO="$FR" bash "$S"; }
actc() { run env CONFIRM=1 CC_REPO="$FR" bash "$S"; }

muts()     { grep -Ec '^(enable|disable|bootout|bootstrap|kickstart|load|unload)( |$)' "$LC_LOG" || true; }
mut_hits() { grep -E '^(enable|disable|bootout|bootstrap|kickstart)( |$)' "$LC_LOG" 2>/dev/null | grep -Fc -- "$1" || true; }
lineno()   { grep -Fn -- "$1" "$LC_LOG" | head -1 | cut -d: -f1; }

# ── CONTROL: the oracle must actually bite, else every ordering assertion is vacuous ───────────────
@test "CONTROL — the fixture reproduces the EIO trap: bootstrap on a disabled label FAILS" {
  disabled com.claude.alpha
  run "$BIN/launchctl" bootstrap "gui/$U" "$FR/launchd/com.claude.alpha.plist"
  [ "$status" -eq 5 ]
  printf '%s' "$output" | grep -Fq 'Input/output error'
  # and after an enable it succeeds — so the trap is order-sensitive, not always-fail
  "$BIN/launchctl" enable "gui/$U/com.claude.alpha"
  run "$BIN/launchctl" bootstrap "gui/$U" "$FR/launchd/com.claude.alpha.plist"
  [ "$status" -eq 0 ]
}

# ── the ordering that is the whole point ──────────────────────────────────────────────────────────
@test "enable is issued BEFORE bootstrap for a disabled label" {
  manifest '# label | expect | interval_s | evidence | owner_row | activate' \
           'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha
  disabled com.claude.alpha
  actc
  [ "$status" -eq 0 ]
  en="$(lineno "enable gui/$U/com.claude.alpha")"
  bs="$(lineno "bootstrap gui/$U $HOME/Library/LaunchAgents/com.claude.alpha.plist")"
  [ -n "$en" ]
  [ -n "$bs" ]
  [ "$en" -lt "$bs" ]                       # ORDER, not mere presence
  printf '%s' "$output" | grep -Fq 'loaded and verified'
  # the oracle above proves this could have failed: a wrong order yields EIO
  ! printf '%s' "$output" | grep -Fq 'Bootstrap failed' || false
  # self-verify is `print` (resolves the label in THIS domain), never the `list | grep` that cannot
  # tell loaded-and-healthy from loaded-and-failing
  vf="$(lineno "print gui/$U/com.claude.alpha")"
  [ -n "$vf" ]
  [ "$(grep -Ec '^list( |$)' "$LC_LOG" || true)" -eq 0 ]
}

@test "a not-loaded label is not booted out, and a loaded-but-disabled one is (idempotent reload)" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh' \
           'com.claude.beta  | run | 300 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha; mkplist com.claude.beta
  disabled com.claude.alpha                       # disabled AND absent  → no bootout
  disabled com.claude.beta; loaded com.claude.beta # disabled BUT loaded  → bootout first
  actc
  [ "$status" -eq 0 ]
  [ "$(mut_hits "bootout gui/$U/com.claude.alpha")" -eq 0 ]
  bo="$(lineno "bootout gui/$U/com.claude.beta")"
  en="$(lineno "enable gui/$U/com.claude.beta")"
  [ -n "$bo" ]
  [ "$bo" -lt "$en" ]
}

# ── skip semantics, each with a positive control in the SAME test ─────────────────────────────────
@test "an already-loaded and enabled label is SKIPPED — a needing-work sibling is NOT (positive control)" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh' \
           'com.claude.beta  | run | 600 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha; mkplist com.claude.beta
  loaded com.claude.alpha                          # loaded, not in the disabled db ⇒ at declared state
  disabled com.claude.beta
  actc
  [ "$status" -eq 0 ]
  [ "$(mut_hits com.claude.alpha)" -eq 0 ]         # untouched
  [ "$(mut_hits com.claude.beta)" -ge 2 ]          # POSITIVE CONTROL: the script does act on work
  printf '%s' "$output" | grep -Fq 'com.claude.alpha'   # still reported in the state table
}

@test "expect=staged and expect=retired are NEVER touched, while a run label in the same manifest IS" {
  manifest 'com.claude.alpha | run     | 300 | - | 12 | 18-fleet-activate.sh' \
           'com.claude.gamma | staged  | 300 | - | 12 | -' \
           'com.claude.delta | retired | 0   | - | 12 | -'
  mkplist com.claude.alpha; mkplist com.claude.gamma; mkplist com.claude.delta
  disabled com.claude.alpha; disabled com.claude.gamma; disabled com.claude.delta
  actc
  [ "$status" -eq 0 ]
  [ "$(mut_hits com.claude.gamma)" -eq 0 ]
  [ "$(mut_hits com.claude.delta)" -eq 0 ]
  [ "$(mut_hits com.claude.alpha)" -ge 2 ]         # POSITIVE CONTROL: a do-nothing script cannot pass
  [ ! -f "$HOME/Library/LaunchAgents/com.claude.gamma.plist" ]
  [ -f "$HOME/Library/LaunchAgents/com.claude.alpha.plist" ]
}

# ── the bare run: the .done trap this script exists to refuse ──────────────────────────────────────
@test "a bare run mutates NOTHING and says so, refusing the .done marker in words" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha
  disabled com.claude.alpha
  act
  [ "$status" -eq 0 ]
  [ "$(muts)" -eq 0 ]                              # zero launchctl MUTATIONS (reads are fine)
  [ ! -f "$HOME/Library/LaunchAgents/com.claude.alpha.plist" ]
  printf '%s' "$output" | grep -Fq 'NOTHING WAS CHANGED'
  printf '%s' "$output" | grep -Fq 'DO NOT touch the .done marker'
  printf '%s' "$output" | grep -Fq 'CONFIRM=1 bash'
  # POSITIVE CONTROL: the same fixture DOES mutate once confirmed, so the zero above is the gate
  actc
  [ "$(muts)" -ge 2 ]
}

@test "re-running twice is idempotent — the second run mutates nothing and says it is a no-op" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh' \
           'com.claude.beta  | run | 600 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha; mkplist com.claude.beta
  disabled com.claude.alpha; disabled com.claude.beta
  actc
  [ "$status" -eq 0 ]
  [ "$(muts)" -ge 4 ]
  : > "$LC_LOG"
  actc
  [ "$status" -eq 0 ]
  [ "$(muts)" -eq 0 ]
  printf '%s' "$output" | grep -Fq 'idempotent no-op'
}

# ── fail loud, never guess ────────────────────────────────────────────────────────────────────────
@test "an unresolvable checkout FAILS LOUD with the exact CC_REPO override and mutates nothing" {
  ISO="$BATS_TEST_TMPDIR/iso"; mkdir -p "$ISO"; cp "$S" "$ISO/18-fleet-activate.sh"
  run bash "$ISO/18-fleet-activate.sh"             # no CC_REPO, fixture HOME ⇒ no fallback checkout
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -Fq 'CC_REPO='
  [ "$(muts)" -eq 0 ]
  # an explicitly WRONG CC_REPO is rejected too — it must never pose as a checkout (816015ecb30b)
  NOT="$BATS_TEST_TMPDIR/notarepo"; mkdir -p "$NOT"
  run env CC_REPO="$NOT" CONFIRM=1 bash "$S"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -Fq 'not a checkout'
  [ "$(muts)" -eq 0 ]
}

# ── the sibling reconciler's contract: consumed when present, never required ───────────────────────
@test "cc-fleet --check is consumed when present and its RED propagates; absence is fail-soft" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.alpha
  disabled com.claude.alpha
  actc                                              # cc-fleet ABSENT (the sibling has not landed)
  [ "$status" -eq 0 ]                               # absence must not break the platter
  printf '%s' "$output" | grep -Fq 'cc-fleet not present'
  printf '%s' "$output" | grep -Fq 'launchctl print gui/'   # names the by-hand read instead

  mkdir -p "$FR/bin"
  printf '#!/bin/bash\necho "FLEET-GREEN-MARKER"\nexit 0\n' > "$FR/bin/cc-fleet"; chmod +x "$FR/bin/cc-fleet"
  actc
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -Fq 'FLEET-GREEN-MARKER'

  printf '#!/bin/bash\necho "FLEET-RED-MARKER"\nexit 1\n' > "$FR/bin/cc-fleet"
  actc
  [ "$status" -ne 0 ]                               # a RED reconciler makes the platter non-zero…
  printf '%s' "$output" | grep -Fq 'FLEET-RED-MARKER'
  printf '%s' "$output" | grep -Fq 'NOT green'
  printf '%s' "$output" | grep -Fq 'mark done: NOT YET'   # …and refuses to bless the marker

  # kill switch: says it is off, never fakes green (explicit `env`, so nothing depends on how bash
  # scopes an assignment prefixed to a function call)
  run env CC_FLEET_RECONCILE=off CONFIRM=1 CC_REPO="$FR" bash "$S"
  printf '%s' "$output" | grep -Fq 'CC_FLEET_RECONCILE=off'
  ! printf '%s' "$output" | grep -Fq 'FLEET-RED-MARKER' || false
}

@test "a missing declaration FAILS LOUD naming the manifest, and never bootstraps blind" {
  run env CC_REPO="$FR" CONFIRM=1 bash "$S"        # $FR has launchd/ but no fleet.manifest
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -Fq 'fleet.manifest'
  [ "$(muts)" -eq 0 ]
}

@test "a declared-run label with NO plist anywhere is a loud non-zero, not a silent skip" {
  manifest 'com.claude.alpha | run | 300 | - | 12 | 18-fleet-activate.sh' \
           'com.claude.beta  | run | 600 | - | 12 | 18-fleet-activate.sh'
  mkplist com.claude.beta                          # alpha has no plist in repo or LaunchAgents
  disabled com.claude.alpha; disabled com.claude.beta
  actc
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -Fq 'NO PLIST'
  [ "$(mut_hits com.claude.alpha)" -eq 0 ]
  [ "$(mut_hits com.claude.beta)" -ge 2 ]          # POSITIVE CONTROL: one bad row does not abort the rest
}
