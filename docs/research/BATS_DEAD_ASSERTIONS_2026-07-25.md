# bats dead assertions — census, mechanism, fix, ratchet

**Date:** 2026-07-25 · **Backlog item:** `94edb2fa9f14` · **Project:** claude-infrastructure
**Detector:** `scripts/bats-assert-liveness.py` · **Fixer:** `scripts/bats-assert-liveness-fix.py`
**Ratchet:** `tests/bats-assert-liveness.bats`

A **dead assertion** is one whose failure cannot reach its test's exit status. It is evaluated,
its false result is discarded, and the test reports `ok`. The suite looks green while asserting
nothing. 226 of them were live in this repo across 51 of 124 files.

This doc is the SSOT for the mechanism and for what was actually measured. Every liveness claim
below was derived by running `bash`/`bats` in this worktree — none is inherited.

---

## 1. Mechanism — three errexit exemptions, plus position

bats runs each test body under `set -eET` (`bats-exec-test:2`), so a failing command normally
aborts the test. But POSIX requires `-e` to be **ignored** for a command whose status is
inverted with `!`, and for any command of an AND-OR list **other than the last**. Bash also
exempts its own compound-command keywords. The result: for three construct families, the *only*
thing that still fails a test is being the body's **final** command.

Measured grid (`bash -ec '<form>'$'\nechoR'` — DEAD = execution continued past the false form).
Both `bash` on PATH and `/bin/bash` here are **3.2.57**, the macOS system bash; no newer bash is
installed, so this is the behaviour the suite actually runs under:

| Form | Verdict | Why |
|---|---|---|
| `[[ 1 -eq 2 ]]` | **DEAD** | `[[` is a shell **keyword** (compound command) — exempt |
| `[[ x == y ]]`, `[[ x =~ ^y ]]`, `[[ -z x ]]` | **DEAD** | same |
| `(( 0 ))`, `(( 1 == 2 ))` | **DEAD** | arithmetic compound command — exempt |
| `! true`, `! [[ x ]]`, `! [ x ]` | **DEAD** | status inverted with `!` — exempt |
| `[ 1 -eq 2 ]` | live | `[` is a **builtin** — an ordinary simple command |
| `test 1 -eq 2` | live | builtin |
| `false`, `echo x \| grep -q y` | live | simple command / pipeline |
| `[[ 1 -eq 2 ]] \|\| false` | live | list's last element is `false`, un-negated |
| `! true \|\| false` | live | same |
| `[ 1 -eq 1 ] && [ 1 -eq 2 ]` | live | failing element **is** last |
| `[ 1 -eq 2 ] && echo hi` | **DEAD** | failing element is **not** last — exempt |
| `false && echo hi` | **DEAD** | same — holds for *any* left-hand command |
| `[[ 1 -eq 1 ]] \|\| [[ 1 -eq 2 ]]` | **DEAD** | last element is a keyword |
| `{ [[ 1 -eq 2 ]]; }` | **DEAD** | group is not a separate command |
| `( [[ 1 -eq 2 ]] )` | live | subshell's status propagates as a simple command |
| `[ -n "$x" ] && [ -f "$x" ] \|\| exit 1` | live | trailing `\|\| exit 1` catches every path |
| `[ -n "$x" ] && [ -f "$x" ] \|\| echo benign` | **DEAD** | benign handler swallows the failure |

**The load-bearing asymmetry:** `[[ ]]` dies where `[ ]` survives, because one is a keyword and
the other a builtin. That is invisible at the line level and is why the census needed an analyzer
rather than a grep.

### The `&&` class nobody was looking for

`A && B` in non-final position discards A's failure for **any** A — `false && echo hi` and
`[ 1 -eq 2 ] && echo hi` are both dead. This is a *third* silent class, independent of `[[ ]]`
and `!`, and it was absent from the original survey. 6 live instances were found.

### Why shellcheck is not the detector

shellcheck does not flag `[[ ]]` or `(( ))` deadness at all — there is no such check; the
construct is perfectly valid shell, and its deadness depends on where it sits in the enclosing
block. `SC2251` addresses only some `!` uses. Any grep- or shellcheck-shaped survey therefore
under-counts by construction. The detector must be a **block-position analyzer**, which is what
`scripts/bats-assert-liveness.py` is.

---

## 2. Census (derived 2026-07-25, this worktree)

**226 dead assertions across 51 of 124 test files** (1726 `@test` blocks total).

