## Summary

Seven defects. The most consequential is a broken isolation premise in the axis‑2 block: two tests there assert a filename that the *other* axis puts in the output for free, so those assertions cannot fail even if the parity axis stops naming the file.

---

### 1. Axis‑2 fixtures are not `.done`-marked, so the filename assertions are satisfied by axis 1

**What** — Three axis‑2 tests stage a live script without a `.done` marker, contradicting the block's stated isolation premise; post‑M3 axis 1 names every un-run script regardless of age, so the axis‑2 "is the file named?" assertions pass on axis‑1 output alone.

**Where** —
- Premise, line 84: `# Fixtures are \`.done\`-MARKED throughout, so axis 1 stays silent and every finding below is`
- Line 91: `  stage "12-only-live-activate.sh"`
- Line 109: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
- Line 134: `  stage "x-activate.sh"`

**Why it is wrong** — With no `.done` file, axis 1 emits the FRESH partition listing `12-only-live-activate.sh` / `07-drift-activate.sh` / `x-activate.sh`. Line 94 (`grep -q '12-only-live-activate.sh'`) and line 112 (`grep -q '07-drift-activate.sh'`) therefore succeed on axis‑1 text. If the parity axis regressed to emitting a bare `LIVE-ONLY:` / `CONTENT-DRIFT:` header with an empty or wrong file list, both tests still go green — exactly the "borrowing another axis's quiet" failure the block comment at lines 85–87 says it fixed. Line 134's case is milder (its only assertion, `DID NOT RUN`, is axis‑2 vocabulary) but breaks the same stated invariant.

---

### 2. The symlink test's negative assertion cannot fail under the bug it names

**What** — The `~/.claude` anti-assertion is unfalsifiable, because the fixture never places the symlink anywhere that could resolve to `~/.claude`.

**Where** — lines 145 and 150:
```
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
```

**Why it is wrong** — The regression described at lines 142–143 is an un-dereferenced `BASH_SOURCE` yielding `REPO=~/.claude`. With the launcher at `$BATS_TEST_TMPDIR/linked.sh`, the un-dereferenced computation yields the *parent of the bats temp dir*, never `~/.claude`. So line 150 holds under both the fixed and the broken implementation and contributes nothing. (Line 149 does catch the bug, so the test as a whole is not vacuous — but the assertion advertised in the test title is.)

---

### 3. The M4 "never LIVE-ONLY" guard is keyed to an exact prose sentence

**What** — The anti-assertion that the file must not be reported as LIVE-ONLY matches one full rendering of the message rather than the label, so it silently stops covering the class on any wording or list change.

**Where** — line 242:
```
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```

**Why it is wrong** — Every other test in the file greps the bare label (line 275: `grep -q 'LIVE-ONLY'`). If the tool ever lists two files on that row (`...unrecoverable: landed-activate.sh, other.sh`), wraps the line, changes the em dash, or drops the trailing phrase, the pattern no longer matches and the assertion passes while the defect it pins — a committed file reported as "never committed" — is live. The test claims to cover "never 'never committed'"; it covers one exact string.

---

### 4. `--selftest` is invoked with the mirror directory overridden by `setup`

**What** — `setup` exports a mirror override into the environment of every invocation, including the selftest run, on the unproven premise that `--selftest` ignores the CLI's env overrides.

**Where** — line 15 and line 20:
```
  export CC_ACTIVATION_MIRROR_DIR="$Q"
  run "$H" --selftest
```

**Why it is wrong** — `export` makes the variable visible to `--selftest` too, and line 146 (`unset CC_ACTIVATION_MIRROR_DIR # force the deref + .git-gate path under test`) is direct evidence that the tool does honor it. If any of the 18 internal checks builds its own mirror fixture, that fixture is overridden by the empty `$Q`, and the check either fails for an environmental reason or passes against the wrong directory — while line 22 still counts 18 `ok` lines and reports success.

---

### 5. `mkmirror` swallows every git failure and returns the path unconditionally

**What** — The fixture builder discards all output and exit statuses of the git setup, then prints the checkout path as if it had been built.

**Where** — lines 224–229:
```
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
```

**Why it is wrong** — If `git push -q -u origin main` fails (no `origin/main`, hence no trunk), or the commit fails, `mkmirror` still returns `$w` and the callers at lines 233, 250 and 269 proceed to adjudicate against a repository that has no trunk ref. The M4 tests then measure the "unreadable trunk" path while claiming to measure the "exists on trunk" path; the subshell's non-zero status is the only signal and it is redirected away and never checked.

---

### 6. The M4 "checkout behind trunk" fixture leaves the checkout *ahead* of trunk

**What** — The first three commands of the M4a fixture are a round trip that cancels out, so the state produced is a local branch one deletion-commit ahead of `origin/main`, not a checkout that trails it.

**Where** — lines 234–237:
```
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```

**Why it is wrong** — `git rm` + `commit -m drop` + `reset --hard HEAD~1` returns the worktree and index exactly to `base`; the net result is identical to the kill-switch fixture at lines 270–271, which reaches the same state in two commands. The deploy-lag shape the comment describes (checkout behind trunk, fast-forwardable) is never constructed: a real lagging checkout has no local commits, whereas this one has a committed deletion of the path. If the adjudicator qualifies its `origin/main` lookup on the checkout actually trailing trunk (e.g. `merge-base --is-ancestor HEAD @{u}`), that path is never entered and the `UNDEPLOYED-MIRROR` verdict is reached, if at all, for a different reason than the one under test.

---

### 7. Exit status unchecked in the tests where a non-zero exit would break the hook contract

**What** — Several tests assert only on output text, so a hook that aborts with a non-zero status after printing its board is reported as passing.

**Where** — e.g. lines 111–113, 207–209, 239–244, 252–255, 264–265, 274–276:
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
  printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
```

**Why it is wrong** — `run` captures `$status`, and the file establishes elsewhere (lines 29, 49, 59, 65, 93, 120, 129, 137, 169) that a SessionStart invocation must exit 0 to stay fail-open. In these tests, a crash after the emit — the shape a mirror-resolution or `git` failure would produce — leaves the expected substrings in `$output` and the test goes green, reporting a broken hook as a success.
