# post-land HUNG `tests/postland-verify.bats` @ 11426/14327 — the premise is refuted, the effect is cured

**Item:** cc-backlog `4f7bf7b75181` — *"post-land HUNG: tests/postland-verify.bats wedged at
11426/14327 @ 4bffeaeeb22d — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)"*.
**Worked:** 2026-09-20, off-box (cloud VM, Linux 6.18, bats 1.13.0), branch
`claude/fire-20260920T160244Z-44379-1`.
**Verdict:** the EFFECT is real and is cured here. The stated CAUSE is refuted; so is the stated
remedy. Details below so the row can be closed on evidence rather than on a diff.

---

## 0. Provenance checks the brief asked for

| check | result |
|---|---|
| shallow clone | `true` → `git fetch --unshallow` run before any trunk read |
| `git rev-list --count HEAD..origin/main` | **0** — this tree IS trunk |
| dispatcher vintage `git rev-parse origin/main:bin/cc-dispatch` | `dc9130372d6332940388c2a17da7c65c1af3c3bd` — **EQUAL** to the blob that composed the brief, so the dispatcher that fired this session is trunk |
| cited `4bffeaeeb22d` | `git cat-file -t` → **`tree`**, not a commit. `merge-base --is-ancestor` refuses it ("is a tree, not a commit"). The title's `@ <sha>` is a TREE sha — which is correct for this producer (stamps are tree-keyed, C3/C5) and is worth knowing before anyone tries to walk history from it |
| cure already on trunk? | **No.** `git log -S'POSTLAND_STALL_POLL_S' -- scripts/postland-verify.sh` returns exactly one commit, `dc12c8db` (2026-07-28, *"progress-keyed stall bound"*), which INTRODUCED the loop diagnosed below. 4432 commits have landed since without touching it |

## 1. What the row's premise claims, and why it is refuted

> *"un-stubbed external seam, timeout-wrap it"*

The external seam in question is `bats`, and it is the most thoroughly bounded call in
`scripts/postland-verify.sh`:

- run under `"$TIMEOUT_BIN" -k 10 "$SUITE_TO"` (`run_target`, ~line 3763), deliberately via `exec`
  in its own process group so the signal reaches the whole bats tree;
- with a **progress-keyed stall watcher** above it (`POSTLAND_STALL_S`, default 900) that cuts on
  TAP silence;
- and a **pre-plan grace** below that (`pre_plan_grace`) for the counting phase that emits no TAP.

There was no un-stubbed seam to wrap. Adding a further `timeout` would have placed a third bound
over an interval that contained **no work at all** — it was 100% `sleep`.

The filer inferred a foreign cause from the fact that the time was not being spent in any code they
could see. It was not being spent in any code: the sleeps in a supervisor are its own. (The
parenthetical *"NOT a peer pkill"* was right, and independently so — `C15–C17` already separate a
machine event from a suite that never returns, and this was neither.)

## 2. What is actually happening

`scripts/postland-verify.sh`, `run_target`, as it stood at `HEAD == origin/main`:

```bash
( cd "$WORKTREE" && … exec "$TIMEOUT_BIN" -k 10 "$SUITE_TO" … "$BATS_BIN" … ) </dev/null > "$tap" 2>&1 &
cpid=$!; last=0; still=0; preplan=0; planned=0; cutby=""
while kill -0 "$cpid" 2>/dev/null; do
  sleep "$poll"                 # ← poll defaults to 60
  …
done
wait "$cpid"
```

The loop is entered unconditionally — the child is alive by construction one line after `&` — so
**the first statement executed is a full-period sleep, and the child's own runtime cannot shorten
it**. `poll` stopped being the resolution of the stall decision and became the **floor on every
corpus run**.

That is invisible where the period was chosen (one 60 s tail on a ~45-minute production corpus run
is 2%). It is total for the four bats suites that DRIVE this script against a **two-file fixture
corpus**: every `--run-if-needed` in them is a real corpus run through the real watcher.

## 3. The measurement

`tests/postland-verify.bats`, 148 tests at the time, this VM, unloaded, `bats -T`:

| test | before | after |
|---|---|---|
| 1 `POSTLAND_VERIFY=off is an immediate no-op` (kill switch returns before `run_target`) | 124 ms | 142 ms |
| 2 `C7: CC_POSTLAND_WORKTREE is still honored verbatim` | **60 442 ms** | **1 448 ms** |
| 3 `C7: a trailing-slash TMPDIR reaches the corpus` | **60 421 ms** | **1 409 ms** |
| `C29: CC_POSTLAND_CONVICT=off restores the one-window red` | **60 831 ms** | **2 782 ms** |

Test 1 is the control that makes this a measurement rather than a coincidence: it is the one test
that never reaches the watcher, and it is the one test that did not move.

The fourth row was first obtained as a **pure A/B with no code change at all** — the same test, the
same box, minutes apart, `POSTLAND_STALL_POLL_S=2` the only difference: 60 831 ms → 2 782 ms. That
is what identifies the period as the subject. The code change then stops it being a floor.

At ~2 SUT runs per test that is **~5 hours of pure `sleep` in this one suite file**, and the suite
runs inside the very corpus it tests. The net saw no TAP line from it for longer than
`POSTLAND_STALL_S`, cut the run, and filed a HUNG naming it. **The verdict was accurate and the
attribution was correct — the subject was the watcher's own loop. The net convicted itself.**

