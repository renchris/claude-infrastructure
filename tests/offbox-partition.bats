#!/usr/bin/env bats
# tests/offbox-partition.bats — the hermetic partition and the off-box runner.
#
# SUBJECTS: scripts/offbox-partition.sh · scripts/offbox-run.sh · scripts/offbox-excluded.manifest
#           · .github/workflows/hermetic.yml
#
# These paths are named here LITERALLY and on purpose. scripts/gate-select.sh maps a changed file to
# the suites that must run by looking for its path in a suite's executable text, and its `unmapped`
# rung fails CLOSED to FULL for any non-`.md` file no clause maps (gate-select.sh:539-543). A
# manifest that no suite names would therefore make every land touching it emit FULL — which
# ship-land reads as "no direct-suite smoke this land". `scripts/host-suites.manifest` avoids that
# only because four suites name it literally; this file is how the off-box manifest earns the same.
#
# WHAT IS DELIBERATELY NOT TESTED HERE: whether any particular suite is hermetic. That is a MEASURED
# property of a runner, not an assertion — it is what .github/workflows/hermetic.yml exists to
# re-measure every commit, and pinning today's answer here would freeze a census into a contract.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PART="$REPO/scripts/offbox-partition.sh"
  RUN="$REPO/scripts/offbox-run.sh"

  # A fixture tree, so every law is exercised against a corpus this test owns.
  FX="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$FX/tests" "$FX/scripts"
  for n in a b c d e; do printf '@test "%s" { true; }\n' "$n" > "$FX/tests/$n.bats"; done
  : > "$FX/scripts/host-suites.manifest"
  : > "$FX/scripts/offbox-excluded.manifest"
}

fx() { # run the partition script against the fixture tree
  CC_OFFBOX_ROOT="$FX" \
  CC_HOST_MANIFEST="$FX/scripts/host-suites.manifest" \
  CC_OFFBOX_EXCLUDED="$FX/scripts/offbox-excluded.manifest" \
  CC_OFFBOX_TESTS_DIR="$FX/tests" \
  bash "$PART" "$@"
}

# ── the set difference ───────────────────────────────────────────────────────────────────────────

@test "1: the partition is tests/*.bats MINUS both manifests" {
  printf 'tests/a.bats\n' > "$FX/scripts/host-suites.manifest"
  printf 'tests/b.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx list
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
  printf '%s\n' "$output" | grep -qxF 'tests/c.bats'
  ! printf '%s\n' "$output" | grep -qxF 'tests/a.bats' || false
  ! printf '%s\n' "$output" | grep -qxF 'tests/b.bats'
}

@test "2: CONTROL — de-listing a suite re-admits it (the difference is real, not incidental)" {
  printf 'tests/b.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx list
  ! printf '%s\n' "$output" | grep -qxF 'tests/b.bats' || false
  : > "$FX/scripts/offbox-excluded.manifest"
  run fx list
  printf '%s\n' "$output" | grep -qxF 'tests/b.bats'
}

@test "3: a new suite lands INSIDE the partition — coverage cannot narrow silently" {
  printf '@test "new" { true; }\n' > "$FX/tests/zz-brand-new.bats"
  run fx list
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'tests/zz-brand-new.bats'
}

@test "4: an ABSENT exclusion manifest WIDENS the partition, never narrows it" {
  printf 'tests/a.bats\n' > "$FX/scripts/host-suites.manifest"
  rm -f "$FX/scripts/offbox-excluded.manifest"
  run fx list
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 4 ]
}

@test "5: SET-BUT-EMPTY is the third state — it means 'no manifest', not 'the default one'" {
  # RED CONTROL for `${VAR:-default}`, which cannot express this and would silently fall back to the
  # shipped manifest. scripts/postland-verify.sh:1121 uses the same `${VAR+set}` form for the same
  # reason. Without this test the seam would look correct and behave as if the caller had said
  # nothing at all.
  printf 'tests/a.bats\n' > "$FX/scripts/host-suites.manifest"
  run env CC_OFFBOX_ROOT="$FX" CC_HOST_MANIFEST="$FX/scripts/host-suites.manifest" \
      CC_OFFBOX_EXCLUDED= CC_OFFBOX_TESTS_DIR="$FX/tests" bash "$PART" list
  [ "$status" -eq 0 ]
  # 5 suites minus the 1 host entry, and NOTHING from a shipped off-box manifest.
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 4 ]
}

