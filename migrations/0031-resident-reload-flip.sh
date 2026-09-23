#!/bin/bash
# migration-class: c10
# migration-step: RULE decision packet 4194644aea26 first (cc-decide list --open), then run this to set CC_INSTALL_RESIDENT_RELOAD=1 in the com.claude.deploy-live launchd plist — it lets the unattended converger bootout/bootstrap a resident daemon that is running stale bytes. It edits a launchd plist AND widens what the unattended path may do, which is C10 twice over.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0031-resident-reload-flip.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.deploy-live.plist
# migration-verify: [ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' "$HOME/Library/LaunchAgents/com.claude.deploy-live.plist" 2>/dev/null)" = 1 ]
# migration-conflict: v="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' "$HOME/Library/LaunchAgents/com.claude.deploy-live.plist" 2>/dev/null)"; [ -n "$v" ] && [ "$v" != 1 ]
#
# 0031 — T17 of docs/plans/CONTINUOUS_DELIVERY_TO_LIVE_KITTY.md, the L4 gap's general case.
#
# WHAT THIS REPLACES AND WHY IT IS NOT IN /tmp. Decision packet 4194644aea26 is class C — OPEN,
# human-only, no default — and its class contract calls for "a staged one-action artifact + rollback
# one-liner". That artifact existed once as `/tmp/resident-reload-flip.sh` and was REAPED by the
# 2026-09-16 reboot, leaving the decision answerable and physically unexecutable. Re-minting it in
# /tmp would re-arm the same failure on the next reboot, so it lands here instead: `migrations/` is
# the enforcing side (README.md), a c10 migration is STAGED and never self-runs, and its
# `migration-step:` is filed to cc-backlog by registration-state.sh — so the operator's step is
# tracked by the machine rather than by a file somebody has to remember to visit.
#
# 🚨 THE PACKET'S POPULATION IS SMALLER THAN THE PACKET SAYS — MEASURED 2026-09-17, AND THE OPERATOR
# SHOULD RULE ON THE CORRECTED VERSION. The packet names "two daemons: the one that supervises
# sessions, and the one that is the only guard against the crash class that killed five machines in
# eleven days." Enumerated from the live LaunchAgents dir, exactly THREE claude jobs are resident
# (KeepAlive=yes): com.claude.caffeinate-floor, com.claude.compressor-sentinel,
# com.claude.lead-supervisor. Of those, **lead-supervisor already cures itself** —
# `self_restart_if_stale()` at scripts/lead-supervisor.sh:1329 digests its own source per tick,
# ABSTAINS if unreadable, and exits on change, so KeepAlive restarts it on the new bytes with no
# deploy-job involvement at all. So one of the packet's two named daemons is already out of scope,
# and the "no" branch's stated cost — "stale daemons keep running old code indefinitely until you
# restart each one by hand" — is true today of compressor-sentinel and caffeinate-floor, not of the
# supervisor. The same self-retire pattern landed for the overlay daemon on 2026-09-17 (38ec05382).
#
# THEREFORE THERE IS A THIRD OPTION THE PACKET DOES NOT CARRY, and it needs no ruling at all: give
# compressor-sentinel and caffeinate-floor the self-retire the other two already have. A daemon
# retiring ITSELF is not the unattended path holding a power withheld from agents — it is the
# process deciding about its own lifetime, which is why nobody had to rule on lead-supervisor's.
# It is NOT built here, deliberately: compressor-sentinel is a crash guard, a self-exit opens a
# restart gap in exactly the protection the packet says killed five machines when absent, and how
# wide a gap that guard tolerates is not a fact this session could measure. Filed rather than driven,
# with the conviction stated — see the plan's Record and the backlog row this commit files.
#
# WHAT `CC_INSTALL_RESIDENT_RELOAD=1` ACTUALLY DOES (install.sh:1101-1118). The staleness DETECTOR
# runs unconditionally already; only the MUTATION is behind the flag. With it set, install.sh —
# invoked by the converger at scripts/deploy-live.sh:2665, as a child, so this plist environment is
# inherited — issues `launchctl bootout gui/$uid/<label>` followed by `bootstrap` for a resident
# daemon whose on-disk image changed after it started. A failed bootstrap is counted and warned, and
# leaves the daemon NOT running: that is the blast radius, and it is why this is the operator's.
#
# WHY THE PLIST AND NOT install.sh's DEFAULT. The flag must be true for the UNATTENDED converger and
# for nothing else. Flipping `${CC_INSTALL_RESIDENT_RELOAD:-0}` to `:-1` would also arm every
# hand-run and every agent-run install.sh on the box, which is a strictly larger grant than the
# packet asks about. Scoping it to com.claude.deploy-live's own environment grants exactly the power
# the packet describes and nothing beyond it.
#
# ROLLBACK, one line:
#   /usr/libexec/PlistBuddy -c 'Delete :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' \
#     ~/Library/LaunchAgents/com.claude.deploy-live.plist && \
#     launchctl bootout "gui/$(id -u)/com.claude.deploy-live" 2>/dev/null; \
#     launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.claude.deploy-live.plist
set -uo pipefail

