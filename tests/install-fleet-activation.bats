#!/usr/bin/env bats
# install-fleet-activation.bats — install.sh may activate ONLY what the fleet manifest declares
# `expect = run`. Everything else is copied (SSOT deploy) and left alone.
#
# THE DEFECT (closed 2026-07-31, DAEMON_FLEET_V2 remainder R-1). install.sh's LaunchAgents loop ran
# `launchctl bootout` + `bootstrap` over EVERY launchd/*.plist unconditionally, swallowing every
# error with `2>/dev/null || true`. Measured on trunk that day:
#
#   7 of the 8 labels the manifest declares `staged` live in that glob — among them
#   com.claude.desk-invariant and com.claude.boot-resume, the two timer-driven session GENERATORS
#   whose runaway spawning forced the operator's fleet shutdown of 2026-07-26 (31 live processes,
#   load 17). The only thing holding them off was the disabled bit in the root-owned
#   /var/db/com.apple.xpc.launchd/disabled.501.plist — outside the repo and outside every repo
#   check. One `launchctl enable` from any source and the next routine install would have started
#   both generators with no operator decision anywhere in the loop.
#
# WHY THE PRESCRIBED REMEDY WAS THE DANGEROUS ONE. R-1's own text said "add `launchctl enable`
# before bootstrap" (to fix a disabled `run` job being unrecoverable — real, and test 4 pins it).
# Applied to this glob it would have enabled all 7 staged labels including both generators, i.e.
# re-created the incident. The remedy had to come from the manifest, not from the remedy as written.
#
# TWO CONTROLS, both replaying a REAL artifact, both MEASURED on 2026-07-31 (not predicted — the
# first run disagreed with the expectation written here, and the measurement won):
#
#   (1) PRE-FIX — `git show 0865293b:install.sh` recovered into the fixture:
#       not ok 1 2 3 4 7 8 9 · ok 5 6.
#   (2) NAIVE FIX — that same pristine file plus R-1's prescription verbatim, one `launchctl enable`
#       line inserted before the bootout (applied by a mutation asserting its anchor matches exactly
#       once, so it cannot silently no-op):
#       not ok 1 2 3 4 5 7 8 9 · ok 6.
#
# The clearest form of control (2) is not a test count but the verb log. Same fixture, one DISABLED
# `staged` plist carrying the real generator's label, three variants of install.sh:
#
#   pre-fix   bootout gui/501/com.claude.desk-invariant
#             bootstrap gui/501 …/com.claude.desk-invariant.plist      (survives only on EIO)
#   NAIVE     enable gui/501/com.claude.desk-invariant                 ← clears the ONLY guard
#             bootout … ; bootstrap …                                  ← generator starts
#   fixed     (no verb issued)
#
# That middle block is the whole argument for reading the manifest: R-1's prescription removes the
# disabled bit that was the sole thing standing between a routine `install.sh` and the runaway
# session generator whose spawning caused the 2026-07-26 outage.
#
# Test 6 is the positive control and passes in all three worlds: it pins that every plist is still
# COPIED whatever its `expect`, so the refusal tests cannot pass by the loop doing nothing at all.
# The stub is on PATH *and* behind the seam precisely so pre-fix code — which calls a bare
# `launchctl` — records into the same log; without that both controls would be vacuous.
#
# Hermeticity: fixture $HOME, fixture repo, PATH-stubbed `launchctl`/`defaults` (the global leg
# reaches both regardless of $HOME). No test loads, enables or bootstraps anything real.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"     # hermetic: never touch the live ~/
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  TDIR="$(cd "$(mktemp -d)" && pwd -P)"
  export TDIR
  FX="$TDIR/repo"
  export LOG="$TDIR/launchctl.log"
  : > "$LOG"

  # Minimal but REAL fixture repo: CLAUDE.md and statusline.sh are unconditional cp targets, so
  # install.sh aborts under `set -e` without them.
  mkdir -p "$FX/launchd"
  cp "$REPO/install.sh" "$FX/install.sh"
  printf '# fixture global instructions\n' > "$FX/CLAUDE.md"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$FX/statusline.sh"

  for l in fx-run fx-staged fx-retired fx-undeclared; do
    mk_plist "com.claude.$l"
  done

  # The declaration. fx-undeclared is deliberately ABSENT — an undeclared plist must never activate.
  cat > "$FX/launchd/fleet.manifest" <<'EOF'
# label | expect | interval_s | evidence | owner_row | activate
com.claude.fx-run     | run     | 300 | - | 12 | a.sh
com.claude.fx-staged  | staged  | 300 | - | 12 | a.sh
com.claude.fx-retired | retired | 300 | - | 12 | a.sh
EOF

  # git init so --absolute-git-dir names a PRIMARY checkout: the linked-worktree refusal must not
  # fire, and detection must not depend on whatever ambient repo $TMPDIR happens to sit in.
  git init -q "$FX"

  # Recording launchctl stub. On PATH *and* behind CC_INSTALL_LAUNCHCTL_BIN so pre-fix code (bare
  # `launchctl`) and fixed code (the seam) both land in one log — without that the red-proof would
  # be vacuous. FX_LOADED/FX_RUNNING drive `list`, the only subcommand whose answer install.sh reads.
  STUB="$TDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/launchctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOG"