@test "6: excluding every suite is an ERROR, never an empty (vacuously green) partition" {
  for n in a b c d e; do printf 'tests/%s.bats\n' "$n"; done > "$FX/scripts/offbox-excluded.manifest"
  run fx list
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'vacuously green'
}

# ── the lint, both directions ────────────────────────────────────────────────────────────────────

@test "7: lint is clean on a well-formed manifest" {
  printf 'tests/b.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx lint
  [ "$status" -eq 0 ]
}

@test "8: lint REDS on a stale entry naming a suite that no longer exists" {
  printf 'tests/b.bats\ntests/ghost.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx lint
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'STALE'
}

@test "9: lint REDS on an entry already granted by host-suites.manifest (the DOWNWARD half)" {
  # An exemption bought twice hides one of the two. This repo's recorded failure shape for a list
  # like this is "correctly placed, wrongly broad" — only the downward half can see it.
  printf 'tests/a.bats\n' > "$FX/scripts/host-suites.manifest"
  printf 'tests/a.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx lint
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'REDUNDANT'
}

@test "10: lint REDS on a line that is not a tests/<name>.bats path" {
  printf 'scripts/offbox-run.sh\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx lint
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'NOT a tests/'
}

@test "11: lint asserts TOTALITY — partition + excluded == every suite" {
  printf 'tests/a.bats\n' > "$FX/scripts/host-suites.manifest"
  printf 'tests/b.bats\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx lint
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '5 suites = 3 partition + 2 excluded'
}

@test "12: comments and blank lines are ignored, per the frozen manifest format" {
  printf '# a comment\n\n   tests/b.bats   \n# another\n' > "$FX/scripts/offbox-excluded.manifest"
  run fx list
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -qxF 'tests/b.bats' || false
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 4 ]
}

# ── sharding ─────────────────────────────────────────────────────────────────────────────────────

@test "13: shards are TOTAL and DISJOINT — every member in exactly one shard" {
  local u
  u="$( { fx shard 1 3; fx shard 2 3; fx shard 3 3; } | LC_ALL=C sort )"
  [ "$u" = "$(fx list | LC_ALL=C sort)" ]
  [ "$(printf '%s\n' "$u" | LC_ALL=C sort -u | grep -c .)" -eq "$(printf '%s\n' "$u" | grep -c .)" ]
}

@test "14: an out-of-range shard ERRORS rather than printing a silent empty slice" {
  # An empty slice reads as "this shard had nothing to run" and its job goes GREEN — the sharded
  # form of the vacuous-green failure test 6 covers for the whole partition.
  run fx shard 4 3
  [ "$status" -eq 2 ]
  run fx shard 0 3
  [ "$status" -eq 2 ]
}

# ── the runner's classifier and fold ─────────────────────────────────────────────────────────────

fold() { # <tsv rows...> — fold against a stub partition of 3
  printf '#!/bin/bash\nprintf "tests/a.bats\\ntests/b.bats\\ntests/c.bats\\n"\n' > "$FX/part.sh"
  printf '# suite\tstate\tok\tnotok\trc\tsecs\n' > "$FX/in.tsv"
  printf '%b' "$1" >> "$FX/in.tsv"
  CC_OFFBOX_PARTITION="$FX/part.sh" bash "$RUN" verdict "$FX/in.tsv"
}

@test "15: a full sweep of greens folds to GREEN" {
  run fold 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tgreen\t2\t0\t0\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n'
  printf '%s\n' "$output" | grep -q '"verdict":"green"'
}

@test "16: R6 — a CUT is never a red and never a green" {
  run fold 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tcut\t0\t0\t124\t120\ntests/c.bats\tgreen\t1\t0\t0\t1\n'
  printf '%s\n' "$output" | grep -q '"verdict":"cut"'
  ! printf '%s\n' "$output" | grep -q '"verdict":"red"'
}

