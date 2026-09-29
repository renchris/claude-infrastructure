#!/usr/bin/env bash
# public-publish.sh — publish the PUBLIC projection of this repo's history.
#
# WHY A PROJECTION. The working repo keeps its full, unrewritten history (its shas are cited across
# docs, the backlog, decision packets and verifier stamps, and ~90 worktrees hang off it). The
# public repo is a deterministic `git filter-repo` projection of `main`: local-only paths removed,
# personal identifiers replaced, operator addresses in commit metadata mapped to the GitHub noreply
# identity. Design, measurements and rejected alternatives: docs/plans/PUBLIC_REPO_HYGIENE.md.
#
# DETERMINISM IS THE CONTRACT. With the rule set and tool version fixed, re-projecting a LONGER
# history reproduces every earlier projected sha, so each publish is a FAST-FORWARD of the last
# (measured at 6 cut points incl. a pruned tip and the one merge; 0 of 5,799 commit-map rows
# disagreed). `--preserve-commit-hashes` is load-bearing: without it the output depends on emission
# order and the ref set. Any change to the rule set re-projects OLD commits too, so the new tip is
# no longer a descendant of the published one; this script then REFUSES to push unless the run is
# an explicit --rebaseline (a force-push, which is the operator's call, never an agent's).
#
# THE RULE SET IS PRIVATE — it names what it hides. $CC_PRIVATE_DIR/public-projection/ holds:
#   replace-text.txt  filter-repo --replace-text rules (also the land gate's identifier arm)
#   paths-remove.txt  paths removed from ALL history (--invert-paths)
#   mailmap           commit-metadata identities
# config/public-hygiene.conf (tracked) contributes the local-only path globs.
#
# Usage:
#   public-publish.sh [--ref main] [--out DIR] [--public-url URL]           build + verify, no push
#   public-publish.sh ... --push --confirm <owner/repo> [--rebaseline]     also push (operator)
# Options: --src REPO (default: this checkout) · --private-dir DIR · --keep (keep the build dir)
#
# Output (last lines, parseable):
#   verdict=projected tip=<sha> commits=<n> ruleset=<sha12>
#   projection-verifier: 0 identifier hit(s), 0 gitleaks finding(s) over <n> commits   (or FAIL)
#   ff=<yes|stale|no|n-a|unknown> published=<sha|none>
#   verdict=stale-snapshot …   (ff=stale: a newer publish already landed; exits 0, persists nothing)
#   verdict=locked …           (--push while another publish holds the shared lock; exits 0)
# Exit: 0 built+verified (and pushed if asked), stale snapshot, or lock held elsewhere · 1 verification
#       failed · 2 bad args / precondition / published commit unreadable · 3 refused: non-fast-forward
#       without --rebaseline, or push target not confirmed.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SELF_DIR/.." && pwd)"
REF=main
OUT="${TMPDIR:-/tmp}/public-publish.$$"
PRIV="${CC_PRIVATE_DIR:-$HOME/Development/claude-private}"
PUBLIC_URL=""
PUSH=0
CONFIRM=""
REBASELINE=0
KEEP=0
FILTER_REPO="${CC_FILTER_REPO:-git-filter-repo}"
LINT="$SELF_DIR/public-hygiene-lint.py"

die() { echo "public-publish: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="${2:?}"; shift 2 ;;
    --ref) REF="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; KEEP=1; shift 2 ;;
    --private-dir) PRIV="${2:?}"; shift 2 ;;
    --public-url) PUBLIC_URL="${2:?}"; shift 2 ;;
    --push) PUSH=1; shift ;;
    --confirm) CONFIRM="${2:?}"; shift 2 ;;
    --rebaseline) REBASELINE=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

MAP="$PRIV/public-projection/replace-text.txt"
PATHS="$PRIV/public-projection/paths-remove.txt"
MAILMAP="$PRIV/public-projection/mailmap"
CONF="$SRC/config/public-hygiene.conf"
for f in "$MAP" "$MAILMAP" "$CONF"; do [ -r "$f" ] || die "missing rule input: $f"; done
command -v "$FILTER_REPO" >/dev/null || die "git-filter-repo not found"
command -v gitleaks >/dev/null || die "gitleaks not found (the verifier's second arm)"
if [ "$PUSH" = 1 ]; then
  [ -n "$PUBLIC_URL" ] || die "--push needs --public-url"
  # The confirmation must NAME the target; a URL that does not end in it is refused.
  case "$PUBLIC_URL" in
    *"/$CONFIRM"|*"/$CONFIRM.git"|*":$CONFIRM"|*":$CONFIRM.git") [ -n "$CONFIRM" ] || { echo "public-publish: refused — --push requires --confirm <owner/repo>" >&2; exit 3; } ;;
    *) echo "public-publish: refused — --confirm '$CONFIRM' does not name $PUBLIC_URL" >&2; exit 3 ;;
  esac
