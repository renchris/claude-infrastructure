#!/usr/bin/env bats
# hooks/lib/permission_matcher.py — ONE @test per ROW of the ground-truth tables in
# docs/research/permission-matcher-truth-2026-08-20.md, so a divergence names the row it broke.
#
# WHY ROW-SHAPED AND NOT FEATURE-SHAPED. This library is a claim about a SPECIFIC decompiled build
# (CC 2.1.220) — a port of `ALs`, `MT`, `iae`, `OTo` and `pme`. Claims about a build go stale, and a
# stale matcher fails in the direction that costs most: it reads BROADER than the harness, so a
# candidate rule looks like coverage and covers nothing. That is exactly how the 2026-08-23 sweep
# produced nine allowlist proposals an adversarial verifier refuted, two of them granting arbitrary
# code execution (docs/research/permission-prompts-2026-08-23.md §3). A feature-shaped suite would
# report "prefix matching broke"; a row-shaped one reports WHICH measured row the build no longer
# honours, which is the only form that tells the next reader where to re-probe.
#
# Harness laws, inherited from tests/cc-permission-dropped.bats: L1 every arm drives the REAL
# library (HOME is redirected and nothing here reads the operator's settings at all); L2 assertions
# key on the failure-distinct quantity — the exact verdict or the exact leaf list, so an over-wide
# and an inert matcher fail in opposite directions; L3 `[ ]` / `grep -q` only; L4 both poles, which
# on this subject means every ALLOW row is paired with the DENY row that shares its mechanism.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  LIB="$REPO/hooks/lib/permission_matcher.py"
  [ -f "$LIB" ] || skip "permission_matcher.py missing"
  RUNNER="$BATS_TEST_TMPDIR/run.py"
  cat > "$RUNNER" <<'PYRUN'
"""Exec a python body from stdin with the matcher bound as `pm`. Fixtures never touch real state."""
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("permission_matcher", os.environ["PM_LIB"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
exec(sys.stdin.read(), {"pm": mod, "__name__": "__pmtest__"})
PYRUN
}

mrun() { # python body on stdin
  PM_LIB="$LIB" python3 "$RUNNER"
}

# ── doc §1 · "The five forms in the brief" ──────────────────────────────────────────────────────

@test "five forms row 1 — Bash(git status) is exact: that literal only, and a double space DENIES" {
  run mrun <<'PY'
r = pm.parse_rule("Bash(git status)")
print(r.kind, pm.rule_matches_leaf(r, "git status"),
      pm.rule_matches_leaf(r, "git status --short"), pm.rule_matches_leaf(r, "git  status"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "exact True False False" ]
}

@test "five forms row 2 — Bash(git status:*) is a prefix: ws-normalised, space boundary, xargs" {
  run mrun <<'PY'
r = pm.parse_rule("Bash(git status:*)")
print(r.kind, *[pm.rule_matches_leaf(r, c) for c in
                ("git status", "git status --short", "git status  --short",
                 "xargs git status -s", "git statusfoo")])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "prefix True True True True False" ]
}

@test "five forms row 3 — Bash(git:*) matches git and git-space, never github-cli" {
  run mrun <<'PY'
r = pm.parse_rule("Bash(git:*)")
print(*[pm.rule_matches_leaf(r, c) for c in ("git", "git push --force", "github-cli x")])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "True True False" ]
}

@test "five forms row 4 — Bash with a lone star is a wildcard equal to bare Bash, and auto drops both" {
  run mrun <<'PY'
star, bare = pm.parse_rule("Bash(*)"), pm.parse_rule("Bash")
print(star.kind, bare.kind,
      pm.rule_matches_leaf(star, "rm -rf /"), pm.rule_matches_leaf(bare, "rm -rf /"),
      bool(pm.auto_mode_dropped("Bash(*)")), bool(pm.auto_mode_dropped("Bash")))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "wildcard bare True True True True" ]
}

@test "five forms row 5 — Bash(curl -s:*) is a literal prefix: not -sS, not --silent, not flag-last" {
  run mrun <<'PY'
r = pm.parse_rule("Bash(curl -s:*)")
print(*[pm.rule_matches_leaf(r, c) for c in
        ("curl -s https://x", "curl -sS https://x", "curl --silent https://x", "curl https://x -s")])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "True False False False" ]
}

