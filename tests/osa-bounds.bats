#!/usr/bin/env bats
#
# osa-bounds.bats — M5. The STANDING check that no osascript call in this repo can wait forever.
#
# WHY. An `osascript` call is an AppleEvent into another application, and an AppleEvent has no
# timeout of its own. If the target app (iTerm2, Dia, System Events, NotificationCenter) is wedged,
# sitting on its own modal, or paging under load, the call does not fail — it waits. The 2026-07-26
# machine-wide iTerm2/AppleEvent wedge is the incident this guards. Every osascript call site in this
# repo is best-effort (`|| true`, `2>/dev/null`), so a CUT costs one notification or one window
# activation; a HANG costs the hook, launchd job or crash handler that made the call. That asymmetry
# is the whole argument, and it is why the rule is "bounded everywhere", not "bounded where it seems
# to matter".
#
# WHY A GREP AND NOT A CODE CHANGE. The bound has to hold for call sites that do not exist yet.
# Converting today's sites fixes today; a standing lint is what makes the NEXT bare osascript fail
# in the gate instead of in production at 2am.
#
# THE CORRECTION. The obvious expression — grep for `osascript` — is useless here: this repo mentions
# the word in prose, in report strings, in a python argv list, and in a variable assignment, and it
# wraps real calls in per-file bounding helpers (`lcw_osa`, `wrc_osa`, `nty_osa`, …) that a naive
# pattern reads as unbounded. A check that fires on 20 healthy lines is functionally a deleted check —
# nobody reads its output twice. So the scan below is anchored to osascript in COMMAND POSITION with
# an actual flag after it, and every exclusion below is a NAMED class, not a blanket carve-out.
#
# EXEMPTION, stated rather than hidden: `osascript -e 'delay <n>'` is a sleep implemented in the
# osascript interpreter with NO target application. It cannot block on another process's event loop,
# which is the entire hazard. The pattern is narrow enough that no call carrying a `tell application`
# can launder itself through it, and the exempted lines are printed by the tree test rather than
# silently dropped.
#
# RED-PROOF: fails against the pristine pre-change tree, where hooks/lib/osa.sh does not exist and
# bin/screenshot-to-clipboard.sh:18 + bin/dia-cdp-launch.sh:322 are bare calls:
#   t=$(mktemp -d); git archive eaa0cdeb | tar -x -C "$t"
#   CC_OSA_SUBJECT_ROOT="$t" bats tests/osa-bounds.bats
#
# DEAD-ASSERTION DISCIPLINE: bats bodies run under `set -eET`, and bash exempts `[[ ]]`, `(( ))` and
# `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` where needed.
#
# GREP IS PINNED to /usr/bin/grep. The interactive shell here resolves `grep` to ugrep, whose ERE
# dialect differs (it rejects an empty alternation outright), so an unpinned scan would encode which
# grep the PATH happened to offer and could return a different verdict in the gate than on the desk.

BATS_TEST_TIMEOUT=180

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_OSA_SUBJECT_ROOT:-$REPO}"
  LIB="$ROOT/hooks/lib/osa.sh"
  G=/usr/bin/grep
  D="$BATS_TEST_TMPDIR"
}

# ── the scan: ONE implementation, used by both controls AND the tree assertion ──────────────────
# A control that exercised a re-typed copy of the expression would prove nothing about the
# expression the tree is actually judged by.
ac22_scan() { # <path>… → hazardous "file:line:text" rows
  "$G" -rnE '^[^#]*(^|[[:space:];&|(`])osascript[[:space:]]+-' "$@" 2>/dev/null \
    | "$G" -vE '[a-z0-9_]+_(osa|bounded)[[:space:]]+osascript' \
    | "$G" -vE 'timeout[[:space:]]+[0-9]' \
    | "$G" -vE 'command -v' \
    | "$G" -vE 'additionalContext' \
    | "$G" -vE "osascript -e '(delay)[[:space:]]+[0-9.]+'"
}

