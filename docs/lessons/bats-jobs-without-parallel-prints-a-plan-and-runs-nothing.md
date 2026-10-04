# `bats --jobs N` without GNU parallel prints the plan line and runs nothing

**Rule.** A `1..N` plan line proves bats *planned* N tests, not that it ran them. Before trusting a
filtered bats result, also check that the `ok` + `not ok` count equals N. On a box without GNU
`parallel`, never pass `--jobs`: run suites serially.

**Incident (2026-10-04, claude-api audit session).** A focused gate over 32 suites was run as
`cc-bats --jobs 6 …`. It printed `1..588`, then `parallel: command not found` and
`# bats warning: Executed 0 instead of expected 588 tests`, and exited 1. A second gate, run as
`bats --jobs 2 …` by three workflow implementers, did the same (`1..3`, 0 executed). Each looked
like a normal run to a reader that greps for `^not ok` and checks for the plan line, which is
exactly the check the resident lesson "Gate refusal ≠ gate result" prescribes. That lesson covers a
gate that refuses and prints nothing. This failure prints the plan line and still runs nothing.

**Why it happens.** bats implements `--jobs` by piping test names into GNU `parallel`
(`bats-exec-suite` line ~314). When `parallel` is missing, the suite runner still emits the plan
line first, then fails to start any worker. The only signals are a stderr line and the
`Executed 0 instead of expected N` warning, both easy to filter away.

**How to apply.**
- Count results: `grep -cE '^(ok|not ok) '` must equal the plan line's N.
- `command -v parallel` before any `--jobs`; on this machine it is absent, so run serially.
- Under the zsh Bash tool, a suite list held in a variable is not word-split (`bats $S` passes one
  argument and fails with `cd: … No such file or directory`); run the list under `bash -c` or
  expand it with `${=S}`.
