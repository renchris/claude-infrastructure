#!/bin/bash
# lr-preseed-env.sh — make an autonomous `claude --resume` prompt-free at the SOURCE.
#
# A headless resume (lr-fire-resume.sh / reso-resume-one) drives the Claude TUI through
# `expect`, which controls the PTY. Two startup blockers are NOT in the PTY stream, so
# expect structurally cannot answer them — a human had to click, defeating "no human in
# the loop" (observed 2026-07-11, the ingest prompt stranded behind stacked modals):
#
#   1. iTerm2 GUI modal "A control sequence attempted to clear scrollback history.
#      Allow this?" — Claude's TUI emits CSI 3 J on init; iTerm2 pops an NSAlert SHEET
#      that sits ABOVE the terminal, freezing every keystroke until dismissed. expect's
#      sends go to the PTY, which the sheet never reads. → suppressed at the source with
#      the documented iTerm2 default `PreventEscapeSequenceFromClearingHistory` (iTerm2
#      then silently ignores CSI 3 J — no modal, scrollback preserved). Verified to apply
#      LIVE to an already-running iTerm2 (no restart) and to persist across launches.
#      RACE NOTE: iTerm2 reads the pref via an async cross-process notification. Set it
#      as early as possible (lr-handoff.sh calls this BEFORE opening the pane, and machine
#      setup pre-seeds it — install.sh) so the write predates the resumed TUI by seconds,
#      not milliseconds. On this machine it is already persistently set, so the write here
#      is a guarded no-op.
#
#   2. Claude's "Is this a project you trust?" folder-trust arrow-menu — appears the first
#      time the resumed cwd is opened under the TARGET account. → pre-accepted in that
#      account's ~/.claude*/.claude.json (`hasTrustDialogAccepted`, the field Claude reads),
#      version-agnostic (does not depend on the menu's option order, unlike arrow-key
#      injection). Best-effort suppression of the one-time startup UPSELLS that could also
#      block an unattended resume (overage-credit / notices / remote-control / passes /
#      push) by RAISING their `*SeenCount` gates. Claude keys projects by Node
#      `process.cwd()` (realpath), so the key is `cd "$WT" && pwd -P`.
#
# CONCURRENCY (corrected 2026-07-11): the .claude.json write is guarded by the SAME
# `.claude.json.lock` (proper-lockfile) that Claude itself uses, so it can never CLOBBER a
# concurrent same-account session's newer write (auth/session/MCP/cost state). If the lock
# cannot be taken quickly (a live session is writing), the trust seed is SKIPPED and the
# expect trust-handler answers the prompt instead — degrade to the fallback, never fight
# for the lock. os.replace is atomic, so a partial/corrupt config is impossible.
#
# The fullscreen-renderer upsell + terminal-query escape gibberish stay handled by the
# expect layer in lr-fire-resume.sh (both ARE in the PTY). Idempotent, fail-open.
# Usage: lr-preseed-env.sh <config-dir|account-alias> <worktree>
set -euo pipefail

CFG_IN="${1:?config-dir or account alias}"; WT="${2:?worktree}"

case "$CFG_IN" in
  next|claude-next)     CFG="$HOME/.claude-next" ;;
  next2|claude-next2)   CFG="$HOME/.claude-secondary" ;;
  next3|claude-next3)   CFG="$HOME/.claude-tertiary" ;;
  next4|claude-next4)   CFG="$HOME/.claude-quaternary" ;;
  *)                    CFG="${CFG_IN/#\~/$HOME}" ;;
esac

# ── 1. iTerm2 clear-scrollback modal (global, durable, live-applied) ──────────────────
if command -v defaults >/dev/null 2>&1; then
  cur=$(defaults read com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory 2>/dev/null || echo "")
  case "$cur" in
    1|true|YES) : ;;  # already suppressed (any truthy encoding)
    *) defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool true 2>/dev/null \
         && echo "lr-preseed: iTerm2 clear-scrollback modal suppressed (PreventEscapeSequenceFromClearingHistory=true)" >&2 \
         || true ;;
  esac
fi

# ── 2. Trust pre-accept + upsell suppression in the TARGET account config ─────────────
CJSON="$CFG/.claude.json"
if [[ -f "$CJSON" && -d "$WT" ]]; then
  WT_REAL=$(cd "$WT" && pwd -P)
  python3 - "$CJSON" "$WT_REAL" <<'PY' >&2 || true
import json, os, sys, tempfile, time, errno
cjson, wt = sys.argv[1], sys.argv[2]
lockdir = cjson + ".lock"          # proper-lockfile uses a <file>.lock DIRECTORY
STALE = 15.0                        # steal only a clearly-dead lock (heartbeat is ~5s)

def acquire(timeout=2.0):
    deadline = time.time() + timeout
    while True:
        try:
            os.mkdir(lockdir); return True
        except OSError as e:
            if e.errno != errno.EEXIST:
                return False
            try:
                if time.time() - os.stat(lockdir).st_mtime > STALE:
                    os.rmdir(lockdir); continue   # crashed holder — steal
            except OSError:
                pass
            if time.time() >= deadline:
                return False
            time.sleep(0.15)

if not acquire():
    print("lr-preseed: .claude.json locked by a live session — skipped trust seed "
          "(expect trust-handler will answer the prompt)")
    sys.exit(0)

tmp = None
try:
    with open(cjson) as f:
        raw = f.read()
    d = json.loads(raw)
    indent = 2 if "\n  " in raw[:200] else None   # match Claude's on-disk formatting
    changed = False

    # (a) folder-trust: the ONLY field Claude reads to skip the trust prompt.
    proj = d.setdefault("projects", {}).setdefault(wt, {})
    if proj.get("hasTrustDialogAccepted") is not True:
        proj["hasTrustDialogAccepted"] = True; changed = True

    # (b) best-effort suppression of one-time startup upsells that can render as blocking
    #     select-menus at resume (RAISE the seen-count gates; never lower — idempotent).
    UPSELL_FLOOR = 99
    for key in ("overageCreditUpsellSeenCount", "subscriptionNoticeCount",
                "remoteControlUpsellSeenCount", "passesUpsellSeenCount",
                "pushNotifUpsellSeenCount", "autoPermissionsNotificationCount"):
        v = d.get(key)
        if isinstance(v, int) and v < UPSELL_FLOOR:
            d[key] = UPSELL_FLOOR; changed = True

    if not changed:
        print("lr-preseed: trust + upsell gates already set for %s" % wt)
    else:
        mode = os.stat(cjson).st_mode & 0o777
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cjson), prefix=".claude.json.", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(d, f, indent=indent)
        os.chmod(tmp, mode)                 # preserve original perms (don't leak 0600 from mkstemp)
        os.replace(tmp, cjson)              # atomic
        tmp = None
        print("lr-preseed: folder-trust pre-accepted + upsell gates raised for %s "
              "in %s/.claude.json" % (wt, os.path.basename(os.path.dirname(cjson))))
except Exception as e:
    if tmp:
        try: os.unlink(tmp)
        except Exception: pass
    print("lr-preseed: trust seed skipped (%s) — expect trust-handler will cover it" % e)
finally:
    try: os.rmdir(lockdir)
    except Exception: pass
PY
fi
