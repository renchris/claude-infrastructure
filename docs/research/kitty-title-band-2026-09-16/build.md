# Building and installing a patched kitty 0.48.2 on this box

**Axis:** build + side-by-side install. **Date:** 2026-09-16.
**Trees read:** `~/kitty-482` (detached at `2cb1d95c3` = `v0.48.2` — the build the operator runs),
`~/kitty-dev` (git master `1d67ecd47`). Every `file:line` below names its tree.

Status legend: **CONFIRMED** = I ran the command and show its output · **UNMEASURED** = I could not
run it and say so · **REFUTED** = the repo record's claim did not reproduce.

---

## 0. Headline

**A patched v0.48.2 build is cheap, safe and already proven on this box: 16 s for a full build, 11 s
for an incremental C edit, and every prerequisite is installed.** The blockers are not the ones the
brief anticipated:

1. **Two complete builds already exist** — at `~/kdev` (master) and `~/k482` (v0.48.2) — but **not**
   in the trees the brief names, and **`~/k482` already carries the sibling's patch**, so it is not a
   clean baseline (§ 4, § 7.3).
2. **`make app` hard-fails without pre-built Sphinx docs** — `SystemExit`, `rc 2`. Two empty
   directories fix it, at zero cost (§ 6.4). This is the one step that stops a naive recipe.
3. **`make` alone cannot produce an installable app.** The `kitty/launcher/kitty.app` bundle is
   *not* relocatable (measured: it dies with `can't find '__main__' module`). Only `make app`
   produces a bundle that survives being moved (§ 8.1).
4. **The ~80-character path ceiling is real — and binds only `./dev.sh`, not `make`.** I re-derived
   it exactly (127-char install-name ⇒ 106-char root ⇒ 80-char repo) from the cached tarball;
   `install_name_tool` appears in `bypy/devenv.go` and **nowhere in `setup.py`** (§ 2, § 3).
5. **Side-by-side is safe.** The Homebrew cask owns only `kitty.app`, so `kitty-patched.app` cannot
   be clobbered; the only real trap is that both bundles claim
   `CFBundleIdentifier = net.kovidgoyal.kitty` (§ 8.3, § 8.5).

**The recipe is in § 6.2 and it is tested end to end**, producing a patched, relocatable
`~/ktb482/kitty.app` whose patch is confirmed against a valid stock-v0.48.2 control.

---

## 1. Build prerequisites, and what is actually on this box

### 1.1 What the source says it needs

`~/kitty-482/docs/build.rst:14-22` — the sanctioned path is **not** a system-library build:

> All you need to get started is a C compiler and the go compiler … `./dev.sh build` … downloads all
> the major dependencies of kitty as pre-built binaries for your platform and builds kitty to use
> these rather than system libraries.

`~/kitty-482/docs/build.rst:78-108` lists the *system-library* build's deps (the other path):

| Kind | Packages |
|---|---|
| Run-time | `python`, `harfbuzz` >= 2.2.0, `zlib`, `libpng`, `liblcms2`, `libxxhash`, `openssl` (`pixman`/`cairo`/`freetype`/`fontconfig`/`libcanberra` explicitly **not needed on macOS**) |
| Build-time | `gcc` or `clang`, `simde`, `go` >= go.mod's version, `pkg-config`, Symbols NERD Font Mono |

`~/kitty-482/go.mod:3-4`:
```
go 1.26.0
toolchain go1.26.5
```

