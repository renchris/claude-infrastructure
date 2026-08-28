#!/bin/bash
# mailbox-drain.sh — v2 non-keystroke delivery on the RELIABLE boundaries: drain this session's inbox
# and surface it as additionalContext (never keystrokes, never the live input line).
#
#   mailbox-drain.sh session-start   (SessionStart hook)     → additionalContext
#   mailbox-drain.sh prompt          (UserPromptSubmit)      → additionalContext
#   mailbox-drain.sh post-tool       (PostToolUse, v3 D5)    → additionalContext, MID-TURN
#
# The Stop channel is DELIBERATELY not here (critique fix B): in-loop mail delivery is folded into
# session-continue.sh — the ONE hook already blocking the in-loop desk — so there is no competing Stop
# blocker, no 4-hook yield-guards, no wall-clock TTL. Idle mail is caught by the target's armed
# cc-await-ping watcher (seeded from .seen so it never misses a pending line); the cc-inbox-guard is the
# fail-loud backstop. Deliveries here advance ONLY the .seen (emitted) cursor (ack_now=0) — never the
# .acked (consumed) cursor. .acked is promoted one cycle later at the next Stop fold (session-continue.sh
# → mailbox_promote_acked), the moment a turn PROVABLY carried the mail. Dup-biased BY DESIGN: a death
# after drain but before that Stop re-surfaces the mail next boundary (a visible dup) — acking at drain
# would instead have marked it consumed and SILENTLY LOST it on a mid-turn death the guard can't see.
#
# ── MID-TURN BOUNDARY (v3 D5) ─────────────────────────────────────────────────────────────────────
# SessionStart + UserPromptSubmit are RELIABLE but both are session/human-gated: a session in an
# hours-long autonomous turn passes NEITHER, which is R-2 (live forensics: the desk sat on 57 unacked
# pages for 2 h while working). PostToolUse fires on every tool call, so it is the boundary those turns
# actually have. GATED ON A LIVE SMOKE-PROBE, not on the docs — Stop `additionalContext` is documented
# and is nonetheless INERT on the running binary (boundary-handoff.sh:21-22), so a citation proves the
# contract, never the binary. Probe (2026-07-25, CC 2.1.219 + claude-opus-5): a throwaway PostToolUse
# hook emitting a sentinel `additionalContext` was echoed back VERBATIM by the model in a headless
# --print turn. Gate open; recorded in the research doc §4.
#
# Because it rides EVERY tool call it is damped three ways — all cheap, all fail-open:
#   • only-when-pending  (the common case is a 3-file stat and an exit 0)
#   • at most one drain per CC_POSTTOOL_DRAIN_MIN_S (default 20 s — well inside the guard's 60 s urgent
#     deadline, so mid-turn mail still beats its own alarm)
#   • at most CC_POSTTOOL_DRAIN_MAX_LINES (default 20) lines per drain, via mailbox_take_n — the cursor
#     advances by exactly what was shown, so the remainder is deferred, never dropped.
#
# The inbox is ~/.claude/mailbox/<own-pane-uuid>.md; delivery is exactly-once via the split cursor
# (.seen emitted / .acked consumed) under a lock — see hooks/lib/mailbox-pending.sh.
#
# ── HUMAN VISIBILITY (v3 D11) ─────────────────────────────────────────────────────────────────────
# additionalContext reaches the MODEL ONLY — operator-confirmed "you see nothing" when sessions talk
# (U-1). Every drain therefore ALSO emits the universal top-level `systemMessage`, which renders as a
# TUI notice to the human (precedent: session-continue.sh:144 ships one today). Success becomes visible,
# not just failure (U-4). The line names the count and the senders — never the message bodies, which
# stay in the model's context where they belong.
#
# FAIL-SAFE: missing uuid / jq / lib → exit 0 (deliver nothing; the guard backstops). Every path exits 0.
# Env seams (tests): CC_MAILBOX_DIR · ITERM_SESSION_ID · CC_POSTTOOL_DRAIN_MIN_S ·
# CC_POSTTOOL_DRAIN_MAX_LINES · CC_DRAIN_CUSTODY_RETURN (kill switch for the ping-receipt
# discharger) · CC_CUSTODY_DIR (not read here — it reaches bin/cc-custody through the environment,
# and a suite that seeds mail containing HANDOFF-PING should pin it rather than the $HOME it
# defaults under).

MODE="${1:-}"

_scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_lib="$_scd/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
# shellcheck source=lib/mailbox-pending.sh
# shellcheck disable=SC1091
. "$_lib" 2>/dev/null || exit 0

# goal-state lib (LIVE-/goal predicate). The wake-path nag below must never instruct the exact arm
# that DISABLES an armed /goal (CC skips goal evaluation at any Stop with a non-terminal background
# Bash — docs/research/goal-in-handoff-2026-08-08.md). Optional: absent → the nag keeps its
# pre-goal-aware form.
_glib="$_scd/lib/goal-state.sh"
[ -f "$_glib" ] || _glib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/goal-state.sh"
[ -f "$_glib" ] || _glib="$HOME/.claude/hooks/lib/goal-state.sh"
if [ -f "$_glib" ]; then
  # shellcheck source=lib/goal-state.sh
  # shellcheck disable=SC1091
  . "$_glib" 2>/dev/null || true
