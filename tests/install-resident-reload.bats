#!/usr/bin/env bats
# install-resident-reload.bats — install.sh must notice a KeepAlive daemon running a stale image.
#
# THE DEFECT (master ce775801633b). install.sh's LaunchAgents loop skips any loaded job whose plist
# did not change: `if $loaded && ! $plist_changed; then continue; fi`. That is exactly right for a
# PERIODIC job — it re-execs its program at its next scheduled load, so new bytes arrive on their
# own. It is permanently wrong for a KeepAlive daemon, which by design never exits: its "next
# natural load" never comes, so it holds the image it exec'd at start forever. And because its
# plist names a SCRIPT PATH, the plist never changes when the script does, so this skip fires on
# EVERY install and the daemon is never reloaded at all.
#
# THE ROW NAMED THE WRONG STATEMENT. It cites the PID skip ("executing right now, not reloaded").
# That branch is UNREACHABLE for an unchanged plist — the `$loaded && ! $plist_changed` skip
# returns first, and copy_file only increments `installed` when the bytes actually differ.
#
# THE ROW'S POPULATION FIGURE IS ALSO WRONG, IN THE DIRECTION THAT MATTERS. It says 6 of 22 plists
# carry KeepAlive, from `grep -l KeepAlive`. Measured 2026-08-19 with PlistBuddy: 3 of 22. The other
# three say the word only in a COMMENT, and two of those comments say the job is deliberately NOT
# KeepAlive. Test 10 pins the discriminator against a plist that mentions KeepAlive in a comment.
#
# MEASURED ON THE LIVE BOX 2026-08-19, corrected instrument:
#   com.claude.compressor-sentinel  pid 80076  image 1395 min (23.3 h) older than the file
#   com.claude.lead-supervisor      pid 82511  image 1127 min (18.8 h) older than the file
#   com.claude.caffeinate-floor     pid  1054  exec'd into /usr/bin/caffeinate — exempt BY
#                                              CONSTRUCTION (no repo script in argv), not by a gap
#
# PRE-FIX EXPECTATION, RECORDED BEFORE THE RUN (pristine origin/main install.sh — no resident arm):
#   RED   1, 4, 6, 7, 8   — each asserts a line, a verb or a function that does not exist pre-fix
#   GREEN 2, 3, 5, 9, 10, 11, 12 — every one asserts an ABSENCE or a PRESERVATION, so it is green
#         pre-fix BY CONSTRUCTION. That is not a weakness and it is not hidden: 2/3/9/10 pin the
#         discriminator's failure directions, 5 pins that the mutation stays default-OFF, 11 is the
#         positive control, 12 pins that the new arm does not swallow the pre-existing reload path.
#         They are credited by mutation, not by pre-fix colour — see the mutant table in the commit.
#
# Hermeticity: fixture $HOME, fixture repo, PATH-stubbed launchctl/ps/defaults. `stat` and `date`
# are REAL — the staleness comparison is exercised for real against fixture files whose mtimes the
# test sets with `touch`. PlistBuddy is real and only ever reads a fixture plist. No test loads,
# enables, bootstraps or bounces anything on the live box.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"     # hermetic: never touch the live ~/
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  TDIR="$(cd "$(mktemp -d)" && pwd -P)"
  export TDIR
  FX="$TDIR/repo"
  export LOG="$TDIR/launchctl.log"
  : > "$LOG"

  mkdir -p "$FX/launchd"
  cp "$REPO/install.sh" "$FX/install.sh"
  printf '# fixture global instructions\n' > "$FX/CLAUDE.md"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$FX/statusline.sh"

  mk_plist com.claude.fx-resident keepalive
  mk_plist com.claude.fx-periodic  none
  mk_plist com.claude.fx-dictka    dict
  mk_plist com.claude.fx-commentka comment

  cat > "$FX/launchd/fleet.manifest" <<'EOF'
