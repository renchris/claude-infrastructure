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