@test "17: a red folds to RED and names the suite" {
  run fold 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tred\t1\t2\t1\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n'
  printf '%s\n' "$output" | grep -q '"verdict":"red"'
  printf '%s\n' "$output" | grep -q '"failing":\["tests/b.bats"\]'
}

@test "18: an EMPTY suite cannot manufacture a green" {
  run fold 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tempty\t0\t0\t0\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n'
  printf '%s\n' "$output" | grep -q '"verdict":"cut"'
}

@test "19: a SHORT fold is a non-verdict — a dropped shard is not a green over what reported" {
  run fold 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tgreen\t2\t0\t0\t1\n'
  printf '%s\n' "$output" | grep -q '"verdict":"cut"'
  printf '%s\n' "$output" | grep -q '"suites":2'
  printf '%s\n' "$output" | grep -q '"expected":3'
}

@test "20: resolve_bats skips the live layer and picks the next bats on PATH" {
  # The measured finding this guard exists for: on the operator's box the bare name `bats` resolves
  # to ~/.claude/bin/cc-bats, an admission wrapper that CREATES $HOME/.claude/state/bats-roots.d and
  # can REFUSE admission under load. Either behaviour would enter the off-box corpus as a suite
  # outcome. $HOME is fixtured here, so the decoy sits exactly where the real one does.
  mkdir -p "$HOME/.claude/bin" "$BATS_TEST_TMPDIR/realbin"
  printf '#!/bin/bash\n' > "$HOME/.claude/bin/bats";         chmod +x "$HOME/.claude/bin/bats"
  printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/realbin/bats"; chmod +x "$BATS_TEST_TMPDIR/realbin/bats"
  # /usr/bin stays on PATH: the extractor needs sed, and stripping it would make this test fail
  # with 127 for a reason that has nothing to do with the law under test.
  run env HOME="$HOME" PATH="$HOME/.claude/bin:$BATS_TEST_TMPDIR/realbin:/usr/bin:/bin" \
      bash -c 'eval "$(sed -n "/^resolve_bats()/,/^}/p" "$1")"; resolve_bats' _ "$RUN"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/realbin/bats" ]
}

@test "21: CONTROL — with no live-layer decoy, the ordinary first-on-PATH answer is kept" {
  # Without this control test 20 would pass for a script that ALWAYS skipped the first match, or
  # that always returned the second entry — neither of which is the rule.
  mkdir -p "$BATS_TEST_TMPDIR/realbin" "$BATS_TEST_TMPDIR/otherbin"
  printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/realbin/bats";  chmod +x "$BATS_TEST_TMPDIR/realbin/bats"
  printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/otherbin/bats"; chmod +x "$BATS_TEST_TMPDIR/otherbin/bats"
  run env HOME="$HOME" PATH="$BATS_TEST_TMPDIR/realbin:$BATS_TEST_TMPDIR/otherbin:/usr/bin:/bin" \
      bash -c 'eval "$(sed -n "/^resolve_bats()/,/^}/p" "$1")"; resolve_bats' _ "$RUN"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/realbin/bats" ]
}

@test "21b: an EXPLICIT CC_OFFBOX_BATS always wins, even if it lives under the live layer" {
  mkdir -p "$HOME/.claude/bin"
  printf '#!/bin/bash\n' > "$HOME/.claude/bin/bats"; chmod +x "$HOME/.claude/bin/bats"
  run env HOME="$HOME" CC_OFFBOX_BATS="$HOME/.claude/bin/bats" PATH="/usr/bin:/bin" \
      bash -c 'eval "$(sed -n "/^resolve_bats()/,/^}/p" "$1")"; resolve_bats' _ "$RUN"
  [ "$output" = "$HOME/.claude/bin/bats" ]
}

# ── the shipped tree, and the workflow that consumes it ──────────────────────────────────────────

@test "22: the SHIPPED manifests lint clean" {
  run bash "$PART" lint
  [ "$status" -eq 0 ]
}

@test "23: both selftests are green on the shipped tree" {
  run bash "$PART" --selftest
  [ "$status" -eq 0 ]
}

