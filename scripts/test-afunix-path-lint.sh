#!/bin/bash
# shellcheck disable=SC2016  # file-wide: single quotes are load-bearing here in two places — the
# guidance text prints the literal python the author must paste (expanding it would substitute this
# shell's values into the prescribed fix), and every --selftest fixture body is written VERBATIM
# into a .bats file, where `$1` and `sys.argv[1]` must arrive unexpanded or the case asserts nothing.
# test-afunix-path-lint — a RATCHET on AF_UNIX sockets bound by ABSOLUTE path in bats fixtures.
#
# WHY: Darwin caps `sun_path` at 104 bytes, and the cap applies to THE STRING HANDED TO bind(2) —
# not to where the file ends up. A fixture that binds "$BATS_TEST_TMPDIR/sock/kitty-42" charges the
# whole tmpdir prefix against a budget it does not control. That prefix is:
#
#     $TMPDIR  +  postland-run.XXXXXX  +  bats-run-XXXX/test/NN  +  THE TEST'S OWN NAME
#
# and only the last term is visible in the file. Under an operator's short TMPDIR (/tmp/… ) it fits;
# under launchd's 49-byte /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/ plus postland's 21-byte
# run dir (scripts/postland-verify.sh:1050,1104) it does not.
#
# THE POLARITY IS THE WHOLE PROBLEM, and it is the worst possible one: the suite is GREEN in every
# hand-check and RED only inside postland-verify — including green under the re-run command postland
# itself prints, which uses a SHORT /tmp/pv-repro. So the operator's own repro EXONERATES the file.
# Measured cost of that polarity: tests/boot-resume-launch.bats was in 17 of 17 postland reds from
# 2026-08-08T07:44 to 2026-08-09T22:39 — 40 hours in which NO green stamp existed, deploy-live
# refused every sweep, and every commit that landed on trunk stayed out of the live ~/.claude layer.
#
# THE FIX IS ALWAYS THE SAME SHAPE — chdir to the directory and bind the BASENAME:
#     /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); \
#                          os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
# It spends ~10 bytes instead of ~130 and changes nothing else: the socket still lands at the same
# absolute path, so `[ -S "$1" ]` still asserts it there.
#
# WHY A LINT AND NOT A FIFTH HAND-FIX. This defect has now been found twice, by two different
# sessions, in four files. Item e1d43f93da19 fixed tests/kitty-socket-address.bats and
# tests/handoff-fire-kitty-daemon.bats on 2026-08-06 and wrote the correct explanation into both —
# then tests/boot-resume-launch.bats and tests/cc-kitty-socket.bats reddened trunk for the next
# three days carrying the identical bug. A per-file fix cannot see its own class; only a whole-tree
# assertion can. (memory: enforcement-must-live-at-the-chokepoint, per-site-mutation-attributes-coverage)
#
# THE RULE, deliberately narrow so it can BLOCK a land without crying wolf. A `.bind(` in a .bats
# file is a violation when BOTH hold:
#   (a) AF_UNIX is in scope — on the same line or within the preceding few non-comment lines. An
#       AF_INET bind has no path at all and is out of scope by construction: tests/cc-authbrowser.bats
#       binds ("127.0.0.1", port) and must stay legal (pinned as a GREEN selftest case).
#   (b) the bind is not the proven-safe shape — `os.chdir(` in scope AND the bind argument is a bare
#       identifier. `bind(sys.argv[1])`, `bind("$T/sock")` and friends are all absolute-capable, and
#       a chdir with an absolute argument is still absolute — so BOTH halves are required.
#
# KNOWN LIMIT, stated rather than hidden: this reads bats fixtures only, and only Python binds.
# A shell-level `socat UNIX-LISTEN:` / `nc -lU` has the same 104-byte cap and is NOT caught here
# (the corpus has no such site today — checked 2026-08-09). Do not read a green here as "no
# oversized socket path anywhere".
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unreadable scan dir (LOUD, never silent-green)
#
# Env seams: CC_AFUNIX_ALLOWLIST overrides the embedded ratchet · CC_AFUNIX_OWN scopes which
# violations may BLOCK (see OWN-SCOPE, identical contract to test-walltime-lint) ·
# CC_AFUNIX_WINDOW sets how many preceding non-comment lines count as "in scope" (default 6).
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the ratchet: suites grandfathered with an absolute AF_UNIX bind. ONLY EVER DELETE LINES. ──
# EMPTY BY CONSTRUCTION, and that is a deliberate choice rather than an accident of timing: all four
# known sites were fixed before this lint landed, so there is no grandfathered debt to erode. An
# entry added here later must carry the same standard its sibling ratchets use — CHECKED and
# explained, never an unexamined hit, because that is how a ratchet decays into an exemption list.
EMBEDDED_ALLOWLIST=""

