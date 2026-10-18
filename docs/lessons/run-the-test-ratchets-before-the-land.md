# A green suite run does not clear the land gate's test ratchets — run them on the changed .bats first

**The rule.** Before `/ship` of a change that adds or edits `.bats` suites, run the land gate's test
ratchets on those files yourself; they are seconds, and the gate reports them one per land cycle:

```
bash scripts/test-afunix-path-lint.sh
bash scripts/test-hermeticity-lint.sh
for f in <changed .bats>; do python3 scripts/bats-assert-liveness-fix.py "$f"; shellcheck "$f"; done
```

**Why.** On 2026-10-18 (lr-inplace-immediacy, session 74ba67f2) teammate-built suites passed every
run (`1..N`, 0 not ok) and still turned four land attempts RED, one ratchet each, at roughly 45-90 min
of gate a cycle under load ~200:

1. AF_UNIX absolute bind: `s.bind(sys.argv[1])` in `handoff-recycle-kitty-precheck.bats`, though the
   fixture `cd`'d first and passed a basename. The lint is static and wants `os.chdir(d)` + `bind(b)`
   inside the Python itself.
2. Dead assertion: `[ a ] && [ b ] || { echo; false; }`. `bats-assert-liveness-fix.py` DECLINED it
   (rc 2), so the fix was a hand split into two `[ x ] || { …; false; }` lines.
3. Test hermeticity: a new suite left `HANDOFF_ACCOUNT_SWEEP_STAMP`, `CC_HEAL_LOCK_PREFIX` (absolute
   /tmp defaults) and `CC_ACCOUNTS_BIN` (a bare name off PATH) unpinned; `$HOME` fixturing does not
   redirect those. Pin each to `$BATS_TEST_TMPDIR/...` in `setup()`.
4. `.bats` shellcheck: SC2034 on an unused variable in a new helper. Only lines the land wrote block;
   pre-existing SC2314 notes that merely shifted are advisory.

A suite run exercises behavior; these ratchets read the TEXT, so a green run says nothing about them.
`scripts/ship-land.sh --precheck` runs the same arms, but it also re-runs the slow statics (shellcheck
of a ~19K-line script took 87 min at 3% CPU that day), so the four lints alone are the fast check.

**How to apply.** Put the four commands in every code-writing teammate brief that adds a suite, and run
them on the merged tree before the first `/ship`.