@test "24: the workflow drives the SHIPPED scripts, not an inlined copy of their logic" {
  # A workflow that reimplements the fold is a second implementation of the verdict, and the two
  # drift on the first edit nobody makes twice.
  local wf="$REPO/.github/workflows/hermetic.yml"
  [ -r "$wf" ]
  grep -q 'scripts/offbox-partition.sh' "$wf"
  grep -q 'scripts/offbox-run.sh' "$wf"
  # The runner must be reached through its verbs, never bypassed with a bare `bats tests/`.
  ! grep -qE '^\s+(run:\s+)?bats\s+tests' "$wf"
}

@test "25: the exclusion manifest carries a reason for every entry it holds" {
  # An entry with no reason is an exemption nobody can re-examine — the shape this repo's
  # host-suites.manifest de-listing (151 tests excluded for a property none of them had) came from.
  # A commented reason must appear within the 6 lines above each entry.
  local mf="$REPO/scripts/offbox-excluded.manifest"
  [ -r "$mf" ]
  run python3 - "$mf" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
bad = []
for i, ln in enumerate(lines):
    s = ln.split('#', 1)[0].strip()
    if not s:
        continue
    window = [w for w in lines[max(0, i-6):i] if w.strip().startswith('#') and len(w.strip()) > 3]
    if not window:
        bad.append(s)
print('\n'.join(bad))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}

# ── THE NOTIFICATION CONTRACT (26-28) ───────────────────────────────────────────────────────────
# WHY THESE EXIST. This producer may ACQUIT or say nothing; it may never CONVICT — the file header,
# the `verdict` job's own comments, and `offbox-green-pull.sh`'s "this producer may acquit; it may
# not convict" all say so. For its first ~4 days the implementation said otherwise: not-green was
# `exit 1`, which is GitHub's error channel, so the null result was delivered to the operator as a
# failure email ~22×/day (89 failures / 2 successes in 100 scheduled runs; 96/100 since birth). The
# doctrine was right and unenforced, which is the only reason it could rot. These tests are the
# enforcement — an O(1) invariant instead of noticing the O(n)th instance.
#
# The laws are checked by one helper so a mutant can be run through the SAME code path as the
# shipped file; a control that cannot fail credits nothing.
_notification_contract() {   # $1 = workflow path → exit 0 clean, 1 findings
  python3 - "$1" "$REPO/scripts/offbox-green-pull.sh" <<'PY'
import re, sys
wf, puller = sys.argv[1], sys.argv[2]

# Split the `jobs:` mapping into per-job blocks BY INDENTATION, with no YAML library. The first
# version of this helper imported PyYAML; the GitHub macOS runner does not have it, so all three
# tests failed off-box and this suite became the single red in run 31914770411 — a contract check
# that cannot run where its subject runs is not a check. Reproduced locally by hiding the module
# (exactly 3 not-ok, matching the runner) before rewriting, so the cause was measured not guessed.
def job_blocks(lines):
    out, cur, name, in_jobs = {}, [], None, False
    for ln in lines:
        if not in_jobs:
            if re.match(r'^jobs:\s*$', ln):
                in_jobs = True
            continue
        if re.match(r'^\S', ln):          # a new top-level key ends the jobs mapping
            break
        m = re.match(r'^  ([A-Za-z_][\w-]*):\s*$', ln)
        if m:
            if name:
                out[name] = cur
            name, cur = m.group(1), []
            continue
        if name is not None:
            cur.append(ln)
    if name:
        out[name] = cur
    return out

def convicts(block):
    # Comments are skipped: the prose ABOVE a job documents the very defect being banned, and a
    # lint that reads its own rationale as a violation is unshippable.
    return any(re.match(r'^\s*exit\s+[1-9]\b', l) for l in block if not l.strip().startswith('#'))

jobs = job_blocks(open(wf).read().splitlines())
bad = []

# L1 AGREEMENT. The puller reads ONE check-run by name; the workflow must publish a job by that
# name. Two files that must agree and cannot check each other is this repo's recurring shape, so
# the name is READ from the consumer rather than restated here.
m = re.search(r'JOB_NAME="\$\{CC_OFFBOX_JOB:-([^}"]+)\}"', open(puller).read())
if not m:
    bad.append("could not read JOB_NAME out of %s — the contract's consumer half is unreadable" % puller)
else:
    name = m.group(1)
    if name not in jobs:
        bad.append("puller reads check-run %r but no such job exists in the workflow" % name)
    else:
        block = jobs[name]
        # L2 ACQUIT-ONLY. The green job must be GATED on green — if it can run when the fold is not
        # green, it publishes a success that is not one, which is a FALSE GREEN in the store.
        gate = [l for l in block if re.match(r'^\s*if:', l) and "== 'green'" in l]
        if not gate:
            bad.append("job %r is not gated on a green fold — it could mint a false green" % name)
        # L3 NO-CONVICT. Nothing on the green path may exit non-zero to mean "not green"; that is
        # the exact defect this contract exists to prevent recurring.
        if convicts(block):
            bad.append("job %r exits non-zero — 'not green' must never be spelled as a failure" % name)

# L3 again, on the fold: it runs unconditionally, so a non-zero exit there fails the RUN and emails.
if 'fold' in jobs and convicts(jobs['fold']):
    bad.append("job 'fold' exits non-zero — the fold reports, it does not convict")

print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}