# How many preceding non-comment lines count as "in scope". 6 covers every real shape in this corpus:
# the one-liner (`import os,socket,sys; …; os.chdir(d); …bind(b)`, everything on one line) and the
# heredoc block (`s = socket.socket(socket.AF_UNIX)` then `s.bind(…)`, 1-3 lines apart). Read at CALL
# time, not load time — a load-time global cannot be overridden by an env prefix on the function,
# which is exactly how test-walltime-lint's horizon once went inert with a vacuous selftest case.
window_lines() { printf '%s' "${CC_AFUNIX_WINDOW:-6}"; }

# OWN-SCOPE — identical contract to test-walltime-lint / test-hermeticity-lint, built in from day one:
# a whole-tree blocking lint is a FLEET-WIDE hard stop (a lander refused over a suite it never
# touched). THREE states: own-set ABSENT ⇒ strict whole-tree; SET-BUT-EMPTY ⇒ "I change no suite" ⇒
# nothing blocks; SET ⇒ block on those only. `${VAR:-}` cannot express that, so presence rides on
# argument count here and `${CC_AFUNIX_OWN+set}` at the entry point.
in_own() {  # $1=basename · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  # DRAINED, not -q: this pipeline is the FUNCTION-FINAL statement, so its rc IS the answer every
  # caller reads. Under the `set -uo pipefail` above, `grep -q` exits on the first match, `sed`
  # takes SIGPIPE, and pipefail returns 141 — a MATCH reading as NOT-IN-OWN-SCOPE, which downgrades
  # a bomb THIS LAND ADDED from BLOCKING to advisory. The three-stage form inverts far earlier than
  # the two-stage one — but ⚠️ the numbers this comment used to quote ("safe to 17,427 bytes and
  # ALWAYS inverted from 23,227", 20 trials, 2026-08-26) are REFUTED and were in the wrong UNIT:
  # re-measured 2026-08-28, 17,427 producer bytes is 0/200 at 13 B per line and 43-54/200 at 55 and
  # 149 B, and 23,227 is RACY at 137-149/200, not ALWAYS. THE BINDING QUANTITY IS WHAT THE `sed`
  # EMITS, not what the printf writes — 22,000 producer bytes held constant across six cells reads
  # 279/400 wrong at 18,000 emitted and 0/400 at 15,600. Full table + method: the header of
  # scripts/pipefail-sigpipe-lint.sh (the SSOT for these bands). LATENT here rather than live, and
  # the RIGHT ceiling to watch is the EMITTED one: this own-set is CHANGED PATHS, the whole .bats
  # corpus is 16,945 bytes of them, and the `sed 's:.*/::'` below reduces those to basenames, so
  # what reaches grep is smaller still. Measure it AFTER the sed. That ceiling still only grows.
  # ⚠️ THE "NO RATCHET WOULD HAVE CAUGHT THIS" CLAUSE THIS COMMENT CARRIED IS NOW FALSE FOR THIS
  # BODY AND STILL TRUE FOR ITS SIBLING TWO LINES BELOW, which is why it is corrected rather than
  # struck. `ca97c678b18b` (pipefail-sigpipe-lint cannot SEE a function-final pipeline) was CURED by
  # clause 4c — the FOURTEENTH CORRECTION in scripts/pipefail-sigpipe-lint.sh, which landed with its
  # caller half. Re-measured 2026-09-04 against the SHIPPED
  # detector, empty allowlist, one fixture per cell: a MULTI-LINE function-final
  # `printf | sed | grep -qxF` whose caller reads the rc (`if in_own …`) — this exact shape — IS
  # reported, beside an inline `if p | grep -q` FIRE control that also reports. The ONE-LINE
  # spelling `f() { … | grep -qxF …; }` that `in_allowlist` uses is NOT: clause 4c reads
  # function-final off the house shape `name() {` … `}` with the closing brace at column 0, which is
  # that correction's own residual (b) and is not this row's. So the drain below is now BOTH drained
  # and ratcheted; the drain two lines down is drained only.
  printf '%s\n' "$2" | sed 's:.*/::' | grep -xF "$1" >/dev/null
}

