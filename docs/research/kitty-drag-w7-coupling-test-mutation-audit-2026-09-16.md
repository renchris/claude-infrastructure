# W7 — is the coupling test DECORATIVE? A per-case mutation audit

Second independent verifier, 2026-09-16, lens = **the test file itself**, not the config.
A sibling verifier's `kitty-drag-w7-adversarial-verification-2026-09-16.md` already proves the
*config* half (HEAD vs worktree parse to a byte-identical mousemap/keymap). This file is disjoint:
it asks whether `tests/kitty-drag-arm.bats` actually *detects* the errors it names.

Instrument, identified per plan § S7 (never `--version`):

```
$ env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
    /Applications/kitty.app/Contents/MacOS/kitty +runpy 'import kitty; print(kitty.__file__)'
/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/kitty/__init__.pyc
```

No window launched, no live socket touched, nothing signalled. `~/.config/kitty/kitty.conf` was
confirmed to symlink the **shared checkout**, not this worktree, before any file here was mutated:

```
$ readlink ~/.config/kitty/kitty.conf
/Users/chrisren/Development/claude-infrastructure/config/kitty.conf
$ grep -c globinclude /Users/chrisren/Development/claude-infrastructure/config/kitty.conf
0
$ ls -d ~/.config/kitty/drag-arm.d
ls: /Users/chrisren/.config/kitty/drag-arm.d: No such file or directory
```

## Plan line vs test count — matched

```
$ grep -c '^@test ' tests/kitty-drag-arm.bats
10
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats | head -1
1..10
```

Ten `@test` blocks, plan line `1..10`, rc=0, all ok. This is a RESULT, not a cc-bats refusal (S6).

## THE MUTATION AUDIT — one mutant per case, applied to the real tree and reverted by overwrite

Every mutant below was applied by me and re-run by me. `restore` = `cp` from a byte-checked
snapshot in `/tmp/kdv2-W7-1/snap`; no `rm`, no `git checkout`, no `git add`.

| mutant | what it breaks | red case(s) | attributes? |
|---|---|---|---|
| M1 | `globinclude` line deleted from kitty.conf | 1, 2 | 2 only (see below) |
| M2 | `cursor_blink_interval 1.5` appended after the globinclude | **2** | yes |
| M3 | `drag.conf.example` moved away | 3, 6, 7 | no single case |
| M4/M5 | `drag.conf.example` **renamed to `drag.conf`** | 3, 5, 6, 7 | **case 4 stays GREEN** |
| M6 | arming line UNCOMMENTED in the example | **6** | yes |
| M7a | every `CHORD` replaced in the example | **7** | yes |
| M7b | template line hardcodes `cmd+shift+left`, prose still says CHORD | **NONE — all 10 pass** | — |
| M8 | setup.sh creates `drag.conf` as a symlink | **8** | yes |
| M9 | setup.sh creation made unconditional (clobbers armed state) | **9** | yes |
| M10 | the DISARM sentence removed from kitty.conf | **10** | yes |
| M11 | **section 1b deleted entirely from kitty-setup.sh** | 8 only — **case 9 passes vacuously** | — |
| M12 | case 5's positive-control pathspec made unmatchable | **5** | yes — line 118 is LIVE |

Seven of ten cases are attributed by a mutant that reddens that case and nothing else. The
exceptions are below.

## FINDING 1 — case 7 does NOT stop a hardcoded chord (refutes a residual)

The implementer's residual states: *"Case 7 of the suite FAILS if someone hardcodes a chord, so the
placeholder cannot quietly become a default."* Measured false. Case 7 is `grep -q 'CHORD' "$EXAMPLE"`
— a presence test over the WHOLE file, and the file says "CHORD" in three prose sentences.

```
$ sed 's|^# mouse_map <CHORD> press|# mouse_map cmd+shift+left press|' snap/drag.conf.example \
    > config/drag-arm.d/drag.conf.example
$ grep -n 'mouse_map' config/drag-arm.d/drag.conf.example
48:# mouse_map cmd+shift+left press grabbed,ungrabbed <ACTION>
51:# mouse_map cmd+shift+left press grabbed,ungrabbed <kitten under A · mouse_drag_window 2 under B>
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats | sed -n '1p;/^not ok/p'
1..10
```