if [ "$1" = list ]; then
  case " ${FX_LOADED:-} " in *" $2 "*) ;; *) exit 1 ;; esac
  case " ${FX_RUNNING:-} " in
    *" $2 "*) printf '{\n\t"PID" = 4242;\n}\n' ;;
    *)        printf '{\n\t"LastExitStatus" = 0;\n}\n' ;;
  esac
fi
if [ "$1" = print-disabled ]; then
  for l in ${FX_DISABLED:-}; do printf '\t\t"%s" => disabled\n' "$l"; done
fi
exit 0
EOF
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/defaults"
  export PATH="$STUB:$PATH"
  export CC_INSTALL_LAUNCHCTL_BIN="$STUB/launchctl"
  export FX_LOADED="" FX_RUNNING=""
  # Mirrors the real box: the staged labels are held off by the disabled bit in the root-owned
  # override db, and NO declared-`run` label is disabled (measured 2026-07-31 — that intersection
  # is empty). So the staged guard is tested in exactly the state the incident happened in.
  export FX_DISABLED="com.claude.fx-staged com.claude.fx-retired com.claude.fx-undeclared"
}

teardown() { rm -rf "$TDIR"; }

mk_plist() { # <label> — a syntactically real plist in the auto-installed glob dir
  cat > "$FX/launchd/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>/bin/echo</string><string>fixture</string></array>
</dict></plist>
EOF
}

install_run() { run bash "$FX/install.sh"; }

did()   { grep -qE "^$1 .*$2" "$LOG"; }
didnt() { if grep -qE "^$1 .*$2" "$LOG"; then return 1; fi; return 0; }

# ---- the incident guard -----------------------------------------------------------------------

@test "a STAGED label is never enabled and never bootstrapped (the 2026-07-26 generator guard)" {
  install_run
  [ "$status" -eq 0 ]
  didnt enable    fx-staged
  didnt bootstrap fx-staged
  didnt bootout   fx-staged
  printf '%s' "$output" | grep -qF "declared 'staged': SSOT deployed, NOT activated"
}

@test "a RETIRED label is never enabled and never bootstrapped" {
  install_run
  [ "$status" -eq 0 ]
  didnt enable    fx-retired
  didnt bootstrap fx-retired
  didnt bootout   fx-retired
}

@test "an UNDECLARED plist is not activated, and says so as a warning" {
  install_run
  [ "$status" -eq 0 ]
  didnt enable    fx-undeclared
  didnt bootstrap fx-undeclared
  printf '%s' "$output" | grep -qF "UNDECLARED in launchd/fleet.manifest"
}

# ---- false-positive guards: the lanes a blanket refusal would have broken ----------------------

@test "a DISABLED declared-run label IS enabled, and enable comes BEFORE bootstrap (the EIO order)" {
  export FX_DISABLED="com.claude.fx-run $FX_DISABLED"
  install_run
  [ "$status" -eq 0 ]
  did enable    fx-run
  did bootstrap fx-run
  n_enable="$(grep -nE '^enable .*fx-run' "$LOG" | head -1 | cut -d: -f1)"
  n_boot="$(grep -nE '^bootstrap .*fx-run' "$LOG" | head -1 | cut -d: -f1)"
  [ -n "$n_enable" ] && [ -n "$n_boot" ]
  [ "$n_enable" -lt "$n_boot" ]
  printf '%s' "$output" | grep -qF "DISABLED at the domain level: clearing the bit"
}

@test "an ALREADY-ENABLED run label is never sent a needless enable (no silent mutation verb)" {
  install_run                       # fx-run carries no disabled bit in the default fixture
  [ "$status" -eq 0 ]
  did bootstrap fx-run              # it is still activated...
  didnt enable  fx-run              # ...without issuing a mutation verb that had nothing to clear
}

@test "positive control: EVERY plist is still COPIED whatever its expect (SSOT deploy intact)" {
  install_run
  [ "$status" -eq 0 ]
  for l in fx-run fx-staged fx-retired fx-undeclared; do
    [ -f "$HOME/Library/LaunchAgents/com.claude.$l.plist" ]
  done
}

# ---- the 600s-cadence safety ------------------------------------------------------------------

@test "an unchanged, already-loaded run job is not touched at all" {
  install_run                       # first run copies + bootstraps
  [ "$status" -eq 0 ]
  export FX_LOADED="com.claude.fx-run"
  : > "$LOG"                        # second run: nothing changed, job is loaded
  install_run
  [ "$status" -eq 0 ]
  didnt bootout   fx-run
  didnt bootstrap fx-run
  didnt enable    fx-run
}

@test "a job EXECUTING right now is never booted out mid-run" {
  install_run
  [ "$status" -eq 0 ]
  export FX_LOADED="com.claude.fx-run" FX_RUNNING="com.claude.fx-run"
  printf '  <!-- changed -->\n' >> "$FX/launchd/com.claude.fx-run.plist"   # force a reload decision
  : > "$LOG"
  install_run
  [ "$status" -eq 0 ]
  didnt bootout fx-run
  printf '%s' "$output" | grep -qF "executing right now, not reloaded"
}

# ---- fail closed ------------------------------------------------------------------------------

@test "an ABSENT manifest activates nothing — the gate fails closed, never back to blanket bootstrap" {
  rm -f "$FX/launchd/fleet.manifest"
  install_run
  [ "$status" -eq 0 ]
  didnt enable    fx-run
  didnt bootstrap fx-run
  didnt bootstrap fx-staged
}