fi

command -v jq >/dev/null 2>&1 || exit 0

# ── M1 (v2): READ the stdin JSON instead of discarding it ─────────────────────────────────────────
# This used to be `cat >/dev/null` — the hook threw away the harness payload and then keyed the inbox
# on $ITERM_SESSION_ID (the PANE) two lines later. The durable identity was being discarded at the
# exact point the fragile one was chosen; 12 other hooks in this repo parse session_id from this same
# stdin. See docs/plans/CROSS_SESSION_COMMS_V2.md §1.3(a).
# Still fully consumed, so the writer never SIGPIPEs.
_stdin_json="$(cat 2>/dev/null || true)"

own_pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; own_pane="${own_pane##*:}"
own_sid="$(printf '%s' "$_stdin_json" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "$own_sid" in *[!0-9A-Fa-f-]*) own_sid="" ;; esac
own_tp="$(printf '%s' "$_stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# AN ADDRESS IS STILL REQUIRED — it is how this hook knows WHICH container it is in, and the alias
# trail is keyed on it. A missing/path-unsafe address is the one unrecoverable case (exit 0, as
# before). What is NOT required is that the address be hex-shaped: this gate refused
# `hdl-<hex>`, the address `bin/cc-pane-headless:124` mints and `:197` exports as `CC_PANE_ID`, so a
# headless session's drain hook exited here before reading a single mailbox line — mail enqueued,
# cursor never advanced, cc-inbox-guard eventually paging (backlog 4b9d5e93b40a; the writer-side
# copy of this rationale is in hooks/session-register.sh).
#
# Widening THIS gate is what keeps the registration fix honest rather than harmful. Registering a
# headless session without it would make peers resolve it as live and deliverable while it stayed
# structurally deaf — "reported dead" traded for "reported live and silently unreachable", which is
# the worse of the two because nothing looks wrong.
#
# Nothing below needs a headless special case, and that is a property of keying on the address the
# driver already minted rather than re-keying on the harness session id: every use downstream
# (`mailbox_alias_write` :101, the pending checks :134, the cover-pane migrate :165-167, the target
# match :198, `mailbox_adoptable_predecessors` :239) treats this value as an opaque mailbox key, and
# the lib's own `_mbx_valid_uuid` already accepts it. The pane→session alias in particular stays
# meaningful — `hdl-…` and the session id are two genuinely different addresses for one session, so
# the trail maps them exactly as it does for a pane.
case "$own_pane" in
  ''|.|..) exit 0 ;;
  .*) exit 0 ;;
  *[!A-Za-z0-9._-]*) exit 0 ;;
esac

# Record pane→session on EVERY boundary. This is the whole of M1's addressing repair: this hook is the
# one place that sees both identities at once, for every session, so the mapping needs no daemon, no
# registry, and no cooperation from a dying party — and it self-heals, because every boundary
# re-asserts it. Append-only + deduped against the tip (see the lib).
if [ -n "$own_sid" ] && [ "${CC_MBX_SESSION_KEY:-1}" != 0 ] \
   && command -v mailbox_alias_write >/dev/null 2>&1; then
  mailbox_alias_write "$own_pane" "$own_sid" 2>/dev/null || true
fi

# The box we read. Session-keyed when we know our session id (M1), else the pane exactly as before —
# so a harness that stops sending session_id, or the kill switch, degrades to today's behaviour.
if [ -n "$own_sid" ] && [ "${CC_MBX_SESSION_KEY:-1}" != 0 ]; then
  own_uuid="$own_sid"
else
  own_uuid="$own_pane"
fi

MAXLINES=0        # 0 = unlimited (the reliable boundaries take the whole window)
case "$MODE" in
  session-start) EVENT=SessionStart ;;
  prompt)        EVENT=UserPromptSubmit ;;
  post-tool)     EVENT=PostToolUse
                 MAXLINES="${CC_POSTTOOL_DRAIN_MAX_LINES:-20}"
                 case "$MAXLINES" in ''|*[!0-9]*) MAXLINES=20 ;; esac ;;
  *)             exit 0 ;;   # Stop / unknown are not handled here (see fix B)
esac

# ── D5 rate limit — checked BEFORE the take, so a throttled tool call never advances a cursor ────────
# The marker is stamped only when a drain actually HAPPENS (below), not on every tool call: stamping here
# would let a burst of pending-free tool calls hold the floor open and delay the first real delivery.
_mdir="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
if [ "$MODE" = "post-tool" ]; then
  _min="${CC_POSTTOOL_DRAIN_MIN_S:-20}"; case "$_min" in ''|*[!0-9]*) _min=20 ;; esac
  # cheap pre-gate: no pending mail ⇒ the overwhelmingly common path exits without a lock or a take.
  command -v mailbox_has_pending >/dev/null 2>&1 || exit 0
  # COVERAGE, NOT AGREEMENT (2026-08-09) — this pre-gate must span the SAME key space the fold below
  # covers, or it exits before the fold can run. Keyed on the session box alone it returns false for
  # every pane-keyed line, which is 99.4% of live mail: the cheap path became a cheap DROP.
  { mailbox_has_pending "$own_uuid" \
    || { [ "$own_pane" != "$own_uuid" ] && mailbox_has_pending "$own_pane"; }; } || exit 0
  _pt="$_mdir/$own_uuid.posttool"
  if [ -f "$_pt" ] && [ "$_min" -gt 0 ]; then
    _ptm="$(stat -f %m "$_pt" 2>/dev/null || stat -c %Y "$_pt" 2>/dev/null || echo 0)"
    case "$_ptm" in ''|*[!0-9]*) _ptm=0 ;; esac
    _ptnow="$(date +%s 2>/dev/null || echo 0)"
    [ "$(( _ptnow - _ptm ))" -lt "$_min" ] 2>/dev/null && exit 0
  fi
