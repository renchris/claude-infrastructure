#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2329  # file-wide, all intentional: HOME/STUB_LOG are exported
#   INTO subshells on purpose (the log PATH vars log_o5/log_next are set + read in the PARENT, so
#   nothing is lost); the _cc_* stubs are invoked indirectly by the eval'd launcher body, not statically.
# check05_launcher.sh — #5 Launcher resolution (an EFFECT-READ, never a grep).
# ─────────────────────────────────────────────────────────────────────────────
# The way we launch is the consolidated `claude()` shell function in ~/.zshrc. A grep of that
# function proves nothing — a launcher can define a flag and still not pass it (wrong branch, a
# guard that aborts first, an override). So this probe RUNS the real launcher body against a STUB
# binary planted under a fake $HOME and reads what the launcher ACTUALLY handed the child:
# the argv + the exported env. PASS iff `claude` passes, exactly:
#   --model claude-opus-5   ·   --effort high   ·   --permission-mode auto   ·   SPAWN_DEPTH=1
#
# RETARGETED 2026-08-01 (was `claude-opus5`, and expected `--permission-mode default`). The
# 2026-07-31 consolidation collapsed claude-next + claude-opus5 into ONE `claude()` body; both old
# names became one-line shims `{ claude "$@"; }`. Extracting a SHIM and effect-reading it finds zero
# pins — so this check read FAIL on a correctly-configured system, and read FAIL identically on BOTH
# 2.1.219 and 2.1.220 (control run 2026-08-01, which is what proved the check and not the binary was
# at fault). The perm-mode expectation had flipped default→auto in that same consolidation.
#
# Two staleness traps closed at the same time, because either would silently re-break this check:
#   (1) The stub-binary PATH is no longer hardcoded to ~/.claude-219 — it is derived from the
#       launcher's OWN `_bin=` line, so a version bump (…-219 → …-220) cannot strand the probe on a
#       path the launcher stopped using. A hardcoded path fails OPEN: the launcher execs a real
#       binary that isn't in the fake HOME, logs nothing, and empty argv reads as "passed no flags".
#   (2) `claude()` execs `$HOME/.claude/bin/cc-close-attrib "$_bin" …`. Under the fake $HOME that
#       wrapper does not exist, so the chain dies before the stub is reached and NOTHING is recorded
#       — again indistinguishable from a launcher that passed no flags. We plant a passthrough
#       cc-close-attrib in the fake HOME so the exec chain completes.
#
# The `_cc_route_check` stub returns 0 with EMPTY stdout on purpose: that leaves `_wt=""` so the
# launcher's DIRECT (non-worktree) branch runs. Returning non-zero would trip the launcher's own
# "worktree isolation failed" guard and abort BEFORE the binary is ever invoked (nothing recorded).
#
# Secondary (non-fatal) spot-check, INVERTED 2026-08-01: the retired names `claude-next` /
# `claude-opus5` must NOT be defined. They were back-compat shims onto this same body, kept while
# ~40 repo files still invoked them by name; the launcher consolidation deleted both the callers and
# the shims (LAUNCHER_SPEC.md — `claude` is the only entrypoint). The probe therefore asserts
# ABSENCE, which is what stops the consolidation regressing silently: a re-added shim resurrects the
# duplicate-name state this change exists to end, and nothing else in the repo would notice.
# shellcheck shell=bash

# Derive the pinned binary path the launcher actually uses, from its own body.
# Echoes a $HOME-relative path (e.g. .claude-219/node_modules/.bin/claude); empty if not found.
_gate05_bin_relpath() {
  # shellcheck disable=SC2016  # $HOME must stay LITERAL here: we are matching the four characters
  #   '$HOME' as they appear verbatim in ~/.zshrc, not this shell's home directory. Expanding it
  #   would make the pattern '/Users/<me>/.claude-NNN' and match nothing in the launcher source.
  printf '%s\n' "$1" \
    | grep -oE '\$HOME/\.claude-[0-9]+/[A-Za-z0-9_./-]*claude' \
    | head -1 | sed 's|^\$HOME/||'
}

# Plant a passthrough cc-close-attrib so claude()'s exec chain reaches the stub binary.
_gate05_stub_closeattrib() {
  local path="$1/.claude/bin/cc-close-attrib"
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\nexec "$@"\n' >"$path"
  chmod +x "$path"
}

