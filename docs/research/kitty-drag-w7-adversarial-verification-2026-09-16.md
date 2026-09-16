# W7 adversarial verification — "the landed diff arms nothing"

Independent verifier, 2026-09-16. Every claim below carries the command that produced it and the
literal output. Nothing here was taken from the implementer's report; each measurement was re-run.
Instrument throughout: the operator's own installed kitty, identified per plan § S7 (never
`--version`):

```
$ /Applications/kitty.app/Contents/MacOS/kitty +runpy 'import kitty; print(kitty.__file__)'
/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/kitty/__init__.pyc
```

No window was launched, no live socket touched, nothing signalled. Every sandbox invocation was
prefixed `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`.

## THE DECISIVE MEASUREMENT — the parsed mousemap and keymap are IDENTICAL to HEAD

The safety property is not "no `mouse_map` text was added"; it is "kitty's behaviour is unchanged".
That is directly measurable, and it is the one check that subsumes every other:

```
$ git show HEAD:config/kitty.conf > /tmp/kdv2-W7-0/headcmp/kitty-HEAD.conf
$ cp config/kitty.conf              /tmp/kdv2-W7-0/headcmp/kitty-WT.conf
$ kitty +runpy "from kitty.config import load_config; ... sha256 of the sorted mousemap ..."

kitty-HEAD   mousemap_len = 37 | mousemap_sha = 5575e2ce5ad82923 | BAD = []   rc=0 stderr_bytes=0
kitty-WT     mousemap_len = 37 | mousemap_sha = 5575e2ce5ad82923 | BAD = []   rc=0 stderr_bytes=0

kitty-HEAD   keymap_len = 146 | keymap_sha = 28e48c69ff6f2b57
kitty-WT     keymap_len = 146 | keymap_sha = 28e48c69ff6f2b57
```

The edited config parses to a **byte-identical** mousemap and keymap. Not one binding is added,
removed or changed. This simultaneously proves (i) the diff arms nothing and (ii) the § 7.1
retirements were not performed.

## POST-LAND LIVE SIMULATION — the exact topology, with both controls

Reproduced `~/.config/kitty/kitty.conf -> <shared checkout>/config/kitty.conf` with the post-land
checkout content (edited kitty.conf + the tracked `drag.conf.example`, nothing else):

```
POST-LAND, loaded via the SYMLINK (what his kitty does), no live-side drag-arm.d
                                                  mousemap_len = 37  rc=0  stderr_bytes=0
CONTROL, loaded via the REAL checkout path         mousemap_len = 37  rc=0  stderr_bytes=0
NEG CONTROL, a real .conf on the LIVE side         mousemap_len = 39  rc=0  stderr_bytes=0
NEG CONTROL 2, a real .conf on the CHECKOUT side,
               loaded via the SYMLINK              mousemap_len = 37  rc=0  stderr_bytes=0
same checkout-side .conf via the REAL path         mousemap_len = 39  rc=0  stderr_bytes=0
```

37 is informative because the same rig reaches 39 when a real drop-in is present. Two further
facts fall out:

- The implementer's finding 3 is **confirmed**: `globinclude` resolves against the path kitty is
  GIVEN, not the resolved symlink target (NEG CONTROL 2 stays at 37).
- That is also an extra margin of safety the report did not claim: even a real
  `config/drag-arm.d/*.conf` accidentally landed into the shared checkout would **not** be read by
  the operator's live kitty.

## THE `.example` SUFFIX — proven with the strongest form of the test

The implementer proved a glob over an empty directory is silent. The stronger test is to put
genuinely **armed** content in a file named `.example` and show it is ignored, with the identical
bytes under a `.conf` name as the control:

```
A  drag-arm.d empty (baseline)                           blink = 1.5   mousemap = 32
B  LOUD armed content in drag.conf.example               blink = 1.5   mousemap = 32   <- ignored
C  CONTROL: the IDENTICAL bytes in drag.conf             blink = 0.77  mousemap = 34   <- read
D  disarm by EMPTYING drag.conf (never deleting)         blink = 1.5   mousemap = 32
E  the REPO's real example file, as drag.conf.example    blink = 1.5   mousemap = 32
F  the REPO's real example file COPIED to drag.conf      blink = 1.5   mousemap = 32   <- still inert
```

(LOUD content = `cursor_blink_interval 0.77` + one real `mouse_map cmd+shift+left press
grabbed,ungrabbed mouse_selection normal`.) rc=0 and 0 bytes of stderr on every row.

Case F is the finding worth carrying: **the tree is double-locked.** The name cannot match the
glob, AND the content is inert even if someone renames it — every line in the example is commented.

## (a) NO TRACKED FILE MATCHES THE GLOB

```
$ git ls-files -- 'config/drag-arm.d/*.conf'     -> (empty)  rc=0
$ git ls-files -- 'config/drag-arm.d/'           -> (empty)  rc=0   (whole dir is untracked today)
$ find config/drag-arm.d -type f -o -type l      -> config/drag-arm.d/drag.conf.example
$ python3 glob.glob('config/drag-arm.d/*.conf')  -> []
$ git add --dry-run -- config/drag-arm.d config/kitty.conf scripts/kitty-setup.sh tests/kitty-drag-arm.bats
add 'config/kitty.conf'
add 'scripts/kitty-setup.sh'
add 'config/drag-arm.d/drag.conf.example'
add 'tests/kitty-drag-arm.bats'
$ git check-ignore -v config/drag-arm.d/drag.conf.example  -> rc=1 (not ignored; it WILL be added)
```

The lead's commit stages exactly four paths and no `.conf`.

## (d) NOTHING WAS WRITTEN TO ~/.config/kitty

