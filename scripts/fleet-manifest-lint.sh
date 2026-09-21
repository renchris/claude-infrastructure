#!/bin/bash
# fleet-manifest-lint — the CHOKEPOINT that stops a launchd plist from landing UNDECLARED.
#
# THE RULE: every committed launchd/com.claude.*.plist and launchd/com.chrisren.*.plist has a row in
# launchd/fleet.manifest, and every row in that manifest uses legal field values. cc-fleet's unit of
# coverage is A LINE IN THAT MANIFEST (DAEMON_FLEET_V2 §4.1), so an undeclared label is not merely
# unalarmed — it is unreachable by every leg of the tool.
#
# THE INCIDENT, AND IT IS THE SIXTH OF ITS SHAPE (backlog 62f54195c398, landed 307f9749d). bd016b0a0
# added launchd/com.claude.browse-mirror.plist with no manifest row. The three-way coverage loop in
# tests/cc-fleet.bats caught it correctly — and caught it POST-land, where it sat RED on trunk for 92
# commits, tripping every lander after it, until postland-verify bisected it and dispatched a worker.
# Its five predecessors are named in fleet.manifest's own comment blocks: capacity-alarm,
# scratchpad-reaper, devserver-gc, browser-spin-guard (438883e365ec) and permission-harvest
# (c893ce32210b, 63734f039).
#
# WHY THE SUITE WAS NOT ENOUGH, which is the whole reason this file exists. tests/cc-fleet.bats is a
# `--direct` suite of any diff touching launchd/, so in principle the land gate already ran it. In
# practice the land's smoke is LOAD-SHED on a busy box (R7) — and the box was at load 244 at the time
# of 438883e365ec, from the very wedge that plist existed to catch. The land most likely to add a
# plist is the one least able to afford a suite. A lint is the answer the repo's own plan already
# reached: DAEMON_FLEET_V2 §4.4 says, in terms, "the manifest lint runs in `run_gate` so an
# undeclared or unmirrored plist cannot land", and fleet.manifest's header has asserted for months
# that such a lint exists. It did not (memory: spec-named-mechanism-may-be-prose-only). This is it.
# It is a whole-tree grep over ~20 paths with no file reads beyond one manifest — cheap enough that
# shedding it would never be the saving, which is exactly the property the suite lacked.
#
# WHY TREE-ONLY, AND WHAT IS DELIBERATELY *NOT* HERE. §4.4 also names LIVE-ONLY / CONTENT-DRIFT
# parity against ~/Library/LaunchAgents. That half MUST NOT be in a land gate: it reads HOST state,
# so one machine's launchd would decide whether another author's land passes, and a gate whose
# verdict depends on the lander's box is not a statement about the tree. It stays where it belongs,
# as a board read — `bin/cc-fleet --plist-parity`. This lint judges exactly the half that is a pure
# function of the commit.
#
# WHY THE POPULATION IS THE FILESYSTEM GLOB, not `git ls-files`. tests/cc-fleet.bats walks
# "$ROOT"/launchd/com.{claude,chrisren}.*.plist, and two enforcers over ONE population must share a
# state model or they disagree in the gap (memory: sibling-auditors-must-share-the-state-model). Using
# the identical glob makes lint and suite agree BY CONSTRUCTION. It also sidesteps a real trap: the
# caller may have exported GIT_INDEX_FILE to a throwaway index with `git add -N` over untracked files
# (ship-land.sh does exactly this in --precheck --working), so a `git ls-files` population would
# silently change shape with the caller's plumbing. Nothing here spawns git at all.
#
# WHY IT CANNOT BECOME A STANDING RED. The repo's baseline is ZERO offenders at the commit that adds
# this lint (307f9749d closed the last one). Both cures are one line in the author's own commit: add
# the manifest row, or do not commit the plist. A refusal that outlives its author's commit would
# mean the manifest rotted rather than the tree failing — delete the arm via
# SHIP_LAND_FLEETMAN_LINT=/nonexistent, which is attested in land.log, and repair the manifest as its
# own commit rather than accumulating silent lands behind a standing refusal.
#
# THE COUNT TRIPWIRE IS NOT HERE, DELIBERATELY. tests/cc-fleet.bats pins the expected number of rows
# (`[ "$n" != <N> ]` — the literal moves with each row, so it is not restated here) as a HUMAN-moved
# tripwire whose comment block records why each row was added.
# That is a judgment ratchet and belongs in a suite a person reads. This lint is structural only, so
# a legitimate row addition does not have to argue with two enforcers at once.
#
# Usage:  fleet-manifest-lint.sh [<repo-root>]        (default: the git toplevel of $PWD, else $PWD)
#         fleet-manifest-lint.sh --selftest
# Env:    CC_FLEETMAN_MANIFEST  manifest path relative to root (default: launchd/fleet.manifest)
#         CC_FLEETMAN_DIR       plist directory relative to root (default: launchd)
#
# Exit: 0 = clean — every committed plist is declared and every row is well-formed
#       1 = RED   — an undeclared plist, or a row with an illegal field value
#       2 = CANNOT DETERMINE (unreadable root / manifest / plist dir) — LOUD, never a silent 0,
#           because an indeterminate check that passes is indistinguishable from a working one
#           (memory: null-result-must-not-use-the-error-channel).
set -uo pipefail