fi

# ── COVERAGE FOLD (2026-08-09) — our OWN pane box, at EVERY boundary, not only SessionStart ──────
# THE DEFECT THIS CLOSES. Every sender resolves a target to a PANE key (a role file, a registry row,
# a raw uuid — all pane-keyed) and none of them calls `mailbox_resolve_key`, so mail lands in
# `<pane>.md`. This hook reads `<session>.md`. The own-pane migrate that reconciles the two lived
# inside the `MODE = session-start` branch below, so a session picked its pane box up **once, at
# birth, and never again** — for its entire life a delivered line was invisible until it restarted.
# Measured this session: 14,763 unacked lines, **99.4% under a pane key**, including 14 addressed to
# the live `orchestrator` role minutes before the census.
#
# WHY READ-SIDE AND NOT A WRITER FIX. The lib's own header already reached this conclusion and it is
# the design inversion of this repair: *"agreement is not the invariant, COVERAGE is."* Making the
# sender resolve is one more place to be wrong, it cannot reach mail already sent, and a write-side
# regression sends mail somewhere NOBODY reads. A read-side fold can only ever make a session hear
# MORE, never less — so it cannot make a live session deaf, which is the one failure mode a fleet-wide
# comms change must not have. It also retroactively drains the existing 14k-line strand.
#
# BOUNDED (R3): one `-f` test and, only when it hits, one migrate of the key WE already own. No
# directory scan, no glob, no alias walk — those stay SessionStart-only below. Runs BEFORE the take so
# the folded lines surface at this same boundary rather than the next one.
# KILL SWITCH: CC_MBX_COVER_PANE=0 → SessionStart-only, i.e. today's behaviour verbatim.
_covered=0
if [ "${CC_MBX_COVER_PANE:-1}" != 0 ] && [ "$own_pane" != "$own_uuid" ] \
   && [ -f "$_mdir/$own_pane.md" ] && command -v mailbox_migrate >/dev/null 2>&1; then
  _covered="$(mailbox_migrate "$own_pane" "$own_uuid" 2>/dev/null || true)"
  case "$_covered" in ''|*[!0-9]*) _covered=0 ;; esac
fi

# LOCKED atomic take on a delivery boundary → advance ONLY .seen (ack_now=0); .acked is promoted at the
# next Stop fold (session-continue.sh → mailbox_promote_acked) once a turn provably consumed the mail.
# Body on stdout; rc 1 = nothing new; rc 2 = delivered-but-.seen-write-failed (still surface the body —
# better a dup next turn than a drop; the re-deliver is bounded and the guard sees the un-advanced .acked).
# take_n's cap advances the cursor by exactly what it printed, so a capped drain defers, never drops.
body="$(mailbox_take_n "$own_uuid" 0 "$MAXLINES")"; rc=$?
[ "$MODE" = "post-tool" ] && [ -n "$body" ] && : > "$_mdir/$own_uuid.posttool" 2>/dev/null

