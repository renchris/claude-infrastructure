#!/usr/bin/env bats
# ONE TAP result-line grammar, across every reader that decides CUT vs RED.
#
# TAP13 (and bats) spell a result line `ok <N> <desc>` / `not ok <N> <desc>`. The <N> is not
# decoration: it is the ONLY thing separating a RESULT from arbitrary text that merely opens with
# those bytes — and arbitrary text is ROUTINE in these streams, because every one of them captures
# its suite as `2>&1`. An unprefixed stderr write splices straight in (hooks/session-register.sh:347
# documents one such injector by name) and a run killed mid-write truncates a line wherever the
# buffer ended.
#
# WHY THIS FILE EXISTS RATHER THAN A SHARED LIBRARY. The grammar was fixed once already, inside
# scripts/postland-verify.sh (C30), where three readers had three spellings and the loosest decided
# whether a tree was RED. That fix was correct and local — and the same loose spelling went on
# living in three OTHER files for the next ten days, because nothing connected them. A shared
# `scripts/lib/tap-grammar.sh` is the obvious answer and is the WRONG one here: ~/.claude is reached
# by PER-FILE symlinks, so a newly added lib file is ABSENT from the live layer until deploy-live
# converges, and the `[ -f lib ] && . lib` guard every consumer would need turns that absence into a
# SILENT fall-back to the loose grammar — on exactly the boxes that run a land. So the literal is
# repeated, deliberately, and THIS FILE is the thing that keeps the repetitions equal.
#
# The four readers and what each one's loose spelling cost:
#   scripts/ship-land.sh        smoke gate    → exit 6, "a VERDICT about your diff: fix it"
#   scripts/deploy-live.sh      host checks   → a page + a backlog item a worker is dispatched to chase
#   scripts/nightly-regression.sh page detail → the 04:00 page spends its budget quoting the splice,
#                                               and the `|| tail -15` fallback never fires
#   scripts/postland-verify.sh  TAP_NOTOK_RE  → already fixed (C30); pinned here so it cannot regress

setup() {
  # Hermetic: nothing here reads ~/, but an unfixtured $HOME is one careless edit away from doing
  # so — and the subjects of this suite are the very scripts that decide whether a land proceeds.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # The REPO, by contrast, is deliberately the real checkout: the invariant is about the four
  # tracked files as they will be LANDED, so a fixture copy of them would assert nothing.
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  # Named explicitly, never globbed: a glob would sweep in THIS file, whose own patterns are the
  # thing being searched for, and the guard would then convict its own harness.
  SUTS="scripts/ship-land.sh scripts/deploy-live.sh scripts/nightly-regression.sh scripts/postland-verify.sh"
  STRICT='^not ok [0-9]+'
  LOOSE='^not ok'
}

@test "every cut-vs-red reader carries the STRICT grammar" {
  for f in $SUTS; do
    [ -f "$REPO/$f" ]
    grep -qF -- "$STRICT" "$REPO/$f"
  done
}

@test "no reader still spells the grammar LOOSELY as a pattern" {
  # The needle is the quoted pattern literal — `'^not ok'`, closing quote immediately after `ok` —
  # not the bare substring. Prose that discusses the old spelling, and ship-land's `sig=` signature
  # line (deliberately loose: a flake-ledger string, never a discriminator) both mention `^not ok`
  # and neither is a discriminator, so a substring ban would fail in both directions at once.
  for f in $SUTS; do
    run grep -cF -- "'$LOOSE'" "$REPO/$f"
    [ "$output" = "0" ]
  done
}

@test "EVERY quoted not-ok pattern BEGINS with the one grammar" {
  # "All four are strict" is not the invariant; ONE grammar is. Two readers could both require a
  # <N> and still disagree — `[0-9]+` vs `[0-9]*`, a dropped anchor, a tab class — and that
  # disagreement is invisible to the two tests above.
  #
  # The rule is PREFIX, not equality, and the difference is load-bearing: ship-land.sh legitimately
  # carries a second, LONGER pattern — leg A's `'^not ok [0-9]+ bats-gather-tests[[:space:]]*$'`,
  # which recognises bats' own collector artifact. That is a SPECIALISATION of the grammar, not a
  # rival spelling, and an equality rule would reject it — i.e. would demand that a correct file be
  # broken. Prefix admits every specialisation and rejects every loosening, which is exactly the
  # asymmetry we want: you may narrow what counts as a failure, never widen it.
  for f in $SUTS; do
    n=0
    while IFS= read -r lit; do
      [ -n "$lit" ] || continue
      n=$((n + 1))
      case "$lit" in
        "'$STRICT"*) ;;
        *) printf 'DIVERGENT grammar in %s: %s\n' "$f" "$lit" >&2; false ;;
      esac
    done < <(grep -oE -- "'\^not ok [^']*'" "$REPO/$f" | sort -u)
    [ "$n" -ge 1 ]        # the file DOES carry one, so an empty loop cannot pass vacuously
  done
}

@test "MEASURED: the four shapes count 0 strict / 1 loose — on BOTH greps that run here" {
  # The reason, kept falsifiable rather than merely asserted. /usr/bin/grep is what launchd's PATH
  # gives deploy-live; the PATH grep is ugrep 7.5.0 on the operator's interactive shell, and the two
  # must not disagree. `-a` is part of the contract: without it ugrep reads a NUL-carrying capture
  # as EMPTY, which resurrects the same divergence from the other side.
  for shape in 'not ok' 'not ok3 squashed' 'not okay then' 'not okcorpus: 3 suites'; do
    printf '%s\n' "$shape" > "$BATS_TEST_TMPDIR/shape"
    for g in /usr/bin/grep grep; do
      [ "$("$g" -acE -- "$STRICT" "$BATS_TEST_TMPDIR/shape")" -eq 0 ]
      [ "$("$g" -ac  -- "$LOOSE"  "$BATS_TEST_TMPDIR/shape")" -eq 1 ]
    done
  done
  # …and the positive control, or the above passes for a grammar that sees nothing at all.
  printf 'ok 1 fine\nnot ok 2 a genuine failure\n' > "$BATS_TEST_TMPDIR/real"
  for g in /usr/bin/grep grep; do
    [ "$("$g" -acE -- "$STRICT" "$BATS_TEST_TMPDIR/real")" -eq 1 ]
  done
}

@test "CONTROL: this ratchet FAILS on a file that reintroduces the loose spelling" {
  # Without this, every assertion above passes vacuously the day someone rewrites the needle wrong.
  poisoned="$BATS_TEST_TMPDIR/poisoned.sh"
  printf 'n="$(grep -c %s "$log")"\n' "'^not ok'" > "$poisoned"
  run grep -cF -- "'$LOOSE'" "$poisoned"
  [ "$output" = "1" ]                       # the needle DOES find a reintroduction…
  run grep -qF -- "$STRICT" "$poisoned"
  [ "$status" -ne 0 ]                       # …and the strict check does NOT pass on it
}
