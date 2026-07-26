#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# shellcheck disable=SC2016  # file-wide: the jq program body is intentionally single-quoted ($c = jq var)
# activation-watch.sh — SessionStart: the absence-is-loud re-page for the C10 activation QUEUE (D-v).
#
# Why: the C10 ceiling means agents stage one-action activation scripts into
# ~/.claude/autonomy/pending-activation/ and the OPERATOR runs them — but a staged-but-un-run
# activation is silently-incomplete wiring (P8 sat ~90 min on stated-but-unexecuted verbal intent;
# a17 §3 "make the activation QUEUE absence-is-loud — re-page an un-run activation"). This hook
# surfaces, once per session, every pending-activation script older than N hours with NO matching
# `.done` marker — so an un-run wiring step can't rot unseen. Advisory only (additionalContext);
# never blocks; fail-open. It reads NO session state and mutates nothing.
#
# Convention: an activation `foo-activate.sh` is marked run by an adjacent `foo-activate.sh.done`
# marker (the operator `touch`es it after running). Selftest: `--selftest`.
#
# ── Axis 2: SSOT PARITY (live queue vs repo mirror) ──────────────────────────────────────────
# Axis 1 only ever asks "was it RUN?" — never "does it still EXIST in the SSOT?". The live
# `~/.claude/autonomy/pending-activation/*.sh` are REAL FILES, not symlinks into the checkout, so
# the two copies drift silently in BOTH directions and nothing compared them:
#   • LIVE-ONLY  — staged live, never committed: one `rm -rf` from unrecoverable. Same class as
#                  the plist-SSOT rule (5 calendar LaunchAgents destroyed 2026-07-25 by a stray
#                  in-place rewrite). Caught only by human observation until now — hand-cleared
#                  once as backlog fdf4161aeb28, which is why this recurrence guard exists.
#   • REPO-ONLY  — committed but never copied live, so it never enters the operator's queue and
#                  axis 1 CANNOT page for it: a staged activation invisible by construction.
#   • CONTENT    — same name, diverged bytes: a landed fix that never reached the copy the
#                  operator actually runs (the deploy-lag class; a land alone does not deploy).
# Reported in the same advisory emit. Still never blocks, still mutates nothing.
#
# A file declared intentionally live-only by an adjacent `<name>.local` marker is exempt from the
# LIVE-ONLY class (mirrors the `.done` convention) — so a legitimately un-committable script does
# not train alarm-fatigue on this channel.
#
# The mirror is resolved by DEREFERENCING this script (it is symlinked into ~/.claude/hooks/) and
# is accepted ONLY when the result is a real checkout — `~/.claude` must never masquerade as one.
# That is not hypothetical: a sibling parity assert resolved REPO=~/.claude via an underefed
# BASH_SOURCE and every leg exited 0 vacuously (backlog 816015ecb30b). An unresolvable mirror is
# therefore REPORTED, never silently skipped — a parity check that cannot run must say so.
set -uo pipefail

DIR="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
MAX_AGE_H="${CC_ACTIVATION_MAX_AGE_H:-24}"
MAX_AGE_S=$(( MAX_AGE_H * 3600 ))
JQ="$(command -v jq || true)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

MIRROR_REL="docs/activation/pending-activation"   # the repo-side SSOT, relative to a checkout root
FALLBACK_REPO="${CC_ACTIVATION_REPO:-$HOME/Development/claude-infrastructure}"

deref() { # <path> → the real file behind any symlink chain (readlink -f, BSD-safe fallback)
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}

resolve_mirror() { # → the repo-side pending-activation dir, or rc 1. NEVER a vacuous ~/.claude "pass".
  local root
  if [ -n "${CC_ACTIVATION_MIRROR_DIR:-}" ]; then
    [ -d "$CC_ACTIVATION_MIRROR_DIR" ] || return 1
    printf '%s\n' "$CC_ACTIVATION_MIRROR_DIR"; return 0
  fi
  # deref FIRST: invoked live we are ~/.claude/hooks/activation-watch.sh, a symlink into the checkout.
  root="$(cd "$(dirname "$(deref "${BASH_SOURCE[0]}")")/.." 2>/dev/null && pwd)" || root=""
  # `.git` gate = the anti-vacuous-pass guard: a checkout has one (dir, or FILE in a linked
  # worktree, hence -e not -d); ~/.claude does not, so it can never pose as the SSOT.
  if [ -n "$root" ] && [ -e "$root/.git" ] && [ -d "$root/$MIRROR_REL" ]; then
    printf '%s\n' "$root/$MIRROR_REL"; return 0
  fi
  [ -d "$FALLBACK_REPO/$MIRROR_REL" ] && { printf '%s\n' "$FALLBACK_REPO/$MIRROR_REL"; return 0; }
  return 1
}

