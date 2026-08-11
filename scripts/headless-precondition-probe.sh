#!/usr/bin/env bash
# headless-precondition-probe.sh — MEASURE (never infer) whether a detached, pty-less Claude Code
# session is a usable fleet substrate.
#
# Phase E of docs/plans/CONCURRENCY_PROGRAM.md asks for panes to become a VIEW attached on demand
# rather than the session's substrate. That is only sound if a session with NO controlling terminal
# still behaves like a fleet citizen. Three things must hold, and this probe measures each rather
# than reading it out of docs:
#
#   P1  it allocates NO pty                     (the resource kern.tty.ptmx_max governs)
#   P2  its hooks still fire                    (SessionStart / UserPromptSubmit / Pre+PostToolUse /
#                                                Stop / SessionEnd — the fleet's whole control plane)
#   P3  cross-session mail still reaches it     (cc-notify's inbox transport + mailbox-drain)
#
# It runs a REAL `claude` binary — the one currently executing, resolved from the running process,
# never a launcher's `--version` (this fleet's indexed `version-identity-is-the-running-process`
# failure). Hooks are supplied through `--settings`, which MERGES with the live settings and
# therefore never registers anything in the live layer.
#
# Cost: a handful of small Haiku turns. Nothing is written outside the work directory.

set -uo pipefail

PROG=${0##*/}
WORK="${CC_HEADLESS_PROBE_DIR:-${TMPDIR:-/tmp}/headless-probe.$$}"
MODEL="${CC_HEADLESS_PROBE_MODEL:-claude-haiku-4-5-20251001}"
KEEP=0
FORMAT=human
TIMEOUT_S="${CC_HEADLESS_PROBE_TIMEOUT_S:-90}"

usage() {
  cat <<EOF
$PROG — measure the headless/detached session precondition for Phase E

  --json          machine-readable verdict object
  --keep          keep the work directory for inspection
  --dir PATH      work directory (default: a fresh mktemp-style dir)
  --timeout N     per-phase timeout seconds (default $TIMEOUT_S)
  -h, --help

Verdicts per predicate: PASS | FAIL | UNKNOWN. UNKNOWN is a real answer and is never
collapsed into either of the others.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    --keep) KEEP=1; shift ;;
    --dir)  WORK="${2:?}"; KEEP=1; shift 2 ;;
    --timeout) TIMEOUT_S="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$WORK" || { echo "$PROG: cannot create $WORK" >&2; exit 2; }
LOG="$WORK/hookfire.log"; : > "$LOG"
: > "$WORK/notes.txt"

note() { printf '%s\n' "$*" >> "$WORK/notes.txt"; }

# shellcheck disable=SC2329  # invoked indirectly by the trap below
cleanup() {
  [ -n "${HP:-}" ] && kill "$HP" 2>/dev/null
  [ "$KEEP" -eq 0 ] && rm -rf "$WORK"
  return 0
}
trap cleanup EXIT INT TERM

