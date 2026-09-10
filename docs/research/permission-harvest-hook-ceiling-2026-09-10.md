# The hook-layer ceiling — what a PreToolUse lever can ever clear on the structural cluster

**2026-09-10** · cc-backlog `5a629c6465d1` (condition `permission-harvest-structural-levers`) ·
DoD ref `docs/plans/PERMISSION_HARVEST.md` · instrument:
`docs/research/permission-harvest-hook-ceiling-2026-09-10/hook-ceiling.py`

## The answer first

**The premise is refuted. The structural cluster is not convertible into a prompt-reducing
hook-layer lever, and the reason is the same one that bounded the rule layer: the operator's
existing guards already own everything worth levering.**

`PERMISSION_HARVEST.md` §3.5 measured STRUCTURAL at 45% of all Bash prompts and 66% of the
1,622 h agents spent waiting at them, then named `command_substitution`, `redirect_file`,
`heredoc`, `cd_git_compound` and `multi_cd` as *"authoring-habit / hook-layer levers, not rule
levers."* That sentence priced the rule layer (13–21 prompts ever, 0.35–0.56%, 0 in the last
7 days) and left the hook layer as an **unpriced hope**. This note prices it.

| | rows | of structural |
|---|---|---|
| STRUCTURAL rows in the archive | 1,752 | — |
| …that `smart-bash-allowlist` allows today | 4 | 0.2% |
| **HOOK-LAYER CEILING** — no danger, no operator fence, no ACE dispatcher, no verb-from-substitution, decomposable | **444** | **25.3%** |
| …after excluding the three verbs an existing guard already owns (`rm`, `git`, `curl`) | **33** | **1.9%** |

The ceiling looks like 444 and is really 33, because the greedy cover's first three picks are
`rm` → `git` → `curl`, which between them carry 181 of the 444. None is a hook improvement:

- **`rm`** — `allowed_segment` already DELEGATES deletion to `hooks/rm-safe-allowlist.sh`, which
  owns the policy and is separately tested. Levering it means overruling that hook.
- **`git`** — sits behind the operator's own `ask`/`deny` entries. A PreToolUse `allow` cannot
  revoke those (the harness re-checks deny and ask after a hook allow — docs /permissions:442,
  `Mfr`), so the lever is *inert where the fence stands* and a silent grant everywhere else.
- **`curl`** — hook-raised, measured: 1,367 of 1,368 curl "gap" rows joined to a `curl-gate`
  `ask` within ±15 s (profile §2). Also the only verb among the 23 refused prompts in the
  archive to appear three times, so `REFUSED_PROMPT_COLLISION` refuses it on its own evidence.

What remains after those three is 33 rows, and its own cover runs out almost immediately:
`cat` clears 9, then `kill`, `chmod`, `launchctl`, `sed`, and then a tail of **ad-hoc scripts**
(`trace.sh`, `probe.sh`, `repro.sh`, `bin/…`) that no whitelist can name because they exist for
one session. A per-verb write policy for eight verbs, several of them privileged, to clear 18
archived prompts is not a lever; it is a widening with a rounding error attached.

Read beside the plan's own conclusion, the two halves now agree: **prompt reduction on this
fleet is ≤0.6% from allow rules and ≤1.9% from hook levers, and `proposed=0` is the correct
steady state at both layers.** The plan's instruction — make the STRUCTURAL breakdown and the
curl-gate attribution the harvester's headline, and size the job's value on consolidation — is
unchanged by this note and is reinforced by it.

## What was built anyway, and what it is worth

Four shapes that **cannot execute anything** were each deferring a whole command. They are fixed
in `hooks/lib/smart-bash-allowlist.py` (tests: `tests/smart-bash-allowlist-inert.bats`):