# ── doc §2 · "Measured behaviour (probes C and D)", ruleset ["Bash(/bin/date:*)"] ────────────────
# Every row below is one line of that table. The verdict vocabulary differs by one word: the doc
# writes DENY for what the harness surfaces as a refusal, and this library reports `ask` (a leaf
# matched no rule) or `structural` (a hard gate fired before rules were consulted). Keeping those
# two apart is the whole point — only the first is fixable by writing a better rule.

@test "measured row 1 — two covered leaves joined by AND is ALLOW" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("/bin/date +%s && /bin/date -u", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 2 — the same pair joined by a semicolon is ALLOW" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("/bin/date +%s ; /bin/date -u", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 3 — the same pair joined by OR is ALLOW" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("/bin/date +%s || /bin/date -u", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 4 — the same pair joined by a pipe is ALLOW" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("/bin/date +%s | /bin/date -u", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 5 — date AND hostname refuses, and names hostname as the uncovered part" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("/bin/date +%s && /bin/hostname", rs)
print(v.outcome, "|".join(v.uncovered))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ask /bin/hostname" ]
}

@test "measured row 6 — date piped to an uncovered head refuses and names that head" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("/bin/date +%s | /usr/bin/head -1", rs)
print(v.outcome, "|".join(v.uncovered))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ask /usr/bin/head -1" ]
}

@test "measured row 7 — command substitution is structural: no allow rule of any form reaches it" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("echo $(/bin/date +%s)", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural command_substitution" ]
}

@test "measured row 8 — a subshell is structural" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("( /bin/date +%s )", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural subshell" ]
}

@test "measured row 9 — a command group is structural" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("{ /bin/date +%s; }", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural command_group" ]
}

@test "measured row 10 — a trailing background operator is structural, not even classifier-approvable" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("/bin/date +%s &", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural background" ]
}

@test "measured row 11 — bash -c is not decomposed and is refused" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("bash -c '/bin/date +%s'", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural bash_c" ]
}

@test "measured row 12 — a for loop IS decomposed: only the body leaf needs a rule" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
d = pm.split_leaves("for i in 1 2; do /bin/date; done")
print(pm.command_verdict("for i in 1 2; do /bin/date; done", rs).outcome, "|".join(d.leaves))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow /bin/date" ]
}

@test "measured row 13 — a conditional IS decomposed" {
  # The doc's verdict for this row is ALLOW, and the confounder is the doc's own: the harness has a
  # built-in read-only set that approved `true` with an EMPTY allowlist (probe B), and this library
  # deliberately does NOT consult that set in any decision path because its contents were sampled,
  # not enumerated. So the ROW's claim — the conditional is decomposed — is asserted directly, and
  # the residue is asserted to be exactly the leaf the read-only set explains.
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
d = pm.split_leaves("if true; then /bin/date; fi")
v = pm.command_verdict("if true; then /bin/date; fi", rs)
print("|".join(d.leaves), ",".join(d.structural) or "-", "|".join(v.uncovered),
      pm.is_builtin_readonly("true"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "true|/bin/date - true True" ]
}

@test "measured row 14 — a while loop IS decomposed" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
d = pm.split_leaves("while false; do /bin/date; done")
print("|".join(d.leaves), ",".join(d.structural) or "-", pm.is_builtin_readonly("false"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "false|/bin/date - True" ]
}

@test "measured row 15 — output redirection to a file is structural" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("/bin/date +%s > /tmp/permprobe/o2.txt", rs)
print(v.outcome, ",".join(v.structural))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "structural redirect_file" ]
}

