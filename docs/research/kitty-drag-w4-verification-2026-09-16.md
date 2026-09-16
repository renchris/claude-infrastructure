# W4 adversarial verification — what I re-derived, and the two defects I found

**2026-09-16, independent verifier.** I did not do W4's work. Every claim below is a command I ran
myself and the output I saw. I performed **no drag** and never addressed the operator's kitty.

## Verdict in one line

The safety envelope is **real and mutation-proven**, the differ is **correct and has genuine power
on the witness axis**, and the script **does print a verdict**. But the handover line — *"one command
for the operator: `bash scripts/kitty-drag-w4.sh`"* — **does not run today**: it exits 2 before
launching anything. Two defects, both in binary selection, neither in the safety or verdict logic.

---

## DEFECT 1 (blocking) — the bare command refuses, rc 2

```
$ bash scripts/kitty-drag-w4.sh --watch-secs 3 --no-screenshot ; echo rc=$?
REFUSED: no kitten beside the kitty binary: /tmp/kitty-482/kitty/launcher/kitten
rc=2
```

Cause, `scripts/kitty-drag-w4.sh:589`:

```bash
KITTEN_BIN="$(dirname "$KITTY_BIN")/kitten"
```

This assumes the `kitten` sits beside the `kitty` binary. True of
`/Applications/kitty.app/Contents/MacOS/` (both files are there), **false of a kitty BUILD TREE**,
whose `kitty/launcher/kitty` is a symlink into `kitty.app/Contents/MacOS/`:

```
$ ls -la ~/k482/kitty/launcher/kitty
lrwxr-xr-x  kitty -> kitty.app/Contents/MacOS/kitty
$ ls ~/k482/kitty/launcher/kitty.app/Contents/MacOS/
kitten   kitty
$ for f in ~/k482/kitty/launcher/{kitty,kitten}; do printf '%s : ' "$f"; [ -x "$f" ] && echo TRUE || echo FALSE; done
/Users/chrisren/k482/kitty/launcher/kitty  : TRUE
/Users/chrisren/k482/kitty/launcher/kitten : FALSE
```

**Why the implementer never hit it: the build tree arrived AFTER their run.** Their residual
("the 0.48.2 build tree never arrived; `/tmp/kitty-482 -> ~/kitty-482` does not exist") was true when
measured and is now false — `/tmp/kitty-482` was re-pointed at **16:18**, three minutes after their
last file write (16:16):

```
$ ls -la /tmp/kitty-482
lrwxr-xr-x  Sep 16 16:18  /tmp/kitty-482 -> /Users/chrisren/k482
$ git -C ~/k482 describe --tags
v0.48.2
$ git -C ~/k482 log -1 --format='%H %d %s'
2cb1d95c3accadd536bd66ba6bda044973440177  (grafted, HEAD, tag: v0.48.2) version 0.48.2
```

So the tree is a genuine **v0.48.2** build, it is now the script's FIRST candidate, and reaching it
is what breaks the script. Proof the rest works once the path is right — pointing `KDW4_KITTY` at the
**resolved** binary (where a `kitten` does sit beside it):

```
$ KDW4_KITTY=~/k482/kitty/launcher/kitty.app/Contents/MacOS/kitty \
    bash scripts/kitty-drag-w4.sh --watch-secs 3 --no-screenshot ; echo rc=$?
  binary : /Users/chrisren/k482/kitty/launcher/kitty.app/Contents/MacOS/kitty
  proof  -> /Users/chrisren/k482/.../../../../../kitty/__init__.py
rc=0
```

**Fix:** resolve the symlink before `dirname` (`realpath`/`python3 -c os.path.realpath`), or fall
back to `$(dirname "$KITTY_BIN")/kitty.app/Contents/MacOS/kitten`, or continue the candidate loop
instead of `die`-ing. Also add `$HOME/k482/...` to `BUILD_482_CANDIDATES` — the tree the fleet
actually built is at `~/k482`, not `~/kitty-482`.

## DEFECT 2 (mis-attribution) — the reuse path certifies a binary it then does not use

`launch_sandbox` reuses an existing sandbox on the socket. `prove_identity` has already run
`$KITTY_BIN +runpy` in a **throwaway process**. When the two disagree, the script prints an identity
for a binary the gate does not execute. Measured, same run, one variable:

```
$ grep -E 'binary  *:|reusing' <the run's output>
  binary : /Users/chrisren/k482/kitty/launcher/kitty.app/Contents/MacOS/kitty
  reusing the existing sandbox on /tmp/kdw4.sock (re-run safe)

$ ps -axo pid=,lstart=,command= | grep kdw4.sock | grep -v grep
75566 Wed 16 Sep 16:15:29 2026  /Applications/kitty.app/Contents/MacOS/kitty --listen-on unix:/tmp/kdw4.sock ...
```