| | shape | why it deferred | archive footprint |
|---|---|---|---|
| I1 | `$(( … ))` arithmetic expansion | `extract_substitutions` returned not-ok on sight of it, failing the WHOLE command | 87 structural rows at the top level |
| I2 | a `# comment` line | `verb()` matched no identifier, so the segment was "not on the allowlist" | 162 occurrences / 114 rows |
| I3 | `[` | the exact synonym of `test`, which **is** in `READ_ONLY`; `test -f x` allowed, `[ -f x ]` refused | 133 occurrences / 102 rows |
| I4 | `:` | the exact synonym of `true`, likewise already in `READ_ONLY` | 50 occurrences / 39 rows |

🚨 **Measured A/B against trunk over all 3,771 archived Bash rows: allow 162 before, 162 after.
ZERO prompts cleared, ZERO regressions.** This is stated first because it is the part a reader
will otherwise assume away. The change is worth landing for a different reason:

**It is a measurement-fidelity fix.** `decide()` returns on its FIRST refusal, so the arithmetic
blanket-refusal did not merely defer those rows — it **masked every other cause in them**. Before
the fix, 111 rows presented as single-cause "cannot decompose", which reads exactly like the
largest single-lever win in the corpus; all of them carried other blockers underneath, and the
harvester's own attribution pass would have reported them that way in its weekly headline. After
the fix, 46 structural rows decompose that previously could not, and their real verbs are
visible. The first-cause column in the table above is labelled a MASK for this reason, and the
instrument refuses to print it as a distribution.

I3/I4 are a second kind of defect: not a wrong decision but an **inconsistent** one. A hook that
allows `test -f x` and refuses `[ -f x ]` cannot be reasoned about by the operator or by the next
measurement, and the asymmetry was invisible because nothing compared the two spellings.

**Safety.** Nothing here widens policy — the allowlist is unchanged and every new path still
passes the operator's fence, the danger patterns and the redirect scanner. The three places that
could have gone wrong are pinned by mutants in the suite (`tests/sba-mutate.py`), because each is
green in BOTH arms and so proves nothing on its own:

- `$((` is genuinely ambiguous — `$( (subshell) )` written without the space is a COMMAND
  substitution. `_arith_end` requires the matching `))` PAIR, so `$((cmd) )` defers.
- an arithmetic body is screened by a POSITIVE character whitelist plus an explicit refusal of
  `$(`, a backtick, `${!` and process substitution — the four shapes that could hide an
  executable behind a placeholder the outer scanners never see again.
- `[` and `:` sit BELOW `redirects_to_file`, which is the only thing between `:` and `: > file`.

## Two instrument defects worth carrying

Both cost a wrong answer before they were caught, and both are about the *arm*, not the subject.

**1. A flat copy of the subject is not the subject.** `smart-bash-allowlist.py` resolves
`_RM_HOOK` relative to its own `__file__`. Patched into a scratchpad file, it loses the sibling
`rm-safe-allowlist.sh`, every `rm` segment then refuses, and the first A/B reported **three
regressions that were pure harness artifact**. The A/B had two variables — the patch and the
module's location — and read as a defect in the patch. Arms are now built as a mirrored `hooks/`
tree and the precondition is ASSERTED (both arms must resolve the sibling hook and agree on a
probe) rather than hoped for. Same family as the `cc-memory-rotate` finding already in memory.

**2. `local a="$1" d="$X/$a"` leaves `$a` EMPTY.** In one `local` statement the later assignment
does not see the earlier one, so every test arm resolved to the bats tmpdir ROOT: the pre-fix
tree silently **overwrote** the fixed tree and the control compared a file against itself. It
surfaced only because the positive-control grep then looked in a directory that had never been
created — i.e. the thing that caught it was the control ON the control, not any assertion. The
helper now splits the declarations and asserts the arm name is non-empty.

## Re-measuring

Every row above decays with the archive (~40 new rows/day), so take the criterion and re-run the
instrument rather than quoting the table:

```
/usr/bin/python3 docs/research/permission-harvest-hook-ceiling-2026-09-10/hook-ceiling.py
```

It fails closed: an unreadable fence or an out-of-shape arm exits 2 rather than reporting. The
claim that would overturn the verdict is *"the cover's top picks are no longer `rm`/`git`/`curl`"*
— that, not the absolute ceiling, is what makes the structural cluster unleverable today.
