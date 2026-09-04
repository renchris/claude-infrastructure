#!/usr/bin/env bash
# drain-brief.sh — GENERATE a drain link's brief from the checked-in template, and nothing else.
#
# ── THE DEFECT THIS CLOSES ──────────────────────────────────────────────────────────────────────
# The local 24/7 drain chain (#1–#299) regenerated each link's brief from its PREDECESSOR'S brief:
# a clone + sed renumber + splice, with every link appending its own "method N" findings. By #299
# the brief was 3,366 lines (~300 KB) of self-audit, its instructions to claim and close backlog
# rows had been spliced out entirely (grep it for `cc-backlog claim`: zero hits), and over its last
# week it landed ~264 commits about its own machinery against ~46 rows closed — the last dozen
# links closing ZERO rows each while writing essays about the link before them.
#
# A brief that is derived from the previous brief is a brief that accumulates. This script makes the
# brief a PURE FUNCTION of (template, N, lane, project, worktree, since, min): the template is a
# tracked file under review like any other, a link cannot extend it (the fire wrapper regenerates
# it), and the only per-link variation is the numbers. The line cap below is the ratchet that keeps
# it that way — a template that grows past it refuses to generate, which is the one failure that
# is loud instead of gradual (memory `enforcement-must-live-at-the-chokepoint`).
#
# Usage:
#   drain-brief.sh --num <N> [--lane infra] [--project claude-infrastructure] [--worktree <abs path>]
#                  [--infra <claude-infrastructure checkout>] [--since <ISO-8601-Z>] [--min <closed floor>]
#                  [--force] [--print]
#     writes <dir>/fire-drain-recycle<N>.txt (lane a) or <dir>/fire-drain-<lane>-recycle<N>.txt,
#     and the ~150-byte pointer beside it; prints the POINTER path on stdout.
#     --print   substitute and print the brief to stdout; write nothing.
#     --force   overwrite an existing brief for this (lane, N). Without it, refuse (rc 3): a brief
#               already on disk is either a sibling chain's or a re-fire's, and clobbering it
#               silently is how two chains end up reading one number.
# Env:
#   CC_DRAIN_BRIEF_DIR   where briefs live (default $CLAUDE_CONFIG_DIR/autonomy — NOT /tmp: a reboot
#                        destroyed #217's whole scratchpad, and this dir is what the chain trusts)
#   CC_DRAIN_TEMPLATE    the template (default scripts/drain-brief.template.md beside this script)
#   CC_DRAIN_MIN_CLOSED  default closure floor (default 3)
#   CC_DRAIN_INFRA       the claude-infrastructure checkout whose scripts/ the brief calls (default
#                        $HOME/Development/claude-infrastructure — the live layer's source, which the
#                        trunk fast-forward keeps current); a lane draining ANOTHER repo needs it
#   CC_DRAIN_BRIEF_MAX_LINES  the ratchet (default 200)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
DIR="${CC_DRAIN_BRIEF_DIR:-$CFG/autonomy}"
TEMPLATE="${CC_DRAIN_TEMPLATE:-$HERE/drain-brief.template.md}"
MAX_LINES="${CC_DRAIN_BRIEF_MAX_LINES:-200}"

die() { printf 'drain-brief: %s\n' "$1" >&2; exit "${2:-2}"; }

NUM=""; LANE="${CC_DRAIN_LANE:-infra}"; PROJECT="claude-infrastructure"; WORKTREE=""; SINCE=""; MIN="${CC_DRAIN_MIN_CLOSED:-3}"
INFRA="${CC_DRAIN_INFRA:-${HOME:-}/Development/claude-infrastructure}"
FORCE=0; PRINT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --num)      NUM="${2:?--num needs the recycle number}"; shift 2 ;;
    --lane)     LANE="${2:?--lane needs a name}"; shift 2 ;;
    --project)  PROJECT="${2:?--project needs a name}"; shift 2 ;;
    --worktree) WORKTREE="${2:?--worktree needs an absolute path}"; shift 2 ;;
    --infra)    INFRA="${2:?--infra needs the claude-infrastructure checkout path}"; shift 2 ;;
    --since)    SINCE="${2:?--since needs an ISO-8601 Z timestamp}"; shift 2 ;;
    --min)      MIN="${2:?--min needs a number}"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    --print)    PRINT=1; shift ;;
    -h|--help)  sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