# label | expect | interval_s | evidence | owner_row | activate
com.claude.fx-resident  | run | 300 | - | 12 | a.sh
com.claude.fx-periodic  | run | 300 | - | 12 | a.sh
com.claude.fx-dictka    | run | 300 | - | 12 | a.sh
com.claude.fx-commentka | run | 300 | - | 12 | a.sh
EOF

  git init -q "$FX"

  # The program the fake daemon is "running". A REAL file, so `stat -L` has something to read.
  PROG="$TDIR/prog.sh"; export PROG
  printf '#!/bin/bash\n:\n' > "$PROG"

  STUB="$TDIR/stub"; mkdir -p "$STUB"
  # launchctl: same recording stub as tests/install-fleet-activation.bats, so pre-fix code (bare
  # `launchctl`) and fixed code (the seam) both land in ONE log.
  cat > "$STUB/launchctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOG"
if [ "$1" = list ]; then
  case " ${FX_LOADED:-} " in *" $2 "*) ;; *) exit 1 ;; esac
  case " ${FX_RUNNING:-} " in
    *" $2 "*) printf '{\n\t"PID" = %s;\n}\n' "${FX_PID:-4242}" ;;
    *)        printf '{\n\t"LastExitStatus" = 0;\n}\n' ;;
  esac
fi
exit 0
EOF
  # ps: answers only the two forms the subject asks for, and EXITS 1 with no output when the pid is
  # unknown — which is what real `ps -p <dead pid>` does. That fidelity is what makes test 9
  # creditable: without it the stub always succeeds and no mutation of the subject's error handling
  # could ever red a case.
  cat > "$STUB/ps" <<'EOF'
#!/bin/sh
case "$*" in
  *command=*) [ -n "${FX_PS_COMMAND:-}" ] || exit 1; printf '%s\n' "$FX_PS_COMMAND" ;;
  *lstart=*)  [ -n "${FX_PS_LSTART:-}"  ] || exit 1; printf '%s\n' "$FX_PS_LSTART" ;;
esac
exit 0
EOF
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/ps" "$STUB/defaults"
  export PATH="$STUB:$PATH"
  export CC_INSTALL_LAUNCHCTL_BIN="$STUB/launchctl"
  export FX_LOADED="" FX_RUNNING="" FX_DISABLED="" FX_PID=4242
  export FX_PS_COMMAND="" FX_PS_LSTART=""
  # Point the sentinel veto at a fixture path so it can never read the operator's real ledger.
  export CC_SENTINEL_FROZEN_DB="$TDIR/frozen.tsv"
  unset CC_INSTALL_RESIDENT_RELOAD
}

teardown() { rm -rf "$TDIR"; }

mk_plist() { # <label> <keepalive-shape: keepalive|none|dict|comment>
  local ka=""
  case "$2" in
    keepalive) ka='  <key>KeepAlive</key><true/>' ;;
    dict)      ka='  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' ;;
    comment)   ka='  <!-- StartInterval 300, NOT KeepAlive — the opposite choice, deliberately -->' ;;
    none)      ka='' ;;
  esac
  cat > "$FX/launchd/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>/bin/echo</string><string>fixture</string></array>
$ka
</dict></plist>
EOF
}

install_run() { run bash "$FX/install.sh"; }

# Counting form everywhere. `producer | grep -q` FAILS under `pipefail` on the very input it just
# matched: grep -q exits at the first hit and SIGPIPEs the producer (rc 141). A shell BUILTIN
# producer is exempt only below the 64 KiB pipe buffer, and install.sh's output is not bounded by
# inspection, so `printf` earns no exemption here.
out_count() { printf '%s\n' "$output" | grep -cF -- "$1" || true; }

# ANTI-VACUITY. Every behavioural case below depends on install.sh reaching the unchanged-plist skip
# on its SECOND run. If the first run did not place the plists, or the second run reinstalled them,
# `plist_changed` is true and the arm under test is never entered — and the case would pass for the
# wrong reason. This asserts the fixture is in the state the defect needs before any assertion runs.
seed_then_rerun() {
  install_run
  [ "$status" -eq 0 ] || { echo "seed install failed: $output"; return 1; }
  [ -f "$HOME/Library/LaunchAgents/com.claude.fx-resident.plist" ] || { echo "seed did not place the plist"; return 1; }
  : > "$LOG"
  install_run
  # The plist must have been SKIPPED as identical on this second run, or the subject never reaches
  # the branch under test.
  local n; n="$(out_count "✓ $HOME/Library/LaunchAgents/com.claude.fx-resident.plist")"
  [ "${n:-0}" -eq 0 ] || { echo "second run REINSTALLED the plist — the skip path was never exercised"; return 1; }
  return 0
}

