# shellcheck shell=bash
# shasum-direct.sh — SHA digests without a #! exec. /usr/bin/shasum is a perl script, and on macOS
# 15.8.1 every exec of a #! script retains ~1 KiB of kernel memory (data.kalloc.1024): the leak that
# panicked this machine on 2026-10-18 (docs/research/panic-2026-10-18-zone-map-shebang-leak.md).
# /sbin/sha256sum and /sbin/sha1sum are Mach-O and print byte-identical output (`<hex>  -` on stdin,
# `<hex>  <path>` per file); Linux falls back to coreutils on PATH. Sourced by the libs on the
# per-turn Stop path, which call "${CC_SHA256:-/sbin/sha256sum}" / "${CC_SHA1:-/sbin/sha1sum}". The file name is kept for its sourcers;
# the `shasum` function it once defined is gone (scripts/shasum-lint.sh refuses new shasum calls).
if [ -z "${_CC_SHA_DIRECT:-}" ]; then
  CC_SHA256=/sbin/sha256sum; [ -x "$CC_SHA256" ] || CC_SHA256=sha256sum
  CC_SHA1=/sbin/sha1sum; [ -x "$CC_SHA1" ] || CC_SHA1=sha1sum
  _CC_SHA_DIRECT=1
fi
