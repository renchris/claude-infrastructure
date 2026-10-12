# shellcheck shell=bash
# Fixtures for the § 2 parked-loop suites (tests/lr-reset-poller-parked-gates.bats and
# tests/lr-reset-poller-parked-moved-on.bats). Each suite runs ONE poller tick in setup_file over
# several independent sids, so it fits the 300 s off-box bound under load.

parked_env() { # exports the fixture $HOME, stubs and seams; every path under $BATS_FILE_TMPDIR
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_FILE_TMPDIR/home"
  export STATE="$HOME/.reso/limit-recover"
  local stubs="$BATS_FILE_TMPDIR/stubs"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/requests" "$stubs"
  unset CLAUDE_CONFIG_DIR KITTY_WINDOW_ID CC_TERM_KITTY_TO LR_RQ_TEAMMATE_PREDICATE LR_PREDICATE_PY LR_CONFIG_DIRS LR_RQ_BG_HOLDER LR_SUCCESSOR_GATE LR_HUSK_RETIRE
  export LR_EVIDENCE_GC=off
  export CC_REGISTRY_DIR="$BATS_FILE_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HANDOFF_LOG="$BATS_FILE_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  export LR_MOVE_ENV_DIR="$BATS_FILE_TMPDIR/env"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_FILE_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_FILE_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_FILE_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$stubs/osascript"
  printf '#!/bin/bash\ncase " $* " in *" --rank "*) echo none; exit 0 ;; esac\necho %s\n' "'{\"rows\":[{\"acct\":\"next4\",\"session_pct\":12,\"weekly_pct\":40}]}'" > "$HOME/bin/claude-accounts"
  export PGREP_LOG="$BATS_FILE_TMPDIR/pgrep.log"; : > "$PGREP_LOG"
  # shellcheck disable=SC2016  # the stub's OWN $* / $PGREP_LOG expand when the stub runs, not here
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$PGREP_LOG"\nexec /usr/bin/pgrep "$@"\n' > "$stubs/pgrep"
  chmod +x "$stubs/osascript" "$stubs/pgrep" "$HOME/bin/claude-accounts"
  export PATH="$stubs:$PATH"
  export LR_FLEET_BIN="$stubs/lr-fleet" FLEET_LOG="$BATS_FILE_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  # shellcheck disable=SC2016  # expands when the stub runs
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$FLEET_LOG"\nexit 0\n' > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  export LR_BACKLOG_BIN="$stubs/cc-backlog"
  printf '#!/bin/bash\necho 0123456789ab\n' > "$LR_BACKLOG_BIN"; chmod +x "$LR_BACKLOG_BIN"
  : > "$STATE/autorecover.on"
  export SRC="$HOME/.claude-secondary" TGT="$HOME/.claude-quaternary"
  mkdir -p "$SRC/projects/-p" "$TGT/projects/-p"
}

tick() { LR_POLLER_AUTOFIRE=1 bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2 2>/dev/null || true; }
lim_rec() {
  printf '{"type":"assistant","timestamp":"2026-10-10T04:05:55Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets 6am"}]}}\n'
}
# $1=sid — a moved session: .handed-off + /exit stub on the source, a confirm tombstone, the copy
# on the target. The target copy is aged past the 48 h § 1 window so § 1 never scans it: every
# `pgrep resume` counted is § 2's.
husk_disk() {
  lim_rec > "$SRC/projects/-p/$1.jsonl.handed-off"
  printf '{"type":"user","message":{"role":"user","content":"<local-command-stdout>(no content)</local-command-stdout>"}}\n' > "$SRC/projects/-p/$1.jsonl"
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","confirm_len":1}\n' "$TGT" "$TGT" "$1" > "$SRC/projects/-p/$1.HANDOFF.json"
  lim_rec > "$TGT/projects/-p/$1.jsonl"
  touch -t 202609010000 "$TGT/projects/-p/$1.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s","cause":"limit"}\n' "$1" "$SRC" "$TGT" > "$STATE/locks/$1.lock"
}
holder() { # $1=sid $2=pane $3=pid $4=account $5=cfg — a live registry row plus the pid's environment
  printf '{"session_id":"%s","pid":%s,"account":"%s","paneUUID":"%s","cwd":"/x"}\n' "$1" "$3" "$4" "$2" > "$CC_REGISTRY_DIR/$2.json"
  printf '%s' "$5" > "$LR_MOVE_ENV_DIR/$3"
}
park_past() { # $1=sid — a record whose reset has passed, already noted as LEFT PARKED (the live shape)
  printf '{"sid":"%s","acct":"next2","cfg":"%s","cwd":"/x","kind":"weekly","reset_at_utc":"2026-01-01T00:00:00Z","parked_at":"2025-12-31T04:15:46Z"}\n' \
    "$1" "$SRC" > "$STATE/parked/$1.json"
  : > "$STATE/parked/$1.husk-noted"
}
turn_on_target() { # $1=sid $2=timestamp — one content-bearing, non-error assistant turn on the target copy
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"done, live on trunk"}]}}\n' "$2" >> "$TGT/projects/-p/$1.jsonl"
  touch -t 202609010000 "$TGT/projects/-p/$1.jsonl"
}
resume_pgreps() { grep -c "resume $1" "$PGREP_LOG" || true; }
