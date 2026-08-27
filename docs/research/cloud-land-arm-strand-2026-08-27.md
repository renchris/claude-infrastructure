# The cloud land arm — `f85fce7c26f5` is cured, and its headline is true anyway

**2026-08-27 · verdict artifact for backlog `f85fce7c26f5`, written from the cloud VM it was
dispatched into (4th dispatch).** Everything below was read on TRUNK
(`git rev-list --count HEAD..origin/main` = 0 at the time of reading), never recalled.

**Verdict in one line:** the row's *diagnosis* was cured on trunk by `a42f107a` two days ago and the
row is closable on that sha — but its *headline*, "the cloud return/land arm died", is TRUE in the
present tense for a reason nobody has measured yet, and this row is one of its 151 casualties.

---

## 1 · The row is cured on trunk — verified by content, not by count

`a42f107aaca68da83345e1c8f95f283a35f4f13a` (2026-08-25, `fix(cc-cloud): deletion is the last step of
a successful session, and the probe read it as failure`) carries `Refs: cc-backlog f85fce7c26f5` and
answers all three of the row's clauses:

- `git merge-base --is-ancestor a42f107a origin/main` → rc 0.
- `git log --oneline a42f107a..origin/main -- bin/cc-cloud scripts/branch-prune-landed.sh
  tests/cc-cloud.bats` → **0 commits**. All three cure arms read intact on trunk.
- `bin/cc-cloud --selftest` → **24 passed, 0 failed**, re-run in this tree this session.
- The 08-19 prune manifest, checked in at `docs/research/branch-prune-manifest-2026-08-19.tsv`,
  confirms the confounder the row named: **55 DELETED · 41 HOLD-stranded · 1 HOLD-young**.

The 81%→33% push-rate step the row reports is therefore an INSTRUMENT artifact, exactly as the row
suspected: `cc-cloud`'s state function asked "is there a remote ref?" before "is the content on
trunk?", so a session that pushed, landed and had its branch pruned scored C1 NOT-STARTED —
byte-identical to one that never booted. The row's own exculpation of the create/fire path (frozen
since 08-11) was the clue: a step with no upstream change is a step in the instrument.

`bats` is absent in this venue, so `tests/cc-cloud.bats` could not be run here; two prior sessions
ran it 31/31 against these same bytes.

## 2 · …and the arm IS dead — 151 branches, 205 commits, measured on an UNCENSORED window

The reason this was missed twice is that the obvious probe is confounded by the very prune the row
names. It is not confounded after 2026-08-19, because **exactly one prune has ever run**: the
manifest above is the only one in the tree or in history (`--diff-filter=A` over
`docs/research/branch-prune-manifest-*`, one hit, `d40b04fa` 2026-08-19). So branches dated ≤08-19
are censored and branches dated ≥08-20 are not.

Landedness below is **patch-equivalence** (`git cherry origin/main <branch>`), never ancestry — the
land rebases, and raw ancestry is the weaker instrument this repo has already been burned by (it
reports 180 branches / 250 commits; the numbers used here are the conservative ones).

| day (branch tip) | on trunk | stranded | landed |
|---|---|---|---|
| 2026-08-20 | 1 | 7 | 12% |
| 2026-08-21 | 1 | 4 | 20% |
| 2026-08-22 | 4 | 2 | 66% |
| 2026-08-23 | 2 | 2 | 50% |
| 2026-08-24 | 10 | 17 | 37% |
| 2026-08-25 | 6 | 30 | 16% |
| 2026-08-26 | 2 | 43 | **4%** |

Whole population: **183 `origin/claude/fire-*` branches, 151 of them carrying 205 commits that are
on no trunk ancestor and patch-equivalent to nothing on trunk.**

The last day is not an artifact of work being too fresh to land. Restricted to branches whose tip
lands in **2026-08-26 00:00–18:00 UTC** — every one of them ≥3.4 h older than trunk's own last
commit (2026-08-26 21:26 UTC) — the score is **1 of 34, 2%**.

Two things this does NOT say. Fires rose from 4–8/day (08-20…08-23) to **27 / 36 / 45** on
08-24/25/26, so load rose ~6× across the collapse; and trunk absorbed **33–112 commits/day**
throughout, so the land pipeline as a whole is alive. What is failing is specifically the arm that
brings cloud branches home, and whether it is broken or merely saturated is a desk-side question —
`~/.claude/autonomy/cloud/return.jsonl` holds the per-session outcomes and is unreachable from here.

The stranded work is real and duplicated. `feat(cc-permission-audit): auto-mode drop audit…` sits on
two different branches; so does `fix(handoff-fire): the recycle retype nudge raw-typed /exit…`. That
is the re-dispatch loop paying for the same work twice.

## 3 · Why THIS row keeps coming back — its own cure is stranded twice over

| sha | date | branch | on trunk |
|---|---|---|---|
| `a42f107a` the cure | 08-25 | (landed) | **yes** |
| `aa556ff4` verdict artifact #1 | 08-25 | `origin/claude/fire-20260825T194636Z-62117-1` | no |
| `8bd76cf0` verdict artifact #2 | 08-26 | `origin/claude/fire-20260826T151105Z-95151-1` | no |

`8bd76cf0` is the one that matters: it wrote the convention for exactly this situation — *a worker
that finds its row cured LANDS A VERDICT ARTIFACT naming the cure sha, which `fill-paths` derives
and `cloud-return` content-verifies to fire the close* — into `CLOUD_OBSERVABILITY.md` as § 14.
**That section is not on trunk** (`git show origin/main:docs/plans/CLOUD_OBSERVABILITY.md` ends at
§ 13.6). The convention meant to break this loop was itself eaten by the loop.

