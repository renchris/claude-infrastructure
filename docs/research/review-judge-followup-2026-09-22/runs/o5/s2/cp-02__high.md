## Findings

Line numbers are counted from the file exactly as presented in the brief (line 1 = `#!/usr/bin/env bats`).

---

### 1. The CONTENT-DRIFT fixture is not `.done`-marked, so axis 1 satisfies the only filename assertion

**What** — `07-drift-activate.sh` is left un-`.done`, so axis 1 names it as a pending activation, and the test's filename grep is satisfied without the parity axis producing anything.

**Where** — lines 108–113:
```bash
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
  printf '#!/bin/bash\n# REPO\n' > "$M/07-drift-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
  printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
```
contradicting line 84:
```bash
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
```

**Why it is wrong** — With the byte-comparison broken (drift never detected), the hook still emits the axis-1 FRESH partition naming `07-drift-activate.sh`; line 112 passes off that. Line 113 is an independent substring search that a zero-count section header (`CONTENT-DRIFT (0):`) satisfies — the hook demonstrably prints headers-with-counts, see line 77. The only test for the deploy-lag class can therefore be green while the class is undetectable. There is also no `[ "$status" -eq 0 ]` here, so the test also passes if the hook exits nonzero.

---

### 2. The LIVE-ONLY fixture is not `.done`-marked either — same contamination

**What** — `12-only-live-activate.sh` is staged without a `.done` marker, so axis 1 fires and the section's stated isolation premise is false for this test.

**Where** — lines 91, 94:
```bash
  stage "12-only-live-activate.sh"
```
```bash
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
```

**Why it is wrong** — If the parity axis silently stopped classifying live-only files, the axis-1 FRESH partition would still print the filename and line 95's `grep -q 'LIVE-ONLY'` would still match a header or legend line. The test passes on axis-1 output attributed to axis 2. (The same missing marker at line 134, `stage "x-activate.sh"`, is harmless only because that test's assertion — `DID NOT RUN` — is not a string axis 1 can produce.)

---

### 3. Classification label and filename are asserted by two unrelated greps throughout

**What** — Almost every classification test asserts "label appears somewhere" and "filename appears somewhere" as separate `grep`s, which does not assert that the file was classified under that label.

**Where** — lines 94–95, 103–104, 112–113, 190–192, 240–241, 253–254, 299–300. Representative pair, lines 240–241:
```bash
  printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR'
  printf '%s' "$output" | grep -q 'landed-activate.sh'
```
and lines 190–192:
```bash
  printf '%s' "$output" | grep -q 'ROTTING'
  printf '%s' "$output" | grep -q 'FRESH'
  printf '%s' "$output" | grep -q 'b-new-activate.sh'
```

**Why it is wrong** — Output such as `UNDEPLOYED-MIRROR (0):` plus a `LIVE-ONLY: landed-activate.sh` row passes lines 240–241 while doing exactly the thing M4 exists to prevent. In the M3 test, a hook that put the fresh entry back under ROTTING passes lines 190–192 unchanged, because nothing ties `b-new-activate.sh` to the FRESH partition. The file shows the coupled form is available and used once (line 77, `'ROTTING (>24h, 1): stale-a.sh'`), so the uncoupled assertions are a deliberate-looking weakening everywhere else — notably for the FRESH half at lines 78–79.

---

### 4. M4's central negative assertion is keyed to an exact prose sentence no other test expects

**What** — The guard that is supposed to prove a committed file is never reported as "never committed" matches one exact full sentence, while the same class is matched elsewhere by the bare token `LIVE-ONLY`.