fi

mkdir -p "$OUT" || die "cannot create $OUT"
LOCK="$PRIV/public-projection/.publish.lock"
LOCK_HELD=0
cleanup() {
  [ "$KEEP" = 1 ] || rm -rf "$OUT"
  if [ "$LOCK_HELD" = 1 ]; then rm -f "$LOCK/owner"; rmdir "$LOCK" 2>/dev/null; fi
}
trap cleanup EXIT
# A signal must reach cleanup too, or a TERM'd publish leaves its lock behind for a live-looking pid.
trap 'exit 143' TERM
trap 'exit 130' INT

# ── ONE publish at a time: the tick and every manual --push share this lock ──────────────────────
# On 2026-09-28 agents hand-published three times beside the launchd tick; a tick that had snapshot
# an OLDER main then found the public tip "not a descendant" and refused with rc=3, the rule-set-
# change message, which sent the next reader after a rule change that never happened. The lock is a
# fixed path beside the rule set, so every caller on the box meets the same one. It holds the pid
# AND that pid's start time: a dead pid, or a live pid that started at another time (reuse), is
# reclaimed; anything else is a publish in progress, and this run steps aside.
proc_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
take_publish_lock() {
  local opid="" ostart="" oat="" stale
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s\n%s\n%s\n' "$$" "$(proc_start $$)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK/owner"
    LOCK_HELD=1
    return 0
  fi
  { read -r opid; read -r ostart; read -r oat; } < "$LOCK/owner" 2>/dev/null
  if [ -z "$opid" ]; then
    # mkdir and the owner write are two steps: an ownerless lock younger than a minute is a holder
    # between them, never a corpse.
    if [ -z "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then return 1; fi
  elif kill -0 "$opid" 2>/dev/null && [ "$(proc_start "$opid")" = "$ostart" ]; then
    echo "public-publish: another publish holds $LOCK (pid $opid, since $oat)" >&2
    return 1
  fi
  # Reclaim by RENAME, which only one reclaimer can win, then prove the renamed lock is the corpse
  # this run inspected (a fresh holder may have taken the path in between).
  stale="$LOCK.stale.$$"
  mv "$LOCK" "$stale" 2>/dev/null || return 1
  if [ "$(head -1 "$stale/owner" 2>/dev/null)" != "$opid" ]; then
    mv "$stale" "$LOCK" 2>/dev/null || true
    return 1
  fi
  echo "public-publish: reclaimed a stale lock (pid ${opid:-none} is gone, taken ${oat:-?})" >&2
  rm -f "$stale/owner"; rmdir "$stale" 2>/dev/null
  take_publish_lock
}
if [ "$PUSH" = 1 ] && ! take_publish_lock; then
  echo "verdict=locked lock=$LOCK"
  exit 0
fi

# ── 1. rule inputs, normalised: filter-repo does NOT skip '#' lines in these files ─────────────
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$MAP" > "$OUT/replace-text.txt"
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$MAILMAP" > "$OUT/mailmap"
{ [ -r "$PATHS" ] && grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$PATHS"
  awk '$1=="path"{print $2}' "$CONF" | grep -v '[*?[]' ; } > "$OUT/paths-exact.txt"
# globbed local-only rows go to filter-repo as glob: path rules
awk '$1=="path" && $2 ~ /[*?[]/ {print "glob:" $2}' "$CONF" > "$OUT/paths-glob.txt"
cat "$OUT/paths-exact.txt" "$OUT/paths-glob.txt" > "$OUT/paths-remove.txt"
RULESET="$( { cat "$OUT/replace-text.txt" "$OUT/mailmap" "$OUT/paths-remove.txt"; "$FILTER_REPO" --version; } | shasum -a 256 | cut -c1-12)"

# ── 2. a main-only clone, then the projection ──────────────────────────────────────────────────
SRC_TIP="$(git -C "$SRC" rev-parse --verify "$REF^{commit}" 2>/dev/null)" || die "no such ref in $SRC: $REF"
git clone -q --no-local --no-hardlinks --bare --single-branch --branch "$REF" "$SRC" "$OUT/proj.git" 2>/dev/null \
  || git clone -q --no-local --no-hardlinks --bare "$SRC" "$OUT/proj.git" || die "clone failed"
git -C "$OUT/proj.git" update-ref "refs/heads/$REF" "$SRC_TIP"
# nothing but the one branch may reach the projection
git -C "$OUT/proj.git" for-each-ref --format='%(refname)' | grep -vx "refs/heads/$REF" \
  | while IFS= read -r r; do git -C "$OUT/proj.git" update-ref -d "$r"; done
( cd "$OUT/proj.git" && "$FILTER_REPO" --force --quiet --preserve-commit-hashes \
    --invert-paths --paths-from-file "$OUT/paths-remove.txt" \
    --replace-text "$OUT/replace-text.txt" --replace-message "$OUT/replace-text.txt" \
    --mailmap "$OUT/mailmap" ) || { echo "public-publish: filter-repo FAILED" >&2; exit 1; }
TIP="$(git -C "$OUT/proj.git" rev-parse "refs/heads/$REF")"
N="$(git -C "$OUT/proj.git" rev-list --count "$TIP")"
cp "$OUT/proj.git/filter-repo/commit-map" "$OUT/commit-map" 2>/dev/null || true
echo "verdict=projected tip=$TIP commits=$N ruleset=$RULESET"

# ── 3. the projection verifier: EVERY blob, message and ident, two independent arms ───────────
LINT_OUT="$(python3 "$LINT" --repo "$OUT/proj.git" --history "$TIP" --conf "$CONF" \
             --map "$MAP" --paths "$OUT/paths-exact.txt" --max-findings 20 2>&1)"; LRC=$?
LHITS="$(printf '%s\n' "$LINT_OUT" | sed -n 's/^public-hygiene-lint: \([0-9]*\) finding.*/\1/p')"
git clone -q --no-local "$OUT/proj.git" "$OUT/proj-wt" 2>/dev/null
GL_CFG="$SRC/.gitleaks.toml"; GL_ARGS=(); [ -r "$GL_CFG" ] && GL_ARGS=(--config "$GL_CFG")
gitleaks git "$OUT/proj-wt" "${GL_ARGS[@]}" --redact --no-banner --log-level error \
  --report-format json --report-path "$OUT/gitleaks.json" >/dev/null 2>&1; GRC=$?
GHITS="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$OUT/gitleaks.json" 2>/dev/null || echo "?")"
if [ "$LRC" -eq 0 ] && [ "$LHITS" = 0 ] && [ "$GHITS" = 0 ] && [ "$GRC" -eq 0 ]; then
  echo "projection-verifier: 0 identifier hit(s), 0 gitleaks finding(s) over $N commits"
  VERIFIED=1
