#!/usr/bin/env bats
# Launcher temp-file hardening — codex-security 2026-07-29 finding 2 (CWE-377 / CWE-59).
#
# THE DEFECT: three sites wrote a shell script to a PREDICTABLE path under mode-1777 /tmp, chmod
# +x'd it, and then executed it BY PATH from another process. The sticky bit stops another uid
# replacing a file we already own; it does NOT stop that uid pre-creating a name that does not
# exist yet. A planted symlink turns the `>` into an arbitrary-file clobber plus a chmod +x on the
# target; a planted 0666 regular file leaves attacker-controlled bytes at a path we then execute.
#
# THE TRAP IN THE PRESCRIBED FIX, which these tests exist to keep closed: the finding's own
# remediation reads `mktemp "${TMPDIR:-/tmp}/lr-poller-launch-XXXXXXXX.sh"`, and on macOS that is
# WORSE than the bug. BSD mktemp substitutes only a TRAILING `XXXXXX`, so a template with anything
# after the Xs creates the file named LITERALLY that — a CONSTANT, fully-predictable name (the
# finding itself rates a constant launcher name as MEDIUM) — and, because nothing ever removes it,
# every mint after the first dies `mkstemp failed … File exists` with EMPTY stdout, permanently
# breaking the fire path. Hence: mint the unique name first, add the suffix after.
#
# THE SECOND TRAP: `${TMPDIR:-/tmp}` alone is not a per-uid dir. Measured 2026-07-30 — launchd does
# not inject TMPDIR into LaunchAgent jobs (14 of 15 sampled user agents had it ABSENT), and
# lr-reset-poller's entire production role IS a LaunchAgent, so that fallback lands right back in
# 1777 /tmp exactly where it matters and the fix reads as applied while being inert.
#
# Hermetic: pure source-shape greps plus extract-and-eval of the real minting blocks into
# $BATS_TEST_TMPDIR. Nothing here touches the live ~/ or the real /tmp.

setup() {
  # Rule 1 of scripts/test-hermeticity-lint.sh — fixture $HOME so nothing here can read or mutate
  # the operator's live ~/.claude state. Nothing in this suite needs a real HOME (paths derive from
  # $BATS_TEST_FILENAME and $BATS_TEST_TMPDIR; the resolver probes come from getconf, not $HOME).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Rule 2 — this suite reads handoff-fire.sh, and the lint scopes by reference rather than by
  # whether a fire actually happens (keying on the mention would exempt exactly the suite that
  # goes red-by-load). Pinning the gate off costs nothing here and keeps the rule honest.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  LRH="$REPO/scripts/limit-recover/lr-handoff.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  STICKY="$REPO/scripts/iterm-clear-sticky-command.sh"
  SANDBOX="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$SANDBOX"
}

# ── the location axis ──────────────────────────────────────────────────────────────────

@test "no write-then-execute site hardcodes a /tmp path for its launcher" {
  # The three assignments the finding named. A future edit that moves any of them back to a
  # literal /tmp re-opens the hole silently — nothing else in the suite would notice.
  run grep -nE '^\s*(launcher|launch_dir)=.*"/tmp' "$POLLER"
  [ "$status" -ne 0 ] || { echo "poller launcher back on literal /tmp: $output"; false; }
  run grep -nE '^\s*LAUNCHER=.*"?/tmp/' "$LRH"
  [ "$status" -ne 0 ] || { echo "lr-handoff LAUNCHER back on literal /tmp: $output"; false; }
  run grep -nE '^\s*(cmdfile|log)="/tmp/' "$HF"
  [ "$status" -ne 0 ] || { echo "handoff-fire recycle files back on literal /tmp: $output"; false; }
}

@test "each site allocates through mktemp rather than a composed name" {
  grep -q 'mktemp "\$launch_dir/lr-poller-launch-' "$POLLER" \
    || { echo "poller no longer mints via mktemp"; false; }
  grep -q 'mktemp "\$(lrh_tmpdir)/lr-launch-' "$LRH" \
    || { echo "lr-handoff no longer mints via mktemp"; false; }
  grep -q 'mktemp "\${TMPDIR:-/tmp}/handoff-recycle-cmd-' "$HF" \
    || { echo "handoff-fire cmdfile no longer mints via mktemp"; false; }
  grep -q 'mktemp "\${TMPDIR:-/tmp}/handoff-recycle-\$SID' "$HF" \
    || { echo "handoff-fire watcher log no longer mints via mktemp"; false; }
}

# ── the entropy axis (the trap in the prescribed fix) ──────────────────────────────────

