# shellcheck shell=bash
# cc-stub.bash — test stubs that the kernel never runs as a `#!` script.
#
# Why: macOS 15.x keeps ~1.1 KiB of kernel memory (data.kalloc.1024) for every `#!` script it execs by
# path, until reboot, and ~20 GiB panics the Mac. A PATH stub written as a `#!` file pays that on every
# call, and test harnesses were 81% of this Mac's `#!` execs (docs/research/kalloc-longterm-2026-10-21/
# REPORT.md §1). With $CC_SHIM set, cc_stub writes the body to DIR/../.<D>-real/NAME and makes DIR/NAME
# a symlink to cc-shim (tools/cc-shim), a Mach-O that reads the body's `#!` line and execs that
# interpreter with the body as its argument — measured +0.020 ± 0.017 elements per exec against ~1.1
# for the kernel route (measure.md § T-1). Without it (Linux CI, a box with no compiler, or
# CC_SHIM set-but-empty) it writes the plain `#!` file it always did. bin/cc-bats exports CC_SHIM.
#
# What a body sees under the shim: $0 / BASH_SOURCE is …/.<D>-real/NAME, not DIR/NAME (same depth, so
# `..`-relative paths hold), and CC_SHIM_HOPS is in its environment. A body that keys a log on "$0"
# must name its log path explicitly instead.
#
# Usage:  cc_stub DIR NAME BODY         BODY is the whole script, `#!` line first
#         cc_stub DIR NAME - <<'EOF'    BODY on stdin
#         cc_stub_body DIR NAME         prints the path that holds NAME's body (to read or edit it)
#         cc_stub_dir DIR / cc_stub_finish DIR   the batch form, below
# Never write or chmod DIR/NAME afterwards: under the shim it is a link to a shared binary (mode 0555,
# so a write fails rather than corrupting it). Call cc_stub again, or edit "$(cc_stub_body DIR NAME)".
# Fork-free apart from mkdir/chmod/ln, which are Mach-O.

_cc_stub_real_dir() { # $1=DIR → the shim's target dir for it: dirname(D)/.basename(D)-real
  local d="${1%/}" parent base
  case "$d" in */*) parent="${d%/*}" ;; *) parent=. ;; esac
  [ -n "$parent" ] || parent=/
  base="${d##*/}"
  printf '%s/.%s-real' "${parent%/}" "$base"
}

cc_stub_body() { # DIR NAME
  if [ -L "$1/$2" ] && [ -n "${CC_SHIM:-}" ] && [ "$1/$2" -ef "$CC_SHIM" ]; then
    printf '%s/%s\n' "$(_cc_stub_real_dir "$1")" "$2"
  else
    printf '%s/%s\n' "${1%/}" "$2"
  fi
}

_cc_stub_on() { [ -n "${CC_SHIM:-}" ] && [ -x "$CC_SHIM" ]; }

cc_stub() { # DIR NAME BODY|-
  local dir="$1" name="$2" body="${3:--}" first real LC_ALL=C  # ${#first} counts bytes, as the kernel does
  if [ "$body" = - ]; then IFS= read -r -d '' body || true; fi
  case "$body" in *$'\n') ;; *) body="$body"$'\n' ;; esac
  [ -d "$dir" ] || mkdir -p "$dir" || return 1
  # Unlink first: a redirect into an existing shim link would write through it.
  if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then rm -f "$dir/$name"; fi
  first="${body%%$'\n'*}"
  # Shim only what the kernel itself would run as `#!`: a `#!` line that ends within 512 bytes.
  if _cc_stub_on && [ "${first:0:2}" = '#!' ] && [ "${#first}" -lt 512 ]; then
    real="$(_cc_stub_real_dir "$dir")"
    [ -d "$real" ] || mkdir -p "$real" || return 1
    if [ -e "$real/$name" ] || [ -L "$real/$name" ]; then rm -f "$real/$name"; fi
    printf '%s' "$body" >"$real/$name" && chmod +x "$real/$name" && ln -s "$CC_SHIM" "$dir/$name"
  else
    printf '%s' "$body" >"$dir/$name" && chmod +x "$dir/$name"
  fi
}

# Batch form, for generators that write hundreds of stubs (one per name on PATH): write each body
# with plain redirects into "$(cc_stub_dir DIR)", then call cc_stub_finish DIR once. That costs one
# chmod and one perl however many stubs there are, where cc_stub costs a chmod and an ln each.
# Every body written there must start with a `#!` line shorter than 512 bytes.
cc_stub_dir() { # DIR → prints the directory bodies go in (created): .<D>-real under the shim, else DIR
  local d="$1"
  _cc_stub_on && d="$(_cc_stub_real_dir "$1")"
  [ -d "$d" ] || mkdir -p "$d" || return 1
  printf '%s\n' "$d"
}

cc_stub_finish() { # DIR — make every body in cc_stub_dir DIR executable and, under the shim, link it
  local real
  real="$(cc_stub_dir "$1")" || return 1
  [ -d "$1" ] || mkdir -p "$1" || return 1
  chmod +x "$real"/* || return 1
  _cc_stub_on || return 0
  /usr/bin/perl -e 'my ($shim, $real, $dir) = @ARGV; opendir(my $h, $real) or die "$real: $!\n";
    for my $n (grep { !/^\.\.?$/ } readdir $h) { unlink "$dir/$n"; symlink($shim, "$dir/$n") or die "$dir/$n: $!\n" }' \
    "$CC_SHIM" "$real" "$1"
}
