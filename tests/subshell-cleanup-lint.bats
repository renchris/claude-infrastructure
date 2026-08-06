#!/usr/bin/env bats
# subshell-cleanup-lint — the controls that make its CLEAN verdict mean something.
#
# The shape-level discrimination cases live in the script's own `--selftest` (12 of them, both
# directions) and are asserted here as one test rather than duplicated. What this suite adds is the
# thing a hand-written fixture cannot give: the REAL pre-fix artifact. The previous, one-level
# detector for this class passed hand-made cases, swept the repo clean, and then failed its positive
# control against the true artifact — so the artifact is the control that decides, and it is pinned
# here in BOTH directions (pre-fix must be flagged, fixed must not).
#
# Each control also carries a HARNESS SELF-CHECK: the extracted blob is asserted to actually contain
# the defect's own shape before anything the lint says about it is trusted. Without that, a control
# whose extraction silently failed (a bad sha, a moved path, an empty blob) passes vacuously and
# certifies nothing.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/subshell-cleanup-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  PREFIX_SHA=d5f97f9a          # names the pre-fix blob; the backlog item's ready-made control
}

# ── the real artifact, both directions ────────────────────────────────────────────────────────────

@test "C1 positive control: the pre-fix postland-verify blob IS flagged" {
  old="$BATS_TEST_TMPDIR/prefix.sh"
  (cd "$REPO" && git show "$PREFIX_SHA:scripts/postland-verify.sh") > "$old"
  # harness self-check — the blob must carry the defect, or this control proves nothing
  [ -s "$old" ]
  run /usr/bin/grep -c '="\$(do_bisect' "$old"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]                       # both call sites present in the pre-fix artifact

  run bash "$LINT" "$old"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WT_MINTED"* ]] || false
  [[ "$output" == *"do_bisect → prepare_worktree"* ]] || false # the TRANSITIVE chain, not just a hit
  [[ "$output" == *"teardown_worktrees reads WT_MINTED"* ]]
}

@test "C1b: BOTH substitution sites are reported, not just the first" {
  old="$BATS_TEST_TMPDIR/prefix.sh"
  (cd "$REPO" && git show "$PREFIX_SHA:scripts/postland-verify.sh") > "$old"
  run bash "$LINT" "$old"
  [ "$status" -eq 1 ]
  n="$(printf '%s\n' "$output" | /usr/bin/grep -c 'WT_MINTED — assigned inside')"
  [ "$n" -eq 2 ]
  # :1219 is verb_bisect — the site that actually leaked. :986 is red_actions, immune BY ACCIDENT
  # because the parent had already minted at the same path. A collector that keeps one site per
  # callee reports only :986 and hides the live defect; that regression is what this pins.
  [[ "$output" == *":1219:"* ]] || false
  [[ "$output" == *":986:"* ]]
}

@test "C1c: a ONE-LEVEL detector could not have found it — the assigner is never substituted" {
  # This is why transitivity is the whole point. `prepare_worktree` assigns WT_MINTED, and it is
  # NEVER the callee of a substitution anywhere in the pre-fix file — it sits one frame deeper,
  # inside do_bisect. So "is the ASSIGNING function itself substituted?" answers NO, which is
  # exactly the non-verdict the previous sweep returned.
  old="$BATS_TEST_TMPDIR/prefix.sh"
  (cd "$REPO" && git show "$PREFIX_SHA:scripts/postland-verify.sh") > "$old"
  run /usr/bin/grep -c '\$(prepare_worktree' "$old"
  [ "$status" -ne 0 ]                        # grep -c finds zero ⇒ non-zero exit
}

@test "C2 negative control: the FIXED postland-verify is NOT flagged" {
  # harness self-check — assert the fix is actually in the file under test, in both halves:
  # the substitution is gone AND the out-parameter is there. Either alone could be true for an
  # unrelated reason (a rename, a deletion), and then a clean verdict would mean nothing.
  run /usr/bin/grep -c '="\$(do_bisect' "$REPO/scripts/postland-verify.sh"
  [ "$status" -ne 0 ]
  run /usr/bin/grep -q 'BISECT_CULPRIT' "$REPO/scripts/postland-verify.sh"
  [ "$status" -eq 0 ]

  run bash "$LINT" "$REPO/scripts/postland-verify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "C2b: do_bisect still cannot be used through a substitution by a future caller" {
  # The fix removed the `printf` that made `$(do_bisect …)` appear to work. If someone restores it,
  # the next caller written that way re-creates the leak and the lint is the only thing standing in
  # the way — so pin the out-parameter contract itself, not just the current call sites.
  run /usr/bin/grep -A3 '^do_bisect()' "$REPO/scripts/postland-verify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BISECT_CULPRIT"* ]] || false
  [[ "$output" != *"prints the first-bad sha"* ]]
}

# ── the detector's own discrimination + contract ──────────────────────────────────────────────────

@test "--selftest passes: 12 shape cases, each proving a RED fires or a GREEN does not" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"--selftest PASS"* ]] || false
  [[ "$output" != *"FAIL"* ]]
}

