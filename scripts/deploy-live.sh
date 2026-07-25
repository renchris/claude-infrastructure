#!/bin/bash
# deploy-live.sh — the OPERATOR's one safe command for advancing the LIVE layer.
#
# Why: the live checkout (~/Development/claude-infrastructure) is what every session actually
# runs — hooks, scripts, launchd jobs. The old nag emitted a raw `git pull --ff-only`, which
# deploys whatever happens to be on origin/main, VERIFIED OR NOT. Agents are classifier-blocked
# from deploying, so the operator is the only one who can pull the trigger — this script makes
# that trigger fail-closed: it advances ONLY to a commit whose tree carries a GREEN post-land
# verification stamp, and refuses (loudly, with a page) when none exists.
#
# Stamp contract: <stamps>/<tree-sha>.json containing "verdict":"green" (tree-keyed, so a
# rebase/cherry-pick that preserves the tree keeps its verdict). Written by postland-verify.sh.
#
# Behavior: fetch origin/main → walk it newest-first → first GREEN commit = TARGET →
# `merge --ff-only TARGET` (never origin/main) → run install.sh (idempotent) → report the
# un-stamped commits still queued above the deployed tip.
#
# Flags: --dry-run (decide + print, mutate nothing) · --bootstrap (stamps dir ABSENT: deploy the
# tip unstamped, loud banner) · --force (same, with stamps present — documented escape hatch).
# Env: DEPLOY_REPO · CC_POSTLAND_DIR · CC_POSTLAND_BIN · CC_PAGES_DIR · CC_DEPLOY_SCAN.
# bash-3.2-safe, no eval, fail-closed, never rolls back.
set -uo pipefail

DEPLOY_REPO="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"
POSTLAND_DIR="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
STAMPS_DIR="$POSTLAND_DIR/stamps"
POSTLAND_BIN="${CC_POSTLAND_BIN:-$DEPLOY_REPO/scripts/postland-verify.sh}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
SCAN_N="${CC_DEPLOY_SCAN:-200}"

DRY_RUN=0; BOOTSTRAP=0; FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --bootstrap) BOOTSTRAP=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)   sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)           printf 'deploy-live: unknown arg %s (use --dry-run|--bootstrap|--force)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf 'deploy-live: %s\n' "$1"; }
die()  { printf 'deploy-live: REFUSED — %s\n' "$1" >&2; exit 1; }
g()    { git -C "$DEPLOY_REPO" "$@"; }

# a stamp is green iff its JSON says so — python3 when available (real parse), grep otherwise
is_green() { # <stamp-file>
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try: sys.exit(0 if json.load(open(sys.argv[1])).get("verdict")=="green" else 1)
except Exception: sys.exit(1)' "$1" 2>/dev/null && return 0
    return 1
  fi
  grep -qE '"verdict"[[:space:]]*:[[:space:]]*"green"' "$1" 2>/dev/null
}

g rev-parse --git-dir >/dev/null 2>&1 || die "DEPLOY_REPO is not a git checkout: $DEPLOY_REPO"
g fetch origin main >/dev/null 2>&1 || die "git fetch origin main FAILED in $DEPLOY_REPO (network? remote?)"

HEAD_SHA="$(g rev-parse HEAD 2>/dev/null || true)"
TIP_SHA="$(g rev-parse origin/main 2>/dev/null || true)"
[ -n "$HEAD_SHA" ] && [ -n "$TIP_SHA" ] || die "cannot resolve HEAD / origin/main in $DEPLOY_REPO"

TARGET=""; UNSTAMPED=0; BANNER=""
if [ ! -d "$STAMPS_DIR" ]; then
  # The verification net is not active yet. Deploying is a decision, not a default.
  [ "$BOOTSTRAP" -eq 1 ] || [ "$FORCE" -eq 1 ] || \
    die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Re-run with --bootstrap to deploy origin/main UNSTAMPED."
  TARGET="$TIP_SHA"; BANNER="UNSTAMPED bootstrap deploy — no verification net; nothing vouches for this tree"
elif [ "$FORCE" -eq 1 ]; then
  TARGET="$TIP_SHA"; BANNER="UNSTAMPED --force deploy — green-stamp gate BYPASSED by the operator"
else
  scanned=0
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    tree="$(g rev-parse "$sha^{tree}" 2>/dev/null || true)"
    if [ -n "$tree" ] && is_green "$STAMPS_DIR/$tree.json"; then TARGET="$sha"; UNSTAMPED="$scanned"; break; fi
    scanned=$((scanned + 1))
  done <<EOF
$(g rev-list "origin/main" -n "$SCAN_N" 2>/dev/null)
EOF
  if [ -z "$TARGET" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$PAGES_DIR" 2>/dev/null || true
      pf="$PAGES_DIR/deploy-blocked-$(printf '%.12s' "$TIP_SHA").page"
      { date +%s
        printf 'deploy-live BLOCKED: no GREEN stamp in the newest %s commits of origin/main (tip %.12s)\n' "$SCAN_N" "$TIP_SHA"
        printf 'the live layer is FROZEN until a tree verifies green. stamps=%s verifier=%s\n' "$STAMPS_DIR" "$POSTLAND_BIN"
      } > "$pf" 2>/dev/null || true
      say "wrote page $pf"
    fi
    die "no GREEN stamp among the newest $SCAN_N commits of origin/main — nothing is safe to deploy (verifier: $POSTLAND_BIN)"
  fi
fi

[ -n "$BANNER" ] && UNSTAMPED="$(g rev-list --count "$TARGET..origin/main" 2>/dev/null || echo 0)"

if [ "$TARGET" = "$HEAD_SHA" ]; then
  say "already deployed — live layer is at the newest deployable commit ${HEAD_SHA:0:12} ($UNSTAMPED un-stamped commit(s) above)"
  exit 0
fi
g merge-base --is-ancestor "$HEAD_SHA" "$TARGET" >/dev/null 2>&1 || \
  die "target ${TARGET:0:12} is not a descendant of live HEAD ${HEAD_SHA:0:12} — this would ROLL BACK the live layer"

if [ "$DRY_RUN" -eq 1 ]; then
  [ -n "$BANNER" ] && say "!! $BANNER"
  say "DRY RUN — would fast-forward ${HEAD_SHA:0:12} → ${TARGET:0:12} ($UNSTAMPED un-stamped commit(s) would remain above); nothing mutated"
  exit 0
fi

[ -n "$BANNER" ] && say "!!!!! $BANNER !!!!!"
g merge --ff-only "$TARGET" >/dev/null 2>&1 || die "git merge --ff-only ${TARGET:0:12} FAILED (dirty tree? diverged?) in $DEPLOY_REPO"
say "deployed ${HEAD_SHA:0:12} → ${TARGET:0:12}: $(g log -1 --pretty=%s "$TARGET" 2>/dev/null)"

if [ -x "$DEPLOY_REPO/install.sh" ]; then
  "$DEPLOY_REPO/install.sh" >/dev/null 2>&1 || die "merged ${TARGET:0:12} but install.sh FAILED — re-run $DEPLOY_REPO/install.sh by hand"
  say "install.sh ok (links refreshed)"
else
  die "merged ${TARGET:0:12} but $DEPLOY_REPO/install.sh is missing/not executable — new files are NOT linked"
fi

say "$UNSTAMPED un-stamped commit(s) remain above the live tip (they deploy once verified green)"
exit 0