| Class | Count | Shape |
|---|---:|---|
| `cond-keyword` | 131 | non-final `[[ ... ]]` |
| `negation` | 89 | non-final `! cmd` |
| `and-absorbed` | 6 | non-final `assertion && ...` |

Top files:

| Count | File | What was silently unasserted |
|---:|---|---|
| 31 | `cc-reaper.bats` | every `! td_called` — "this pane was **not** torn down" |
| 20 | `handoff-teardown-marker.bats` | teardown-marker attribution |
| 18 | `claude-accounts-core.bats` | `[ "$status" -eq 0 ] && [[ "$output" == *OK* ]]` — both halves dead |
| 16 | `claude-kimi.bats` | launcher/endpoint assertions |
| 14 | `teammate-auto-shutdown.bats` | shutdown-path assertions |
| 12 | `lr-select.bats` | limit-recover selection |
| 8 | `cc-teardown.bats` | teardown safety |

The `cc-reaper.bats` block is the sharpest risk in the repo: 31 assertions of the form
`! td_called` / `! notified`, each asserting that a **pane was not killed** or an operator was
not paged. Dead, they cannot fail — a regression that tears down a live pane on a dry run would
have landed green.

### Corrections to the handed-down figures

The backlog item's numbers came from a survey whose doc was never written. Re-derived:

| Claim | Handed down | Measured | Note |
|---|---:|---:|---|
| total | 212 | **226** | |
| files | 51 | **51** | agrees |
| `[[ ]]` | 123 | **131** | |
| bare-`!` | 89 | **89** | agrees |
| `&&`-absorbed | — | **6** | class absent from the survey |
| `cc-reaper.bats` | 31 | **31** | agrees |
| `handoff-teardown-marker.bats` | 19 | **20** | |
| `cc-notify.bats` | 17 | **0** | **already fixed** — see below |

`cc-notify.bats` was reported as the third-worst file and is in fact **clean**: it already
applies `|| false` to every `[[ ]]`, and its header comment (line 9) documents this exact bug —
*"`|| false` on EVERY bare `[[ ]]` — bats does not trap a bare `[[ ]]` failure mid-body"*. The
fix idiom adopted below is therefore this repo's own prior art, not an import.

---

## 3. The fix — a uniform `|| false`, and why the two obvious fixes are wrong

**Applied fix:** append ` || false` to the offending statement. For a non-final statement `S`:

- `S` succeeds → `||` short-circuits → status 0, body continues (behaviour unchanged)
- `S` fails → `false` runs as the list's **last**, un-negated element → errexit applies → the
  test fails, as was intended all along

One token, no semantic change, `$output`/`$status` untouched, and idempotent (a statement already
ending in `|| false` is never reported, so never re-touched).

### `[[ ]]` → `[ ]` would have broken 98% of the call sites

Of the 131 `[[ ]]` findings, **127 use glob matching** (`== *"text"*`) and **2 use regex**
(`=~`) — 129 of 131, or 98%. POSIX `[ ]` can express neither. `[ "$output" == *"delivered"* ]` is a
*literal* comparison against the string `*"delivered"*`, so the rewrite does not weaken the
assertion, it silently replaces it with a different, near-always-false one (and leaves an
unquoted `*` exposed to pathname expansion). Verified:

```
output="delivered to inbox"
[  "$output" == *"delivered"* ]   → NO MATCH   ← rewrite breaks it
[[ "$output" == *"delivered"* ]]  → MATCH      ← correct
```

### `! cmd` → `run cmd; [ "$status" -ne 0 ]` clobbers `$output`

These negations routinely sit **between** a `run` and a later assertion on that run's output.
`run` overwrites `$output`/`$status`, so the rewrite breaks the *following* assertion. The
canonical shape, `cc-reaper.bats:167-169`:

```bash
run "$R" sweep
[ "$status" -eq 0 ]
! td_called                              # ← the dead assertion
echo "$output" | grep -q WOULD-REAP      # ← depends on the ORIGINAL run
```

Verified with a two-test fixture: the `run`+status rewrite **fails** the following `$output`
assertion; `! td_called || false` **passes** it. Hence `|| false` for negations too.

---

## 4. How the detector was validated

Deadness is not taken on faith anywhere: **bats itself is the oracle.** Each fixture asserts
something false, so a fixture bats reports `ok` proves the assertion was discarded (dead), and
one bats reports `not ok` proves it was honoured (live). The analyzer's verdict is then compared
against that.

