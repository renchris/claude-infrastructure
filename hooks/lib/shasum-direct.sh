# shellcheck shell=bash
# shasum-direct.sh — `shasum` without a #! exec. /usr/bin/shasum is a perl script, and on macOS
# 15.7.9 every exec of a #! script retains 1 KiB of kernel memory (data.kalloc.1024): the leak that
# panicked this machine on 2026-10-18 (docs/research/panic-2026-10-18-zone-map-shebang-leak.md).
# Perl run on the script directly is the same program without the leak (perl honours the #! line's
# switches itself). Sourced by the libs on the per-turn Stop path; a no-op where shasum is anything
# else, so the caller's own `shasum` resolution is unchanged there.
if [ -z "${_CC_SHASUM_DIRECT:-}" ] && [ -x /usr/bin/perl ] && [ -r /usr/bin/shasum ]; then
  _cc_sl=""
  IFS= read -r _cc_sl < /usr/bin/shasum || true
  case "$_cc_sl" in
    '#!/usr/bin/perl'*) shasum() { /usr/bin/perl /usr/bin/shasum "$@"; }; _CC_SHASUM_DIRECT=1 ;;
  esac
  unset _cc_sl
fi