# ── ADOPTION (v3 D1) — SessionStart only: inherit what a predecessor pane never consumed ──────────
# A pane that self-closed with a successor left `<old>.forward` → us. Its inbox may still hold lines
# nobody ever read (live forensics: 631/206/155 stranded in former-desk boxes). Take them ONCE, here,
# where we already hold a boundary that can surface them.
#
# ORDER: own take FIRST (adoption is best-effort; a bug in it must never cost us our OWN mail), then
# migrate, then a SECOND take to surface what just landed AT THIS SAME BOUNDARY. Deferring adopted
# mail to the next boundary would reproduce the exact latency the SLO exists to kill — and the second
# take is free (rc 1 when nothing migrated).
#
# BOUNDED: only *.forward files naming us, one pass, no chain-walking (a chain's intermediate hops are
# resolved by the SENDER; here we adopt only what points directly at us — a multi-hop predecessor is
# adopted by ITS successor, transitively, as each one starts). Every path exits 0.
if [ "$MODE" = "session-start" ] && command -v mailbox_migrate >/dev/null 2>&1; then
  _adopted=0
  for _f in "$_mdir"/*.forward; do
    [ -f "$_f" ] || continue                                   # unmatched glob
    _tgt="$(head -n1 "$_f" 2>/dev/null | tr -dc '0-9A-Fa-f-')"
    # a forward may name our PANE (legacy, pre-M1) or our SESSION (post-M1) — honour both
    { [ "$_tgt" = "$own_uuid" ] || [ "$_tgt" = "$own_pane" ]; } || continue
    _pred="$(basename "$_f" .forward)"
    [ "$_pred" = "$own_uuid" ] && continue                     # paranoia: never adopt from ourselves
    _n="$(mailbox_migrate "$_pred" "$own_uuid" 2>/dev/null || true)"
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    _adopted=$(( _adopted + _n ))
  done

  # ── M4 (v2): PULL-ADOPTION — no `.forward` required ────────────────────────────────────────────
  # The loop above can only ever adopt from a predecessor that COOPERATIVELY wrote a pointer while
  # dying. Measured coverage of that mechanism: 3 of 91 dead-pane boxes = 3.3%. A crash, a 529, a
  # SIGKILL or an OOM writes nothing, so ~96.7% of stranded mail was structurally unreachable.
  #
  # Invert the direction: the SUCCESSOR discovers its predecessor from the pane's own alias trail,
  # which this hook has been maintaining on every boundary. Nothing is owed by the dying party.
  #
  # SAFETY — the guard that makes this legitimate rather than theft: a predecessor is adoptable only
  # if it is not the CURRENT occupant of any pane (mailbox_session_is_current). That is what stops us
  # taking mail from a session that RESUMED ELSEWHERE and is still alive — the case pane-keying could
  # not even represent. Bounded to the N most recent predecessors (R3: no unbounded work in a hook).
  #
  # Also adopts this session's own LEGACY PANE box: mail sent before M1 landed, or by a sender whose
  # resolution fell through to the pane, lands under the pane key. One bounded, idempotent migration.
  if [ "${CC_MBX_PULL_ADOPT:-1}" != 0 ] && [ -n "$own_sid" ] \
     && command -v mailbox_adoptable_predecessors >/dev/null 2>&1; then
    # our own pane box first (cheapest, most common).
    # 2026-08-09: the COVERAGE FOLD above now does this at EVERY boundary, so on the default path this
    # is already drained and migrates 0 — kept because it is idempotent and because it remains the ONLY
    # own-pane migrate when CC_MBX_COVER_PANE=0 (the fold's kill switch must degrade to today's
    # behaviour verbatim, not to no coverage at all).
    if [ "$own_pane" != "$own_uuid" ] && [ -f "$_mdir/$own_pane.md" ]; then
      _n="$(mailbox_migrate "$own_pane" "$own_uuid" 2>/dev/null || true)"
      case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
      _adopted=$(( _adopted + _n ))
    fi
    while IFS= read -r _q; do
      [ -n "$_q" ] || continue
      _n="$(mailbox_migrate "$_q" "$own_uuid" 2>/dev/null || true)"
      case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
      _adopted=$(( _adopted + _n ))
    done <<MBXADOPT
$(mailbox_adoptable_predecessors "$own_pane" "$own_sid" 2>/dev/null || true)
MBXADOPT
  fi

  if [ "$_adopted" -gt 0 ]; then
    # BOUNDED, and the bound is load-bearing (2026-08-16 red-team D2). Until the tip-set fix,
    # adoption never actually completed — the hook was reaped inside mailbox_adoptable_predecessors,
    # so this line effectively never ran. Making adoption work turns it on for ~48% of starts, and
    # an UNBOUNDED take here would dump a whole adopted box into the first turn's context: the
    # largest box on this machine holds 8,294 lines / 2.26 MB (~566K tokens). mailbox_take_n exists
    # for exactly this ("a 600-line box must not be dumped into a tool result") and advances the
    # cursor by precisely what it printed, so the remainder stays undelivered rather than being
    # silently marked seen. Kill switch for the whole adoption path: CC_MBX_PULL_ADOPT=0.
    _more="$(mailbox_take_n "$own_uuid" 0 "${CC_MBX_ADOPT_MAX_LINES:-200}")"  # surface adopted lines NOW
    [ -n "$_more" ] && body="$([ -n "$body" ] && printf '%s\n' "$body"; printf '%s' "$_more")"
  fi
fi

# ── WAKE NUDGE (v3 D4) — the fleet-wide finding: 0 armed watchers across 16 live sessions, and the
# desk sat on 57 unacked pages for 2 h. The harness floor is that NOTHING external can wake an idle
# session — only the model can arm its own watcher. So the one moment we can fix that is HERE, when we
# have the model's attention and can see (by the absence of a fresh `.watching` heartbeat) that it has
# no wake path. Only when actually unwatched — a nudge at an armed boundary would be noise.
# The predicate is the lib's mailbox_wake_armed (SSOT): a marker carrying a DEAD watcher's pid (SIGKILL
# skips cc-await-ping's EXIT cleanup) is not a wake path — nudge the model to re-arm rather than let it
# idle behind a watcher that no longer runs. The lib is sourced at :33 (a missing lib already exited 0).
#
# 🚨 HOISTED ABOVE THE EMPTY-INBOX EXIT (2026-07-26). This block used to sit BELOW
# `[ -n "$body" ] || exit 0`, so the nudge could only ever fire when mail was ALREADY pending — i.e.
# only after a wake had already been missed. A session reaching a boundary with an EMPTY inbox (the
# exact moment before it goes idle, and the only moment at which arming is still cheap) was never told
# to arm at all. That is a mechanical cause of the 0-watcher fleet: the re-arm lived on the
# "message arrived" path instead of the "connection opened" path. The same defect, and the same fix,
# as a WebSocket client that calls subscribe() once after its first connect instead of from its
# on-open handler — it silently stops receiving after the first reconnect. SessionStart is our
# "on open"; UserPromptSubmit is the per-turn re-assert. Self-limiting: it stops the moment a watcher
# is armed.
nudge=""
_watched=0
mailbox_wake_armed "$own_uuid" && _watched=1
# ── HEADLESS: there is no watcher for this session to arm (F7 of
#    docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md) ───────────────────────
# SYMMETRIC WITH hooks/session-continue.sh's wake-floor abstain, and that symmetry is load-bearing:
# tests/wake-floor.bats already pins that these two advisories must not disagree about the arm, and
# a floor that stands down headless while this hook keeps nagging for the same arm re-creates that
# disagreement in a new shape. Both hooks therefore read the SAME predicate, which is
# hooks/session-register.sh:142's — the writer's own env, never the id's shape (that file states in
# terms that reading the surface off an id is "the exact mistake", because only the writer knows it).
#
# WHY SUPPRESS RATHER THAN RE-WORD. A resident `--input-format stream-json` agent's only turn
# boundary is a WRITE TO ITS STDIN, performed by bin/cc-wake-headless against the fifo its spawner
# made — so arming is not merely the wrong command here, it is not this session's job at all. An
# advisory naming no action its recipient can take is pure noise, and at the 150× headless scale
# this substrate is built for it is noise on every prompt of every agent.
#
# NOT the parked-watcher branch below, deliberately: "kill $pid, it is holding your goal inert" IS
# an action a headless agent can take, and it stays.
#
# THE SPEC'S OWN REASON FOR THIS ITEM IS REFUTED AND THE ITEM SURVIVES ANYWAY. F7 says the nag is
# for "a command that cannot run — cc-await-ping exits 3 headless". It does not: bin/cc-await-ping:193
# derives its uuid from `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`, landed 2026-07-31 in 7b7a7e014,
# before the spec was written, and cc-pane-headless:197 exports exactly that variable. The command
# resolves fine. It is still the wrong advice, for the reason above rather than the one filed.
_headless=0
[ -n "${CC_PANE_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ] && _headless=1
# NO-ARG (2026-07-31). This used to interpolate $own_uuid — our SESSION key — while session-continue.sh
# interpolated its own separately-derived key, so the two advisories named DIFFERENT ids for one
# mechanism and a session following either could arm a box nothing writes to. Passing no id at all
# removes the disagreement by construction: cc-await-ping with no argument derives
# ${ITERM_SESSION_ID##*:}, which is the SAME expression cc-notify uses to resolve a target, and it
# then covers that key's whole set (lib → mailbox_keyset). There is no longer an id here to get wrong.
_armcmd="$HOME/.claude/bin/cc-await-ping --timeout ${CC_DRAIN_ARM_TIMEOUT_S:-14400} --interval 15"
# GOAL-AWARE (2026-08-10, docs/research/goal-in-handoff-2026-08-08.md § RESOLUTION). With a LIVE
# /goal, the arm this nag used to instruct is the exact act that disables the goal: a parked
# background Bash makes CC skip /goal evaluation at every Stop, silently. A goal-driven session is
# not deaf unarmed either — an unmet evaluation blocks the stop, so the session keeps taking turns
# and this very hook drains its mail at each boundary. So: warn AGAINST arming instead of for it.
#
# ── FLIPPED FROM "DO NOT ARM" TO "ARM THIS ONE" (2026-08-16, goal-safe-2way-comms §4 C7) ──────────
# The 08-10 text is right about the shape and incomplete about the STATE. It closed the starvation
# pole and left the session in the other one: a lead whose goal's truth lives in its peers' progress
# stays bare, blocks every stop, and re-judges an unchanged world — measured at 90 unmet evaluations
# in 76 minutes, one evaluator call and one forced turn every ~51 s, all carrying no information
# (82% of met goals are met on evaluation #1). Neither pole is idle, and the model cannot invent the
# third mode from a prohibition. `--idle-scoped` IS the third mode, and this hook is one of the
# three places the model is holding the question, so it is where the form gets taught.
#
# WITH THE SID, ALWAYS. The mode's exit condition is this session's turn beat, so an arm that cannot
# name its own sid is refused at the tool (cc-await-ping exit 6) — a nag that instructed the
# unqualified form would be teaching a command that fails. This hook is one of the few surfaces that
# holds both the goal state and the session id at once; where the id is missing (the pane-keyed
# degrade at :101) it says so rather than emitting a form it knows to be incomplete.

# ── E2 (2026-08-15) — THE ARM THAT WAS ALREADY THERE WHEN THE GOAL ARRIVED ────────────────────────
# docs/research/goal-safe-2way-comms-2026-08-13.md §8 E2. The branch above only ever fires when the
# session is UNWATCHED, so it covers the arm that has not happened yet — and misses the one that
# already has. A watcher armed BEFORE `/goal` was typed defers that goal for the rest of its 4-hour
# term, and NOTHING model-facing said so: hooks/goal-inert-watch.sh reports the same condition on
# `systemMessage`, which reaches the operator and never the agent. In the screenshot that opened this
# investigation the session knew only by luck, and it is the measured shape of the starvation pole
# (47 of 84 goal sessions, ZERO evaluations).
#
# This hook is where it belongs: it already sources the goal predicate, already reads the wake
# marker, and already runs at every boundary — so the report costs one extra marker read on a path
# that just did one. It NAMES THE PID and hands over the single act that ends the deferral, because
# "a background task is disabling your goal" is unactionable when the agent cannot see the registry.
#
# SELF-LIMITING, not damped: it stops the moment the watcher is gone, exactly like the arm nudge
# above (whose hoist note argues the case). `post-tool` cannot repeat it per tool call — that mode
# exits at the empty-inbox path below, and its pre-gate exits before the take when nothing is pending.
#
# EXEMPTION: an idle-scoped watcher (B3, §4 C1-C7) is SANCTIONED under a live goal — it stands down
# on any new turn of its own session, so its deferral spans exactly the idle window. It declares
# itself in the marker/claim; mailbox_wake_idle_scoped is the reader, and its absence means "plain",
# which is what every watcher in the fleet is today.
_goal_cond=""
if command -v goal_live_condition >/dev/null 2>&1; then
  _goal_cond="$(goal_live_condition "$own_tp" 2>/dev/null)" || _goal_cond=""
fi
_hdr="🔔 No inbox wake path armed."
if [ -n "$_goal_cond" ]; then
  if [ -n "$own_sid" ]; then
    _idlecmd="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid $own_sid"
  else
    _idlecmd="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid <this session's id>"
  fi
  if [ "$_watched" = 1 ]; then
    _wpid=""
    if command -v mailbox_wake_pid >/dev/null 2>&1 \
       && ! { command -v mailbox_wake_idle_scoped >/dev/null 2>&1 && mailbox_wake_idle_scoped "$own_uuid"; }; then
      _wpid="$(mailbox_wake_pid "$own_uuid" 2>/dev/null || true)"
      case "$_wpid" in ''|*[!0-9]*) _wpid="" ;; esac
    fi
    if [ -n "$_wpid" ]; then
      _hdr="🚨 A parked watcher is holding your LIVE /goal inert."
      nudge="
(pid $_wpid is a cc-await-ping parked in this session's task registry, and a /goal is LIVE (\"$(printf '%s' "$_goal_cond" | cut -c1-120)\"). Claude Code SKIPS /goal evaluation at every Stop where a non-terminal background Bash exists — restoring the hook afterwards, so nothing ever looks wrong — which means that watcher is silently making your goal inert. It was almost certainly armed BEFORE the goal. End the deferral as your next Bash tool call: kill $_wpid
You lose nothing by killing it: the goal blocks your stops, so you keep taking turns and this drain delivers peer mail at every boundary the goal forces. Its death writes a WAKE-PATH-DOWN line into this inbox — that is the designed receipt, not a fault, and the harness will render the kill as 'failed with exit code 143/144'. Detail: docs/research/goal-safe-2way-comms-2026-08-13.md §8 E2.)"
    fi
  else
    [ "$_headless" = 1 ] || nudge="
(a /goal is LIVE, so do NOT park the ordinary 4-hour watcher — Claude Code SKIPS /goal evaluation at any Stop where a non-terminal background Bash exists, and that arm would silently disable the goal driving this session. Peer mail still lands at every turn boundary the goal forces, so while you have work you need no watcher at all. If you have NOTHING actionable and are waiting on an external event, arm the idle-scoped awaiter instead — it stands itself down on your next operator-driven turn (never on your own closing chain of hook-blocked stops), so it defers the goal for exactly as long as you are actually idle: $_idlecmd)"
  fi
else
  [ "$_watched" = 1 ] || [ "$_headless" = 1 ] || nudge="
(no watcher armed — before you go idle, run this as a Bash tool call with run_in_background=true, or peer mail will sit unread until someone types at you: $_armcmd)"
fi

# EMPTY INBOX — nothing to deliver, but this is still a boundary at which we can see the session has
# no wake path. Arming here is the whole point (see the hoist note above), so emit the nudge alone.
# additionalContext only: this fires on every prompt, and a systemMessage per turn would bury the
# operator's own output. With nothing to say we exit silently.
#
# GATED ON THE NUDGE, NOT ON `_watched` (E2, 2026-08-15). This used to exit whenever a watcher was
# armed, on the reasoning that an armed session has nothing to be told — true while the only message
# here was "arm one". E2 added the opposite message: under a live goal an armed watcher is the
# defect, and it is reported at exactly this boundary — the idle one, where the session is about to
# stop and have its goal skipped. Keying the exit on the presence of a message instead of on the
# state that used to imply it keeps every prior path byte-identical (armed + no goal ⇒ empty nudge
# ⇒ exit 0) while letting the new one through.
#
# post-tool (v3 D5) NEVER takes this path: it rides EVERY tool call, so one nudge here would repeat
# tens of times per turn — the exact burial this comment warns about, amplified. The mode's own
# only-when-pending pre-gate (:108) already exits before the take, so this is the local re-assert of
# that invariant rather than a second policy — a lost race on the take must stay silent, not nudge.
if [ -z "$body" ]; then
  [ -z "$nudge" ] && exit 0
  [ "$MODE" = "post-tool" ] && exit 0
  jq -nc --arg e "$EVENT" --arg c "${_hdr}${nudge}" \
    '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
  exit 0
fi

n="$(printf '%s\n' "$body" | grep -c '')"; plural=$([ "$n" = 1 ] && echo message || echo messages)
warn=""; [ "$rc" = 2 ] && warn=' (⚠ cursor write failed — you may see this again; that is a dup, not a loss)'

# A capped (D5) drain leaves a remainder. SAY SO — silence would read as "that was all your mail", which
# is the reading that turns a deferral into a perceived drop. The remainder is still (seen, EOF]; the very
# next boundary takes it. Only the capped mode can leave one, so MAXLINES=0 renders nothing.
rest=""
if [ "$MAXLINES" -gt 0 ] && command -v mailbox_pending_count >/dev/null 2>&1; then
  _left="$(mailbox_pending_count "$own_uuid")"; case "$_left" in ''|*[!0-9]*) _left=0 ;; esac
  [ "$_left" -gt 0 ] && rest="
     (+$_left more pending — capped at $MAXLINES per mid-turn drain; the rest arrives at your next tool boundary. Nothing is lost.)"
fi

# ── W2 CUSTODY — THE PING-RECEIPT DISCHARGER (custody v1.1, item d29b73103189) ──────────────────
# THE GAP THIS CLOSES. bin/cc-custody's own header names this hook as a producer of `return` rows,
# and scripts/handoff-fire.sh:8936 defers a restriction to "custody v1.1 adds the ping-receipt
# discharger" — but no such code existed, so custody v1 had exactly ONE discharge path: a peer that
# reaches `handoff-fire.sh self-close`, which returns by MARKER off its own fired-peer stamp. Every
# peer that finishes its work, pings back, and is then closed by the operator, by a reaper, or by a
# crash left its originator's row OPEN FOREVER — and an open row is 🔧 in wrap-ledger, so the
# originator could never reach ✅ again for that cwd. A ledger that only ever accumulates debt is a
# ledger nobody can act on; it decays into an always-alarm, which is the polarity failure the whole
# close-integrity design is built to avoid.
#
# THE JOIN KEY IS THE SLUG, because it is the only custody field a received ping actually carries:
# handoff-fire arms the back-channel recipe as `cc-notify <originator> "HANDOFF-PING <slug>: …"`
# (:7100) and cloud-return.sh mirrors that shape (`HANDOFF-PING cloud/<id>: …`). The marker is
# never echoed to the peer, so it cannot be read off the wire. cc-custody's open-set derivation
# accepts either (`return <marker-or-slug>`), so slug-keyed discharge needs no store change.
#
# WHY THIS HOOK. The originator is BY CONSTRUCTION the session that receives the ping — the
# back-channel address is the firing pane — and this hook is the one place that sees the ping
# text at all. Nothing is owed by the peer beyond the ping it was already told to send, which is
# what makes this reach the crashed/reaped/operator-closed cases that self-close cannot.
#
# SCOPED TO OUR OWN cwd, deliberately, unlike cloud-return.sh's store-wide `return`. That caller
# holds a MARKER (globally unique) and runs from a cwd that is not the originator's; here the token
# is a SLUG — `basename` of a prompt file (:7087) — which two originators can collide on. A
# store-wide discharge on a collided slug would silently drop a DIFFERENT cwd's custody, and the
# store header is explicit that silently dropping custody is the failure direction to design
# against. The cost of scoping is the converse: an originator that has since RECYCLED INTO A NEW
# WORKTREE keys on a new cwd and its old rows stay open — an over-count, which costs a bounded
# block and is the direction the polarity note already accepts.
#
# IDEMPOTENT + BOUNDED + FAIL-OPEN: a `return` against an already-discharged key is an rc-0 no-op
# (the fold finds no open row), so the dup-biased delivery contract above cannot double-count;
# slugs are deduped and capped at 8 per drain; the whole block is gated on a `grep -q` that the
# overwhelming majority of drains fail; a missing binary, an unreadable store or a malformed line
# all leave the drain exactly as it was. Kill switch: CC_DRAIN_CUSTODY_RETURN=0.
_cust_n=0 _cust_slugs="" _cust_note=""
if [ "${CC_DRAIN_CUSTODY_RETURN:-1}" != 0 ] && printf '%s\n' "$body" | grep -q 'HANDOFF-PING'; then
  _cust_bin=""
  for _c in "$_scd/../bin/cc-custody" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-custody" \
            "$HOME/.claude/bin/cc-custody"; do
    [ -x "$_c" ] && { _cust_bin="$_c"; break; }
  done
  # The hook payload's cwd is the session's own — the same $PWD handoff-fire keyed `open` on. $PWD
  # is the fallback, not the primary: a hook's process cwd is the harness's to choose, and keying
  # custody on it without checking would silently address a different store.
  _cust_cwd="$(printf '%s' "$_stdin_json" | jq -r '.cwd // empty' 2>/dev/null || true)"
  { [ -n "$_cust_cwd" ] && [ -d "$_cust_cwd" ]; } || _cust_cwd="$PWD"
  if [ -n "$_cust_bin" ]; then
    # The slug charset stops at the first `:` and admits `/` for the cloud namespace. Both
    # slug-LESS shapes are excluded by construction rather than by a filter: `HANDOFF-PING:` has no
    # space, and sc_announce_before_retire's `HANDOFF-PING (auto, …)` opens on `(`. Neither carries
    # a join key, and neither needs one — the self-close path they belong to discharges by marker.
    while IFS= read -r _slug; do
      [ -n "$_slug" ] || continue
      # rc is 0 either way BY CONTRACT (an unmatched return must never fail a peer's close path),
      # so the discharge/no-discharge verdict is read off stderr — empty means a row was matched.
      # Any unexpected stderr therefore under-reports the note and never over-reports it.
      if [ -z "$("$_cust_bin" return "$_slug" --cwd "$_cust_cwd" 2>&1 >/dev/null)" ]; then
        _cust_n=$(( _cust_n + 1 ))
        _cust_slugs="${_cust_slugs:+$_cust_slugs, }$_slug"
      fi
    done <<CUSTODYSLUGS
$(printf '%s\n' "$body" \
  | sed -n 's/.*HANDOFF-PING \([A-Za-z0-9][A-Za-z0-9._\/-]*\):.*/\1/p' \
  | awk '!s[$0]++' | head -8)