The script's own header says the fallback is announced *"because the answer is about THIS binary and
no other."* On the reuse path that sentence is false. **Fix:** record the chosen binary in
`$RUN_ROOT/binary.txt` at launch and refuse (or relaunch) on mismatch.

---

## What I re-derived and CONFIRMED

### Safety — every refusal fires, and each was exercised by me

| Probe I ran | Result |
|---|---|
| `KDW4_SOCK=/tmp/kitty-633` | `REFUSED: socket … is inside the /tmp/kitty-* glob`, rc 2 |
| `KDW4_SOCK=/private/tmp/kitty-999` | same refusal |
| `KDW4_SOCK=rel.sock` | `REFUSED: socket path must be absolute` |
| 120-char socket | `REFUSED: socket path is 120 chars; Darwin caps sun_path near 104` |
| `KDW4_ROOT=$HOME/.config/kitty/evil` | `REFUSED: RUN_ROOT … is inside /Users/chrisren/.config/kitty` |
| `KDW4_ROOT=$HOME/Development/claude-infrastructure/evil` | `REFUSED: … is inside …/claude-infrastructure` |

None of the refused runs created anything (`/tmp/kdv2-W4-1/` empty afterwards;
`~/.config/kitty/` unchanged, still just the two symlinks and the 2026-09-14 backup).

- **`bash -n` rc 0**, **`shellcheck -s bash` rc 0, zero findings**, `py_compile` rc 0. Re-run by me.
- **No signal is ever sent.** `grep -nE '\bkill\b|pkill|killall|signal-child|SIGUSR|97084'` returns
  three hits and **all three are inside comments** (lines 19, 34, 35). No executable signal exists.
- **No recursive delete.** The only `rm` are two `rm -f` on single files (`:398` a stale socket,
  `:461` a zero-byte screenshot). Nothing that trips a destructive-command prompt.
- **`env -u` covers all three vars at every executing site.** Three binary-invoking lines exist
  (`:249` `+runpy`, `:261` `kit()`, `:401` the launch) and each is prefixed
  `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`. The S3 preflight probe is a live
  positive/negative pair: it printed `note: this shell is inside kitty (KITTY_PID=633)` (parent HAS
  the vars) while the `env -u sh -c` probe read back empty.
- **Only one `@` invocation site exists and it always passes `--to unix:$SOCK`** — the script has no
  path that can address the operator's socket.
- **Identity by `+runpy`, never `--version`.** `grep -- '--version'` hits only two comment lines;
  `+runpy` appears 5 times, and the live run printed the `kitty/__init__.py` path.
- **The operator's kitty was untouched by all of my runs.** pid 633 alive throughout
  (etime 23:42 → 25:53); `~/Development/claude-infrastructure/config/kitty.conf` mtime
  `2026-09-16T11:49:37` and `~/.config/kitty/` mtime `2026-09-16T15:21:04`, both predating my
  16:19 runs.

🚨 **The plan's named pid is DEAD and the live one is 633.** `ps -p 97084` → **rc 1, zero bytes**.
The real terminal is pid 633, watched by
`kitten __watch_conf__ 633 100 … /Users/chrisren/.config/kitty/kitty.conf`. The hazard is entirely
intact; only its identifier rotted. The script is right not to hardcode either — it refuses on the
identity-free `/tmp/kitty-*` glob.

### The differ — I reproduced the control, the mutant, and added the positive control they lacked

Control, run by me, **plan line asserted** (S6):

```
$ bats tests/kitty-pane-graph.bats
bats rc=0 · 1..14 · ok=14 · not ok=0
```

**My own independently written mutant** (I did not reuse theirs): I moved the ORDER block above the
SET block and changed its loop to `sorted(set(b) & set(a))` — the faithful pre-fix shape that does
not crash. Result, identical to their report:

```
bats rc=1 · 1..14 · ok=11 · not ok=3   (cases 3,4,5 — branch (b) only)
```

and the fabrication itself, on a real 3-pane → 2-pane close:

```
VERDICT: REORDERED — the pane layout genuinely changed.
  panes before=3 after=2
verdict=REORDERED
```

against the pristine file's correct answer:

```
VERDICT: SET-CHANGED — NOT a reorder; a pane was opened or closed.
  gone: 2
verdict=SET-CHANGED
```

