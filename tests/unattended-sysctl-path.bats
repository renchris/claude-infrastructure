#!/usr/bin/env bats
# The loadavg instrument in postland-verify.sh and qos-census.sh must be readable in a SCHEDULED
# run, not just from a terminal.
#
# WHY THIS SUITE EXISTS (measured 2026-08-06, item ff544977e4ea — not hypothetical). Both jobs are
# launchd wrappers that EXPORT a PATH ending `/usr/bin:/bin`. `sysctl` lives in /usr/sbin, which is
# absent from both. Neither script resolved it absolutely, so the bare name worked from a shell and
# did not exist for the daemon — the failure mode that survives review by construction. Measured on
# this machine's own artifacts at the time of the fix:
#     postland stamps      34 of 80  carried "load":"0"      ← renders unreadable AS AN IDLE BOX
#     qos-census rows     859 of 867 carried loadavg1 "?"    ← the contention instrument, blind
# `${l:-0}` is the dangerous half: a dead instrument reporting the HEALTHY value is worse than no
# instrument (same shape as the swap rung in tests/capacity-alarm-launchd-path.bats, and as
# 752024be's capacity gate, whose load term had never once evaluated).
#
# WHY SCRIPT-SIDE AND NOT A PLIST PATH EDIT — this suite pins the choice so it is not silently
# reverted. Adding /usr/sbin to the two plists would fix only the launchd caller, and it would
# break launchd-parity-lint assertion (c) (live `plutil -p` vs repo SSOT; the live files are real
# copies, not symlinks) for every session in the fleet until the operator ran a bootout+bootstrap.
# Absolute resolution in the script needs no reload, covers every caller, and is the precedent this
# repo already set for this exact class: e6de2e15, 752024be, 9ac045cb.
#
# SCOPE NOTE — the sibling call sites in these files were ALREADY correct when this landed and are
# asserted here only so a regression in them cannot hide behind a green suite:
#     qos-census.sh          /usr/sbin/taskpolicy first  (pre-existing)
#     team-orphan-reaper.sh  /usr/sbin/lsof first        (9ac045cb, 2026-07-26)

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  QOS="$REPO/scripts/qos-census.sh"
  PLV="$REPO/scripts/postland-verify.sh"
  # The literal PATH each job runs with, taken FROM THE PLIST rather than restated here — a copy in
  # the test could drift from the plist and pass while production is broken.
  QOS_PATH="$(plist_path "$REPO/launchd/com.claude.qos-census.plist")"
  PLV_PATH="$(plist_path "$REPO/launchd/com.claude.postland-verify.plist")"
}

plist_path() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$1" 2>/dev/null \
    | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p'
}

# ── the controls come first: if these ever pass, everything below proves nothing ─────────────────

@test "RED CONTROL: both plists really do omit /usr/sbin, so a bare sysctl is genuinely hidden" {
  [ -n "$QOS_PATH" ] || { echo "could not parse PATH from the qos-census plist"; false; }
  [ -n "$PLV_PATH" ] || { echo "could not parse PATH from the postland-verify plist"; false; }
  local p
  for p in "$QOS_PATH" "$PLV_PATH"; do
    p="${p//\$HOME/$HOME}"
    # If this ever resolves, the plist gained /usr/sbin and the suite below is vacuous.
    run env -i PATH="$p" HOME="$HOME" bash -c 'command -v sysctl'
    [ "$status" -ne 0 ] || { echo "sysctl IS reachable on: $p — this suite no longer discriminates"; false; }
  done
}

@test "RED CONTROL: the pre-fix bare-name form really fails on that PATH (mutant from the real file)" {
  # Derived FROM THE SHIPPING FILE, not hand-written: a hand-made approximation can pass vacuously.
  # The mutant restores exactly what the fix replaced — a bare `sysctl -n vm.loadavg`.
  local p="${QOS_PATH//\$HOME/$HOME}" out
  out="$(env -i PATH="$p" HOME="$HOME" bash -c 'sysctl -n vm.loadavg 2>/dev/null | awk "{print \$2}"')"
  [ -z "$out" ] || { echo "bare sysctl returned [$out] on the launchd PATH — the defect is not reproducible here"; false; }
  # ...and the absolute form, on the same PATH, does answer. Both halves, or this proves nothing.
  out="$(env -i PATH="$p" HOME="$HOME" bash -c '/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | awk "{print \$2}"')"
  [ -n "$out" ] || skip "/usr/sbin/sysctl does not answer on this host — nothing to assert"
}

# ── qos-census: end-to-end, the real script, on the real plist PATH ──────────────────────────────