PLIST="$HOME/Library/LaunchAgents/com.claude.deploy-live.plist"
LABEL="com.claude.deploy-live"
PB=/usr/libexec/PlistBuddy
# Seam, matching install.sh's own LAUNCHCTL_BIN: without it the suite that proves this refuses
# correctly would BOOTOUT THE OPERATOR'S REAL CONVERGER to find that out (memory:
# a-research-probe-that-drives-real-ui-writes-into-the-operator-s — a "read-only" test that invokes
# an actuator is not read-only). Production resolves the real binary exactly as before.
LAUNCHCTL_BIN="${CC_LAUNCHCTL_BIN:-launchctl}"
DECISIONS="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
PACKET="$DECISIONS/4194644aea26.json"

# ── PRECONDITION 1: THE RULING. This is the whole point of the packet, so the script refuses to be
# the thing that quietly pre-empts it. An OPEN class-C packet has not been decided; `cc-decide
# action 4194644aea26` is what records that it has. Fails CLOSED on an unreadable packet: a ruling
# we cannot read is not a ruling (memory: predicate-refusal-is-not-a-negative).
if [ -f "$PACKET" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    printf '0031: REFUSED — jq is required to read decision packet 4194644aea26, and an unverifiable ruling is not a ruling.\n' >&2
    exit 1
  fi
  RID=4194644aea26
  status="$(jq -r '.status // "unreadable"' "$PACKET" 2>/dev/null || printf 'unreadable')"
  # `actioned` is NOT always a ruling. A consolidation closes a stale packet with `cc-decide action
  # --evidence "SUPERSEDED by <new> …"` (or MOOT / MERGED into / NOT YOURS) — measured 2026-09-22:
  # the consolidation in docs/research/decision-consolidation-2026-09-22.md closed THIS packet that
  # way, and this gate then read it as "ruled" with no ruling ever made. Follow a supersession to the
  # packet that carries the live question; refuse every other consolidation closure. Bounded hops.
  hops=0
  while [ "$status" = actioned ] && [ "$hops" -lt 5 ]; do
    ev="$(jq -r '.evidence // ""' "$PACKET" 2>/dev/null || printf '')"
    case "$ev" in
      "SUPERSEDED by "*)
        next="$(printf '%s' "$ev" | sed -n 's/^SUPERSEDED by \([0-9a-f]\{12\}\).*/\1/p')"
        if [ -z "$next" ] || [ ! -f "$DECISIONS/$next.json" ]; then status="superseded-unresolvable"; break; fi
        RID="$next"; PACKET="$DECISIONS/$next.json"
        status="$(jq -r '.status // "unreadable"' "$PACKET" 2>/dev/null || printf 'unreadable')"
        hops=$((hops + 1)) ;;
      "MOOT"*|"MERGED into"*|"NOT YOURS"*) status="closed-without-ruling"; break ;;
      *) break ;;
    esac
  done
  [ "$status" = actioned ] && [ "$hops" -ge 5 ] && status="supersession-chain-too-long"
  case "$status" in
    actioned) printf '0031: precondition OK — packet %s is ruled (status=actioned)\n' "$RID" ;;
    open)
      printf '0031: REFUSED — decision packet %s is still OPEN.\n' "$RID" >&2
      printf '      It is class C (human-only, no default): it asks whether the unattended deploy\n' >&2
      printf '      job may restart a background daemon by itself. Running this now would answer it\n' >&2
      printf '      by acting, which is the one thing the class forbids.\n' >&2
      printf '      Read it:  cc-decide list --open\n' >&2
      printf '      Rule it:  cc-decide action %s --evidence "<why>"   (then re-run this)\n' "$RID" >&2
      printf '      Kill it:  cc-decide veto   %s\n' "$RID" >&2
      printf '      NOTE: the packet overstates its population — see this file header. Only\n' >&2
      printf '      compressor-sentinel and caffeinate-floor are affected; lead-supervisor already\n' >&2
      printf '      self-restarts (lead-supervisor.sh:1329).\n' >&2
      exit 1 ;;
    vetoed)
      printf '0031: REFUSED — packet %s was VETOED. The operator declined this grant; the flag stays off.\n' "$RID" >&2
      exit 1 ;;
    *)
      printf '0031: REFUSED — packet %s status is "%s", which is not a ruling this can act on.\n' "$RID" "$status" >&2
      exit 1 ;;
  esac
