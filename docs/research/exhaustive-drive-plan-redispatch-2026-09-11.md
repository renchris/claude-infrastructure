# EXHAUSTIVE DRIVE re-dispatched 1 h 13 m after its own close landed — verdict: ALREADY CURED

**Date:** 2026-09-11 · **Item:** cc-backlog `1dd6fbb6766c` (`plan-open`, minted from
`docs/plans/EXHAUSTIVE_DRIVE_2026-09-08.md` § H1) · **Venue:** cloud VM, branch
`claude/fire-20260911T163500Z-39093-1` · **Tree:** `git rev-list --count HEAD..origin/main` = **0**,
after `git fetch --unshallow` (the checkout arrived shallow at depth 50; every trunk read below is a
read of full trunk, not of a 50-commit horizon).

---

## 1. Verdict

**The row is cured and needs no code.** The cure is `f09640f51d1bb79a08f76b8142b3d62d529eeac5`, which
is **trunk's tip**:

```
$ git merge-base --is-ancestor f09640f51d1bb79a08f76b8142b3d62d529eeac5 origin/main ; echo $?
0
$ git rev-list --count f09640f..origin/main
0
$ git log -1 --format='%cd' --date=format-local:'%Y-%m-%dT%H:%M:%SZ' f09640f     # TZ=UTC
2026-09-11T15:21:31Z
```

It carries `status: complete` in the plan's frontmatter and a `**Status**:` line on every level-≥2
heading, and it answers the item's own stored falsifier affirmatively:

```
$ scripts/plan-phase-scan.sh docs/plans/EXHAUSTIVE_DRIVE_2026-09-08.md --falsify
FALSIFIED           rc=0
$ scripts/find-plan.sh --status docs/plans/EXHAUSTIVE_DRIVE_2026-09-08.md
complete            rc=0
$ scripts/plan-phase-scan.sh docs/plans/EXHAUSTIVE_DRIVE_2026-09-08.md   # summary
sections 16 · done 16 · in_progress 0 · pending 0
```

`FALSIFIED` / rc 0 is the only load-bearing answer under the falsifier contract. Nothing in this
session re-derived the close; the close was read back through the consumers that dispatch on it.

**No diff is owed.** This document is the deliverable.

---

## 2. So why was it dispatched at 16:35Z, 1 h 13 m 29 s after the close landed?

The brief's own PREMISE CHECK carries the answer, and it disagrees with trunk:

| | brief's probe (desk, 16:35:00Z) | trunk (this VM) |
|---|---|---|
| `--falsify` | silent, **rc 1** (NOT REFUTED) | `FALSIFIED`, **rc 0** |
| sections | **12 of 15** not DONE | **0 of 16** not DONE |
| `find-plan --status` | (implied `open`) | `complete` |

Two candidates: a stale **script** (the probe runs `$HOME/.claude/scripts/plan-phase-scan.sh`, the
live-layer copy) or a stale **plan file** (the probe's argument is the desk's shared checkout,
`/Users/chrisren/Development/claude-infrastructure/docs/plans/…`). A 2×2 separates them, one
variable at a time. The "09-08 vintage" script arm is the copy that the firing dispatcher's own
blob dates to — `git show 32b64cfe:scripts/{plan-phase-scan,find-plan}.sh`.

| script vintage | plan file | `--falsify` |
|---|---|---|
| trunk | trunk (`origin/main:…`) | `FALSIFIED` rc 0 |
| trunk | pre-cure (`f09640f^:…`) | silent **rc 1** |
| 09-08 (dispatcher vintage) | trunk | `FALSIFIED` rc 0 |
| 09-08 (dispatcher vintage) | pre-cure (`f09640f^:…`) | silent **rc 1** |

**The script arm is dead: both vintages answer `FALSIFIED` on trunk's file.** The verdict moves only
with the FILE. ⇒ the desk read a **pre-`f09640f` copy of the plan**.

### 2.1 The fingerprint, which makes this an identification rather than an inference

