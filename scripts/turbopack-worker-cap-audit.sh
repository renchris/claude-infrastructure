#!/bin/bash
# turbopack-worker-cap-audit.sh — which Next apps on this box can still mint an unbounded
# postcss worker horde, and which have been capped.
#
#   scripts/turbopack-worker-cap-audit.sh [--root DIR] [--json] [--quiet]
#
# Exit 0 = every app that CAN carry the cap does. Exit 3 = at least one cannot be ruled out.
# The non-zero exit is the DESIGNED verdict, not an error — it is what lets a caller gate on this.
#
# WHY THIS EXISTS, AND WHY IT IS AN AUDITOR RATHER THAN AN EDIT (CONCURRENCY_PROGRAM §S6.5).
# Wave C's second deliverable is "cap the worker pool". The cap is real and it is a ONE-LINE config
# edit — `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` — but it lives in the
# next.config of each app's OWN repo, and this repo owns none of them. W11's source-level finding
# (crash-rootcause-2026-08-09.md §7) is why no upgrade substitutes for it: turbopack's
# `process_pool/mod.rs` is byte-identical across 16.2.6↔16.2.12, its bootup semaphore gains +1
# permanent permit per completed boot, the scheduler spawns fresh workers with ZERO delay whenever
# `queued_tasks` spikes, and the only reaper fires after a whole-app module-graph COMPLETION that
# continuous fleet edits prevent. The flag removes the child processes entirely by moving plugin
# evaluation onto worker THREADS — one V8 heap instead of 700 PIDs.
#
# So the honest deliverable from THIS repo is not the edit; it is making the gap OBSERVABLE and
# re-checkable, in a store something already reads. A remedy that exists only as a sentence in a
# research doc is the exact shape MEMORY.md records as conclusion-must-reach-the-enforcing-store:
# eight correct analyses that landed and changed nothing.
#
# THE SUPPORT TEST READS THE INSTALLED ARTIFACT, NEVER A VERSION NUMBER. Support is decided by
# grepping the app's OWN `node_modules/next/dist/server/config-schema.js` for the option. A version
# range in package.json is an intent, and even the installed package.json version is a label — the
# schema file is the thing that will accept or reject the key at boot. Measured 2026-08-09: of 76
# Next apps under ~/Development, exactly 3 have a schema that carries it (all on 16.2.6), and NONE
# of the 3 set it. `reso-playwright` declares ^15.5.11 and has 14.2.30 installed, which is precisely
# the drift a version-number test would have got wrong.
#
# WHAT COUNTS AS COVERED — three ways, all of them honest:
#   set       the flag is present in the app's next config
#   webpack   the app's dev AND build scripts opt out of turbopack (`--webpack`), so the turbopack
#             process pool is never reached. A real mitigation, not a pass by omission.
#   n/a       the installed next has no such option (or next is not installed) — nothing to set.
# Anything else is UNCOVERED and is what the exit code and the verdict token report.
#
# Deliberately NOT a fixer. It never writes into another repo: a cross-repo config edit belongs to
# that repo's own rails, and an auditor that silently edits its subjects is how a census becomes an
# incident.
set -uo pipefail

ROOT="$HOME/Development"
FMT=table
QUIET=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-$ROOT}"; shift 2 || shift ;;
    --json) FMT=json; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

[ -d "$ROOT" ] || { printf 'turbopack-cap: no such root: %s\n' "$ROOT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'turbopack-cap: jq required\n' >&2; exit 1; }

OPT=turbopackPluginRuntimeStrategy
ROWS=""            # <app>\t<installed>\t<support>\t<state>\t<config>
UNCOVERED=0
SCANNED=0

# Top level only. `.worktrees` is excluded by construction (it is a dot-directory and never a
# top-level repo here), and node_modules is never descended into: a nested app inside a dependency
# is not a thing anyone runs.
for pkg in "$ROOT"/*/package.json; do
  [ -f "$pkg" ] || continue
  app="$(dirname "$pkg")"
  # A `next` DEPENDENCY, in either map — not a mention anywhere in the file.
  jq -e '((.dependencies // {}) + (.devDependencies // {})) | has("next")' "$pkg" >/dev/null 2>&1 || continue
  SCANNED=$((SCANNED + 1))

  installed="$(jq -r '.version // "?"' "$app/node_modules/next/package.json" 2>/dev/null)" || installed=""
  [ -n "$installed" ] || installed="not-installed"

  # SUPPORT — read the installed schema, never the version label.
  support=no
  if [ "$installed" = "not-installed" ]; then
    support=n/a
  elif grep -q "$OPT" "$app/node_modules/next/dist/server/config-schema.js" 2>/dev/null; then
    support=yes
  fi

  cfg=""
  for c in next.config.js next.config.mjs next.config.ts next.config.cjs; do
    [ -f "$app/$c" ] && { cfg="$c"; break; }
  done

  # STATE.
  state=uncovered
  if [ "$support" != "yes" ]; then
    state=n/a
  elif [ -n "$cfg" ] && grep -q "$OPT" "$app/$cfg" 2>/dev/null; then
    state="set"
  else
    # A turbopack opt-out on BOTH dev and build is a real mitigation. One-sided (e.g. an
    # analyze-only `--webpack`) is NOT — the dev path is where the storm was measured.
    dev="$(jq -r '.scripts.dev // ""' "$pkg" 2>/dev/null)"
    bld="$(jq -r '.scripts.build // ""' "$pkg" 2>/dev/null)"
    case "$dev$bld" in
      *--webpack*)
        case "$dev" in *--webpack*) d=1 ;; *) d=0 ;; esac
        case "$bld" in *--webpack*) b=1 ;; *) b=0 ;; esac
        [ "$d" = 1 ] && [ "$b" = 1 ] && state=webpack ;;
    esac
  fi
  [ "$state" = "uncovered" ] && UNCOVERED=$((UNCOVERED + 1))

  ROWS="$ROWS$(basename "$app")	$installed	$support	$state	${cfg:-none}
"
done

if [ "$FMT" = json ]; then
  printf '%s' "$ROWS" | jq -R -s --argjson u "$UNCOVERED" --argjson n "$SCANNED" '
    { scanned: $n, uncovered: $u,
      verdict: (if $u == 0 then "covered" else "uncovered" end),
      apps: (split("\n") | map(select(length > 0)) | map(split("\t") |
             {app:.[0], installed:.[1], supports:.[2], state:.[3], config:.[4]})) }'
elif [ "$QUIET" -eq 0 ]; then
  printf 'app\tinstalled\tsupports\tstate\tconfig\n'
  printf '%s' "$ROWS" | sort -t'	' -k4,4 -k1,1
  printf '\n'
fi

# The verdict token is emitted on EVERY format and always to stderr, so a caller that parses stdout
# as a table or as JSON still gets a machine-readable answer, and a `|| true` in a caller cannot
# quietly convert this into a success (MEMORY.md claimed-outcome-vs-checked-outcome).
printf 'turbopack-cap: verdict=%s scanned=%d uncovered=%d option=%s\n' \
  "$([ "$UNCOVERED" -eq 0 ] && printf covered || printf uncovered)" "$SCANNED" "$UNCOVERED" "$OPT" >&2

[ "$UNCOVERED" -eq 0 ] || exit 3
exit 0
