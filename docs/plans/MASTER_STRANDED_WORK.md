---
status: open
---

# MASTER: stranded work — value that reached a branch and never reached trunk

**Condition key:** `master-stranded-work` · **Live members 2026-08-12 (measured after the apply):** 50 (34 blocked · 16 open)
**Inventory (run this, never trust the count above):**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-stranded-work" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort and not 87.** Every member is the same mechanism seen once per branch:
`ship-land` exited 5, 6 or 143, its auto-recovery did not finish the job, and a commit was left where
only this machine can see it. 62 commits across 21 abandoned wave branches were measured
content-stranded on 2026-08-10 (CLOSE_INTEGRITY recon). One sweep session with a roadmap re-lands
them; 87 dispatches would each re-derive the same sweep.

🚨 **The mechanical fold was RIGHT to refuse this shape and this plan is what makes it safe.** Its
largest sha-keyed cluster of 14 was nine different stranded worktrees, and joining them with no
roadmap behind them would have refused dispatch on all nine while delivering nothing. The join is
honest here *because* this file exists: the group's one session sweeps every member.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| ~~**S1 · census**~~ **DONE** | **L** (was S) | per-branch verdict BY CONTENT | — |
| ~~**S2 · re-land**~~ **DONE** | **L** (was S) | `b9fc0dcb3` — the population's only genuine loss | S1 |
| **S3 · the generator** | **T** (one teammate) | the filer/sweep fix + a red-proved test | S1 (its measurement) |
| ~~**S4 · close by content**~~ **DONE for the 25 re-land rows** | **L** | rows closed against per-path blob identity | S2 |
| **S5 · the other 23** | **L**, teammates per item | the non-re-land members, each driven or reason-named | — |

**S1/S2/S4 ran lead-inline, not as dispatched sessions** — a revision of this table's own default,
and the reason is the census result: 24 of 25 rows needed *adjudication*, not implementation. There
was no code to write for them, and a dispatched session per row would have re-derived the same three
git oracles 25 times. The one row that did need a commit took a single Edit.

**S3 is a teammate** (T): it writes code in files this lead is not otherwise touching
(`scripts/stranded-sweep.sh`, the ship-land filer), and its brief is small enough that its report
does not threaten the lead's window.

**Lead context budget:** hold ≥50% for adjudication. **Succession point:** between S3 and S5 — the
census and the generator are one context; the 23 heterogeneous items are another, and each of them
carries its own reading list.

## Sub-waves

### S1 · Census — by CONTENT, never by commit count
`git rev-list origin/main..<branch>` reads 0 after a sibling rebase and proves nothing; a count is
also blind to staged and untracked bytes. Per candidate: `git ls-tree origin/main -- <paths>` plus
`git diff origin/main..<branch> --stat`, and for a live worktree also `git status --porcelain`.
Emit one verdict per branch: `LANDED` (close the row) · `HOLDS-CONTENT` (S2) · `EMPTY` (dispose).

### S2 · Re-land — serialised, smallest diff first
`git rerere` is enabled globally, so repeated same-hunk conflicts auto-resolve across branches. Land
via `scripts/ship-land.sh` only; never a bare `git push`. Rebase onto fresh `origin/main` per branch,
`--ff-only` merge, gate green, then verify BY CONTENT before closing the row.

### S3 · The generator — why the recovery stops short
Every row's own title names the exit code. Exit 6 dominates; 143 is SIGTERM (a signal-kill, which
`ship-land` currently misreports as GATE RED — see `master-verification-integrity`, and do not fix
it twice). The deliverable is the reason the auto-recovery leaves a branch behind, plus the fix, plus
a test that red-proves it.

### S4 · Close by content, dispose the rest
`worktree-gc --dispose-landed-dirt` writes NO disposal record today (a member of
`master-fleet-footprint` — coordinate, do not duplicate). Close each row with
`cc-backlog done <id> --evidence "landed <sha>, verified by content"`.

## S1/S2 outcome — 24 of the 25 re-land rows were FALSE, and that IS the S3 finding

Measured 2026-08-12 by the W4 drain session against `origin/main a9a268e28`→`53caadb3b`. Every one of
the 25 `re-land …` rows is now closed. Exactly **one** held content trunk lacked.

| Verdict | n | What it means |
|---|---|---|
| **LANDED-BY-CONTENT** | 21 | the content reached trunk by another route; the row recorded an exit code |
| **FALSE MEMBER** | 2 | the row names a synthetic ship-land repro sandbox, not this repo |
| **RESIDUE, re-landed** | 1 | `2d5bd0a56d97` → `b9fc0dcb3` (the only genuine loss in the population) |
| **SUPERSEDED-IN-PART** | 1 | counted in the 21; its first half landed via a sibling sha, second half was the residue above |

