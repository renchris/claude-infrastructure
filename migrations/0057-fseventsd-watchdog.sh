#!/bin/bash
# migration-class: c10
# migration-step: install the root watchdog that restarts fseventsd when its footprint passes 16 GB (2026-10-04: it reached 64 GB, 56 GB of it compressed, filled swap to 40.7 of 42 GB and got every land gate on the machine SIGKILLed by the compressor sentinel). It copies scripts/fseventsd-watch.sh to a root-owned /usr/local/libexec/claude-fseventsd-watch.sh and loads the system LaunchDaemon com.claude.fseventsd-watchdog; macOS asks for an administrator password or Touch ID. A root LaunchDaemon is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0057-fseventsd-watchdog.sh --confirm com.claude.fseventsd-watchdog
# migration-batch-hold: manual — it needs the macOS administrator dialog (osascript with administrator privileges), which the batch's scratch-HOME rehearsal cannot answer or sandbox; run its migration-run line by hand
# migration-subject: launchd/system/com.claude.fseventsd-watchdog.plist
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0057-fseventsd-watchdog.sh" --verify
#
# The verifier is config-dir-INVARIANT: a system LaunchDaemon and a root-owned file give one answer
# from every config dir.
#
# ══ 0057 — the root half of the fseventsd watchdog ══════════════════════════════════════════════════
# WHY (docs/research/concurrency-scale-2026-10-04/a1-capacity-knee.md, c-outcome-ledger.md):
#   fseventsd (pid 317, up 4 days) held a 64 GB footprint with 56 GB compressed. Compressor segments
#   read 66-69% against a 70% alarm (both 09-16 kernel panics had them at 100%), and the sentinel's
#   SIGKILLs turned every /ship red. A manual `sudo kill` (launchd respawns the daemon at once) cut
#   swap to 5.1 of 6 GB. The user-level detector com.claude.fseventsd-watch (a `run` row in
#   launchd/fleet.manifest, loaded by install.sh at converge) sees it and pages, but cannot act:
#   signalling a root daemon needs root.
#
# MODES — re-runnable, every step idempotent:
#   (no args) | --dry-run   print what --confirm would do; change nothing
#   --confirm com.claude.fseventsd-watchdog
#                           copy the watcher to a ROOT-OWNED /usr/local/libexec/claude-fseventsd-watch.sh,
#                           install /Library/LaunchDaemons/com.claude.fseventsd-watchdog.plist, load it
#                           (one administrator dialog), then run --verify
#   --verify                exit 0 iff the daemon is loaded, the copy is root-owned and identical to
#                           the repo script, and the installed plist is identical to the repo plist.
#                           A repo edit to the script makes this fail until it is re-run: a stale
#                           root copy is not the watchdog the repo describes.
#
# WHAT IT CANNOT UNDO BY ITSELF: once loaded, the daemon SIGTERMs (then SIGKILLs) fseventsd when its
#   footprint is >= 16 GB on 2 consecutive 300 s runs, at most every 30 min. Spotlight, Time Machine
#   and file watchers then rescan what they watch. Uninstall:
#     sudo launchctl bootout system/com.claude.fseventsd-watchdog
#     sudo rm /Library/LaunchDaemons/com.claude.fseventsd-watchdog.plist /usr/local/libexec/claude-fseventsd-watch.sh
set -uo pipefail
LABEL=com.claude.fseventsd-watchdog
REPO="${CC_MIGRATION_REPO:-${CC_REPO:-$HOME/Development/claude-infrastructure}}"
SRC="$REPO/scripts/fseventsd-watch.sh"
SRC_PLIST="$REPO/launchd/system/$LABEL.plist"
DST="${FSE_INSTALL_DST:-/usr/local/libexec/claude-fseventsd-watch.sh}"
DST_PLIST="${FSE_INSTALL_DST_PLIST:-/Library/LaunchDaemons/$LABEL.plist}"
STDOUT_LOG=/var/log/claude-fseventsd-watchdog.stdout.log
LAUNCHCTL="${FSE_INSTALL_LAUNCHCTL:-/bin/launchctl}"

