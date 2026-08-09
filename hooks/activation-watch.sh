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
# marker (the operator `touch`es it after running). Selftest: `--selftest`. Full list: `--queue`.
#
# ⚠ THIS QUEUE IS NO LONGER WHERE NEW WIRING GOES (face 3, inertness-generator-2026-08-07 §3). A
# registration / plist / settings change now lands as a MIGRATION in the same diff as its subject and
# is run by the converger (migrations/README.md, scripts/deploy-migrations.sh) — a `c10`-class
# migration files its operator step once into cc-backlog instead of joining this pile. What survives
# here is the pre-existing residue, and the two mechanical parity classes below are now the
# converger's to fix rather than the operator's.
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

# ── PAGE-ONCE (face 3, inertness-generator-2026-08-07 §3/§4.4) ────────────────────────────────────
# The itemized banner fired at EVERY SessionStart, naming all 38 items every time. An alarm that
# always fires carries exactly as many bits as one that cannot (MEMORY.md alarm-polarity), and this
# one had trained the operator to skip past a 38-line wall for weeks. Face 3's contract is that the
# hand-queue survives only for genuinely operator-owned steps, "each blocking its own item and paged
# ONCE". So the itemized page is now an EDGE — it renders when the un-run SET changes (or the window
# elapses) — and the steady state collapses to one counted line, which is what CLAUDE.md already does
# for the standing pile via the `◆` line. Absence stays loud (the count always asserts); only the
# repetition is deleted.
#
# Fingerprint = the sorted un-run set, never a timestamp or a count: a fingerprint that moves every
# sweep silently disables damping while looking wired, and a bare COUNT would hide a swap (one item
# run, one staged, same total). Window defaults to 24h, matching CC_DEPLOY_DAMP_S — this store moves
# on the scale of days, so page-damp's 30-minute default would still fire at nearly every session.
DAMP_WINDOW_S="${CC_ACTIVATION_DAMP_S:-86400}"
DAMP_FILE="${CC_ACTIVATION_DAMP_FILE:-$DIR/.queue-page.damp}"
case "$DAMP_WINDOW_S" in ''|*[!0-9]*) DAMP_WINDOW_S=86400 ;; esac

queue_damp_ok() { # <fingerprint> → 0 = render the full page (new set / window elapsed) · 1 = suppress
  local fp="$1" prev_fp="" prev_ts=0 now
  [ "$DAMP_WINDOW_S" -eq 0 ] && return 0                  # 0 ⇒ damping off (the documented spelling)
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$now" in ''|*[!0-9]*) return 0 ;; esac             # no clock ⇒ fail OPEN, never lose the page
  if [ -f "$DAMP_FILE" ]; then
    prev_ts="$(sed -n '1p' "$DAMP_FILE" 2>/dev/null | tr -dc '0-9')"
    prev_fp="$(sed -n '2p' "$DAMP_FILE" 2>/dev/null)"
    case "$prev_ts" in ''|*[!0-9]*) prev_ts=0 ;; esac
    # A CHANGED set re-pages immediately: change is signal, repetition is noise.
    if [ "$prev_fp" = "$fp" ] && [ "$(( now - prev_ts ))" -lt "$DAMP_WINDOW_S" ]; then return 1; fi
  fi
  printf '%s\n%s\n' "$now" "$fp" > "$DAMP_FILE" 2>/dev/null || true   # unwritable ⇒ page every time
  return 0
}

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
  [ "$n" -eq 0 ] && { rm -f "$DAMP_FILE" 2>/dev/null; return 0; }   # drained ⇒ re-arm, so a refill is loud
  # The un-run SET, order-independent. Sorted so a re-listing in a different order is not a "change",
  # and hashed so the marker stays one short line whatever the queue size.
  # `${arr[@]+"${arr[@]}"}`, not `"${arr[@]}"`: under `set -u` bash 3.2 treats an EMPTY array
  # expansion as an unbound variable and aborts the substitution. That does not fail loudly here —
  # it yields an EMPTY fingerprint, so every set hashes identically and the damp can never re-page on
  # a change, i.e. the mute button with no escape. Caught by the change/swap fixtures below, which is
  # why they exist rather than only the "unchanged is quiet" half.
  local fp
  fp="$(printf '%s\n' ${stale[@]+"${stale[@]}"} ${fresh[@]+"${fresh[@]}"} 2>/dev/null | sort | cksum | tr -d ' \n')"
  [ -n "$fp" ] || fp="unhashable-$n"   # a hash we could not take must not read as "same as last time"
  if ! queue_damp_ok "$fp"; then
    # STEADY STATE — one counted line, per class. Absence is still loud; the 38-line wall is not.
    printf 'ACTIVATION QUEUE: %s un-run (%s rotting >%sh) — unchanged since the last page, so the list is suppressed. Full list: `bash %s --queue`. New wiring should land as a `c10` migration (migrations/README.md), not here.\n' \
      "$n" "${#stale[@]}" "$MAX_AGE_H" "$SELF"
    return 0
  fi
  local out
  out="$(printf 'ACTIVATION QUEUE (absence-is-loud, D-v): %s pending-activation script(s) NOT run. These are C10 operator hand-steps (agent stages, operator runs): review + run %s/<name>, then `touch %s/<name>.done`. An un-run activation is silently-incomplete wiring. This full listing renders on a CHANGE of the un-run set (or every %sh); in between you get one counted line.' "$n" "$DIR" "$DIR" "$(( DAMP_WINDOW_S / 3600 ))")"
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

