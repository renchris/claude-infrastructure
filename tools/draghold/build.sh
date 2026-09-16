#!/usr/bin/env bash
# Build draghold. Single translation unit, one framework, no flags to guess.
# The exact compile line, recorded so it is never re-derived:
#     clang -O2 -Wall -Wextra -o draghold draghold.c -framework ApplicationServices
# It compiles clean, zero warnings under -Wall -Wextra, to a Mach-O 64-bit arm64 executable.
# The binary is NOT committed (per-arch, and the source is the artifact); build it here.
set -euo pipefail
cd "$(dirname "$0")"
out="${1:-./draghold}"
clang -O2 -Wall -Wextra -o "$out" draghold.c -framework ApplicationServices
echo "built: $out"
file "$out"
echo
echo "Verify without moving the cursor:   $out --check"
echo "                                    $out --dry-run 400 300 900 300 3000 4"
