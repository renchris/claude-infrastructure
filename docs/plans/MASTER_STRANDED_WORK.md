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

## S5 · the other 23 — what they actually are

The re-land rows were one mechanism seen 25 times. **The remaining members are not.** The semantic
grouping joined genuinely distinct engineering to this condition, so the second half of this effort
is ordinary work with ordinary reading lists — expect no sweep to close it.

They partition three ways, and the split is what a successor needs:

| | n | Disposition |
|---|---|---|
| **Agent work** | ~11 | drive it: a fix, a test, a land |
| **Operator-owned** | 4 | a credential, a GUI action, or a spend — file the reason, never fake the close |
| **The wave row itself** | 1 | `0328e7cc5742`, closes last |

**Driven so far** (each verified by content on trunk, never by an exit code):

- `417fbab3c317` — the shared checkout's `branch.main.merge` was still the leaked fixture value
  `refs/heads/up`, so `main@{u}` did not resolve at all. Repaired; the two lag readings now AGREE
  (`main@{u}..main` = `origin/main..main` = 0) where the incident had the sensor reading 2 against a
  true 6. The orphan fixture branch `up` (`730e5c7a0`, author `t <t@t>`, subject `b`) is deleted —
  it was the leak's source, and both preconditions were re-verified before the delete.
- `7176bda11a8d` — `recycle_engaged()`'s ROW-CHANGE arm probed a FLAT `$pdir/$sid.jsonl`; Claude
  Code writes transcripts one level down. All 835 real transcripts are nested and zero are flat, so
  the arm was dead in production **while passing its own suite** — every case in
  `tests/handoff-recycle-engagement.bats` fixtures transcripts flat, i.e. in the layout the bug
  assumes. Fixed + two cases pinning the real layout.
- `87822050d5e5` (`c4df09dd5`) — `/compact-memory`'s E3 exclusion asked ONE grep about three paths
  and read it through `||`; an unreadable operand exits 2 **even when another operand matched**, so
  every residual file printed as ORPHAN (13 false ones on reso). Re-measured, the defect is
  environment-dependent and that is why it survived: `/usr/bin/grep` returns 0 here, the grep an
  interactive session resolves returns 2 — correct for a script, broken for the reader pasting it,
  and a `/command` is run by the reader.
- `0db2c692efb7` — closed as a STALE BLOCK, not as work: the hook is on trunk, its live symlink
  resolves, migration `0005` is in `applied/`, and `jq .hooks.Stop[].hooks[].command` finds it in
  both live `settings.json` files. **Re-verify a park before working it** — this one had been done
  for days.
- `85bb7476f57f` / `6eebbe61881a` — both closed by re-derivation from content after their refs went
  missing. A gone ref is a lookup miss, and in all three cases here the work had landed.

**Still open** — `ed6d0716caa7` (L1 death-watch has no watch-file producer) · `dc426ee8df11`
(WORKTREE MANAGEMENT V2) · `55065a61b31c` (cc-cloud trunk refusal, written, verification blocked on
a bats admission slot) · `635eb82ef810` (cc-version-audit 2.1.224) · `f76e7d78aaac` (engagement
oracle has ONE consumer and two spawners that ignore it) · `8ad4b02602dc` (no wake path for an idle
headless session) · `6ab41e312a13` (vendor `reso-keepalive`; a reso land, so read reso's own
`CLAUDE.md` first) · `d4c091a86fb8` (zshrc `_cc_sync_account` fails open at 10 sites) · plus the two
stranded-sweep rows in S3.

🚨 **The box is the binding constraint, not the work.** `cc-bats` refuses at
`CC_BATS_MAX_ROOTS=2` when 1-min load/core ≥ 2.0, and it refuses as a **DEFERRAL — nothing ran,
nothing was verified**, which is the honest shape but means a verification cannot be scheduled by
wanting it. Four in-session teammates plus a sibling wave saturated every slot for the whole middle
of this session. **Do not answer a load-gated queue by adding workers**: the parallelism that makes
a wave fast is exactly what makes its own verifications undispatchable. Size the team to the *test*
slots, not to the task list. Never reach for the printed `CC_BATS_MAX_ROOTS=0` override to get a
verdict — the gate is measuring a real machine.

