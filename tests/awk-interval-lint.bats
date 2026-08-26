#!/usr/bin/env bats
# awk-interval-lint — the RATCHET that stops an INTERVAL EXPRESSION ({n} / {n,} / {n,m}) reaching an
# awk program, where its meaning depends on which awk runs it and every wrong answer is silent.
#
# THE DIVISION OF LABOUR, and it is deliberate. `--selftest` owns the MECHANISM: twelve synthetic
# fixtures, every discrimination in both directions, no history and no second awk required. This
# suite owns what a synthetic fixture structurally cannot give — a verdict on the REAL corpus, on the
# REAL pre-fix artifacts replayed from a pinned sha, and (where the host has two awks) the
# BEHAVIOURAL difference the lint exists to prevent. Asking either to do the other's job yields a
# vacuous pass (memory: the union-arm split in scripts/unattended-path-lint.sh, same argument).
#
# WHY THE RULE NEEDED A GATE AT ALL. It already existed, in prose, in exactly one place —
# scripts/typed-send-lint.sh:164 — and bound exactly that one file. Censused 2026-08-26: eight
# interval sites across six others, two of them answering wrongly under mawk 1.3.4, which accepts
# `{m,n}` and then matches EXACTLY m whenever m >= 2. (memory: enforcement-must-live-at-the-chokepoint)
#
# SELF-REFERENCE HAZARD, and how it is handled. The lint's scan population includes THIS FILE. Every
# interval expression written below therefore lives in a `grep -E` pattern or a shell string — never
# inside an awk program — which is exactly the invocation-vs-mention line the lint draws. Verified
# both directions: move one into an awk body here and the corpus case goes red.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/awk-interval-lint.sh"
  [ -x "$LINT" ] || false
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: obey the sibling suites' rule
  export CC_FIRE_CAPACITY_GATE=off
  D="$BATS_TEST_TMPDIR"
  PIN="51bf8570"          # the last commit before this repair — a LITERAL sha, never a moving ref
}

@test "--selftest passes: the mechanism discriminates in both directions" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || false
  # A floor on the case count, so a gutted --selftest cannot pass this by asserting nothing.
  n="$(printf '%s' "$output" | sed -n 's|.*--selftest: \([0-9]*\)/[0-9]*.*|\1|p')"
  [ -n "$n" ] || false
  [ "$n" -ge 20 ] || false
}

@test "the REAL tree is clean — a lint that ships standing-red is rot" {
  run bash "$LINT" "$REPO"
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q 'clean —' || false
  # …over a population that is actually the tree, not three files a mis-scoped find happened to see.
  n="$(printf '%s' "$output" | sed -n 's|.*clean — \([0-9]*\) awk-bearing.*|\1|p')"
  [ -n "$n" ] || false
  [ "$n" -ge 100 ] || false
}

@test "POSITIVE CONTROL on the REAL artifacts: the five repaired files, replayed pre-fix, all flag" {
  # An empty result from a matcher is not evidence of absence until the matcher has been shown able
  # to return a hit — and a synthetic fixture only shows it can hit a fixture. These are the real
  # files as they stood at the pin, plus two that must NOT flag:
  #   typed-send-lint.sh — the file that STATES the rule and obeys it ⇒ MUST NOT flag
  #   self-path-lint.sh  — carries `${BASH_SOURCE[0]}` in an awk COMMENT ⇒ MUST NOT flag
  # Seven of seven is exactly as wrong as zero of seven.
  [ -n "$(command -v git)" ] || skip "git unavailable"
  local pre="$D/pre/scripts"; mkdir -p "$pre"
  local f
  for f in moving-ref-control-lint plan-phase-scan assignee-pane-residency teammate-reap-alarm \
           occupancy-probe typed-send-lint self-path-lint; do
    git -C "$REPO" show "$PIN:scripts/$f.sh" > "$pre/$f.sh" 2>/dev/null \
      || skip "pre-repair commit $PIN unavailable (shallow clone?)"
  done
  # THE MARKER: the replayed corpus must actually BE pre-repair, or this case passes for the wrong
  # reason. The pin carries the offending shape; the repaired file carries the length() bound.
  grep -qE '\[0-9a-f\]\{7,40\}' "$pre/moving-ref-control-lint.sh" || false
  grep -q 'length(ref) >= 7' "$REPO/scripts/moving-ref-control-lint.sh" || false
  ! grep -q 'length(ref) >= 7' "$pre/moving-ref-control-lint.sh" || false

  run bash "$LINT" "$pre"
  [ "$status" -eq 1 ] || false
  printf '%s' "$output" | grep -q 'AWK-INTERVAL moving-ref-control-lint.sh' || false
  printf '%s' "$output" | grep -q 'AWK-INTERVAL plan-phase-scan.sh' || false
  printf '%s' "$output" | grep -q 'AWK-INTERVAL assignee-pane-residency.sh' || false
  printf '%s' "$output" | grep -q 'AWK-INTERVAL teammate-reap-alarm.sh' || false
  printf '%s' "$output" | grep -q 'AWK-INTERVAL occupancy-probe.sh' || false
  ! printf '%s' "$output" | grep -q 'typed-send-lint' || false
  ! printf '%s' "$output" | grep -q 'self-path-lint' || false
  printf '%s' "$output" | grep -q '⛔ 5 file(s)' || false
}