All ten pass with a concrete chord sitting in the arming template. To hold the stated property the
assertion must be on the arming LINE, e.g. `grep -Eq '^#[[:space:]]*mouse_map[[:space:]]+<CHORD>'`.

## FINDING 2 — case 4 is a tautology over the test's own constant (converges with the sibling)

`base="$(basename "$EXAMPLE")"` is a string operation on the path hardcoded in `setup()`. It reads
nothing from disk. Renaming the file to the exact error the case names leaves it green:

```
$ mv config/drag-arm.d/drag.conf.example config/drag-arm.d/drag.conf
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats | sed -n '1p;/^ok 4/p;/^not ok/p'
1..10
not ok 3 config/drag-arm.d/drag.conf.example exists
ok 4 the example's NAME cannot match the glob — this is the safety property, not a convention
not ok 5 🚨 the tracked tree contains NO config/drag-arm.d/*.conf — the landed diff arms nothing
not ok 6 the example's arming line is COMMENTED OUT
not ok 7 the example refuses to ship a chosen chord — W4 has not ruled
```

Case 4 can only ever go red if someone edits line 51 of the test file. The safety property is real
and is enforced by cases 3 and 5 — case 4 credits nothing. Found independently by the sibling
verifier; recorded here because two independent finds is evidence FOR the call.

## FINDING 3 — case 9 passes vacuously when section 1b is deleted

Case 8 guards its extraction with `[ -s "$frag" ]` and `grep -q 'drag-arm.d' "$frag"`. **Case 9 has
neither.** Delete section 1b outright and case 9 sources an empty fragment, `after == sentinel`, pass:

```
$ python3 -c "...delete lines 225..256 of kitty-setup.sh..."
$ grep -c 'drag-arm' scripts/kitty-setup.sh
0
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats | sed -n '1p;/^not ok/p;/^ok 9/p'
1..10
not ok 8 kitty-setup.sh creates the live drop-in as a REAL dir and REAL file, never a symlink
ok 9 kitty-setup.sh never overwrites an existing drag.conf — that file IS the armed state
```

Case 8 catches it, so the suite is not blind — but case 9 alone credits nothing on that axis. Copy
case 8's two guards into case 9.

## FINDING 4 — the `sed` range endpoint is unasserted (absent-endpoint-selects-everything)

Cases 8 and 9 extract section 1b with
`sed -n '/^# ── 1b\. …/,/^# ── 2\./p' | sed '$d'`, then **`source` the result**. The end marker is
`# ── 2. the it2 translator` in an unrelated section. Rename it and the range runs to EOF:

```
$ sed 's|^# ── 2\. the it2 translator|# ── 2a. the it2 translator|' snap/kitty-setup.sh > setup-renamed.sh
$ sed -n '/^# ── 1b\. the window-drag ARMING drop-in/,/^# ── 2\./p' setup-renamed.sh | sed '$d' | wc -l
     479          # bounded extraction is 32 lines
$ [ -s frag-runaway.sh ] && echo PASSES          -> PASSES
$ grep -q 'drag-arm.d' frag-runaway.sh && echo PASSES -> PASSES
```

Both of case 8's guards accept the 479-line runaway, which contains ~10 `ln -sfn` calls into
`$BIN_DIR`/`$SHIM_DIR` and two `python3` blocks that `open(path,"w").write(...)`. I deliberately did
**not** execute it. `BIN_DIR`/`REPO`/`SHIM_DIR` are assigned at kitty-setup.sh:36-38, *above* the
extracted range, so in the sourced shell they are unset and most writes would target `/` and fail —
the likely symptom is a confusing red, not a damaged `$HOME`. The defect is that nothing asserts the
endpoint exists. Fix: `grep -q '^# ── 2\. ' "$SETUP" || { echo "end marker gone"; false; }` and cap
the fragment length.