@test "26: the SHIPPED workflow satisfies the notification contract" {
  run _notification_contract "$REPO/.github/workflows/hermetic.yml"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "27: CONTROL — restoring the exit-1 convict makes the contract RED" {
  # The real pre-fix defect, replayed: the green job spelled "not green" as a failing exit.
  local mut="$BATS_TEST_TMPDIR/mutant-exit1.yml"
  python3 - "$REPO/.github/workflows/hermetic.yml" "$mut" verdict exit1 <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
job, mode = sys.argv[3], sys.argv[4]
start = next(k for k, l in enumerate(lines) if re.match(r'^  %s:\s*$' % job, l))
end = len(lines)
for k in range(start + 1, len(lines)):
    if re.match(r'^  \S', lines[k]):
        end = k
        break
if mode == 'exit1':
    lines.insert(end, '          exit 1')
else:                                  # 'ungate' — delete the job's own `if:` line
    lines = [l for k, l in enumerate(lines) if not (start < k < end and re.match(r'^\s*if:', l))]
open(sys.argv[2], 'w').write("\n".join(lines) + "\n")
PY
  grep -q '^          exit 1$' "$mut"   # anchor: the mutation actually applied
  run _notification_contract "$mut"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must never be spelled as a failure"* ]]
}

@test "28: CONTROL — un-gating the green job makes the contract RED (false-green half)" {
  # The opposite failure the gate protects against: a `verdict` job that runs unconditionally would
  # report success on every tree, and the puller would stamp an off-box green for a red partition.
  local mut="$BATS_TEST_TMPDIR/mutant-ungated.yml"
  python3 - "$REPO/.github/workflows/hermetic.yml" "$mut" verdict ungate <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
job, mode = sys.argv[3], sys.argv[4]
start = next(k for k, l in enumerate(lines) if re.match(r'^  %s:\s*$' % job, l))
end = len(lines)
for k in range(start + 1, len(lines)):
    if re.match(r'^  \S', lines[k]):
        end = k
        break
if mode == 'exit1':
    lines.insert(end, '          exit 1')
else:                                  # 'ungate' — delete the job's own `if:` line
    lines = [l for k, l in enumerate(lines) if not (start < k < end and re.match(r'^\s*if:', l))]
open(sys.argv[2], 'w').write("\n".join(lines) + "\n")
PY
  # anchor: the gate is genuinely gone. Spelled `run` + status rather than `! grep`, because
  # bash exempts a `!`-negated command from errexit — the negated form is a DEAD assertion that
  # passes whether or not the mutation applied, which is precisely the vacuous-anchor failure this
  # control exists to avoid. (Caught by the land gate's dead-assertion ratchet, not by review.)
  run grep -q "== 'green'" "$mut"
  [ "$status" -ne 0 ]
  run _notification_contract "$mut"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could mint a false green"* ]]
}