@test "measured row 16 — a trailing comment does not stop the match" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("/bin/date +%s # hello", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 17 — the timeout wrapper is stripped" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("timeout 5 /bin/date +%s", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 18 — an allowlisted env prefix is stripped" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(pm.command_verdict("LC_ALL=C /bin/date +%s", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "measured row 19 — a non-allowlisted env prefix defeats the allow rule" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
v = pm.command_verdict("FOO=1 /bin/date +%s", rs)
print(v.outcome, "|".join(v.uncovered))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ask FOO=1 /bin/date +%s" ]
}

# ── doc §1 · "Normalisation applied to the command before matching" (`iae`) + §6 footguns ────────

@test "normalisation — a comment LINE is dropped before matching" {
  run mrun <<'PY'
print(pm.normalize_leaf("# just a note\n/bin/date +%s"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "/bin/date +%s" ]
}

@test "normalisation — LC_ALL=C is stripped for an ALLOW rule: it is on the 39-name allowlist" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/bin/date:*)"])
print(len(pm.ENV_ALLOWLIST), "LC_ALL" in pm.ENV_ALLOWLIST,
      pm.command_verdict("LC_ALL=C /bin/date +%s", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "39 True allow" ]
}

@test "normalisation — FOO=1 is seen past by deny and ask only, never by allow (footgun F6)" {
  # The asymmetry `v7e` ships: stripAllEnvVars is true for deny and ask, false for allow. Getting it
  # backwards makes an allow rule look broader than the harness will ever treat it — the unsafe
  # direction, and the one an ad-hoc matcher always gets wrong.
  run mrun <<'PY'
r = pm.parse_rule("Bash(rm *)")
print(pm.rule_matches_leaf(r, "FOO=bar rm -rf tmp/", "deny"),
      pm.rule_matches_leaf(r, "FOO=bar rm -rf tmp/", "ask"),
      pm.rule_matches_leaf(r, "FOO=bar rm -rf tmp/", "allow"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "True True False" ]
}

@test "normalisation — the timeout wrapper leaves with its own duration argument" {
  # Peeling `timeout` and leaving `5` behind normalises to `5 /bin/date`, which matches nothing:
  # a covered leaf silently becomes a gap, and the harvester then proposes a rule for it.
  run mrun <<'PY'
print(pm.normalize_leaf("timeout 5 /bin/date +%s"), "|",
      pm.normalize_leaf("nohup timeout -k 2 30s /bin/date"), "|",
      pm.normalize_leaf("env FOO=1 /bin/date"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "/bin/date +%s | /bin/date | env FOO=1 /bin/date" ]
}

@test "normalisation — Bash rules are case-sensitive: LS -la does not match Bash(ls colon star)" {
  run mrun <<'PY'
print(pm.rule_matches_leaf(pm.parse_rule("Bash(ls:*)"), "LS -la"),
      pm.rule_matches_leaf(pm.parse_rule("Bash(ls:*)"), "ls -la"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "False True" ]
}

@test "normalisation — an exact rule is NOT whitespace-normalised, so a double space refuses" {
  run mrun <<'PY'
rs = pm.ruleset_from_lists(allow=["Bash(/usr/bin/basename foo)"])
print(pm.command_verdict("/usr/bin/basename foo", rs).outcome,
      pm.command_verdict("/usr/bin/basename  foo", rs).outcome)
PY
  [ "$status" -eq 0 ]
  [ "$output" = "allow ask" ]
}

@test "normalisation — a wildcard rule ending in space-star also matches the bare head" {
  # `ffe`: if the built regex ends in " .*" and the pattern held exactly one star, the tail becomes
  # optional. So Bash(git status *) covers bare `git status` — and Bash(git status --short *) does
  # not cover bare `git status`, which is what keeps the rule a rule.
  run mrun <<'PY'
r = pm.parse_rule("Bash(git status *)")
print(r.kind, pm.rule_matches_leaf(r, "git status"), pm.rule_matches_leaf(r, "git status --short"),
      pm.rule_matches_leaf(pm.parse_rule("Bash(git status --short *)"), "git status"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "wildcard True True False" ]
}

@test "normalisation — a prefix rule also matches xargs prefix, but not xargs carrying flags" {
  # Footgun F14: `ALs` tries the literal string "xargs " + prefix, so an intervening `-n1` breaks it.
  run mrun <<'PY'
r = pm.parse_rule("Bash(grep:*)")
print(pm.rule_matches_leaf(r, "xargs grep p"), pm.rule_matches_leaf(r, "xargs -n1 grep p"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "True False" ]
}

# ── the two rows this port exists to pin ────────────────────────────────────────────────────────

@test "quote-aware end to end — a quoted process-substitution lookalike splits, and is not structural" {
  # hooks/lib/smart-bash-allowlist.py:split_segments refuses the whole command the moment the two
  # characters `<(` appear ANYWHERE, quotes included. Run over the real corpus in wave A that
  # pre-check shredded ordinary commands: this is a grep for a literal string, not a process
  # substitution, and no shell would expand it. Mirroring that splitter's structure without
  # inheriting its pre-check is the whole difference, so it gets its own row.
  run mrun <<'PY'
d = pm.split_leaves("grep -oE '<(script|style)' f | sort")
print(len(d.leaves), "|".join(d.leaves), ",".join(d.structural) or "-", d.kind)
real = pm.split_leaves("diff <(sort a) <(sort b)")
print(",".join(real.structural), real.kind)
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2 grep -oE '<(script|style)' f|sort - compound" ]
  [ "${lines[1]}" = "process_substitution structural" ]
}

@test "mode auto moves a broad allow rule into dropped so it covers nothing; mode default keeps it" {
  # B2-3, measured: 7 fleet allows are auto-inert and 17.3% of gap rows were over-credited through
  # them. A rule that is dropped before matching reads as coverage and covers nothing, so the mode
  # has to be part of the rule set, not a note beside it.
  run mrun <<'PY'
rules = ["Bash(python3:*)", "Bash(sort:*)"]
auto = pm.ruleset_from_lists(allow=rules, mode="auto")
dflt = pm.ruleset_from_lists(allow=rules, mode="default")
print("|".join(pm.command_verdict("python3 x.py && sort -u", auto).uncovered) or "-",
      "|".join(pm.command_verdict("python3 x.py && sort -u", dflt).uncovered) or "-",
      "|".join(r for r, _why in auto.dropped), len(dflt.dropped))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "python3 x.py - Bash(python3:*) 0" ]
}

# ── parity with bin/cc-permission-audit's PRE-LIB predicates ────────────────────────────────────
# The two predicates moved out of that tool verbatim. Its own suites (cc-permission-dropped.bats,
# cc-permission-prune.bats) still drive the TOOL and remain the regression guard for the move; these
# four arms drive the LIBRARY directly on the same fixtures, so a future edit that changes the
# predicate is caught at the library even if no tool calls it that way any more.

DROPPED_FIXTURE='rules = ["Bash(python3:*)","Bash(npm run:*)","Bash(sudo -u *)","Bash(node -e *)","Bash(*)","Bash","Agent(Explore)","Bash(kubectl exec mypod)","Bash(npm run test:*)","Bash(python -m pkg.module *)","Bash(python3 scripts/foo.py *)","Bash(git status:*)","Bash(rg:*)","Bash(envsubst:*)","Bash(evaluate:*)","Bash(shellcheck:*)","Bash(npm:*)","Bash(nodemon:*)","Bash(sudoku:*)","Bash(execa:*)","Bash(npm run-script:*)","Read(//tmp/fixture/**)"]'

@test "parity — auto_mode_dropped names exactly 8 of the 22-entry fixture, each by its own branch" {
  run mrun <<PY
$DROPPED_FIXTURE
hits = [(r, pm.auto_mode_dropped(r)) for r in rules]
hits = [(r, w) for r, w in hits if w]
print(len(hits), len(rules))
for r, w in hits:
    print(r, "::", w)
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "8 22" ]
  echo "$output" | grep -q 'Bash(python3:\*) :: .*dangerous-command list'
  echo "$output" | grep -q 'Bash(npm run:\*) :: .*dangerous-command list'
  echo "$output" | grep -q 'Bash(sudo -u \*) :: .*flag form'
  echo "$output" | grep -q 'Bash(node -e \*) :: .*flag form'
  echo "$output" | grep -q 'Bash(\*) :: .*bare/wildcard Bash form'
  echo "$output" | grep -q 'Bash :: .*empty-content form'
  echo "$output" | grep -q 'Agent(Explore) :: .*every Agent allow rule'
  echo "$output" | grep -q 'Bash(kubectl exec mypod) :: .*dropped-verb list'
}

@test "parity — auto_mode_dropped clears every documented prefix-confusion survivor" {
  # The false positives the substring grep this predicate replaced would produce (struck from the
  # truth doc's DO #8). Each begins with a listed command's LETTERS and is a different command;
  # `_sn` keys on the whole token, so the boundary is what makes a match, not the prefix.
  run mrun <<PY
$DROPPED_FIXTURE
survivors = [r for r in rules if not pm.auto_mode_dropped(r)]
print("|".join(survivors))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "Bash(npm run test:*)|Bash(python -m pkg.module *)|Bash(python3 scripts/foo.py *)|Bash(git status:*)|Bash(rg:*)|Bash(envsubst:*)|Bash(evaluate:*)|Bash(shellcheck:*)|Bash(npm:*)|Bash(nodemon:*)|Bash(sudoku:*)|Bash(execa:*)|Bash(npm run-script:*)|Read(//tmp/fixture/**)" ]
}

@test "parity — dead_entries removes the shadowed entry and keeps the auto-dropped one" {
  # The "two axes are independent" fixture from tests/cc-permission-dropped.bats: redundancy is
  # semantics-preserving and gets removed; an auto-mode drop is undone outside auto mode and stays.
  run mrun <<'PY'
allow = ["Bash(git:*)", "Bash(git -C /tmp/x status)", "Bash(sudo:*)"]
survivors, dead = pm.dead_entries(allow)
print("|".join(survivors), "||", "|".join("%s::%s" % (r, why) for _i, r, why in dead))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "Bash(git:*)|Bash(sudo:*) || Bash(git -C /tmp/x status)::shadowed by Bash(git:*)" ]
}

@test "parity — dead_entries finds nothing redundant in the 22-entry drop fixture" {
  # The other pole, and the reason the two axes are separate sections in the report: every one of
  # those 22 entries is live under `default` mode, so a prune that touched them would be a real
  # behaviour change wearing a tidy-up's clothes.
  run mrun <<PY
$DROPPED_FIXTURE
survivors, dead = pm.dead_entries(rules)
print(len(survivors), len(dead))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "22 0" ]
}

@test "the library imports and self-tests under the interpreter launchd will use" {
  # PERMISSION_HARVEST.md §9: launchd's PATH resolves python3 to Apple's 3.9.6 while the interactive
  # PATH resolves it to 3.11. A 3.10-only construct compiles green all day on the desk and dies once
  # a week at 04:17 with nobody reading the log.
  [ -x /usr/bin/python3 ] || skip "Apple python3 absent"
  run /usr/bin/python3 -m py_compile "$LIB"
  [ "$status" -eq 0 ]
  run /usr/bin/python3 "$LIB" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'permission_matcher selftest:'
}

# ── dead_entries · the `literal == base` arm (added 2026-09-09) ─────────────────────────────────
#
# The predicate proved shadowing ONLY through `literal.startswith(base + " ")`, and the omission was
# arithmetic rather than cosmetic: `{X, X <args>}` is the commonest acceptance cluster on this box,
# its 2-token head is `X`, so the minted prefix `Bash(X:*)` retired `X <args>` and left `Bash(X)`
# behind — the allow list no shorter (+1 prefix, −1 entry) and the grant strictly wider. Measured on
# the real 30-day proposal, 3 of 7 consolidation prefixes retired a NET of zero this way.
#
# Both arms rest on ONE line of matcher (`rule_matches_leaf`'s prefix arm, `c == g or c.startswith(
# g + " ")`), so the control below asserts that line directly: if the equality arm here is ever
# deleted again, the second assertion says why it was never "the matcher's business" to decide.

@test "dead_entries — a literal EQUAL to a prefix base is dead, exactly like a longer one" {
  run mrun <<'PY'
allow = ["Bash(sysctl hw.memsize hw.ncpu)", "Bash(sysctl hw.memsize)", "Bash(sysctl hw.memsize:*)"]
survivors, dead = pm.dead_entries(allow)
print("|".join(survivors))
print(";".join("%s::%s" % (r, why) for _i, r, why in dead))
# the matcher line both arms rest on — the prefix rule DOES match its own base as a leaf
print(pm.rule_matches_leaf(pm.parse_rule("Bash(sysctl hw.memsize:*)"), "sysctl hw.memsize"))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Bash(sysctl hw.memsize:*)" ]
  [ "${lines[1]}" = "Bash(sysctl hw.memsize hw.ncpu)::shadowed by Bash(sysctl hw.memsize:*);Bash(sysctl hw.memsize)::shadowed by Bash(sysctl hw.memsize:*)" ]
  [ "${lines[2]}" = "True" ]
}

@test "dead_entries — the equality arm keys on the WHOLE base, never a character prefix of it" {
  # The failure direction the new arm could introduce: killing a literal a prefix does NOT match.
  # `Bash(sysctl hw.mem:*)` matches `sysctl hw.mem` and `sysctl hw.mem <x>`, never `sysctl
  # hw.memsize` — one token, not one substring. A cross-TOOL base must not reach it either.
  run mrun <<'PY'
allow = ["Bash(sysctl hw.memsize)", "Bash(sysctl hw.mem:*)", "Read(sysctl hw.memsize)", "Read(sysctl hw.memsize:*)"]
survivors, dead = pm.dead_entries(allow)
print("|".join(survivors))
print(pm.rule_matches_leaf(pm.parse_rule("Bash(sysctl hw.mem:*)"), "sysctl hw.memsize"))
PY
  [ "$status" -eq 0 ]
  # Bash(sysctl hw.memsize) survives (its own tool's base does not match it); Read(...) does not
  # (its own tool's prefix base is equal), which is the same rule applied to a different tool.
  [ "${lines[0]}" = "Bash(sysctl hw.memsize)|Bash(sysctl hw.mem:*)|Read(sysctl hw.memsize:*)" ]
  [ "${lines[1]}" = "False" ]
}

# ── discovery · the 229.6 s walk (2026-09-09) ───────────────────────────────────────────────────
#
# `discover_settings` used to `os.walk` each root to depth 5. `~/Development/.worktrees` holds 222
# full checkouts and `.worktrees` was not in WALK_SKIP, so the harvester's FIRST pipeline step stat'd
# hundreds of thousands of paths: 229.6 s wall / 2.4 s user for 161 files, and the whole tool hit
# rc 124 at 241 s even with an empty corpus, empty transcripts and a 1-day window. Both arms below
# exist because the file list alone cannot see this: the walk returned the RIGHT answer, slowly.

@test "discovery finds every real shape a bounded walk finds — including the four the first draft missed" {
  D="$BATS_TEST_TMPDIR/dev"
  # The five shapes MEASURED under the real ~/Development (161 files), one fixture each.
  mkdir -p "$D/proj-a/.claude" "$D/cloud-agent/knowledge-base/.claude" \
           "$D/_worktrees/wt-underscore/.claude" "$D/.worktrees/wt-flat/.claude" \
           "$D/.worktrees/drain/lane-infra/.claude" "$D/proj-a/deep/deeper/evendeeper/.claude"
  for p in proj-a cloud-agent/knowledge-base _worktrees/wt-underscore .worktrees/wt-flat \
           .worktrees/drain/lane-infra proj-a/deep/deeper/evendeeper; do
    echo '{}' > "$D/$p/.claude/settings.json"
  done
  echo '{}' > "$D/proj-a/.claude/settings.local.json"
  run mrun <<PY
rows = pm.discover_settings(roots=("$D",))
for p, s in rows:
    print(s, p.replace("$D/", ""))
PY
  [ "$status" -eq 0 ]
  # `*` never matches a leading dot: without the LITERAL .worktrees segments these two vanish.
  echo "$output" | grep -q '^worktree \.worktrees/wt-flat/\.claude/settings\.json$'
  echo "$output" | grep -q '^worktree \.worktrees/drain/lane-infra/\.claude/settings\.json$'
  # `_worktrees` (underscore) and a two-level project ride the plain `*/*` shape.
  echo "$output" | grep -q '^project _worktrees/wt-underscore/\.claude/settings\.json$'
  echo "$output" | grep -q '^project cloud-agent/knowledge-base/\.claude/settings\.json$'
  echo "$output" | grep -q '^project proj-a/\.claude/settings\.json$'
  echo "$output" | grep -q '^project proj-a/\.claude/settings\.local\.json$'
  # 6 shapes + the second name = 7 rows; the 4-levels-down decoy is BEYOND the shapes and is the
  # honest residue of the trade (the walk reached it at depth 5). Naming it here is what keeps the
  # residue visible instead of discovered later as a silent absence.
  [ "$(echo "$output" | grep -c .)" -eq 6 ]
  echo "$output" | grep -qv 'evendeeper' || true
  ! echo "$output" | grep -q 'evendeeper'
}

@test "discovery does not descend a checkout: os.walk is never called, and the same tree costs 5x to walk" {
  D="$BATS_TEST_TMPDIR/wtdev"
  # `_worktrees` (underscore) on purpose: it is NOT in WALK_SKIP, so walk=True still finds the same
  # 25 files and the two paths are comparable. The literal `.worktrees` has its own arm below — a
  # skipped directory would make walk=True find ZERO and prove nothing about cost.
  python3 - "$D" <<'PY'
import os, sys
root = sys.argv[1]
for w in range(25):                       # 25 checkouts x 64 leaf dirs = 1,600 dirs to walk
    wt = os.path.join(root, "_worktrees", "wt%02d" % w)
    os.makedirs(os.path.join(wt, ".claude"), exist_ok=True)
    open(os.path.join(wt, ".claude", "settings.json"), "w").write("{}")
    for a in range(8):
        for b in range(8):
            os.makedirs(os.path.join(wt, "src", "d%d" % a, "e%d" % b), exist_ok=True)
PY
  run mrun <<PY
import os, time
calls = []
real_walk = os.walk
def counting_walk(*a, **k):
    calls.append(a[0] if a else "")
    return real_walk(*a, **k)
os.walk = counting_walk
t0 = time.time(); rows = pm.discover_settings(roots=("$D",)); fast = time.time() - t0
n_glob_walks = len(calls)
calls[:] = []
t0 = time.time(); legacy = pm.discover_settings(roots=("$D",), walk=True); slow = time.time() - t0
print(len(rows), len(legacy), n_glob_walks, len(calls) > 0)
print("%.4f %.4f" % (fast, slow))
PY
  [ "$status" -eq 0 ]
  # Same 25 files either way; the default path calls os.walk ZERO times, walk=True calls it.
  [ "${lines[0]}" = "25 25 0 True" ]
  fast="$(echo "${lines[1]}" | cut -d' ' -f1)"
  slow="$(echo "${lines[1]}" | cut -d' ' -f2)"
  # The wall-time bound the incident asks for: absolute, and RELATIVE so it cannot rot with the box.
  awk -v f="$fast" 'BEGIN{exit !(f < 2.0)}'
  awk -v f="$fast" -v s="$slow" 'BEGIN{exit !(s > f * 5)}'
}

@test "the legacy walk is bounded too: .worktrees is in WALK_SKIP, so walk=True cannot enter a checkout" {
  D="$BATS_TEST_TMPDIR/skipdev"
  mkdir -p "$D/.worktrees/wt-a/.claude" "$D/proj/.claude"
  echo '{}' > "$D/.worktrees/wt-a/.claude/settings.json"
  echo '{}' > "$D/proj/.claude/settings.json"
  run mrun <<PY
print(".worktrees" in pm.WALK_SKIP)
print(sorted(p.replace("$D/", "") for p, _ in pm.discover_settings(roots=("$D",), walk=True)))
print(sorted(p.replace("$D/", "") for p, _ in pm.discover_settings(roots=("$D",))))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "True" ]
  # walk=True is the AUDIT population and now stops at the checkout boundary...
  [ "${lines[1]}" = "['proj/.claude/settings.json']" ]
  # ...while the harvester's default still reaches it, because a worktree file is EVIDENCE.
  [ "${lines[2]}" = "['.worktrees/wt-a/.claude/settings.json', 'proj/.claude/settings.json']" ]
}

# ── ACE_CLASS · the two transcriptions of one list (2026-09-09) ──────────────────────────────────
#
# ACE_VERBS and DROP_CMDS are both TRANSCRIPTIONS of the same decompiled reading, and they had
# diverged: `bun` reached ACE_VERBS, `npm`/`yarn`/`pnpm` did not, while DROP_CMDS carried
# `npm run`/`yarn run`/`pnpm run`/`bun run`. MEASURED consequence — `Bash(npm:*)` passed all eleven
# gates on an empty collision set and reached a FLEET proposal, matching `npm exec`, `npm x`,
# `npm install` (registry lifecycle scripts) and `npm run <anything>`.

@test "every DROP_CMDS leading token is refused by ACE or ARG_EXEC — the divergence that let Bash(npm:*) through" {
  run mrun <<'PY'
# The claim is not "ACE contains them all" — `ssh` is DROP_CMDS and is refused by ARG_EXEC instead
# (`-o ProxyCommand`), which is the right gate for it. The claim is that NO entry of CC's own
# dangerous-command list can be minted as a bare prefix rule by this tool. `npm`/`yarn`/`pnpm`
# failed exactly this, on both gates, for as long as the two lists disagreed.
missing = [v for v in sorted({e.split()[0] for e in pm.DROP_CMDS})
           if not pm.ace_reason(v) and not pm.arg_exec_reason(v)]
print("MISSING:" + ",".join(missing))
# And the sub-verb spelling the list actually names must be refused too, not just the bare verb.
sub = [e for e in pm.DROP_CMDS if " " in e
       if not pm.ace_reason(e) and not pm.arg_exec_reason(e)]
print("SUBMISSING:" + ",".join(sub))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "MISSING:" ]
  [ "${lines[1]}" = "SUBMISSING:" ]
}

