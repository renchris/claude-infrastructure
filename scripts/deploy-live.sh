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
# `merge --ff-only TARGET` (never origin/main) → run install.sh (idempotent) → POST-DEPLOY HOST
# CHECKS (§4.3) → report the un-stamped commits still queued above the deployed tip.
#
# --auto (LAND_PIPELINE_V2 §4.3) makes the same fail-closed decision AUTONOMOUSLY, on a launchd
# tick every 600s. Three deltas, all of them consequences of running 144×/day unattended:
#   (a) nothing new stamped green (TARGET == live HEAD) ⇒ SILENT exit 0. The steady state must
#       not narrate; a log line per tick is 144/day of "already deployed".
#   (b) a REFUSAL pages at most once per damp window (CC_DEPLOY_DAMP_S, default 24h), keyed on
#       the refusal REASON — subject+state damping, so any change of reason re-pages immediately
#       and a recovery (advance / already-at-target) CLEARS the marker so the next failure is
#       loud again. Undamped, the "no stamps dir" refusal alone is 144 identical pages/day, which
#       is how an operator learns to ignore the channel.
#   (c) --auto is non-interactive BY CONSTRUCTION: it can never be combined with --bootstrap or
#       --force. Those two are the operator's documented escape hatches from the green gate;
#       an unattended job that could take them would silently deploy unverified trees forever.
#
# POST-DEPLOY HOST CHECKS: the suites listed in scripts/host-suites.manifest are the ones whose
# real subject is the LIVE layer (deploy-parity & friends). Running them PRE-deploy is the
# bootstrap circle — they assert a tree that is not deployed yet, so they can never pass, which
# is why 0 green stamps have ever existed. Post-advance they run against their actual subject,
# `nice -n 19` and bounded, from $DEPLOY_REPO. A host RED is a LIVE-LAYER finding: it pages and
# files a backlog packet, and does NOT roll back (this script never rolls back — rolling the live
# layer back is an operator decision) and does NOT change the exit code.
#
# Flags: --dry-run (decide + print, mutate nothing) · --auto (unattended launchd mode) ·
# --bootstrap (stamps dir ABSENT: deploy the tip unstamped, loud banner) · --force (same, with
# stamps present — documented escape hatch).
# Env: DEPLOY_REPO · CC_POSTLAND_DIR · CC_POSTLAND_BIN · CC_PAGES_DIR · CC_DEPLOY_SCAN ·
#      CC_DEPLOY_DAMP_S · CC_HOST_MANIFEST · CC_DEPLOY_HOST_TIMEOUT_S · CC_BACKLOG_BIN ·
#      CC_DEPLOY_BATS_BIN / CC_DEPLOY_TIMEOUT_BIN (UNSET ⇒ resolved; SET-EMPTY ⇒ disabled).
# bash-3.2-safe, no eval, fail-closed, never rolls back.
set -uo pipefail

DEPLOY_REPO="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"
POSTLAND_DIR="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
STAMPS_DIR="$POSTLAND_DIR/stamps"
POSTLAND_BIN="${CC_POSTLAND_BIN:-$DEPLOY_REPO/scripts/postland-verify.sh}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
SCAN_N="${CC_DEPLOY_SCAN:-200}"
DAMP_FILE="$POSTLAND_DIR/deploy-auto.damp"
DAMP_WINDOW_S="${CC_DEPLOY_DAMP_S:-86400}"
MANIFEST="${CC_HOST_MANIFEST:-$DEPLOY_REPO/scripts/host-suites.manifest}"
HOST_TIMEOUT_S="${CC_DEPLOY_HOST_TIMEOUT_S:-300}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"

DRY_RUN=0; BOOTSTRAP=0; FORCE=0; AUTO=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --auto)      AUTO=1 ;;
    --bootstrap) BOOTSTRAP=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)   sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)           printf 'deploy-live: unknown arg %s (use --dry-run|--auto|--bootstrap|--force)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# --auto implies non-interactive: the two gate-bypasses are OPERATOR verbs and an unattended job
# must never be able to take them. Refused at parse time, before anything reads the network.
if [ "$AUTO" -eq 1 ] && { [ "$BOOTSTRAP" -eq 1 ] || [ "$FORCE" -eq 1 ]; }; then
  printf 'deploy-live: --auto cannot be combined with --bootstrap/--force (operator-only gate bypasses)\n' >&2
  exit 2
fi

say()  { printf 'deploy-live: %s\n' "$1"; }
# Under --auto the steady state is silence: only state CHANGES reach the log.
asay() { [ "$AUTO" -eq 1 ] || printf 'deploy-live: %s\n' "$1"; }
die()  { printf 'deploy-live: REFUSED — %s\n' "$1" >&2; exit 1; }
g()    { git -C "$DEPLOY_REPO" "$@"; }

