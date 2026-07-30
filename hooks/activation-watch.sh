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

age_axis() { # → the QUEUE finding (axis 1), empty only when the queue is genuinely empty
  # M3 (OPERATOR_SURFACE_V2 §4 F7) — PARTITION, never FILTER. The >MAX_AGE_H gate was built against
  # rot ("do not nag about something staged five minutes ago") and it hid the newest entries, which
  # are exactly the ones a just-finished rebuild staged and the ones the operator still has context
  # for. Measured 2026-07-29: 13 pending, 6 named — so the operator read "6 pending" and believed
  # that was the queue, while `18-fleet-activate.sh` (12 dark launchd labels), `16-session-beat` and
  # `17-qos-chokepoint` sat in the invisible half. Same law as the class budget: a surface may
  # de-emphasise a class, never delete it.
  # Kill switch: CC_ACTIVATION_AGE_FILTER=on restores the >MAX_AGE_H filter exactly.
  local now f mt stale=() fresh=() n
  now="$(date +%s)"
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    [ -f "$f.done" ] && continue                 # already run (operator touched the marker)
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    if [ $(( now - mt )) -ge "$MAX_AGE_S" ]; then stale+=("$(basename "$f")")
    else                                              fresh+=("$(basename "$f")"); fi
  done
  if [ "${CC_ACTIVATION_AGE_FILTER:-off}" = on ]; then
    [ "${#stale[@]}" -eq 0 ] && return 0
    printf 'ACTIVATION QUEUE (absence-is-loud, D-v): %s pending-activation script(s) staged >%sh and NOT run — %s. These are C10 operator hand-steps (agent stages, operator runs): review + run %s/<name>, then `touch %s/<name>.done`. An un-run activation is silently-incomplete wiring.\n' \
      "${#stale[@]}" "$MAX_AGE_H" "$(join_names "${stale[@]}")" "$DIR" "$DIR"
    return 0
  fi
  n=$(( ${#stale[@]} + ${#fresh[@]} ))
  [ "$n" -eq 0 ] && return 0
  local out
  out="$(printf 'ACTIVATION QUEUE (absence-is-loud, D-v): %s pending-activation script(s) NOT run. These are C10 operator hand-steps (agent stages, operator runs): review + run %s/<name>, then `touch %s/<name>.done`. An un-run activation is silently-incomplete wiring.' "$n" "$DIR" "$DIR")"
  # ROTTING first — age is the escalation signal, so it leads. But the count above is the QUEUE.
  if [ "${#stale[@]}" -gt 0 ]; then
    out="$out"$'\n'"  ROTTING (>${MAX_AGE_H}h, ${#stale[@]}): $(join_names "${stale[@]}")"
  fi
  if [ "${#fresh[@]}" -gt 0 ]; then
    out="$out"$'\n'"  FRESH (<${MAX_AGE_H}h, ${#fresh[@]}) — staged by a session whose context is probably still open, i.e. the cheapest moment to run them: $(join_names "${fresh[@]}")"
  fi
  printf '%s\n' "$out"
}

inert_axis() { # → axis 3: a `.done` marker whose EFFECT never landed (empty when every claim holds)
  # WHY THIS EXISTS (2026-07-29): axis 1 trusts the marker absolutely — `[ -f "$f.done" ] && continue`.
  # But every launchd activation script here gates its real work behind CONFIRM=1 and otherwise only
  # ECHOES the commands. Run one bare, read the printout, `touch` the marker, and the alarm is silenced
  # FOREVER while nothing was ever loaded. That is exactly what happened to the auto-drive spine:
  # 02-load-dispatcher and 03-load-discovery were marked .done on Jul 19/20 and neither job was ever
  # bootstrapped — 10 days of a backlog that could not drain, reported as fully activated.
  # A marker records that the SCRIPT RAN. Only launchctl records that the EFFECT LANDED. Read the effect.
  #
  # M5 (§4 F9) — TWO FIXES, both row 12's laws applied one layer out.
  # (a) SCOPE. The label pattern was `com\.claude\.` only, so an activation whose effect is a
  #     `com.chrisren.*` label was unverifiable BY CONSTRUCTION — and one such script is staged right
  #     now (`13-mailbox-gc-activate.sh`). A `com.claude`-only scope is exactly what hid row 4's live
  #     reaper from the fleet audit; the declared fleet is 20 labels across two families.
  # (b) STATE. `launchctl list` alone cannot tell DISABLED from NOT-INSTALLED, and those have
  #     OPPOSITE fixes (`enable` vs `bootstrap`), so the row used to send the operator to the wrong
  #     one half the time. The literal `=> disabled` read from the override DB separates them —
  #     `print-disabled` prints `"<label>" => disabled|enabled`, NEVER true/false, and grepping the
  #     plist vocabulary against the CLI returns a confident ZERO (the trap that cost the campaign
  #     coordinator a read on 2026-07-29).
  # NOT a reimplementation of launchd health: the six-state verdict (NEVER-RAN / FAILING / STALLED /
  # UNDECIDED …) is `bin/cc-fleet`'s, declared in launchd/fleet.manifest, and this axis consumes that
  # board rather than competing with it. Axis 3 asks strictly "did the EFFECT land at all?", where
  # `list`'s absent-means-not-loaded is the safe direction.
  # Kill switch: CC_ACTIVATION_INERT_SCOPE=claude restores the com.claude-only pattern.
  local f label inert=() listing disabled_db uid pat state lc
  # A SEAM (CC_ACTIVATION_LAUNCHCTL_BIN), and not decoration: without it this axis reads the
  # OPERATOR's real launchd from inside the suite and the verdict flips by machine — borrowed
  # hermeticity (memory hermetic-suite-leaks-caller-identity). READ-ONLY subcommands only.
  lc="${CC_ACTIVATION_LAUNCHCTL_BIN:-launchctl}"
  command -v "$lc" >/dev/null 2>&1 || return 0
  pat='com\.(claude|chrisren)\.[a-z0-9-]+'
  [ "${CC_ACTIVATION_INERT_SCOPE:-both}" = claude ] && pat='com\.claude\.[a-z0-9-]+'
  listing="$("$lc" list 2>/dev/null)" || return 0          # no sensor ⇒ no verdict (fail-open)
  uid="$(id -u 2>/dev/null || true)"
  case "${uid:-}" in ''|*[!0-9]*) disabled_db="" ;; *) disabled_db="$("$lc" print-disabled "gui/$uid" 2>/dev/null || true)" ;; esac
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    [ -f "$f.done" ] || continue                 # axis 1 already owns the un-run case
    # Only the launchd class is effect-readable here; a script naming no label is out of scope.
    label="$(grep -oE "$pat" "$f" 2>/dev/null | head -1)"
    [ -n "$label" ] || continue
    # $NF, not $3: matches the label as a whole final field, the idiom bin/cc-blockers already uses.
    printf '%s\n' "$listing" | awk -v l="$label" '$NF==l{found=1} END{exit !found}' && continue
    state="NOT-LOADED"
    printf '%s\n' "$disabled_db" | grep -q "\"$label\" => disabled" && state="DISABLED"
    inert+=("$(basename "$f") → $label [$state]")
  done
  [ "${#inert[@]}" -eq 0 ] && return 0
  printf 'ACTIVATION CLAIMED-DONE BUT INERT (axis 3, effect-read): %s activation(s) carry a `.done` marker while their launchd job is NOT loaded — %s. A `.done` marker proves the SCRIPT RAN, never that the EFFECT LANDED: these scripts print their commands and only cp+lint+bootstrap under CONFIRM=1, so a bare run + `touch` silences axis 1 permanently over a job that was never bootstrapped. Re-run with CONFIRM=1: `CONFIRM=1 bash %s/<name>` — then this axis clears itself, because it reads launchctl, not the marker.\n' \
    "${#inert[@]}" "$(join_names "${inert[@]}")" "$DIR"
}

# M4 (OPERATOR_SURFACE_V2 §4 F8) — LIVE-ONLY must be adjudicated against TRUNK, not the working
# tree. resolve_mirror() dereferences to the SHARED CHECKOUT, so parity is live-vs-checkout; while
# that checkout trails origin/main, a file that IS committed reads as "never committed, one `rm` from
# unrecoverable" and the platter says `cp live -> repo`, creating a local diff the next fast-forward
# must conflict on. Deploy lag wearing a parity costume, and in the one direction that does damage.
# Latent on 2026-07-29 (all four live drifts were real, verified live-vs-origin/main) — fixed before
# it fired rather than after.
# Returns: 0 = present on trunk (so NOT live-only), 1 = genuinely absent, 2 = cannot tell.
on_trunk() { # <repo-root> <basename>
  [ "${CC_ACTIVATION_TRUNK_ADJUDICATE:-on}" = off ] && return 1
  local root="$1" b="$2" ref
  [ -n "$root" ] && [ -e "$root/.git" ] || return 2
  ref="$(git -C "$root" rev-parse --verify --quiet origin/HEAD 2>/dev/null || true)"
  [ -n "$ref" ] || ref="$(git -C "$root" rev-parse --verify --quiet origin/main 2>/dev/null || true)"
  [ -n "$ref" ] || return 2                       # no trunk ref ⇒ NO verdict, never a guess
  git -C "$root" cat-file -e "$ref:$MIRROR_REL/$b" 2>/dev/null && return 0
  return 1
}

parity_axis() { # → the live-vs-repo SSOT finding (axis 2), empty when the two copies agree
  local mirror f b lonly=() ronly=() cdrift=() undep=() n out root lag tv
  if ! mirror="$(resolve_mirror)"; then
    # Loud-not-silent: an unrunnable check is a finding, not a pass (see the 816015ecb30b note).
    printf 'ACTIVATION SSOT PARITY: the repo mirror could not be resolved (no checkout at %s, and no %s/%s) — the live-vs-repo parity check DID NOT RUN. Point CC_ACTIVATION_MIRROR_DIR at the repo copy to restore it.\n' \
      "$MIRROR_REL" "$FALLBACK_REPO" "$MIRROR_REL"
    return 0
  fi
  root="${mirror%/"$MIRROR_REL"}"
  # The checkout's own trunk position, carried on every finding: a parity number computed against a
  # behind-checkout is not a parity number, and the operator must be able to see that before acting.
  lag="$(git -C "$root" rev-list --count 'HEAD..@{u}' 2>/dev/null || true)"
  case "${lag:-}" in ''|*[!0-9]*) lag="" ;; esac
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$f.local" ] && continue                # declared intentionally live-only
    if [ ! -f "$mirror/$b" ]; then
      on_trunk "$root" "$b"; tv=$?
      case "$tv" in
        0) undep+=("$b") ;;                      # committed on trunk, absent from THIS checkout
        1) lonly+=("$b") ;;                      # genuinely never committed
        *) lonly+=("$b (trunk unreadable — verdict UNCONFIRMED)") ;;
      esac
    elif ! cmp -s "$f" "$mirror/$b"; then cdrift+=("$b"); fi
  done
  for f in "$mirror"/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$DIR/$b" ] || ronly+=("$b")
  done

  n=$(( ${#lonly[@]} + ${#ronly[@]} + ${#cdrift[@]} + ${#undep[@]} ))
  [ "$n" -eq 0 ] && return 0
  out="$(printf 'ACTIVATION SSOT PARITY (D-v axis 2): %s drift(s) — live %s vs repo %s%s.' "$n" "$DIR" "$mirror" \
    "$( [ -n "$lag" ] && [ "$lag" != 0 ] && printf ' (this checkout is %s commit(s) BEHIND its trunk — every finding below is live-vs-checkout, so read it with that in mind)' "$lag" )")"
  if [ "${#undep[@]}" -gt 0 ]; then
    out="$out"$'\n'"  UNDEPLOYED-MIRROR — committed ON TRUNK but absent from this checkout, i.e. DEPLOY LAG, not a missing commit: $(join_names "${undep[@]}")"
    out="$out"$'\n'"    ▶ git -C $root fetch origin main && git -C $root merge --ff-only origin/main   # do NOT cp live->repo: it would recreate a committed file as a local diff the next ff must conflict on"
  fi
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
  local msg age par inert
  age="$(age_axis)"
  par="$(parity_axis)"
  inert="$(inert_axis)"
  msg="$age"
  if [ -n "$par" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$par"; else msg="$par"; fi
  fi
  # Axis 3 last but never least: a CLAIMED-DONE-BUT-INERT activation is the quietest of the three
  # (axis 1 is silenced by the very marker that is lying), so it must still reach the operator.
  if [ -n "$inert" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$inert"; else msg="$inert"; fi
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
  # CHANGED 2026-07-29 (row 10, §4 F7): axis 1 PARTITIONS instead of FILTERING, so a fresh un-run
  # script is now NAMED — under a FRESH heading, not a rotting one. The old assertion pinned the
  # >24h gate that hid the campaign's own freshest activations.
  printf '%s' "$out" | grep -q 'fresh-activate.sh' && okp "fresh (<24h) script IS named (partitioned)" || badp "fresh script NOT named"
  printf '%s' "$out" | grep -q 'ROTTING' && okp "rotting partition labelled" || badp "no ROTTING partition"
  printf '%s' "$out" | grep -q 'FRESH'   && okp "fresh partition labelled"   || badp "no FRESH partition"
  printf '%s' "$out" | grep -q '2 pending-activation script(s) NOT run' && okp "the count is the QUEUE (2), not a filtered subset (1)" || badp "count is not the queue"
  out2="$(CC_ACTIVATION_DIR="$d/q" CC_ACTIVATION_MIRROR_DIR="$d/q" CC_ACTIVATION_AGE_FILTER=on "$SELF")"
  printf '%s' "$out2" | grep -q 'fresh-activate.sh' && badp "kill switch did not restore the filter" || okp "CC_ACTIVATION_AGE_FILTER=on restores the >24h filter"
  printf '%s' "$out" | grep -q 'done-activate.sh'  && badp ".done-marked script wrongly named" || okp ".done-marked script NOT named"
  printf '%s' "$out" | grep -q 'ACTIVATION QUEUE'  && okp "emits the absence-is-loud line" || badp "no activation-queue line"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null 2>&1 \
      && okp "output is valid SessionStart additionalContext JSON" || badp "output not valid SessionStart JSON"
  else okp "jq absent — plain-stdout fallback (skipped JSON check)"; fi

  # a genuinely EMPTY queue → NO output, exit 0. `.done`-marked, not merely fresh: since axis 1
  # partitions, "nothing pending" is the only silent state, which is the honest definition of clean.
  mkdir -p "$d/clean"
  printf '#!/bin/bash\n' > "$d/clean/fresh.sh"; : > "$d/clean/fresh.sh.done"
  out="$(CC_ACTIVATION_DIR="$d/clean" CC_ACTIVATION_MIRROR_DIR="$d/clean" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "no stale scripts → silent, exit 0" || badp "spurious output on a clean queue"

  # absent dir → silent, exit 0
  out="$(CC_ACTIVATION_DIR="$d/does-not-exist" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "absent queue dir → silent, exit 0 (fail-open)" || badp "absent dir not tolerated"

  # ══ axis 2: SSOT parity — live `p/live` vs repo mirror `p/repo`, every fixture FRESH so axis 1
  #    stays silent and each finding below is attributable to the parity axis alone ═══════════
  # `.done`-marked (not merely fresh) since axis 1 partitions: freshness no longer buys silence, and
  # borrowing another axis's quiet is not isolation.
  mkdir -p "$d/p/live" "$d/p/repo"
  printf '#!/bin/bash\n# same\n' > "$d/p/live/same-activate.sh"
  printf '#!/bin/bash\n# same\n' > "$d/p/repo/same-activate.sh"
  printf '#!/bin/bash\n# LIVE\n' > "$d/p/live/drifted-activate.sh"
  printf '#!/bin/bash\n# REPO\n' > "$d/p/repo/drifted-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/live/liveonly-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/repo/repoonly-activate.sh"
  printf '#!/bin/bash\n'         > "$d/p/live/intentional-activate.sh"; : > "$d/p/live/intentional-activate.sh.local"
  for _f in "$d/p/live"/*.sh "$d/p/repo"/*.sh; do : > "$_f.done"; done      # axis-1 silence, by marker

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
