# Rebuilding the kitty trees from scratch — the four things a fresh clone lacks

**Why this file exists.** On 2026-09-16 at 15:50 the box rebooted and reaped `/private/tmp`,
destroying both built kitty trees that phase 1 and phase 2 had relied on. The plan recorded the
trees' *paths* and the fact that they were *built*; it recorded nothing about **how**. Reconstructing
them cost four consecutive build failures, each with a different cause and each diagnosable only by
reading the actual error. That is exactly the failure this repo already has a name for — *an
invocation that lives only in a log is lost by construction; one that lives in a tracked file is
not* — so the recipe is written down rather than re-derived.

**Where the trees now live, and why not `/private/tmp`.** `~/kdev` (master) and `~/k482` (v0.48.2)
are **25 characters**, comfortably under the measured ~80-character build-path ceiling, and they
survive a reboot. The original `/private/tmp` siting satisfied the ceiling and silently sacrificed
durability, which nobody had weighed. `/private/tmp/kitty-dev` and `/private/tmp/kitty-482` are
symlinks to them so the plan's and the goals' literal paths still resolve.

## The recipe

```bash
# 0. Clone SHALLOW. A full clone of kitty stalls on history negotiation, not bandwidth: measured
#    ~3 MB/min (80+ min projected) against 37 MB in 20 s for --depth=1 over the same link.
#    depth 50 on master keeps enough history for upstream-convention checks.
git clone --depth=50 https://github.com/kovidgoyal/kitty.git ~/kdev
git clone --depth=1 --branch v0.48.2 https://github.com/kovidgoyal/kitty.git ~/k482

# 1. PATH. A bare `python3` on this box is macOS system Python 3.9.6 and kitty requires >= 3.12;
#    the homebrew one is 3.14.7. Without this the build dies in two seconds.
export PATH=/opt/homebrew/bin:$PATH

# 2. Build deps that were genuinely absent (harfbuzz, freetype, libpng, little-cms2, openssl
#    were already installed):
brew install xxhash librsync simde

# 3. The builtin font. setup.py's add_builtin_fonts() looks for SymbolsNerdFontMono-Regular.ttf
#    and copies it to $src_base/fonts/ — and src_base is the TREE ROOT, not the kitty/ package
#    dir. (The INSTALLED app's layout is Resources/kitty/fonts/, which misleads.) It early-returns
#    on `if os.path.exists(dest): continue`, so seeding the file directly satisfies the check with
#    ZERO network and NO change to the operator's font library — strictly smaller blast radius
#    than `brew install --cask font-symbols-only-nerd-font`. The installed kitty.app already
#    ships the exact file:
cp /Applications/kitty.app/Contents/Resources/kitty/fonts/SymbolsNerdFontMono-Regular.ttf ~/kdev/fonts/
cp /Applications/kitty.app/Contents/Resources/kitty/fonts/SymbolsNerdFontMono-Regular.ttf ~/k482/fonts/

# 4. slangc — MASTER ONLY; v0.48.2 does not need it and builds without it. Homebrew has no
#    shader-slang formula. kitty's own CI pins the version in bypy/sources.json and fetches the
#    release tarball (.github/workflows/ci.py:108-130); do the same, to a durable path:
V=$(python3 -c "import json;print([d['name'].split()[-1] for d in json.load(open('$HOME/kdev/bypy/sources.json')) if d['name'].startswith('slang ')][0])")
curl -fsSL "https://github.com/shader-slang/slang/releases/download/v${V}/slang-${V}-macos-aarch64.tar.gz" -o /tmp/slang.tar.gz
mkdir -p ~/slang && tar -xzf /tmp/slang.tar.gz -C ~/slang
export SLANGC="$HOME/slang/bin/slangc"          # setup.py honours this env var

# 5. Build.
( cd ~/k482 && make )        # needs 1,2,3
( cd ~/kdev && make )        # needs 1,2,3,4
```

## 🚨 DO NOT RUN `./autoformat` IN A KITTY CHECKOUT ON THIS MACHINE

**It panicked the kernel twice on 2026-09-16** — `panic-full-2026-09-16-155400` and
`panic-full-2026-09-16-162856` — and both panics ended a Claude Code session mid-wave, destroying
one in-flight patch and every scratchpad artifact of two research phases. The two "reboots" this
document elsewhere treats as bad luck were **self-inflicted, by this exact command.**

