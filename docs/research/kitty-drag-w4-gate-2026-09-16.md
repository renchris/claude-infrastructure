# W4 — the operator gate: what was built, and what it was measured against

**2026-09-16.** Wave W4 of `docs/plans/KITTY_DRAG_ACTION.md` (plan lines 1254-1284). W4 is not an
agent wave: it needs a human hand on a real mouse for about sixty seconds. This wave built the
apparatus that makes those sixty seconds cost nothing else, and **performed no gesture and drove no
drag**.

## The three deliverables

| File | What it is |
|---|---|
| `scripts/kitty-drag-w4.sh` | the operator-gate driver — sandbox launch, six live bindings, in-pane instructions, self-read verdict |
| `scripts/kitty-pane-graph.py` | the verdict reader — pane-adjacency snapshot + witness-safe differ |
| `tests/kitty-pane-graph.bats` | the differ's control suite, five branches, 14 cases, no kitty required |

## The one command the operator runs

```
bash scripts/kitty-drag-w4.sh
```

Everything else is a flag: `--dry-run` (generate and validate, launch nothing), `--watch-secs N`
(gesture window, default 120), `--no-screenshot`, `--wait-build N` (poll for the 0.48.2 tree),
`--teardown`.

## The `neighbors` schema — MEASURED, not guessed

The plan required finding the real shape before designing a parser. Read off a sandbox kitty with
its own `KITTY_CONFIG_DIRECTORY`, socket outside the `/tmp/kitty-*` glob, all three `KITTY_` vars
dropped, against `/Applications/kitty.app/Contents/MacOS/kitty`:

```
$ kitten @ --to unix:/tmp/kdwp.sock ls          # 3 panes, layout=splits
  id 1 neighbors = {'bottom': [2, 3]}
  id 2 neighbors = {'right': [3], 'top': [1]}
  id 3 neighbors = {'left': [2], 'top': [1]}
```

`neighbors` is a **dict**; keys are drawn from `left/right/top/bottom` and a direction with no
neighbour is **absent**, not present-and-empty; each value is a **list** of int window ids and it
**can hold more than one** (pane 1). A parser assuming a scalar, or assuming all four keys exist, is
wrong on real data — that is branch (e) of the suite.

The 24 window keys in the same run: `at_prompt cmdline columns created_at cwd env
foreground_processes has_activity_since_last_focus id in_alternate_screen is_active is_focused
is_self last_cmd_exit_status last_focused_at last_reported_cmdline lines needs_attention neighbors
pid session_name title title_overridden user_vars`. The OS-window level carries
`platform_window_id`, which is what scopes the Q10 screenshots to the sandbox window alone.

## The witness rule, and the proof the suite is not decorative

`diff_graphs()` tests the member **set** before it tests the **order**, because closing a pane makes
its two neighbours adjacent — so an order-first differ reports ordinary churn as a REORDER, and W4's
evidence is a HUMAN ACTION, the one proof a session may not manufacture.

The **faithful** mutant is the order test moved above the set test *and iterating the intersection*,
which is how the real pre-fix differ behaved: it does not crash, it silently fabricates. (A first
mutant that simply swapped the blocks died with `KeyError: '2'` — loud, and therefore a weaker
mutant than the defect being guarded. It was discarded.)

Under the faithful mutant, branch (b) is the only branch that reddens:

```
1..14
ok 1 (a) true reorder ...
ok 2 (a) true reorder satisfies --expect REORDERED
not ok 3 (b) member closed: a pane close is NOT a reorder, it is SET-CHANGED
not ok 4 (b) member closed: names the gone pane and reports no moves
not ok 5 (b) member closed: --expect REORDERED must FAIL, rc 1
ok 6 (c) member opened ...
ok 7..14 ...
ok:     11
not ok: 3
```

and the fabrication is printed in full — a pane **close** reported as a layout change, with
`panes before=3 after=2` sitting right beside the word REORDERED:

```
# VERDICT: REORDERED — the pane layout genuinely changed.
#   why: the pane set is IDENTICAL on both sides and the adjacency graph changed ...
#   panes before=3 after=2
#   moved: window 1  [osw 1 tab 1] bottom=[2, 3]  ->  [osw 1 tab 1] bottom=[3]
#   moved: window 3  [osw 1 tab 1] left=[2] top=[1]  ->  [osw 1 tab 1] top=[1]
# verdict=REORDERED
```

Branch (c) opens its new pane in a **different OS window** so no surviving member's adjacency is
perturbed; the mutant reaches the right answer for the wrong reason and stays green. That is
deliberate, and it is what makes (b) the single discriminating branch.

The mutation was applied to the tracked file in place and reverted by overwriting from a pristine
copy; both arms verified by sha256 (`7be0a7bc…0581af` before and after).

## The six bindings, live at once

Three Q12 chord candidates × two Q2 arming spellings. A kitty mouse_map key is
(button, mods, trigger-count, grab-mode), so six distinct chords are needed to hold six bindings
simultaneously; **`opt` and nothing else** selects the spelling, keeping the chord axis and the
spelling axis independent for the operator's hand.

```
mouse_map cmd+shift+left     press       ungrabbed kitten …/kitty-drag-window.py --spelling=preserving
mouse_map cmd+left           press       ungrabbed kitten …/kitty-drag-window.py --spelling=preserving
mouse_map cmd+left           doublepress ungrabbed kitten …/kitty-drag-window.py --spelling=preserving
mouse_map opt+cmd+shift+left press       ungrabbed kitten …/kitty-drag-window.py --spelling=free
mouse_map opt+cmd+left       press       ungrabbed kitten …/kitty-drag-window.py --spelling=free
mouse_map opt+cmd+left       doublepress ungrabbed kitten …/kitty-drag-window.py --spelling=free
```