else
  printf '0031: REFUSED — decision packet 4194644aea26 is not on disk (%s).\n' "$PACKET" >&2
  printf '      This migration exists to execute THAT ruling. Without the packet there is nothing\n' >&2
  printf '      recording that the grant was made, so the grant is not made.\n' >&2
  exit 1
fi

# ── PRECONDITION 2: the subject. Never create a plist here; a missing one means the converger is
# not installed the way this grant assumes, and inventing it would grant power over a job nobody
# registered.
if [ ! -f "$PLIST" ]; then
  printf '0031: REFUSED — %s does not exist, so there is no unattended converger to grant this to.\n' "$PLIST" >&2
  exit 1
fi
if ! $PB -c 'Print :Label' "$PLIST" >/dev/null 2>&1; then
  printf '0031: REFUSED — %s is not a readable plist.\n' "$PLIST" >&2
  exit 1
fi

# Already set? Idempotent, exactly as every migration here must be.
cur="$($PB -c 'Print :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' "$PLIST" 2>/dev/null || true)"
if [ "$cur" = 1 ]; then
  printf '0031: already set — CC_INSTALL_RESIDENT_RELOAD=1 in %s\n' "$PLIST"
  exit 0
fi
if [ -n "$cur" ]; then
  printf '0031: CONFLICT — CC_INSTALL_RESIDENT_RELOAD is already set to "%s", not 1. Left unchanged; resolve by hand.\n' "$cur" >&2
  exit 1
fi

bak="$PLIST.bak-0031-$(date +%Y%m%d%H%M%S)"
cp -p "$PLIST" "$bak" || { printf '0031: backup FAILED, not touching the plist\n' >&2; exit 1; }

# Add the dict only if absent — never clobber sibling variables.
if ! $PB -c 'Print :EnvironmentVariables' "$PLIST" >/dev/null 2>&1; then
  $PB -c 'Add :EnvironmentVariables dict' "$PLIST" || {
    printf '0031: could not add :EnvironmentVariables; restoring backup\n' >&2
    cp -p "$bak" "$PLIST"; exit 1; }
fi
if ! $PB -c 'Add :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD string 1' "$PLIST"; then
  printf '0031: could not set CC_INSTALL_RESIDENT_RELOAD; restoring backup\n' >&2
  cp -p "$bak" "$PLIST"; exit 1
fi

# VERIFY BY READING IT BACK through a different call than the one that wrote it — never by the
# writer's own exit code (memory: discharge-predicate-must-measure-its-own-subject).
if [ "$($PB -c 'Print :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' "$PLIST" 2>/dev/null)" != 1 ]; then
  printf '0031: the edit did not verify; restoring backup\n' >&2
  cp -p "$bak" "$PLIST"; exit 1
fi
if ! plutil -lint "$PLIST" >/dev/null 2>&1; then
  printf '0031: plist failed plutil -lint after the edit; restoring backup\n' >&2
  cp -p "$bak" "$PLIST"; exit 1
fi
printf '0031: set CC_INSTALL_RESIDENT_RELOAD=1 in %s (backup: %s)\n' "$PLIST" "$bak"

# ── Reload the job so the new environment is actually in effect. A plist edit alone changes NOTHING
# about the RUNNING job — landed is not live, and that is this whole plan's subject.
uid="$(id -u)"
"$LAUNCHCTL_BIN" bootout "gui/$uid/$LABEL" 2>/dev/null || true
if "$LAUNCHCTL_BIN" bootstrap "gui/$uid" "$PLIST" 2>/dev/null; then
  printf '0031: %s reloaded — the next converge inherits the flag\n' "$LABEL"
else
  printf '0031: WARNING — %s did not bootstrap; the flag is in the plist but the job is NOT running.\n' "$LABEL" >&2
  printf '      Recover: launchctl bootstrap gui/%s %s\n' "$uid" "$PLIST" >&2
  exit 1
fi
exit 0