MODE=dry; CONFIRM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry; shift ;;
    --verify) MODE=verify; shift ;;
    --confirm) MODE=confirm; CONFIRM="${2:-}"; shift 2 2>/dev/null || shift ;;
    *) echo "usage: $0 [--dry-run | --verify | --confirm $LABEL]" >&2; exit 2 ;;
  esac
done

fail() { echo "0057 FAIL: $*" >&2; exit 1; }

verify() {
  "$LAUNCHCTL" print "system/$LABEL" >/dev/null 2>&1 || { echo "0057: $LABEL is not loaded"; return 1; }
  [ -f "$DST" ] || { echo "0057: $DST is missing"; return 1; }
  [ "$(/usr/bin/stat -f %Su "$DST" 2>/dev/null)" = root ] || { echo "0057: $DST is not root-owned"; return 1; }
  cmp -s "$SRC" "$DST" || { echo "0057: $DST differs from $SRC (re-run --confirm to refresh the root copy)"; return 1; }
  cmp -s "$SRC_PLIST" "$DST_PLIST" || { echo "0057: $DST_PLIST differs from $SRC_PLIST"; return 1; }
  echo "0057: $LABEL loaded; $DST root-owned and current"
  return 0
}

for f in "$SRC" "$SRC_PLIST"; do [ -f "$f" ] || fail "missing $f (has the fix landed and converged into $REPO?)"; done
/usr/bin/plutil -lint "$SRC_PLIST" >/dev/null || fail "$SRC_PLIST does not parse"

case "$MODE" in
  verify) verify; exit $? ;;
  dry)
    if verify >/dev/null; then echo "0057: already installed and current — nothing to do"; exit 0; fi
    echo "0057 (dry run): would copy $SRC -> $DST (root:wheel 755) and $SRC_PLIST -> $DST_PLIST"
    echo "     (root:wheel 644), then launchctl bootout + bootstrap system/$LABEL."
    echo "     Apply with: bash $REPO/migrations/0057-fseventsd-watchdog.sh --confirm $LABEL"
    exit 0 ;;
esac

[ "$CONFIRM" = "$LABEL" ] || fail "--confirm must name the target: --confirm $LABEL"
if verify >/dev/null; then echo "0057: already installed and current — nothing to do"; exit 0; fi

tmpd="$(mktemp -d /tmp/fsew.XXXXXX)" || fail "mktemp"
chmod 700 "$tmpd"
cat > "$tmpd/root.sh" <<EOF
set -e
/bin/mkdir -p /usr/local/libexec
/usr/bin/install -o root -g wheel -m 755 "$SRC" "$DST"
/usr/bin/install -o root -g wheel -m 644 "$SRC_PLIST" "$DST_PLIST"
/bin/launchctl bootout system/$LABEL 2>/dev/null || true
/bin/launchctl bootstrap system "$DST_PLIST"
EOF
/usr/bin/osascript -e "do shell script \"/bin/bash $tmpd/root.sh\" with administrator privileges" >/dev/null \
  || { rm -rf "$tmpd"; fail "administrator step refused or failed (nothing past this point ran)"; }
rm -rf "$tmpd"

echo "== verify (read back, fail closed)"
verify || exit 1
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$STDOUT_LOG" ] && break; sleep 1
done
v="$(grep -o 'verdict=[a-z]*' "$STDOUT_LOG" 2>/dev/null | tail -1)"
[ -n "$v" ] || fail "the daemon loaded but has not written a verdict yet — check /var/log/claude-fseventsd-watchdog.stderr.log"
echo "0057: first run: $v"
tail -1 "$STDOUT_LOG" 2>/dev/null | sed 's/^/   /'
echo "OK: $LABEL installed"