DEFAULT_MANIFEST="launchd/fleet.manifest"
DEFAULT_DIR="launchd"

lint_repo() {
  local root="$1" man dir rc=0 n_plist=0 n_row=0
  # `${VAR-default}`, never `${VAR:-default}`: `:-` collapses SET-BUT-EMPTY into the default, so an
  # operator who blanked the variable would get a full-strength run and never learn it was ignored
  # (memory: harness-default-collapses-the-states-under-test). An empty value is honored verbatim
  # below and reaches the CANNOT-DETERMINE arm, which is the honest answer for "judge nothing".
  man="${CC_FLEETMAN_MANIFEST-$DEFAULT_MANIFEST}"
  dir="${CC_FLEETMAN_DIR-$DEFAULT_DIR}"

  [ -n "$root" ] && [ -d "$root" ] || { echo "fleet-manifest-lint: CANNOT DETERMINE — no readable repo root '$root'"; return 2; }
  [ -n "$man" ] || { echo "fleet-manifest-lint: CANNOT DETERMINE — the manifest path is empty, so this lint judges nothing"; return 2; }
  [ -n "$dir" ] || { echo "fleet-manifest-lint: CANNOT DETERMINE — the plist directory is empty, so this lint judges nothing"; return 2; }
  [ -r "$root/$man" ] || { echo "fleet-manifest-lint: CANNOT DETERMINE — manifest '$man' is not readable under '$root'"; return 2; }
  [ -d "$root/$dir" ] || { echo "fleet-manifest-lint: CANNOT DETERMINE — plist directory '$dir' does not exist under '$root'"; return 2; }

  local M="$root/$man"

  # ── leg 1: every committed plist is DECLARED ────────────────────────────────────────────────────
  # The same two families tests/cc-fleet.bats walks. A label outside them (homebrew.mxcl.postgresql@14)
  # may hold a row with no plist in this repo at all — that direction adds no obligation and is not
  # checked, exactly as the suite does not check it.
  local f b lbl
  for f in "$root/$dir"/com.claude.*.plist "$root/$dir"/com.chrisren.*.plist; do
    [ -f "$f" ] || continue            # an unmatched glob expands to itself; -f rejects it
    n_plist=$((n_plist + 1))
    b="${f##*/}"; lbl="${b%.plist}"
    # Anchored at BOTH ends of the label: `^` stops a comment that merely MENTIONS the label from
    # declaring it, and the ` *|` column tail stops a LONGER row (com.claude.foo-bar-baz) from
    # discharging a SHORTER label (com.claude.foo-bar). Both directions are mutation-proved in
    # --selftest and in tests/fleet-manifest-lint.bats; the first versions of both tests were written
    # backwards and passed against a mutant, which is how the pair got pinned.
    # RESIDUAL, stated rather than hidden: `$lbl` is interpolated as a REGEX, so its dots match any
    # character — `com.claude.x` would also match a row `comXclaudeXx`. No such label exists or
    # plausibly could, and tests/cc-fleet.bats's coverage loop carries the identical pattern, so this
    # stays byte-for-byte the same predicate as the suite it backs (memory:
    # sibling-auditors-must-share-the-state-model) rather than diverging for a hazard neither has.
    if ! grep -q "^$lbl *|" "$M"; then
      if [ "$rc" -eq 0 ]; then
        echo "  RED  fleet-manifest  a committed launchd plist is UNDECLARED in $man:"
      fi
      echo "         $dir/$b  ->  no row for '$lbl'"
      rc=1
    fi
  done

  # ── leg 2: every row uses LEGAL field values ────────────────────────────────────────────────────
  # cc-fleet reads this file positionally and a malformed row silently shifts a column, so the same
  # three constraints tests/cc-fleet.bats asserts are enforced here at the act rather than after it.
  local label expect interval activate rest _evidence _owner badrow=0
  while IFS='|' read -r label expect interval _evidence _owner activate rest; do
    label="$(printf '%s' "$label" | tr -d '[:space:]')"
    # A comment or blank line is not a row. `case` is used OUTSIDE any command substitution on
    # purpose: bash 3.2 (the /bin/bash every launchd job here gets) dies on `case` inside `$( )`,
    # and scripts/bash32-parse-lint.sh enforces that.
    case "$label" in ''|'#'*) continue ;; esac
    n_row=$((n_row + 1))
    expect="$(printf '%s' "$expect" | tr -d '[:space:]')"
    interval="$(printf '%s' "$interval" | tr -d '[:space:]')"
    activate="$(printf '%s' "$activate" | tr -d '[:space:]')"
    case "$expect" in
      run|staged|retired) ;;
      *) echo "         $label  ->  illegal expect '$expect' (want run|staged|retired)"; badrow=1 ;;
    esac
    case "$interval" in
      ''|*[!0-9]*) echo "         $label  ->  illegal interval_s '$interval' (want digits; 0 means calendar-scheduled)"; badrow=1 ;;
    esac
    if [ -z "$activate" ]; then
      echo "         $label  ->  no activate script (it is the row's paste-ready recover_cmd)"; badrow=1
    else
      case "$activate" in
        *.sh) ;;
        *) echo "         $label  ->  activate '$activate' is not a .sh"; badrow=1 ;;
      esac
    fi
  done < "$M"
  # `_evidence` and `_owner` are read to keep the column split honest but are not constrained here:
  # both are free-form by design (evidence may be auto, a path, or '-'; owner_row is routing metadata
  # that never changes a verdict). Naming them is what stops `activate` reading a column early — and
  # the `_` prefix says "bound deliberately, never referenced", which is also what settles SC2034.
  if [ "$badrow" -ne 0 ]; then
    echo "  RED  fleet-manifest  $man has row(s) whose fields cc-fleet cannot read (listed above)"
    rc=1
  fi

  if [ "$rc" -ne 0 ]; then
    echo "         cc-fleet's unit of coverage is a LINE IN THIS MANIFEST (DAEMON_FLEET_V2 §4.1), so"
    echo "         an undeclared label is not merely unalarmed — every leg of the tool is blind to it."
    echo "         Cure, in this same commit: add the row to $man. Fields and their legal values are"
    echo "         documented in that file's own header; the rows already there are the worked examples."
    return 1
  fi

  # The denominator is printed with the verdict: a clean result whose population nobody stated is not
  # auditable, and a glob that silently matched nothing would otherwise read exactly like a pass
  # (memory: the-prelint-denominator / alarm-polarity-and-attention-budget).
  echo "  OK   fleet-manifest  $n_plist committed plist(s) all declared across $n_row manifest row(s)"
  return 0
}