**Three instruments, and only one of them is the arbiter.** They disagreed in *both* directions, so
the DoD's "verify by CONTENT" is not a style preference — it is the only one that was ever right:

- `git rev-list --count origin/main..<ref>` — the instrument that stranded the population. Blind to
  a land under a different sha.
- `git diff origin/main...<ref>` — **over-reports**. Non-empty for 17 refs; 13 of those were fully
  landed. A ref whose patch landed under a new sha still diffs against the old merge-base.
- `git cherry origin/main <ref>` (patch-id) — **wrong in both directions**. It cleared 7 refs of
  which 3 still held residue, and it convicted `0a131da73` (`f9857dc67e82`) as unlanded when every
  path was blob-identical to trunk. Context drift moves a patch-id; it does not move content.
- **`git rev-parse <ref>:<path>` vs `origin/main:<path>`, per path** — the arbiter. A ref is landed
  iff every path it touches has ZERO ref-only lines. This is what closed all 25.

**A rebase is a second content oracle, and a cheap one.** `git rebase origin/main` reports
`skipped previously applied commit` and leaves `rev-list --count = 0` for a ref whose work is on
trunk. Three refs (`ef8bfc876c3c`, `7dddf341f72e`, `90defa63861d` — 13 commits between them) closed
on that alone.

🚨 **Landing a "stranded" ref can REGRESS trunk, and four of these would have.** The rows are 1–2
days old and trunk moved underneath them; what looks like residue is usually the OLDER draft of a
line trunk has since rewritten. Re-landing `4f382708b` would have reverted postland-verify's mutex
to a pre-`proc_lstart` form (losing the C33 locale fix); `d8495994f` would have reverted
`8d7064bc9`'s scoped conservation assertion back to the store-wide one; `f796f090f` and `4cd6b7815`
would each have reintroduced a **vacuous** bats assertion (`grep -q X && false || true` and a bare
`! … grep`) in place of the `|| false` form trunk now carries. *Verify by content **before** you
rebase — the sweep's default action is not the safe one.*

### The generator, named (S3 input)
The filer keys a row on **ship-land's exit code**, and nothing ever re-asks by content. So the
population measures *land-gate failures*, not *stranded value* — at a **96% false-positive rate**
measured here (24/25). Two independent confirmations sit in this same effort's own membership:
`fd517a5863cc` (stranded-sweep's `review` verdict fires on 955/989 lands — an always-alarm) and
`634ecdccbc55` (the sweep's `git cherry` is swallowed, and `--mine` keys on a `Session-Id` trailer
nothing writes). **Same defect, three sightings**: the sweep and the filer both trust a signal that
is not content, and neither closes the loop afterwards.

Two smaller generator facts fell out of the census:
- **The filer fires from inside ship-land's own test repros.** `aedb1a8337a0` and `93e7e347db98`
  name `/private/var/…/tmp.*/work` sandboxes that are their own git repos (remote
  `tmp.*/origin.git`, history `base` + `feat: broken`). The exit-7 one is the non-fast-forward case
  its repro was *built* to produce. A filer that cannot tell the subject repo from a fixture mints
  rows nobody can ever land.
- **The same failed land files twice.** `19692d4032b5` and `9cd25257a847` are the same change
  (`6573023ec` / `59c03d976`), filed 10 minutes apart from two different pane sids.

## Definition of done
Every member row is either closed against a content-verified land or carries a named reason it
cannot be landed. `git ls-tree origin/main` proves each claim. The exit-5/6/143 generator has a
landed fix with a red-proved test, so the population stops growing.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 87 rows joined to this
  condition by `scripts/backlog-consolidation/group.py`; 9 of them by the 2026-08-09 triage wave's
  own human adjudication (`link.py --dir` replay). Not yet worked.
- **2026-08-12 — W4 drain session: S1 + S2 DONE.** Condition claimed as ONE lease (`cc-backlog claim
  0328e7cc5742`, which carries `condition=master-stranded-work`, so all 50 members are covered by
  one slot — the economics this wave exists to prove). **All 25 `re-land …` rows closed**, live
  members 50 → 23. One genuine loss recovered and landed: `b9fc0dcb3`. Outcome table, the
  three-instrument disagreement, the four refs whose re-land would have REGRESSED trunk, and the
  named generator are in § S1/S2 outcome above. Escalation packets `shipland-esc-41605a11` and
  `shipland-esc-55d3b105` actioned as resolved-by-content (both branches' work is on trunk; one
  artifact was later removed deliberately by `e9be66ebe`). **Remaining 23 rows are NOT re-land
  rows** — they are distinct engineering items the semantic grouping joined to this condition, so
  the effort's second half is ordinary work, not a sweep.
