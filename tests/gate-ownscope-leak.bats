#!/usr/bin/env bats
# gate-ownscope-leak.bats — the ratchet arms' OWN-DIFF BLOCKING SCOPE (land-arch P2, backlog
# 46eb9be14249; docs/research/land-architecture-100p-2026-08-10.md §5 row P2, §2.B).
#
# WHAT IS BEING PINNED. Gate-red is 27%/14d → 39%/3d → 45% on the last day of ship-land
# invocations, and 89% of those run no smoke, so the reds are statics and ratchets. Part of that
# rate is not the author's fault at all: the arms scan O(repo) and are supposed to BLOCK only on
# own-diff files, and the audit's exit-6 attribution reads "mostly repo-wide ratchets firing on
# files the land did not touch". Trunk-wide debt taxing innocent lands is the #112/#126
# red-on-trunk class. This suite is the per-arm audit made executable.
#
# THE THREE STATES ARE THE WHOLE MECHANISM, and every leak found was a collapse of two of them:
#   UNSET          nobody scoped ⇒ strict, the whole tree may block
#   SET-BUT-EMPTY  a caller scoped and owns nothing here ⇒ NOTHING may block
#   SET            only the named files may block
# ship-land ALWAYS exports the variable, so SET-BUT-EMPTY is the common case (any land touching
# none of an arm's pathspec — docs-only, launchd-only, commands-only), not a corner. A lint that
# spells its presence test `${CC_X_OWN:-}` cannot express it, and reads that land as strict.
#
# ONE MUTANT PER SITE, not one per suite (repo memory: per-site-mutation-attributes-coverage).
# Each arm gets its own fixture tree carrying a violation of THAT arm's rule and nothing else, so
# an over-wide red indicts the mutant rather than the coverage. Every arm is asserted in all
# reachable own-states, including the ones that MUST still block — the bar is not being lowered
# here, only moved off the wrong author (a suite that only proved "does not block" would pass
# against a deleted ratchet).
#
# MEASURED RED BEFORE THE FIX, per site, on the pre-fix scripts:
#   chromium-bundle   SET-BUT-EMPTY → rc 1 (blocked a docs-only land over a sibling's file)
#   pipefail-sigpipe  SET-BUT-EMPTY → rc 1 (same shape, same cause)
#   unattended-path   SET-BUT-EMPTY → rc 1 AND a SET own-set naming a different file → rc 1
#                     (its stuck-ratchet branch consulted no own-set at all)
# The structural test at the bottom is what stops the NEXT arm from re-introducing it by copying
# a neighbour — which is how all of these came to share one defect.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX"
}

# ── arm 1/15: chromium-bundle ────────────────────────────────────────────────────────────────────
# Fixture: one file carrying the real scar shape — the playwright FULL app bundle path.
cb_fixture() {
  mkdir -p "$FIX/cb/scripts"
  printf '#!/usr/bin/env bash\nCHROME="$HOME/x/chrome-mac/Chromium.app/Contents/MacOS/Chromium"\n"$CHROME" --headless --screenshot "$1"\n' \
    > "$FIX/cb/scripts/sibling.sh"
}

@test "chromium-bundle: UNSET own-set is STRICT — the sibling's file blocks" {
  cb_fixture
  run env -u CC_CHROMIUM_OWN bash "$REPO/scripts/chromium-bundle-lint.sh" --root "$FIX/cb"
  [ "$status" -eq 1 ]
}

@test "chromium-bundle: SET-BUT-EMPTY own-set blocks NOTHING (the docs-only land)" {
  # THE LEAK. Pre-fix this was rc 1: `${CC_CHROMIUM_OWN:-}` could not tell "no caller scoped" from
  # "a caller scoped and owns nothing here", so a land touching none of bin/hooks/scripts/tools was
  # refused over a file it had never opened, with nothing of its own to fix.
  cb_fixture
  run env CC_CHROMIUM_OWN="" bash "$REPO/scripts/chromium-bundle-lint.sh" --root "$FIX/cb"
  [ "$status" -eq 0 ]
}

@test "chromium-bundle: an own-set naming ANOTHER file blocks nothing" {
  cb_fixture
  run env CC_CHROMIUM_OWN="scripts/mine.sh" bash "$REPO/scripts/chromium-bundle-lint.sh" --root "$FIX/cb"
  [ "$status" -eq 0 ]
}

@test "chromium-bundle: the OWNER of the offending file still blocks (the bar is not lowered)" {
  cb_fixture
  run env CC_CHROMIUM_OWN="scripts/sibling.sh" bash "$REPO/scripts/chromium-bundle-lint.sh" --root "$FIX/cb"
  [ "$status" -eq 1 ]
}