CUSTODYSLUGS
  fi
fi
[ "$_cust_n" -gt 0 ] && _cust_note="
     (custody: $_cust_n dispatched session(s) DISCHARGED by this ping — $_cust_slugs. Their work is
      reported, not yet collected: land/synthesize it. Still out: cc-custody list --open --cwd .)"

# ── BLOCK RENDERING (operator request 2026-07-28) ───────────────────────────────────────────────
# Peer mail used to arrive as a bare paragraph, visually identical to every other scrap of
# context. Render the bodies as a BLOCK behind a left rule so the channel is unmistakable at a
# glance — and so a model reporting it downstream mirrors that structure instead of inlining it.
# PRESENTATION ONLY: every body line is reproduced verbatim, and the tokens the suites pin
# ("as CONTEXT", "no watcher armed") are preserved.
_block="$(printf '%s\n' "$body" | sed 's/^/  │ /')"
ctx="$(printf '📬 peer mail ◀ %s new %s from other Claude sessions%s\n  ╭─\n%s\n  ╰─ delivered as CONTEXT via the non-keystroke inbox channel — never typed into your input line.\n     Already marked delivered. Triage/act as appropriate; reply to a peer with cc-notify <uuid> "…". This is a message TO you, not something you typed.%s%s%s' \
  "$n" "$plural" "$warn" "$_block" "$rest" "$_cust_note" "$nudge")"