# A daemon whose image is STALE: the process started before the program file was last written.
stale_daemon() {
  export FX_LOADED="com.claude.fx-resident com.claude.fx-periodic com.claude.fx-dictka com.claude.fx-commentka"
  export FX_RUNNING="$FX_LOADED"
  export FX_PS_COMMAND="/bin/bash $PROG"
  export FX_PS_LSTART="Tue Aug 18 11:36:03 2026"
  touch -t 202608190000.00 "$PROG"      # written AFTER the process started ⇒ stale
}

fresh_daemon() {
  export FX_LOADED="com.claude.fx-resident"
  export FX_RUNNING="$FX_LOADED"
  export FX_PS_COMMAND="/bin/bash $PROG"
  export FX_PS_LSTART="Tue Aug 18 11:36:03 2026"
  touch -t 202608170000.00 "$PROG"      # written BEFORE the process started ⇒ fresh
}

@test "1 a RESIDENT daemon running a stale image is REPORTED (pre-fix: silent forever)" {
  stale_daemon
  seed_then_rerun || false
  n="$(out_count "com.claude.fx-resident — RESIDENT daemon is running a STALE image")"
  [ "${n:-0}" -gt 0 ] || false
}

@test "2 a PERIODIC job running a stale image is NOT reported (it re-execs on its own)" {
  stale_daemon
  seed_then_rerun || false
  run bash -c 'printf "%s\n" "$1" | grep -cF "com.claude.fx-periodic — RESIDENT" || true' _ "$output"
  [ "$output" -eq 0 ] || false
}

@test "3 a RESIDENT daemon whose image is FRESH is NOT reported" {
  fresh_daemon
  seed_then_rerun || false
  run bash -c 'printf "%s\n" "$1" | grep -cF "RESIDENT daemon is running a STALE image" || true' _ "$output"
  [ "$output" -eq 0 ] || false
}

@test "4 with CC_INSTALL_RESIDENT_RELOAD=1 the stale resident daemon IS bounced" {
  stale_daemon
  export CC_INSTALL_RESIDENT_RELOAD=1
  seed_then_rerun || false
  run grep -cF "bootout gui/" "$LOG"
  [ "$output" -ge 1 ] || false
  run grep -cF "bootstrap gui/" "$LOG"
  [ "$output" -ge 1 ] || false
}

@test "5 by DEFAULT a stale resident daemon earns NO launchd verb (the mutation is opt-in)" {
  stale_daemon
  seed_then_rerun || false
  run grep -cF "bootout gui/" "$LOG"
  [ "$output" -eq 0 ] || false
}

@test "6 the sentinel is NOT bounced while it owes a SIGCONT, even with reload enabled" {
  # The one bounce that can lose something: the compressor sentinel SIGSTOPs burst processes and
  # owes each a SIGCONT, a debt recorded ONLY in its frozen ledger. Bouncing it mid-freeze strands
  # them stopped forever — a remedy strictly worse than the stale image it cures.
  mk_plist com.claude.compressor-sentinel keepalive
  printf 'com.claude.fx-resident\t1234\t1787000000\n' > "$CC_SENTINEL_FROZEN_DB"
  cat >> "$FX/launchd/fleet.manifest" <<'EOF'
com.claude.compressor-sentinel | run | 300 | - | 12 | a.sh
EOF
  export FX_LOADED="com.claude.compressor-sentinel"
  export FX_RUNNING="$FX_LOADED"
  export FX_PS_COMMAND="/bin/bash $PROG"
  export FX_PS_LSTART="Tue Aug 18 11:36:03 2026"
  touch -t 202608190000.00 "$PROG"
  export CC_INSTALL_RESIDENT_RELOAD=1
  install_run
  [ "$status" -eq 0 ] || false
  : > "$LOG"
  install_run
  n="$(out_count "owes SIGCONT to 1 frozen pid(s)")"
  [ "${n:-0}" -gt 0 ] || false
  run grep -cF "bootout gui/" "$LOG"
  [ "$output" -eq 0 ] || false
}

