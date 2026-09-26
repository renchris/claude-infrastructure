#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 46-public-repo-cutover — keep github.com/renchris/claude-infrastructure PUBLIC, with a clean history
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHAT (docs/plans/PUBLIC_REPO_HYGIENE.md § Phase B):
#   1. back up EVERY local ref to a git bundle, and verify it
#   2. build + verify the public projection FIRST (0 identifier hits, 0 gitleaks findings, all history)
#   3. disable Actions on the current repo (it is about to be private: macOS minutes would bill)
#   4. rename  renchris/claude-infrastructure → renchris/claude-infrastructure-private (full history)
#   5. point this machine's `origin` at the private repo; keep the old URL as git config
#      cc.canonicalUrl (DoD store + project label identity) and set cc.publicRepo
#   6. make the renamed repo PRIVATE
#   7. create a new PUBLIC renchris/claude-infrastructure and push the projection to it
#   8. enable the recurring publisher (com.claude.public-publish: fast-forward pushes only)
#   9. self-verifying post-check: visibilities, a FRESH clone of the public repo scanned over all
#      history, the private origin still serving this machine's main
#
# WHAT IT CANNOT UNDO: the rename breaks the old URL's redirect the moment step 7 creates the new
#   repo; the visibility flip ERASES the 2 stars and DETACHES the 1 fork (which stays public with
#   the 305 commits it already copied — nothing recalls those). The working history, every sha,
#   every worktree and every cited commit are untouched: nothing here rewrites the working repo.
#
# RUN:   bash <this> --confirm renchris/claude-infrastructure      (without --confirm: dry run)
# Safe to re-run: every step checks its own end state first and skips when already there.
# Exit: 0 done (or dry run clean) · 1 a step failed (state printed) · 2 refused (preflight/confirm)
set -uo pipefail

OWNER=renchris
NAME=claude-infrastructure
PRIVATE_NAME=claude-infrastructure-private
TARGET="$OWNER/$NAME"
REPO="${CC_CUTOVER_REPO:-$HOME/Development/claude-infrastructure}"
PRIV="${CC_PRIVATE_DIR:-$HOME/Development/claude-private}"
BACKUP_DIR="${CC_CUTOVER_BACKUP_DIR:-$HOME/Backups/claude-infrastructure}"
WORK="${TMPDIR:-/tmp}/public-cutover.$$"
PUB="$REPO/scripts/public-publish.sh"
LINT="$REPO/scripts/public-hygiene-lint.py"
LABEL=com.claude.public-publish
CONFIRM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    --dry-run) CONFIRM=""; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
say()  { printf '%s\n' "── $*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }
refuse() { printf '✗ REFUSED: %s\n' "$*" >&2; exit 2; }
# A renamed repo keeps answering at its OLD name (GitHub redirects), so "exists" means the API's
# canonical full_name IS the name asked for — never merely that the call succeeded.
repo_exists() {
  local fn; fn="$(gh api "repos/$1" --jq .full_name 2>/dev/null)" || return 1
  [ "$(printf '%s' "$fn" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ]
}
visibility() { repo_exists "$1" && gh api "repos/$1" --jq .visibility 2>/dev/null; }
mkdir -p "$WORK" || refuse "cannot create $WORK"

# ── preflight (read-only) ─────────────────────────────────────────────────────────────────────
say "preflight"
for t in gh git git-filter-repo gitleaks python3 jq; do command -v "$t" >/dev/null || refuse "missing tool: $t"; done
gh auth status >/dev/null 2>&1 || refuse "gh is not authenticated (gh auth login)"
[ -x "$PUB" ] && [ -r "$LINT" ] || refuse "publisher not deployed in $REPO (land docs/plans/PUBLIC_REPO_HYGIENE.md first)"
for f in replace-text.txt mailmap; do [ -r "$PRIV/public-projection/$f" ] || refuse "private rule file missing: $PRIV/public-projection/$f"; done
# the RAW configured string (get-url would expand url.insteadOf) — it is what the DoD key hashes
ORIGIN_URL="$(git -C "$REPO" config --get remote.origin.url)" || refuse "no origin in $REPO"
case "$ORIGIN_URL" in
  *"github.com/$OWNER/$NAME"|*"github.com/$OWNER/$NAME.git"|*"github.com:$OWNER/$NAME.git") STAGE=before ;;
  *"github.com/$OWNER/$PRIVATE_NAME"|*"github.com/$OWNER/$PRIVATE_NAME.git") STAGE=after-seturl ;;
  *) refuse "origin is $ORIGIN_URL — neither the public nor the private repo" ;;
esac
say "origin: $ORIGIN_URL (stage: $STAGE)"
git -C "$REPO" fetch -q origin main || refuse "cannot fetch origin main"

# ── 1. backup every ref ───────────────────────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR" || refuse "cannot create $BACKUP_DIR"
BUNDLE="$BACKUP_DIR/all-refs-$(date -u +%Y%m%dT%H%M%SZ).bundle"
say "1. backup: git bundle of every local ref → $BUNDLE"
git -C "$REPO" bundle create -q "$BUNDLE" --all 2>/dev/null || fail "bundle create failed"
git -C "$REPO" bundle verify -q "$BUNDLE" >/dev/null 2>&1 || fail "bundle verify FAILED — refusing to touch GitHub"
say "   verified ($(du -h "$BUNDLE" | cut -f1))"