### 🚨 The content oracle inherited this effort's own bug — measured 2026-08-12

`scripts/land-content-verify.sh` + its falsifier wiring at `ship-land.sh:845` landed as the S3
deliverable: the filer now attaches a probe that RETRACTS a `re-land …` row once the pinned ref's
content reaches trunk. Cross-checked against the same 25-row census that motivated it, it disagrees
on three of five:

| ref | oracle | census |
|---|---|---|
| `845d18c17` | ON-TRUNK | landed ✓ |
| `0a131da73` | HOLDS-CONTENT | **landed** ✗ |
| `3a54808af` | HOLDS-CONTENT | **landed** ✗ |
| `8c2416e03` | HOLDS-CONTENT | **landed** ✗ |
| `fefa49b05` | HOLDS-CONTENT | held ✓ |

**It is right about the bytes and wrong about the question.** For `0a131da73` it names one path and
one line — `if [ -f "$pdir/$newsid.jsonl" ] && assistant_turn_in …` — which is *the bug this session
deleted* (replaced by the nested-layout fix, `12343c527`). The oracle reports our own improvement as
"content trunk lacks". `8c2416e03` (22 lines of `handoff-fire.sh`) and `3a54808af` are the same
shape.

**A falsifier that cannot fire is worse than none**, and this one cannot: it retracts on exit 0, and
a ref whose region trunk later REWROTE can never again reach exit 0. So exactly the rows it exists
to close stay open forever, and the population still grows. That is the inert-mechanism class —
landed, wired, and changing nothing.

The missing distinction is **trunk LACKS this** vs **trunk REWROTE this**, and a line-subset test
cannot see it. Worse, the gap *widens with age*, which is precisely the population being aimed at: a
1-day-old ref looks stranded, a 5-day-old one certainly does. A cheap discriminator that needs no
judgment — **did trunk's history touch that path AFTER the ref's commit?**
(`git rev-list --count <ref>..origin/main -- <path>`). Newer commits on the path ⇒ a line-level
difference is supersession, not loss; no commits since ⇒ the missing lines are a genuine loss. Exit
2 must stay reachable and distinct when the arm cannot decide.

**The general lesson, which outlives this file:** every instrument in this effort failed by
answering a *narrower* question than the one asked, and each new instrument inherited the flaw one
level up — count → "is the sha there"; patch-id → "is this exact patch there"; line-subset → "are
these exact bytes there". The question is always *"did the VALUE reach trunk"*, and supersession is
value reaching trunk **and then being improved**. Any successor oracle must be tested against a ref
trunk deliberately rewrote, or it will re-learn this the same way.

### In flight at the succession point — what a successor must collect

Branches, all committed; verify each BY CONTENT on `origin/main`, then close the row named:

**RESOLVED as of the recycle** — this table is kept because the *shape* of the seam is the reusable
part, but every row below is settled except the last two:

| Branch | Row | Final state |
|---|---|---|
| `w4/cc-cloud-trunk-refusal` | `55065a61b31c` | ✅ **landed + closed**, 26/26, D1/D3 red-proved |
| `w4/keepalive-vendor` | `6ab41e312a13` | ✅ landed — **row still OPEN on purpose**, see below |
| `w4/s3-content-oracle` | S3 / wave row | ✅ landed, then **re-landed by the lead** with the supersession fix |
| `w4/s3-sweep-fix` | `fd517a5863cc`, `634ecdccbc55` | ❌ produced nothing; teammate stood down. Triage above is the lead's own |
| `w4/s5-rbw-shim` | `475a87e801bf` | ✅ **landed + closed** (`b6ac4f6ed`), 31/31 standalone |
| `w4/s5-gc-franchise` | `6cab0ab3cb2f` | ⏳ **untouched at `48850a3b2`** — teammate never rebased; 8 commits still stranded |

🚨 **`6ab41e312a13` is landed but NOT closed, and that is the point.** `bin/reso-keepalive` and its
suite are on trunk, but **`tests/reso-keepalive.bats` has never actually run.** The land's smoke
phase GATE-KILLED it — `exit 124`, `ZERO 'not ok'`, printed as *"It is NOT a red and NOT evidence
about your tree"* — and the land proceeded anyway, which is correct behaviour and exactly why **a
green land is not a green suite**. Standalone runs were deferred for 25+ minutes at load 22. Run
`bats tests/reso-keepalive.bats` and close the row on THAT, never on the land log.