@test "every launcher template ends in a TRAILING XXXXXX — a suffixed template is a constant name" {
  # Any mktemp template in these three files whose X-run is followed by another character.
  # The character class deliberately EXCLUDES X: `X{3,}[A-Za-z…]` would match its own X-run
  # (X is in A-Za-z) and report every correct template as a violation.
  # `^[^#]*mktemp` + `sed 's/#.*//'` keep this to CODE. Without them the rule matches the prose in
  # this repo's own comments — the header above literally spells `-XXXXXX.sh` while explaining why
  # it is forbidden, and a lint that convicts its own documentation is the prose-match hole.
  local f hits=""
  for f in "$POLLER" "$LRH" "$HF"; do
    local h
    h="$(grep -nE '^[^#]*mktemp' "$f" | sed 's/#.*//' \
         | grep -E 'X{3,}[A-WYZa-wyz0-9._/-]' || true)"
    [ -z "$h" ] || hits="$hits
$(basename "$f"): $h"
  done
  [ -z "$hits" ] || { echo "suffixed mktemp template(s) — these mint a CONSTANT name:$hits"; false; }
}

@test "POSITIVE CONTROL: on this host a suffixed template really does yield a constant, colliding name" {
  # Proves the guard above discriminates instead of passing vacuously — the shape the finding
  # prescribed, run against this machine's real mktemp, must misbehave exactly as described.
  local a b
  a="$(mktemp "$SANDBOX/pc-XXXXXXXX.sh" 2>/dev/null || true)"
  if [ "$a" != "$SANDBOX/pc-XXXXXXXX.sh" ]; then
    skip "this host's mktemp is suffix-aware (GNU); the prescribed shape cannot collide here"
  fi
  [ -f "$a" ]                                              # the literal name was created
  # stdout captured on its OWN (bats `run` merges stderr, which would hide the empty-stdout fact
  # behind mktemp's error text — and empty stdout is the half that breaks `x="$(mktemp …)"`).
  local second_out; second_out="$(mktemp "$SANDBOX/pc-XXXXXXXX.sh" 2>/dev/null || true)"
  [ -z "$second_out" ] || { echo "expected empty stdout on the colliding mint; got: $second_out"; false; }
  run mktemp "$SANDBOX/pc-XXXXXXXX.sh"
  [ "$status" -ne 0 ] || { echo "expected the second mint to collide; it succeeded"; false; }
  # …and the trailing-X form, the shape we actually ship, does NOT collide.
  a="$(mktemp "$SANDBOX/ok-XXXXXX")"; b="$(mktemp "$SANDBOX/ok-XXXXXX")"
  [ "$a" != "$b" ] || { echo "trailing-X template collided: $a"; false; }
}

@test "mktemp refuses a pre-created symlink rather than following it (the O_EXCL half)" {
  # The other axis the fix buys: even a correctly-guessed name cannot become a clobber.
  ln -s "$SANDBOX/CLOBBER-TARGET" "$SANDBOX/planted-AAAAAA"
  run mktemp "$SANDBOX/planted-AAAAAA"
  [ "$status" -ne 0 ] || { echo "mktemp followed a planted symlink"; false; }
  [ ! -e "$SANDBOX/CLOBBER-TARGET" ] || { echo "symlink target was clobbered"; false; }
}

# ── the per-uid axis (launchd injects no TMPDIR) ───────────────────────────────────────

@test "the poller's tmpdir resolver reaches a per-uid dir even with TMPDIR unset" {
  local fn; fn="$(sed -n '/^lrp_tmpdir() {/,/^}/p' "$POLLER")"
  [ -n "$fn" ] || { echo "could not extract lrp_tmpdir"; false; }
  eval "$fn"
  local got; got="$(unset TMPDIR; lrp_tmpdir)"
  [ -n "$got" ] || { echo "resolver returned empty"; false; }
  # On a Darwin box the confstr dir must win. Falling through to /tmp here is the exact
  # silent-inertness this resolver exists to prevent, so it fails the test rather than warning.
  if getconf DARWIN_USER_TEMP_DIR >/dev/null 2>&1; then
    [ "$got" != "/tmp" ] || { echo "resolver fell back to 1777 /tmp despite a working getconf"; false; }
    [ -d "$got" ] || { echo "resolved dir does not exist: $got"; false; }
    [ -O "$got" ] || { echo "resolved dir is not owned by this uid: $got"; false; }
  fi
}

@test "lr-handoff carries the same resolver, not a bare \${TMPDIR:-/tmp}" {
  local fn; fn="$(sed -n '/^lrh_tmpdir() {/,/^}/p' "$LRH")"
  [ -n "$fn" ] || { echo "could not extract lrh_tmpdir"; false; }
  eval "$fn"
  local got; got="$(unset TMPDIR; lrh_tmpdir)"
  if getconf DARWIN_USER_TEMP_DIR >/dev/null 2>&1; then
    [ "$got" != "/tmp" ] || { echo "lr-handoff resolver fell back to 1777 /tmp"; false; }
  fi
}

