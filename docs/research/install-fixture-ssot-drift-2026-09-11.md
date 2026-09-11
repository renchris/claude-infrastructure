# The SSOT rename reddened five install fixtures, and the walk convicted a commit 32 later

2026-09-11 · cc-backlog `cde8a9e450bc` · post-land RED
`tests/install-stale-refusal.bats::CC_INSTALL_ALLOW_STALE=1 overrides the refusal, loudly`
convicted at `823398c2e24a`. Measured off-box (Linux VM, bats 1.13.0, shellcheck 0.9.0).

## 1. Verdict

The RED is **real and now cured**; the **conviction was wrong**. The convicted commit is innocent by
direct A/B, and the true introducer is **`367e42f2`** — 32 commits and ~4 hours earlier.

| claim | evidence |
| --- | --- |
| the RED reproduces on trunk | `HEAD..origin/main` = 0 commits; suite reads **4 ok / 6 not ok**, plan line `1..10` present, convicted test 4 among the reds |
| `823398c2e24a` is innocent | its whole diff is `scripts/lead-supervisor.sh` + `scripts/supervisor-e2e.sh` — it touches neither `install.sh` nor this suite |
| `367e42f2` introduced it | convicted test is **RED at `367e42f2`** and **GREEN at `367e42f2~1`** (`1d1b509e`), probed in an isolated worktree, one test selected |
| `367e42f2` precedes the convicted sha | `git merge-base --is-ancestor 367e42f2 823398c2e24a` → true; 32 commits between |

Dispatcher vintage: `git rev-parse origin/main:bin/cc-dispatch` = `9109de61dc7add48cd94809d54e591af0bfe9021`
— **EQUAL** to the blob that composed the brief. The dispatcher that fired this row **is** trunk, so
no deploy-layer convergence question is mixed into this finding.

## 2. Mechanism

`367e42f2` ("the global SSOT moves off the repo root, which was loading it twice") renamed the
repo-side global SSOT `CLAUDE.md` → `CLAUDE.global.md`, so `install.sh:893` now copies
`$REPO_DIR/CLAUDE.global.md` → `$CONFIG_DIR/CLAUDE.md`.

This fixture builds a **synthetic** repo and seeded the old name:

```
printf 'TRUNK-V1\n' > "$TDIR/seed/CLAUDE.md"        # setup()
printf 'TRUNK-V2-LANDED\n' > "$TDIR/seed/CLAUDE.md" # advance_origin()
```

install.sh therefore found no SSOT, its `cp` aborted the run, and every test whose subject is a
**successful** install failed on `[ "$status" -eq 0 ]`. The real cause —
`cp: cannot stat '.../CLAUDE.global.md': No such file or directory` — appears only in bats' captured
`$output`, which no TAP reader prints. Six mute reds, cause invisible.

### Why the introducer's own audit could not see it

`367e42f2`'s commit body lists "**every reader of the old path**, audited and repointed" and names
`tests/{deploy-parity,wrap-ledger}.bats`. That enumeration was correct and still missed an entire
population: this file is not a **reader** of a repo path, it is a **writer** of a synthetic one
(`"$TDIR/seed/CLAUDE.md"`), which matches no grep for the old reader.

⇒ **when you rename a path, enumerate the fixtures that MINT that path, not only the code that reads
it.** A synthetic-repo fixture is a second implementation of your repo's layout, and it drifts
silently because nothing in the tree spells the path the way the audit searched for it.

## 3. Why the walk landed 32 commits away

