# W3 — deploy the kitten (route A′): the measurements

Wave W3 of `docs/plans/KITTY_DRAG_ACTION.md` (lines 1224-1253). Everything below is a command that
was run in `/Users/chrisren/Development/.worktrees/kitty-drag-impl` on 2026-09-16 and the output it
printed. Nothing here is recalled.

**Scope note.** W3 touches exactly two things: `tests/kitty-conf-bindings.bats` (this wave owns it)
and this record. It writes no config, adds no `mouse_map` line, and references the kitten from no
config file. `scripts/kitty-drag-window.py` was landed by W2 as `254e1b47b` and is not edited here.

---

## 1. The land-gate defect W3 exists to close, reproduced

`gate-select` maps a changed file to the suites whose **executable** text names it. Before this
wave's case existed, the kitten mapped to nothing:

```
$ bash scripts/gate-select.sh --explain --direct 254e1b47b^..254e1b47b
FULL <- unmapped:scripts/kitty-drag-window.py
FULL
```

`FULL` is the selector's **abstention**, and `ship-land` reads it as "run no smoke" — deferring the
whole corpus to `postland-verify`, where it surfaces as a post-land RED with a possible AUTO-REVERT
against a diff that was fine. This is a land-gate mechanic, not a coverage nicety.

After appending the case (below), the same range, same command:

```
$ bash scripts/gate-select.sh --explain --direct 254e1b47b^..254e1b47b
tests/kitty-conf-bindings.bats <- literal:scripts/kitty-drag-window.py
tests/kitty-conf-bindings.bats <- NOT-DIRECT closure:scripts/kitty-drag-window.py
tests/kitty-conf-bindings.bats <- NOT-DIRECT stem:scripts/kitty-drag-window.py
gate-select --direct: 1 direct suite(s); 0 reached ONLY by non-direct clauses (marked NOT-DIRECT
above). An empty direct set is a VERDICT — nothing this diff executes — NOT an abstention; this
selector abstains by printing the literal token FULL.
tests/kitty-conf-bindings.bats
```

The edge is **`literal:`**, i.e. **DIRECT** — clause (a) with `cited_only` false. That matters and is
not automatic: `gate-select.sh:359-389` demotes an edge whose *entire* evidence is a comment, so a
case that named the kitten only in a `#` line would have selected the suite while leaving it
un-exonerable. The path appears in the case's executable text (`"$REPO/scripts/kitty-drag-window.py"`),
which is what earns the DIRECT edge.

## 2. Route A′ holds: the existing `scripts/*.py` glob is the entire deployment

`install.sh:689`, read verbatim:

```
$ sed -n '689p' install.sh
for script in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/*.py; do
```

The loop body calls `link_file` in the global install, so a top-level `scripts/*.py` becomes a
symlink under `~/.claude/scripts/`. **The positive control is a census, not an argument** — every
top-level `scripts/*.py` in the repo, asked two questions independently:

| | on `origin/main` | under `~/.claude/scripts/` |
|---|---|---|
| 34 top-level `.py` files (`assignee-chain-state.py` … `plan-venue-census.py`) | yes | **SYMLINK** into the shared checkout |
| `kitty-drag-window.py` | **no** | **ABSENT** |

i.e. deployment is 34-for-34 among the on-trunk members and the one absentee is the one not yet
landed. The two sets coincide exactly, which is the strongest statement available while the kitten
is still on a branch.

```
$ ls -la ~/.claude/scripts/kitty-drag-window.py
ls: /Users/chrisren/.claude/scripts/kitty-drag-window.py: No such file or directory

$ git ls-tree origin/main -- scripts/kitty-drag-window.py
(no output — not on trunk)

$ ls -la ~/.claude/scripts/kitty-pane-title-overlay.py
lrwxr-xr-x@ 1 chrisren staff 85 Sep 15 08:15 /Users/chrisren/.claude/scripts/kitty-pane-title-overlay.py
  -> /Users/chrisren/Development/claude-infrastructure/scripts/kitty-pane-title-overlay.py
```

**So the DoD's `ls -la` cannot pass until the lead lands and the live layer converges** — the live
layer is a per-file symlink farm over the shared checkout, and `install.sh` runs on the converge. The
deploy MECHANISM is what is proven here, by the sibling `.py` that rides the same one glob.

⚠️ **Which path the DoD should name.** The plan says both, and one is stale:

| | says | verdict |
|---|---|---|
| § 6 DoD item 2 (`:1481`), W7 goal (`:1447`) | `~/.config/kitty/kitty-drag-window.py` | **route A — stale** |
| § 4.M ruling table (`:1078-1079`), W3 (`:1226`, `:1243-1244`) | `~/.claude/scripts/kitty-drag-window.py` | **route A′ — correct** |

§ 4.M is the later measurement and it is the one the code follows: nothing in `install.sh`,
`scripts/kitty-setup.sh` or `scripts/deploy-parity-assert.sh` places anything named
`kitty-drag-window.py` into a kitty config dir, and route A′ deliberately removed those arms. The two
route-A spellings at `:1447` and `:1481` should be corrected to `~/.claude/scripts/`.

## 3. `tests/deploy-parity.bats` — unchanged at 107/107

§ 4.M predicted "107/107 green, measured unchanged". Measured:

```
$ bin/cc-bats tests/deploy-parity.bats
1..107
... 107 ok, 0 not ok ...
ok 107 WALK INPUT COVERAGE fire test: deleting the two root SSOT pathspec entries strands them, ...
```

Plan line present, so this is a result and not a `cc-bats` contention refusal.

## 4. `tests/kitty-conf-bindings.bats` — 32/32, with the two new cases

The wave adds one case plus its mutant control. The case pins two couplings, both durable across W7:

1. **the deploy route** — `install.sh` still globs `scripts/*.py`. Narrow it back to `*.sh` and the
   kitten silently stops reaching `~/.claude/scripts/`, leaving W7's absolute-path config line
   pointing at nothing, which is § 2.2 M4's *worst* state, not its safe one.
2. **the dispatch contract**, read out of the AST rather than grepped: a module-level `main()`
   (`kittens/runner.py:65` subscripts `g['main']` unconditionally), `handle_result` with the
   documented four-parameter signature `(args, answer, target_window_id, boss)`, and a `no_ui`
   declaration. Any of the three missing turns every press into
   `show_error('Key action failed', …)` *and consumes the press* (§ 2.1 S3).

**What the case deliberately does NOT assert: that no config line references the kitten.** Inertness
is W3's *state*, not an invariant — W7 lands the arming line in a `globinclude`d drop-in — and a test
pinning today's state would have to be deleted by the very wave it is meant to protect. That is the
`[Stale test inverts]` failure this repo has already paid for three times in this one file.

```
$ bin/cc-bats tests/kitty-conf-bindings.bats
1..32
... 32 ok, 0 not ok ...
ok 31 the drag kitten deploys through the scripts/*.py glob and is dispatchable — W3, route A′
ok 32 MUTANT CONTROL: the drag kitten's dispatch guards are each visible to that probe
```

## 5. A PRE-EXISTING RED found and fixed in the suite this wave owns

Case 27 (`no usable face is a REFUSAL, not a verdict computed on a substitute font`) was **red before
this wave touched anything**. A/B against the HEAD copy of the suite, run from a scratch tree whose
`config/` and `scripts/` symlink back to this worktree so `$REPO` resolves identically:

```
$ git show HEAD:tests/kitty-conf-bindings.bats > <scratch>/tests/kitty-conf-bindings.bats
$ /opt/homebrew/bin/bats -f 'no usable face is a REFUSAL' <scratch>/tests/kitty-conf-bindings.bats
1..1
not ok 1 no usable face is a REFUSAL, not a verdict computed on a substitute font
#   ModuleNotFoundError: No module named 'PIL'
```

**Cause, measured — it is the interpreter, not the overlay.** The case invoked a bare `python3`; this
box's PATH `python3` is `/usr/bin/python3`:

```
/usr/local/bin/python3   -> PIL 12.2.0
/opt/homebrew/bin/python3 -> ModuleNotFoundError
/usr/bin/python3          -> ModuleNotFoundError
```

Case 9 in the same file (`the overlay can reach a python with Pillow`) already ships the correct
idiom — iterate the three candidates — and passes. Case 27 did not, so it asserted a defect in
`scripts/kitty-pane-title-overlay.py` that the run never actually looked for.

**Fix:** resolve a PIL-capable interpreter the way case 9 does, and `skip` when none exists. The
body's ARM 2 does `from PIL import ImageFont` itself, so PIL is a *precondition* of the case, and a
precondition the environment can falsify must skip rather than redden. The assertions are untouched.
On this box it does not skip — it runs and passes (`ok 27`, no `# skip` marker), so the fix did not
buy the green by disabling the case.