**Where** — line 242:
```bash
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```
compare lines 253 and 275:
```bash
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
```bash
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```

**Why it is wrong** — If the hook's live-only row is worded or spaced any differently (different dash, a line break, the filename on its own line, a count prefix such as `LIVE-ONLY (1):`), line 242 can never match any output, so it passes unconditionally and the defect it was written for — a trunk-committed file reported as unrecoverable — is undetected. The mismatch with lines 253/275, which assume only the short token exists, shows the long string is not the format the rest of the suite believes in.

---

### 5. Three tests consist only of absence assertions with no proof the hook ran

**What** — The M5 positive control, the M5 kill switch, and the M3 kill switch assert nothing positive and never check `$status`, so a hook that dies immediately and prints nothing passes all three.

**Where** — lines 303–307:
```bash
@test "M5 POSITIVE CONTROL: a LOADED label yields NO row (the axis can go quiet)" {
```
```bash
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```
lines 326–327:
```bash
    CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```
lines 206–209:
```bash
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_AGE_FILTER=on run "$H"
  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
```

**Why it is wrong** — If `CC_ACTIVATION_LAUNCHCTL_BIN` were ignored, misspelled, or the hook aborted on a stub it could not execute, the output is empty, the negated grep succeeds, and the test reports success. The M5 case is specifically labelled the *positive control* — the one test whose job is to show the axis is capable of going quiet *for the right reason* — and it cannot distinguish "quiet because the label is loaded" from "the hook produced no output at all."

---

### 6. The M3 kill switch never checks that the filtered-in entry is still reported

**What** — The test claims the `>24h` filter is restored "exactly" but only asserts the old headline string and the absence of the fresh entry; it never asserts that `a-old-activate.sh` is named.

**Where** — lines 204–208:
```bash
  stage "a-old-activate.sh" "$OLD"
  stage "b-new-activate.sh"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_AGE_FILTER=on run "$H"
  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
```

**Why it is wrong** — With `CC_ACTIVATION_AGE_FILTER=on`, a hook that emits the legacy headline and then names nothing at all — i.e. the kill switch silences the queue entirely rather than restoring the old filter — passes every assertion. That is the exact starvation failure the M3 banner (lines 176–181) says must never recur, now reachable through the escape hatch.

---

### 7. `mkmirror` reports success even when it built nothing

**What** — All git output and exit statuses are discarded and the function unconditionally prints the path, so callers proceed as if a checkout with a populated `origin/main` exists.

**Where** — lines 224–229:
```bash
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    mkdir -p docs/activation/pending-activation
    printf '#!/bin/bash\n# committed\n' > docs/activation/pending-activation/landed-activate.sh
    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
```

**Why it is wrong** — `|| exit 1` exits the subshell, not `mkmirror`; the `>/dev/null 2>&1` swallows failures from `git config`, `commit` (e.g. a host with commit hooks or a `commit.gpgsign` default) and `push`. If the commit or push fails there is no `origin/main` containing `landed-activate.sh`, and the M4 kill-switch test at lines 268–276 then passes vacuously: with no trunk content, `LIVE-ONLY` is reported and `UNDEPLOYED-MIRROR` is absent for reasons that have nothing to do with `CC_ACTIVATION_TRUNK_ADJUDICATE=off` — it would pass identically with adjudication on.

---

### 8. The M4 "checkout behind trunk" fixture does not build that state, and half of it is a no-op

**What** — The fixture's first two commands are undone by the next command, and the state it actually produces is a local branch *ahead* of `origin/main` by an explicit deletion commit, not a checkout that trails trunk.

**Where** — lines 233–237:
```bash
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```

**Why it is wrong** — `git reset -q --hard HEAD~1` discards the `drop` commit made on the preceding line, so `git rm` + `git commit -q -m drop` contribute nothing to the fixture. The surviving state is "the checkout's tip records a deliberate removal of the path," which is the opposite premise from deploy lag ("the checkout never received the commit that added it"). An adjudicator that reads the checkout's own history for the path, or that tests `HEAD` being an ancestor of `origin/main` to decide "behind," gets a different answer here than in production, so the test pins a verdict for a condition the code under test does not face.

---

### 9. `setup()` exports the mirror override into the `--selftest` run

**What** — `CC_ACTIVATION_MIRROR_DIR` is exported globally in `setup`, including for the selftest invocation, which the header describes as the hook's own self-contained RED-proof.

**Where** — line 15 and line 20:
```bash
  export CC_ACTIVATION_MIRROR_DIR="$Q"
```
```bash
  run "$H" --selftest
```

**Why it is wrong** — Every other test in the file depends on the hook honouring `CC_ACTIVATION_MIRROR_DIR`, so `--selftest` inherits it too and any self-check touching the parity axis is redirected at an empty bats temp directory instead of the fixtures it built for itself. Those checks then report `ok` for a premise other than the one they assert, and line 22's `-eq 18` count still holds, so the discrepancy is invisible.

---

### 10. The launchctl stub is the only oracle for the disabled/not-loaded distinction, and it models one vocabulary and one exit status

**What** — The stub only ever emits the `=> disabled` form and always exits 0, so the test proves the hook parses the stub rather than `launchctl`.

**Where** — lines 288–289:
```bash
    printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
    printf 'esac\nexit 0\n'
```
against the claim at lines 311–313:
```bash
  # `launchctl list` alone maps both onto 'absent', so the row sent the operator to `bootstrap` when
  # the answer was `enable`. The override DB prints `\"<label>\" => disabled`, never true/false —
```

**Why it is wrong** — The assertion at line 316 (`[DISABLED]`) can only fail if the hook stops matching the stub's spelling; on a host where `print-disabled` emits the `"<label>" => true` form instead, the hook silently falls back to `[NOT-LOADED]` and this test still passes, which is precisely the wrong-fix outcome (`bootstrap` instead of `enable`) the test claims to prevent. Separately, `exit 0` on line 289 means the stub cannot model `launchctl list <label>` failing for an unloaded label, so a hook probing by exit status gets "loaded" for everything — undetected by the absence-only tests at lines 307 and 327.

---

### 11. Filename regexes in `jq test()` and in the symlink path grep are matched unescaped

**What** — Filenames and the repo path are interpolated into regex/BRE contexts, so `.` matches any character.

**Where** — line 38 and line 149:
```bash
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
```
```bash
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
```

**Why it is wrong** — `test("x-activate.sh")` matches `x-activate_sh` or `x-activatexsh` as readily as the real name, and `$REPO` is inserted into a BRE unescaped, so any metacharacter in the checkout path (e.g. a directory named `rvw.jxuFYS`) loosens the match. Both only ever admit strings the assertion did not intend to accept; neither can produce a false failure, but each is a weaker check than it reads as.

---

Two things I checked and found **not** defective, since they look suspicious: the `! cmd | grep -q X || false` idiom (lines 52, 208, 242, 255, 275, 307, 327) parses as `(! pipeline) || false` and does fail the test when the pattern is found; and `for l in ; do` generated by `lcstub` with empty arguments is accepted by bash's grammar and iterates zero times.
