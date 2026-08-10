# Hook Tests

Test harness for `hooks/*.sh` validators.

## Running

```bash
./validate-bash.test.sh              # run all
./validate-bash.test.sh -v           # verbose (show pass output)
./validate-bash.test.sh --filter A12 # run subset (regex on test name)
```

Exit code 0 = all green, 1 = at least one case failed.

## Format

Each case is:

```bash
assert_case "<name>" "<command>" "<expected: allow|deny|ask>" "<reason_substring_or_empty>"
```

The harness:
1. Wraps the command in the `{"tool_input":{"command":"..."}}` JSON payload the hook expects on stdin
2. Runs the hook under a throwaway `$HOME` (via `mktemp -d`) so audit logs don't pollute the real one
3. Parses the hook's JSON stdout with `jq`
4. Asserts decision + (optional) reason substring

## Test categories

- **A. False positives** — commands that LOOK dangerous (mention forbidden flags / DDL in message bodies) but must be ALLOWED
- **B. True positives** — real bypass / destructive attempts that must be DENIED
- **C. Ask-before-run** — destructive but sometimes intentional (user confirmation)
- **D. Common commands** — routine dev flows that must pass through silently
- **E. Edge cases** — unclosed quotes, pipelines, heredocs, env prefixes, `git -C` redirection, etc.

## Adding a case

Append to the matching section in `validate-bash.test.sh`. For false-positive cases,
include a comment describing WHY the command is legitimate — the reasoning is what
prevents a future contributor from "fixing" the hook to block it.

## CI

Two workflows exist (this section claimed "no CI wired today" until 2026-08-10, which had been
false since `449fdfde` landed `diagrams.yml` on 2026-07-28):

- `.github/workflows/diagrams.yml` — fails if a rendered SVG has drifted from its `.mmd` source.
- `.github/workflows/hermetic.yml` — runs the **hermetic partition** of the `tests/*.bats` corpus
  on `macos-latest`, as a second green producer for the deploy lane
  (`docs/plans/DEPLOY_LANE_GROUND_UP.md`, 2026-08-10). Partition:
  `scripts/offbox-partition.sh`; runner: `scripts/offbox-run.sh`.

**This suite is not in either.** `hooks/tests/validate-bash.test.sh` is the pre-bats standalone
harness, and `hermetic.yml` runs `tests/*.bats` only. Adding it is a one-line step in
`hermetic.yml`, not a new workflow — the template that used to live here would have created a
third one.