@test "7 staleness is read through the SYMLINK to its target, not off the link's own mtime" {
  # master 475222a572de half 1, reproduced. The live layer is per-file symlinks; a link's own mtime
  # is the day it was created, so a probe without `stat -L` reports a long-stale daemon as fresh.
  # Measured on the live box: com.claude.compressor-sentinel's link mtime is 13 days OLDER than the
  # daemon's own start, while its target is 23 h NEWER. This is a one-character defect.
  ln -s "$PROG" "$TDIR/live-link.sh"
  touch -h -t 202608010000.00 "$TDIR/live-link.sh"   # the LINK looks ancient
  touch    -t 202608190000.00 "$PROG"                # the TARGET is new
  export FX_LOADED="com.claude.fx-resident"
  export FX_RUNNING="$FX_LOADED"
  export FX_PS_COMMAND="/bin/bash $TDIR/live-link.sh"
  export FX_PS_LSTART="Tue Aug 18 11:36:03 2026"
  seed_then_rerun || false
  n="$(out_count "com.claude.fx-resident — RESIDENT daemon is running a STALE image")"
  [ "${n:-0}" -gt 0 ] || false
}

@test "8 STRUCTURAL: the start-time read pins BOTH TZ and LC_ALL, on ps and on date" {
  # Unpinned, this box renders lstart as `Tue 18 Aug 11:36:03 2026`, which the US-order format
  # cannot parse — yielding an EMPTY start that silently compares as "fresh". TZ alone is not
  # enough, which is why this is asserted rather than left to a comment. Structural because the
  # stub emits one fixed string regardless of locale, so no behavioural case can reach it.
  # A stale range marker does not fail, it INVERTS — `sed -n '1,/nomatch/p'` selects the whole
  # file — so the extract is asserted non-empty before anything is concluded from it.
  run bash -c "sed -n '/^resident_image_stale() {/,/^}/p' '$FX/install.sh'"
  [ -n "$output" ] || false
  n="$(printf '%s\n' "$output" | grep -cE 'TZ=UTC LC_ALL=C ps .*lstart=' || true)"; [ "${n:-0}" -gt 0 ] || false
  n="$(printf '%s\n' "$output" | grep -cE 'TZ=UTC LC_ALL=C date '        || true)"; [ "${n:-0}" -gt 0 ] || false
  n="$(out_count 'stat -L -f %m')";                                                 [ "${n:-0}" -gt 0 ] || false
}

@test "9 an unreadable process fails CLOSED: no report, no verb, install still succeeds" {
  export FX_LOADED="com.claude.fx-resident"
  export FX_RUNNING="$FX_LOADED"
  export FX_PS_COMMAND="" FX_PS_LSTART=""     # the pid is gone by the time we look
  export CC_INSTALL_RESIDENT_RELOAD=1
  seed_then_rerun || false
  [ "$status" -eq 0 ] || false
  run grep -cF "bootout gui/" "$LOG"
  [ "$output" -eq 0 ] || false
}

@test "10 a KeepAlive DICT and a KeepAlive COMMENT are both NOT resident" {
  # The row's "6 of 22" came from `grep -l KeepAlive`, which matches prose. The real discriminator
  # is the plist's own top-level key, and a DICT is a conditional restart — the job does exit, so
  # it is not in the class this arm exists for.
  stale_daemon
  seed_then_rerun || false
  run bash -c 'printf "%s\n" "$1" | grep -cE "fx-(dictka|commentka) — RESIDENT" || true' _ "$output"
  [ "$output" -eq 0 ] || false
}

@test "11 POSITIVE CONTROL: every plist is still COPIED, whatever its KeepAlive shape" {
  stale_daemon
  install_run
  [ "$status" -eq 0 ] || false
  for l in fx-resident fx-periodic fx-dictka fx-commentka; do
    [ -f "$HOME/Library/LaunchAgents/com.claude.$l.plist" ] || false
  done
}

@test "12 a resident job whose PLIST changed still takes the ordinary reload path" {
  # The new arm lives inside the unchanged-plist skip. It must not swallow the pre-existing path
  # for a job whose plist genuinely changed.
  stale_daemon
  install_run
  [ "$status" -eq 0 ] || false
  export FX_RUNNING=""                       # loaded but not executing, so the PID skip is inert
  printf '\n<!-- changed -->\n' >> "$FX/launchd/com.claude.fx-resident.plist"
  : > "$LOG"
  install_run
  run grep -cF "bootstrap gui/" "$LOG"
  [ "$output" -ge 1 ] || false
}