**Three of four teammates produced nothing** and were stood down with structured `shutdown_request`s
after ~40–90 min of clean worktrees and no replies. The one that delivered (`s5-rbw-shim`) delivered
superbly — and still had to have its land taken over. **Read that as a sizing lesson, not a staffing
one:** on a box that admits two concurrent bats roots, a five-agent wave cannot verify itself, and
every extra agent lengthens the queue its siblings are already stuck in.

`w4/keepalive-vendor` carries an **unrun suite** and says so in its commit body. Do not close
`6ab41e312a13` until `tests/reso-keepalive.bats` has actually run — a commit body is a claim, not a
verdict, and this whole effort exists because a claim was mistaken for one.

### Verified triage for the rows this session did not finish

Measured on trunk 2026-08-12, so the next agent starts from facts rather than re-deriving them. Each
is agent work; none is operator-gated.

**`634ecdccbc55` — `scripts/stranded-sweep.sh` exonerates the land gate.** Two independent defects,
both confirmed:

- **The swallowed `git cherry` (lines ~130-132).** The per-branch loop is fed by
  `done <<EOF\n$(git cherry "$REMOTE_TRUNK" "$branch" 2>/dev/null)\nEOF`. The rc is discarded and
  stderr suppressed, so an instrument failure — unborn ref, no merge base, corrupt ref — makes the
  loop read EMPTY and the branch is certified CLEAN. A failure of the instrument is reported as a
  clean verdict about the subject. Worse, **`git cherry` is the wrong oracle here at all**: measured
  over this very population it was wrong in BOTH directions (cleared 3 refs still holding residue,
  convicted `0a131da73` whose every path was blob-identical). Keep it as a cheap pre-filter; take
  the verdict from `scripts/land-content-verify.sh`, which now exists and handles supersession.
- **`--mine` keys on a trailer nothing writes.** `mine_match()` matches a `Session-Id` or
  `Land-Session` git trailer. **Measured: 0 of the last 500 commits on `origin/main` carry either.**
  `ship-land.sh:121` is a comment *claiming* commits carry `Session-Id`; nothing in the tree writes
  one. So `--mine` can only ever report 0 — the sweep's one damping mechanism is dead on arrival,
  which is why the undamped verdict is all anyone sees. **The identity that DOES exist** is the
  failed-land ref the filer already writes, `refs/land/failed/<utcstamp>-<sid>-<branch>`
  (`ship-land.sh:806-812`): a sha is MINE if a `refs/land/failed/*-<MINE>-*` ref reaches it.

**`fd517a5863cc` — the sweep's `review` verdict fires on 955/989 lands.** An alarm at 97% carries
almost no bits; this session watched it fire on its own land over 69 peer commits across 675
branches, none of them the lander's. It is the same defect as the row above seen from the other end:
the damping arm (`--mine`) is dead, so everything falls through to the undamped wall. **Fix them
together** — a working `--mine` is most of the damping, and the residual un-`--mine` verdict should
degrade to a count rather than a per-commit wall with recovery recipes for peer WIP the sweep's own
text tells the reader never to cherry-pick.

**`ed6d0716caa7` — L1 death-watch has no watch-file producer.** Premise fully corroborated: every
reference to `lead-deathwatch.sh --watch` in the tree is a SPECIFICATION, never a writer —
`migrations/0004-lead-deathwatch-l1-activation.sh` (staged, step 2 BLOCKED),
`docs/NEVER-WAIT-ACTIVATION.md` (a template "you adapt + install"), and two 2026-07-18 audit rows.
Nothing writes a file in `lead-deathwatch.sh:31`'s format (`pid⇥start⇥label⇥waiter⇥worktree`);
`~/.claude/deathwatch` holds only fixtures the 2026-07-15 `--selftest` left behind. This is the
`spec-named-mechanism-may-be-prose-only` class. **The split:** *(a) agent* — derive the watch-file
from the P8 registry (`~/.claude/cc-registry/*.json`) on a refresh cadence, plus a suite; *(b)
operator* — the launchd load. 🚨 **Do not invert that order.** Migration 0004's own header says why:
a launchd job installed today arms kqueue on an EMPTY watch-list forever and reports a perfectly
healthy heartbeat while watching nothing — a watcher whose liveness proves nothing about its
coverage, which is the exact failure L1-e exists to prevent, reintroduced one level up.
**Completeness of the DETECTOR is not the same claim as COVERAGE of the fleet**, and
`scripts/wait-safety-gate.sh` being GREEN only asserts the first.

