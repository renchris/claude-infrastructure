# Post-land RED `tests/agents-omit-claudemd.bats::3` at 2be051f3: already cured on trunk by revert e7321f2a

cc-backlog `0ef0c3577a86`. Verdict: **CURED ON TRUNK. Nothing to land.** One residual, which this
row does not cover, is described under *Residual* below.

## Cure

`e7321f2a` (`Revert "fix(agents): point research agents at the research-subagents skill, and quote
the critic's description"`) reverts `2be051f3` in full and is trunk's tip:

    $ git merge-base --is-ancestor e7321f2a origin/main && echo revert-on-trunk
    revert-on-trunk

## What I ran

This was an off-box cloud VM with no `bats` installed, so I replayed case 3's exact pipeline
(`sed -n 's/^description: //p' | wc -c`) against each revision:

| revision | research-decomposition-critic | ceiling | case 3 |
|---|---|---|---|
| `2be051f3~1` | 342 | 342 | ok |
| `2be051f3` | 344 | 342 | **RED** |
| `origin/main` (`e7321f2a`) | 342 | 342 | ok |

The other three ceilings (deep-research 250/1367, deep-research-sonnet 232/885,
frontier-derivation 288/532) stay green at all three revisions. The whole red comes from the two
`"` characters `2be051f3` added to quote the critic's description, so the case reported what it
exists to report: a description grew without its ceiling being raised.

Checkout state: `HEAD..origin/main` = 0 after unshallowing. The dispatcher blob
`dc9130372d6332940388c2a17da7c65c1af3c3bd` equals `origin/main:bin/cc-dispatch`, so the
dispatcher that fired this row IS the trunk version.

## Residual (outside this row, and possibly the operator's call)

The revert also undid the two real fixes in `2be051f3`:

1. `agents/research-decomposition-critic.md`: the description again holds an unquoted `: `
   (`verdict: APPROVE`). `yaml.safe_load` of the frontmatter on trunk raises
   `mapping values are not allowed here`, and per `2be051f3`'s message CC 2.1.114 drops the whole
   frontmatter when that happens.
2. Six references in the research agents again point at `~/.claude/rules/research-subagents.md`,
   which does not exist. The file is `skills/research-subagents/SKILL.md`.

To re-land it green, cherry-pick `2be051f3` and raise the critic's ceiling in
`tests/agents-omit-claudemd.bats` case 3 from 342 to 344, in the same commit. The case's own
comment names that as the allowed route ("Growing one is allowed only by raising its ceiling here,
in the open"). I did not do this. The row's scope is frozen to this RED, and trunk may have chosen
the revert on purpose, so reversing it is not something to do unasked.