# ── damping: subject+state, sticky only while the STATE holds ────────────────────────────────────
# Returns 0 (emit + re-arm) when the reason CHANGED or the window elapsed; 1 (suppress) otherwise.
# The marker is cleared on every healthy outcome, so recovery→re-failure is loud immediately —
# a window that survives a recovery would swallow the first page of the NEXT outage.
damp_ok() { # <state-key>
  local key="$1" prev_key="" prev_ts=0 now
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ -r "$DAMP_FILE" ]; then
    prev_ts="$(sed -n '1p' "$DAMP_FILE" 2>/dev/null || true)"
    prev_key="$(sed -n '2p' "$DAMP_FILE" 2>/dev/null || true)"
  fi
  case "$prev_ts" in ''|*[!0-9]*) prev_ts=0 ;; esac
  case "$now"     in ''|*[!0-9]*) now=0 ;; esac
  if [ "$prev_key" = "$key" ] && [ "$((now - prev_ts))" -lt "$DAMP_WINDOW_S" ]; then return 1; fi
  mkdir -p "$POSTLAND_DIR" 2>/dev/null || true
  printf '%s\n%s\n' "$now" "$key" > "$DAMP_FILE" 2>/dev/null || true
  return 0
}
damp_clear() { rm -f "$DAMP_FILE" 2>/dev/null || true; }

# ── absolute-path binary resolution (launchd's PATH has no Homebrew — where both of these live) ──
_resolve_bin() { # <name…> → first executable absolute path
  local c n
  for n in "$@"; do
    c="$(command -v "$n" 2>/dev/null || true)"
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    for c in "/opt/homebrew/bin/$n" "/usr/local/bin/$n"; do
      if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    done
  done
  return 1
}
# UNSET ⇒ resolve one. SET (including set to EMPTY) ⇒ honored verbatim, so CC_DEPLOY_TIMEOUT_BIN=
# genuinely disables bounding — `${VAR:-}` cannot tell unset from set-empty, and a seam that
# cannot turn a thing OFF is not a seam.
if [ -n "${CC_DEPLOY_TIMEOUT_BIN+set}" ]; then TIMEOUT_BIN="$CC_DEPLOY_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_bin timeout gtimeout || true)"; fi
if [ -n "${CC_DEPLOY_BATS_BIN+set}" ]; then BATS_BIN="$CC_DEPLOY_BATS_BIN"
else BATS_BIN="$(_resolve_bin bats || true)"; fi

bounded() { # <secs> <cmd…> — rc 124 = OUR bound fired. Unbounded (never blocked) with no timeout(1).
  local secs="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 10 "$secs" "$@"   # no --foreground ⇒ its own process group ⇒ the whole bats tree
}

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