# ── OPERATOR-VISIBLE LINE (2026-07-26) ──────────────────────────────────────────────────────────
# additionalContext is MODEL-ONLY: it reaches the agent and is never rendered in the conversation,
# so until now every inbox delivery was invisible to the human. Operator-reported: "I can't see
# these 2-way communication mailbox pings in the UI so I'm at a loss for visibility" — with 751
# messages crossing the substrate in 12 h, that is a large silent channel. systemMessage IS the
# human lever (the same key hooks/session-continue.sh uses for its cap notice), and BOTH keys are
# legal in one object, so the agent still gets full bodies while the operator gets a digest.
#
# Deliberately a ONE-LINE DIGEST, never the bodies: this fires on every UserPromptSubmit, and
# reprinting messages would bury the operator's own turn. Senders are deduped and capped at 3 so a
# 40-message drain cannot emit a 40-name line. Fixture/lifecycle noise (the non-hermetic suites
# that page REAL pages — HANDOFF-HUSK-PANE / REAPER SURFACE / desk-sweep) is COUNTED but not NAMED,
# so a burst of test traffic can never crowd out one real peer report. Counting rather than hiding
# it matters: "0 peer messages, 12 fixture" is itself the signal that a suite is leaking.
_names="$(printf '%s\n' "$body" \
  | grep -v 'HANDOFF-HUSK-PANE\|REAPER SURFACE\|\[desk-sweep\]' \
  | sed -n 's/^[0-9TZ:+-]* \[\([^]]*\)\].*/\1/p' \
  | awk '!seen[$0]++' | head -3 | paste -sd, - 2>/dev/null)"