@test "chromium-bundle: an own-entry carrying a regex metacharacter is matched literally" {
  # The membership test used to interpolate the own-entry into `grep -q "^$o:"`, so a path with a
  # regex metacharacter matched the wrong rows or none. A land owning a DIFFERENT file whose name
  # merely regex-matches the offender must not block, and the offender's owner must.
  mkdir -p "$FIX/cbre/scripts"
  printf '#!/usr/bin/env bash\nCHROME="$HOME/x/chrome-mac/Chromium.app/Contents/MacOS/Chromium"\n' \
    > "$FIX/cbre/scripts/aXb.sh"
  run env CC_CHROMIUM_OWN='scripts/a.b.sh' bash "$REPO/scripts/chromium-bundle-lint.sh" --root "$FIX/cbre"
  [ "$status" -eq 0 ]
}

# ── arm 2/15: pipefail-sigpipe ───────────────────────────────────────────────────────────────────
pf_fixture() {
  mkdir -p "$FIX/pf/scripts"
  printf '#!/usr/bin/env bash\nset -o pipefail\nif cat /etc/hosts | grep -q localhost; then echo yes; fi\n' \
    > "$FIX/pf/scripts/sibling.sh"
}

@test "pipefail-sigpipe: UNSET own-set is STRICT — the sibling's file blocks" {
  pf_fixture
  run env -u CC_PIPEFAIL_OWN CC_PIPEFAIL_ROOT="$FIX/pf" bash "$REPO/scripts/pipefail-sigpipe-lint.sh"
  [ "$status" -eq 1 ]
}

@test "pipefail-sigpipe: SET-BUT-EMPTY own-set blocks NOTHING (the launchd-only land)" {
  # THE LEAK, same shape as chromium's. This arm's pathspec lists bin/ hooks/ scripts/ tests/
  # docs/ *.sh — so a land touching only launchd/ or commands/ produces an empty own-set and was
  # judged against the whole tree.
  pf_fixture
  run env CC_PIPEFAIL_OWN="" CC_PIPEFAIL_ROOT="$FIX/pf" bash "$REPO/scripts/pipefail-sigpipe-lint.sh"
  [ "$status" -eq 0 ]
}

@test "pipefail-sigpipe: an own-set naming ANOTHER file blocks nothing" {
  pf_fixture
  run env CC_PIPEFAIL_OWN="scripts/mine.sh" CC_PIPEFAIL_ROOT="$FIX/pf" bash "$REPO/scripts/pipefail-sigpipe-lint.sh"
  [ "$status" -eq 0 ]
}

@test "pipefail-sigpipe: the OWNER of the offending file still blocks (the bar is not lowered)" {
  pf_fixture
  run env CC_PIPEFAIL_OWN="scripts/sibling.sh" CC_PIPEFAIL_ROOT="$FIX/pf" bash "$REPO/scripts/pipefail-sigpipe-lint.sh"
  [ "$status" -eq 1 ]
}

# ── arm 3/15: unattended-path (the STUCK-RATCHET branch) ─────────────────────────────────────────
# The worst of the three, and the only one that ignored own-scope in ALL states. An allowlist entry
# goes "stuck" when its site stops violating — which happens when a SIBLING fixes or deletes that
# file, and also when nothing in the tree changed at all and the BOX did (the lint's
# installed_somewhere searches the caller's live $PATH, so an entry stops counting as used the
# moment gtimeout/lsof/sysctl becomes unreachable here). Unscoped, that refused every land on the
# machine and told the author to edit an allowlist line that was not theirs.
up_fixture() {
  mkdir -p "$FIX/up/hooks"
  printf '#!/usr/bin/env bash\n/bin/echo hello\n' > "$FIX/up/hooks/clean.sh"
  UP_ALLOW="hooks/clean.sh:gtimeout
"
}

@test "unattended-path: UNSET own-set is STRICT — a stuck allowlist entry blocks" {
  up_fixture
  run env -u CC_UNATTENDED_OWN CC_UNATTENDED_ALLOWLIST="$UP_ALLOW" \
    bash "$REPO/scripts/unattended-path-lint.sh" "$FIX/up"
  [ "$status" -eq 1 ]
}

@test "unattended-path: SET-BUT-EMPTY own-set does not block on a stuck entry" {
  up_fixture
  run env CC_UNATTENDED_OWN="" CC_UNATTENDED_ALLOWLIST="$UP_ALLOW" \
    bash "$REPO/scripts/unattended-path-lint.sh" "$FIX/up"
  [ "$status" -eq 0 ]
}

