# F4 project-rules split: adversarial review

Reviewer read the diff of the owned paths only, plus `git status` for new files, and re-ran every
check below in the shared worktree on 2026-09-23.

## Verdict

The split is correct, and so is its default-load claim. Every original line is in exactly one
file. The lint is clean on both files, 17 + 163 = 180 bullets, the same as the original's 180.
Headless `/context` (2.1.280) lists the resident file at 3.5k tokens and the situational file at
24.6k. Every writer now routes to the situational file.

There is one major landing hazard: `.gitattributes` gives the resident file `merge=union`, and that
silently undoes part of the split on any rebase. Fix it before landing.

## What was re-run

| check | result |
|---|---|
| `tests/rules-split.bats` + `rules-hook-budget-lint.bats` + `migration-0036-*.bats` | `1..32`, 0 fail |
| `memory-nudge-budget` `1..43` · `memory-index-entry-cap` `1..20` · `memory-index-budget` `1..32` · `memory-index-drain` `1..29` · `memory-rules-routing` `1..18` · `cc-memory-rotate` `1..44` · `compact-memory-orphan-sweep` `1..6` · `deploy-migrations` `1..10` · `gitattributes-union-merge` `1..3` | all 0 fail |
| `jev-promote.bats` | `1..48`, 3 fail (40, 43, 46): the same three the implementer named. Every test sets `CC_JEV_RULES_FILE=/dev/null`, so the new `RULES_SIT` becomes `/dev/null-situational.md`, which does not exist, and the added line cannot run there. The failures are not caused by this diff |
| `bash -n`, `/bin/bash -n`, bare `shellcheck` on the 7 changed shell files + `tests/helpers/rules-split-check.sh` | clean |
| `scripts/rules-hook-budget-lint.sh` (no args) / `--selftest` / the pre-split blob | rc 0 / PASS / rc 0 (180 bullets) |
| headless `/context` from the worktree root | memory files 87.9k; resident 3.5k, situational 24.6k |
| resident membership vs `audit/C7.labels.md` RESIDENT rows | all 19 match |
| compact-memory description | 230 chars, YAML parses |

## Findings

**major 1: `merge=union` on the resident file silently brings back part of the split on rebase.**
`.gitattributes` still carries `.claude/rules/agent-operating-lessons.md merge=union`, which was
added because every rotor appended to that file. Scratch repo, reproducible with
`bash /tmp/f4rev/union.sh`: base = HEAD's unsplit file, branch A = this split, branch B = one
appended bullet (what every pre-split rotor copy still does). Rebasing B onto A exits 0 with no
conflict markers, and the resident file grows from 53 to 83 lines. The union driver copies back the
original's last 29 lines, which now live in both files, plus the new bullet. The other direction
behaves the same: when the lead rebases this branch onto a trunk that has had any append since
HEAD, the result is again 83 lines. Nothing at the land gate catches it: ship-land calls the lint
once per file with `--file`, and the new cross-file duplicate arm runs only without `--file`. Only
`tests/rules-split.bats` would go red, and only if it runs.

Fix, in the lead's split commit (both files are outside F4's list):
- In `.gitattributes`, move `merge=union` from the resident file to
  `agent-operating-lessons-situational.md`. The resident file is no longer append-only, so a
  conflict there should be loud.
- Point `TARGET` in `tests/gitattributes-union-merge.bats` at the situational file.
- After the final rebase, run `tests/rules-split.bats` and `wc -l` the resident file.

**major 2: the cross-file duplicate arm never runs at the enforcement point.**
`scripts/ship-land.sh:3615` runs `"$RULES_LINT" --file "$_rf" --own-range "$range"` for each
changed rules file. The new `DUPLICATE — both files link` arm lives only in the no-`--file` branch
of `scripts/rules-hook-budget-lint.sh`, so the land never runs it, and major 1 lands clean. The fix
fits inside F4's own file: when `--file` names either half and the sibling file exists, also run the
cross-file arm. It is always blocking, like the in-file duplicate arm. Add a bats case that uses
`--file`.

**minor 3: `tests/rules-split.bats` case 1 blocks every future edit of either file.**
It compares the current working-tree files against the pinned blob `51ea44c9a` and requires every
original line in exactly one file, with a hard-coded "208 of them bullets". The first legitimate
curation turns it red permanently: deleting one of the three DELETE duplicates, rewriting an
over-budget hook as the lint instructs, or dropping a stale rotor comment. It checks a one-time
migration, so check the migration commit instead. After the lead commits, compare the split
commit's two blobs against its parent (`git show <split>^:…` vs `<split>:…`), or skip when either
file differs from its blob at the split commit.

**minor 4: the de-indented resident bullet has no directory.** Its line is
`` - `narrated-verdict-is-indistinguishable-from-a-computed-one.md` — … ``. In the original, its
parent bullet said "Bodies under `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/`".
That parent is now in the situational file, so a reader of the resident file cannot locate the body
(C7.labels row 83 says it should link its mem path). The parent in the situational file now says
"six topic files" and lists five. The check script normalises whitespace, so adding the path breaks
nothing, but it does change the "original text".

**minor 5: pre-split writers keep appending to the resident file.** Sessions run their own worktree
copy of `cc-memory-rotate`, the drain hook and the nudge text, and the live layer lags until
converge. So the resident file will keep receiving routed lines for days after the land. Nothing
refuses them: the lint judges bullet shape, not which file a bullet is in. Optional ratchet: under
`--own-range`, flag a bullet added to the resident file (advisory, or blocking with an escape). The
resident header's line 17 ("then one hook here") also still says to append here, as the implementer
noted.

**minor 6: with the flag on, routed MEMORY lines disappear in every repo, with no pointer.**
`resolve_rules_dest`, the drain and the budget gate now create
`<any-project>/.claude/rules/agent-operating-lessons-situational.md`. The `**/` glob excludes that
file in every repo on the flagged account. Only claude-infrastructure's resident file tells a
session to grep it. The migration comment says this is intended, but it changes the rotor's premise
("a routed line is on a different SURFACE, not a colder one") for the A/B arm. In other repos,
routed rules on the flagged account are effectively demoted. Either state this in the operator step
text, or make the rotor's create-header for a new situational file say what it is and to grep it.

**minor 7: the new orphan-skip branch in promote-memory has no test.** No case proves that a topic
cited only in the situational file is left out of the orphan corpus. Add one fixture: set
`CC_JEV_RULES_SIT_FILE` to a file citing `orph1.md` and check that the orphan count drops by one.

**minor 8: scope.** `commands/compact-memory.md` is outside the literal owned list. The implementer
disclosed it, and the F7 review (minor 8) already notes that two items edited its description. The
lead should keep one description. This one drops "human-gated" and the stripped-and-trimmed unit
wording.

**minor 9: flag default.** With the flag off, nothing in any `settings.json` changes, and both
files load (the `/context` above), so the flag defaults to current behaviour. The migration is
correctly c10. Its verify oracle is invariant across config dirs (bats case 2) and it keeps sibling
keys (case 3). `~/.claude-tertiary/settings.json` is a real file, not a symlink, so the edit stays
on one account.