@test "BEHAVIOURAL: plan-phase-scan reports a WHOLE sha, not its first seven characters" {
  # The lint is a text rule; this is the answer the text rule protects. Pre-fix, the sha scan read
  # `/[0-9a-f]{7,40}/` and mawk took exactly SEVEN characters of every run, three ways at once:
  #   ce7651b02a17     -> ce7651b            truncated
  #   a1b2c3d4e5f6a7b8 -> a1b2c3d, 4e5f6a7   two shas nobody wrote
  #   1234567abcdef    -> (none)             the head is purely numeric and the tail too short, so
  #                                          the hash vanished AND the section fell back to PENDING
  cat > "$D/p.md" <<'MD'
---
status: open
---

# Fixture

## §1 landed (ce7651b02a17)

## §2 landed (a1b2c3d4e5f6a7b8)

## §3 landed (1234567abcdef)
MD
  run bash "$REPO/scripts/plan-phase-scan.sh" "$D/p.md"
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q '"ce7651b02a17"' || false
  printf '%s' "$output" | grep -q '"a1b2c3d4e5f6a7b8"' || false
  printf '%s' "$output" | grep -q '"1234567abcdef"' || false
  # the fabricated pair and the truncation must be ABSENT, not merely outnumbered
  ! printf '%s' "$output" | grep -q '"ce7651b"' || false
  ! printf '%s' "$output" | grep -q '"a1b2c3d"' || false
  # and §3 must read DONE — the hash is what flips it, so losing the hash lost the status
  printf '%s' "$output" | grep -q '"status": "DONE"' || false
  [ "$(printf '%s' "$output" | grep -c '"status": "DONE"')" -eq 3 ]
}

@test "TWO AWKS AGREE: the same file, the same answer, on both interval implementations" {
  # The strongest arm this suite has, and it can only run where the host carries two awks. It is the
  # measurement the whole change rests on: pre-fix these two disagreed on the real plan corpus.
  local a b
  a="$(command -v mawk || true)"; b="$(command -v gawk || true)"
  [ -n "$a" ] && [ -n "$b" ] || skip "needs two awk implementations (mawk + gawk) on PATH"
  mkdir -p "$D/m" "$D/g"; ln -sf "$a" "$D/m/awk"; ln -sf "$b" "$D/g/awk"
  # First prove the two awks really DO differ on an interval — otherwise this case is vacuous.
  local am bm
  am="$(printf 'aaaaaaaaa\n' | "$a" '{ print ($0 ~ /^a{2,9}$/) ? "M" : "no" }')"
  bm="$(printf 'aaaaaaaaa\n' | "$b" '{ print ($0 ~ /^a{2,9}$/) ? "M" : "no" }')"
  [ "$am" != "$bm" ] || skip "this host's two awks agree on {2,9} — nothing to discriminate"

  cat > "$D/agree.md" <<'MD'
---
status: open
---

# Fixture

## §1 landed (ce7651b02a17)
MD
  PATH="$D/m:$PATH" bash "$REPO/scripts/plan-phase-scan.sh" "$D/agree.md" > "$D/out.m"
  PATH="$D/g:$PATH" bash "$REPO/scripts/plan-phase-scan.sh" "$D/agree.md" > "$D/out.g"
  diff "$D/out.m" "$D/out.g" || { echo "the two awks disagree on the fixed scanner"; false; }
  grep -q '"ce7651b02a17"' "$D/out.m" || false

  # …and the same for the pinned-ref decision the land gate makes.
  PATH="$D/m:$PATH" bash "$REPO/scripts/moving-ref-control-lint.sh" "$REPO/tests" > "$D/mr.m" 2>&1
  PATH="$D/g:$PATH" bash "$REPO/scripts/moving-ref-control-lint.sh" "$REPO/tests" > "$D/mr.g" 2>&1
  diff "$D/mr.m" "$D/mr.g" || { echo "moving-ref-control-lint answers differently per awk"; false; }
  grep -q 'clean —' "$D/mr.m" || false
}

@test "SELF-HARNESS: this suite is in the scanned corpus and is NOT flagged" {
  # Every interval expression written above is in a grep pattern or a shell string, never in an awk
  # program. This asserts the specific thing that would break: the file is in the population, clean.
  [ -f "$REPO/tests/$(basename "$BATS_TEST_FILENAME")" ] || false
  run bash "$LINT" "$REPO"
  [ "$status" -eq 0 ] || false
  ! printf '%s' "$output" | grep -q "$(basename "$BATS_TEST_FILENAME")" || false
}

@test "the ONE structural exclusion is exactly one path, and nothing else is exempt" {
  # The lint skips its own file, because --selftest keeps its RED fixtures there as heredocs. That
  # exclusion is how a ratchet rots into an exemption list, so it is pinned: one basename, and the
  # embedded allowlist is empty.
  [ "$(grep -c "grep -v '/awk-interval-lint\\\\.sh\$'" "$LINT")" -eq 1 ]
  grep -q '^EMBEDDED_ALLOWLIST=""$' "$LINT" || false
}

@test "the land gate calls it, own-scoped — enforcement at the chokepoint, not in this suite" {
  # Enforced only here it is post-hoc DETECTION: gate-select maps this suite from exactly one edge
  # (the lint), so WRITING a new interval never selects it. The gate arm is the enforcing surface.
  # (memory: enforcement-must-live-at-the-chokepoint, conclusion-must-reach-the-enforcing-store)
  grep -q 'AWKINT_LINT=' "$REPO/scripts/ship-land.sh" || false
  grep -q 'own_run AWKINT CC_AWKINT_OWN' "$REPO/scripts/ship-land.sh" || false
  # own-scope is what keeps a whole-tree ratchet from stopping every concurrent lander.
  grep -q 'SHIP_LAND_AWKINT_OWN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  # and the NON-VERDICT arm: exit 2 must be GATE_KILLED (retryable), never gate_red (author-fixable)
  grep -q 'awk-interval-lint could not RUN (exit 2)' "$REPO/scripts/ship-land.sh" || false
}