**Every binding is on LEFT, and that is a safety requirement rather than a preference:** the only
mouse-driven clear of `window_being_dragged` is a LEFT release (v0.48.2 `tabs.py:1866`), so a chord
on any other button arms a flag no release can clear. The dry run asserts it (`every binding is on
LEFT: OK`) and refuses otherwise. `drag_threshold 5` is pinned explicitly because at 0 the kitten
declines by design (G4) and the dead band is precisely what Q8 is about.

## What it verdicts, and the one thing it deliberately does not

**Layout (Q9/Q12) — a real machine verdict**, from the graph differ, with three distinguishable
outcomes: REORDERED (the chord moved a pane), NO-CHANGE (no gesture observed), SET-CHANGED
(inconclusive — a pane was opened or closed, so nothing can be attributed).

**Graphics (Q10) — stated, not faked.** The script captures a before frame, a burst spanning the
gesture and an after frame, all scoped to the sandbox OS window by `platform_window_id` so nothing
else on the operator's screen is photographed, and it hands over one `open <dir>` command. It does
**not** invent a pixel verdict: "did the image survive the relayout" is a two-second look, and a
manufactured answer to it would be the same defect the witness rule exists to prevent. If
`screencapture` returns nothing the script names macOS Screen Recording permission as the cause and
reports Q10 **UNANSWERED** rather than inferring anything.

**Q8/Q12 preference** is the operator's by construction and the script says so.

## Safety — enforced as refusals, measured firing

`~/.config/kitty/kitty.conf` is a symlink into the shared checkout and the live kitty's
`__watch_conf__` child reloads it ~100 ms after any write there (plan § 2). The driver therefore
refuses rather than intends. All four refusals were executed:

```
KDW4_SOCK=/tmp/kitty-999.sock  → REFUSED: socket … is inside the /tmp/kitty-* glob that
                                          bin/cc-kitty-socket:48 scans.
KDW4_SOCK=/tmp/kitty-633       → REFUSED (same rule; 633 is the operator's LIVE kitty today)
KDW4_ROOT=~/.config/kitty/…    → REFUSED: RUN_ROOT … is inside /Users/chrisren/.config/kitty
KDW4_SOCK=relative.sock        → REFUSED: socket path must be absolute
```

Preflight also proves the `env -u` drop actually works before addressing anything, rather than
assuming it. **The script sends no signals at all** — there is no `kill`, `pkill`, `killall` or
`signal-child` in it; teardown is `kitten @ close-window --match all` against its own socket, which
leaves the sandbox process idle with zero windows and makes the next run a relaunch. That is also
what makes it re-run safe without deleting anything recursively.

⚠️ **One refusal has an empty population, stated rather than hidden.** The "our socket is a live
kitty's socket" check can never fire, because every live kitty socket is `/tmp/kitty-<pid>` and the
glob rule above already refuses that path. It is defence in depth against a future `listen_on`
change, not a check that has ever caught anything.

## The binary actually used, and why that is announced

The 0.48.2 build tree was **absent** — `/tmp/kitty-482` is a symlink to `~/kitty-482`, which does
not exist; `/tmp/kbuild/build.log` still read `--- cloning master` at the time of the run. The
driver fell back and said so by name, loudly, and proved identity the only way that works:

```
  binary : /Applications/kitty.app/Contents/MacOS/kitty
  source : THE INSTALLED APP — the 0.48.2 build tree was NOT found
  proof  : kitty +runpy 'import kitty; print(kitty.__file__)'   (never --version:
           master at 1d67ecd still self-reports 0.48.2)
           -> …/python-lib.bypy.frozen/kitty/__init__.pyc
```

This is the operator's shipped 0.48.2 and is a legitimate W4 target — route A is config-only and
needs no patched build. It is announced because the answer is about *this* binary and no other.

## End-to-end, with no gesture performed

The driver was run for real (`--watch-secs 8 --no-screenshot`, so no `screencapture` and therefore
no TCC prompt) and **no drag was performed or simulated**. It brought up two stacked panes, placed
the kitty logo in the bottom pane as the Q10 subject, read its own baseline, watched, and then
reported the truth:

```
  sandbox : two stacked panes up on /tmp/kdw4.sock
  Q10    : kitty logo placed in pane 2 (bottom)
  wrote /tmp/kdw4/before.graph.json (2 pane(s))
VERDICT: NO-CHANGE — the layout is identical.
  panes before=2 after=2
verdict=NO-CHANGE
  Q9  : NO GESTURE OBSERVED.
```

**That negative is the load-bearing result of this wave.** The instrument reports "no gesture" when
no gesture happened, which is the property a tool whose job is to witness a human action must have
before its positive is worth anything.

Collateral checks from the same run: the sandbox kitty's stderr carried **one** line and it was an
unrelated OpenGL warning, so all six `mouse_map` lines and every option parsed clean; and the W2
kitten resolves and runs under the real kitten dispatcher on this binary —
`kitten @ --to unix:/tmp/kdw4.sock kitten …/kitty-drag-window.py --selftest` returned
`"ok": true` with `"final_state": [0, false, 0.0, 0.0]`, i.e. the drag flag **cleared**, not wedged.

Both sandboxes were then torn down to zero windows by remote control. The operator's kitty (**pid
633** today — the box rebooted at 15:50, so the plan's `97084` is stale) was never addressed,
never signalled, and is still live.