# ── post-deploy HOST checks (§4.3) ───────────────────────────────────────────────────────────────
# The manifest is the corpus PARTITION contract (§4.2, owned by postland-verify): plain text, one
# tests/<name>.bats per line, `#` comments. MISSING manifest ⇒ EMPTY set ⇒ skip silently — the
# verifier's side of the same contract reads a missing manifest as "run everything", so the two
# halves stay total by construction and neither ever needs hand-syncing.
host_checks() { # <deployed-sha> — never blocks, never rolls back, never changes the exit code
  local sha="$1" line s tap rc notok n=0 red="" cut="" pf
  [ -r "$MANIFEST" ] || return 0
  # Build a list (bash 3.2: no mapfile). Suite paths are repo-relative and space-free by contract.
  local SUITES; SUITES=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                                   # trailing / whole-line comment
    line="$(printf '%s' "$line" | tr -d '[:space:]')"    # trim (a path with whitespace is not one)
    [ -n "$line" ] || continue
    SUITES[${#SUITES[@]}]="$line"
  done < "$MANIFEST"
  [ "${#SUITES[@]}" -gt 0 ] || return 0

  if [ -z "$BATS_BIN" ] || [ ! -x "$BATS_BIN" ]; then
    say "host-checks SKIPPED — no bats(1) resolvable (${#SUITES[@]} manifest suite(s) unrun)"
    return 0
  fi
  say "post-deploy host checks: ${#SUITES[@]} suite(s) from ${MANIFEST##*/}, against the LIVE layer"
  for s in "${SUITES[@]}"; do
    if [ ! -f "$DEPLOY_REPO/$s" ]; then say "  skip $s (absent in the deployed tree)"; continue; fi
    n=$((n + 1))
    tap="$( cd "$DEPLOY_REPO" && bounded "$HOST_TIMEOUT_S" nice -n 19 "$BATS_BIN" "$s" 2>&1 )"; rc=$?
    notok="$(printf '%s\n' "$tap" | grep -c '^not ok' 2>/dev/null || true)"
    case "$notok" in ''|*[!0-9]*) notok=0 ;; esac
    # R6: a NAMED failure is the only red. rc alone is blind — bats masks a load-kill behind its
    # own pipefail'd pipeline and exits non-zero naming zero tests. That is CUT: a non-verdict
    # about the machine, never a claim about the tree, and it must never page as a failure.
    if [ "$notok" -gt 0 ]; then      red="$red $s($notok)"; say "  RED  $s — $notok failing"
    elif [ "$rc" -eq 124 ];  then    cut="$cut $s";         say "  CUT  $s — bound ${HOST_TIMEOUT_S}s fired (no verdict)"
    elif [ "$rc" -ne 0 ];    then    cut="$cut $s";         say "  CUT  $s — rc=$rc naming 0 tests (no verdict)"
    else                                                    say "  ok   $s"
    fi
  done
  [ -n "$cut" ] && say "host-checks: non-verdict (cut) suites —$cut"
  [ -n "$red" ] || return 0

  # A live-layer finding, not a deploy blocker: page + backlog, sha-keyed so a repeat tick of the
  # same deployed sha overwrites one page instead of accreting a new one per run.
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  pf="$PAGES_DIR/deploy-host-red-$(printf '%.12s' "$sha").page"
  { date +%s
    printf 'post-deploy HOST RED at %.12s — the LIVE layer is advanced and FAILING host suites\n' "$sha"
    printf 'failing:%s\n' "$red"
    [ -n "$cut" ] && printf 'no-verdict (cut):%s\n' "$cut"
    printf 're-run:  cd %s && bats%s\n' "$DEPLOY_REPO" "$(printf '%s' "$red" | sed 's/([0-9]*)//g')"
    printf 'NOT a rollback trigger: rolling the live layer back is an operator decision.\n'
  } > "$pf" 2>/dev/null || true
  say "host RED —$red · paged $pf (live layer NOT rolled back)"
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-deploy HOST RED:$red @ $(printf '%.12s' "$sha")" \
    --project claude-infrastructure --source deploy-live >/dev/null 2>&1
  return 0
}

g rev-parse --git-dir >/dev/null 2>&1 || die "DEPLOY_REPO is not a git checkout: $DEPLOY_REPO"
g fetch origin main >/dev/null 2>&1 || die "git fetch origin main FAILED in $DEPLOY_REPO (network? remote?)"

HEAD_SHA="$(g rev-parse HEAD 2>/dev/null || true)"
TIP_SHA="$(g rev-parse origin/main 2>/dev/null || true)"
[ -n "$HEAD_SHA" ] && [ -n "$TIP_SHA" ] || die "cannot resolve HEAD / origin/main in $DEPLOY_REPO"

TARGET=""; UNSTAMPED=0; BANNER=""
if [ ! -d "$STAMPS_DIR" ]; then
  # The verification net is not active yet. Deploying is a decision, not a default.
  if [ "$BOOTSTRAP" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    if [ "$AUTO" -eq 1 ]; then
      # Damped: this state persists until an operator runs the activation, i.e. potentially for
      # days at 144 ticks/day. Page once per window; the cc-blockers VERIFIER-INERT alarm is the
      # standing surface (absence-is-loud, R9) — the page is the edge, not the level.
      if damp_ok "no-stamps-dir:$STAMPS_DIR"; then
        mkdir -p "$PAGES_DIR" 2>/dev/null || true
        { date +%s
          printf 'deploy-live BLOCKED: no stamps dir (%s) — the post-land verification net is not active\n' "$STAMPS_DIR"
          printf 'the live layer is FROZEN until the net is activated and a tree verifies green.\n'
          printf 'fix: run docs/activation/pending-activation/14-land-pipeline-v2-activate.sh (CONFIRM=1)\n'
        } > "$PAGES_DIR/deploy-no-stamps.page" 2>/dev/null || true
        die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Run 14-land-pipeline-v2-activate.sh."
      fi
      exit 1   # same refusal, inside the damp window: an honest non-zero, silently
    fi
    die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Re-run with --bootstrap to deploy origin/main UNSTAMPED."
  fi
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
    # Under --auto this refusal is damped on the REASON, not the tip: a moving tip with no green
    # is one persistent state, and keying the page on the tip would mint a fresh page per land.
    if [ "$AUTO" -eq 1 ] && ! damp_ok "no-green:$STAMPS_DIR"; then exit 1; fi
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
  # The healthy steady state: nothing new is stamped green. Silent under --auto, and it CLEARS the
  # damp marker — a later refusal is then a state CHANGE and pages immediately.
  [ "$AUTO" -eq 1 ] && damp_clear
  asay "already deployed — live layer is at the newest deployable commit ${HEAD_SHA:0:12} ($UNSTAMPED un-stamped commit(s) above)"
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
  # install.sh re-globs every per-file-symlink class (hooks/*.sh, hooks/lib/*.sh, commands/*.md,
  # scripts/*.sh, scripts/limit-recover/*, bin/cc-*, skills/*/*, launchd/*.plist) on EVERY run and
  # link_file ln -sf's whatever is missing — so a brand-new tracked file in those classes IS linked
  # by this call. No relink pass is needed here (verified 2026-07-28, install.sh:43-52,89-105,148-155,193-200,256-259).
  say "install.sh ok (links refreshed, incl. any brand-new tracked file)"
else
  die "merged ${TARGET:0:12} but $DEPLOY_REPO/install.sh is missing/not executable — new files are NOT linked"
fi

# The live layer has ADVANCED — only now do the host suites have a real subject to assert.
host_checks "$TARGET"

# A successful advance is a healthy outcome: re-arm the refusal channel.
[ "$AUTO" -eq 1 ] && damp_clear

say "$UNSTAMPED un-stamped commit(s) remain above the live tip (they deploy once verified green)"
exit 0