```
$ ls -la ~/.config/kitty/
drwxr-xr-x@ 5  Sep 16 15:21 .
lrwxr-xr-x@ 1  Sep 13 23:55 kitty-title-on.conf -> .../config/kitty-title-on.conf
lrwxr-xr-x@ 1  Sep 16 15:21 kitty.conf          -> .../config/kitty.conf
-rw-r--r--@ 1  Sep 14 23:09 kitty.conf.pre-cc-20260914230902

$ stat -f '%Sm %N' ~/.config/kitty   -> 2026-09-16T15:21:04
$ ls -la ~/.config/kitty/drag-arm.d  -> No such file or directory
$ date                               -> 2026-09-16T16:20:14
```

The directory mtime is frozen at **15:21:04**, which is ~52 minutes before `config/drag-arm.d/` was
created in the worktree (16:13) and before the wave's work. There is no `drag-arm.d` there. Re-read
after all of my own commands: unchanged.

Independently: `install.sh` contains **zero** references to `~/.config/kitty`, `kitty.conf` or
`drag-arm` (`grep -n 'config/kitty\|\.config/kitty\|KCONF\|kitty.conf\|drag-arm' install.sh` -> no
hits), so no installer deploys `config/drag-arm.d/` into the live config dir. Only
`scripts/kitty-setup.sh` writes there, and only when run — it was not run.
`bash scripts/deploy-parity-assert.sh` is clean (no FAIL/DRIFT/missing rows; `config/` is not a
deploy class).

## (e) THE § 7.1 RETIREMENTS WERE NOT DONE

```
$ git diff -U0 -- config/kitty.conf | grep '^@@'
@@ -1288,0 +1289,57 @@          <- ONE hunk, at EOF, 57 insertions, 0 deletions

working tree :601  map cmd+opt+b combine : launch … kitty-pane-title-toggle.sh toggle
git HEAD     :601  map cmd+opt+b combine : launch … kitty-pane-title-toggle.sh toggle   (identical)
working tree :535  map cmd+shift+b combine : launch … kitty-pane-title-overlay.py toggle
git HEAD     :535  map cmd+shift+b combine : launch … kitty-pane-title-overlay.py toggle (identical)
```

`scripts/kitty-pane-title-toggle.sh` and `config/kitty-title-on.conf` both still exist;
`real_bar_key()` / `glance_key()` are still in `tests/kitty-conf-bindings.bats`. Corroborated at the
parsed level by the identical keymap sha above.

Note: the plan cites these at `:552` and `:502`; they are actually at **:601** and **:535**. The
plan's line numbers are stale — a documentation nit, not a defect in the deliverable.

## THE SUITE — reproduced, and mutation-tested

```
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats
1..10
ok 1 .. ok 10        (all ten; plan line present, so S6 is satisfied: this is a RESULT)
bats rc=0
```

Five mutants, applied to a scratch COPY at `/tmp/kdv2-W7-0/mutrepo` (the real tree was never
mutated), each restored afterwards:

| mutant | red case(s) |
|---|---|
| M1 rename `drag.conf.example` -> `drag.conf` | 3, 6, 7 |
| M2 uncomment the arming line in the example | 6 |
| M3 append a line after the `globinclude` | 2 |
| M4 kitty-setup symlinks the live drop-in into the repo | 8 |
| M5 kitty-setup clobbers an existing `drag.conf` | 9 |

Case 5 is red in every row of that table **for an unrelated reason** — the scratch copy is not a git
repository, so its ARM 2 fails closed (`git ls-files failed: fatal: not a git repository`). Failing
closed is the right polarity, but it means the copy carries no information about case 5. Its two
arms were therefore verified directly instead:

```
ARM 1, extracted verbatim, against fixtured ARMDIRs:
  empty  -> ARM1 passes (nothing matches)                                   rc=0
  armed  -> ARM1 RETURNS 1 (refuses): /tmp/kdv2-W7-0/arm1-armed/armed.conf  rc=1

ARM 2 pathspec mechanism, against the REAL repo:
  target  'config/drag-arm.d/*.conf' -> []                                        rc=0
  control 'config/*.conf'            -> [config/kitty-title-on.conf config/kitty.conf]  rc=0
```

## 🚨 ONE REAL DEFECT FOUND — case 4 is VACUOUS

`@test "the example's NAME cannot match the glob"` reads `basename "$EXAMPLE"`, where
`EXAMPLE="$ARMDIR/drag.conf.example"` is a **string literal built in `setup()`**. It never reads the
filesystem, so it asserts a constant and can never fail:

```
$ ARMDIR=/nonexistent/path; EXAMPLE="$ARMDIR/drag.conf.example"; base="$(basename "$EXAMPLE")"
  case "$base" in *.conf) exit 1;; esac; [ "$base" = "drag.conf.example" ]
case-4 logic PASSES with ARMDIR=/nonexistent and NO file on disk at all
```

Confirmed by mutant M1: renaming the file to `drag.conf` — the exact error the case names in its own
comment ("even if config/drag-arm.d/ were symlinked …") — left **case 4 green**. The rename is caught
by cases 3, 6 and 7, and by case 5's ARM 1, so the safety property still holds; case 4 simply credits
nothing. Same family as [One mutant per site] and [Green in both arms is an EQUIVALENCE guard].

The fix is one line — read the directory rather than the literal:

```bash
for f in "$ARMDIR"/*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in *.conf) echo "$f matches the glob"; return 1 ;; esac
done
[ -f "$ARMDIR/drag.conf.example" ]
```

NOT blocking: it weakens a guard against a future edit; it does not affect what this wave lands.

## VERDICT

The lens's five conditions all hold, and the stronger property (the parsed mousemap and keymap are
unchanged from HEAD) holds as well. The landed diff arms nothing.