@test "the package-manager family is ACE at the bare verb AND at a sub-verb head, exactly like bun" {
  run mrun <<'PY'
for head in ("npm", "yarn", "pnpm", "bun", "npm run", "pnpm lint", "yarn build"):
    print(head, "|", "REFUSE" if pm.ace_reason(head) else "pass")
PY
  [ "$status" -eq 0 ]
  # Every line refuses: ACE keys on the head's FIRST token, and `pnpm lint` runs whatever
  # package.json calls "lint" — code that changes when the repo does.
  ! echo "$output" | grep -q '| pass' || false
  [ "$(echo "$output" | grep -c '| REFUSE')" -eq 7 ]
}

@test "the shell-escape class is refused, and an ordinary read-only verb still passes" {
  run mrun <<'PY'
refuse = ("make", "rake", "gem", "pip3", "brew", "cargo", "go", "gradle", "mvn", "just",
          "ansible", "terraform", "vim", "less", "man", "ed", "nc", "socat", "tmux", "screen",
          "script", "expect", "gdb", "lldb", "sqlite3", "ssh-keygen", "ninja", "pipx")
allow = ("gh", "git", "ls", "sysctl", "plutil", "dig", "sips", "kubectl", "aws", "rg", "jq")
print("LEAKED:" + ",".join(v for v in refuse if not pm.ace_reason(v)))
print("OVERBLOCKED:" + ",".join(v for v in allow if pm.ace_reason(v)))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "LEAKED:" ]
  # The pole that keeps the list from growing into everything: a verb whose arguments are data,
  # not code, must still reach the other ten gates.
  [ "${lines[1]}" = "OVERBLOCKED:" ]
}