# ── behavioural: the real minting blocks, executed twice ───────────────────────────────

@test "poller: two mints for one sid differ, are executable-ready and keep .sh" {
  # Executes the REAL source lines, so this goes RED against the pre-fix tree.
  local mint; mint="$(sed -n '/^    launch_dir=/,/^    mv "\$launcher" "\$launcher.sh"/p' "$POLLER")"
  [ -n "$mint" ] || { echo "could not extract the poller minting block"; false; }
  # `sid` is read by the extracted block through eval, and `launcher` is ASSIGNED by it — neither
  # data flow is visible to static analysis, which sees one write-only and one read-only variable.
  # Declaring `launcher` here is the honest fix rather than a blanket suppression: it makes the
  # variable genuinely local to this test (an eval'd assignment would otherwise leak to the file
  # scope and let one case's value satisfy the next), and it leaves SC2154 free to fire for real.
  # shellcheck disable=SC2034  # sid: consumed by the extracted block via eval
  local sid="aaaa0001-1111-2222-3333-444444444444" first second launcher=""
  log() { :; }
  export LR_POLLER_LAUNCH_DIR="$SANDBOX"
  eval "$mint"; first="$launcher"
  eval "$mint"; second="$launcher"
  [ -f "$first" ]  || { echo "first mint produced no file"; false; }
  [ -f "$second" ] || { echo "second mint produced no file (the collision bug)"; false; }
  [ "$first" != "$second" ] || { echo "both mints returned the SAME path: $first"; false; }
  [ "${first%.sh}" != "$first" ] || { echo "launcher lost its .sh suffix: $first"; false; }
  # the sid stays a readability prefix — but it must not be the whole entropy budget
  case "$(basename "$first")" in lr-poller-launch-aaaa0001-*) : ;;
    *) echo "readability prefix lost: $first"; false ;; esac
}

@test "handoff-fire recycle: cmdfile and log mint under the dir session-end.sh actually sweeps" {
  # The reaper (hooks/session-end.sh) globs `handoff-recycle-*` at -maxdepth 1 over
  # ${CC_TMP_SWEEP_DIRS:-${TMPDIR:-/tmp} /private/tmp}. Producer and reaper must resolve the same
  # dir with the same expression or these leak forever — so assert the shared expression by shape.
  grep -q 'mktemp "\${TMPDIR:-/tmp}/handoff-recycle-' "$HF" \
    || { echo "handoff-fire no longer mints with the expression session-end sweeps"; false; }
  grep -q 'CC_TMP_SWEEP_DIRS:-\${TMPDIR:-/tmp}' "$REPO/hooks/session-end.sh" \
    || { echo "session-end sweep dirs changed — re-check the producer/reaper pairing"; false; }
  # and the prefix the sweep's -name glob keys on survives the mktemp rename
  grep -q "name 'handoff-recycle-\*'" "$REPO/hooks/session-end.sh" \
    || { echo "session-end no longer globs handoff-recycle-*"; false; }
}

# ── the coupled consumer ───────────────────────────────────────────────────────────────

@test "the sticky-command repair regex still matches a launcher under the per-uid TMPDIR" {
  # scripts/iterm-clear-sticky-command.sh repairs panes pinned to a generated launcher. It used to
  # anchor on /tmp/, so moving the producers would have silently degraded it to a no-op — it skips
  # non-matching commands and still exits 0 with a success summary, so nothing would have surfaced.
  local rx; rx="$(grep -oE 'LAUNCHER = re\.compile\(r".*"\)' "$STICKY")"
  [ -n "$rx" ] || { echo "could not extract the LAUNCHER regex"; false; }
  run python3 - "$STICKY" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'LAUNCHER = re\.compile\(r"(.*?)"\)', src)
assert m, "regex not found"
rx = re.compile(m.group(1))
must_match = [
    "/bin/bash /var/folders/0s/abc123/T/lr-launch-076a1186-Ab3xQ1.sh",
    "/bin/bash /var/folders/0s/abc123/T/lr-poller-launch-eeeeeeee-Zz9Kp2.sh",
    "/bin/bash /var/folders/0s/abc123/T/handoff-recycle-cmd-UUID-123-Qq1.sh",
    "/bin/bash /tmp/lr-launch-076a1186.sh",              # legacy panes still repairable
]
must_not = [
    "/usr/local/bin/my-own-launcher.sh",                  # operator-owned
    "vim /etc/passwd",
    "/bin/bash /Users/me/projects/lr-launch-notours/x.py",
]
for c in must_match:
    assert rx.search(c), f"FAILED to match generated launcher: {c}"
for c in must_not:
    assert not rx.search(c), f"wrongly matched operator-owned command: {c}"
print("ok")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