## FINDING 5 — the land gate's dead-assertion ratchet will flag line 118

The repo's own analyzer, the one `scripts/ship-land.sh:3480` runs as `DEAD_LINT`:

```
$ python3 scripts/bats-assert-liveness.py tests/kitty-drag-arm.bats
tests/kitty-drag-arm.bats:118: DEAD [cond-keyword] [[ "$output" == *"config/kitty.conf"* ]]
$ python3 scripts/bats-assert-liveness-fix.py --dry-run tests/kitty-drag-arm.bats
would fix   1  tests/kitty-drag-arm.bats
── would revive 1 assertion(s) across 1 file(s)
```

**The line is in fact LIVE at runtime** — mutant M12 made the control pathspec unmatchable and case 5
went red — so this is a false positive *about behaviour* and a true positive *about the gate*:
`ship-land` blocks on lines this land writes. Run the sanctioned fixer
(`python3 scripts/bats-assert-liveness-fix.py tests/kitty-drag-arm.bats`), never a hand-written
`|| false` — the fixer declines at exit 2 rather than guessing for the families it cannot rewrite.

## FINDING 6 — kitty's globinclude DOES match a dotfile; case 5's ARM 1 does not

ARM 1's stated job is the working tree ("git ls-files is blind to an untracked file a working tree is
about to grow"). Measured, it is blind to a dotfile that kitty *would* load:

```
# kitty side, scratch config dir
$ printf 'mouse_map cmd+shift+left press grabbed,ungrabbed mouse_selection normal\n' > $S/drag-arm.d/.hidden.conf
$ kitty +runpy "... len(load_config('$S/kitty.conf').mousemap)"
mousemap_len with a DOTFILE .hidden.conf present = 39     # baseline 37 -> INCLUDED

# the test's own ARM 1, run under bash exactly as written
$ printf '# probe\n' > config/drag-arm.d/.probe.conf
$ bash -c 'found=""; for f in config/drag-arm.d/*.conf; do [ -e "$f" ] && found="$found $f"; done; echo "found=[$found]"'
found=[]
$ /opt/homebrew/bin/bats --tap tests/kitty-drag-arm.bats | sed -n '1p;/^not ok/p'
1..10          # GREEN with an arming dotfile sitting in the tree
```

ARM 2 *would* catch it once tracked — git pathspecs have no dotfile rule:

```
$ git ls-files --others --exclude-standard -- 'config/drag-arm.d/*.conf'
config/drag-arm.d/.probe.conf
```

So the wave's headline property — *the landed diff arms nothing* — survives, because a tracked
dotfile is caught by ARM 2. What fails is ARM 1's documented coverage of the untracked working tree.
Fix: `shopt -s dotglob nullglob` in ARM 1 (or iterate `find "$ARMDIR" -maxdepth 1 -name '*.conf'`).

## What I re-derived and confirmed (implementer's measurements, reproduced)

```
$ kitty +runpy 'import kitty.conf.utils as u; print("include_keys =", u.include_keys)'
include_keys = ('include', 'globinclude', 'envinclude', 'geninclude')

# empty glob is silent, with BOTH controls, scratch copy of the real kitty.conf
A drag-arm.d ABSENT            mousemap 37  rc=0  stderr 0
B dir EMPTY                    mousemap 37  rc=0  stderr 0
C ZERO-BYTE drag.conf          mousemap 37  rc=0  stderr 0
D NEG CTRL real mouse_map      mousemap 39  rc=0  stderr 0      <- glob is not a no-op
E POS CTRL bad directive       mousemap 37  rc=0  stderr 64
                               [0.023] Ignoring unknown config key: this_is_not_a_kitty_option
   BAD_LINES stayed [] in every arm, including E — the channel is STDERR, as the residual says.

# the real repo config, drag-arm.d/ present holding only drag.conf.example
BAD_LINES = []  mousemap_len = 37  rc=0  STDERR_BYTES=0

# globinclude resolves against the GIVEN path, not the symlink target
via SYMLINK path  cursor_blink_interval = 0.99      (live-side drop-in)
via REAL path     cursor_blink_interval = 0.11      (checkout-side drop-in)
both emptied      cursor_blink_interval = -1.0      (kitty default)

# placement is load-bearing
globinclude LAST  -> mouse_selection normal            (the drop-in won)
globinclude FIRST -> mouse_show_command_output         (the top-level line won)
```