_noise="$(printf '%s\n' "$body" | grep -c 'HANDOFF-HUSK-PANE\|REAPER SURFACE\|\[desk-sweep\]' || true)"
case "$_noise" in ''|*[!0-9]*) _noise=0 ;; esac
_sig=$(( n - _noise )); [ "$_sig" -lt 0 ] && _sig=0
if [ "$_sig" -gt 0 ]; then
  msg="📬 peer mail ◀ ${_sig} peer message(s)${_names:+ from ${_names}}"
  [ "$_noise" -gt 0 ] && msg="${msg} · ${_noise} fixture/lifecycle suppressed"
  msg="${msg} — full text: cc-mail"
else
  msg="📬 peer mail ◀ ${n} lifecycle/fixture message(s), no peer traffic — cc-mail --all"
fi
# A custody discharge is a LEDGER state change the operator's close surface reads, so it belongs on
# the human line as well as the model's — appended to whichever digest was built, because a peer's
# return ping can arrive alongside either real peer traffic or none.
if [ "$_cust_n" -gt 0 ]; then
  msg="${msg} · custody −${_cust_n} (returned: ${_cust_slugs})"
fi
jq -nc --arg e "$EVENT" --arg c "$ctx" --arg m "$msg" \
  '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}, systemMessage:$m}'
exit 0
