# Handoff Back-Channel — can a /handoff-fired peer session ping its originator?

**Date**: 2026-07-10 · **Session**: hbackchan2 (wt-pool-5, fired via /handoff from pane
`w4t0p2:A8867762-9534-46DB-A132-7369F7C05549`) · **Scope**: read-only research + this doc.

## Verdict

**YES — two-way is achievable today with zero harness changes.** The recommended back-channel
is the **same it2 python-API pane injection handoff-fire.sh already uses in its recycle
watcher, run in REVERSE**: the fired session types a message into the *originator's* pane via
`~/.claude/bin/it2 session send -s <uuid> "<text>"` followed by a `$'\r'` submit. Delivered
text lands in the originator's composer as a genuine user message — it **wakes an idle
session** (starts a real turn) and **queues into a busy one** (steered in at the next
tool-result boundary, per the type-asymmetric queue documented at `handoff-fire.sh:320-329`).
It is account/config-dir agnostic (iTerm2 pane UUIDs are machine-global) and detached-proven
(the exact property the recycle/self-close watchers were built on). The only missing piece is
*plumbing*: the originator must hand its pane UUID to the fired session — a ~10-line
`--notify-back` option in `handoff-fire.sh` (spec below). **Live PoC: see § Proof of concept.**

## Why handoff-fire is one-way today (vs Agent Teams two-way)

| Property | Agent Teams (SendMessage) | /handoff fire |
|---|---|---|
| Registry | Shared `$CLAUDE_CONFIG_DIR/teams/<team>/config.json`; every member recorded with `tmuxPaneId` + `agentId` (verified: `~/.claude/teams/session-23fe72e2/config.json`) | **None.** The fired peer is an independent OS process, usually on a *different account/config dir* (`--account auto` walks next2→next3→next4→next, `handoff-fire.sh:354-359`), so it cannot even *see* the originator's `teams/` root |
| Addressing | `SendMessage({to: name})` resolves through the team registry, same harness runtime | The originator's identity is **discarded at fire time** — `FIRING_SID` (`handoff-fire.sh:496`) is used once to anchor the split/tab spawn, then never written anywhere the fired session can read |
| Return path | In-process mailbox; teammate idle/checkpoint hooks close the loop lead-side | The prompt file is the *entire* contract; the fired session's decision gates surface in its own pane |
| Lifecycle | Lead outlives teammates by design | Originator may `self-close`/`--recycle` — its pane is *not guaranteed to exist* later, which is the honest architectural reason fire-and-forget was the default |

So one-way-ness is not a capability gap in the transport — the transport (it2 write into an
arbitrary pane by UUID) is exactly what handoff-fire already does *downward*. It is a missing
**handshake**: nobody passes the return address.

## Mechanism comparison

Ratings: **async→idle** = reaches an idle originator without it polling · **interrupt** = wakes
/ enters the session's turn loop vs passive · **x-account** = survives fired session on a
different account/config dir · **setup** = what the originator must do before going idle.

| Mechanism | async→idle | interrupt | x-account | setup | Verdict |
|---|---|---|---|---|---|
| **it2 pane injection in reverse** (`it2 session send -s <uuid> "msg"` + `send $'\r'`) | ✅ wakes it (real user turn) | ✅ | ✅ (pane UUIDs are global) | pass `$ITERM_SESSION_ID` UUID in the fired prompt | **RECOMMENDED.** Detached-proven python-API path (`handoff-fire.sh:141-145` — detached osascript AppleEvents fail silently; the it2 shim is the reliable one). **Must submit with `\r` not `\n`** — Ink only binds Enter to CR (`handoff-fire.sh:176-178`); `session run`'s auto-newline is `\n`-shaped, fine for a shell, a no-op submit in a CC composer |
| /tmp mailbox + originator background watcher (`run_in_background` Bash polling until the file appears, harness notifies on task exit) | ✅ | ✅ (task-completion notification re-invokes the model) | ✅ (file-based) | originator must arm the watcher BEFORE idling; dies with the session | **Best complement** — survives the originator being at a modal/permission prompt where composer injection could misland. Pair: fired session writes the mailbox *and* injects |
| /tmp mailbox + ScheduleWakeup/Cron poll | ✅ (latency = poll interval) | ✅ on wake | ✅ | originator schedules wakeups; burns cache/quota per tick | Workable but strictly worse than the watcher above |
| Agent Teams `SendMessage` | ✅ | ✅ | ❌ **no** — registry lives under one `$CLAUDE_CONFIG_DIR/teams/`; a peer on another config dir can't resolve it, and the fired session was never a member | would require joining the team (no join API for an already-running foreign session) | Not viable for /handoff peers |
| `Agent` tool (spawn instead of fire) | ✅ | ✅ | n/a (in-process) | n/a | Two-way by construction, but defeats /handoff's purpose (fresh OS-level session, own account/quota/context) |
| `PushNotification` | ✅ to the **human's device** | ❌ (session never sees it) | ✅ | none | Human-awareness only; not session-to-session |
| Notification/Stop hooks on originator | — | — | — | — | Hooks fire on the *own* session's lifecycle; no inbound trigger surface for an external peer. (The background-watcher row above is the practical way to get "hook-like" inbound wake.) |
| osascript `write text` from fired session | ✅ | ✅ | ✅ | same as it2 | Works foreground, but the empirical record (3/3 silent failures detached, `handoff-fire.sh:141-145`) says standardize on the it2 shim |