envarm_axis() { # → axis 4: a `.done` ENV-VAR arm whose value never reached the consumer (empty when delivered)
  # M6 (backlog 80321b2556e6) — WHY THIS EXISTS. Axis 1 trusts the `.done` marker and axis 3
  # effect-reads launchctl, so an activation whose entire effect is an EXPORTED VARIABLE escapes
  # BOTH by construction: it installs no launchd job to read, and the marker it sets is the very
  # thing that silences axis 1. `10-lead-crash-orphan-close-activate.sh` is exactly that shape — it
  # appends `export LCW_ORPHAN_CLOSE=1` to an env file and nothing else. Marked `.done` 2026-07-30
  # with nothing sourcing that file, so hooks/lead-crash-watchdog.sh read `${LCW_ORPHAN_CLOSE:-0}`
  # as 0 and went on leaving orphaned assignee panes RUNNING: an activation reported fully
  # activated while 100% inert, and no axis on this hook could say so.
  #
  # The gap is self-demonstrating. The backlog item that commissioned this axis asserted the arm was
  # inert — and by the time it was worked, `~/.zshrc` DID source the file and the var WAS being
  # delivered. Both the original finding and its refutation were invisible to every sensor; the only
  # way anyone learned either was a human reading the tree by hand. That is the durable defect, and
  # it is why this axis reports a live verdict instead of anyone re-asserting a remembered one
  # (memory: resident-policy-must-not-restate-perishable-facts).
  #
  # THE CONSUMER READ IS THIS PROCESS'S OWN ENVIRONMENT, and that is the mechanism, not a shortcut.
  # The consumer is spawned from a SessionStart hook; this axis IS a SessionStart hook. Same process
  # tree, same inherited environment ⇒ what we can see is precisely what the consumer can see. It is
  # not a proxy that can drift from its subject (memory: proxy-must-be-independent-of-what-it-
  # supplements — a proxy needs calibration; an identity does not), and it costs zero execs.
  #
  # It is therefore a PER-SESSION verdict, which is the only honest one: an env-only arm is
  # PROSPECTIVE-ONLY (no already-running session ever inherits it) and cannot reach a
  # launchd-invoked caller at all. A session whose provenance did not deliver the var IS unarmed,
  # and this says so for THAT session instead of averaging over a fleet.
  # Kill switch: CC_ACTIVATION_ENVARM=off.
  [ "${CC_ACTIVATION_ENVARM:-on}" = off ] && return 0
  local f envf var val line seen cands bad=()
  # ONE exec for the whole queue. The class is narrow — exactly 1 of the 46 staged scripts is in it
  # — so a per-script grep would spend 45 execs to learn there was nothing to do, the shape da5c862c
  # just removed from the checkpoint hook. This pre-filter is strictly WEAKER than the per-script
  # test below (it matches any `.env` mention; the test demands an ASSIGNMENT), so it can only
  # over-select and can never shadow the real discriminator, whose own mutant must stay inert
  # (memory: cost-gate-must-be-strictly-weaker).
  cands="$(grep -lE '\.env([^A-Za-z0-9_]|$)' "$DIR"/*.sh 2>/dev/null || true)"
  [ -n "$cands" ] || return 0
  while IFS= read -r f; do
    { [ -n "$f" ] && [ -f "$f" ]; } || continue
    [ -f "$f.done" ] || continue                 # axis 1 already owns the un-run case
    # The CLASS is "the script ASSIGNS an env-file path", never "the script says export". That
    # distinction is load-bearing and was measured against the real queue: four sibling scripts
    # carry a bare `export VAR=` in prose (a kill switch, a PATH line, two echo'd instructions) and
    # none of them arms anything through a sourced file. Keying on `export` convicts all four
    # (memory: denylist-enumerates-spellings-not-the-class).
    envf="$(sed -n 's/^[A-Za-z_][A-Za-z0-9_]*="\([^"]*\.env\)".*/\1/p' "$f" 2>/dev/null | head -1)"
    [ -n "$envf" ] || continue                   # pre-filter over-selected; that is its job
    # These are LITERAL prefixes read out of another script's source text, not paths this shell is
    # expanding, so every pattern is quoted on purpose. SC2088's advice is inverted here: bash DOES
    # tilde-expand an unquoted `case` pattern, so `~/*` would silently become this machine's home
    # directory and could never match the `~` the file actually contains.
    # shellcheck disable=SC2088
    case "$envf" in
      '$HOME'/*)   envf="$HOME${envf#\$HOME}" ;;
      '${HOME}'/*) envf="$HOME${envf#\$\{HOME\}}" ;;
      '~/'*)       envf="$HOME${envf#\~}" ;;
    esac
    # A path we cannot resolve is REPORTED, never skipped — a check that quietly declines to run is
    # the vacuous pass this whole file exists to prevent (cf. resolve_mirror's unresolvable arm).
    case "$envf" in *'$'*) bad+=("$(basename "$f") → $envf [UNRESOLVED-PATH]"); continue ;; esac
    [ -f "$envf" ] || { bad+=("$(basename "$f") → $envf [NOT-STAGED]"); continue; }
    seen=""
    while IFS= read -r line; do
      case "$line" in 'export '*) ;; *) continue ;; esac
      var="${line#export }"; var="${var%%=*}"; var="${var%"${var##*[![:space:]]}"}"
      case "$var" in ''|*[!A-Za-z0-9_]*) continue ;; esac
      val="${line#*=}"
      case "$val" in *[[:space:]]#*) val="${val%%[[:space:]]#*}" ;; esac   # inline trailing comment
      val="${val%"${val##*[![:space:]]}"}"
      case "$val" in \"*\") val="${val#\"}"; val="${val%\"}" ;; \'*\') val="${val#\'}"; val="${val%\'}" ;; esac
      seen=1
      # THREE states, not two, and the two failing ones have OPPOSITE fixes — the same law axis 3
      # had to learn for DISABLED vs NOT-INSTALLED, one layer out. Collapsing them sends the
      # operator to the wrong remedy half the time.
      if [ -z "${!var+set}" ]; then
        bad+=("$(basename "$f") → $var [NOT-DELIVERED]")
      elif [ "${!var}" != "$val" ]; then
        bad+=("$(basename "$f") → $var [OVERRIDDEN: file=$val live=${!var}]")
      fi
    done < "$envf"
    [ -n "$seen" ] || bad+=("$(basename "$f") → $envf [NOT-STAGED: file has no export line]")
  done <<EOF
$cands
EOF
  [ "${#bad[@]}" -eq 0 ] && return 0
  printf 'ACTIVATION ARMED BUT NOT IN EFFECT (axis 4, env-arm effect-read): %s activation(s) carry a `.done` marker while the variable they arm is NOT what this session actually sees — %s. These install no launchd job, so axis 3 cannot see them, and the marker itself silences axis 1: an env-var arm is invisible to both by construction. This axis reads the variable in ITS OWN environment, which is the one the consumer hook inherits. The three states have DIFFERENT fixes. NOT-STAGED: marked done but the arm was never written — re-run `bash %s/<name>`. NOT-DELIVERED: the arm is on disk but nothing in this session'"'"'s provenance sourced it — add a source line to the shell rc that launches sessions. OVERRIDDEN: something later in the chain set a different value. An env-only arm is PROSPECTIVE-ONLY even once sourced — no already-running session inherits it, and it cannot reach a launchd-invoked caller at all, so a consumer that must work under launchd has to source the file itself.\n' \
    "${#bad[@]}" "$(join_names "${bad[@]}")" "$DIR"
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
    # THE SANCTIONED ADVANCE, never a raw ff (ship.md:98). This line used to render
    # `git -C $root merge --ff-only origin/main` as a ▶ runnable step on EVERY SessionStart, which
    # is the one command the deploy doctrine forbids: a bare ff advances the FILES but creates no
    # symlinks, so a brand-new tracked file lands unlinked and silently does nothing, and it skips
    # the green-stamp gate entirely. Rendering it here did not merely permit that — it INSTRUCTED
    # it, to every agent and operator, at session start. Measured on the shared checkout
    # 2026-07-31: 29 of the last 30 HEAD advances were raw ffs, which carried live HEAD 196 commits
    # above the newest green-stamped tree and deadlocked deploy-live's monotonicity guard (96
    # consecutive refusals). deploy-live.sh is green-gated AND runs install.sh, which is what
    # actually creates the missing links; if it refuses, that refusal is the finding, not a reason
    # to reach for the ff. Same command operator-readout.sh:169 already platters, so the two
    # operator surfaces cannot disagree about what "deploy" means.
    out="$out"$'\n'"    ▶ bash $root/scripts/deploy-live.sh   # the ONLY sanctioned advance (green-gated + runs install.sh, which creates the symlinks a bare ff never makes). do NOT cp live->repo: it would recreate a committed file as a local diff the next ff must conflict on"
  fi
  if [ "${#lonly[@]}" -gt 0 ]; then
    out="$out"$'\n'"  LIVE-ONLY — never committed, one \`rm\` from unrecoverable: $(join_names "${lonly[@]}")"
    out="$out"$'\n'"    ▶ cp $DIR/<name> $mirror/<name>   # then commit it; or \`touch $DIR/<name>.local\` if intentionally live-only"
  fi
  # REPO-ONLY and CONTENT-DRIFT are now CONVERGER-OWNED, and that changes both the remedy and what
  # the finding MEANS. scripts/deploy-migrations.sh materialises the live queue from the repo SSOT on
  # every converge (face 3), so neither class can persist across one — the repo side is authoritative
  # by construction and there is no longer a "which side wins" question to hand the operator. Seeing
  # either here therefore reports a CONVERGE THAT HAS NOT RUN, not a drift to reconcile by hand. The
  # old `cp`/`diff` platters are deleted deliberately: a hand-sync races the next converge and, in the
  # REPO-ONLY direction, invited exactly the repo-side write that creates a local diff the next
  # fast-forward must conflict on.
  if [ "${#ronly[@]}" -gt 0 ]; then
    out="$out"$'\n'"  REPO-ONLY — committed but not yet materialised into the live queue: $(join_names "${ronly[@]}")"
  fi
  if [ "${#cdrift[@]}" -gt 0 ]; then
    out="$out"$'\n'"  CONTENT-DRIFT — the copy the operator runs is behind the committed SSOT: $(join_names "${cdrift[@]}")"
  fi
  if [ "$(( ${#ronly[@]} + ${#cdrift[@]} ))" -gt 0 ]; then
    out="$out"$'\n'"    ▶ bash $root/scripts/deploy-live.sh   # the converger derives the live queue from the repo SSOT (deploy-migrations.sh --materialise); both classes above are unrepresentable once it runs. Do NOT hand-sync — the repo side is authoritative and a cp live->repo creates a local diff the next ff must conflict on"
  fi
  printf '%s\n' "$out"
}

watch() {
  [ -d "$DIR" ] || exit 0
  local msg age par inert envarm
  age="$(age_axis)"
  par="$(parity_axis)"
  inert="$(inert_axis)"
  envarm="$(envarm_axis)"
  msg="$age"
  if [ -n "$par" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$par"; else msg="$par"; fi
  fi
  # Axis 3 last but never least: a CLAIMED-DONE-BUT-INERT activation is the quietest of the three
  # (axis 1 is silenced by the very marker that is lying), so it must still reach the operator.
  if [ -n "$inert" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$inert"; else msg="$inert"; fi
  fi
  # Axis 4 is quieter still: axis 3 at least has a launchd job to interrogate, while an env-var arm
  # leaves NO durable artifact outside the env file itself. Never folded into axis 3 — their fixes
  # share no vocabulary (`bootstrap` vs `source`), and one axis emitting two remedy languages is how
  # the operator gets sent to the wrong one.
  if [ -n "$envarm" ]; then
    if [ -n "$msg" ]; then msg="$msg"$'\n\n'"$envarm"; else msg="$envarm"; fi
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
  out="$(CC_ACTIVATION_DIR="$d/q" CC_ACTIVATION_MIRROR_DIR="$d/q" CC_ACTIVATION_MAX_AGE_H=24 CC_ACTIVATION_DAMP_S=0 "$SELF")"
  printf '%s' "$out" | grep -q 'stale-activate.sh' && okp "stale un-run script is named" || badp "stale un-run NOT named"
  # CHANGED 2026-07-29 (row 10, §4 F7): axis 1 PARTITIONS instead of FILTERING, so a fresh un-run
  # script is now NAMED — under a FRESH heading, not a rotting one. The old assertion pinned the
  # >24h gate that hid the campaign's own freshest activations.
  printf '%s' "$out" | grep -q 'fresh-activate.sh' && okp "fresh (<24h) script IS named (partitioned)" || badp "fresh script NOT named"
  printf '%s' "$out" | grep -q 'ROTTING' && okp "rotting partition labelled" || badp "no ROTTING partition"
  printf '%s' "$out" | grep -q 'FRESH'   && okp "fresh partition labelled"   || badp "no FRESH partition"
  printf '%s' "$out" | grep -q '2 pending-activation script(s) NOT run' && okp "the count is the QUEUE (2), not a filtered subset (1)" || badp "count is not the queue"
  out2="$(CC_ACTIVATION_DIR="$d/q" CC_ACTIVATION_MIRROR_DIR="$d/q" CC_ACTIVATION_AGE_FILTER=on CC_ACTIVATION_DAMP_S=0 "$SELF")"
  printf '%s' "$out2" | grep -q 'fresh-activate.sh' && badp "kill switch did not restore the filter" || okp "CC_ACTIVATION_AGE_FILTER=on restores the >24h filter"
  printf '%s' "$out" | grep -q 'done-activate.sh'  && badp ".done-marked script wrongly named" || okp ".done-marked script NOT named"
  printf '%s' "$out" | grep -q 'ACTIVATION QUEUE'  && okp "emits the absence-is-loud line" || badp "no activation-queue line"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null 2>&1 \
      && okp "output is valid SessionStart additionalContext JSON" || badp "output not valid SessionStart JSON"
  else okp "jq absent — plain-stdout fallback (skipped JSON check)"; fi

  # ══ PAGE-ONCE (face 3) — the itemized page is an EDGE, the steady state is one counted line ══════
  # Its OWN dir, so the marker cannot leak into the cases above and silence one of them (every case
  # above runs with damping off precisely because a second invocation over the same set would
  # otherwise go quiet and its assertion would pass vacuously — memory:
  # sibling-guard-makes-the-fixture-vacuous).
  mkdir -p "$d/dampq"
  printf '#!/bin/bash\n' > "$d/dampq/one-activate.sh";  touch -t "$old" "$d/dampq/one-activate.sh"
  dq() { CC_ACTIVATION_DIR="$d/dampq" CC_ACTIVATION_MIRROR_DIR="$d/dampq" "$SELF" "$@"; }
  out="$(dq)"
  printf '%s' "$out" | grep -q 'one-activate.sh' && okp "first page of a new set is ITEMIZED" || badp "first page was not itemized"
  out="$(dq)"
  printf '%s' "$out" | grep -q 'one-activate.sh' && badp "the SAME un-run set re-listed every session (the always-fires alarm survives)" || okp "an unchanged set is damped — the 38-line wall is gone"
  printf '%s' "$out" | grep -q '1 un-run' && okp "…but absence stays LOUD: one counted line still asserts" || badp "damping went fully silent — absence-is-loud lost"
  # A CHANGED set re-pages IMMEDIATELY. Without this the damp is just a mute button.
  printf '#!/bin/bash\n' > "$d/dampq/two-activate.sh"; touch -t "$old" "$d/dampq/two-activate.sh"
  out="$(dq)"
  printf '%s' "$out" | grep -q 'two-activate.sh' && okp "a CHANGED set re-pages immediately (change is signal)" || badp "a newly staged activation was swallowed by the damp window"
  # A SWAP keeps the count identical — the case a count-keyed fingerprint would miss.
  : > "$d/dampq/two-activate.sh.done"
  printf '#!/bin/bash\n' > "$d/dampq/three-activate.sh"; touch -t "$old" "$d/dampq/three-activate.sh"
  out="$(dq)"
  printf '%s' "$out" | grep -q 'three-activate.sh' && okp "a SWAP at equal count re-pages (fingerprint is the SET, not the count)" || badp "an equal-count swap was damped — the fingerprint is keying on the count"
  # `--queue` is the escape hatch the damped line points at, and looking must not re-arm the window.
  out="$(dq --queue)"
  printf '%s' "$out" | grep -q 'three-activate.sh' && okp "--queue prints the full list on demand" || badp "--queue did not print the list"
  out="$(dq)"
  printf '%s' "$out" | grep -q 'three-activate.sh' && badp "--queue re-armed the damp marker — a look must not consume the next genuine change" || okp "--queue did not disturb the damp state"
  # DRAINED ⇒ the marker is cleared, so a REFILL is loud again rather than inheriting the old window.
  for _m in one two three; do : > "$d/dampq/$_m-activate.sh.done"; done
  dq >/dev/null 2>&1
  printf '#!/bin/bash\n' > "$d/dampq/four-activate.sh"; touch -t "$old" "$d/dampq/four-activate.sh"
  out="$(dq)"
  printf '%s' "$out" | grep -q 'four-activate.sh' && okp "a queue that drained and refilled pages LOUD (marker re-armed on empty)" || badp "a refill after a drain stayed damped"

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

  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/p/repo" CC_ACTIVATION_DAMP_S=0 "$SELF")"
  printf '%s' "$out" | grep -q 'liveonly-activate.sh'    && okp "LIVE-ONLY named (the unrecoverable class)"   || badp "LIVE-ONLY drift NOT named"
  printf '%s' "$out" | grep -q 'repoonly-activate.sh'    && okp "REPO-ONLY named (committed, never deployed)" || badp "REPO-ONLY drift NOT named"
  printf '%s' "$out" | grep -q 'drifted-activate.sh'     && okp "CONTENT-DRIFT named (live ≠ committed SSOT)" || badp "CONTENT-DRIFT NOT named"
  printf '%s' "$out" | grep -q 'intentional-activate.sh' && badp ".local live-only wrongly named"             || okp ".local marker exempts an intentional live-only"
  printf '%s' "$out" | grep -q 'same-activate.sh'        && badp "in-parity file wrongly named"               || okp "in-parity file NOT named (no false drift)"

  # positive control: the SAME code path must go quiet when the two copies agree
  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/p/live" CC_ACTIVATION_DAMP_S=0 "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "identical live+repo → silent (positive control)" || badp "false drift on identical dirs"

  # an unrunnable check must be LOUD — the vacuous-pass failure mode this axis exists to prevent
  out="$(CC_ACTIVATION_DIR="$d/p/live" CC_ACTIVATION_MIRROR_DIR="$d/nope" CC_ACTIVATION_DAMP_S=0 "$SELF")"
  printf '%s' "$out" | grep -q 'DID NOT RUN' && okp "unresolvable mirror is REPORTED, not a vacuous pass" || badp "unresolvable mirror silently skipped"

  echo "activation-watch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "activation-watch --selftest: GREEN — axis 1 stale/fresh/done/absent; PAGE-ONCE itemizes a new set, damps an unchanged one to a counted line, re-pages on a change AND on an equal-count swap, is inspectable via --queue without re-arming, and re-arms on drain; axis 2 live-only/repo-only/content-drift/.local-exempt/in-parity-quiet/unresolved-loud."
}

case "${1:-}" in
  --selftest) selftest ;;
  --queue)    # the full itemized listing on demand — the escape hatch the damped line points at.
              # It must NOT re-arm the damp marker: a human asking to see the list is not the machine
              # deciding the set changed, and letting a look reset the window would mean the next
              # genuine change went unpaged.
              CC_ACTIVATION_DAMP_S=0 DAMP_WINDOW_S=0 DAMP_FILE=/dev/null age_axis ;;
  --envarm)   # standalone entry: rc 1 when an env-var arm is not in effect for THIS shell, rc 0 when
              # every armed variable is delivered. Deliberately NOT a commit gate: the verdict is a
              # property of the CALLER's provenance, so a CI/launchd runner would read NOT-DELIVERED
              # for a perfectly healthy arm. It is an inspection entry, the `--queue` analogue.
    if [ ! -d "$DIR" ]; then echo "activation env-arm: live queue $DIR absent — nothing to read."; exit 0; fi
    EA="$(envarm_axis)"
    if [ -n "$EA" ]; then printf '%s\n' "$EA"; exit 1; fi
    echo "activation env-arm: GREEN — every armed variable is delivered to this shell (or none is staged)."
    ;;
  --parity)   # standalone/gate entry: rc 1 on ANY drift (incl. an unresolvable mirror), rc 0 only in parity
    if [ ! -d "$DIR" ]; then echo "activation SSOT parity: live queue $DIR absent — nothing to compare."; exit 0; fi
    PAR="$(parity_axis)"
    if [ -n "$PAR" ]; then printf '%s\n' "$PAR"; exit 1; fi
    echo "activation SSOT parity: GREEN — $DIR and the repo mirror agree."
    ;;
  *)          watch ;;
esac