- **Agreement on the form grid** — analyzer flagged exactly the forms bats passed, and stayed
  silent on every form bats failed. Zero false positives, zero false negatives.
- **Both controls asserted every run** — a guaranteed-false body must fail, a true body must
  pass. Without these the oracle could be vacuous.
- **RED-proof of the fix** — a dead assertion passes; after the fixer it fails; the analyzer then
  reports zero.
- **Fixtures built with `printf`, never a heredoc.** bats' preprocessor strips `@test` inside a
  heredoc, which yields a vacuously green suite (prior incident; see the `fixture-shape-parity`
  memory).

Four analyzer defects were found and fixed *by* this validation, all in the false-all-clear
direction that matters:

1. `for ((i=0; i<n; i++))` read as an arithmetic assertion → loop headers exempted.
2. `[[ A && B ]]` split as an AND-OR list → `[[ ]]` depth now tracked, so it is one element.
3. **Quoted bats source analyzed as code.** A test that builds a fixture by passing source as
   arguments (`mkblock "$f" '[[ 1 -eq 2 ]]'`) tripped false positives, and a quoted `<<EOF`
   started a heredoc skip that never terminated — **silently swallowing the rest of the block**.
   Construct detection is now quote-aware (`strip_quoted`).
4. `A && B || exit 1` reported as absorbed, when the trailing handler catches every failure
   path → a `||` handler that reliably fails (`false`/`exit N`/`return N`) now clears the
   finding, while a *benign* handler (`|| echo missing`) still reports, because it swallows.

Finality is judged **conservatively**: live only when provably the last top-level statement of
the body. Anything nested in `if`/`while`/`for`/`case`/`{ }` is reported, since reachability is
data-dependent. A false report costs one mechanical edit; a false all-clear is absorbed forever.

---

## 5. The ratchet

`tests/bats-assert-liveness.bats` re-derives all of the above on every gate run: the class
grid against the bats oracle, both controls, the live forms that must stay unflagged, the
fixer's revive/idempotence/`$output` properties, and a final **RATCHET** case asserting the real
suite is at zero. Because the commit gate runs `bats tests/`, a reintroduced dead assertion now
fails the gate with the exact fix command in the failure output.

Re-run by hand:

```bash
python3 scripts/bats-assert-liveness.py --summary      # census; exit 1 if any
python3 scripts/bats-assert-liveness-fix.py --dry-run  # what would change
python3 scripts/bats-assert-liveness-fix.py            # apply, then re-verify at 0
```

## 6. What the revival exposed — two assertions that were never true

Reviving 226 assertions turned **two** tests red. Neither was a product bug: both were
assertions that could not have passed as written, and both were unfalsifiable while dead.

### 6a. A fixture that never matched — `tests/lr-select.bats`

*"uncommitted work annotates the group but does NOT pick the winner"*.

The assertion `[[ "$output" == *"322 uncommitted"* ]]` had **never once matched**. Root cause
is a `/var` vs `/private/var` path-resolution skew in the test's own `git` stub:

- `$BATS_TEST_TMPDIR` is `/var/folders/…`, so the fixture recorded its dirty-count key there.
- The producer groups candidates on the **physically resolved** `/private/var/folders/…`.
- The stub matched keys by exact string (`awk '$1==c'`), so the lookup silently found nothing,
  `dirty_count()` returned 0, and no annotation was ever emitted.

Real `git -C` accepts either spelling, so **the product was never broken** — this was pure
fixture skew. It survived because the one assertion that would have caught it was a non-final
`[[ ]]`, i.e. dead. Fixed by comparing keys physically (`pwd -P`) in the stub, which also
makes every future dirty-count fixture robust to the same skew.

This is another instance of the fixture-shape-parity class: *a fixture is a contract claim
about the real producer's shape, and a dead assertion means nothing ever checked the claim.*
The assertion is now mutation-proved load-bearing — substituting a wrong count fails the test,
the correct count passes.

### 6b. An assertion that could not express its own claim — `tests/ship-land.bats`

*"T-P9-7 kill-switch: SHIP_LAND_VERIFY_RETRIES=0 → single-shot exit 8, no auto-retry"*
asserted `! echo "$output" | grep -qi "auto-retry"`. With retries disabled, ship-land
correctly reports `post-push CONTENT-VERIFY FAILED after 0 auto-retry attempt(s)` — a
sentence the bare substring test matches. So the assertion could never distinguish "no retry
happened" from "a retry happened"; it passed only because it was dead. Retargeted at the
per-attempt marker (`auto-retry <n>/<max>`, ship-land.sh:507) plus a positive check that the
reported count is 0 — strictly stronger than the original intent.