## The exact handoff-fire.sh change — `--notify-back`

Small and self-contained. `FIRING_SID` is already computed at `handoff-fire.sh:496`; today it
only anchors the spawn. The change forwards it into the fired prompt:

```bash
# 1. New option (arg parser, ~line 284):
#   --notify-back [UUID]   Append a back-channel trailer to the prompt: the fired session is
#                          told the originator's pane UUID + the exact it2 ping recipe.
#                          UUID defaults to the firing pane ($ITERM_SESSION_ID's UUID).
  --notify-back) NOTIFY_BACK="${2:-}"; case "$NOTIFY_BACK" in ""|--*) NOTIFY_BACK="__self__"; shift ;; *) shift 2 ;; esac ;;

# 2. After FIRING_SID is derived (~line 497), materialize the trailer into a COPY of the
#    prompt file (never mutate the caller's file):
if [ -n "${NOTIFY_BACK:-}" ]; then
  BACK_SID="$NOTIFY_BACK"; [ "$BACK_SID" = "__self__" ] && BACK_SID="$FIRING_SID"
  [ -n "$BACK_SID" ] || { echo "!! --notify-back: no \$ITERM_SESSION_ID and no UUID given" >&2; exit 1; }
  PF2="/tmp/handoff-prompt-nb-$$.txt"
  cp "$PROMPT_FILE" "$PF2"
  cat >>"$PF2" <<EOF

## BACK-CHANNEL (originator pane: $BACK_SID)
On completion, decision gates, or blockers, ping the originating session:
  "\$HOME/.claude/bin/it2" session send -s "$BACK_SID" "HANDOFF-PING <slug>: <one-line status>" && \\
  "\$HOME/.claude/bin/it2" session send -s "$BACK_SID" \$'\r'
(\r not \n — CC's Ink composer only submits on CR.) Also append the same line to
/tmp/handoff-mailbox-$BACK_SID.md as the fallback record. If the originator armed a
mailbox watcher, the file write alone wakes it; the injection is the interrupt path.
EOF
  PROMPT_FILE="$PF2"   # before QP="$(printf %q "$PROMPT_FILE")" at line 445
fi
```

Originator-side (optional, for the modal-safe complement): before going idle after a
`--notify-back` fire, arm `Bash(run_in_background)`:
`until [ -s /tmp/handoff-mailbox-<uuid>.md ]; do sleep 15; done` — the harness's
task-completion notification then re-invokes the originator even if composer injection
mislands.

**Failure modes to accept**: originator pane closed/recycled → `it2` exits non-zero, fired
session falls back to the mailbox file (why the trailer mandates both). Originator sitting at
a permission dialog → injected text buffers into the composer and submits into whatever state
holds focus; the mailbox record disambiguates. Neither corrupts state — injection is plain
typed text, identical to the operator typing.

## Proof of concept (live)

Executed from THIS fired session against the originator pane
`A8867762-9534-46DB-A132-7369F7C05549` (verified live in `it2 session list`, tty
`/dev/ttys018`, before firing):

```bash
"$HOME/.claude/bin/it2" session send -s A8867762-9534-46DB-A132-7369F7C05549 "PING FROM hbackchan: …" \
&& "$HOME/.claude/bin/it2" session send -s A8867762-9534-46DB-A132-7369F7C05549 $'\r'
```

Fallback record: `/tmp/hbackchan-ping.txt` (written unconditionally).

**Result**: RECORDED IN FOLLOW-UP COMMIT — the ping cites this commit's sha, so it fires
immediately after this commit lands; the empirical outcome (both it2 exit codes) is appended
here in the next commit.

**Result (recorded post-fire)**: ✅ **SUCCESS** — both it2 calls exited 0 (`send-text rc=0`,
`send-CR rc=0`); the ping line (citing `0412c84a3`) was typed and CR-submitted into the
originator's composer, and `/tmp/hbackchan-ping.txt` holds the identical fallback record.
This is the empirical answer: a /handoff-fired peer on a different account/config dir
(`~/.claude-quaternary` here) reached its originator's session with zero pre-arranged
infrastructure beyond knowing the pane UUID.
