# RESTART BRIEF — 2026-07-27 00:45 local

Written immediately before a full iTerm2 restart, after the operator reported **5+ days stuck on
deploy/gate blockage**. Everything here is disk-truth verified this session, not recalled.

---

## 1. THE HEADLINE: the gate is not broken. LOAD is the blockage.

Direct evidence, from `wt-1a941c28a079`'s land report at 00:21 (its own words):

> post-Phase-1 this landed on the **FIRST attempt of the first quiet window (load 9, one gate,
> 2307 tests, 0 not-ok)** … 37 REDs were the monolith's 2.3% law

That is the whole 5-day story in one line. The same branch had died **37 times**; at load 9 it
landed first try with 2307 passing tests. Nothing about the tree changed — the box got quiet.

Corroborating measurements from this session:

| Fact | Value |
|---|---|
| `gate_admit` load ceiling | **8** |
| Load observed while "stuck" | **88 – 104** (peaked 153% Chrome + 130% iTerm + 71% WindowServer) |
| Load after closing Chrome/Dia | **10 – 16** |
| postland run at load 39.59 | 2h47m, RED, 6 suites |
| Those same 6 suites on a quiet box | **147 ok / 0 not-ok** — twice (individually AND together in one bats process) |
| Real land lock hold | **84–302 s, wait 0 s** (230 successful lands) |

**A land is not slow. The gate is not flaky.** At load > 8 every runner sleeps in `gate_admit`
instead of testing — 6 of 7 ship-lands and postland itself were observed with a `sleep` child and
no bats child at all.

### The one real bug behind the sleeping

`gate_admit`'s 600 s budget is **per call**, not per run. postland re-enters it once per suite and
once per retry, so ~12 calls ≈ 2 h of pure sleeping inside a "bounded by design" shedder.
`ship-land` was given a run-wide `CC_GATE_ADMIT_TOTAL_WAIT` cap; **postland's call site never was**.
→ backlog `60ec4c2d86d4`.

---

## 2. What is LANDED and LIVE (content-verified, both sides)

Trunk at write time: `ebad3250`. Shared checkout: **0 behind, 0 dirty, drift = 0 MISSING**.

| Item | Commit | Live |
|---|---|---|
| Phase 1 — per-suite gate runner | `1bc02f6f` | ✓ |
| Phase 2a — per-gate `$HOME` isolation (APFS clone) | `d9b934ee` | `gate_home_setup` ×5 |
| §9 measurement (66% → 30%) | in plan | — |
| Ratchet binds on YOUR diff, not the whole tree | `f5b1efed` | own-scope ×2 |
| Wall-clock time-bomb lint | `58e5bb97` | linked, selftest RC=0 |
| Deploy-parity existence leg | `33e60df2` | ✓ |
| …its own `$0`-through-symlink false-RED | `f94d9631` | ✓ |
| Fabricated-leak fix (grep rc=1 vs rc>1 + 3× retry) — **14 consecutive lands died on this** | peer | on trunk |
| cc-inbox-guard set-but-EMPTY disable seam (hung every landing gate) | `6f31dc26` | on trunk |

**Operator repairs done tonight** (were blocking the whole box):
- Shared checkout had diverged → `ff-merge` refused → *nothing on the box could deploy*. Reset after
  proving the local commit's patch-id was already on trunk.
- 4 scripts on trunk were **never symlinked** into `~/.claude` (per-file symlink dirs never link a
  BRAND-NEW file). Plus `test-walltime-lint.sh` after it landed.

---

## 3. AFTER THE RESTART — do these in order

```bash
# 1. Deploy path sane? (must print 0 MISSING and 0 behind)
cd ~/Development/claude-infrastructure && git fetch origin main -q \
  && git merge --ff-only origin/main \
  && bash scripts/deploy-parity-assert.sh; echo "RC=$?"

# 2. Is the box quiet enough for the gate to RUN? (need < 8)
uptime

# 3. Only if load < 8: kick the verification net. NOTHING schedules it —
#    com.claude.postland-verify is installed but UNLOADED (one of the 13 disabled jobs).
~/.claude/scripts/postland-verify.sh --run-if-needed
```

**Keep the session count low.** 14 Claude sessions cost ~15–20 % CPU each *plus* iTerm and
WindowServer rendering; that alone can hold the box above the ceiling with no work running.