else
  printf '%s\n' "$LINT_OUT" | tail -22 >&2
  [ "$GHITS" != 0 ] && [ -r "$OUT/gitleaks.json" ] && python3 -c 'import json,sys
for f in json.load(open(sys.argv[1]))[:20]: print("GITLEAKS", f["RuleID"], f["File"], f["Commit"][:10])' "$OUT/gitleaks.json" >&2
  echo "projection-verifier: FAIL — lint rc=$LRC hits=${LHITS:-?}; gitleaks rc=$GRC findings=$GHITS"
  VERIFIED=0
fi

# ── 4. fast-forward check against what is already public ──────────────────────────────────────
# ff=yes   the published tip is an ancestor of this projection: an ordinary fast-forward
# ff=stale this projection is an ancestor of the published tip: a snapshot of an OLDER main, and a
#          newer publish has already landed. Nothing to do, and nothing wrong.
# ff=no    neither: real divergence (the rule set changed); only --rebaseline pushes over it
# A published object this clone has never seen is FETCHED before the ancestry test: merge-base
# exits 128 on a missing object, and reading that as "not a descendant" is how a stale snapshot was
# reported as a rule-set change (2026-09-28).
FF=n-a; PUBLISHED=none
if [ -n "$PUBLIC_URL" ]; then
  if PUBLISHED="$(git ls-remote "$PUBLIC_URL" "refs/heads/$REF" 2>/dev/null | cut -f1)" && [ -n "$PUBLISHED" ]; then
    if ! git -C "$OUT/proj.git" cat-file -e "$PUBLISHED^{commit}" 2>/dev/null; then
      git -C "$OUT/proj.git" fetch -q --no-tags "$PUBLIC_URL" "refs/heads/$REF" 2>/dev/null
    fi
    git -C "$OUT/proj.git" cat-file -e "$PUBLISHED^{commit}" 2>/dev/null \
      || { echo "ff=unknown published=$PUBLISHED"; echo "public-publish: cannot read the published commit $PUBLISHED from $PUBLIC_URL — no fast-forward verdict" >&2; exit 2; }
    if git -C "$OUT/proj.git" merge-base --is-ancestor "$PUBLISHED" "$TIP"; then FF=yes
    elif git -C "$OUT/proj.git" merge-base --is-ancestor "$TIP" "$PUBLISHED"; then FF=stale
    else FF=no; fi
  else
    PUBLISHED=none; FF=n-a
  fi