# The counterpart to that last exclusion, and the reason it is safe. `delay N` runs inside the
# osascript interpreter — no `tell application`, no target process, so it cannot block on another
# app's event loop (measured: `osascript -e 'delay 2'` returns in 2.045s wall clock). That makes the
# 4 real sites in scripts/handoff-fire.sh portable sleeps rather than AppleEvents, and exempting them
# correct. But the exclusion above is a LINE-scoped `grep -v`, so it exempts everything else on the
# line too. This is the check that the exemption is not carrying a passenger: strip the delay
# invocations, and anything left that still calls out is a real, unbounded site.
# ONE implementation, exercised by both the tree assertion and its positive control below.
delay_launder(){ # <path>… → delay-exempt rows carrying another call (empty = clean)
  "$G" -rnE "osascript -e '(delay)[[:space:]]+[0-9.]+'" "$@" 2>/dev/null \
    | sed -E "s/osascript -e '(delay)[[:space:]]+[0-9.]+'/<DELAY>/g" \
    | "$G" -E 'osascript|tell application' || true
}

# ── POSITIVE CONTROL: the scan can FAIL ─────────────────────────────────────────────────────────
@test "AC22 control (+): a bare osascript call IS caught" {
  mkdir -p "$D/pos"
  printf '#!/bin/bash\nosascript -e %s\n' "'tell application \"Finder\" to activate'" > "$D/pos/bare.sh"
  n="$(ac22_scan "$D/pos" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "the scan did NOT catch a bare osascript (n=$n) — it cannot fail, so a green tree means nothing"; false; }
}

@test "AC22 control (+): a bare call mid-pipeline, not at line start, is still caught" {
  # Anchoring only to the start of a line would miss every call in a compound command — the shape
  # most of this repo's real call sites actually have.
  mkdir -p "$D/pos2"
  printf '#!/bin/bash\ntrue && osascript -e %s || true\n' "'tell application \"iTerm2\" to activate'" > "$D/pos2/mid.sh"
  n="$(ac22_scan "$D/pos2" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "a mid-command bare call escaped the scan (n=$n)"; false; }
}

# ── NEGATIVE CONTROLS: the scan does not fire on bounded or non-call lines ──────────────────────
@test "AC22 control (-): a wrapper-bounded call (hf_bounded / osa_bounded) is NOT flagged" {
  mkdir -p "$D/neg"
  {
    printf '#!/bin/bash\n'
    printf 'hf_bounded osascript -e %s\n'  "'tell application \"iTerm2\" to activate'"
    printf 'osa_bounded osascript -e %s\n' "'tell application \"Dia\" to activate'"
    printf 'lcw_osa osascript -e %s\n'     "'display notification \"x\"'"
    printf 'timeout 10 osascript -e %s\n'  "'display notification \"x\"'"
  } > "$D/neg/bounded.sh"
  n="$(ac22_scan "$D/neg" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "the scan flagged a BOUNDED call — a check that fires on healthy lines gets ignored:"; ac22_scan "$D/neg"; false; }
}

@test "AC22 control (-): prose, assignments and comments are NOT flagged" {
  # Every one of these is a real shape from this repo that a naive `grep osascript` reports.
  mkdir -p "$D/neg2"
  {
    printf '#!/bin/bash\n'
    printf '# osascript -e "commented out"\n'
    printf 'OSASCRIPT="${CC_OSASCRIPT_BIN:-osascript}"\n'
    printf 'echo "note: osascript window-open fails when headless"\n'
    printf 'if command -v osascript >/dev/null; then :; fi\n'
    printf "osascript -e 'delay 2' >/dev/null 2>&1\n"
  } > "$D/neg2/prose.sh"
  n="$(ac22_scan "$D/neg2" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "false positives on non-call lines:"; ac22_scan "$D/neg2"; false; }
}

# ── THE STANDING ASSERTION ──────────────────────────────────────────────────────────────────────
@test "AC22: zero unbounded osascript calls across hooks/ bin/ scripts/" {
  rows="$(ac22_scan "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" || true)"
  n="$(printf '%s' "$rows" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "UNBOUNDED osascript call site(s) — each can wait forever on a wedged app:"; printf '%s\n' "$rows"; false; }
}

