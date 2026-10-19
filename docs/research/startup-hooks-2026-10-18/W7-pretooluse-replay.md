# W7: replaying validate-bash's PreToolUse cancels (2026-10-19)

README §5 Wave 7 / A9-F9 asked for `cutreplay.py` to be adapted for PreToolUse and run in a hermetic
HOME. A9 R9 asked the replay to find the slow rule behind validate-bash's cancels (34 in 48 h).

## Method

- Reconstruct: `python3 -I docs/research/load-hook-timeouts-2026-10-11/cutreplay.py --event PreToolUse validate-bash 40 <out> 2026-10-16T00:00:00Z`
  rebuilds each cancelled call's payload from the `tool_use` named by the cancel record's `toolUseID`.
  Results are deduplicated by real path, because `~/.claude-next/projects` is a symlink to
  `~/.claude/projects`; without that, every case appeared twice.
- Replay: `python3 -I docs/research/startup-hooks-2026-10-18/a9-replay-pretooluse.py hooks/validate-bash.sh <out> --repo <checkout> [--trace /bin/bash]`.
  It runs `/bin/bash` (the harness's interpreter) with `HOME=<case>/home`, which holds only symlinks
  to the checkout's code, and with `CLAUDE_CONFIG_DIR` unset, so the hook's audit and decision logs
  land in the case directory. `--trace` timestamps each `-x` line as it arrives on the pipe, because
  bash 3.2 has no clock to put in `PS4`.
- Pinned by `tests/cutreplay-pretooluse.bats`.

## Result (40 cancels, 2026-10-18 to 2026-10-19, replayed at load ~275-330)

| | value |
|---|---|
| replay wall time | p50 2.8 s, p90 9.9 s, max 29.0 s |
| cases over 5 s / over 10 s | 12 / 4 |
| heredoc commands (`python3 - <<'EOF'`, `cat > f <<'EOF'`) | 39 of 40 |
| command size | p50 7.1 KB, range 3.2-13.2 KB; 29 of 40 contain a non-ASCII byte |
| decision | all `allow`: none of these calls is one the gate exists to deny |

The six slowest cases traced under `/bin/bash`:

| line | share of traced time | what it is |
|---|---|---|
| `hooks/validate-bash.sh:1608-1611` (`pha_flatten`) | 65.7% | four `${PHA_FLAT//<ch>/}` deletions of `'` `"` `\` `$` |
| `hooks/validate-bash.sh:476` (worker-claim gate) | 25.6% | nine `${_wcs_words//<sep>/\n}` replacements |
| `hooks/validate-bash.sh:647-654` (write gate) | 5.5% | `${_wbw_scan//…/ }` replacements |

**The interpreter is the cause.** The same replay that takes 16.7 s under `/bin/bash` 3.2.57 takes
0.3 s under bash 5.3. **The locale is why.** Bash 3.2 runs `${x//pat/}` multibyte-aware under a UTF-8
locale. Three passes of two such deletions over the 13.2 KB case-1 command take 35.0 s under
`LC_ALL=en_US.UTF-8` and 1.9 s under `LC_ALL=C` (the operator's `LANG` is `en_CA.UTF-8`).

All three sites match only ASCII bytes. A UTF-8 multibyte sequence never contains an ASCII byte, so
running these substitutions byte-wise (`LC_ALL=C`) gives identical output.

## Fix (follow-on, 2026-10-19)

`LC_ALL=C` alone was not enough. Bash 3.2's `${x//c/}` is also quadratic in its match count, so a
42 KB synthetic heredoc still ran past 120 s byte-wise. The landed fix (`hooks/validate-bash.sh`,
`pha_flatten`, `_wcs_split`, `_wbw_strip`):

- A function-local `LC_ALL=C` at all three sites.
- Above 2 KB (`CC_VB_TR_MIN_BYTES`), `pha_flatten` and `_wcs_split` make one `LC_ALL=C tr` pass. That
  is one fork, only on a command that large.

Same 40 cancels, replayed back to back at load ~185-205:

| | p50 | p90 | max | over 5 s | decisions changed |
|---|---|---|---|---|---|
| pre-fix | 2,763 ms | 10,356 ms | 22,618 ms | 12 | — |
| fixed | 218 ms | 384 ms | 618 ms | 0 | 0 of 40 |

The 42 KB fixture goes from over 120 s to 1 s. `tests/validate-bash-locale.bats` pins it within the
harness's limit, and pins byte-identical decisions against the pre-fix hook on both paths.

## Not covered

- Only validate-bash was replayed. The runner takes any PreToolUse hook path; agent-teams-enforce
  (A9 R8) needs its own run.
- A hermetic HOME has none of the live stores (backlog leases, the registry, the shared checkout).
  A rule that is slow only because of live state would be fast here. The traced time sits in pure
  string handling, so that gap does not change this result.