# ── --selftest: prove BOTH directions fire. A test that can only pass proves nothing. ──────────────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)" || { echo "fleet-manifest-lint --selftest: CANNOT RUN — mktemp failed"; exit 2; }
  trap 'rm -rf "$d"' EXIT
  fails=0

  mk() {  # $1=case dir — a MINIMAL fixture: one declared plist, one well-formed row
    mkdir -p "$d/$1/launchd"
    : > "$d/$1/launchd/com.claude.alpha.plist"
    printf '# a comment line, and a blank one below\n\n' > "$d/$1/launchd/fleet.manifest"
    printf 'com.claude.alpha | run | 600 | auto | 11 | 18-fleet-activate.sh\n' >> "$d/$1/launchd/fleet.manifest"
  }
  chk() {  # $1=case name  $2=expected rc  $3=case dir
    local got
    ( lint_repo "$d/$3" ) >/dev/null 2>&1; got=$?
    if [ "$got" -ne "$2" ]; then
      echo "fleet-manifest-lint --selftest: FAIL $1 — expected rc $2, got $got"
      fails=$((fails + 1))
    fi
  }

  # GREEN control. Without this, every RED case below could be passing for the wrong reason (a lint
  # that returns 1 unconditionally satisfies all of them).
  mk clean;                                                             chk "clean tree is GREEN" 0 clean

  # RED 1 — THE INCIDENT ITSELF: a committed plist with no row. This is the mutant that reproduces
  # bd016b0a0 exactly, and it is the case the whole file exists for.
  mk undeclared; : > "$d/undeclared/launchd/com.claude.beta.plist";     chk "undeclared plist is RED" 1 undeclared
  # ...and the com.chrisren.* family is walked too, not just com.claude.*.
  mk undeclared2; : > "$d/undeclared2/launchd/com.chrisren.beta.plist"; chk "undeclared com.chrisren plist is RED" 1 undeclared2

  # RED 2 — THE ANCHOR, in the two directions that actually kill a mutant. Both of these were first
  # written backwards here and in tests/fleet-manifest-lint.bats; a mutation run that dropped the
  # `^...  *|` anchor left the old fixture RED either way, so it proved nothing about the anchor.
  #   2a the ` *|` column tail: `^com.claude.alpha` is a PREFIX of the row `com.claude.alpha-extra |`,
  #      so without it a LONGER row discharges a SHORTER label and a real gap passes.
  mkdir -p "$d/longrow/launchd"; : > "$d/longrow/launchd/com.claude.alpha.plist"
  printf 'com.claude.alpha-extra | run | 600 | auto | 11 | x.sh\n' > "$d/longrow/launchd/fleet.manifest"
  chk "a LONGER row does not discharge a shorter label" 1 longrow
  #   2b the `^`: without it the label matches anywhere on a line, so a COMMENT naming the label
  #      declares it — the detector matching its own documentation.
  mkdir -p "$d/mention/launchd"; : > "$d/mention/launchd/com.claude.alpha.plist"
  printf '# see com.claude.alpha | run | 600 | auto | 11 | x.sh\n' > "$d/mention/launchd/fleet.manifest"
  chk "a COMMENT mentioning the label does not declare it" 1 mention

  # RED 3 — illegal field values, one mutant per constraint so a green suite credits each of them
  # (memory: per-site-mutation-attributes-coverage).
  mk badexpect; printf 'com.claude.g | running | 60 | auto | 1 | x.sh\n' >> "$d/badexpect/launchd/fleet.manifest"
  chk "illegal expect is RED" 1 badexpect
  mk badint;    printf 'com.claude.g | run | 10m | auto | 1 | x.sh\n'   >> "$d/badint/launchd/fleet.manifest"
  chk "non-numeric interval is RED" 1 badint
  mk noact;     printf 'com.claude.g | run | 60 | auto | 1 |\n'         >> "$d/noact/launchd/fleet.manifest"
  chk "missing activate is RED" 1 noact
  mk badact;    printf 'com.claude.g | run | 60 | auto | 1 | activate\n' >> "$d/badact/launchd/fleet.manifest"
  chk "activate that is not a .sh is RED" 1 badact

  # A comment whose text merely LOOKS like a row must not be counted or judged — the detector must
  # not match its own documentation (memory: the manifest's own header shows example rows).
  mk commented; printf '# com.claude.ghost | bogus | later | auto | 1 | nope\n' >> "$d/commented/launchd/fleet.manifest"
  chk "a commented-out row is not judged" 0 commented

  # rc 2 — CANNOT DETERMINE must be reachable in every direction, and must never be a silent 0.
  chk "absent root is rc 2" 2 no-such-dir
  mkdir -p "$d/nomanifest/launchd";                                     chk "absent manifest is rc 2" 2 nomanifest
  mkdir -p "$d/nodir"; : > "$d/nodir/fleet.manifest"
  ( CC_FLEETMAN_MANIFEST=fleet.manifest lint_repo "$d/nodir" ) >/dev/null 2>&1
  [ "$?" -eq 2 ] || { echo "fleet-manifest-lint --selftest: FAIL absent plist dir — expected rc 2"; fails=$((fails + 1)); }
  mk emptyvar
  ( CC_FLEETMAN_MANIFEST='' lint_repo "$d/emptyvar" ) >/dev/null 2>&1
  [ "$?" -eq 2 ] || { echo "fleet-manifest-lint --selftest: FAIL set-but-empty manifest var — expected rc 2, not the default"; fails=$((fails + 1)); }

  if [ "$fails" -ne 0 ]; then
    echo "fleet-manifest-lint --selftest: $fails case(s) FAILED — the lint does not discriminate"
    exit 1
  fi
  echo "fleet-manifest-lint --selftest: OK — 15 cases, both directions proven"
  exit 0
fi

root="${1:-}"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  [ -n "$root" ] || root="$PWD"
fi
lint_repo "$root"
