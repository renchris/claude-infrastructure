#!/usr/bin/env bash
# cc-run.sh — run a script through its own #! interpreter instead of letting the kernel read the #!.
#
# WHY (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4; REPORT §3 Phase 4): macOS 15.8.1 keeps
# ~1.1 KiB of kernel memory (data.kalloc.1024) for every #! file the kernel execs by path, until reboot,
# and ~20 GiB of it panics the Mac. Exec'ing the INTERPRETER with the script as its argument is the
# same program run the same way — the kernel builds exactly this argv from the #! line — but the
# image the kernel loads is a Mach-O, so nothing is kept.
#
#   cc_argv <path>          sets the global array CC_ARGV to the argv the kernel would build for <path>:
#                           ( <interp> [<interp-args>…] <path> ) for a #! file, or ( <path> ) unchanged
#                           for anything else (a Mach-O, a file with no #!, a bare name, a missing file).
#   cc_run <path> [args…]   runs it: cc_argv, then "${CC_ARGV[@]}" args. Returns its exit status.
#
# Use cc_argv when the call needs a prefix or must be the process itself — exec, timeout, nohup, `&`
# (so $! is the program, not a subshell):
#     cc_argv "$BACKLOG"; timeout 10 "${CC_ARGV[@]}" add --title x
#     cc_argv "$RUNNER";  exec "${CC_ARGV[@]}" "$@"
#
# The #! line is split exactly as the kernel splits it (xnu exec_extract_strings: space/tab separated,
# every word its own argument, runs collapsed), so $0, BASH_SOURCE, sys.argv[0], ps/pgrep -f, exit codes
# and `$!` are what a by-path exec gives. Anything the kernel would refuse or treat specially is passed
# through UNCHANGED so the kernel keeps deciding it: not +x, no interpreter word, an interpreter that is
# itself a #! file (IMGPF_INTERPRET), an unreadable file. Bare names are passed through too: resolving
# one would need a fork, and `bash NAME` would search the cwd first.
#
# Fork-free and bash 3.2 safe (launchd runs /bin/bash 3.2): two `read` builtins on the file, no command
# substitution, no here-string. Pure function definitions; sourcing it has no side effects.
# Python twin: scripts/lib/cc_run.py (same rules, for subprocess call sites).

cc_argv() { # <path> → CC_ARGV
  local _ccr_f="$1" _ccr_m="" _ccr_i=""
  local -a _ccr_w=()
  CC_ARGV=("$_ccr_f")
  case "$_ccr_f" in */*) ;; *) return 0 ;; esac
  [ -f "$_ccr_f" ] && [ -x "$_ccr_f" ] && [ -r "$_ccr_f" ] || return 0
  IFS= read -r -n 2 _ccr_m < "$_ccr_f" 2>/dev/null || :
  [ "$_ccr_m" = "#!" ] || return 0
  IFS=$' \t' read -r -a _ccr_w < "$_ccr_f" 2>/dev/null || :
  # "#!/bin/sh -x" reads as ("#!/bin/sh" "-x"); "#! /bin/sh" as ("#!" "/bin/sh").
  if [ "${_ccr_w[0]}" = "#!" ]; then _ccr_w=(${_ccr_w[@]+"${_ccr_w[@]:1}"}); else _ccr_w[0]="${_ccr_w[0]#\#!}"; fi
  [ ${#_ccr_w[@]} -gt 0 ] && [ -n "${_ccr_w[0]}" ] || return 0
  _ccr_i="${_ccr_w[0]}"
  [ -f "$_ccr_i" ] && [ -x "$_ccr_i" ] || return 0
  _ccr_m=""
  IFS= read -r -n 2 _ccr_m < "$_ccr_i" 2>/dev/null || :
  [ "$_ccr_m" = "#!" ] && return 0
  CC_ARGV=("${_ccr_w[@]}" "$_ccr_f")
  return 0
}

cc_run() { # <path> [args…]
  cc_argv "$1"
  shift
  "${CC_ARGV[@]}" "$@"
}