So the mechanism is closed: a cloud VM cannot write `~/.claude/autonomy/backlog.jsonl` (it is absent
here; `cc-backlog done` answers `unknown id`, rc 3), its one channel out is its branch, and its
branch does not land. `cc-cloud` scores it C1 NOT-STARTED, `cloud-return` says nothing to return,
`cloud_map` sends NOT-STARTED → open, and the row is dispatched again. This document is the third
attempt at the same push and will strand identically unless § 5 happens.

## 4 · The VM cannot self-land — and the recorded cause is REFUTED

`scripts/ship-land.sh:3176` runs `unattended-path-lint.sh --selftest` **unconditionally**, before
own-scope is consulted, and `gate_red`s on failure. Here it fails **11 of 42**, so `/ship` exits 6
GATE RED for any diff, including a docs-only one. Reproduced this session.

Run first-hand on this commit, not inherited: `scripts/ship-land.sh` reaches that arm with **every
preceding gate green** — `utc-stamp-lint` clean ×3, `pipefail-sigpipe-lint` clean, `self-path-lint`
clean (377 files, 25 grandfathered, 0 new), `pane-spawn-coverage-lint` OK (23 sites / 432 files, 5
tier-2 notices, 0 advisory) — then `✗ ship-land: GATE RED — not pushing`, rc 6. So this one arm is
the whole of what stops a Linux land; nothing else in the gate objects to a cloud-authored diff.

`4ce67e78` (`docs(venue): the land rail is unusable from a Linux cloud VM too`, stranded on
`origin/claude/fire-20260826T084003Z-70841-1`) attributes all 11 to `/usr/libexec/PlistBuddy` being
absent on Linux, and proposes a Darwin guard or a skip-with-nonverdict as the fix.

**That attribution is wrong, and the proposed fix would change nothing.** A working PlistBuddy was
installed at `/usr/libexec/PlistBuddy` in this container (a 20-line `plistlib` shim, verified to
print `:ProgramArguments:<i>` correctly on the suite's own fixture and to exit 1 past the end of the
array) and the selftest was re-run: **still 11 of 42, the identical eleven.** PlistBuddy explains
**zero** of them. The shim was removed afterwards.

The real cause is one level down, and it is not guardable:

| failing case | fixture binary | why it flips on Linux |
|---|---|---|
| 2 · 8 · 13a · 13b | `tmux` | `/usr/bin/tmux` exists here, so it IS reachable on the stock PATH — on macOS it is Homebrew-only |
| 10 · 20a · 20c | `yq` | `/usr/bin/yq` exists here, and all three route through a plist whose inline PATH is `/usr/bin:/bin` |
| 14 · 17 · 18 | `md5` | absent from this box AND from the embedded inventory, so `installed_somewhere` drops the finding; on macOS it is `/sbin/md5` |
| `:1720` real-tree | many | `zsh · sqlite3 · afplay · shellcheck · bats · gtimeout · osascript · plutil · kitty · node` are all unreachable here, so the shipped allowlist leaves hundreds of findings |

This is not a portability bug in the fixtures. The lint asks *"will this bare name resolve on the
PATH the unattended job actually runs with"*, and that job runs on the operator's Mac — so the
lint's verdict is a property of **the box executing it**, not of the tree. Off Darwin it is
structurally inert, in both directions at once: it invents findings the Mac does not have, and it
drops findings the Mac does. A `uname` guard hides the inertness; it does not restore the sensor.

**No bypass was taken.** `SHIP_LAND_UNATTENDED_LINT=/nonexistent` would have skipped the arm and
landed this file. Weakening the gate that admits a VM's own commit is forbidden here, and it is a
worse act from a VM than from the desk. The principled repair — give the lint a checked-in reference
environment so it answers the same question anywhere — is a change to a mandatory land gate,
`bats` and `shellcheck` are both absent in this venue, and an ungated change to that file is
precisely what the gate exists to refuse. It belongs to an on-box session, and it is named in § 5.

## 5 · What is the desk's, and what is nobody's yet

**This row.** It is done. Close it on the cure:

    cc-backlog done f85fce7c26f5 --evidence a42f107aaca68da83345e1c8f95f283a35f4f13a

**The two follow-ons this venue cannot file** (`cc-backlog add` exits 3 against an absent store):

1. **The strand.** 151 branches / 205 commits are not on trunk, and the daily rate reached 2% on
   08-26 with load 6× its 08-23 level. `return.jsonl` names which of `cloud-return`'s three
   completion facts is failing and whether `<id>.land-refused` artifacts are piling up; nothing
   here can read it. Every re-dispatch off this pile pays twice for work that already exists.
2. **`unattended-path-lint` judges the box, not the tree.** Until it has a checked-in reference
   environment, `--selftest` is red off Darwin, `ship-land.sh:3176` gate-reds unconditionally on
   it, and no cloud session can land anything — which is one plausible input to (1), not a proven
   one, since the desk's own land path runs on macOS where the arm is green.

## 6 · Honest limits

- `bats` and `shellcheck` are absent here, so nothing in this document was gated by the repo's
  suites; every number is a git read or a direct invocation, reproducible from the commands named
  inline.
- The whole desk side — declaration store, `return.jsonl`, refusal artifacts, launchd state — is
  unreadable from a cloud VM. § 2 measures the OUTCOME (branches vs trunk) and deliberately stops
  short of naming a mechanism it cannot see.
- § 2's window is uncensored only because exactly one prune has run. A second prune pass will
  delete the landed branches and re-censor it; re-derive from a manifest, not from survivors.
