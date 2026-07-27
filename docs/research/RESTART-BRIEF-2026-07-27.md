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