fi
echo "ff=$FF published=$PUBLISHED"
[ "$VERIFIED" = 1 ] || exit 1
if [ "$FF" = stale ]; then
  # Exit BEFORE the commit-map is persisted: an older snapshot's map would overwrite the newer one.
  echo "verdict=stale-snapshot tip=$TIP published=$PUBLISHED"
  exit 0
fi

# persist the commit-map beside the rule set: consumers map a private commit to its public sha
if [ -r "$OUT/commit-map" ] && [ -d "$PRIV/public-projection" ]; then
  cp "$OUT/commit-map" "$PRIV/public-projection/commit-map"
  printf '%s %s %s\n' "$RULESET" "$SRC_TIP" "$TIP" > "$PRIV/public-projection/last-projection"
fi

[ "$PUSH" = 1 ] || exit 0
if [ "$FF" = no ] && [ "$REBASELINE" != 1 ]; then
  echo "public-publish: refused — $TIP is not a descendant of the published $PUBLISHED (the rule set changed?)." >&2
  echo "  Re-publishing over it is a FORCE-PUSH of public history; only an explicit --rebaseline does that." >&2
  exit 3
fi
# Attribution. proj.git is a fresh clone, so init.templatedir fills it with the operator's identity
# gate (githooks/pre-push), and that gate accepts only the PRIVATE address — the identifier the
# mailmap exists to remove — so it refuses every projected commit (the 2026-09-27 cutover: 5814 of
# 5814). What it protects, a commit GitHub credits to the account, holds just as well for the
# account's own noreply address. So the publisher asserts exactly that over the whole projection,
# and only then uses the gate's sanctioned per-repo exemption on this throwaway clone.
OWNER="${CONFIRM%%/*}"
UNATTR="$(git -C "$OUT/proj.git" log --format='%ae%n%ce' "$TIP" | sort -u \
  | grep -viE "^[0-9]+\+${OWNER}@users\.noreply\.github\.com\$" || true)"
if [ -n "$UNATTR" ]; then
  echo "public-publish: refused — the projection carries identities GitHub would not credit to @$OWNER:" >&2
  printf '%s\n' "$UNATTR" | head -10 | sed 's/^/  /' >&2
  echo "  Map each to @$OWNER's noreply address in the private mailmap, then re-run." >&2
  exit 1
fi
git -C "$OUT/proj.git" config cc.identity.exempt \
  "public projection: every author and committer verified as @$OWNER's noreply address"
FORCE=(); [ "$FF" = no ] && FORCE=(--force)
git -C "$OUT/proj.git" push "${FORCE[@]}" "$PUBLIC_URL" "$TIP:refs/heads/$REF" || { echo "public-publish: push FAILED" >&2; exit 1; }
AFTER="$(git ls-remote "$PUBLIC_URL" "refs/heads/$REF" | cut -f1)"
[ "$AFTER" = "$TIP" ] || { echo "public-publish: push verification FAILED — remote reads ${AFTER:-nothing}, want $TIP" >&2; exit 1; }
echo "pushed=$TIP remote=$PUBLIC_URL"