case "$NUM" in ''|*[!0-9]*) die "--num must be digits, got '${NUM:-}'" ;; esac
case "$MIN" in ''|*[!0-9]*) die "--min must be digits, got '${MIN:-}'" ;; esac
case "$LANE" in ''|*[!a-z0-9-]*) die "--lane must be [a-z0-9-], got '${LANE:-}'" ;; esac
case "$PROJECT" in ''|*[!A-Za-z0-9._-]*) die "--project must be a project label, got '${PROJECT:-}'" ;; esac
[ -n "$SINCE" ] || SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "$SINCE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) die "--since must be ISO-8601 Z (e.g. 2026-09-04T12:00:00Z), got '$SINCE'" ;;
esac
[ -n "$WORKTREE" ] || WORKTREE="${HOME:-}/Development/.worktrees/drain/lane-$LANE"
case "$WORKTREE" in /*) : ;; *) die "--worktree must be absolute, got '$WORKTREE'" ;; esac
case "$INFRA" in /*) : ;; *) die "--infra must be absolute, got '$INFRA'" ;; esac
[ -r "$TEMPLATE" ] || die "template unreadable: $TEMPLATE" 4

# ── PER-PROJECT RAILS. A lane drains ONE project and lands with THAT repo's rail; the drain scripts
# themselves always come from the claude-infrastructure checkout ($INFRA). The rails below are the
# two repos with a known, verified landing policy; any other project gets the honest instruction
# to read its own CLAUDE.md, because a landing cost is a perishable fact only the repo can state
# (global CLAUDE.md § Ship policy). The §2.1 entry exists only in claude-infrastructure's plan.
# shellcheck disable=SC2016  # the backticks below are MARKDOWN code spans in the generated brief, not
#                               command substitutions — single quotes are exactly what keeps them literal.
case "$PROJECT" in
  claude-infrastructure)
    GATE_CMD='`bash scripts/gate-select.sh --direct origin/main...HEAD` (run every suite it names, one at a time, each with `< /dev/null`)'
    LAND_CMD='`SHIP_LAND_SMOKE_BUDGET_S=420 bash scripts/ship-land.sh` from this worktree (the project-local /ship; standing-land is authorized here). rc 11 = the post-land verifier is still in flight: `ps -p <pid>`, wait, re-fire unchanged.'
    ENTRY_STEP="Append ONE entry of ≤8 lines to \`docs/plans/BACKLOG_DRAIN_24_7.md\` §2.1 (newest first, directly under the \`## §2.1\` heading): \`- **<UTC date> — recycle #$NUM (lane $LANE):** closed <ids> · blocked <ids> · released <ids> · landed <shas> · <the closure-report line verbatim>.\` Commit it (\`docs(drain): recycle #$NUM — closed N rows\`) and land it with your last batch, or alone." ;;
  reso-management-app)
    GATE_CMD='`pnpm typecheck && pnpm lint && pnpm test:unit` (the repo'"'"'s own gate — see its CLAUDE.md)'
    LAND_CMD='FIRST `bash scripts/land-status.sh` — it asserts from the live APIs that a push to main builds and ships NOTHING (LAND_SHIP_V2, 2026-08-02); if it reads UNKNOWN or says main deploys, do NOT land — leave the branch and say so in the ping. Otherwise run this repo'"'"'s `/ship` (free and agent-driven per its CLAUDE.md § Deploy trigger). NEVER `/deploy` — that one spends money and is the operator'"'"'s.'
    ENTRY_STEP='This lane'"'"'s repo is not claude-infrastructure: there is no §2.1 entry to write — the ledger (`cc-backlog`) is the record, and the closure-report line goes into the ping.' ;;
  *)
    GATE_CMD='this repo'"'"'s typecheck / lint / unit gate as its CLAUDE.md names them'
    LAND_CMD='this repo'"'"'s `/ship` rail as its own CLAUDE.md § ship states — read it first; if landing there spends money, do NOT land: leave the branch, block the row with the exact land command in `--run`, and say so in the ping.'
    ENTRY_STEP='This lane'"'"'s repo is not claude-infrastructure: there is no §2.1 entry to write — the ledger (`cc-backlog`) is the record, and the closure-report line goes into the ping.' ;;
esac

# THE RATCHET. The template is what a link reads; a template past the cap is the old chain's shape
# returning, and it must refuse here rather than ship a longer brief one link at a time.
tlines="$(wc -l < "$TEMPLATE" | tr -d ' ')"
[ "$tlines" -le "$MAX_LINES" ] || die "template is $tlines lines; the cap is $MAX_LINES (CC_DRAIN_BRIEF_MAX_LINES). A brief that grows is the defect this script exists to stop — cut it, do not raise the cap." 5

body="$(cat "$TEMPLATE")"
next=$((NUM + 1))
body="${body//\{\{N\}\}/$NUM}"
body="${body//\{\{NEXT\}\}/$next}"
body="${body//\{\{LANE\}\}/$LANE}"
body="${body//\{\{PROJECT\}\}/$PROJECT}"
body="${body//\{\{WORKTREE\}\}/$WORKTREE}"
body="${body//\{\{SINCE\}\}/$SINCE}"
body="${body//\{\{MIN\}\}/$MIN}"
body="${body//\{\{INFRA\}\}/$INFRA}"
body="${body//\{\{GATE_CMD\}\}/$GATE_CMD}"
body="${body//\{\{LAND_CMD\}\}/$LAND_CMD}"
body="${body//\{\{ENTRY_STEP\}\}/$ENTRY_STEP}"
case "$body" in *'{{'*) die "template carries a placeholder this script does not know: $(printf '%s' "$body" | grep -o '{{[A-Z_]*}}' | sort -u | tr '\n' ' ')" 6 ;; esac

if [ "$PRINT" -eq 1 ]; then printf '%s\n' "$body"; exit 0; fi

if [ "$LANE" = a ]; then
  brief="$DIR/fire-drain-recycle$NUM.txt"; pointer="$DIR/fire-pointer-$NUM.txt"
else
  brief="$DIR/fire-drain-$LANE-recycle$NUM.txt"; pointer="$DIR/fire-pointer-$LANE-$NUM.txt"
fi
mkdir -p "$DIR" || die "cannot create $DIR" 4
if [ "$FORCE" -ne 1 ] && { [ -e "$brief" ] || [ -e "$pointer" ]; }; then
  die "a brief for lane $LANE recycle #$NUM already exists ($brief) — pass --force to replace it, or pick the next number" 3
fi
printf '%s\n' "$body" > "$brief" || die "cannot write $brief" 4
printf 'Read %s in full, then follow it as your complete brief.\nYou are recycle #%s of the 24/7 backlog drain chain (lane %s, project %s).\n' \
  "$brief" "$NUM" "$LANE" "$PROJECT" > "$pointer" || die "cannot write $pointer" 4
psize="$(wc -c < "$pointer" | tr -d ' ')"
[ "$psize" -lt 400 ] || die "pointer is $psize bytes; it must stay a pointer (<400) — handoff-fire expands it into one argv word" 7
printf 'drain-brief: wrote %s (%s lines) and %s (%s bytes) — lane %s recycle #%s project %s since %s min %s\n' \
  "$brief" "$(wc -l < "$brief" | tr -d ' ')" "$pointer" "$psize" "$LANE" "$NUM" "$PROJECT" "$SINCE" "$MIN" >&2
printf '%s\n' "$pointer"
