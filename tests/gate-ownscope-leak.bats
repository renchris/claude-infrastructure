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
  # DOGFOOD rules 5 and 6 of test-hermeticity-lint, which this file came into scope for the moment
  # the basename-collapse cases below started EXECUTING that lint by path. Both variables are that
  # lint's own extractor anchors — it declares CC_HERM_SEAM_SELFPROBE with an absolute /tmp default
  # (rule 5, shape 5a) and CC_HERM_ENV_SELFPROBE as both an injection and a read (rule 6) — so a
  # suite naming its path must take a position on each. tests/test-hermeticity-lint.bats pins the
  # identical pair for the identical reason. A lint's caller sitting on that lint's exemption list
  # is the rot this repo is killing.
  export CC_HERM_SEAM_SELFPROBE="$BATS_TEST_TMPDIR/absent-seam-anchor"
  export CC_HERM_ENV_SELFPROBE=0
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX"
}

# mk_gid_leak <path> — a fixture carrying ONE git-identity violation: a bare `-C` expansion on an
# identity write.
#
# THE SHAPE IS ASSEMBLED, NEVER WRITTEN — the same idiom scripts/tsv-pad-lint.sh takes for its scan
# marker, and for the same reason. Spelled literally, this line would itself be a git-identity
# violation, and the land gate would refuse the very file that proves that arm's own-scope works.
# (Measured: the precheck reds on it.) The lint keys on a contiguous `user.email` / `user.name`, so
# splitting the key across two printf arguments keeps a TRUE violation on disk while no source line
# here carries the shape. Text is never evidence — what makes this a valid control is the file
# written, not the file writing it.
mk_gid_leak() {  # $1 = path of the .bats fixture to write
  mkdir -p "${1%/*}"
  printf '@test "x" {\n  git -C "$dir" config %s%s t@t\n}\n' 'user.' 'email' > "$1"
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

# ── THE BASENAME COLLAPSE — the second half of the own-set contract (backlog c1a29f8ee045) ───────
#
# THE THREE STATES above answer "did a caller scope this run?". They say nothing about WHICH files
# an own-set names, and that is where §5.P2's audit left two arms filed-not-fixed: it recorded
# arms 1 and 4 as carrying a latent basename collapse and closed the row with "no basename
# collisions exist in the tree today". That is a property of the TREE, checked by hand on one day,
# not a property of the code — the first `bin/x.sh` + `scripts/x.sh` pair anyone adds re-opens it,
# and nothing in the gate would notice.
#
# WHAT COLLAPSED. All four matchers basenamed the own-set (`sed 's:.*/::'`) and compared it to a
# basename, so an entry `scripts/foo.sh` matched a judged `tests/foo.sh`: the land is refused over a
# file it never touched, which is the fleet-wide hard stop this whole mechanism exists to remove,
# re-entering through the MATCHER rather than through the scope. utc-stamp's copy carried the same
# defect one level out — it matches paths, but the lint scans bin/, hooks/ and scripts/ as three
# separate roots, so ship-land stripped the leading component to make the two sides meet and merged
# the three namespaces doing it.
#
# THE CONTRACT NOW, one body shared by four files:
#   a PATHED entry (contains `/`) matches the judged path exactly or as a suffix on a COMPONENT
#     boundary — `tests/foo.bats` matches `<root>/tests/foo.bats` and never `scripts/foo.bats`;
#   a BARE entry (no `/`) is a basename and still matches in any directory — deliberately wide,
#     because callers pass bare names and the too-narrow direction lets a real violation land.
# Each lint's own --selftest proves both directions on its own fixtures. These tests are the
# BLACK-BOX half, driven through the real entrypoints and their real CC_*_OWN seams, plus the
# structural pin below that stops the four copies drifting apart.

@test "basename collapse: a PATHED own-entry blocks its own path and NOT the same name elsewhere" {
  # One fixture tree per lint, each carrying that lint's violation under a REAL directory name, so
  # the entry's directory component is load-bearing rather than decoration.
  #
  # git-identity: the judged file is tests/zz-probe.bats. `scripts/zz-probe.bats` is a different
  # file, so it must not block; `tests/zz-probe.bats` is this one, so it must.
  mk_gid_leak "$FIX/bc_gid/tests/zz-probe.bats"
  run env CC_GITID_ALLOWLIST="" CC_GITID_OWN="tests/zz-probe.bats" bash "$REPO/scripts/git-identity-lint.sh" "$FIX/bc_gid"
  [ "$status" -eq 1 ]
  run env CC_GITID_ALLOWLIST="" CC_GITID_OWN="scripts/zz-probe.bats" bash "$REPO/scripts/git-identity-lint.sh" "$FIX/bc_gid"
  [ "$status" -eq 0 ]

  # test-hermeticity: same shape on a $HOME leak. Rule 4 is pinned off — it scans the real tool
  # dirs under the given root, and a rule-4 verdict about the fixture would become this assertion's
  # answer (the lint's own selftest records the same trap at case (m)).
  mkdir -p "$FIX/bc_herm/tests"
  printf '#!/usr/bin/env bats\nsetup() {\n  REPO="$(pwd)"\n}\n@test "x" { true; }\n' > "$FIX/bc_herm/tests/zz-probe.bats"
  run env CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_RULE=off CC_HERM_ENV_RULE=off \
      CC_HERM_OWN="tests/zz-probe.bats" bash "$REPO/scripts/test-hermeticity-lint.sh" "$FIX/bc_herm/tests"
  [ "$status" -eq 1 ]
  run env CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_RULE=off CC_HERM_ENV_RULE=off \
      CC_HERM_OWN="scripts/zz-probe.bats" bash "$REPO/scripts/test-hermeticity-lint.sh" "$FIX/bc_herm/tests"
  [ "$status" -eq 0 ]
}

@test "basename collapse: utc-stamp matches the repo-relative path ship-land now passes UNSTRIPPED" {
  # This arm's collapse was in the CALLER. The lint scans bin/ hooks/ scripts/ as three roots, so
  # ship-land used to strip the leading component off `git diff --name-only` to make an own-set
  # entry meet the lint's per-root `rel` — and `bin/cc-x` and `scripts/cc-x` both became `cc-x`.
  # The strip is gone and the lint matches the full scanned path, so BOTH halves have to hold: the
  # unstripped entry must still block (or every land would block on nothing, which is the
  # fail-permissive direction and would have gone unnoticed), and the sibling root must not.
  mkdir -p "$FIX/bc_utc/bin" "$FIX/bc_utc/scripts"
  printf '#!/bin/bash\nlog(){ printf "[%%s]\\n" "$(date \x27+%%Y-%%m-%%dT%%H:%%M:%%SZ\x27)"; }\n' > "$FIX/bc_utc/bin/zz-probe.sh"
  printf '#!/bin/bash\necho fine\n' > "$FIX/bc_utc/scripts/zz-probe.sh"
  run env CC_UTC_ALLOWLIST="" CC_UTC_OWN="bin/zz-probe.sh" bash "$REPO/scripts/utc-stamp-lint.sh" "$FIX/bc_utc/bin"
  [ "$status" -eq 1 ]
  run env CC_UTC_ALLOWLIST="" CC_UTC_OWN="scripts/zz-probe.sh" bash "$REPO/scripts/utc-stamp-lint.sh" "$FIX/bc_utc/bin"
  [ "$status" -eq 0 ]

  # …and the caller half, asserted on ship-land's source: a re-introduced strip would silently put
  # the collapse back with every lint here still passing, because the lints never see the caller.
  # RE-ANCHORED 2026-08-26. This used to `run grep -n "uown=\"\$(git diff --name-only"` — a
  # SOURCE-TEXT anchor on a spelling the 2026-08-15 lint_own_scope refactor deleted (backlog
  # c1a29f8ee045 / 5fc8ff411a7c, and the arm's own comment records the removal). The grep therefore
  # matched nothing, `[ "$status" -eq 0 ]` went red — and the `case` that carried the ACTUAL
  # anti-strip check never executed at all. So this guard had stopped guarding while reporting
  # itself as a RED on every land that selected it: the loud failure and the silent hole were the
  # same event. An anchor pins a SPELLING and rots with the next refactor; assert the PROPERTY.
  run grep -n 'uown="$(lint_own_scope' "$REPO/scripts/ship-land.sh"
  [ "$status" -eq 0 ]
  # THE PROPERTY, and it is what the `case` above was reaching for: no LIVE line may re-introduce
  # the strip. Comment lines are excluded deliberately — the one surviving mention is the comment
  # RECORDING the removal, and a guard that counted its own documentation is the scar where a grep
  # matches the prose describing the thing instead of the thing.
  [ "$(grep -Fn "sed 's:^[^/]*/::'" "$REPO/scripts/ship-land.sh" | grep -vc '^[0-9]*: *#')" -eq 0 ]
}

@test "basename collapse: a BARE own-entry is still wide — it matches in any directory" {
  # The width of the bare form is deliberate and load-bearing: callers do pass bare names, and the
  # too-narrow direction reports a real violation as "not in your diff — advisory" and lets it
  # land. Without this half, "tighten the matcher" reads as "tighten it everywhere", which is the
  # direction that turns a gate into detection (memory: gate-default-decides-failure-direction).
  mk_gid_leak "$FIX/bc_bare/tests/zz-probe.bats"
  run env CC_GITID_ALLOWLIST="" CC_GITID_OWN="zz-probe.bats" bash "$REPO/scripts/git-identity-lint.sh" "$FIX/bc_bare"
  [ "$status" -eq 1 ]
}

@test "the four in_own copies are ONE body — a fix to any of them cannot miss the others" {
  # These four lints source nothing (utc-stamp and tsv-pad source nothing at all; the other two take
  # gate-memo through an optional `. … || true`), so the shared predicate is four literal copies.
  # That is deliberate — a correctness-critical matcher arriving through an optional source degrades
  # SILENTLY when the live layer has not converged on the new lib file, and this repo IS the live
  # layer's source. The cost of copies is drift, and drift is what this pins: all four bodies must
  # be byte-identical below the signature line. The signature comment differs by design (each names
  # its own caller), so the comparison starts after it.
  #
  # This is the same lesson as the three-state test below it: one defect copied between neighbours
  # needs a rule, not N patches. §5.P2 fixed three arms of that defect and left two arms of THIS one
  # filed as latent — the pin is what makes "latent" a state the gate can see.
  local first="" body f n=0 bad=""
  for f in test-hermeticity git-identity utc-stamp tsv-pad; do
    body="$(sed -n '/^in_own() {/,/^}/p' "$REPO/scripts/$f-lint.sh" | sed '1d')"
    [ -n "$body" ] || { bad="$bad$f-lint.sh: no in_own() body found — the extractor stopped matching
"; continue; }
    n=$((n + 1))
    if [ -z "$first" ]; then first="$body"
    elif [ "$body" != "$first" ]; then
      bad="$bad$f-lint.sh's in_own has drifted from test-hermeticity-lint.sh's
"
    fi
  done
  [ "$n" -eq 4 ] || { echo "expected 4 in_own bodies, extracted $n" >&2; return 1; }
  [ -z "$bad" ] || { printf '%s' "$bad" >&2; return 1; }
  # POSITIVE: the body must actually implement the two-form rule, not merely agree with itself —
  # four identical copies of a re-introduced `sed 's:.*/::'` would pass the comparison above.
  case "$first" in
    *"sed 's:.*/::'"*) echo "in_own basenames the own-set again — the collapse is back in all four" >&2; return 1 ;;
  esac
  printf '%s' "$first" | grep -qF '*/"$e") return 0' || { echo "in_own no longer matches a PATHED entry on a component boundary" >&2; return 1; }
  printf '%s' "$first" | grep -qF '${1##*/}' || { echo "in_own no longer matches a BARE entry as a basename" >&2; return 1; }
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
  # So: floor here, TALLY below (memory: exact-count-assertion-tripwires-its-own-subject). The one
  # remaining ratchet arm outside this rule is bats dead-assertion, scoped by ARGUMENT LIST.
  #
  # unguarded-kill USED to sit beside it, "deliberately strict whole-corpus" — and that exemption is
  # gone (backlog e191b6801be5): its strictness rested on the UNENFORCED runtime invariant that the
  # corpus baseline stays zero, so one sibling's unguarded kill refused every land in the fleet. It
  # now carries CC_KILLGUARD_OWN and is covered by the per-arm loop below like any other; its own
  # three-state behaviour is pinned in tests/bats-kill-guard-lint.bats.
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

# ── THE FAIL-OPEN PIPELINE IN THE MEMBERSHIP PREDICATES (drain recycle #241) ──────────────────────
# One defect, six copies, and the guard that exists to catch it is structurally blind to all six.
#
# THE SHAPE. Every own-scope lint answers "may this finding BLOCK the land?" with a membership
# predicate whose whole body is a pipeline: `printf '%s\n' "$2" | [sed …] | grep -qxF "$1"`. It is
# the FUNCTION-FINAL statement, so its rc IS the return value the caller reads. Under the
# `set -uo pipefail` every one of these lints sets, `grep -q` exits the instant it matches, the
# producer takes SIGPIPE, and pipefail hands the caller 141 (external producer) or 1 (bash builtin)
# — both of which mean NOT-IN-OWN-SCOPE. A MATCH therefore reads as "not in your diff", which
# downgrades a real finding from BLOCKING to advisory and lets it land. A fail-OPEN in a blocking
# land gate. scripts/deploy-link-parity.sh:264 wrote this scar out once already; #240 drained
# test-walltime-lint's copy; these are the rest.
#
# WHY A TEST AND NOT A COMMENT. scripts/pipefail-sigpipe-lint.sh's clause 4 asks whether anything
# READS the pipeline's status, and a function-final pipeline's status is read by the CALLER, which
# the clause could not observe. Measured then: its --census saw 0 of the three in_own sites and the
# allowlist grandfathered none of them, so they were not exempt — they were INVISIBLE. That was
# backlog ca97c678b18b, and IT IS CURED: clause 4c — the FOURTEENTH CORRECTION in
# scripts/pipefail-sigpipe-lint.sh — collects same-file callers in a first pass, so a function-final
# pipeline is judged by whoever reads its rc.
#
# ⚠️ THIS TEST DOES NOT RETIRE WITH THAT ROW, AND THE REASON IS A MEASUREMENT RATHER THAN CAUTION.
# Re-measured 2026-09-04 against the SHIPPED detector on one fixture per cell, empty allowlist,
# beside an inline `if p | grep -q` FIRE control that reports: the MULTI-LINE `in_own` shape is now
# reported, and the ONE-LINE `in_allowlist() { … | grep -qxF …; }` shape is NOT. Clause 4c reads
# function-final off the house shape `name() {` … `}` with the closing brace at column 0 — its own
# residual (b) — so HALF the population the arm below sweeps is still invisible to the ratchet, and
# the arm sweeps BOTH predicates by construction. It also pins the drained SPELLING, which no
# detector fix makes redundant.
#
# THE REGIME IS MEASURED, NOT ASSUMED (2026-08-26, load ~13, 20 trials per size). The transition is
# a RACE with a band, not a step, and it differs by pipeline SHAPE — so the single 64 KiB constant
# in the sibling comments describes only the two-stage form:
#     2-stage  printf | grep -q        safe to 37,121 B · racy at 55,721 · ALWAYS inverted 87,122+
#     3-stage  printf | sed | grep -q  safe to 17,427 B · ALWAYS inverted from 23,227 B
#
# ⚠️ BOTH ROWS ABOVE ARE KEPT ONLY AS THE HISTORICAL READING; BOTH HAVE SINCE BEEN REFUTED, AND THE
# 3-STAGE ROW IS WRONG IN ITS UNIT AND NOT MERELY IN ITS VALUE (2026-08-28,
# ~/.claude/autonomy/probe257-{3stage,emit}.sh; the full table is in the header of
# scripts/pipefail-sigpipe-lint.sh, which is the SSOT for these bands).
#   · "safe to 17,427 B" holds at ONE line width and not at two others on the SAME producer bytes:
#     17,420 B over 1,340 lines of 13 B is 0/200, while 17,435 B over 317 lines of 55 B is 43/200
#     and 17,433 B over 117 lines of 149 B is 54/200.
#   · "ALWAYS inverted from 23,227 B" is RACY, not ALWAYS: 137-149 of 200 across four widths. The
#     ALWAYS band needs ~94,711 emitted bytes. Both rows' sharp edges are n=20 artifacts.
#   · THE BINDING QUANTITY IS WHAT THE STAGE FEEDING grep EMITS, not what the producer writes.
#     Held at 400 lines x 55 B = 22,000 producer bytes in all six cells and varying only the bytes
#     the `sed` strips: 279/400 wrong at 18,000 emitted, 1/400 at 16,400, 0/400 at 15,600.
#     scripts/postland-verify.sh:3359 had already landed exactly this sentence on 2026-08-27.
# THE PIN BELOW IS UNAFFECTED — it asserts the drained SPELLING, which is correct at every size, and
# the numbers above are the RATIONALE for draining rather than the thing being pinned.
# Only ONE of the six sites can reach its floor today: bats-shellcheck's own-set is one "path:line"
# per CHANGED LINE, and a real 60-commit landing range on this repo already measures 95,164 bytes.
# The other five are bounded under their floors by an empty embedded allowlist or by the whole .bats
# corpus being 16,945 bytes of paths. LATENT, not safe: every one of those ceilings is an
# operational quantity that grows.

@test "no membership predicate in a land-blocking lint ends in an early-exit pipeline" {
  # DERIVED population, never a hand-listed one: the sites this defect can hide in are exactly the
  # membership predicates of the own-scope lints, and a list written by hand goes stale the day a
  # lint is added. The count assertion below is what stops a broken extractor reporting a clean
  # sweep over nothing (memory: probe-that-acts-on-absence-must-confirm-presence).
  #
  # COMMENT LINES ARE STRIPPED FIRST, and that is load-bearing rather than tidy: the drained sites
  # each carry a comment EXPLAINING the -q hazard, so a grep over raw bodies matches the prose
  # documenting the fix and convicts the fixed file (memory: enforce-at-chokepoint's scar, and the
  # rule that the repair is to ANCHOR, never to reword).
  local f n=0 bad="" body live
  for f in "$REPO"/scripts/*-lint.sh; do
    for pred in in_own in_allowlist; do
      body="$(sed -n "/^$pred()/,/^}/p" "$f")"
      [ -n "$body" ] || continue
      n=$((n + 1))
      live="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*#')"
      if [ "$(printf '%s\n' "$live" | grep -cE '\|[[:space:]]*(/usr/bin/)?grep[[:space:]]+-[A-Za-z]*q')" -ne 0 ]; then
        bad="$bad$(basename "$f")'s $pred pipes into an early-exit grep -q
"
      fi
    done
  done
  [ "$n" -ge 8 ] || { echo "extractor found only $n predicates — it has stopped matching" >&2; return 1; }
  [ -z "$bad" ] || { printf '%s' "$bad" >&2; return 1; }
}

@test "bats-kill-guard carries a FIFTH copy of the shared in_own body, unpinned by the four-copy test" {
  # The test above this block pins four copies byte-identical. There are ELEVEN in_own definitions
  # under scripts/, and bats-kill-guard's is byte-identical to the pinned four while sitting outside
  # their loop — so a drift there is invisible to the pin that exists to catch drift. Its title says
  # "the four", which reads as a completeness claim over a population it does not span
  # (memory: assertion-span-must-equal-its-subject). Pinned here rather than by widening that loop,
  # so the existing arm keeps asserting exactly what its comment explains.
  local a b
  a="$(sed -n '/^in_own() {/,/^}/p' "$REPO/scripts/test-hermeticity-lint.sh" | sed '1d')"
  b="$(sed -n '/^in_own() {/,/^}/p' "$REPO/scripts/bats-kill-guard-lint.sh" | sed '1d')"
  [ -n "$a" ] || { echo "test-hermeticity in_own body not found — extractor stopped matching" >&2; return 1; }
  [ -n "$b" ] || { echo "bats-kill-guard in_own body not found — extractor stopped matching" >&2; return 1; }
  [ "$a" = "$b" ] || { echo "bats-kill-guard's in_own has drifted from the four pinned copies" >&2; return 1; }
}

@test "bats-shellcheck's in_own still answers IN-OWN on an own-set past the pipe-buffer regime" {
  # THE BEHAVIOURAL ARM, and the only one of the three that survives a rewording of the fix. The two
  # above pin a SPELLING; this one pins the MECHANISM, which is the property that may not change
  # (memory: control-calibrated-to-implementation-decays — #240 lost a pre-land run to a stub keyed
  # on the exact flag string its own correct fix removed).
  #
  # 162,716 bytes over 2,601 lines of 62.6 B, needle on line 1, is past the measured always-inverted
  # floor of 87,122 for this two-stage shape, so a re-introduced `grep -q` fails this
  # deterministically rather than one run in twenty. The function is EXTRACTED and sourced, never
  # re-implemented, so this replays the real shipped artifact (memory:
  # control-must-replay-the-real-artifact).
  #
  # THAT SIZE WAS "120,000 bytes" HERE UNTIL 2026-08-28 AND THE GENERATOR NEVER PRODUCED IT. Running
  # this awk verbatim writes 162,716 B — the stated figure was 35.6% low. Harmless in this direction
  # (bigger is further past the floor) but it is the SECOND fixture in this repo whose landed size
  # omitted framing the fixture itself introduced; tests/pipefail-sigpipe-lint.bats test 7 confesses
  # the first ("63488 … actually wrote 64290"). Measured, not computed: 500/500 inverted at this
  # shape, 0/500 truncated to 16,384 B (~/.claude/autonomy/probe256-fix.sh).
  #
  # AND THE GUARD BELOW IS A PROXY, WHICH IS WORTH KNOWING WHEN YOU EDIT THE GENERATOR. 87,122 is a
  # byte figure, and scripts/pipefail-sigpipe-lint.sh's header now records that the floor is scoped
  # to (bytes, LINE WIDTH, CONSUMER, trial count). The width is the lever: at 37,121 B, 2,856 lines
  # of 13 B invert 763/1,000 while 676 lines of 55 B invert 0/1,000. It does NOT bite here — the
  # same 162,716 B rebuilt at 998 B per line still inverts 500/500, because that far above the
  # buffer the producer has unwritten remainder whatever the line count — so the guard is sound at
  # THIS size and the width caveat is band-limited, not general. Do not carry either half across to
  # a fixture near 37 KB without re-measuring.
  sed -n '/^in_own() {/,/^}/p' "$REPO/scripts/bats-shellcheck-lint.sh" > "$FIX/in_own.sh"
  [ -s "$FIX/in_own.sh" ] || { echo "in_own body not found in bats-shellcheck-lint.sh" >&2; return 1; }
  awk 'BEGIN{ printf "tests/zz-needle.bats:1\n";
              for (i = 1; i <= 2600; i++) printf "tests/filler-%06d-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bats:%d\n", i, i }' \
    > "$FIX/own.txt"
  [ "$(wc -c < "$FIX/own.txt")" -ge 87122 ] || { echo "fixture is under the inverting floor — it cannot discriminate" >&2; return 1; }

  # POSITIVE: a member answers 0. Under pipefail, a re-introduced -q returns 1 or 141 here.
  run bash -c "set -uo pipefail; . '$FIX/in_own.sh'; own=\"\$(cat '$FIX/own.txt')\"; in_own 'tests/zz-needle.bats:1' \"\$own\" 1; echo rc=\$?"
  [ "$output" = "rc=0" ] || { echo "member read as NOT-in-own: $output" >&2; return 1; }

  # NEGATIVE: a non-member must still answer non-zero, so the arm cannot pass by always returning 0.
  run bash -c "set -uo pipefail; . '$FIX/in_own.sh'; own=\"\$(cat '$FIX/own.txt')\"; in_own 'tests/absent-from-the-set.bats:9' \"\$own\" 1; echo rc=\$?"
  [ "$output" = "rc=1" ] || { echo "non-member did not answer 1: $output" >&2; return 1; }
}
