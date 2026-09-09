# W2-B6 — the settings.local.json permission prefix census

**ZERO prefixes recur across ≥3 distinct approval sets, so the promotion criterion this wave was
sent to apply is unsatisfiable on this population — REFUTED (94).** The "22 files" are not 22
populations: 14 of them carry an EMPTY `permissions.allow`, and 3 of the remaining 8 are
byte-identical copies of one 95-entry set, so the union of 302 raw entries collapses to **111
distinct entries across 6 distinct sets**. Every candidate that reached "≥3 files" reached it
because one file was copied three times. What survives the deduplication is a different and
smaller finding, stated below: **27 of 64 exact Bash approvals (42.2 %) are read-only by
construction** and should never have produced a prompt at all — an admission-gate defect, not a
permission-rule defect.

## The number

| quantity | value |
|---|---|
| files inspected | 22 (1 main checkout + 21 worktrees) |
| files with a non-empty `permissions.allow` | 8 |
| **distinct** non-empty allow sets (byte-identical sets collapsed) | **6** |
| raw allow entries across all 22 files | 302 |
| **distinct** allow entries (the union) | **111** — 191 of the 302 (63.2 %) are copy duplicates |
| Bash entries in the union | 98 |
| of those: wildcard / prefix rules (`x:*`, `x *`, `*`) | 34 |
| of those: **exact literals** | **64** |
| prefixes recurring across ≥3 **distinct sets** | **0** |
| prefixes recurring across ≥2 distinct sets | 2 (`pnpm design:gate`, `curl`) |
| exact literals that are **read-only by construction** | **27 / 64 = 42.2 %** |

The six distinct sets are `claude-infrastructure` (95 entries), and five worktree sets of 1, 2, 3,
3 and 8 entries. The 95-entry set is copied verbatim into `wt-lr-kitty-fire-verify` and
`wt-permission-harvest`; those two contribute no independent approvals.

## Method (re-runnable)

Throwaway prototype, described rather than committed (three ~40-line Python scripts in the session
scratchpad; the census is a one-shot audit, not an instrument anything re-runs). The whole result
reproduces from:

```
for f in ~/Development/claude-infrastructure/.claude/settings.local.json \
         ~/Development/.worktrees/*/.claude/settings.local.json; do
  jq -r '.permissions.allow|sort|join(" ")' "$f" | md5 -q; done | sort | uniq -c | sort -rn
```

which prints the set-fingerprint histogram — `14 d41d8cd9…` (empty), `3 592f7368…` (the copy trio),
and five singletons. Classification then runs over the *union* of entries: an entry is a wildcard if
its argument ends in `:*` or ` *` or is exactly `*`; otherwise it is an exact literal. Exact literals
normalise to their first token (`basename`d), to first-two-tokens for the `git`/`pnpm`/`npm`/`python3`/
`sysctl` family, with a leading `VAR=value` assignment and a leading `timeout N` stripped first, and
`git -C <path>` collapsed to its sub-verb (`git -C … fetch` → `git fetch`).

## Population and every excluded stratum

- **Included:** the `permissions.allow` array of all 22 `settings.local.json` files reachable at
  `~/Development/claude-infrastructure/.claude/` and `~/Development/.worktrees/*/.claude/`.
- **Excluded — `ask` and `deny`:** all 22 files carry zero entries in both. Nothing to census, and
  the brief forbids touching them regardless.
- **Excluded — the user layer** (`~/.claude/settings.json`, 339 allow entries) and the **committed
  project layer** (`.claude/settings.json`, 35 entries). They are the *coverage* reference, not the
  population: a promotion candidate already covered there is not a candidate.
- **Excluded — deleted worktrees.** This is the census's largest blind stratum and it is
  unrecoverable: `worktree-gc` deletes a worktree's gitignored `settings.local.json` with the
  worktree, so approvals granted in any worktree reaped before 2026-09-09 are absent by
  construction. The 14 empty files are the same effect caught mid-life. **This census therefore
  measures the approvals that SURVIVED, not the approvals that were GRANTED**, and the survivors
  are dominated by the one location that is never reaped (the main checkout).
- **Excluded — non-Bash entries** (13 in the union: 9 `Read`, 3 `WebFetch`, 1 `Skill`, 1 `Agent`)
  from the prefix arithmetic. They are path/domain scopes, not command prefixes.

## Verdict for W3 — REFUTED (94)

The decision rule was: *candidates in the read-only / repo-scoped classes with ≥3 files and zero
shell-escape widening cross 90.* Applied to distinct sets rather than to file copies, the candidate
list is **empty**, so there is no committed-settings diff for W3 to prepare and no operator read to
ask for. Conviction 94 rather than higher because the deleted-worktree stratum above is
unmeasurable: a population that included reaped worktrees could in principle contain a recurring
prefix this one cannot see. It could not, however, rescue the criterion as written — see the fail
direction.

Under the naive file-count reading the answer inverts, which is exactly why this row is being
refuted rather than answered: five prefixes reach ≥3 *files* — `claude-accounts` (8 distinct exact
approvals, read-only), `awk` (3, read-only), `curl` (3, all `http://localhost:*` health probes),
`rm` (3, all `rm -rf …/__pycache__`), `pnpm design:gate` (3, repo-scoped write) — and they cover
20 of the 64 exact approvals (31.2 %). Every one of those file counts is the copy trio or two
copies of it. Promoting on that basis would widen the committed project settings on the strength of
`cp`.

## The residual that IS real — and it is not a permissions finding

**27 of the 64 exact literals (42.2 %) are read-only by construction**: `sysctl` ×5, `vm_stat`,
`memory_pressure`, `pmset -g therm`, `kitty --version`, `~/.local/bin/codex --version`, `mdls`,
`osascript -e 'id of application "iTerm"'`, `sort -k2 -rn`, `awk` ×3, `shellcheck`, the
`claude-accounts` read flags (`--json`, `--login-status`, `--relogin-info`, `--fresh`) ×8, and the
`git -C … status|log|rev-list|fetch --quiet` reads. Each of these consumed a human approval for a
command that cannot mutate anything. That is the admission gate prompting on a read, and it is a
different defect from the one this wave was sent to measure — the remedy is a read-only classifier
at the gate, not a prefix in `settings.json`. **Not filed as a backlog row: it is already the
subject of decision packet `1df4081249d2` (who answers a permission prompt while you are asleep),
whose shadow-mode option covers exactly this class.**

A second observation, offered without a remedy: 15 of the 64 exact literals are already covered by
a wildcard present in the *union* — most of them `git -C …` commands standing beside a bare
`Bash(git *)` in the 95-entry set. Within a single file that would be redundancy; across files it is
the fragmentation the empty-worktree stratum predicts.

## Fail direction — what a wrong reading looks like

The wrong reading is the one this census started with and had to correct: **counting FILES rather
than DISTINCT SETS.** `settings.local.json` is copied into a new worktree at provisioning, so file
multiplicity is a function of how many worktrees were provisioned from a checkout that already had
approvals — never of how often a human approved the command. The tell is cheap and should be run
before any future permission census: the set-fingerprint histogram above. If it shows one
fingerprint at multiplicity *k*, then every entry in that set carries a free count of *k* and any
"≥N files" threshold below *k* is satisfied by copying alone.

The second wrong reading is classifying `Bash(git *)` and `Bash(git checkout *)` as exact literals.
They end in ` *`, not `:*`, so a classifier keyed only on the documented `:*` prefix form counts
them as literals — which understates existing wildcard coverage by 10 entries here and would have
scored `git` as a fresh promotion candidate that is in fact already granted in full.