**Why fix it here rather than file it.** This wave's own case is what makes
`tests/kitty-conf-bindings.bats` a **DIRECT** suite for `scripts/kitty-drag-window.py`. A DIRECT red
is, by `ship-land`'s contract, a verdict about the landing diff — so leaving it would have converted
W3's whole deliverable into a land that cannot pass its own gate.

---

## 6. Two residuals for the lead, both measured, neither W3's to fix

### 6a. The branch STILL answers `FULL` — and it is now W8's `.c` file, not the kitten

Closing the kitten's `unmapped` rung does not by itself make the land narrow. Over the whole branch:

```
$ bash scripts/gate-select.sh --explain --direct origin/main...HEAD
tests/kitty-conf-bindings.bats <- literal:scripts/kitty-drag-window.py      ← W3's fix, holding
FULL <- unmapped:tools/draghold/draghold-original.c                          ← the remaining door
FULL
```

Per commit:

| commit | verdict |
|---|---|
| `fe1d82342` W1 | maps — `tests/cc-kitty-reload.bats` (literal + naming) |
| `254e1b47b` W2 | **maps — `tests/kitty-conf-bindings.bats`, and only that one** |
| `6f64a25e5` W8 | **`FULL <- unmapped:tools/draghold/draghold-original.c`** |
| `c1c1008a8`, `c02267069` docs | map / inert |

`tools/draghold/` is W8's, and it has the identical defect W3 was dispatched to close: no suite names
`tools/draghold/draghold-original.c` in executable text, so `ship-land` will run no smoke for the
land regardless of the kitten. **One case naming that path literally in a suite's executable text
closes it**, the same shape as § 4 above.

### 6b. Four suites fail `test-hermeticity-lint`, two of them added on this branch

```
$ bash scripts/test-hermeticity-lint.sh tests
  LEAK     cc-owner.bats: setup() does not fixture $HOME — it runs against the live ~/
  LEAK     handoff-claim-assert.bats: setup() does not fixture $HOME — it runs against the live ~/
  LEAK     kitty-drag-arm.bats: setup() does not fixture $HOME — it runs against the live ~/
  LEAK     kitty-pane-graph.bats: setup() does not fixture $HOME — it runs against the live ~/
test-hermeticity-lint: ⛔ 4 new non-hermetic suite(s) above.
rc=1
```

`tests/kitty-conf-bindings.bats` is **not** among them — its `setup()` already fixtures `$HOME`.
`tests/kitty-drag-arm.bats` and `tests/kitty-pane-graph.bats` are untracked and were added on this
branch by sibling waves; `cc-owner.bats` and `handoff-claim-assert.bats` are on `origin/main`.
The remedy the lint itself prints is one line in each `setup()`; it explicitly forbids the allowlist.

### 6c. The stale route-A path: `:1481` is fixed, `:1447` is not

`c1c1008a8` corrected § 6 DoD item 2 in place. **`:1447`, the W7 goal line, still reads
`ls -la ~/.config/kitty/kitty-drag-window.py`** and should read `~/.claude/scripts/`.

## 7. Lints run against this wave's file

| lint | producer rc | verdict |
|---|---|---|
| `scripts/gate-select.sh lint` (map anti-rot) | 0 | clean — no unreachable suite |
| `scripts/bats-assert-liveness.py tests/kitty-conf-bindings.bats` | 0 | no dead assertion |
| ↳ positive control (planted `[[ "1" == "2" ]]`) | 1 | `DEAD [cond-keyword]` — the analyzer speaks |
| `scripts/test-hermeticity-lint.sh tests` | 1 | 4 leaks, **none of them this file** (§ 6b) |
| `scripts/bats-shellcheck-lint.sh tests/kitty-conf-bindings.bats` | 0 | `clean — 1 suite(s) scanned, 0 blocking finding(s), 0 unanalyzable` — **only once `shellcheck` is on PATH**. The bare run returned rc 2 `shellcheck not installed — NOT a clean verdict`; the binary is at `/opt/homebrew/bin/shellcheck`, absent from this shell's PATH, and the lint correctly refused rather than passing. A refusal is not a result. |

The liveness positive control is not decoration: an analyzer that returns 0 because it parsed nothing
is indistinguishable from one that returned 0 because the file is clean. The planted mutant is what
separates them.