# ── 2. build + verify the projection BEFORE anything outward ─────────────────────────────────
say "2. projection build + verify (all history)"
bash "$PUB" --src "$REPO" --ref main --out "$WORK/build" --keep > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log" >&2; fail "projection did not verify — nothing outward has been done"; }
grep -E '^(verdict=|projection-verifier:)' "$WORK/build.log"

if [ "$CONFIRM" != "$TARGET" ]; then
  say "DRY RUN — preflight, backup and a verified projection are done; nothing on GitHub was touched."
  say "To execute: bash $0 --confirm $TARGET"
  exit 0
fi

# ── 3-6. move the working repo to a PRIVATE origin ────────────────────────────────────────────
if repo_exists "$OWNER/$PRIVATE_NAME"; then
  say "3-4. $OWNER/$PRIVATE_NAME already exists — rename already done"
else
  [ "$(visibility "$TARGET")" = public ] || fail "$TARGET is not the public repo it should be (visibility: $(visibility "$TARGET"))"
  say "3. disable Actions on $TARGET (private macOS minutes would bill)"
  gh api -X PUT "repos/$TARGET/actions/permissions" -F enabled=false >/dev/null || fail "could not disable Actions"
  say "4. rename $TARGET → $OWNER/$PRIVATE_NAME"
  gh repo rename "$PRIVATE_NAME" --repo "$TARGET" --yes >/dev/null || fail "rename failed"
  repo_exists "$OWNER/$PRIVATE_NAME" || fail "renamed repo not visible"
fi
say "5. origin → private repo (identity kept as cc.canonicalUrl)"
if [ -z "$(git -C "$REPO" config --get cc.canonicalUrl 2>/dev/null)" ]; then
  git -C "$REPO" config cc.canonicalUrl "$ORIGIN_URL"
fi
git -C "$REPO" remote set-url origin "https://github.com/$OWNER/$PRIVATE_NAME.git"
git -C "$REPO" config cc.publicRepo "$TARGET"
[ "$(git -C "$REPO" ls-remote origin refs/heads/main | cut -f1)" = "$(git -C "$REPO" rev-parse origin/main)" ] \
  || fail "the private origin does not serve this machine's origin/main"
if [ "$(visibility "$OWNER/$PRIVATE_NAME")" != private ]; then
  say "6. make $OWNER/$PRIVATE_NAME PRIVATE"
  gh repo edit "$OWNER/$PRIVATE_NAME" --visibility private --accept-visibility-change-consequences >/dev/null \
    || fail "visibility change failed"
fi
[ "$(visibility "$OWNER/$PRIVATE_NAME")" = private ] || fail "$OWNER/$PRIVATE_NAME is not private"

# ── 7. the PUBLIC repo at the original name ───────────────────────────────────────────────────
if ! repo_exists "$TARGET"; then
  say "7. create PUBLIC $TARGET"
  gh repo create "$TARGET" --public \
    --description "Claude Code infrastructure: hooks, skills, agents and tooling (public projection)" >/dev/null \
    || fail "create failed"
fi
[ "$(visibility "$TARGET")" = public ] || fail "$TARGET is not public"
say "7. publish the projection to $TARGET (fast-forward only)"
bash "$PUB" --src "$REPO" --ref main --public-url "https://github.com/$TARGET.git" \
  --push --confirm "$TARGET" > "$WORK/publish.log" 2>&1 || { tail -20 "$WORK/publish.log" >&2; fail "publish failed"; }
grep -E '^(verdict=|projection-verifier:|ff=|pushed=)' "$WORK/publish.log"
PUBLISHED="$(sed -n 's/^pushed=\([0-9a-f]*\).*/\1/p' "$WORK/publish.log")"

# ── 8. the recurring publisher ────────────────────────────────────────────────────────────────
say "8. enable $LABEL"
mkdir -p "$PRIV/public-projection" && touch "$PRIV/public-projection/publish-enabled"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
[ -f "$PLIST" ] || cp "$REPO/launchd/$LABEL.plist" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || fail "$LABEL is not loaded"

# ── 9. post-check, by independent reads ───────────────────────────────────────────────────────
say "9. post-check"
[ "$(visibility "$OWNER/$PRIVATE_NAME")" = private ] || fail "private repo is not private"
[ "$(visibility "$TARGET")" = public ] || fail "public repo is not public"
git clone -q --bare "https://github.com/$TARGET.git" "$WORK/fresh.git" || fail "cannot clone the public repo"
[ "$(git -C "$WORK/fresh.git" rev-parse main)" = "$PUBLISHED" ] || fail "public main is not the published tip"
python3 "$LINT" --repo "$WORK/fresh.git" --history main --conf "$REPO/config/public-hygiene.conf" \
  --max-findings 10 > "$WORK/fresh-lint.log" 2>&1 || { cat "$WORK/fresh-lint.log" >&2; fail "the PUBLIC repo's history has findings"; }
tail -1 "$WORK/fresh-lint.log"
[ "$(git -C "$REPO" ls-remote origin refs/heads/main | cut -f1)" = "$(git -C "$REPO" rev-parse origin/main)" ] \
  || fail "private origin no longer serves origin/main"
say "verdict=CUTOVER-OK public=$TARGET@${PUBLISHED:0:12} private=$OWNER/$PRIVATE_NAME backup=$BUNDLE"
say "The fork zeroxvee/claude-infrastructure keeps what it copied (305 commits); only its owner or"
say "GitHub Support (https://support.github.com/request) can remove it."
rm -rf "$WORK"