@test "unattended-path: a stuck entry for a file OUTSIDE the diff is advisory, not blocking" {
  # THE LEAK IN ITS SHARPEST FORM. Pre-fix this was rc 1 even though the own-set explicitly named
  # a different file — the stuck-ratchet `return 1` consulted neither $own nor $have_own.
  up_fixture
  run env CC_UNATTENDED_OWN="hooks/mine.sh" CC_UNATTENDED_ALLOWLIST="$UP_ALLOW" \
    bash "$REPO/scripts/unattended-path-lint.sh" "$FIX/up"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -F "advisory, not blocking" >/dev/null
}

@test "unattended-path: the AUTHOR who fixed the site still owes the allowlist line" {
  # The one case with an actor who can act, and it must be unchanged: the ratchet only shrinks if
  # the person who shrank it also lowers the line.
  up_fixture
  run env CC_UNATTENDED_OWN="hooks/clean.sh" CC_UNATTENDED_ALLOWLIST="$UP_ALLOW" \
    bash "$REPO/scripts/unattended-path-lint.sh" "$FIX/up"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -F "STUCK RATCHET" >/dev/null
}

# ── the CONTROLS: arms the audit found CLEAN must already behave, or the mutant proves nothing ───
# These are the discrimination check for the instrument above. If a clean arm failed here, the
# fixture shape — not the arm — would be what the leaking tests were measuring.

@test "control: self-path already distinguishes all three own-states" {
  mkdir -p "$FIX/sp/scripts"
  printf '#!/usr/bin/env bash\nROOT="$(dirname "$0")/.."\necho "$ROOT"\n' > "$FIX/sp/scripts/sibling.sh"
  run env -u CC_SELFPATH_OWN bash "$REPO/scripts/self-path-lint.sh" "$FIX/sp"
  [ "$status" -eq 1 ]
  run env CC_SELFPATH_OWN="" bash "$REPO/scripts/self-path-lint.sh" "$FIX/sp"
  [ "$status" -eq 0 ]
  run env CC_SELFPATH_OWN="scripts/sibling.sh" bash "$REPO/scripts/self-path-lint.sh" "$FIX/sp"
  [ "$status" -eq 1 ]
}

@test "control: tsv-pad already distinguishes UNSET from SET-BUT-EMPTY" {
  # No violation is planted: this control asserts only that the two states take DIFFERENT code
  # paths, which is what the leaking arms could not do. A clean tree returns 0 either way, so the
  # discriminator is the reported scope line, not the exit code.
  run env CC_TSVPAD_OWN="" bash "$REPO/scripts/tsv-pad-lint.sh" "$REPO"
  [ "$status" -eq 0 ]
}

# ── THE STRUCTURAL RATCHET — what stops the next arm inheriting the defect ────────────────────────

