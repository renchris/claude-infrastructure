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

One idea: bats-core runs its own libexec `#!` files as `"$BASH" <full path>`. Every hunk carries a
`# cc-kalloc:` comment (`grep -rn 'cc-kalloc:' vendor/bats-core`). Line numbers are v1.13.0's:

| File:line (upstream) | Was | Now |
|---|---|---|
| `bin/bats:75` | `exec env … "$BATS_ROOT/libexec/bats-core/bats"` | `… "$BASH" "$BATS_ROOT/libexec/bats-core/bats"` |
| `libexec/bats-core/bats:396,398` | `interpolated_formatter="bats-format-<name>"` (by name via PATH) | array `("$BASH" "$BATS_LIBEXEC/bats-format-<name>")`; an absolute-path user formatter stays `("<path>")` and runs as-is |
| `libexec/bats-core/bats:427,429` | same, report formatter | same treatment |
| `libexec/bats-core/bats:517,522` | `exec bats-exec-suite` (by name via PATH) | `exec "$BASH" "$BATS_LIBEXEC/bats-exec-suite"` |
| `libexec/bats-core/bats-exec-file:236` | `"$BATS_LIBEXEC/bats-exec-test"` | `"$BASH" "$BATS_LIBEXEC/bats-exec-test"` |
| `libexec/bats-core/bats-exec-suite:141` | `bats-gather-tests` (by name) | `"$BASH" "$BATS_LIBEXEC/bats-gather-tests"` |
| `libexec/bats-core/bats-exec-suite:314` | GNU parallel command word `bats-exec-file` | `$(printf "%q %q" "$BASH" "$BATS_LIBEXEC/bats-exec-file")` |
| `libexec/bats-core/bats-exec-suite:323` | `bats-exec-file` (by name) | `"$BASH" "$BATS_LIBEXEC/bats-exec-file"` |
| `lib/bats-core/preprocessing.bash:12` | `"$BATS_ROOT/libexec/bats-core/bats-preprocess"` | `"$BASH" "$BATS_ROOT/…/bats-preprocess"` |

Proof the patch is complete: a copy of this tree with `chmod a-x libexec/bats-core/*`, started as
`bash bin/bats`, passes with every formatter, a report formatter and a failing test; the unpatched
1.13.0 copy treated the same way fails at once with `Permission denied` (rc 126). The GNU parallel
site (`-j N`) is untested here because `parallel` is not installed.

## How to re-vendor

1. Download the new tag's tarball into its own empty dir under `/tmp`; extract it there; run
   nothing from inside it.
2. `diff -r` its `bin libexec lib` against the Homebrew Cellar copy of the same version.
3. `cp -Rp` `bin libexec lib LICENSE.md README.md` over this directory and commit that
   alone as `chore(vendor): bats-core <ver> verbatim`.
4. Re-apply each local patch (grep `cc-kalloc:` in the previous version), commit them separately,
   and update this file.