Reverted by overwrite; `shasum -a 256` matches the pristine copy byte-for-byte and the suite is
green again (`1..14`, 0 failures).

**Their residual (f) is accurate and I checked it:** branch (c) survives the mutant because its new
pane opens in a different OS window. I confirmed a **same-tab** open *would* have caught it — under
the mutant that synthetic case also prints `verdict=REORDERED` with `panes before=3 after=4`.

**The positive control they did NOT run, which I did.** Their evidence was a synthetic REORDERED and
a real NO-CHANGE. Neither shows the reader detecting a *real* layout change on *real* `kitten @ ls`
data. Against my own sandbox, using `move_window_forward` (a layout change, **not** a drag):

```
$ K action move_window_forward ; K ls > real_after.json
$ python3 scripts/kitty-pane-graph.py diff real_before.json real_after.json
VERDICT: REORDERED — the pane layout genuinely changed.
  moved: window 5  [osw 3 tab 3] bottom=[6]  ->  [osw 3 tab 3] top=[6]
  moved: window 6  [osw 3 tab 3] top=[5]  ->  [osw 3 tab 3] bottom=[5]
verdict=REORDERED
$ … --expect REORDERED → rc 0 ; … --expect NO-CHANGE → rc 1
```

That is exactly the two-pane swap a successful drag produces, on real data. **The instrument is now
controlled in both directions.**

Instrument-error paths also verified by me: empty document, invalid JSON and a missing file each
give `verdict=ERROR` at **rc 2**, never a quiet NO-CHANGE.

### The driver's own safety assertions are live, not decorative

I mutated the generated config in place and reverted:

| Mutant | Result |
|---|---|
| one chord moved to `opt+cmd+middle` | `REFUSED: a binding is not on LEFT; only a LEFT release clears window_being_dragged` |
| one `mouse_map` line deleted | `REFUSED: expected 6 mouse_map lines, generated 5` |

`shasum -a 256` confirms `scripts/kitty-drag-w4.sh` restored byte-identical; `git status --porcelain`
shows both files still `??` (untracked), i.e. no tracked file was edited.

### Idempotency — measured, not asserted

Two consecutive full runs, then a pane census:

```
os windows: 1
  tab 3 layout splits panes [5, 6]
```

One OS window, two panes — no accumulation. `--teardown` run twice: both succeed, and the second is
a clean no-op (the process persists with zero windows because the generated config sets
`macos_quit_when_last_window_closed no`).

### What the operator actually sees

The script prints a **verdict**, not data. Three named outcomes off `verdict=`:

- `REORDERED` → `Q9 : YES -- the chord moved a pane. Route A works end to end on this binary`
- `NO-CHANGE` → `Q9 : NO GESTURE OBSERVED. The layout is byte-identical`
- `SET-CHANGED` → `Q9 : INCONCLUSIVE -- a pane was opened or closed`
- anything else → `Q9 : NO VERDICT -- the differ could not read its own inputs`

The three tokens match `VERDICT_*` in `scripts/kitty-pane-graph.py:104-106` exactly. Q10 prints a
frame count and one `▶ Run this: open <dir>`, or an explicit `UNANSWERED`; Q8/Q12 are stated as the
operator's alone. **Nothing asks him to interpret a graph.**

Collateral, verified by me: the generated 6-binding config **parses clean** in a real kitty — the
sandbox's whole stderr is 408 bytes, one OpenGL warning and three benign
`Failed to send resize signal` lines, no config error — and all six `mouse_map` entries are in the
loaded file, all on `left`.

---

## Residuals I could not clear

1. **The screenshot path is still unexercised.** I deliberately ran `--no-screenshot` throughout:
   `/usr/sbin/screencapture` triggers a macOS Screen Recording TCC dialog, which is the prompt class
   an agent must not provoke. Q10's capture leg remains proven only by code reading.
2. **A malformed baseline collapses the gesture window silently.** In `watch_for_gesture`, any
   non-zero rc from the differ — including the rc 2 *instrument error* — is read as "changed" and
   breaks the loop. If `before.json` is itself unreadable, the first poll (~0.35 s) ends the watch
   and the operator never gets his window; the final line is the honest
   `Q9 : NO VERDICT -- instrument fault`, but the 120 s he was promised is gone. `BEFORE` is never
   validated: the `snapshot --ls` call that would catch it is piped into `sed`, so its rc is
   discarded and `set -e` cannot see it. Not reproduced — reasoned from the code.
3. **I did not perform the drag**, by instruction. Q9/Q10/Q8/Q12 remain the operator's to answer;
   what is verified here is only that the apparatus is safe, self-reading and honest.
