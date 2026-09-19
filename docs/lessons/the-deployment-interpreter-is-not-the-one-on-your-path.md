# The interpreter your script runs under in production is not the one on your PATH

**2026-09-19.** A launchd job installed that morning had run **five times and crashed every time**,
exit 2, with a bash **syntax error**. The script parsed and ran perfectly by hand, its suite was
10/10 green, and two land gates had passed it.

```
runs = 5        last exit code = 2
browse-mirror-sync.sh: line 240: syntax error near unexpected token `;;'
```

## Why it was invisible

The plist runs `/bin/bash -c 'exec "$HOME/.claude/scripts/browse-mirror-sync.sh"'`. The script's
shebang is `#!/usr/bin/env bash`, and `env` resolves `bash` against **launchd's** PATH — so the
interpreter is `/bin/bash`, which on macOS is **3.2.57** (Apple froze it at the last GPLv2 release in
2007). A developer shell resolves the same shebang to Homebrew's **5.3**. Two interpreters, eighteen
years apart, selected by which environment the process happens to start in.

The specific incompatibility: **bash 3.2 cannot parse a `case` arm containing `continue` inside a
command substitution.** Minimally reproduced, and — measured, not assumed — the multi-line form fails
identically, so reformatting is not the fix:

```bash
out=$(
  while IFS='|' read -r path ref; do
    case "$path" in \#*) continue ;; esac     # 3.2: syntax error. 5.x: fine.
  done <<< "$LIST"
)
```

The repair was to drop the `case` entirely: `[ "${path#\#}" != "$path" ] && continue`. Parameter
expansion has no such problem.

## The rule

**For anything a scheduler runs — launchd, cron, a git hook, CI — the interpreter is chosen by THAT
environment, and it must be part of the test.** Not as a lint, and not as a parse check alone: a 3.2
*runtime* defect (an associative array, `${v^^}`, `mapfile`) parses fine and dies on execution. So
the test **runs** the subject under the real interpreter:

```bash
run /bin/bash -n "$SUBJECT"     # parses under the deployment interpreter
run /bin/bash "$SUBJECT"        # …and actually runs, end to end
```

`#!/usr/bin/env bash` is the portable shebang and that is exactly why it is the hazard: it promises
"whatever bash is here", and *here* differs between the terminal you wrote it in and the daemon that
runs it. Pinning `#!/opt/homebrew/bin/bash` trades this bug for a worse one — a Homebrew dependency
on an unattended path, which `scripts/unattended-path-lint.sh` exists to refuse. **Write 3.2-clean
and prove it by execution.**

## The shape, which is the third instance in a single change

This is the same defect class as the two before it in the same work (see
[[a-read-only-surface-must-not-be-able-to-hold-state]]):

| # | Defect | Why the suite could not see it |
|---|---|---|
| 1 | `producer \| grep -q` under pipefail — condition reads FALSE on a match | needs ~550 worktrees to fill a 64 KiB pipe buffer |
| 2 | bare `timeout` — a Homebrew binary, absent on a launchd PATH | tests run with Homebrew on PATH |
| 3 | `case`+`continue` in `$( )` — a bash 3.2 parse error | tests run under bash 5 |

Every one lives in the **gap between the test environment and the deployment environment**, and every
one is silent: two were caught by static ratchets at the land gate, and the third by a *verifier that
asserted the effect rather than the paperwork*. Had migration `0032`'s oracle checked only "is the
launchd job loaded", it would have answered **yes**, forever, over a job that crashed on every
trigger. That is why `migrations/README.md` says verify the EFFECT, not the paperwork — this is what
it costs when you don't.

**Green tests are evidence about the environment they ran in.** When a thing will run somewhere else,
that somewhere else is a test dimension, not a deployment detail.

## Re-derive

```bash
/bin/bash --version | head -1                      # the deployment interpreter
launchctl print "gui/$(id -u)/<label>" | grep -E 'runs|last exit code'
/bin/bash -n <script> && /bin/bash <script> --dry-run
```