The two failures are different species, and both matter:

| | `lr-select` | `ship-land` |
|---|---|---|
| Wrong thing | the **fixture** (path-resolution skew) | the **assertion** (imprecise predicate) |
| Product correct? | yes | yes |
| Could it ever pass? | no — key never matched | no — substring always present |

That 224 of 226 revived assertions passed is the reassuring half of the result: the suite's
*intent* was overwhelmingly correct; it simply was not being enforced. The unreassuring half
is that both failures were *permanently* false, not flaky — evidence that a dead assertion is
not merely unenforced but actively rots, because nothing ever contradicts it.

### Collateral: a pre-existing HANG that blocked the gate

Not caused by the revival — found by running the suites it touched, and fixed here because a
hanging suite blocks every land whose diff selects it (this one is in the diff).

`tests/comms-drain-activate.bats` hung at test 1 of 14, **also at clean HEAD**, with no
`sed`/subprocess activity. Traced to `bin/cc-inbox-guard --selftest` → its recursive
`sweep` → a shell-out to the real `bin/cc-reconcile`, i.e. live session reconciliation.

The seam that was supposed to prevent exactly that could not express "off":

```bash
RECONCILE_BIN="${CC_INBOX_GUARD_RECONCILE_BIN:-}"   # "" ⇒ empty
if [ -z "$RECONCILE_BIN" ]; then                    # …and empty ⇒ AUTODISCOVER
  for _c in "$_bd/cc-reconcile" …                   # …which finds the real tool
```

Both this file's own `--selftest` (line 313) and `tests/cc-inbox-guard.bats` (line 16) set
`CC_INBOX_GUARD_RECONCILE_BIN=""` to isolate. Empty resolved to *autodiscover* — the exact
opposite of the intent — so both ran the live tool. Fixed by distinguishing **unset**
(⇒ autodiscover) from **explicitly set, empty included** (⇒ disabled) via `${VAR+set}`.
`PUSH_BIN` had the identical shape and was fixed with it. Production behaviour is unchanged:
only an explicitly-exported value behaves differently, and nothing but tests exports one.

After the fix: `--selftest` GREEN (3/3), `comms-drain-activate.bats` 14/14,
`cc-inbox-guard.bats` 19/19.

## 7. Known limits

- **Line-oriented, not a shell parser.** Multi-line AND-OR lists are judged at their head line;
  the analyzer skips continuation lines rather than joining them. No finding in this repo is
  currently a continuation head (verified: 0).
- **Conservative finality** over-reports a `[[ ]]` that is last inside a final `if` body. The
  cost is a harmless `|| false`.
- **`[ ]` inside `[[ ]]`-free `&&` chains** is only reported when the left element looks like an
  assertion (`[`, `[[`, `test`, `grep`, `diff`, `cmp`, `!`, or a pipeline ending in one), so
  genuine setup chains (`mkdir -p "$D" && cd "$D"`) stay quiet. A novel assertion helper called
  bare on the left of `&&` would be missed; naming it `assert_*` would not help until added here.
- **bash 3.2 is what was measured.** Bash ≥4.1 narrows some of these exemptions, so on a modern
  bash several of these assertions would newly *fire*. That makes the fix strictly more valuable,
  not less, and `|| false` is correct under both.

---

## Root cause — the gate has never linted a single `.bats` file

Found by `tm/relogin-exec`, verified by lead. `scripts/ship-land.sh:85`:

```bash
is_shell_file() {  # *.sh/*.bash OR a shell shebang
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
}
```

A bats file's shebang is `#!/usr/bin/env bats`, which matches **neither** that regex
**nor** the `*.sh|*.bash` case. So the `/ship` gate's `shellcheck` pass has **never run on
any test file in this repo** — which is exactly why 212 dead assertions accumulated across
51 files with a permanently green suite. This is the mechanism, not just an exposure.

**But fixing `is_shell_file()` alone is NOT sufficient**, and this is the trap: SC2314
covers only the bare-`!` class (89). It does not flag non-final `[[ ]]` at all (123 — the
majority). Wiring bats into the existing shellcheck pass would fix 42% of the problem
while reporting a confidently green gate. The lint is necessary; the analyzer below is
what actually closes the class.