`~/kitty-482/Brewfile` (the project's own Homebrew manifest): `zlib xxhash simde python imagemagick
harfbuzz sphinx-doc go`.

### 1.2 Measured on this box (CONFIRMED — commands and output)

```
$ command -v go && go version
/opt/homebrew/bin/go
go version go1.27.1 darwin/arm64
$ python3 --version
Python 3.11.4          # /Library/Frameworks/Python.framework/Versions/3.11/bin/python3
$ pkg-config --version
2.5.1                  # /opt/homebrew/bin/pkg-config
$ clang --version
Apple clang version 17.0.0 (clang-1700.6.4.2)
Target: arm64-apple-darwin24.6.0
$ xcode-select -p
/Applications/Xcode.app/Contents/Developer
$ make --version | head -1
GNU Make 3.81          # /usr/bin/make
$ brew --version | head -1
Homebrew 7.0.3
```

`pkg-config --modversion` for each library dep:

| Package | Version | Verdict |
|---|---|---|
| `harfbuzz` | 14.3.1 | PRESENT (>= 2.2.0 required) |
| `zlib` | 1.2.12 | PRESENT |
| `libpng` | 1.6.58 | PRESENT |
| `lcms2` | 2.19 | PRESENT |
| `libxxhash` | 0.8.3 | PRESENT |
| `openssl` | 3.6.4 | PRESENT |
| `fontconfig` | 2.18.3 | present (not needed on macOS) |
| `freetype2` | 26.6.20 | present (not needed on macOS) |

`brew list --versions`: `go 1.27.1`, `harfbuzz 11.1.0 12.1.0 14.3.1`, `imagemagick 7.1.2-18`,
`libpng 1.6.58`, `little-cms2 2.19`, `openssl@3 3.6.4 3.6.3`, `simde 0.8.2`, `xxhash 0.8.3`,
`python@3.13 3.13.3`.
`ls /opt/homebrew/include/simde/` → `arm  check.h  debug-trap.h …` (simde headers present).

### 1.3 The one gap

`ls ~/kitty-482/fonts/` → **`No such file or directory`**. Symbols NERD Font Mono is a build-time
dependency (`docs/build.rst:106`) and is **not** in the tree. `./dev.sh deps` downloads it
(`~/kitty-482/bypy/devenv.go:28`, `NERD_URL = https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz`).
On the `make app` (system-library) path this must be supplied separately or the build will say so.

**Verdict on prerequisites: every toolchain and library prerequisite is present and new enough.
The only missing item is the NERD symbols font, which `./dev.sh deps` fetches.**

---

## 2. The two build paths are NOT the same build, and only one has a path ceiling

This is the finding that reorganises the rest of the document. `~/kitty-482` offers two routes and
the repo record treats them as one.

| | **Route A — `./dev.sh build`** | **Route B — `make` / `make app`** |
|---|---|---|
| Libraries | **Downloads a prebuilt bundle** (`~50 MB`) into `<repo>/dependencies/darwin-arm64`, incl. its own Python framework | Links against **Homebrew** libs already on this box |
| Source | `docs/build.rst:14-28` (~/kitty-482) | `Makefile:12-14`, `:36-37` (~/kitty-482) |
| Relocation | `install_name_tool` rewrites every `.so`/`.dylib` — `bypy/devenv.go:134`, walk at `:333-336` | **none** |
| **Path-length ceiling** | **YES — 80 chars (§ 3)** | **NO** (see the grep below) |
| Python used | the bundle's own 3.14 | whatever `python3` resolves to first on `PATH` |
| Network needed | yes (tarball + NERD font) | only for the NERD font, and that can be seeded offline |

**The ceiling binds Route A only — CONFIRMED by grep, both trees:**

```
$ grep -n "install_name_tool" ~/kitty-482/setup.py          # → no output, rc 1
$ grep -n "install_name_tool" ~/kitty-482/bypy/devenv.go
134:	c := exec.Command("install_name_tool", cmd...)
```

`setup.py` never calls `install_name_tool`. The relocation that fails at a long path is entirely a
property of `./dev.sh deps` rewriting *someone else's* prebuilt binaries. **A `make` build has no
prebuilt bundle to relocate and therefore no path ceiling.** The repo record
(`docs/plans/KITTY_DRAG_ACTION.md:627`, `docs/research/kitty-drag-action-implementation-2026-09-16.md:1116`)
states the ceiling without this qualification; it is correct about Route A and over-general about
the build as such.

---

## 3. The ~80-character ceiling — INDEPENDENTLY CONFIRMED by direct measurement

The record derived `max_root_len = 106 ⇒ repo path ceiling 80` by binary search against a pristine
re-extraction. I re-derived it from the **cached tarball** (`~/kdev/dependencies/macos-64.tar.xz`,
49,622,064 bytes) without re-downloading anything, and got the **same number**.

**The mechanism, precisely.** `bypy/devenv.go:106-118` (~/kitty-482) matches a load command whose
path begins `@rpath/` and rewrites it to `<root_dir>/lib/<basename>`, where
`root_dir() = <repo>/dependencies/darwin-arm64` (`:30-36`). For `pyexpat`, the load command is
`@rpath/libexpat.1.dylib` (23 chars) and the replacement is `<repo>/dependencies/darwin-arm64/lib/libexpat.1.dylib`.
The file is a **fat binary (x86_64 + arm64)**, which is why its Mach-O header padding is tight:

```
$ otool -L <pristine pyexpat.cpython-314-darwin.so>
… (architecture x86_64):   @rpath/libexpat.1.dylib …
… (architecture arm64):    @rpath/libexpat.1.dylib …
```

**Measured ceiling (CONFIRMED).** Pristine copy per trial, `install_name_tool -change`, new path
padded to an exact length:

| install-name length | 23 | 60 | 100 | 106 | 110 | 120 | **127** | **128** | 129 | 140 | 160 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| result | OK | OK | OK | OK | OK | OK | **OK** | **FAIL** | FAIL | FAIL | FAIL |

FAIL text: `install_name_tool: changing install names or rpaths can't be redone for: … because larger
updated load commands do not fit`.

**The arithmetic, therefore:**

```
max install-name string          = 127
  − len("/lib/libexpat.1.dylib") =  21
  ⇒ max root_dir                 = 106     ← exactly the record's max_root_len
  − len("/dependencies/darwin-arm64") = 26
  ⇒ MAX REPO PATH                =  80     ← exactly the record's ceiling
```

**Validated against the literal candidate paths (CONFIRMED):**

| repo path | len | install-name len | verdict |
|---|---|---|---|
| `/Users/chrisren/k482` | 20 | 67 | **OK** |
| `/Users/chrisren/kitty-482` | 25 | 72 | **OK** |
| `/Users/chrisren/Development/.worktrees/kitty-title-band` | 55 | 102 | **OK** |
| this session's scratchpad root `…/5cea01e1-…/scratchpad/kitty-482` | 131 | 178 | **FAIL** |

**Two honest limits on this measurement.** (1) It is one file. The record says every other file in
the bundle tolerates ≥260 and that exactly one lacks padding; I did not re-verify the "every other"
half — **UNMEASURED**. (2) 127 is a property of *this tarball* (upstream-rebuilt 2026-09-16 07:51),
not of kitty. Keep well under 80 and let `deps` shout if it ever changes.

### 3.1 Recommended durable build location

**Use `~/kitty-482` (25 chars) — the tree the brief names — or `~/k482` (20).** Both are far under
the ceiling, both are under `$HOME`, and neither is reaped on reboot. `/private/tmp` satisfied the
ceiling and silently sacrificed durability: it was reaped at 15:50 today, destroying both built
trees (`docs/research/kitty-build-recipe-2026-09-16.md:4-8`). `/private/tmp/kitty-dev` and
`/private/tmp/kitty-482` exist today only as **symlinks** into `~/kdev` and `~/k482`:

```
$ readlink /private/tmp/kitty-dev  →  /Users/chrisren/kdev
$ readlink /private/tmp/kitty-482  →  /Users/chrisren/k482
```

🚨 **The tree is location-bound.** `docs/build.rst:36-39` (~/kitty-482): *"the built kitty executable
assumes it will find source in whatever directory you first ran `./dev.sh build` in. If you
move/rename the directory, run `make clean && ./dev.sh build`."* Choose the path **before** the
first build.

---

## 4. What is ALREADY built on this box (brief item 5) — answered first, because it changes the plan

🚨 **Two complete kitty builds already exist, and they are NOT in the trees the brief names.**

| Tree | HEAD | Built? | Route | Links against | Size |
|---|---|---|---|---|---|
| `~/kdev` | `1d67ecd` (master) | **YES** | **A** (`./dev.sh build`) | `~/kdev/dependencies/darwin-arm64/…` | 506 MB |
| `~/k482` | `2cb1d95` (**v0.48.2**) **+ the sibling's patch, see below** | **YES** | **B** (`make`) | `/opt/homebrew/opt/{python@3.14,harfbuzz,xxhash}/…` | 78 MB |
| `~/kitty-dev` | `1d67ecd47` (master) | **no** | — | — | 103 MB |
| `~/kitty-482` | `2cb1d95c3` (v0.48.2) | **no** | — | — | 28 MB |

`~/kitty-482` is a **git worktree of `~/kitty-dev`** (`cat ~/kitty-482/.git` →
`gitdir: /Users/chrisren/kitty-dev/.git/worktrees/kitty-482`; `git -C ~/kitty-dev worktree list`
confirms both). Both are **pristine**: no `fonts/`, no `dependencies/`, no
`kitty/launcher/kitty`, zero `*.so`.

**Artifacts (CONFIRMED, `stat`):**

```
~/k482/kitty/launcher/kitty.app/Contents/MacOS/kitty     115,656 B   17:14
~/k482/kitty/launcher/kitty.app/Contents/MacOS/kitten 24,839,874 B   17:14
~/k482/kitty/fast_data_types.so                        1,515,600 B   17:14
~/k482/build/*.o  → 87 objects + compile_commands.json
~/kdev/kitty/launcher/kitty                              115,656 B   16:21
~/kdev/kitty/launcher/kitten                          29,555,890 B   16:21
~/kdev/kitty/fast_data_types.so                        1,584,496 B   16:21
```

**How I know which route each used — `otool -L` on `fast_data_types.so`:**

```
~/k482 → /opt/homebrew/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/Python
         /opt/homebrew/opt/harfbuzz/lib/libharfbuzz.0.dylib          ← Homebrew = Route B
~/kdev → /Users/chrisren/kdev/dependencies/darwin-arm64/python/…/Python
         /Users/chrisren/kdev/dependencies/darwin-arm64/lib/libharfbuzz.0.dylib  ← bundle = Route A
```

`~/k482` has **no `dependencies/` directory at all**, which independently confirms it never ran
`./dev.sh deps`. **Both routes are therefore proven to work on this box**, each at a durable short
path.

**No `kitty.app` package exists anywhere.** Neither tree has a root-level `kitty.app`; the only
bundles are the `kitty/launcher/kitty.app` *minimal* bundles, and those are not installable (§ 6.1).
`find $HOME /private/tmp -name kitty.app` outside these two trees and `/Applications` → nothing.

---

## 5. Verifying WHICH kitty a binary is (brief item 3)

🚨 **`--version` is useless, CONFIRMED.** All three report the same string — including master:

```
$ ~/k482/kitty/launcher/kitty --version          → kitty 0.48.2 created by Kovid Goyal
$ /Applications/kitty.app/Contents/MacOS/kitty --version → kitty 0.48.2 created by Kovid Goyal
```

**The check that works** (`kitty +runpy`, measured 2026-09-16; each is distinct):

| Binary | `kitty +runpy 'import kitty; print(kitty.__file__)'` |
|---|---|
| `~/k482/kitty/launcher/kitty` | `/Users/chrisren/k482/kitty/launcher/kitty.app/Contents/MacOS/../../../../../kitty/__init__.py` |
| `~/kdev/kitty/launcher/kitty` | `/Users/chrisren/kdev/kitty/__init__.py` |
| `/Applications/kitty.app/…/kitty` | `/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/kitty/__init__.pyc` |

**Read it as:** a `.py` under a build tree ⇒ a from-source build (and the path names *which* tree);
a `.pyc` under `…/python-lib.bypy.frozen/` ⇒ the frozen Homebrew-cask build.

A second, independent discriminator worth knowing — it survives even if two trees share a name:

```
$ kitty +runpy 'import sys; print(sys.version)'
~/k482 → 3.14.7 (main, Aug  5 2026 …)        # Homebrew python@3.14
/Applications → 3.14.6                        # the frozen bundle's own python
```

🚨 **`~/k482` is NOT a clean v0.48.2 build — it is the sibling session's PATCHED tree.** I discovered
this by trying to use it as a negative control and getting a positive (§ 7.3). `git -C ~/k482 status
--porcelain` returns exactly the patch's six files:

```
 M kitty/fast_data_types.pyi    M kitty/state.c
 M kitty/glfw.c                 M kitty/state.h
 M kitty/options/utils.py       M kitty/window.py
```

**Do not treat `~/k482` as stock v0.48.2, and do not build in it** — it belongs to the live sibling
session in `/Users/chrisren/Development/.worktrees/kitty-drag-impl`.
The only stock v0.48.2 available for comparison is **`/Applications/kitty.app`** (the cask) and the
pristine worktree `~/kitty-482`.

---

## 6. THE RECIPE — measured end to end, this session, once

I built **v0.48.2 + the sibling's `mouse_drag_window` patch** in a fresh tree and packaged it as a
relocatable `kitty.app`. Every number below is from that run.

### 6.1 Why `~/kitty-482` itself must not be the build tree

Three reasons, in order of how expensive they are to learn:

1. It is a **git worktree of `~/kitty-dev`** and the brief forbids modifying either.
2. **The tree is location-bound after the first build** (`docs/build.rst:36-39`), so the choice is
   one-way.
3. `~/kitty-482` is *pristine* — `ls ~/kitty-482/build` → `No such file or directory`, zero `.o`.
   Building there would leave 30 MB of artifacts in a tree a sibling expects clean.

**Use a private copy.** `cp -R` is sufficient: the build does not need git
(`setup.py:730-731` guards every git call behind `if os.path.exists('.git')`), so the worktree
pointer file can simply be removed.

### 6.2 The commands, exactly as run (all CONFIRMED, rc 0)

```bash
# --- stage a private tree at a short, durable path (22 chars) ---
cp -R ~/kitty-482 ~/ktb482
rm ~/ktb482/.git                      # a FILE (worktree pointer), not a dir; build needs no git

# --- the builtin font: seed it offline from the installed app (no network, no font install) ---
mkdir -p ~/ktb482/fonts
cp /Applications/kitty.app/Contents/Resources/kitty/fonts/SymbolsNerdFontMono-Regular.ttf \
   ~/ktb482/fonts/

# --- apply the patch ---
cd ~/ktb482 && patch -p1 < <repo>/docs/patches/kitty-mouse-drag-window-v0.48.2.patch

# --- 🚨 make app needs man pages + html docs, or it SystemExits at packaging (§ 6.4) ---
mkdir -p ~/ktb482/docs/_build/man ~/ktb482/docs/_build/html

# --- build.  PATH first: a bare python3 here is 3.11.4 and kitty needs >= 3.12 (§ 6.3) ---
export PATH=/opt/homebrew/bin:$PATH
cd ~/ktb482 && make          # run-from-source build
cd ~/ktb482 && make app      # → ~/ktb482/kitty.app, relocatable
```

**Patch application (CONFIRMED):** `--dry-run` then apply, both clean, **6 files, zero rejects,
zero fuzz**: `kitty/fast_data_types.pyi`, `kitty/glfw.c`, `kitty/options/utils.py`,
`kitty/state.c`, `kitty/state.h`, `kitty/window.py`.

### 6.3 Measured cost

| Step | Wall clock | Output |
|---|---|---|
| `cp -R ~/kitty-482 ~/ktb482` | < 1 s | 30 MB |
| `make` (full, 87 C objects + all Go kittens) | **16 s** | rc 0 |
| `make app` (reuses objects) | **3 s** | rc 0, `kitty.app successfully built!` |

```
START = 2026-09-16T22:49:03Z … END = 2026-09-16T22:49:19Z     RC=0   WALL_SECONDS=16
python3 = /opt/homebrew/bin/python3 Python 3.14.7
go      = go version go1.27.1 darwin/arm64
```

This ran at **load average 25-27** with 74 Claude processes live, so 16 s is a *loaded-box* figure,
not a best case. Artifacts: 87 `.o` in `build/`, `fast_data_types.so` 1,515,600 B,
`launcher/kitty.app/Contents/MacOS/{kitty 115,656 B, kitten 24,839,874 B}`, packaged
`kitty.app` **43 MB**.

🚨 **PEAK MEMORY: UNMEASURED, and my first figure was wrong.** My sampler summed
`ps | grep -E 'clang|setup\.py|go build|link|cc1'` and reported **8.1 GB** — which on inspection was
**Cursor renderer helpers and other Claude sessions**, matched on the word `link` in their argv. This
is the repo's own *argv-census* trap: a pattern loose enough to catch the build is loose enough to
catch every sibling agent's brief. I am not quoting a peak. What I can say is bounded and useful:
**the box stayed at 94% free of 64 GB with 0.00 MB swap throughout**, and a kitty compile is ordinary
`clang` on ~87 small translation units — nothing like the `./autoformat` clang-format swarm
(1-19 GB per worker) that panicked this box twice today.

### 6.4 🚨 `make app` hard-fails without pre-built docs — CONFIRMED, with the cheap workaround

`create_macos_bundle_gunk` calls `copy_man_pages` and `copy_html_docs` unconditionally
(`setup.py:1832-1833`, ~/kitty-482), and each raises `SystemExit` on a missing directory
(`setup.py:1464-1468` and `:1483-1487`).

**Measured, both arms, one variable:**

| Arm | Result |
|---|---|
| `make app`, no `docs/_build` | **rc 2** in 2 s — `The kitty man pages are missing. If you are building from git then run: make && make docs (needs the sphinx documentation system to be installed)` |
| `mkdir -p docs/_build/{man,html}` then `make app` | **rc 0** in 3 s — `kitty.app successfully built!` |

**Two empty directories satisfy both checks**, because `copy_man_pages` only globs `*.1`/`*.5` into
the target (an empty glob copies nothing) and `copy_html_docs` does `shutil.copytree` (fine on an
empty dir). The resulting app has no man pages and no bundled HTML docs — irrelevant for a
side-by-side test build, and it avoids installing Sphinx and running a multi-minute docs build.
If you *want* real docs: `./dev.sh deps -for-docs && ./dev.sh docs` (Route A) — **UNMEASURED**, I
did not run it.

---

## 7. Proving the built binary is the PATCHED one

### 7.1 `--version` cannot do it, and neither can `strings`

`--version` is covered in § 5. A second dead instrument, recorded because it looked authoritative:

```
$ strings ~/ktb482/kitty/fast_data_types.so | grep -c mouse_drag_window   → 0
$ strings ~/k482/kitty/fast_data_types.so   | grep -c mouse_drag_window   → 0
```

Zero in both arms. The action *name* lives in Python (`kitty/options/utils.py`), not in the shared
object, so grepping the `.so` for it can only ever return 0 and says nothing about either build.

### 7.2 The discriminator that works — an import probe, two arms

The patch adds two C functions to the module method table
(`state.c` hunk: `M(get_mouse_press_data_for_window, METH_VARARGS)`), so importing one is a direct
test of the compiled artifact:

```bash
kitty +runpy '
import kitty.options.utils as u
print("mouse_drag_window in options.utils:", hasattr(u, "mouse_drag_window"))
from kitty.fast_data_types import get_mouse_press_data_for_window
print("C symbol: PRESENT")'
```

| Arm | `mouse_drag_window` | C symbol |
|---|---|---|
| `/Applications/kitty.app` — stock cask v0.48.2 (**negative control**) | **False** | **ABSENT** — `cannot import name 'get_mouse_press_data_for_window' from 'kitty.fast_data_types'` |
| `~/ktb482` — my patched build (**subject**) | **True** | **PRESENT** |

Both halves move together and in the right direction, so the probe has power.

### 7.3 🚨 My first control was invalid, and this is the reusable half

I first used **`~/k482` as the negative control** and it came back **positive on both fields** —
which reads as "the patch is everywhere, the probe is broken". It was neither. `~/k482` is the
**sibling session's tree and already has the patch applied**; `git status --porcelain` returns
exactly the patch's six modified files. It was never stock v0.48.2.

⇒ **A tree that merely shares a COMMIT with your baseline is not a baseline.** Before using a
checkout as a control, run `git status --porcelain` in it — a dirty tree at the right sha is the
easiest invalid control to reach for, and its false positive points *away* from the truth (it
suggests your probe is wrong rather than your control). Same family as this repo's
*control-must-replay-the-real-artifact*. The only genuine stock v0.48.2 on this box is
**`/Applications/kitty.app`** (and the unbuilt worktree `~/kitty-482`).

**A second instrument error, recorded for the same reason.** `find ~/ktb482/build -name '*.o'
-newermt '2026-09-16 22:45'` returned **0**, which reads as *"the C never recompiled, your patch is
not in the binary"*. False: `-newermt` interprets its argument in the **ambient timezone**, and the
build's `START` was logged in **UTC** (22:49:03Z = 17:49:03 local). The objects were all stamped
17:49:04-17:49:07 local, i.e. squarely inside the build. Pin the timezone on both sides of any mtime
comparison, or compare against a file rather than a literal.

The `.so` hashes also differ between the two patched trees
(`adc2484c…` vs `31189e5a…`) while the launcher binaries are **byte-identical**
(`453768ac…` both) — exactly what the patch predicts, since it touches no launcher source.

---

## 8. Side-by-side install (brief item 4) — tested

### 8.1 The minimal bundle cannot be installed; the packaged one can

This is the single most important mechanical fact, and it is measured both ways:

| Bundle | Made by | Relocatable? |
|---|---|---|
| `<tree>/kitty/launcher/kitty.app` | `make` | **NO** |
| `<tree>/kitty.app` | `make app` | **YES** |

```
# minimal bundle copied to a new path, then run:
/private/tmp/…/reloc/kitty.app/Contents/MacOS/kitty: can't find '__main__' module in
  '/private/tmp/…/reloc/kitty.app/Contents/MacOS/../../../../..'

# packaged bundle copied to a new path, then run:
kitty.__file__ = /private/tmp/…/reloc2/kitty-patched.app/Contents/MacOS/../Resources/kitty/kitty/__init__.py
mouse_drag_window: True      C symbol: PRESENT
```

The minimal bundle resolves the source tree through a **fixed relative path** (`../../../../..`) —
it is a launcher *for the build tree*, not an app. `make app` is therefore mandatory for a
side-by-side install; `make` alone is not enough.

### 8.2 ⚠️ "Relocatable" here means *on this box*, not redistributable

```
$ otool -L <packaged>/Contents/MacOS/kitty | grep -i python
	/opt/homebrew/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/Python
```

A Route-B app is **hard-linked to Homebrew's `python@3.14`**. It runs anywhere on this machine and
breaks if that formula is removed or major-bumped. The cask's app is frozen and self-contained
(`Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/`) — the built one is not.
If you want self-containment, build via **Route A** (`./dev.sh build`), whose app carries the
bundle's own Python — **UNMEASURED for `make app`**, I only packaged the Route-B tree.

### 8.3 The bundle-identity collision, and the fix

Both apps ship **`CFBundleIdentifier = net.kovidgoyal.kitty`** (`setup.py:1708`):

```
$ PlistBuddy -c "Print :CFBundleIdentifier" /Applications/kitty.app/Contents/Info.plist
net.kovidgoyal.kitty
$ PlistBuddy -c "Print :CFBundleIdentifier" <packaged kitty.app>/Contents/Info.plist
net.kovidgoyal.kitty
```

Two bundles with one identifier makes LaunchServices' choice (Dock, `open -b`, default-handler
registration) arbitrary. Give the patched app its own identity — **tested, rc 0, still runs after
the edit**:

```bash
APP=~/Applications/kitty-patched.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.kovidgoyal.kitty-patched" $APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleName        kitty-patched"               $APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName kitty-patched"               $APP/Contents/Info.plist
codesign --force --sign - $APP        # → "replacing existing signature", rc 0
```

Editing `Info.plist` is safe because the as-built signature is **adhoc / linker-signed with
`Info.plist=not bound`** (`codesign -dv`), so the plist is not part of the seal; the re-sign is
belt-and-braces. Contrast the cask's app: `TeamIdentifier=NTY7FVCEKP`, `flags=0x10000(runtime)` —
properly signed, hardened runtime. **The built app is ad-hoc signed, so macOS will not grant it
notification entitlements** (`docs/build.rst:43-49`, ~/kitty-482). Not quarantined, though — it was
never downloaded — so Gatekeeper will not block first launch.

### 8.4 The install, and how to switch back

```bash
# install (NOTHING touches /Applications/kitty.app)
mkdir -p ~/Applications
cp -R ~/ktb482/kitty.app ~/Applications/kitty-patched.app
# …then the four identity commands from § 8.3…

# verify it is the patched one, not the cask one
~/Applications/kitty-patched.app/Contents/MacOS/kitty +runpy \
  'import kitty, kitty.options.utils as u; print(kitty.__file__, hasattr(u,"mouse_drag_window"))'

# switch back: just launch /Applications/kitty.app. Nothing was changed.
# remove the patched one: delete ~/Applications/kitty-patched.app in Finder.
```

**`~/Applications` vs `/Applications`.** `/Applications` is `drwxrwxr-x root:admin` and the operator
**is** in `admin` — I confirmed it is writable with a touch probe, no `sudo` needed. But
`~/Applications` (`drwx------ chrisren`) is the better target: same Finder/Spotlight visibility, zero
chance of colliding with a cask operation, and removable without authentication.

⚠️ **I did not execute the final `cp` into `~/Applications`** — creating an app in the operator's
home was not asked for. Every other step in § 8.3-8.4 was executed and passed at
`/private/tmp/ktb-build/reloc2/kitty-patched.app`, and a copy to `~/Applications` is the identical
operation (§ 8.1 proves relocation to an arbitrary path works).

### 8.5 Will the Homebrew cask clobber it? — **No. CONFIRMED.**

```
$ brew info --cask kitty
==> Artifacts
kitty.app (App)
.homebrew-command-wrappers/kitty  -> kitty   (Command Wrapper)
.homebrew-command-wrappers/kitten -> kitten  (Command Wrapper)
```

The cask owns exactly three artifacts, all named `kitty`/`kitten`. **`kitty-patched.app` is in none
of them**, so `brew upgrade --cask kitty` and `brew uninstall --cask kitty` cannot touch it.

Two details worth knowing before you rely on that:

* **`/Applications/kitty.app` is the real directory; the Caskroom holds a symlink to it**
  (`/opt/homebrew/Caskroom/kitty/0.48.2/kitty.app -> /Applications/kitty.app`). So an upgrade
  replaces that one path and nothing else. Installed 2026-07-31, version 0.48.2 — i.e. the cask and
  `~/kitty-482` are the **same upstream version**, which is what makes the patched build a true A/B.
* **The PATH `kitty` is the cask's, and stays that way**:
  `/opt/homebrew/bin/kitty -> /opt/homebrew/Caskroom/kitty/0.48.2/.homebrew-command-wrappers/kitty`.
  A patched app in `~/Applications` is **not** on `PATH`. If you want to invoke it from a shell, call
  its binary by absolute path — do **not** overwrite `/opt/homebrew/bin/kitty`, which Homebrew owns
  and will rewrite on upgrade.

**The operator's live terminal is `/Applications/kitty.app/Contents/MacOS/kitty` (pid 597)**, so a
side-by-side install leaves all 9 live agent sessions completely untouched.

---

## 9. The edit → rebuild loop the implementation phase will actually live in

Measured in `~/ktb482` after the first build, `PATH=/opt/homebrew/bin:$PATH`, load ~25:

| Change | Wall clock |
|---|---|
| touch `kitty/shaders.c` (the file the proposed `render_a_bar` design patches) → `make` | **11 s** |
| touch `kitty/state.h` (a header the design also touches) → `make` | **11 s** |
| no-op `make` | **3 s** |
| `make app` (re-package after a build) | **3 s** |

A header change costs the same as a single `.c` change here, so the design's
`shaders.c` + `state.h` + `mouse.c` edit set rebuilds in **~11 s**, and a runnable app is **~14 s**
from an edit. Python-only edits (`window.py`, `options/utils.py`) need no rebuild at all — the
packaged app reads `Contents/Resources/kitty/kitty/*.py`.

**This is the number that makes the title-band design tractable:** the C hit test in `mouse.c` and
the bar draw in `shaders.c` can be iterated dozens of times per hour.

---

## 10. What I left on this box

| Path | What | Disposition |
|---|---|---|
| `~/ktb482` | my private v0.48.2 + patch build tree, 22-char durable path, fully built | **KEEP** — this is the phase-3 build tree; it is nobody else's |
| `~/ktb482/kitty.app` | the packaged relocatable app (43 MB), patched | KEEP |
| `/private/tmp/ktb-build/` | scratch: pristine `pyexpat` for the ceiling probe, relocation tests, logs | disposable; reaped on reboot |

**I did NOT touch:** `/Applications/kitty.app`, `~/.config/kitty/`, `~/kitty-dev`, `~/kitty-482`,
`~/kdev`, `~/k482`, the shared checkout, or the live kitty (pid 597). I ran no `kitty @` command
against any instance and started no kitty GUI — every verification was `kitty +runpy`, which opens
no window.

**I never ran `./autoformat`.**

---

## 11. Residual — what I did NOT measure

* **Route A + `make app`.** I packaged only the Route-B (Homebrew-linked) tree. Whether
  `./dev.sh build && make app` yields a self-contained app carrying the bundle's own Python is
  **UNMEASURED**, though § 8.2's `otool` reasoning says it should.
* **The "every other file tolerates ≥260" half** of the ceiling claim. I re-derived the 127/106/80
  numbers from the one file that fails; I did not re-scan the other 48 relocatable files.
* **Real Sphinx docs.** `./dev.sh deps -for-docs && ./dev.sh docs` was not run; I used the
  empty-directory workaround instead.
* **Peak build memory.** My sampler was contaminated (§ 6.3). Bounded only by "94% of 64 GB stayed
  free, 0 swap".
* **GUI launch of the patched app.** Verified by `+runpy` only — I deliberately did not open a
  window on the operator's screen, so nothing here proves the patched build *renders* correctly.

---

## ADVERSARIAL VERIFICATION

**Verifier:** adversarial pass, 2026-09-16, independent re-measurement. Method: every `file:line`
re-opened in the tree it names; every measured claim re-run with a positive **and** a negative arm.
Where the original evidence was an *absence* (a grep that returned nothing), I replaced it with a
positive test. I ran no `kitty @` command against any instance, opened no GUI, and never ran
`./autoformat`.

**Bottom line: 11 of 13 claims stand, several now with controls the original lacked. Two are
overturned, one on the instrument and one on its characterisation of the repo record — and the
RECOMMENDATION has a material defect the claims do not cover.**

### OVERTURNED

#### O-1 — Claim 11 is half wrong: `strings` is NOT a dead instrument. The needle was wrong.

The write-up generalised *"`strings … | grep mouse_drag_window` returns 0 in both arms"* into
*"`strings` is a dead instrument."* §7.1 itself gives the reason it returned 0 — the option **name**
lives in `kitty/options/utils.py`, not in the `.so` — and then indicts the tool instead of the query.
Grep a **C symbol the patch adds** and it separates cleanly, with a positive control proving the
instrument reads both files:

| `strings <so> \| grep -c` | stock cask `.so` | `~/ktb482` patched `.so` |
|---|---|---|
| `get_mouse_press_data_for_window` | **0** | **1** |
| `mouse_drag_window` (the write-up's needle) | 0 | 0 |
| `set_window_render_data` (**positive control**) | 2 | 1 |

Stock `.so` = `/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/kitty.fast_data_types.so`.
(`nm -gU` is useless here — both files export exactly 8 symbols; the module method table is data,
not an exported symbol. That *is* a dead instrument, and it is a different one.)

**CORRECTED CLAIM.** `strings <fast_data_types.so> | grep -c get_mouse_press_data_for_window` is a
valid, ~0.2 s discriminator: **1 = patched, 0 = stock**, with `set_window_render_data` as the
control that proves the read happened. It is *strictly better* than `+runpy` for one purpose — it
identifies a bundle **without executing it**, which matters for a bundle that is broken,
adhoc-signed, or that you do not want to launch. `+runpy` remains the right check for the assembled
app (it also proves the Python layer matches the C layer). Keep both; retire neither.

#### O-2 — Claim 4's substance is right and its evidence was blind; its characterisation of the repo record is wrong.

*The evidence.* `grep -n install_name_tool setup.py` → rc 1 confirms (I re-ran it). But an absence
from one file cannot establish that **no** mechanism on the `make` path is path-length-sensitive.
I replaced it with the positive test the claim needed — a real build at an over-ceiling path:

| repo path length | `make` | `make app` | app runs (`+runpy`) |
|---|---|---|---|
| 97 chars (17 over the Route-A ceiling) | **rc 0, 15 s, 87 objs** | **rc 0, 4 s** | **OK** |
| 121 chars (past the 131-char case the record shows FAILING for Route A) | **rc 0, 15 s, 87 objs** | — | — |

Zero `install_name_tool` / `do not fit` / `File name too long` lines in either log.

*The characterisation.* The write-up tells other agents to carry the correction *"the repo record
states the ceiling without this qualification."* **It does not.** Both sites it cites scope the wall
to `dev.sh` explicitly:

* `docs/research/kitty-drag-action-implementation-2026-09-16.md:1102` — the heading's own first
  sentence: *"**`./dev.sh deps` FAILS at the session scratchpad path**"*; the whole mechanism
  paragraph is about the prebuilt bundle.
* `docs/plans/KITTY_DRAG_ACTION.md:625` — *"`./dev.sh deps` fails at a long path."*

**CORRECTED CLAIM.** The ~80-char ceiling binds Route A only — now **positively measured**, not
inferred from a grep. The repo record already attributes it correctly at both detailed sites; the
only unqualified restatement is the one-line summary at `docs/plans/KITTY_DRAG_ACTION.md:1589`
(*"The build path ceiling is 80 characters"*). Fix that **one line**; do not rewrite the record.

#### O-3 — Claim 7/8 name the wrong number of contaminated trees. `~/kdev` is patched too.

§7.3's lesson — *"a tree that merely shares a COMMIT with your baseline is not a baseline"* — was
applied to `~/k482` and not re-run on the other pre-existing build, which the tables list as plain
`(master)`:

```
$ git -C ~/kdev status --porcelain
 M docs/changelog.rst        M kitty/state.c
 M kitty/fast_data_types.pyi  M kitty/tabs.py
 M kitty/options/utils.py     M kitty/window.py
A  kitty_tests/window_drag.py     ?? .w5bin/
```

`grep -c mouse_drag_window kitty/options/utils.py` → `k482 4 · kdev 4 · ktb482 4 · kitty-482 0 ·
kitty-dev 0`. `~/kdev` carries a **different variant** of the patch (it touches `tabs.py` and adds a
test; it does **not** touch `glfw.c`/`state.h`) — i.e. the master-branch form, mid-development.

**CORRECTED CLAIM.** **Neither** pre-existing build is stock. `~/k482` = v0.48.2 + the 6-file
v0.48.2 patch; `~/kdev` = master + a 7-file master-variant patch, still moving. The only stock
v0.48.2 on this box is `/Applications/kitty.app`; the only clean *sources* are the unbuilt worktrees
`~/kitty-482` and `~/kitty-dev` (re-verified: 0 `.so`, no `build/`, no `fonts/`, no launcher, clean
porcelain). Run `git status --porcelain` on **every** tree before using **any** of them as a control.

#### O-4 — Claim 13's number is right and its framing is wrong: the loop is LINK-bound, not edit-bound.

Presented as *"11 s for a C file or header change"*, which reads as a per-edit cost. Re-measured in
`~/ktb482` (`PATH=/opt/homebrew/bin:$PATH`, load 22-24, objects counted against a marker file to
avoid the `-newermt` TZ trap §7.3 already names):

| edit | wall | objects rebuilt |
|---|---|---|
| no-op `make` | 3 s | 3 (launcher only) |
| `shaders.c` alone | **9 s** | **1 / 87** |
| `state.h` alone | 11 s | 23 / 87 |
| **`shaders.c` + `state.h` + `mouse.c` — the design's actual edit set** | **10 s** | 23 / 87 |
| `make app` re-package | 4 s | — |

One object and twenty-three cost the same. The cost is the **fixed link + go-tool step**, so it is
flat in edit size — which the repo record had already measured and stated
(`docs/research/kitty-drag-action-implementation-2026-09-16.md:1095`: *"a C edit costs ~9s of which
~8s is the fixed link + go-tool step"*), a figure the write-up neither cites nor reconciles with its
own 11 s.

**CORRECTED CLAIM.** The edit→runnable-app loop is **~10 s ± 1 s regardless of how many C files the
design touches**, plus 4 s to re-package. The conclusion the write-up draws is *strengthened*: the
design's three-file edit set is no more expensive than a one-line change, so there is no incentive
to batch edits. **And the header-dependency question — never asked, and the one that could have
invalidated the whole loop — resolves clean:** `setup.py:987` compiles with `-MMD` and writes
`build/*.d`; exactly **23** dep files name `kitty/state.h` and exactly **23** objects rebuilt, set
difference empty. So adding a field to a struct in `state.h` (which the `render_a_bar` design does)
rebuilds every dependent and cannot produce a silent ABI mismatch. *(My first count of 52 was my own
instrument error — a loose `state.h` grep matching CPython's `pystate.h`.)*

#### O-5 — The RECOMMENDATION has a defect no claim covers: the proposed phase-3 tree has no version control.

`~/ktb482` was created by `cp -R` and then `rm ~/ktb482/.git` (§6.2, by design — the build needs no
git). Confirmed: `git -C ~/ktb482 status` → `fatal: not a git repository`. The consequence is
specific to what phase 3 must *produce*:

* **no `git diff`** — the deliverable of the title-band work is a patch, and this tree cannot emit
  one of its own work alone;
* **no branch / stash / bisect / `git checkout --` on a bad edit**;
* it is **pre-loaded with the sibling's drag patch**, and that patch's `state.h` hunk lives in the
  same file the design edits (drag at `state.h:~448`, `OSWindow`; the design at `state.h:220-226`
  `WindowBarData` / `:276` `title_bar_data`). Disjoint regions, so no textual conflict — but
  `diff -u ~/kitty-482 ~/ktb482` after the title-band work emits **one patch carrying both
  features**, unsplittable.

**CORRECTED RECOMMENDATION.** Keep `~/ktb482` as the build tree — it is correctly sited (22 chars),
correctly built, and independent of both sibling worktrees. **Before the first title-band edit, give
it history**, which costs seconds and is reversible:

```bash
cd ~/ktb482 && printf 'build/\nfonts/\nkitty.app/\n*.so\n*_generated.go\n' >> .gitignore
git init -q && git add -A && git commit -qm 'baseline: v0.48.2'          # then, separately:
# (re-apply the drag patch on top if you want it as its own commit)
```

Then the title-band deliverable is `git diff` and nothing else. **And re-verify the drag patch
against the sibling before you rely on it** — `~/kdev` shows that patch is still being revised, so
`~/ktb482` is a snapshot of a moving target (`kitty/state.h`, `state.c`, `glfw.c` in `~/ktb482` are
currently byte-identical to `~/k482`'s, verified).

### UPHELD — and four of them now have the control the original lacked

* **Claim 1 — and its open question is now closed.** Toolchain re-verified. The write-up seeded the
  NERD font but never established the seed was *necessary*: `add_builtin_fonts`
  (`~/kitty-482/setup.py:914-961`, called unconditionally at `:1221`) raises `SystemExit` unless the
  font is in `fonts/` **or** one of four macOS dirs. Measured: `SymbolsNerdFontMono-Regular.ttf` is
  absent from all four (`~/Library/Fonts`, `/Library/Fonts`, `/System/Library/Fonts`,
  `/Network/Library/Fonts`), direct **and** recursive. So the seed step is **mandatory**, not
  belt-and-braces — and the seeded copy is byte-identical to the cask's (`sha1 a4225aba18f4…`).
* **Claim 2 — confirmed, mechanism included.** `python3` → 3.11.4; `/usr/bin/python3` → 3.9.6;
  Homebrew-first → 3.14.7. The gate is `check_version_info()` at `~/kitty-482/setup.py:31-48`,
  parsing `requires-python = ">=3.12"` from `pyproject.toml:2`. The record's "3.9.6" rotted because
  a python.org framework install now shadows the system one — **the remedy is unchanged**; only the
  error string a reader will see differs (`docs/research/kitty-build-recipe-2026-09-16.md:147`).
* **Claim 3 — confirmed, and the residual §11 flagged is now CLOSED.** I re-measured in a more
  directly usable unit (root length, not install-name length) and the boundary is exact:
  `pyexpat` root **106 = OK, 107 = FAIL** (100 OK, 108/120 FAIL) — agreeing with the write-up's
  arithmetic to the character. The unmeasured half — *"every other file tolerates ≥260"* — now has
  evidence: the true relocation population is larger than `@rpath` alone (`bypy/devenv.go:107-117`
  also matches `macos_prefix = "/Users/Shared/kitty-build/sw/sw"`, `:25`), and **7 further
  relocatable binaries** — all 4 `@rpath` files plus the multi-dep `libssl`, `_ssl`, `libcrypto`,
  `libharfbuzz`, `libxml2` — **all pass at root = 200**. `pyexpat` is genuinely the single binding
  file. 80 is the ceiling, not an upper bound on it.
* **Claim 5 — confirmed with three arms, one of which the write-up only asserted from source.**
  `make app` with `docs/_build` moved aside → **rc 2**, *"The kitty man pages are missing"*. With
  `docs/_build/man` present but no `html` → **rc 2**, *"The kitty html docs are missing"* — the
  second `SystemExit` fires independently, as `setup.py:1483-1487` predicts. Both empty dirs → rc 0,
  `kitty.app successfully built!`. Both directories are required.
* **Claim 6 — confirmed, plus the in-place positive control the write-up did not run.** Minimal
  bundle moved → `can't find '__main__' module`. Packaged bundle moved → runs. **Minimal bundle run
  in place → runs.** That third arm is what proves the failure is *relocation* and not a broken
  binary.
* **Claims 8, 9 — confirmed byte-for-byte.** `~/ktb482` differs from pristine `~/kitty-482` in
  exactly the patch's six files and nothing else (the only other deltas are `*_generated.go` build
  products); `state.h`, `state.c`, `glfw.c` are byte-identical to `~/k482`'s.
* **Claim 10 — confirmed both arms, and extended.** Patched: `mouse_drag_window True` + C symbol
  PRESENT. Stock cask: `False` + ABSENT. **New:** the packaged app contains **zero** references to
  its build tree (`grep -rl ktb482 <app>` → 0), so it survives `~/ktb482` being deleted. `otool -L`
  shows its only non-system links are `/opt/homebrew/opt/python@3.14/…/Python` and
  `/opt/homebrew/opt/xxhash/…` — **the real coupling, and it is a live risk: a `brew upgrade` that
  major-bumps `python@3.14` breaks the installed patched app silently.**
* **Claim 12 — confirmed verbatim.** Cask artifacts are `kitty.app` + the two command wrappers;
  `/Applications/kitty.app` is the real directory and `/opt/homebrew/Caskroom/kitty/0.48.2/kitty.app`
  is a symlink to it; `/opt/homebrew/bin/kitty` points into the Caskroom wrappers.
* **Bonus, never stated and load-bearing for the recommendation.** The design's target exists in the
  version being built: `render_a_bar` is at **`~/ktb482/kitty/shaders.c:837`** (and `~/kitty-482`,
  4 occurrences), with call sites at `:929` and `:943`; `WindowBarData` at `~/kitty-482/kitty/state.h:220`
  and `title_bar_data, url_target_bar_data` at `:276`; `mouse_region` ×7 in `kitty/mouse.c`. Identical
  counts in `~/kitty-dev` (master). **So v0.48.2 is the right tree for the design, and the timings
  above are timings of the real edit set.**

### What I could not re-measure

* **Peak build memory** — still UNMEASURED, and the write-up is right to refuse a number. I did not
  attempt it either; my builds ran at load 22-24 with no swap growth.
* **Route A + `make app`** — not run (Route A is not the recommended route and `./dev.sh deps`
  downloads ~50 MB).
* **Real Sphinx docs** — not run; the empty-directory workaround is measured and sufficient.
* **GUI launch of any patched build** — deliberately not attempted, so nothing here proves the
  patched build *renders*. That gap is unchanged.

### Scratch I left behind (disposable, reaped on reboot)

`/private/tmp/ktb-verify/` — two throwaway v0.48.2 trees built at 97- and 121-char paths (the
claim-4 positive test), relocation copies, and the extracted dependency binaries used for the
ceiling sweep. I mutated **no** tracked tree: `~/kitty-482`, `~/kitty-dev`, `~/kdev`, `~/k482`,
`/Applications/kitty.app`, `~/.config/kitty/` and the shared checkout are untouched. In `~/ktb482`
(the write-up's own tree) I ran incremental `make`/`make app` and briefly moved `docs/_build` aside
for the claim-5 negative arm; both empty directories were restored and the tree is left built and
packaged, exactly as I found it.
