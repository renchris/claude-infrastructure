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

Repo has no CI wired today. A minimal workflow (Ubuntu latest + `bash` + `jq`)
would run this suite on every PR. Template:

```yaml
# .github/workflows/test.yml
name: test
on: [push, pull_request]
jobs:
  hook-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: hooks/tests/validate-bash.test.sh
```
