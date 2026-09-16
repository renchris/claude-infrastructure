# claude-infrastructure — Project Memory

Project-only rules for THIS repo. Loaded as project memory (`./.claude/CLAUDE.md`, per CC docs) only
when working in `~/Development/claude-infrastructure`. NOT part of the global `~/.claude/CLAUDE.md`
core — kept here so a claude-infrastructure-specific safety rule never ships to every other project.

## Never commit or land in the shared checkout

`~/Development/claude-infrastructure` is the symlink source for `~/.claude` and frequently sits on
another session's feature branch. Committing there risks (a) landing onto a branch you did not
create, and (b) a concurrent `/ship` of that branch rebase-dropping your commit — incident
2026-07-11: `dfacccd` (limit-recover skill, 5 new files) silently dropped by a sibling land of
`feat/two-way-session-comms`; `git rev-list origin/main..HEAD` read 0 ('looks landed') while the
files were absent from main. Always work in a dedicated worktree, commit on your OWN branch, and
land via the project-local `/ship`. Verify landings by CONTENT (`git ls-tree origin/main --
<paths>`), never by count.

## Standing-land authorization (this repo only)

In THIS repo, work that is **complete + gate-green + committed on your own branch** lands via the
project-local `/ship` flow **without a fresh ask** — the 📦-offer/wait cycle is waived here
(operator standing directive 2026-07-18: identified net-positive work is finished, not offered;
Follow-On Gate F1-F4 in the global CLAUDE.md governs what qualifies). Why scoped here: parked
commits leave the LIVE `~/.claude` layer stale (this repo is its symlink/source), so
committed-not-landed is itself "work left on the table". The authorization is exclusively for the
fail-closed project-local `/ship` (landing lock + last-moment re-fetch + full gate + content-verify
+ stranded sweep) — never a bare `git push`. Global Git Safety is unchanged for every other repo.
After landing, sync the non-symlinked live copies (`~/.claude/CLAUDE.md` is a separate real file —
apply the same edits there; most of `skills/ hooks/ bin/ scripts/ commands/` are per-file symlinks
into the checkout and go live on the trunk fast-forward).

## Standing-converge authorization (this repo only)

Landing is the second-to-last step, not the last: `~/.claude` is a per-file symlink farm over THIS
checkout, so a landed commit runs nothing until the shared checkout fast-forwards. In THIS repo the
agent therefore converges its own just-landed, content-verified work **without a fresh ask** — the
same waiver § Standing-land gives the 📦 offer — and it does so on the **degraded tier**, which
relaxes the CLOCK and keeps the EVIDENCE:

```
CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh
```

🚨 **Never `--force`, and the difference is not stylistic.** `--force` takes trunk's tip regardless
of RED stamps and bypasses the T1/T1H/T2/T3 ladder outright; the degraded tier takes the newest
NOT-RED commit, still refuses a trunk that is red all the way down, still runs `install.sh` so
brand-new tracked files get their symlinks, and still banners + pages the unverified advance. Both
leave the live tree unstamped, so both make `deploy-parity-assert`'s verification leg say so —
measured 2026-09-15, a `--force` run reddened `tests/deploy-parity-live.bats` within the minute.
The degraded tier at least earns that state through the ladder. `--force` stays the OPERATOR's
escape hatch, for when the ladder itself is what is in the way.

**Not covered, because none of it is a clock:** a bare `git merge --ff-only` / `git pull --ff-only`
in the shared checkout (denied by `hooks/validate-bash.sh:1352`, and rightly — it advances FILES
while creating no symlinks, so every newly tracked file lands UNLINKED and silently does nothing),
`--bootstrap`, and any advance while the ladder reports T3/BLOCKED. A refusal about EVIDENCE is a
`⛔` to surface, never a knob to turn.

**Why it is safe to let the agent hold this.** The green-stamp producer emits ~0.17 greens/day
against a trunk moving ~63 commits/day, so T1 is structurally unreachable and *every* real advance
already comes through T2's absence-of-evidence door — the budget only spaces those out. An agent
converging after each of its own gate-green lands is the same order of frequency as the 6h clock it
replaces, and each advance is attributable to a land instead of to a timer. **Residual, stated
rather than hidden:** a converge carries every sibling commit below the target too, exactly as the
timer-driven one does, and it leaves the live tree unstamped until `postland-verify` catches up.
That was already true of T2; what changes is who decides when.

**The paired permission rule lives in `.claude/settings.json`**, and without it the agent is refused
at the tool call and falls back to the bare form (which waits out the budget honestly). Measured
2026-09-15 as a 2x2, one variable per cell: `bash deploy-live.sh` is ALLOWED for an agent both
dry-run and real — it ran twice unattended that day — while the `CC_DEPLOY_MAX_LAG_COMMITS=0`
prefix is allowed under `--dry-run` and DENIED for real. So the guard was never "agents may not
deploy"; it is the narrower and better "an agent may not alter the gating and then deploy", keyed
on the mutation rather than on the env var. This section plus that rule is the operator granting
exactly that one exception, in the open, rather than an agent widening it for itself — the grant
was given explicitly on 2026-09-15 after the agent refused to write it unasked.

## The global instructions live at `CLAUDE.global.md`, never at a root `CLAUDE.md`

The SSOT for `~/.claude/CLAUDE.md` is **`CLAUDE.global.md`** at this repo's root; `install.sh`
copies it out under the deployed name. Do **not** create or restore a root `CLAUDE.md` here: Claude
Code would load it as PROJECT memory on top of the byte-identical user-memory copy every session
already has, which is what made a session in this checkout load the same ~94 KB twice — ~83% of the
always-loaded budget, ~20.7K tokens per session of pure duplicate (backlog `c3647a090021`). Nothing
diverges when that happens, so no parity auditor can see it; `tests/deploy-parity.bats` pins the
absence instead. THIS file is the project-only memory and is not a duplicate — it stays.