@test "AC22: the delay-exemption is reported, never silently dropped" {
  # An exemption nobody can see is indistinguishable from a hole. If this list ever grows something
  # that is not a bare interpreter delay, it is visible in the gate output.
  ex="$("$G" -rnE "osascript -e '(delay)[[:space:]]+[0-9.]+'" "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" 2>/dev/null || true)"
  echo "delay-exempt sites (no target app, cannot block on another process):"
  printf '%s\n' "$ex"
  bad="$(delay_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" | "$G" -c . || true)"
  [ "$bad" -eq 0 ] || { echo "a real call laundered itself through the delay exemption:"; delay_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts"; false; }
}

@test "AC22 control (+): a real call sharing a line with a delay does NOT escape the exemption" {
  # The exemption is only sound while a delay is the ONLY call on its line, and nothing in ac22_scan
  # can enforce that — its delay filter is a line-scoped `grep -v`, so a second, genuinely unbounded
  # call sharing the line is exempted along with the delay. Verified 2026-07-30 with exactly this
  # fixture: it escaped both ac22_scan AND the previous `tell application`-only guard, because
  # `display notification` names no application while still being a real AppleEvent (NotificationCenter).
  mkdir -p "$D/laund"
  {
    printf '#!/bin/bash\n'
    printf "osascript -e 'delay 2'; osascript -e 'display notification \"x\"'\n"
  } > "$D/laund/l.sh"
  s="$(ac22_scan "$D/laund" | "$G" -c . || true)"
  [ "$s" -eq 0 ] || { echo "precondition changed: ac22_scan now catches this unaided, so this guard's premise needs re-deriving"; false; }
  n="$(delay_launder "$D/laund" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "the laundering guard did not fire (n=$n) — the delay exemption is a hole"; false; }
}

# ── the shared lib ──────────────────────────────────────────────────────────────────────────────
@test "osa.sh exists and its bound is REAL (a slow command is actually cut)" {
  [ -r "$LIB" ] || { echo "hooks/lib/osa.sh missing"; false; }
  # Positive control for the BOUND itself: without this, "osa_bounded ran" proves only that a
  # function exists, not that anything is bounded.
  run env CC_OSA_TIMEOUT_S=1 bash -c ". '$LIB'; osa_bounded sleep 20"
  [ "$status" -eq 124 ]
}

@test "osa.sh: a normal command passes through with its own exit status" {
  run bash -c ". '$LIB'; osa_bounded printf hi"
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  run bash -c ". '$LIB'; osa_bounded false"
  [ "$status" -eq 1 ]
}

@test "osa.sh: CC_OSA_TIMEOUT_BIN set-but-EMPTY genuinely disables the bound" {
  # `${VAR:-}` cannot tell unset from set-empty, so a seam written that way can never be turned OFF —
  # and a suite that cannot run the unbounded path cannot prove the bounded path differs from it.
  run env CC_OSA_TIMEOUT_BIN= CC_OSA_TIMEOUT_S=1 bash -c ". '$LIB'; [ -z \"\$CC_OSA_TB\" ] || exit 9; osa_bounded printf ok"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "osa.sh: with no timeout binary it degrades to UNBOUNDED, never to a lost call" {
  # Failing closed here would silently delete every notification on a machine without coreutils —
  # permanent, unlike the occasional hang it would be preventing.
  run env CC_OSA_TIMEOUT_BIN=/nonexistent/timeout bash -c ". '$LIB'; osa_bounded printf through"
  [ "$status" -eq 0 ]
  [ "$output" = "through" ]
}

# ── the two converted sites ─────────────────────────────────────────────────────────────────────
@test "converted: screenshot-to-clipboard and dia-cdp-launch call through osa_bounded" {
  for f in "$ROOT/bin/screenshot-to-clipboard.sh" "$ROOT/bin/dia-cdp-launch.sh"; do
    [ -r "$f" ] || { echo "missing $f"; false; }
    "$G" -qE 'osa_bounded osascript' "$f" || { echo "$f still calls osascript unbounded"; false; }
    # The lib must be reached through $0's PHYSICAL location: ~/bin holds per-file symlinks into the
    # checkout, and a directory of per-file symlinks never gains a NEW file.
    "$G" -qE 'readlink' "$f" || { echo "$f does not resolve \$0's symlink before sourcing the lib"; false; }
    "$G" -qE 'osa_bounded\(\) \{ timeout' "$f" || { echo "$f has no inline fallback if the lib is unreadable"; false; }
  done
}