## 4. The cure

`scripts/postland-verify.sh`:

- new `STALL_TICK_S="${POSTLAND_STALL_TICK_S:-1}"` (0 = kill switch, restores the old whole-poll
  sleep) and a top-level `stall_wait <poll> <cpid>` that sleeps in ticks and returns **rc 1 the
  moment the child is gone**;
- the watcher's `sleep "$poll"` becomes `stall_wait "$poll" "$cpid" || break`.

**No clock changes.** `still` and `preplan` still advance by whole `poll` units, once per completed
outer iteration, and an outer iteration still takes `poll` wall seconds whenever the child is alive
for all of it. The stall and pre-plan predicates are byte-for-byte the arithmetic they were; the
tick only decides how soon a DEAD child ends the wait.

`|| break` rather than `|| true` is load-bearing: on early exit the accounting must be **skipped**,
not run with a partial period. Running it would let a run that finished normally inside its last
partial period be convicted by `still + poll >= stall` and forced to rc 124 — a healthy run cut at
the finish line.

`tests/postland-verify.bats` gains four tests (`stall_wait: …` ×3 plus a call-site arm). They drive
the helper **as a unit**, read out of the SUT with `eval "$(sed -n '/^stall_wait() {/,/^}/p' …)"`
(the `C13f`/`cond_slug` idiom). Deliberately not a wall-clock assertion on a whole
`--run-if-needed`: that would be a load sensor, and this corpus's band is measured at an 84x tax
(`2514226e`). `stall_wait`'s cost is sleeps, and a sleep costs its wall time at any load.

### Mutants, run rather than asserted

| mutation | test | result |
|---|---|---|
| `stall_wait` body → `sleep "$left"; return 0` | *"the wait ends when the CHILD does"* | **dies** — 20 121 ms, rc 0 (expected rc 1, < 8 s) |
| call site reverted to `sleep "$poll"`, helper untouched | *"the watcher's wait is stall_wait, not a bare sleep"* | **dies** |

The second mutant is the one a unit test alone cannot catch — the helper-position half
(`helper-position-bounds-a-fixs-reach`), which is why the call-site arm exists.

Recycled-pid hazard runs the safe way: a stranger inheriting the pid reads as LIVE, so the wait runs
to the full period and the test goes **red**. It cannot go green because a pid was re-issued.

## 5. Suite state on this box, and what belongs to the box

Both arms of the full file were run on this VM (arm A = trunk with `POSTLAND_STALL_POLL_S=1`
ambient so the pre-fix arm is affordable; arm B = the patched tree at the default period). See §6
for the sets. Two red classes are **properties of this Linux VM and reproduce identically on
unpatched trunk**:

1. **`stat -f %m` is BSD/macOS syntax** (`try_acquire`, `scripts/postland-verify.sh:1066`). GNU
   coreutils reads `-f` as *file system* and prints `  File: "/tmp"` on stdout, which lands inside
   `$(( $(now_epoch) - … ))` and dies under `set -u` as `line 1066: File: unbound variable`. Every
   test that pre-creates `run.lock.d` therefore fails in ~170 ms without reaching the corpus — the
   C6/C6b/C33 mutex block. Not in this item's scope and **not touched**; recorded because a future
   off-box worker will meet it in the first ten minutes.
2. **git identity.** `identity_assert` deliberately DROPS a local `[user]` section whose email is
   not the sanctioned `ren.chris@outlook.com`, so the fixture's `tester@example.com` is removed by
   design on the first SUT run. On the operator's Mac the global identity catches the fall-through;
   on a bare VM with `HOME` sandboxed by `setup()` there is nothing to fall through to and every
   later `push_commit` dies with *"Author identity unknown … got 'root@vm.(none)'"*. Cured for the
   verification run by a **system-level** (`git config --system`) identity, which `HOME`
   redirection cannot hide. This is harness setup, not a code change, and nothing in the repo
   moved for it.

## 6. Exactly what was run

```bash
npm install -g bats                                   # bats 1.13.0, the version the stubs claim
bats --count tests/postland-verify.bats               # 148 before, 152 after
bats -T tests/postland-verify.bats                     # both arms, full file
bash -n scripts/postland-verify.sh
bash scripts/rules-hook-budget-lint.sh                 # clean — 140 bullets, all bodied, ≤420 chars
```

Arm A (trunk, `POSTLAND_STALL_POLL_S=1`) and arm B (patched, default period) failure sets are
recorded in the commit message. The claim this section supports is narrow and is the only one that
matters for the land: **arm B introduces no red that arm A does not already have.**

## 7. Lesson filed

`docs/lessons/poll-period-charged-as-a-cost-floor.md`, hooked from
`.claude/rules/agent-operating-lessons.md`. The transferable rule: for any polling supervisor, *how
often must the decision be re-made* and *how soon must the wait end once there is nothing left to
wait for* are two different numbers, and collapsing them into one `sleep` charges every caller the
first as a floor.

## 8. Disposition of the row

`4f7bf7b75181` is **cured, not refuted** — but its stated cause and remedy are both refuted, so it
must not be closed as "timeout-wrapped a seam". It is closed by this branch:
the cure is §4, the disproof of the premise is §1, and the measurement that separates them is §3.