# Effect-read one launcher name out of $zshrc. Sets globals _g5_argv / _g5_depth.
# $1=function name  $2=zshrc path  $3=fake HOME
_gate05_effect_read() {
  local fn="$1" zshrc="$2" fakehome="$3" body="" log="" rel=""
  _g5_argv=""; _g5_depth=""
  body="$(extract_function "$fn" "$zshrc")" || return 1
  [ -n "$body" ] || return 1
  rel="$(_gate05_bin_relpath "$body")"
  # A body carrying no _bin= line (a forwarding wrapper such as claude-x / claude-desk) falls back
  # to the resolved `claude` path, so it still reaches the stub instead of reading as "no flags".
  [ -n "$rel" ] || rel="$_g5_main_rel"
  [ -n "$rel" ] || return 1
  log="$(mktemp)"
  build_stub_binary "$fakehome/$rel"
  (
    export HOME="$fakehome" STUB_LOG="$log"
    unset CLAUDE_CONFIG_DIR CLAUDE_PERM_MODE CLAUDE_EFFORT \
          CLAUDE_OPUS5_PERM CLAUDE_OPUS5_EFFORT CLAUDE_NEXT_MODEL CLAUDE_DEFAULT_EFFORT
    # shellcheck disable=SC2317  # invoked indirectly by the eval'd launcher body, not statically
    _cc_route_check()  { return 0; }   # empty stdout + rc 0 → _wt="" → direct (non-worktree) branch
    # shellcheck disable=SC2317
    _cc_sync_account() { :; }
    # shellcheck disable=SC2317
    _cc_tlid()         { echo t; }
    eval "$body"
    "$fn" -p ok >/dev/null 2>&1
  )
  _g5_argv="$(grep '^ARGV:' "$log" 2>/dev/null | tail -1)"
  _g5_depth="$(grep -m1 '^SPAWN_DEPTH=' "$log" 2>/dev/null)"
  rm -f "$log"
  return 0
}

check_05() {
  local zshrc="$HOME/.zshrc"
  local body_main="" fakehome="" argv_main="" depth_main="" miss="" shim_note=""

  if [ ! -f "$zshrc" ]; then
    emit_result 05 launcher-resolution SKIP "no ~/.zshrc to extract the launcher from" ""
    return 0
  fi
  body_main="$(extract_function claude "$zshrc")"
  if [ -z "$body_main" ]; then
    emit_result 05 launcher-resolution SKIP "claude() not found in ~/.zshrc" ""
    return 0
  fi

  _g5_main_rel="$(_gate05_bin_relpath "$body_main")"
  if [ -z "$_g5_main_rel" ]; then
    emit_result 05 launcher-resolution SKIP \
      "claude() carries no \$HOME/.claude-NNN binary pin to plant a stub against" ""
    return 0
  fi

  # --- primary: effect-read the consolidated `claude` launcher under a FAKE HOME ----------------
  fakehome="$(mktemp -d)"
  _gate05_stub_closeattrib "$fakehome"
  _gate05_effect_read claude "$zshrc" "$fakehome"
  argv_main="$_g5_argv"; depth_main="$_g5_depth"

  case "$argv_main" in *"--model claude-opus-5"*)  : ;; *) miss="$miss model" ;; esac
  case "$argv_main" in *"--effort high"*)          : ;; *) miss="$miss effort" ;; esac
  case "$argv_main" in *"--permission-mode auto"*) : ;; *) miss="$miss permission-mode" ;; esac
  [ "$depth_main" = "SPAWN_DEPTH=1" ]              ||    miss="$miss depth-guard"

  if [ -n "$miss" ]; then
    emit_result 05 launcher-resolution FAIL \
      "claude launcher did NOT pass:${miss} (effect-read of the child argv/env)" \
      "argv=[${argv_main#ARGV: }] ${depth_main} bin=${_g5_main_rel}"
    rm -rf "$fakehome"
    return 0
  fi

  # --- secondary (non-fatal): the retired names stay retired -----------------------------------
  # An ABSENCE cannot be effect-read — there is no body to run — so this half IS a source read, and
  # deliberately so: it looks for a DEFINITION (function or alias), which is the only way a name can
  # come back. Past-tense mentions in the file's own consolidation history are therefore unaffected.
  # `claude-default` is NOT in this list: it is retired by activation 28, a separate pending item,
  # and convicting it here would make this check WARN for a reason outside the consolidation.
  local back_names="" n_dead=0 dead
  for dead in claude-next claude-next2 claude-next3 claude-next4 \
              claude-opus5 claude-opus5-2 claude-opus5-3 claude-opus5-4 \
              cc-next cc-next2 cc-next3 cc-next4 \
              claude-fable claude-fable2 claude-fable3 claude-fable4 \
              claude-fable-x claude-fable-h claude-fable-q \
              claude-previous claude-previous2 claude-previous3 claude-previous4 \
              cc-previous claude-stable; do
    n_dead=$((n_dead + 1))
    if grep -qE "^[[:space:]]*(${dead}\(\)|alias[[:space:]]+${dead}=)" "$zshrc"; then
      back_names="$back_names $dead"
    fi
  done
  # Positive control: with no launchers at all in the file, "every retired name is absent" is
  # vacuously true. `claude-prev` is the rename half's survivor, so requiring it makes the absence
  # claim mean something — and catches a half-applied consolidation (deletes done, renames not).
  local survivor_note="claude-prev present"
  if ! grep -qE '^[[:space:]]*claude-prev\(\)' "$zshrc"; then
    survivor_note="claude-prev MISSING (rename half not applied)"
    back_names="$back_names (no-claude-prev)"
  fi
  if [ -n "$back_names" ]; then
    shim_note="consolidation WARN (non-fatal): retired names still defined:${back_names}; ${survivor_note}"
  else
    shim_note="consolidation intact: all ${n_dead} retired launcher names absent; ${survivor_note}"
  fi

  emit_result 05 launcher-resolution PASS \
    "claude passes --model claude-opus-5 + --effort high + --permission-mode auto + SPAWN_DEPTH=1 (effect-read of child argv/env)" \
    "$shim_note"
  rm -rf "$fakehome"
  return 0
}