⚠️ **`cc-backlog add --condition <slug>` cannot file a NEW row into an existing group** — the flag
re-keys the id to `project+condition`, so `add` returns the group row's id early and the title is
discarded. That is why this triage is in the plan and not in three new rows. File with `add` first,
then `link --condition`.

### S3 acceptance — the retractor covers 14 of 23, and that is the honest claim

The DoD asks for a generator fix "so the population stops growing". Measured, not asserted: the
fixed oracle was run over **every** re-land ref this session closed, as an independent instrument
against the hand census.

| | n | Meaning |
|---|---|---|
| oracle agrees (ON-TRUNK) | **14** | the falsifier retracts these automatically, with no human in the loop |
| oracle abstains (exit 1) | **9** | it cannot PROVE the value landed; the row stays open pending a read |
| oracle wrong | **0** | — |

**The 9 abstentions are correct behaviour, not residual bug.** Spot-checked the worst of them,
`f3bb2ac65` (20 ref-only lines): trunk carries every identifier that commit introduced —
`BAND`×9, `taskpolicy`×14, `ProcessType`×5, `utility`×21 — and the ref-only lines are the
**pre-`lstart` mutex** trunk deliberately replaced with the locale-canonical `proc_lstart` version.
The value landed; the exact blob never existed on trunk, so blob-history cannot prove it. Exit 1
means *do not retract*, which is the safe answer where only a semantic read settles it.

So the claim to make is narrow and true: **the filer's rows now auto-retract for the majority and
fail safe for the rest.** It does not close the loop unaided, and saying it did would be the same
overclaim — a mechanism reported as complete because it is installed — that this whole effort
exists to catch. The residue is *bounded and shrinking*: the more trunk diverges from a stranded
ref, the more likely blob-history finds the ref's own blob in the path's past, so the arm gets
STRONGER with age, unlike every instrument it replaced.

**Do not chase the last 9 by loosening the test.** The rejected alternative — "did trunk touch this
path after the ref?" — would have retracted all 23 including any genuine loss among them. For a
falsifier that DESTROYS a row, over-forgiving costs work and under-forgiving costs noise; take the
error on the noise side, always.

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
- **2026-08-12 — W4 drain session, part 2: S3 + part of S5, then RECYCLED (not finished).** Live
  members **50 → 15**. Landed and content-verified this session, beyond the S1/S2 work above:
  `12343c527` (recycle's ROW-CHANGE arm read a transcript path Claude Code never writes — dead in
  production while passing its own suite, because every case fixtured the layout the bug assumed) ·
  `c4df09dd5` (`/compact-memory`'s orphan sweep called every residual file an orphan on any project
  missing an E3 path; environment-dependent, which is why it survived) · the cc-cloud trunk refusal
  (`55065a61b31c`) · `8eddb12bf` (`bin/reso-keepalive`, the half of `410f920c` that never landed —
  its untracked copy had rotted into a nudger aimed at twelve worktrees that no longer exist) ·
  `scripts/land-content-verify.sh` + the `ship-land.sh:845` falsifier, then its supersession fix ·
  `b6ac4f6ed` (the read-before-write parity shim, untracked since Aug 5).
  **The two findings that outlive the rows:** (1) the guard the shim restores is OFF in **16 of 16**
  account × model-bucket cells — proven live by overwriting an unread file successfully, where both
  prior sources claimed one bucket or one account; it is landed but INERT until wired, filed as
  operator step `504d0bc2fe50`. (2) The S3 falsifier's coverage is **14 of 23**, measured by auditing
  this session's own closes with it — see § S3 acceptance. **Recycled rather than finished**: 15 rows
  remain, all triaged above, and the box (cc-bats deferring at load 22) not context was the binding
  constraint for the last hour.