---

## 4. Open state that survives the restart

Backlog (`cc-backlog list --project claude-infrastructure`):

- `60ec4c2d86d4` **open** — port the run-wide admit cap to postland. *This is the fix for the
  sleeping.* Highest leverage remaining.
- `e65d45027b3d` **blocked** — read the first post-repair postland stamp; GREEN ⇒ lift the §7
  embargo and start Phase 2b, RED ⇒ name which of the 6 suites did not share the deployed-path shape.
- `da18f179ac50` **blocked** — the 0-green-stamp deadlock (peer's elimination chain).
- `fe21305312ec`, `761a546f939c`, `91a29f4806fe` — other blocked fleet items.

postland: **22 stamps, 0 green ever.** The newest (`red`, `run_s 10052`, load 39.59) *spans* the
21:56 deploy repair and graded a stale commit, so it settles nothing. pid 13755 is parented to
launchd (ppid 1) and **survives an iTerm restart** — but if it ever exits, nothing restarts it.

Roadmap after that stamp: **Phase 2b** (content-addressed proof cache; precondition met, blocked
only by the embargo) → **Phase 3** (hermeticity for ~20 hot suites; already in progress on
`wt-1a941c28a079`'s `herm-migration-wip` stash).

---

## 5. Things that cost hours tonight — do not re-derive

- **A wedged pane looks alive.** `4EEADDF5` had a live process, a readable screen, and `it2 session
  send` returning **0** — while its transcript was frozen 50 min and *no* keystroke landed (proved
  with a positive control on another pane). Neither mail nor keystrokes reach a husk; `cc-teardown`
  fail-closes on it. Only `⌘W` clears it.
- **`cwd` gone ≠ work gone.** A pruned worktree can leave a branch with real unlanded commits. Grade
  by branch + patch-id, never by worktree existence.
- **Verify with the RIGHT path.** Two symbol greps returned 0 hits purely because the paths were
  wrong (`hooks/cc-inbox-guard.sh` vs the real `bin/cc-inbox-guard`) — nearly reported landed work
  as lost and would have re-landed a duplicate.
- **`${VAR:-}` cannot tell unset from set-empty.** That distinction is load-bearing in the own-scope
  ratchet (set-but-empty = "I change no suite" = nothing blocks).
- **A red with zero `not ok` lines is not always a non-verdict** — shellcheck is a real verdict that
  emits no TAP.

---

## 6. CORRECTION (02:10) — "load is the blockage" is HALF right

The decisive post-repair stamp landed after §1 was written, and it splits the diagnosis in two.

    verdict: red   commit: f94d9631   run_s: 6606 (1h50m)   load: 9.34
    failing: deploy-parity, desk-arm-live, desk-recycle-durable,
             lr-team-audit, session-continue, waiting-recycle

That is **current trunk** — carrying both the PATH fix and the 21:56 deploy repair — at **load 9.34**,
essentially the same quiet window in which `wt-1a941c28a079` landed 2307 tests with 0 not-ok. The
same six suites are still convicted.

| Claim | Verdict |
|---|---|
| Load explains why **LANDS** kept failing | **HOLDS.** 37 REDs → landed first attempt at load 9. |
| Load explains **postland's 6 red suites** | **REFUTED.** They fail at load 9.34 too. |

**So the 0-green-stamp deadlock is NOT the load story.** The remaining uncontrolled variable is the
one the `session-close-hardening` peer named: postland runs the FULL corpus in **its own reused
`ci-postland` worktree**, and that specific cell — full-137 × reused-worktree — is the only
combination that reproduces. My own clean-box control (147 ok / 0 not-ok, twice) was run in a
DIFFERENT worktree, so it never tested that cell; it is evidence about the suites, not about
postland.

**Next measurement, and it is cheap** — bisect the cell rather than the tree:

```bash
# does the corpus fail because it is FULL, or because the worktree is REUSED?
cd ~/Development/.worktrees/ci-postland && TMPDIR=$(mktemp -d) nice -n 10 bats tests/   # reused wt
git worktree add /tmp/wt-fresh-postland origin/main && cd /tmp/wt-fresh-postland \
  && TMPDIR=$(mktemp -d) nice -n 10 bats tests/                                          # fresh wt
```
Same corpus, same load, one variable. If fresh passes and reused fails, the cause is accumulated
worktree state, not the suites and not the tree — and `postland-verify.sh` should mint a clean
worktree per run (or reset it) rather than reusing one.

Backlog `da18f179ac50` (0-green-stamp deadlock) remains the owner of this; `e65d45027b3d` can now be
answered: the stamp came back RED, and it did NOT share the deployed-path shape.

---

## 7. RESOLVED 2026-07-29 — and §6's named variable was not the cause either

The cell hypothesis above (full-137 × reused-worktree) was overtaken: land-pipeline-v2 (`8d50f953`)
mints a fresh cell per run, and the 7 post-v2 stamps were still 0 green. The actual cause was in the
**retry ladder**, not the cell — it scored rc 124 (its own 300 s bound firing) as a test failure, so
any suite slower than the bound could only ever be convicted. Full evidence and the C23 fix:
`LANDING_GATE_ROOT_CAUSE_2026-07-26.md` §5. Backlog `10941179f8ec`.

### §7 ANSWERED by measurement (2026-07-29, backlog `ba63751cea54`)

§7 closed the cell hypothesis as **OBSOLETE** (the pipeline no longer reuses a cell). The bisect §6
actually asked for was then run anyway, so it is now also closed as **REFUTED by measurement** →
**`docs/research/POSTLAND-CELL-BISECT-2026-07-29.md`**. It agrees with §7's ladder finding and adds
one correction. Short form, so nobody re-runs it:

- The reused `ci-postland` cell's *entire* non-tracked content is **3 `.pyc` files** whose sources are
  byte-identical across the tree change — a valid, inert cache, not cross-tree residue. Same tree hash
  in both cells; the disk differed by exactly those 3 files.
- The six convicted suites are **exactly** `scripts/host-suites.manifest`. v1 ran `bats tests/` (bare
  dir, includes them); v2 runs `tests/*.bats` MINUS that manifest. **v2 cannot convict them because it
  does not run them** — that, not the fresh cell and not PATH, is why they vanished at the cutover.
- The `env -i` PATH model in §6's neighbourhood is wrong for this job: the launchd plist has exported
  `$HOME/.claude/bin` since its first commit (`95438bbb`); only `$HOME/bin` was ever missing, and the
  six pass 155/0 under exactly that PATH.
- Both full-corpus arms ran to completion (2324/2324, same 7145 s window). The reused cell produced
  **zero** failures the fresh cell did not; the only asymmetry was one *extra* file in the **fresh**
  arm, and it passes 11/0 alone in both cells. The red was also caught **flipping live** with the cell
  held constant: `21b68c60` landed two brand-new tracked files at 22:31:50Z, and deploy-parity's host
  assertion went red in *both* cells 2 s apart — the deployed-layer circle, not worktree residue.
- **Independently re-derived §7's ladder finding** before seeing it: `waiting-recycle` measures 445 s
  alone vs `FILE_TO=300`, so both retries die on the bound and it is convicted 2/3 with `flakes=0` as
  the tell. That is §7/C23, already fixed — my duplicate backlog item was closed, not re-worked.
- **The one correction to §7.** Its point 4 ("the convicted suites are exactly the heaviest") holds for
  the *post-v2* red (`postland-verify.bats`, 51 tests ≈ 50 min solo) but **not** for the 18 *pre-v2*
  convictions: measured solo at load 25, five of that six are **2-14 s** (deploy-parity 9 s,
  desk-arm-live 9 s, desk-recycle-durable 11 s, lr-team-audit 2 s, session-continue 14 s) — a 300 s
  bound cannot convict them. Those five are host/deployed-layer assertions, and *that* is why the set's
  membership never varied. Two eras, two mechanisms; the ladder fix does not retire the first one.
- **Still open and unfixed on trunk** (`cc89fc8dc765`): the stall watcher is blind to bats' no-TAP
  counting pass — its clock starts at t=0 and only `ok|not ok` lines reset it (verified on `origin/main`:
  zero plan-line awareness), while the counting pass over 141 files measured **>600 s** at load 33-48
  under background QoS against a 900 s bound. Latent load-conditional false cut.