@test "the whole tree is CLEAN — so a new instance landing goes red here" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "the clean line reports the PARSED population, never a bare 'clean'" {
  # A file with no trap cannot exhibit the class, so the expensive parse is skipped for it. That
  # filter is sound, but it must never be silent: a verdict that hid how much it actually parsed
  # would be a claim about a smaller repo than the one shipped.
  run bash "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+" file(s) parsed of "[0-9]+" scanned" ]]
}

@test "exit contract: 0 clean · 1 findings · 2 unusable" {
  run bash "$LINT" "$BATS_TEST_TMPDIR/does-not-exist.sh"
  [ "$status" -eq 2 ]
  run bash "$LINT" --shapes nonsense
  [ "$status" -eq 2 ]
  run bash "$LINT" --bogus-flag
  [ "$status" -eq 2 ]
}

@test "a SCANNER failure is exit 2 — UNSCANNED is never reported as clean" {
  # The failure mode this guards is the one that makes every static checker worthless: the scanner
  # dies, prints no findings, and "no findings" is byte-identical to "clean". Forcing awk to be
  # unusable must produce a LOUD 2, not a quiet 0. (Measured cause of this exact death once: a
  # UTF-8 locale widening this repo's own comment glyphs — hence LC_ALL=C in the scan.)
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\necho "boom" >&2\nexit 2\n' > "$BATS_TEST_TMPDIR/fakebin/awk"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/awk"
  printf '#!/bin/bash\nG=""\ntrap cleanup EXIT\n' > "$BATS_TEST_TMPDIR/probe.sh"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run bash "$LINT" "$BATS_TEST_TMPDIR/probe.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNSCANNED, not clean"* ]]
}

@test "no positional is required — the prelint slot passes none" {
  # postland-verify's prelint invokes each lint as `./scripts/<name>.sh` with NO argument, and its
  # own selftest asserts that. A lint that needed a scan root would exit 2 there, prelint_check would
  # read the 2 as PRELINT_UNPROVEN, and EVERY post-land run would CUT — no tree could be stamped
  # green again. So the no-argument invocation must resolve its own root and give a real verdict.
  run bash "$LINT"
  [ "$status" -ne 2 ]
}

@test "--list enumerates tracked shell files and exits 0" {
  run bash "$LINT" --list
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 100 ]
  [[ "$output" == *"scripts/postland-verify.sh"* ]]
}

@test "--json emits one parseable object per finding" {
  old="$BATS_TEST_TMPDIR/prefix.sh"
  (cd "$REPO" && git show "$PREFIX_SHA:scripts/postland-verify.sh") > "$old"
  run bash "$LINT" --json "$old"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "{"*"}" ]] || false
  [[ "${lines[0]}" == *'"var":"WT_MINTED"'* ]] || false
  [[ "${lines[0]}" == *'"shape":"cmdsub"'* ]] || false
  echo "$output" | while IFS= read -r l; do [ -n "$l" ] && printf '%s' "$l" | python3 -c 'import json,sys; json.loads(sys.stdin.read())'; done
}

@test "it is executable — the prelint slot gates on -x" {
  [ -x "$LINT" ]
}

# ── the wiring, and the argument contract that makes it safe ──────────────────────────────────────

@test "wired into postland-verify's blocking pre-corpus PRELINTS slot" {
  # A lint in its own suite is DETECTION, not a gate. The always-run prelint slot is the chokepoint:
  # it has no load-shed branch, unlike ship-land's smoke phase, so it cannot be skipped under load.
  run /usr/bin/grep -E 'PRELINTS=\(.*subshell-cleanup-lint\.sh' "$REPO/scripts/postland-verify.sh"
  [ "$status" -eq 0 ]
}

@test "fast enough for the band it runs in — a slow lint CUTS every post-land run" {
  # LINT_TO is 600s and the measured background-band tax reaches 84x, so the whole-tree sweep must
  # stay in single-digit foreground seconds. The first version took 16.4s (~1380s taxed) and would
  # have turned every run into a CUT while looking perfect by hand. 8s foreground is the ceiling
  # this asserts; the shipped sweep measures ~3.6s.
  start=$(date +%s)
  run bash "$LINT"
  end=$(date +%s)
  [ "$status" -eq 0 ]
  [ $((end - start)) -lt 8 ]
}

@test "--mutants: not blind on the REAL corpus, and enough files actually exercised" {
  # The complaint that produced this lint was that a CLEAN sweep is a non-verdict unless the detector
  # can be shown to find the instance already in hand. Fixtures cannot retire that — they test the
  # shapes the author thought of. This injects each trap-handler file's OWN trap-consulted global into
  # a function that file ALREADY substitutes, and requires a catch. The floor on testable files is
  # part of the assertion: a guard that quietly drifts to proving nothing is the exact failure mode
  # this lint exists to prevent.
  run bash "$LINT" --mutants
  [ "$status" -eq 0 ]
  [[ "$output" != *"BLIND"* ]] || false
  [[ "$output" != *"LIVE FINDING"* ]] || false
  [[ "$output" == *"blind=0"* ]]
}