join_names() { local s; s="$(printf '%s, ' "$@")"; printf '%s' "${s%, }"; }

emit() { # <context-string> — SessionStart additionalContext (JSON form, matching session-start.sh)
  if [ -n "$JQ" ]; then
    "$JQ" -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
  else
    printf '%s\n' "$1"   # SessionStart also injects plain stdout as context (frontier-status precedent)
  fi
}

age_axis() { # → the staleness finding (axis 1), empty when the queue is clean
  local now f mt stale=()
  now="$(date +%s)"
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    [ -f "$f.done" ] && continue                 # already run (operator touched the marker)
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    [ $(( now - mt )) -ge "$MAX_AGE_S" ] && stale+=("$(basename "$f")")
  done
  [ "${#stale[@]}" -eq 0 ] && return 0
  printf 'ACTIVATION QUEUE (absence-is-loud, D-v): %s pending-activation script(s) staged >%sh and NOT run — %s. These are C10 operator hand-steps (agent stages, operator runs): review + run %s/<name>, then `touch %s/<name>.done`. An un-run activation is silently-incomplete wiring.\n' \
    "${#stale[@]}" "$MAX_AGE_H" "$(join_names "${stale[@]}")" "$DIR" "$DIR"
}

parity_axis() { # → the live-vs-repo SSOT finding (axis 2), empty when the two copies agree
  local mirror f b lonly=() ronly=() cdrift=() n out
  if ! mirror="$(resolve_mirror)"; then
    # Loud-not-silent: an unrunnable check is a finding, not a pass (see the 816015ecb30b note).
    printf 'ACTIVATION SSOT PARITY: the repo mirror could not be resolved (no checkout at %s, and no %s/%s) — the live-vs-repo parity check DID NOT RUN. Point CC_ACTIVATION_MIRROR_DIR at the repo copy to restore it.\n' \
      "$MIRROR_REL" "$FALLBACK_REPO" "$MIRROR_REL"
    return 0
  fi
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$f.local" ] && continue                # declared intentionally live-only
    if [ ! -f "$mirror/$b" ]; then lonly+=("$b")
    elif ! cmp -s "$f" "$mirror/$b"; then cdrift+=("$b"); fi
  done
  for f in "$mirror"/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$DIR/$b" ] || ronly+=("$b")
  done

  n=$(( ${#lonly[@]} + ${#ronly[@]} + ${#cdrift[@]} ))
  [ "$n" -eq 0 ] && return 0
  out="$(printf 'ACTIVATION SSOT PARITY (D-v axis 2): %s drift(s) — live %s vs repo %s.' "$n" "$DIR" "$mirror")"
  if [ "${#lonly[@]}" -gt 0 ]; then
    out="$out"$'\n'"  LIVE-ONLY — never committed, one \`rm\` from unrecoverable: $(join_names "${lonly[@]}")"
    out="$out"$'\n'"    ▶ cp $DIR/<name> $mirror/<name>   # then commit it; or \`touch $DIR/<name>.local\` if intentionally live-only"
  fi
  if [ "${#ronly[@]}" -gt 0 ]; then
    out="$out"$'\n'"  REPO-ONLY — committed but never deployed, so it never enters the operator's queue: $(join_names "${ronly[@]}")"
    out="$out"$'\n'"    ▶ cp $mirror/<name> $DIR/<name>"
  fi
  if [ "${#cdrift[@]}" -gt 0 ]; then
    out="$out"$'\n'"  CONTENT-DRIFT — the copy the operator runs differs from the committed SSOT: $(join_names "${cdrift[@]}")"
    out="$out"$'\n'"    ▶ diff $mirror/<name> $DIR/<name>   # decide which side is authoritative, then sync"
  fi
  printf '%s\n' "$out"
}

watch() {
  [ -d "$DIR" ] || exit 0
  local msg age par
  age="$(age_axis)"
  par="$(parity_axis)"
  msg="$age"
  if [ -n "$par" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$par"; else msg="$par"; fi
  fi
  [ -z "$msg" ] && exit 0
  emit "$msg"
  exit 0
}

# ════ selftest — stale-unrun named · fresh-unrun skipped · done-marked skipped · absent-dir silent ══
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d out; d="$(mktemp -d "${TMPDIR:-/tmp}/activation-watch-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  local old; old="$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo 200001010000.00)"
  echo "activation-watch --selftest:"

  mkdir -p "$d/q"
  printf '#!/bin/bash\n' > "$d/q/stale-activate.sh";  touch -t "$old" "$d/q/stale-activate.sh"
  printf '#!/bin/bash\n' > "$d/q/fresh-activate.sh"                                   # mtime = now
  printf '#!/bin/bash\n' > "$d/q/done-activate.sh";   touch -t "$old" "$d/q/done-activate.sh"; : > "$d/q/done-activate.sh.done"

  # mirror := the queue itself ⇒ axis 2 is trivially in parity, so axis 1 is measured alone
  out="$(CC_ACTIVATION_DIR="$d/q" CC_ACTIVATION_MIRROR_DIR="$d/q" CC_ACTIVATION_MAX_AGE_H=24 "$SELF")"
  printf '%s' "$out" | grep -q 'stale-activate.sh' && okp "stale un-run script is named" || badp "stale un-run NOT named"
  printf '%s' "$out" | grep -q 'fresh-activate.sh' && badp "fresh script wrongly named" || okp "fresh (<24h) script NOT named"
  printf '%s' "$out" | grep -q 'done-activate.sh'  && badp ".done-marked script wrongly named" || okp ".done-marked script NOT named"
  printf '%s' "$out" | grep -q 'ACTIVATION QUEUE'  && okp "emits the absence-is-loud line" || badp "no activation-queue line"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null 2>&1 \
      && okp "output is valid SessionStart additionalContext JSON" || badp "output not valid SessionStart JSON"
  else okp "jq absent — plain-stdout fallback (skipped JSON check)"; fi

  # only fresh + done → NO output, exit 0
  mkdir -p "$d/clean"
  printf '#!/bin/bash\n' > "$d/clean/fresh.sh"
  out="$(CC_ACTIVATION_DIR="$d/clean" CC_ACTIVATION_MIRROR_DIR="$d/clean" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "no stale scripts → silent, exit 0" || badp "spurious output on a clean queue"

  # absent dir → silent, exit 0
  out="$(CC_ACTIVATION_DIR="$d/does-not-exist" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "absent queue dir → silent, exit 0 (fail-open)" || badp "absent dir not tolerated"

  # ══ axis 2: SSOT parity — live `p/live` vs repo mirror `p/repo`, every fixture FRESH so axis 1
  #    stays silent and each finding below is attributable to the parity axis alone ═══════════
  mkdir -p "$d/p/live" "$d/p/repo"
  printf '#!/bin/bash\n# same\n' > "$d/p/live/same-activate.sh"
  printf '#!/bin/bash\n# same\n' > "$d/p/repo/same-activate.sh"
  printf '#!/bin/bash\n# LIVE\n' > "$d/p/live/drifted-activate.sh"
  printf '#!/bin/bash\n# REPO\n' > "$d/p/repo/drifted-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/live/liveonly-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/repo/repoonly-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/live/intentional-activate.sh"; : > "$d/p/live/intentional-activate.sh.local"

  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/p/repo" "$SELF")"
  printf '%s' "$out" | grep -q 'liveonly-activate.sh'    && okp "LIVE-ONLY named (the unrecoverable class)"   || badp "LIVE-ONLY drift NOT named"
  printf '%s' "$out" | grep -q 'repoonly-activate.sh'    && okp "REPO-ONLY named (committed, never deployed)" || badp "REPO-ONLY drift NOT named"
  printf '%s' "$out" | grep -q 'drifted-activate.sh'     && okp "CONTENT-DRIFT named (live ≠ committed SSOT)" || badp "CONTENT-DRIFT NOT named"
  printf '%s' "$out" | grep -q 'intentional-activate.sh' && badp ".local live-only wrongly named"             || okp ".local marker exempts an intentional live-only"
  printf '%s' "$out" | grep -q 'same-activate.sh'        && badp "in-parity file wrongly named"               || okp "in-parity file NOT named (no false drift)"

  # positive control: the SAME code path must go quiet when the two copies agree
  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/p/live" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "identical live+repo → silent (positive control)" || badp "false drift on identical dirs"

  # an unrunnable check must be LOUD — the vacuous-pass failure mode this axis exists to prevent
  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/nope" "$SELF")"
  printf '%s' "$out" | grep -q 'DID NOT RUN' && okp "unresolvable mirror is REPORTED, not a vacuous pass" || badp "unresolvable mirror silently skipped"

  echo "activation-watch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "activation-watch --selftest: GREEN — axis 1 stale/fresh/done/absent + axis 2 live-only/repo-only/content-drift/.local-exempt/in-parity-quiet/unresolved-loud."
}

case "${1:-}" in
  --selftest) selftest ;;
  --parity)   # standalone/gate entry: rc 1 on ANY drift (incl. an unresolvable mirror), rc 0 only in parity
    if [ ! -d "$DIR" ]; then echo "activation SSOT parity: live queue $DIR absent — nothing to compare."; exit 0; fi
    PAR="$(parity_axis)"
    if [ -n "$PAR" ]; then printf '%s\n' "$PAR"; exit 1; fi
    echo "activation SSOT parity: GREEN — $DIR and the repo mirror agree."
    ;;
  *)          watch ;;
esac