Running the scanner on `f09640f^`'s plan does not merely produce *a* non-DONE result — it reproduces
the brief's snapshot exactly:

- pre-cure totals: **15 sections**, 2 DONE, 13 not DONE. The 13th is the level-1 H1, which the
  falsifier excludes by design (its own header: *"LEVEL 1 IS EXCLUDED … counting it would make every
  plan permanently unfalsifiable"*). **12 of 15** — the brief's number, to the digit.
- the brief lists the first 8 PENDING headings. Against the pre-cure scan they match **verbatim and
  in order**: Phase 0 · The operator's goal · What the lead measured before firing W0 · Lead probes
  while W0 ran · Waves — filled from SYNTHESIS.md · Fires · W2 returns · W3 returns.
- the 2 pre-cure DONE sections are `W0` and `Harvest`, both `status_source: heading` on
  `commit_hashes` `["928fd86"]` and `["093e40f"]` — i.e. DONE **by accident**, off a workflow id and
  a session id that satisfy the scanner's "7+ hex in the heading" rule. That independently confirms
  the claim the cure's own § Definition of done makes about those two sections.

---

## 3. Dispatcher vintage — the brief's own check, answered, and the bound it buys

```
brief cc-dispatch blob = 9109de61dc7add48cd94809d54e591af0bfe9021
trunk cc-dispatch blob = 27c461a5f1a4de551fdfbe2a619e28e696c13aaa
```

**DIFFERENT — the firing dispatcher is BEHIND trunk.** This is a convergence fact about the deploy
layer, not a defect in the cure. It is also a *measurement*, because the blob dates the executing ref:

```
$ git rev-list 32b64cfe..5a983031^ | while read c; do
    [ "$(git rev-parse $c:bin/cc-dispatch)" = 9109de61… ] || echo DIFFERS $c; done
(no output — blob constant across all 282 commits of the window)
```

| | commit | UTC |
|---|---|---|
| window opens (blob introduced) | `32b64cfe` | 2026-09-09T03:01:01Z |
| window closes (next commit to touch the file) | `5a983031` | 2026-09-11T07:11:37Z |
| the cure | `f09640f` | 2026-09-11T15:21:31Z |
| the fire | — | 2026-09-11T16:35:00Z |

The blob is held by every commit in `[32b64cfe, 5a983031)` and by none after, so the executing layer
was at a ref **strictly older than `5a983031`** ⇒ **at least 9 h 23 m 23 s stale at fire time**. That
bound comes from the dispatcher alone and is 7.7× tighter than what the plan file alone gives
(1 h 13 m 29 s) — the plan file only proves staleness back to 15:21Z, the dispatcher proves it back
to 07:11Z.

### 3.1 One fact explains both readings

The probe's *script* comes from `~/.claude/scripts/`, its *argument* from the shared checkout. Those
look like two independent surfaces, and they are not: `install.sh` deploys `scripts/ bin/ hooks/`
as a **per-file symlink farm** into the primary checkout (`link_file` → `ln -sf "$src" "$dest"`,
`install.sh:214`; and its own guard at :86 — *"every $CONFIG_DIR symlink would point into this
worktree"*), and `.claude/CLAUDE.md` names that checkout as the symlink source for `~/.claude`.

⇒ a shared checkout whose **working tree** is behind trunk puts the live layer behind trunk in the
same stroke. One stale ref, two stale readings, and the dispatcher blob is the better clock of the
two. This is the known shared-checkout converge-block class (`.claude/rules/agent-operating-lessons.md`
§ *Shared-checkout commit blocks the fleet*), reaching a consumer nobody had priced: **the falsifier
probe that decides whether a `plan-open` row may retract itself.**

---

## 4. What I could NOT determine from off-box

I can prove *the desk read a pre-cure file* and *the desk ran a pre-`5a983031` dispatcher*. I cannot
prove **why** the checkout was behind — a behind-trunk working tree, an un-fast-forwarded merge, a
local commit blocking `merge --ff-only`, or a dispatcher snapshot cached at mint time are all
consistent with what I can see from here, and I will not narrate a mechanism I did not compute.
Three desk-side commands separate them, in order:

```sh
cd /Users/chrisren/Development/claude-infrastructure
git fetch origin -q && git rev-list --count HEAD..origin/main   # >0 ⇒ working tree behind trunk
git cherry origin/main HEAD                                     # any '+' ⇒ a local commit blocks --ff-only
git rev-parse HEAD:bin/cc-dispatch                              # ==9109de61… ⇒ this checkout is what fired me
```

Note the second one's own caveat, already in the rules: a `+` is not proof of absence
(*cherry + ≠ absence*), so verify any candidate by content before acting on it.

---

## 5. Residual worth filing (the desk must file it; `cc-backlog` is a no-op from here)

**A `plan-open` row's falsifier is evaluated against the desk's CHECKOUT, so a checkout behind trunk
re-dispatches a plan that trunk has already closed — and the re-dispatch is indistinguishable from a
genuinely open plan.** The fail direction is the expensive one: the probe exits 1 ("not refuted"),
which the brief correctly calls *the safe direction*, so nothing anywhere goes red. The cost is a
whole cloud fire per occurrence.

The cheap fix is not a new gate — it is to read the plan **through git** rather than through the
working tree, i.e. make the probe's file argument `git show origin/main:<path>` (or fetch-then-scan)
so the falsifier answers about trunk, which is the thing the row's landedness is judged against
anyway. Filing this as a named row rather than implementing it here: it edits the dispatch lane,
which is outside this item's frozen scope, and its own premise (§ 4) is not yet settled on-box.

---

## 6. Instrument note — an rc I nearly reported as a finding

The 09-08-vintage arm of § 2's 2×2 first came back **rc 2 on BOTH plan files**, which reads as "the
old script cannot evaluate this at all" and would have made the script arm look alive. It was my
harness. `git show <sha>:<path> > file` writes mode **644**, and the script's clause (a) is gated on
`[[ -x "$_fp_bin" ]]`; with the bit missing it skipped `find-plan.sh` entirely, fell through to
clause (b), re-exec'd `"${BASH_SOURCE[0]}"` — also non-executable — and took its `|| exit 2`. The
tell was that rc 2 was *invariant across the axis under test*: a reading that does not move when the
only variable moves is an instrument, not a result. `chmod +x` on the two copies produced the table
above. ⇒ when extracting a historical script to A/B it, restore its mode before believing its exit
code.

---

## 7. What was run

```
git rev-parse --is-shallow-repository        → true    ⇒ git fetch --unshallow   (4734 commits)
git fetch origin -q && git rev-list --count HEAD..origin/main                → 0
git merge-base --is-ancestor f09640f origin/main                             → 0
git merge-base --is-ancestor 889c65600 origin/main   (W3-B1, cited by the cure) → 0
git merge-base --is-ancestor f6ee42ea0 origin/main   (W3-B1, cited by the cure) → 0
scripts/plan-phase-scan.sh  <trunk plan>   --falsify  → FALSIFIED rc 0
scripts/plan-phase-scan.sh  <f09640f^ plan> --falsify → silent    rc 1
scripts/find-plan.sh --status <trunk plan>            → complete  rc 0
scripts/find-plan.sh --status <f09640f^ plan>         → open      rc 0
32b64cfe:scripts/plan-phase-scan.sh <trunk plan>   --falsify → FALSIFIED rc 0
32b64cfe:scripts/plan-phase-scan.sh <f09640f^ plan> --falsify → silent   rc 1
git rev-parse origin/main:bin/cc-dispatch  → 27c461a5…  ≠ brief's 9109de61…
```

**Disposition:** close `1dd6fbb6766c` as ALREADY-CURED, evidence `f09640f51d1bb79a08f76b8142b3d62d529eeac5`.
No code owed. File § 5 as its own row.