*(Section preserved from the original finding doc, which this file supersedes. It is the
COVERAGE mechanism — why the debt accumulated unseen — and complements §1, which is the
LANGUAGE mechanism. Neither alone explains 226: bash made the assertions dead, and a gate
that never linted a `.bats` file made them invisible. Note the trap it names is exactly the
one §1 confirms: wiring bats into the shellcheck pass would close the 89 bare-`!` findings
via SC2314 and report a confident green over the 131 `[[ ]]` ones. The block-position
analyzer is what actually closes the class.)*

---

## 8. The ratchet's first catch — 30 more, one day later (2026-07-26)

Rebasing this branch onto `origin/main` pulled in **34 commits** written while the census was
being taken. The analyzer immediately reported **30 new dead assertions across 4 files**:

| Count | File | Class |
|---:|---|---|
| 16 | `cc-relogin.bats` | 16 `cond-keyword` |
| 8 | `handoff-selfclose-teammate-gate.bats` | 8 `cond-keyword` |
| 5 | `claude-accounts-core.bats` | 5 `cond-keyword` |
| 1 | `handoff-fire-account-sweep.bats` | 1 `negation` |

This is the result that justifies the ratchet: **dead assertions are not a one-time debt, they
are a continuous inflow.** 30 arrived in roughly one day of other sessions' work — a rate that
would have re-accumulated the original 226 within a month. A one-shot cleanup would have decayed;
only the gate-wired ratchet holds the line. `cc-relogin.bats` alone silently unasserted the
consent-gate result and the `pip install websocket-client` remedy — the operator's exact recovery
step, and the one assertion distinguishing a missing dependency from a browser failure.

All 87 tests in those 4 suites were green **before and after** revival, so unlike §6 nothing here
was masking a false assertion. Same uniform `|| false`.

### Measured false-positive rate: 3 of 30, all harmless

§4 promised finality would be judged conservatively — *"a false report costs one mechanical edit;
a false all-clear is absorbed forever."* That trade was measured here rather than assumed. Of the
30 findings, **3 sat in final position** and were therefore already live:

- `cc-relogin.bats:146`, `cc-relogin.bats:198`, `claude-accounts-core.bats:816`

All three are the same shape — `[ "$status" -eq 0 ] && [[ "$output" == *OK* ]]` as the body's last
statement, where the list's non-zero status becomes the body's return status and bats fails the
test. The analyzer misses their finality because a preceding multi-line `python3 -c '…'` block
defeats its line-oriented block tracking (§7, limit 1). The `|| false` is semantically inert on
these, so the cost is exactly the predicted one mechanical edit.

**27 of 30 were genuinely dead. 0 false all-clears.** The error is entirely in the safe direction.

### How that was established — mutation, with a negative control

A green post-fix suite proves nothing on its own: an assertion that is unreachable also never
fails. Each sampled assertion was therefore **mutated to a guaranteed-false predicate** and the
suite required to go RED (`not ok` counted from the TAP body, never the exit code — a piped or
truncated run reports the wrong rc):

| Site | Mutation | Post-fix | Pre-fix (control) |
|---|---|---|---|
| `cc-relogin.bats:111` | `"refused"` → `"ZZIMPOSSIBLE"` | **RED** ✓ | GREEN — truly dead |
| `cc-relogin.bats:146` | `-eq 0` → `-eq 99` | **RED** ✓ | RED — *already live* (over-report) |
| `cc-relogin.bats:326` | `!=` → `==` | **RED** ✓ | — |
| `claude-accounts-core.bats:836` | `next3*REQUIRED*` → `next3*ZZIMPOSSIBLE*` | **RED** ✓ | GREEN — truly dead |
| `handoff-fire-account-sweep.bats:247` | drop the `!` | **RED** ✓ | — |
| `handoff-selfclose-teammate-gate.bats:99` | `2 LIVE` → `9 LIVE` | **RED** ✓ | — |

The **pre-fix control column is what makes this a proof rather than a demonstration**: it shows
the same mutation passing unnoticed before the fix, so the `|| false` — and nothing else — is what
made the assertion fail-able. It is also what exposed the 3 over-reports, which no amount of
post-fix green could have distinguished from a genuine revival.

`cc-relogin.bats:146` doubles as the proof for the `and-absorbed` class: mutating the **left**
element of `A && B` fails the test, so both halves are now load-bearing.