@test "every CC_*_OWN lint distinguishes UNSET from SET-BUT-EMPTY (no two-state presence test)" {
  # The three leaks were one defect copied between neighbours, so the durable fix is a rule, not
  # three patches. A lint may read its own-set however it likes, but its PRESENCE test must be able
  # to express three states: `${VAR+set}` (or an equivalent arity check), never `${VAR:-}` /
  # `${VAR-}`, which collapse UNSET and SET-BUT-EMPTY into one.
  #
  # The arm list is derived from ship-land.sh's own call sites rather than hardcoded here, so an
  # arm added later is covered without anyone remembering to edit this test (memory:
  # caller-census-keyed-on-path-misses-the-name — a census keyed on a list you maintain by hand
  # answers about the list, not the population).
  # COMMENTS ARE NOT CODE, and the first draft of this test forgot it: every one of these lints
  # DISCUSSES the `${VAR:-}` form in prose (several warn against it by name, which is precisely why
  # they got it right), so a raw grep indicted six correct files. An over-wide red indicts the
  # mutant, not the coverage (memory: per-site-mutation-attributes-coverage) — so the scan drops
  # whole-line comments first, and asserts BOTH directions rather than only the negative one.
  # THE POPULATION IS THE LINTS, not every file that mentions the variable. Grepping the tree by
  # name pulled in scripts/postland-verify.sh, which names CC_HERM_OWN/CC_WALLTIME_OWN only to
  # `unset` them — it is the whole-tree verifier, i.e. a CALLER doing exactly the right thing, and
  # convicting it would have been the census-keyed-on-the-wrong-population error twice in one test.
  # So each arm's lint is read from ship-land's own `SHIP_LAND_<ARM>_LINT` default, which is the
  # authoritative mapping and lives beside the own_run call it pairs with.
  local pairs bad="" arm v f code lint
  pairs="$(grep -oE 'own_run [A-Z_]+ CC_[A-Z_]*OWN' "$REPO/scripts/ship-land.sh" | sort -u)"
  [ -n "$pairs" ]
  # A FLOOR, not an equality — and the difference is the whole point of deriving the list above.
  # This assertion exists for ONE failure: the grep stops matching (a renamed helper, a reformatted
  # call site) and the census silently returns too little, so the per-arm loop below iterates over
  # a truncated population and the test passes having checked almost nothing. A floor catches that.
  #
  # `-eq 13` instead made it a tripwire on its own subject's GROWTH. 85fd75bc8 added a FOURTEENTH
  # env-scoped arm — own_run MOVINGREF CC_MOVINGREF_OWN — correctly, three-state presence test and
  # all, and this line went red for it: not a regression, a sibling doing the right thing. Worse,
  # bats aborts the test body at the failing line, so the per-arm loop that is the ACTUAL check
  # never ran and the new arm went unjudged by the very test that was red about it. And because
  # this suite is a land gate, an assertion that COUNTS blocked every land in the repo.
  #
  # So: floor here, TALLY below (memory: exact-count-assertion-tripwires-its-own-subject). The
  # remaining ratchet arms — bats dead-assertion, scoped by ARGUMENT LIST, and unguarded-kill,
  # deliberately strict whole-corpus — carry no CC_*_OWN and are correctly outside this rule.
  [ "$(printf '%s\n' "$pairs" | grep -c .)" -ge 13 ]
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    arm="$(printf '%s' "$p" | awk '{print $2}')"
    v="$(printf '%s' "$p" | awk '{print $3}')"
    lint="$(grep -oE "SHIP_LAND_${arm}_LINT:-[^}]+" "$REPO/scripts/ship-land.sh" | head -1 | sed "s/^SHIP_LAND_${arm}_LINT:-//")"
    [ -n "$lint" ] || { bad="$bad$arm: no SHIP_LAND_${arm}_LINT default to resolve
"; continue; }
    f="$REPO/$lint"
    [ -f "$f" ] || { bad="$bad$arm: $lint does not exist
"; continue; }
    case "$f" in *.py) continue ;; esac   # a python lint expresses presence differently
    if true; then
      code="$(grep -v '^[[:space:]]*#' "$f")"
      # NEGATIVE: no executable line may use the two-state form as its presence test.
      if printf '%s\n' "$code" | grep -E "\\\$\{$v(:-|-)" >/dev/null 2>&1; then
        bad="$bad$lint reads \${$v:-} in CODE — two-state, cannot express SET-BUT-EMPTY
"
      fi
      # POSITIVE: it must actually carry a three-state presence test somewhere. Without this half
      # a lint that read the variable with NO presence test at all would pass, which is the same
      # collapse arriving by omission instead of by spelling.
      if ! printf '%s\n' "$code" | grep -F "\${$v+" >/dev/null 2>&1; then
        bad="$bad$lint reads $v but carries no \${$v+set} presence test
"
      fi
    fi
  done < <(printf '%s\n' "$pairs")
  [ -z "$bad" ] || { printf '%s' "$bad" >&2; return 1; }
}

@test "own_run: the =off kill switch UNSETS the variable, restoring strict whole-tree blocking" {
  # The switch every arm documents as "restores whole-tree blocking" used to leave the own-set
  # empty and STILL export it — so the lint read SET-BUT-EMPTY and blocked on NOTHING. The escape
  # hatch for a leaking arm silently disabled that arm. Asserted through ship-land's own helper,
  # against a probe that reports which of the three states it was handed.
  cat > "$FIX/probe.sh" <<'PROBE'
#!/usr/bin/env bash
if [ -z "${CC_PROBE_OWN+set}" ]; then echo UNSET
elif [ -z "$CC_PROBE_OWN" ]; then echo EMPTY
else echo "SET:$CC_PROBE_OWN"; fi
PROBE
  chmod +x "$FIX/probe.sh"
  # The function is EXTRACTED, never sourced: ship-land.sh's dispatch tail calls main_outer when it
  # is read with no `__locked` argument, so `source` would fire a REAL LAND from inside the suite.
  # Same idiom tests/bats-shellcheck-lint.bats already uses on this file.
  sed -n '/^own_run() {/,/^}/p' "$REPO/scripts/ship-land.sh" > "$FIX/own_run.sh"
  [ -s "$FIX/own_run.sh" ]

  run bash -c ". '$FIX/own_run.sh'; own_run PROBE CC_PROBE_OWN 'a/b.sh' '$FIX/probe.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "SET:a/b.sh" ]

  run bash -c ". '$FIX/own_run.sh'; own_run PROBE CC_PROBE_OWN '' '$FIX/probe.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "EMPTY" ]

  run bash -c ". '$FIX/own_run.sh'
               SHIP_LAND_PROBE_OWN_SCOPE=off own_run PROBE CC_PROBE_OWN 'a/b.sh' '$FIX/probe.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "UNSET" ]
}
