# VENDORED — bats-core 1.13.0

| Field | Value |
|---|---|
| Upstream | <https://github.com/bats-core/bats-core> |
| Version | `v1.13.0` (tag object `d6a46f2cc2d3025ee3ffb59991c6d93ef903e339`, commit `3bca150ec86275d6d9d5a4fd7d48ab8b6c6f3d87`) |
| Tarball | <https://github.com/bats-core/bats-core/archive/refs/tags/v1.13.0.tar.gz> |
| Tarball sha256 | `a85e12b8828271a152b338ca8109aa23493b57950987c8e6dff97ba492772ff3` |
| License | MIT (`LICENSE.md`) |
| Vendored | 2026-10-22 |

Files kept: `bin/`, `libexec/bats-core/`, `lib/bats-core/`, `LICENSE.md`, `README.md`. Upstream's
`AUTHORS` is left out: it lists maintainers' personal e-mail addresses, which this public repo's
hygiene gate refuses, and the MIT copyright notice the license requires is in `LICENSE.md`.
`bin/libexec/lib` were checked with `diff -r` against Homebrew's
`/opt/homebrew/Cellar/bats-core/1.13.0/`: identical except that Homebrew's `bin/bats` lacks the
final newline.

## Why vendored

macOS 15.x retains about 1.1 KiB of kernel memory for every `#!` script the kernel execs by path,
until reboot. bats-core execs its own libexec `#!` scripts by path or by name for every file and
every test (`bats-exec-test` alone was 1268 execs in one census window). Running those files as
`"$BASH" <path>` removes the kernel `#!` exec. `bin/cc-bats` runs this copy
(`CC_BATS_VENDORED=0` falls back to the Homebrew bats).

## Local patches

None: the files are byte-identical to the tarball.

## How to re-vendor

1. Download the new tag's tarball into its own empty dir under `/tmp`; extract it there; run
   nothing from inside it.
2. `diff -r` its `bin libexec lib` against the Homebrew Cellar copy of the same version.
3. `cp -Rp` `bin libexec lib LICENSE.md README.md` over this directory and commit that
   alone as `chore(vendor): bats-core <ver> verbatim`.
4. Re-apply each local patch (grep `cc-kalloc:` in the previous version), commit them separately,
   and update this file.
