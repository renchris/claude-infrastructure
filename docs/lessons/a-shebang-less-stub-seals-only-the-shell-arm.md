# A shebang-less PATH stub seals only the SHELL arm of a census

**The rule.** A stub dropped on `PATH` without a `#!` line is executable by **bash**, which falls
back to reading an `ENOEXEC` file as a script — so every shell caller is sealed. **CPython is not.**
`subprocess` treats the same `ENOEXEC` as *"not executable here"* and **keeps walking `PATH`** to
the real binary. A fixture whose subject is called from both a shell and a Python program therefore
seals half the callers, and the half it misses reads the real machine.

**Give every stub a shebang, and seal each caller through the seam that caller actually resolves.**

## The 2×2, measured directly (2026-09-21, macOS 24.6.0, python3, bash)

Stub writes `STUB-HIT` to stderr and exits `42`; the pattern matches nothing, so the *real* `pgrep`
would exit 1 silently. Both arms run with the identical `PATH`.

| stub shape | bash caller | CPython `subprocess.run` |
|---|---|---|
| **no shebang** | `rc=42 stderr=STUB-HIT` — **sealed** | `rc=1 stderr=''` — **walked past to `/usr/bin/pgrep`** |
| **`#!/bin/bash`** | `rc=42 stderr=STUB-HIT` | `rc=42 stderr='STUB-HIT\n'` — sealed |

One variable changed. `file(1)` reports the shebang-less stub as `ASCII text`, and it is `chmod +x`
in both arms.

**And Python's own resolver agrees with the seal while `subprocess` ignores it:** under the same
`PATH`, `shutil.which('pgrep')` returns `/tmp/enoexec-probe/stubdir/pgrep`. The obvious verification
— *"does the interpreter find my stub?"* — answers **yes** on exactly the configuration that fails.

## The incident

`tests/lr-reset-poller-inplace.bats` was voting with the real fleet: `pgrep -f "resume <sid>"` is
consulted **twice per tick from two different programs** — `lr-reset-poller.sh` calls it bare at
`:1139` and `:1281`, and `lr-select.py`'s `is_running()` runs `LR_SELECT_PGREP_BIN`, defaulting to
bare `pgrep`. Any process anywhere on the box whose argv held `resume <SID>` answered YES, lr-select
filtered the fixture's own candidate as `already-running`, and the tick retired the record before
the case's assertion was reached. Pre-fix, with one live decoy carrying `--resume <SID>`: **17 of 21
red**. Post-fix under the identical decoy: **21/21**.

**The first cut of that very fix carried a shebang-less stub** — the shape of the `osascript` and
`tmux` stubs sitting beside it in the same `setup()`, which are correct *because only bash invokes
those*. It sealed the bash arm, left the python arm on `/usr/bin/pgrep`, and **looked sealed**: the
stub's log carried exactly one line and it said `caller=bash`. Landed as `8bfdcd60d`
(`tests/lr-reset-poller-inplace.bats:56-78`), which also exports `LR_SELECT_PGREP_BIN` by **absolute
path**, so the python seam does not depend on `PATH` order surviving the poller.

## Two instrument traps — worth more than the rule

**(1) A probe whose pattern matches nothing cannot see the hole.** The natural check is "run the
subject and look at the exit code." With a non-matching pattern the stub returns 1 and the real
`pgrep` returns 1, so the instrument has *no discriminating output at all* and its silence reads as
a seal. The 2×2 above is only legible because the stub exits **42** and prints a token: give a stub
a return value the real binary cannot produce, then assert on that, never on success/failure.
(Companion: [[uniform-error-ratio-indicts-the-model]].)

**(2) A sibling census can be un-probeable by the obvious probe.** `ps -axo command=`
(`lr-lib.sh:493,673`) is the other real-table census in this subject and is deliberately **not**
stubbed. The first probe injected a matching line carrying a **dead** pid and the suite stayed
green — which proves nothing, because the census discards anything failing `kill -0`
(`lr-lib.sh:290,368`). Re-probed with a matching line carrying a **live** pid (pid 1), still green.
That is the difference between *"ps is not an axis here"* as a measurement and as a guess. Recorded
so the next reader re-probes rather than re-quotes.

## What to do

1. **Every stub gets a shebang**, even where the caller you have in mind is a shell. It costs one
   line and removes a whole class of half-seals.
2. **Enumerate the CALLERS of the stubbed name, not the spellings.** Two programs in different
   languages calling one binary are two arms; a language-level env seam (`LR_SELECT_PGREP_BIN`) and
   a `PATH` drop are two different seals and you may need both.
3. **Make the stub's verdict unforgeable** — a distinctive rc plus a log line — before you believe
   any probe of it.
4. **Ask what the sibling census filters on** before calling it not-an-axis; a fixture that the
   subject silently discards is a blind probe, not a negative result.

Companions: [[hermetic-in-stubs-not-in-interpreter]] (stubbed ≠ hermetic — reproduce at
`PATH=/usr/bin:/bin` before believing a logic red), [[denylist-enumerates-spellings-not-the-class]]
(a seal keyed on the spelling you saw misses the class),
[[a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool]],
[[nth-fallback-source-un-seals-old-fixtures]].

Refs: `8bfdcd60d`; cc-backlog `92760deed5ea`, `1117e6f228cf`.