Not investigated beyond ruling it out as this row's defect, and deliberately not "fixed" here — but
the shape is the one the corpus already records at
`.claude/rules/agent-operating-lessons.md` ("A bisect's predicate must be the CONVICTED TEST, not
its suite" / "A ratchet's culprit is in its output, not in the range"). Two facts worth carrying:

- **The failing assertion's own captured output named the true file** (`CLAUDE.global.md`) while the
  convicted diff contains no such path. A named culprit whose diff does not contain the path the
  assertion printed is **unattributed**.
- `bisect_reach_ok` would correctly **not** veto here: the convicted diff is not `*.md`-only, so the
  one-sided reachability guard has nothing to say. The guard is not at fault; the predicate is.

## 4. The hypothesis that looked right and is dead

The convicted test is the only one in the file whose subject is an env override, and it is written
as an env prefix on a **bats shell function**:

```
CC_INSTALL_ALLOW_STALE=1 run bash "$CLONE/install.sh"
```

That is exactly the shape of the `Empty selector is a universal selector` incident — `VAR=v cmd`
binds to that command's environment and never to the shell — so "the override never reaches
install.sh" is the natural diagnosis, and it would have produced a real-looking diff rewriting the
call. **Measured instead of assumed** (`bats` probe, two cases):

| probe | result |
| --- | --- |
| `FOO=bar run bash -c 'echo "FOO=${FOO:-UNSET}"'` | `FOO=bar` — the prefix **does** reach the child |
| the next `run` in the same test | `FOO=UNSET` — and it does **not** leak |

So the form is correct as written and is not a second cause. Test 10 uses the same form and passes.

## 5. The fix, and the mutant that killed its first draft

The seeded SSOT name is now **derived from `install.sh`** rather than hardcoded, so the next rename
cannot drift this fixture. The derivation **fails closed**: a default here would restore exactly the
mute failure it replaces.

🚨 **The first draft guarded on non-emptiness and that is not the guard.** A mutant respelling the cp
source as an unexpanded `"$REPO_DIR/$GLOBAL_SSOT"` made the capture non-empty — `[^"]*` matches a
variable reference as happily as a filename — so the derivation **failed OPEN, straight back into the
six mute reds it exists to replace, and the mutant SURVIVED**. The load-bearing check is that the
derived token is a **plain filename** *and* **names a real file in the real repo**.

All arms at `c469f7f7`, one variable each, isolated worktree:

| arm | `install.sh` | test file | result |
| --- | --- | --- | --- |
| control | trunk | fixed | **10 ok / 0 not ok** |
| pre-fix (the RED) | trunk | trunk | 4 ok / **6 not ok**, convicted test among them |
| M1 · tracks a rename | SSOT renamed in `install.sh` **and** on disk | fixed, **unedited** | **10 ok** — derivation returned `CLAUDE.deployed.md`, uniquely anchored (1 matching line) |
| M2 · cp line respelled `$REPO_DIR/$GLOBAL_SSOT` | mutated | fixed | **fails CLOSED**, named message in TAP output |
| M2 against the **first draft** | mutated | first draft | **SURVIVED** → 6 mute reds |
| M3 · `$SSOT` hardcoded back to `CLAUDE.md` | trunk | fixed but hardcoded | **6 not ok** — the exact trunk red set |

M1 is what proves the fix buys a property rather than a patch: the SSOT can be renamed again and the
fixture follows with no edit. M3 is what proves the derived name is load-bearing, not decorative.

**Instrument scar:** the first M3 run reported 10 reds and was **confounded** — M1's `git mv` was
still staged, so `CLAUDE.global.md` did not exist and every test died in setup for the wrong reason.
A hard reset and a re-established control separated them. Control the instrument before reading the
mutant.

### The asymmetry is deliberate

Repo side `CLAUDE.global.md`, live side `CLAUDE.md`. Do **not** also seed a root `CLAUDE.md` "to be
safe": while both sides share one name, a subject reading the **wrong** side still finds a file, so
no fixture can tell the two identifier spaces apart — the shape that hides address bugs — and a root
`CLAUDE.md` is the very thing `367e42f2` and `tests/deploy-parity.bats:1844` exist to forbid.

## 6. FOUR MORE SUITES ARE RED ON TRUNK FROM THIS SAME LINE — not fixed here

The frozen scope of `cde8a9e450bc` is one row, so this branch does **not** widen to them. Each was
measured to fail with the **identical** `cp: cannot stat '.../CLAUDE.global.md'` in its captured
output, i.e. the same missed fixture-writer population, not merely the same symptom:

| suite | seeded at | reads |
| --- | --- | --- |
| `tests/install-worktree-refusal.bats` | `:45` `"$PRIMARY/CLAUDE.md"` (also `:127`) | 3 ok / 5 not ok |
| `tests/install-fleet-activation.bats` | `:67` `"$FX/CLAUDE.md"` | 0 ok / 9 not ok |
| `tests/install-templatedir-home-guard.bats` | `:51` `"$FIX/CLAUDE.md"` | 6 ok / 4 not ok |
| `tests/install-resident-reload.bats` | `:64` `"$FX/CLAUDE.md"` | 1 ok / 14 not ok |

Remedy for each is the same one line — seed the name `install.sh` actually copies, ideally via the
`derive_ssot_name` helper this commit adds. Verified NOT of this class: every
`$CC_PARITY_LIVE/CLAUDE.md` in `tests/deploy-parity.bats` is a **live-side** write and correct.

⇒ the honest read of a post-land RED whose cause is a renamed path is that **the population is every
suite that mints the old name**, not the one suite that got filed. Re-measure the population before
closing the row.

## 7. What was run

```
git fetch --unshallow                     # arrived SHALLOW at depth 50
git rev-list --count HEAD..origin/main    # 0 — this tree IS trunk
git rev-parse origin/main:bin/cc-dispatch # EQUAL to the brief's blob
bats tests/install-stale-refusal.bats     # 4/6 before, 10/10 after
python3 scripts/bats-assert-liveness.py tests/install-stale-refusal.bats   # rc 0
bash scripts/bats-shellcheck-lint.sh      tests/install-stale-refusal.bats # clean, 0 blocking
bash scripts/bats-kill-guard-lint.sh      tests/install-stale-refusal.bats # clean
bash scripts/bats-testname-eval-lint.sh   tests                            # clean, 656 suites
bash scripts/gate-select.sh --explain origin/main..HEAD                    # selects 2 suites
```

The repo's own selector, asked with a real range, names exactly two suites for this diff:
`tests/install-stale-refusal.bats` (**10 ok / 0 not ok**, plan line present) and
`tests/bats-assert-liveness.bats` via the `assert-liveness:` edge — see below.

### The non-verdicts, named rather than counted as passes

- **`bats-shellcheck-lint`** first answered `⛔ shellcheck not installed — NOT a clean verdict`.
  Installed 0.9.0 and re-ran: clean, 0 blocking. The first answer was a refusal, not a pass.
- **`bash32-parse-lint`** answers `/bin/bash is bash 5, not 3.x — NON-VERDICT` and cannot be
  satisfied off a macOS box.
- **`tests/bats-assert-liveness.bats`** reads **31 ok / 6 not ok** here, and the 6 are structural:
  the suite hardcodes `LEGACY_BASH=/bin/bash` expecting macOS system bash 3.2, and its own CONTROL
  says so — `legacy bash is major 5, not 3.x`. Attribution is exact rather than merely
  "pre-existing": the **red set IS the LEGACY_BASH set, 6 of 6 with no residue in either direction**
  (reds `{3,4,5,14,21,36}` ≡ the six tests referencing `LEGACY_BASH`; the other 31 pass), and the
  same 6 fail in a clean worktree at `origin/main`. My diff touches neither that suite nor its
  analyzer.

For the bash-3.2 question the diff adds no `[[ ]]`, no associative array and no `${var^^}`; its new
constructs are `local`, `case`, `sed`, `printf` and `if ! v="$(f)"`, all bash 3.2. **That is an
argument, not a verdict** — the macOS-side gate still owes the answer on all three.

**Instrument scar worth carrying:** the first A/B of the liveness suite was run as
`bats … ; git stash -q ; bats …` **after the work was already committed**, so `git stash` stashed
nothing, both arms ran the same tree, and the `IDENTICAL` it printed was vacuous. The real A/B needs
a worktree at `origin/main`. A stash-based A/B silently degenerates into one arm whenever the tree is
clean — and it reports agreement, which is the direction that reads as confirmation.
