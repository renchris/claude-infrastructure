# H14-hook-text-trims — adversarial review

Reviewer read `git diff` of the four owned hooks and their tests, and the two new test files.

## Verdict

One major issue, under flag (d): turning on `CC_DOD_LINEAGE_ONLY=1` breaks the documented `/handoff`
DoD carry, and it also breaks survival across compaction for any session whose scope text matches a
capture already in the same worktree. Cuts (a), (b) and (c) are correct. Scope is clean, the flags
default off, and the suites are green. Two test assertions are vacuous (details below).

## Checks run

| check | result |
|---|---|
| scope: files changed | only the 4 owned hooks and their tests; the mailbox-drain change is one hunk, in the render path only |
| `/bin/bash -n` and `bash -n`, 4 hooks | clean |
| bare `shellcheck`, 4 hooks | rc 0 |
| `tests/config-mirror-assert.bats` + `tests/session-index-start-context.bats` | 1..10, 0 fail |
| `tests/dod-persist.bats` | 1..36, 0 fail |
| `tests/mailbox-drain.bats` | 1..60, 0 fail |
| config-mirror under `/bin/bash` 3.2, interleaved names | correct: non-backups listed first, `(+4 more)` |
| python3 stale-forward path under `LC_ALL=C` | UTF-8 in and out works (PEP 540) |
| consumers of the changed strings | none outside the hooks and their tests |

Mutation controls (on scratch copies):

| mutant | killed? |
|---|---|
| M1: dod own-sid match disabled | yes, tests 1 and 5 |
| M2: dod predecessor-toplevel match disabled | yes, test 2 |
| M3: mailbox `len(summ) < len(raw)` guard removed | **no, survives** |
| M4: mailbox age taken from the forward stamp instead of the origin stamp | yes |
| M5: session-index treats a tag-only entry as empty | yes |
| M6: config-mirror "non-backups first" ordering removed | **no, survives** |

## Findings

### major: flag (d) drops the successor's contract on recycle and after compaction

`commands/handoff.md:133-136` (T-P4-4) says the predecessor runs `dod-persist.sh set` so that the
successor's SessionStart injection carries the DoD. It states that a `--recycle` "carries nothing
unless this capture runs". Under the flag, that capture is stamped with the predecessor's
`CLAUDE_CODE_SESSION_ID`. The successor has a new session id in the same worktree, so it gets only
the pointer.

The gap is also permanent, which the implementer's open issue does not say. Write-side dedup
compares against the toplevel-filtered stream, not the session's own captures:

- `set` at `dod-persist.sh:139`
- PreCompact at `:318` (frozen) and `:329` (grown)

So when the successor restates the same scope, it never gets a capture of its own. Reproduced on a
scratch store:

1. Session A runs `set "Scope (frozen): ship X"`.
2. Session B runs PreCompact on a transcript that contains the same line. Nothing is written for B.
3. Session B's SessionStart (source `compact`) with the flag on returns only the pointer.

The contract is lost across compaction, and compaction is the reason this hook exists (a19 HOP A).

Fix, inside the owned file:

- Under the flag, dedup `set` and PreCompact against `_dod_lineage_blocks "$sid"` instead of
  `dod_filter_for`.
- Treat same-pane predecessor session ids as lineage. They are recorded:
  `mailbox_alias_trail <pane>` (`hooks/lib/mailbox-pending.sh:104`) lists every session that has
  occupied a pane, newest first. `mailbox-drain.sh` already uses it for pull-adoption. This also
  refutes the open issue's claim that "no store records a predecessor's session id".
- Add a test: set by SID_A, then SessionStart as SID_B on the same pane with the flag on, and expect
  the contract.

### minor: the "stays verbatim when shorter" assertion is vacuous

In `tests/mailbox-drain.bats`, `grep -qF "  │ $OLDSHORT"` also matches the summarised form, because
the summary begins with exactly that text. Mutant M3 (guard removed) passes the whole suite. Fix:
assert that the `[peer-c]` line has no `[stale forward:`, or compare the full rendered line.

### minor: the "non-backups first" ordering is untested

The fixture in the first FORKED test already lists the non-backups first, so mutant M6 (no
reordering) passes. The real library emits names in glob order, which is alphabetical, so
`settings.json.bak-*` comes before `skills` and `todos`. Fix: put backups ahead of at least one
non-backup in the fixture, for example `settings.json.bak-1 … todos`.

### minor: flag (c) bounds each line but not the total

Adoption can surface up to `CC_MBX_ADOPT_MAX_LINES` = 200 lines. Each stale summary is about 330
chars with a real box path, so a full adopted batch is still about 66 KB. That is past Claude Code's
10,000-char persistence cap, so the model would see a 2,000-char preview anyway.

Measured on the live boxes: 957 forwarded lines, median 1,240 chars, p90 2,500. The per-line summary
therefore cuts about 3.7x, but it cannot keep a large batch under the cap. hooks.md §5 row 10
proposed a count and a listing command. Consider collapsing to one count line plus one `grep` once
the stale lines exceed a small N.

### minor: flag (c) applies at every boundary, not only at session start

The block runs in `prompt` and `post-tool` modes too. The coverage fold (`mailbox_migrate` from the
own pane box) stamps `[forwarded:<pane8>]` at every boundary. Those lines are normally fresh, so the
effect is harmless. Either gate the block on `MODE = session-start` to match the task, or say in the
comment that it covers all modes.

### minor: flag (d) omits pre-header content without counting it

`_dod_lineage_blocks` starts with `keep=0`. Content before the first `## ` is therefore dropped:
the file header, and a legacy boxes-only file that `_dod_filter_file` always keeps. Leaving it out is
consistent with "no provenance". But the pointer's count (`nall` counts only `^## ` lines) does not
mention it. Count it or name it in the message, so that a legacy `- [ ]` checklist is not silently
invisible.