# ── doc §2 · the sixth hard gate, `too_long` ────────────────────────────────────────────────────
#
# Truth doc §2 lists six hard gates in `sW_`; five are asserted in this file or in
# tests/cc-permission-harvest.bats (`structural.by_kind`). `too_long` was asserted by NOTHING, and
# this diff is what first makes it REACHABLE: hooks/cc-permission-beacon.sh raised
# CC_PERMARCHIVE_MAXLEN 3500 → 12000, so until now every command over 3,500 chars arrived at the
# harvester already `truncated` and the 10,000-char branch could not execute. MEASURED over the live
# corpus (246,920 anchored records): 428 commands exceed 10,000 chars and 80 land in the newly
# reachable 10,000 < len ≤ 12,000 window. A regression here sends those rows out of STRUCTURAL and
# into `rule_gap` — the count inflation the whole design exists to prevent.

@test "hard gate — a command longer than 10,000 characters is structural, unsplit, and named too_long" {
  run mrun <<'PY'
d = pm.split_leaves("x" * (pm.MAX_COMMAND_CHARS + 1))
print(d.kind, d.structural, d.too_long, len(d.leaves), len(d.leaves[0]))
PY
  [ "$status" -eq 0 ]
  # `MT` returns [e] — the command is NOT decomposed, so no leaf of it can be matched by any rule.
  [ "$output" = "structural ['too_long'] True 1 10001" ]
}

@test "hard gate — the negative pole at exactly 10,000 characters decomposes normally" {
  run mrun <<'PY'
tail = " && echo done"
cmd = "x" * (pm.MAX_COMMAND_CHARS - len(tail)) + tail
d = pm.split_leaves(cmd)
print(len(cmd), d.kind, d.structural, d.too_long, len(d.leaves), d.leaves[-1])
PY
  [ "$status" -eq 0 ]
  # The bound is `>`, not `>=`: at the cap itself the splitter still runs, so a regression that
  # moved the comparison one character either way is visible here rather than in a bucket count.
  [ "$output" = "10000 compound [] False 2 echo done" ]
}