@test "qos-census reads a NUMERIC loadavg1 on its own launchd PATH" {
  local p="${QOS_PATH//\$HOME/$HOME}" out load
  # --no-append: never touch the operator's live census log from a test.
  out="$(env -i PATH="$p" HOME="$HOME" bash "$QOS" --json --no-append 2>/dev/null)"
  [ -n "$out" ] || { echo "qos-census produced no output on PATH=$p"; false; }
  load="$(printf '%s' "$out" | sed -n 's/.*"loadavg1":"\([^"]*\)".*/\1/p')"
  echo "loadavg1=[$load]"
  [ -n "$load" ] || { echo "no loadavg1 field in: $out"; false; }
  [ "$load" != "?" ] || { echo "loadavg1 is still the unreadable placeholder on the launchd PATH"; false; }
  # A number, not merely non-empty — "?" is not the only way this can be a non-value.
  case "$load" in ''|*[!0-9.]*) echo "loadavg1=[$load] is not numeric"; false ;; esac
}

@test "qos-census renders '?' — never a number — when sysctl is genuinely unreachable" {
  # The seam is set-but-EMPTY, which is honored verbatim; this is the ONLY way to reach the
  # unreadable branch on a host where /usr/sbin/sysctl exists. Without it this direction is untested
  # and the fallback could rot into rendering 0 again.
  local p="${QOS_PATH//\$HOME/$HOME}" out load
  out="$(env -i PATH="$p" HOME="$HOME" QOS_CENSUS_SYSCTL= bash "$QOS" --json --no-append 2>/dev/null)"
  [ -n "$out" ] || { echo "qos-census produced no output with the probe disabled"; false; }
  load="$(printf '%s' "$out" | sed -n 's/.*"loadavg1":"\([^"]*\)".*/\1/p')"
  echo "loadavg1=[$load]"
  [ "$load" = "?" ] || { echo "unreadable sysctl rendered [$load]; must be '?', never a number"; false; }
}

# ── postland-verify: the resolution block + load1(), replayed from the shipping file ─────────────

# Extract the REAL block rather than restating it. The anchor is asserted to match exactly once, so
# a rename or a second copy fails loudly instead of silently testing nothing.
plv_block() {
  sed -n '/^# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea/,/^}$/p' "$PLV"
}

@test "postland-verify's sysctl resolution block is findable exactly once" {
  local n; n="$(grep -c '^# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea' "$PLV")"
  [ "$n" -eq 1 ] || { echo "anchor matched $n times — the extraction below is unreliable"; false; }
  local blk; blk="$(plv_block)"
  [ -n "$blk" ] || { echo "extracted an empty block"; false; }
  printf '%s' "$blk" | grep -q 'load1()' || { echo "block does not contain load1(); extraction is wrong:"; echo "$blk"; false; }
}

@test "postland-verify resolves sysctl absolutely and load1 answers on its own launchd PATH" {
  local p="${PLV_PATH//\$HOME/$HOME}" inc="$BATS_TEST_TMPDIR/blk.sh"
  plv_block > "$inc"
  run env -i PATH="$p" HOME="$HOME" bash -c "source '$inc'; printf '%s|%s' \"\$SYSCTL_BIN\" \"\$(load1)\""
  [ "$status" -eq 0 ] || { echo "sourcing the block failed: $output"; false; }
  echo "resolved|load = $output"
  local bin="${output%%|*}" load="${output#*|}"
  [ "$bin" = "/usr/sbin/sysctl" ] || { echo "resolved [$bin], expected /usr/sbin/sysctl"; false; }
  [ -n "$load" ] || { echo "load1 was empty on the launchd PATH — the instrument is still blind"; false; }
  case "$load" in ''|*[!0-9.]*) echo "load1=[$load] is not numeric"; false ;; esac
}

@test "postland-verify's seam honors set-but-EMPTY verbatim (the probe can be turned OFF)" {
  # A seam that cannot disable the thing is not a seam, and the unreadable branch would be untestable.
  local p="${PLV_PATH//\$HOME/$HOME}" inc="$BATS_TEST_TMPDIR/blk.sh"
  plv_block > "$inc"
  run env -i PATH="$p" HOME="$HOME" CC_POSTLAND_SYSCTL_BIN= bash -c "source '$inc'; printf '[%s][%s]' \"\$SYSCTL_BIN\" \"\$(load1)\""
  [ "$status" -eq 0 ] || { echo "sourcing the block failed: $output"; false; }
  [ "$output" = "[][]" ] || { echo "expected both empty with the probe disabled, got $output"; false; }
}

@test "an unreadable load is stamped '?' and never '0' in either postland record" {
  # The whole point of the item: `${l:-0}` made a dead instrument read as an idle machine. Assert on
  # the RENDERING defaults in the shipping file, both sites (the stamp and the flake row).
  run grep -n 'load":"%s"' "$PLV"
  [ "$status" -eq 0 ]
  grep -q '"${l:-?}"' "$PLV" || { echo "env_fingerprint no longer defaults load to '?'"; false; }
  grep -q '"${load:-?}"' "$PLV" || { echo "record_flake no longer defaults loadavg to '?'"; false; }
  # The exact pre-fix defaults must be gone, not merely joined by the new ones.
  ! grep -q '"${l:-0}"' "$PLV" || { echo "the '0' default survives in env_fingerprint"; false; }
  ! grep -q '"${load:-0}"' "$PLV" || { echo "the '0' default survives in record_flake"; false; }
}

# ── the class guard: no /usr/sbin binary may be re-introduced by bare name in these files ────────

@test "CLASS: every sysctl/lsof/taskpolicy call word in these scripts is absolute or a variable" {
  # Not a re-implementation of unattended-path-lint — a tight, file-scoped assertion that the three
  # /usr/sbin binaries these scripts use are never invoked by bare name in COMMAND position.
  # `command -v <name>` is a lookup, not an invocation, and is the sanctioned fallback rung.
  local f bad="" hits
  for f in "$PLV" "$QOS" "$REPO/scripts/team-orphan-reaper.sh"; do
    # command position = start of line / after ( { | & ; or $( — excluding `command -v` lookups.
    hits="$(grep -nE '(^|[;&|(){]|\$\()[[:space:]]*(sysctl|lsof|taskpolicy)[[:space:]]' "$f" \
            | grep -vE 'command -v' || true)"
    [ -z "$hits" ] || bad="$bad
$(basename "$f"):
$hits"
  done
  [ -z "$bad" ] || { echo "bare-name /usr/sbin invocation(s) in command position:$bad"; false; }
}