All four measurements reproduce exactly. `config/kitty.conf` grew a comment-only EOF block from a
sibling at 16:20 while this ran; the suite stays green and `grep -vE '^[[:space:]]*(#|$)' | tail -1`
still yields `globinclude drag-arm.d/*.conf`, which is a live demonstration that case 2 pins the
right property (last *directive*, not last *line*).

## Restore integrity

```
$ md5 tests/kitty-drag-arm.bats /tmp/kdv2-W7-1/snap/kitty-drag-arm.bats
40d8e651b498b1f4c3045762d1f73385  (both)
$ md5 config/drag-arm.d/drag.conf.example /tmp/kdv2-W7-1/snap/drag.conf.example
928d676e94aaf21b9bfa17820701942e  (both)
$ md5 scripts/kitty-setup.sh /tmp/kdv2-W7-1/snap/kitty-setup.sh
9bad1440c9f4008729b814783cdcdf4e  (both)
```

`config/kitty.conf` differs from my 16:18 snapshot by exactly the sibling's 21-line comment block
appended at 16:20 (verified by `diff`); nothing of mine remains in it.

## FINDING 5, escalated — the DEAD lint is a LAND BLOCKER, and the fix is one line

Read at `scripts/ship-land.sh:3480-3545`: findings on stdout → `gate_red dead-assertion; return 1`,
an explicit **"REAL verdict: exit 6, never a retryable 9"**. Scope is
`git diff --name-only "$range" -- 'tests/*.bats'`, which includes a file the land ADDS. So a `/ship`
of this wave goes red on `tests/kitty-drag-arm.bats:118` unless the fixer is run first.

The sanctioned fixer handles it cleanly — it does **not** decline (exit 2) on this shape. Verified on
a copy in `/tmp/kdv2-W7-1/fixprobe`, the repo file left untouched:

```
$ python3 scripts/bats-assert-liveness-fix.py tests/kitty-drag-arm.bats
fixed   1  tests/kitty-drag-arm.bats
── revived 1 assertion(s) across 1 file(s)
── analyzer now reports 0 dead assertions
$ diff snap/kitty-drag-arm.bats tests/kitty-drag-arm.bats
118c118
<   [[ "$output" == *"config/kitty.conf"* ]]
---
>   [[ "$output" == *"config/kitty.conf"* ]] || false
$ python3 scripts/bats-assert-liveness.py tests/kitty-drag-arm.bats   # rc=0, no output
```

**▶ Before landing:** `python3 scripts/bats-assert-liveness-fix.py tests/kitty-drag-arm.bats`

Note the line is behaviourally live already (M12 reddens case 5), so this is a gate-shape fix, not a
correctness fix — but the gate does not care, and neither does the 3.2h-later corpus red it exists to
prevent.

## Verdict

The wave's headline property holds and I re-derived it independently: `1..10`, rc=0, all ok; ten
`@test` blocks matching the plan line; seven of ten cases attributed by a mutant that reddens only
that case; and the four kitty measurements reproduce exactly. The suite is **not** decorative as a
whole.

What is not true: case 4 credits nothing (tautology over the test's own constant), case 9 credits
nothing when section 1b is deleted, case 7 does not stop a hardcoded chord despite a residual saying
it does, case 5's ARM 1 is blind to a dotfile kitty would load, and the `sed` range that cases 8/9
`source` has no asserted endpoint. None of those breaks "the landed diff arms nothing" — cases 3 and
5-ARM-2 hold that line — but four documented guards do not guard what their comments say.