# --- resolve the binary that is ACTUALLY running, not a launcher ------------------------------
resolve_claude() {
  local c
  # The running session's own binary is the most honest answer available.
  c=$(ps -axo command= 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++){n=split($i,p,"/"); if(p[n]=="claude" && $i ~ /^\//){print $i; exit}}}')
  if [ -n "$c" ] && [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
  c=$(command -v claude-latest 2>/dev/null) && [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  return 1
}
CLAUDE_BIN="${CC_HEADLESS_PROBE_BIN:-$(resolve_claude || true)}"
if [ -z "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
  echo "$PROG: could not resolve an executable claude binary — refusing to guess" >&2
  exit 2
fi
note "binary: $CLAUDE_BIN"

# Counted off the glob directly: an unmatched glob expands to its own literal, which fails -e,
# so the no-match case is 0 without a pipeline.
pty_count() { local n=0 p; for p in /dev/ttys[0-9][0-9][0-9]; do [ -e "$p" ] && n=$((n+1)); done; printf '%s' "$n"; }

# --- probe settings: one hook per event, each appending its own name ---------------------------
cat > "$WORK/probe-settings.json" <<EOF
{"hooks":{
 "SessionStart":[{"hooks":[{"type":"command","command":"echo SessionStart >> $LOG"}]}],
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo UserPromptSubmit >> $LOG"}]}],
 "PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"echo PreToolUse >> $LOG"}]}],
 "PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"echo PostToolUse >> $LOG"}]}],
 "Stop":[{"hooks":[{"type":"command","command":"echo Stop >> $LOG"}]}],
 "SessionEnd":[{"hooks":[{"type":"command","command":"echo SessionEnd >> $LOG"}]}]
}}
EOF

# ==============================================================================================
# Run a RESIDENT headless session: stream-json in/out, stdin held open on a FIFO.
#
# The FIFO is deliberate. `exec 9> fifo` gives a writable fd we own and can close on our own
# schedule; a process substitution would hand us a pid that names the WRONG job
# (this fleet's indexed `procsub-pid-is-unreachable-own-the-pipe` failure).
# ==============================================================================================
FIFO="$WORK/in.fifo"; rm -f "$FIFO"; mkfifo "$FIFO" || exit 2

PTY_BEFORE=$(pty_count)
SID=$(/usr/bin/uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]')

# `--strict-mcp-config` (eece54939e7f): a precondition probe must measure the CLI, not whatever
# `.mcp.json` sits in the cwd it was launched from. Without it the probe inherits a repo's stdio
# servers — startup latency and RSS that belong to the repo, attributed to the probe — and the
# measurement silently changes with the directory. Same reason this suite unsets terminal-shaped
# env: an unfixtured axis is the one that goes latent.
"$CLAUDE_BIN" -p \
  --strict-mcp-config \
  --settings "$WORK/probe-settings.json" \
  --model "$MODEL" \
  --input-format stream-json --output-format stream-json --verbose \
  ${SID:+--session-id "$SID"} \
  --allowedTools "Bash(echo:*)" \
  < "$FIFO" > "$WORK/stream.out" 2> "$WORK/stream.err" &
HP=$!
exec 9> "$FIFO"

# settle: wait for the process to be up, bounded
i=0
while [ "$i" -lt "$TIMEOUT_S" ]; do
  kill -0 "$HP" 2>/dev/null || break
  [ -s "$WORK/stream.out" ] && break
  i=$((i+1)); sleep 1
done

ALIVE=no; kill -0 "$HP" 2>/dev/null && ALIVE=yes
TTY_OF_PROC=$(ps -o tty= -p "$HP" 2>/dev/null | tr -d ' ')
[ -z "$TTY_OF_PROC" ] && TTY_OF_PROC="(gone)"
PTY_RESIDENT=$(pty_count)
note "resident=$ALIVE tty=$TTY_OF_PROC ptys before=$PTY_BEFORE resident=$PTY_RESIDENT"

# --- P3 setup: drop a message into this session's inbox BEFORE the next turn -------------------
# cc-notify's v2 transport appends to ~/.claude/mailbox/<uuid>.md, which the target's
# mailbox-drain.sh surfaces at its next hook boundary. We write via cc-notify when the session is
# resolvable, and record the verdict token it prints rather than assuming delivery.
MAIL_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
MAIL_TOKEN="HEADLESSPROBE-$$"
MAIL_VERDICT="not-attempted"
MAIL_FILE=""
if [ -n "$SID" ]; then
  MAIL_FILE="$MAIL_DIR/$SID.md"
  if [ -x "$HOME/.claude/bin/cc-notify" ]; then
    MAIL_VERDICT=$("$HOME/.claude/bin/cc-notify" --mailbox-only "$SID" "$MAIL_TOKEN probe mail" 2>&1 \
                     | grep -o 'verdict=[a-z-]*' | head -1)
    MAIL_VERDICT="${MAIL_VERDICT:-no-verdict-token}"
  else
    MAIL_VERDICT="cc-notify-absent"
  fi
fi
note "mail: file=$MAIL_FILE verdict=$MAIL_VERDICT"

# --- drive one real turn that uses a tool (exercises Pre/PostToolUse + Stop) -------------------
#
# The second half of this turn is the load-bearing part of P3. A cursor that advanced proves the
# DRAIN ran; it does not prove the message reached the MODEL — `additionalContext` is injected into
# context and is invisible in the output stream, so "cursor advanced" and "silently discarded" have
# the same signature there. The only un-fakeable test is to ask the model to echo a token that
# exists nowhere but the inbox: if it comes back, delivery happened end to end.
if [ "$ALIVE" = yes ]; then
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Use the Bash tool to run exactly: echo PROBEOK . Then, separately: if you have received ANY peer/inbox message this session, reply with the exact token it contains. If you have received none, reply with the single word NOMAIL."}]}}' >&9
  i=0
  while [ "$i" -lt "$TIMEOUT_S" ]; do
    kill -0 "$HP" 2>/dev/null || break
    grep -q 'PROBEOK' "$WORK/stream.out" 2>/dev/null && grep -q '"type":"result"' "$WORK/stream.out" 2>/dev/null && break
    i=$((i+1)); sleep 1
  done
fi

# Did the token itself come back out of the model? Restricted to assistant/result payloads so a
# hook echoing it into our own log cannot manufacture the answer.
P3_REACHED_MODEL=no
if grep -q "$MAIL_TOKEN" "$WORK/stream.out" 2>/dev/null; then P3_REACHED_MODEL=yes; fi
NOMAIL_SEEN=no
if grep -q 'NOMAIL' "$WORK/stream.out" 2>/dev/null; then NOMAIL_SEEN=yes; fi
note "mail reached model=$P3_REACHED_MODEL nomail_asserted=$NOMAIL_SEEN"
PTY_ACTIVE=$(pty_count)
note "ptys during active turn=$PTY_ACTIVE"

# close stdin → the session should end cleanly and fire SessionEnd
exec 9>&-
i=0
while [ "$i" -lt 20 ]; do kill -0 "$HP" 2>/dev/null || break; i=$((i+1)); sleep 1; done
kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
PTY_AFTER=$(pty_count)

# ==============================================================================================
# Verdicts
# ==============================================================================================
fired() { grep -qx "$1" "$LOG" 2>/dev/null; }

# P1 — no pty. The process's own controlling terminal is the direct read; the census delta is the
# corroborating one. A process reporting `??` has no controlling tty by definition.
if [ "$TTY_OF_PROC" = "??" ]; then
  P1=PASS
elif [ "$TTY_OF_PROC" = "(gone)" ]; then
  P1=UNKNOWN
else
  P1=FAIL
fi
[ "$PTY_RESIDENT" -gt "$PTY_BEFORE" ] && P1=FAIL

# P2 — hooks. SessionStart is the floor; the tool-use pair is the discriminating half, because a
# hook stack that fires only at the edges cannot police what a session DOES.
P2_MISSING=""
for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop SessionEnd; do
  fired "$ev" || P2_MISSING="$P2_MISSING $ev"
done
if [ -z "$P2_MISSING" ]; then P2=PASS
elif fired SessionStart; then P2=PARTIAL
else P2=FAIL
fi

# P3 — mail. Two separable facts: was it ENQUEUED (a file exists carrying the token) and was it
# CONSUMED (the drain advanced its cursor). Enqueue without consumption is a real, distinct state
# and is reported as such rather than rounded to either verdict.
P3_ENQUEUED=no; P3_CONSUMED=unknown
if [ -n "$MAIL_FILE" ] && [ -f "$MAIL_FILE" ] && grep -q "$MAIL_TOKEN" "$MAIL_FILE" 2>/dev/null; then
  P3_ENQUEUED=yes
  if [ -f "$MAIL_DIR/$SID.seen" ]; then
    seen=$(cat "$MAIL_DIR/$SID.seen" 2>/dev/null | tr -dc '0-9')
    lines=$(wc -l < "$MAIL_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$seen" ] && [ -n "$lines" ] && [ "$seen" -ge "$lines" ]; then P3_CONSUMED=yes; else P3_CONSUMED=no; fi
  else
    P3_CONSUMED=no
  fi
fi
# PASS requires the token to have come back OUT of the model. Enqueue+cursor is explicitly NOT
# enough: on the first run of this probe both were true while the token never reached the model,
# which is the vacuous pass this predicate now cannot return.
if   [ "$P3_REACHED_MODEL" = yes ]; then P3=PASS
elif [ "$P3_ENQUEUED" = yes ] && [ "$NOMAIL_SEEN" = yes ]; then P3=FAIL    # positively denied
elif [ "$P3_ENQUEUED" = yes ]; then P3=PARTIAL                            # enqueued, fate unproven
elif [ "$MAIL_VERDICT" = "not-attempted" ] || [ "$MAIL_VERDICT" = "cc-notify-absent" ]; then P3=UNKNOWN
else P3=FAIL
fi

HOOKS_FIRED=$(sort -u "$LOG" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

if [ "$FORMAT" = json ]; then
  printf '{"binary":"%s","resident":"%s","tty":"%s","pty_before":%s,"pty_resident":%s,"pty_active":%s,"pty_after":%s,' \
    "$CLAUDE_BIN" "$ALIVE" "$TTY_OF_PROC" "$PTY_BEFORE" "$PTY_RESIDENT" "$PTY_ACTIVE" "$PTY_AFTER"
  printf '"P1_no_pty":"%s","P2_hooks":"%s","P2_missing":"%s","P3_mail":"%s","P3_enqueued":"%s","P3_consumed":"%s","P3_reached_model":"%s","mail_verdict":"%s","hooks_fired":"%s"}\n' \
    "$P1" "$P2" "${P2_MISSING# }" "$P3" "$P3_ENQUEUED" "$P3_CONSUMED" "$P3_REACHED_MODEL" "$MAIL_VERDICT" "$HOOKS_FIRED"
else
  echo "── headless precondition ──────────────────────────────────────────"
  printf 'binary        %s\n' "$CLAUDE_BIN"
  printf 'resident      %s   controlling tty: %s\n' "$ALIVE" "$TTY_OF_PROC"
  printf 'ptys          before=%s resident=%s active=%s after=%s\n' "$PTY_BEFORE" "$PTY_RESIDENT" "$PTY_ACTIVE" "$PTY_AFTER"
  printf 'P1 no-pty     %s\n' "$P1"
  printf 'P2 hooks      %s   fired: %s\n' "$P2" "${HOOKS_FIRED:-none}"
  [ -n "$P2_MISSING" ] && printf '              missing:%s\n' "$P2_MISSING"
  printf 'P3 mail       %s   enqueued=%s cursor-advanced=%s reached-model=%s (%s)\n' "$P3" "$P3_ENQUEUED" "$P3_CONSUMED" "$P3_REACHED_MODEL" "$MAIL_VERDICT"
  [ "$KEEP" -eq 1 ] && printf 'work dir      %s\n' "$WORK"
fi

# Exit 0 unless a predicate came back FAIL — UNKNOWN/PARTIAL are reportable states, not errors.
case "$P1$P2$P3" in *FAIL*) exit 1 ;; esac
exit 0