**Mechanism.** `./autoformat` walks every top-level directory except `dist`, `build`, `bypy` and
`3rdparty` — so it formats the vendored ~300 MB `dependencies/` tree. It runs ten parallel
`clang-format` workers, and on `dependencies/darwin-arm64/include/simde/*.h` (1-3 MB of macro
soup: `wasm/simd128.h`, `wasm/relaxed-simd.h`, `mips/msa.h`) each worker grew to **1-19 GB RSS**.
The VM compressor reached 100% of its segment limit and the kernel watchdog panicked 4-5 minutes
later. Its cache is written only on completion, so an interrupted run re-formats everything next
time — the failure is perfectly repeatable and gets no cheaper.

**Corroborated from two directions.** A sibling session matched the two invocations to the two
panic files; independently, a `ps` sample taken here at 16:25:40 while diagnosing a "slow agent"
caught `./autoformat` plus three clang-format workers on exactly those simde headers, **2 min 16 s
before** the 16:28:56 panic.

**What to do instead.** Format only the files you changed:

```bash
clang-format -i --style=file:.clang-format kitty/state.c        # one changed file at a time
ruff format kitty/window.py kitty/options/utils.py kitty_tests/window_drag.py
```

A `dependencies` entry in autoformat's skip tuple is the real fix and looks upstream-worthy.

⚠️ **The generalisable half:** a formatter, linter or test runner that walks "the whole tree" is
sized by the VENDORED tree, not by yours — and a repo that vendors its C dependencies in-tree can
turn a routine pre-commit step into a machine-killer. Before running a whole-tree tool in an
unfamiliar checkout, read its exclusion list against `du -sh */`. Here the two numbers are 0.4 MB
of changed source against 300 MB of vendored headers.

## Running kitty's GATES, not just its build

The build is not the whole story — `./autoformat`, `ruff check .` and `./test.py type-check` are
kitty's own acceptance gates and none of their tooling was on this box either. All three are
isolated installs that touch no system Python:

```bash
uv tool install ruff          # 0.16.8
uv tool install ty            # 0.0.81 — the type checker is ty (Astral), NOT mypy
export PATH="$HOME/.local/bin:$PATH"
```

🚨 **And `./test.py type-check` will report 10 errors that are NOT yours.** They are
`unresolved-import` for `sphinx`, `docutils` and `pygments` — documentation-build dependencies ty
resolves out of `/opt/homebrew/lib/python3.14/site-packages`. Install them and the gate reads
`All checks passed!` at rc 0:

```bash
pip3 install --break-system-packages sphinx docutils pygments
```

**Two failed controls are recorded here because each looked authoritative and neither was.** Asked
whether that red was pre-existing or caused by a patch, the obvious move is to A/B against a
pristine tree — and a detached `git worktree` of the same commit is the wrong instrument twice over:

1. `./test.py` there exits **127, `bad interpreter: ./kitty/launcher/kitty`** — an unbuilt tree has
   no launcher, so the harness cannot run at all. A diff of "10 errors vs 0 errors" then reads as
   *the patch caused them*, which is an artifact of a dead instrument.
2. Running `ty check .` directly in both trees does execute, and inverts the answer: the pristine
   worktree reports **341** errors against the patched tree's **10**, because an unbuilt tree lacks
   build-GENERATED sources (`kitty/cli_stub.py` and friends). The two trees differ in build state,
   not only in the patch, so the comparison cannot isolate anything.

⇒ **A control must differ from its subject in exactly one thing, and "same commit" does not mean
"same tree" once a build generates sources.** What actually settled it was cheaper than either
control: *none of the 10 diagnostics named any changed file*, and installing the three missing
dependencies drove the count to zero. When an A/B is expensive or confounded, ask first whether the
finding even points at your diff.

## Verifying which build you are running

🚨 **`--version` cannot tell you** — master also reports `0.48.2`. Use:

```bash
~/k482/kitty/launcher/kitty +runpy 'import kitty; print(kitty.__file__)'
```

Measured 2026-09-16 after the rebuild: resolves under `/Users/chrisren/k482/`, and the clones came
back at the *same commits the reaped trees were on* — master `1d67ecd`, v0.48.2 `2cb1d95` — so the
rebuild is a faithful reconstruction and not a moving target.

## The failure modes, in the order they actually appear

| Symptom | Real cause |
|---|---|
| `kitty requires Python >=3.12. Current Python version: 3.9.6` — fails in ~2 s | `/opt/homebrew/bin` not first on `PATH` |
| `Package 'libxxhash' not found` | `brew install xxhash librsync simde` |
| `The font 'Symbols NERD Font Mono' was not found on your system` | seed `<TREE ROOT>/fonts/`, **not** `<tree>/kitty/fonts/` |
| `The shader slang compiler (slangc) not in PATH` — *after* a clean 89/89 compile and 4/4 link | master only; set `SLANGC` |

The last row is worth its own line: **the shader step runs after everything compiles and links**, so
a build that fails there looks like a build that nearly worked, and the C side genuinely did.