# DRAINED for the reason in in_own above — same shape, same pipefail, and this body IS the pipeline.
in_allowlist() { printf '%s\n' "$2" | grep -xF "$1" >/dev/null; }

# Absolute-capable AF_UNIX bind sites in one suite: "<lineno>:<trimmed source>", one per line.
# Comment lines are dropped first — prose describing the defect (this repo now has four files
# explaining it at length) must never be flagged, or people learn to ignore this lint.
afunix_bad_binds() { # $1=file
  awk -v win="$(window_lines)" '
    { line = $0 }
    # skip comments (bash # and python #) but KEEP the physical line number
    line ~ /^[[:space:]]*#/ { next }
    {
      # slide the window of recent non-comment source
      for (i = win; i > 1; i--) w[i] = w[i-1]
      w[1] = line
      ctx = ""
      for (i = 1; i <= win; i++) ctx = ctx " " w[i]

      if (line !~ /\.bind\(/) next
      if (ctx !~ /AF_UNIX/) next                     # (a) AF_INET and friends are out of scope

      # (b) the proven-safe shape: chdir in scope AND the bind argument is a bare identifier
      safe = 0
      if (ctx ~ /os\.chdir\(/ && line ~ /\.bind\([A-Za-z_][A-Za-z0-9_]*\)/) safe = 1
      if (safe) next

      t = line; sub(/^[[:space:]]+/, "", t)
      printf "%d:%s\n", NR, t
    }
  ' "$1" 2>/dev/null
}

# lint <tests-dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f base hits bad=0 seen=0 other=0 stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$dir" ] || { echo "test-afunix-path-lint: ⛔ not a directory: $dir" >&2; return 2; }
  for f in "$dir"/*.bats; do
    [ -e "$f" ] || continue
    seen=$((seen + 1)); base="$(basename "$f")"
    hits="$(afunix_bad_binds "$f")"
    if [ -n "$hits" ]; then
      if in_allowlist "$base" "$allow"; then
        continue                                   # grandfathered — known site, already on the list
      elif in_own "$base" "$own" "$own_scoped"; then
        printf '  ABS-BIND %s: AF_UNIX bind on an absolute path — chdir + bind the basename\n' "$base"
        printf '%s\n' "$hits" | sed 's/^/             /'
        bad=$((bad + 1))
      else
        printf '  abs?     %s: AF_UNIX bind on an absolute path (NOT in your diff — advisory, not blocking)\n' "$base"
        other=$((other + 1))
      fi
    elif in_allowlist "$base" "$allow"; then
      if in_own "$base" "$own" "$own_scoped"; then
        printf '  RATCHET  %s has no absolute AF_UNIX bind now — delete its allowlist line\n' "$base"
        stuck=$((stuck + 1))
      else
        printf '  ratchet? %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$base"
        other=$((other + 1))
      fi
    fi
  done
  [ "$seen" -gt 0 ] || { echo "test-afunix-path-lint: ⛔ no .bats suites under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "test-afunix-path-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bad" -gt 0 ]; then
    echo "test-afunix-path-lint: ⛔ $bad suite(s) above bind an AF_UNIX socket by absolute path."
    echo "  Why it matters: Darwin caps sun_path at 104 bytes against the string handed to bind(2)."
    echo "  Under a short TMPDIR the suite passes; inside postland-verify (launchd's /var/folders/…"
    echo "  plus postland-run.XXXXXX plus the test NAME) it raises 'AF_UNIX path too long' and the"
    echo "  whole tree goes red — while every hand-check, and postland's own printed re-run command,"
    echo "  keep saying green. That cost 40h of red trunk and a frozen live layer on 2026-08-08/09."
    # shellcheck disable=SC2016  # the single quotes are the POINT: this prints the literal python
    # the author must paste. Expanding it here would substitute this shell's values into the fix.
    echo '  Fix: os.chdir the directory, bind the BASENAME —'
    # shellcheck disable=SC2016  # ditto — literal guidance text, not an expansion
    echo '       /usr/bin/python3 -c '"'"'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)'"'"' "$1"'
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "test-afunix-path-lint: ⛔ $stuck suite(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "test-afunix-path-lint: clean — $seen suite(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 absolute AF_UNIX binds."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  for c in abs absheredoc safe inet chdirabs prose nobind; do mkdir -p "$d/$c"; done
  mk() { printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$d/$1/zz-fixture.bats"; }

  # Every fixture body below is written VERBATIM into a .bats file, so the single quotes are the
  # point: `$1` and `sys.argv[1]` must reach that file unexpanded. Expanding them here would bake
  # this shell's values into the fixture and make the cases assert nothing.
  # shellcheck disable=SC2016
  # RED: the two real shapes this defect took in this corpus.
  mk abs       'mksock() { python3 -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$1"; }'
  mk absheredoc 'mksock() {
  python3 - "$1" <<PYEOF
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
PYEOF
}'
  # GREEN: the proven-safe shape.
  mk safe      'mksock() { /usr/bin/python3 -c "import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)" "$1"; }'
  # GREEN: AF_INET has no path — tests/cc-authbrowser.bats must stay legal.
  mk inet      'mkport() { python3 -c "import socket,sys; s=socket.socket(); s.bind((\"127.0.0.1\", int(sys.argv[1])))" "$1"; }'
  # RED: chdir present but the bind argument is STILL absolute — half the fix is not the fix.
  mk chdirabs  'mksock() { python3 -c "import os,socket,sys; os.chdir(os.path.dirname(sys.argv[1])); socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$1"; }'
  # GREEN: the defect described in PROSE. Four files in this repo now do exactly this.
  mk prose     '# AF_UNIX .bind( an absolute path ) is the 104-byte defect — see e1d43f93da19
setup() { true; }'
  # GREEN: a suite with no socket at all.
  mk nobind    'setup() { true; }'

  fails=0
  lint_dir "$d/abs" ""        >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an absolute AF_UNIX bind (one-liner) did not go RED"; fails=1; }
  lint_dir "$d/absheredoc" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an absolute AF_UNIX bind (heredoc, AF_UNIX on an EARLIER line) did not go RED — the window is too narrow"; fails=1; }
  lint_dir "$d/chdirabs" ""   >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: chdir + an ABSOLUTE bind argument passed — the rule accepted half a fix"; fails=1; }
  lint_dir "$d/safe" ""       >/dev/null 2>&1 || { echo "SELFTEST FAIL: the proven-safe chdir+basename shape went RED"; fails=1; }
  lint_dir "$d/inet" ""       >/dev/null 2>&1 || { echo "SELFTEST FAIL: an AF_INET bind went RED — it has no path and is out of scope"; fails=1; }
  lint_dir "$d/prose" ""      >/dev/null 2>&1 || { echo "SELFTEST FAIL: the defect described in a COMMENT went RED — prose is not a fixture"; fails=1; }
  lint_dir "$d/nobind" ""     >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite with no socket went RED"; fails=1; }
  # the ratchet, both directions
  lint_dir "$d/abs"  "zz-fixture.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered absolute bind did not go GREEN"; fails=1; }
  lint_dir "$d/safe" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted suite did not go RED (ratchet not shrinking)"; fails=1; }
  # own-scope, all four states
  lint_dir "$d/abs" "" "other.bats"      >/dev/null 2>&1 || { echo "SELFTEST FAIL: a violation OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/abs" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a violation INSIDE the own-set did not block — own-scope disabled the rule"; fails=1; }
  lint_dir "$d/abs" "" ""                >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty collapsed into unset"; fails=1; }
  lint_dir "$d/abs" ""                   >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }
  # the window is what makes the multi-line shape decidable — prove it MOVES the verdict
  CC_AFUNIX_WINDOW=1 lint_dir "$d/absheredoc" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: with a 1-line window the heredoc shape should be INVISIBLE and GREEN — the window is inert"; fails=1; }
  # the real tree must be clean, and a bad dir is a NON-VERDICT (2), never a stale-allowlist claim
  lint_dir "$ROOT/tests" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: the real tree carries an unlisted absolute AF_UNIX bind"; fails=1 ;;
  esac
  lint_dir "$d/nope" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  if [ "$fails" -eq 0 ]; then
    echo "test-afunix-path-lint --selftest: 16/16 — RED on both real shapes + on chdir-with-an-absolute-arg + on a stuck ratchet entry; GREEN on chdir+basename, AF_INET, comment-only, no-socket and a grandfathered site; own-scope blocks INSIDE / advises OUTSIDE / passes set-empty / stays strict when absent; the window changes the verdict; real tree clean; LOUD on a bad dir."
    exit 0
  fi
  echo "test-afunix-path-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

if [ -n "${CC_AFUNIX_OWN+set}" ]; then
  lint_dir "${1:-$ROOT/tests}" "${CC_AFUNIX_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_AFUNIX_OWN"
else
  lint_dir "${1:-$ROOT/tests}" "${CC_AFUNIX_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
exit $?
