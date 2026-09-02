#!/usr/bin/env bash
# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
#
# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
# one loops on the wrong things (that's why the Session Close Protocol banned it).
# This design keeps scope-judgment with the AGENT: the agent (which classifies each
# close as 🔧 / ✅ / 📦 / ⛔ / 📤) ARMS a sentinel ONLY on 🔧, and this script is a
# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
# loop cap so a stuck gate can never run away.
#
# Agent interface (run from the session's worktree):
#   session-continue.sh set "<the ONE next step>"   # arm — ONLY on the 🔧 state
#   session-continue.sh clear                        # disarm — on ✅/📦/⛔/📤, read-only, or "...and stop"
#   session-continue.sh status                       # inspect
#
# Claude Code calls it with NO args + the Stop JSON on stdin → actuation mode.
#
# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
# keyed by config-dir + cwd hash, so it never gets committed and concurrent sessions —
# including different accounts (each with its own CLAUDE_CONFIG_DIR) — don't collide.
#
# HARDENING (a19 D-7/D-8, a17 S-12) beyond the base actuator:
#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
#       "…and stop" / "no auto-continue" / "just do X" / explicit-pause phrase clears the sentinel
#       and allows the stop. Operator stop ALWAYS wins over a stale sentinel (was D-8: the actuator
#       parsed no phrase, so a stale sentinel forced work when told to stop).
#   (b) SID-BIND — `set` records the arming session's id in a `.sid` sidecar; actuation clears AND
#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-succession
#       inheritance: a recycled successor in the same cwd inheriting the predecessor's sentinel).
#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
#       (that reset is how a faithful long grind avoids the cap — D-7). At the cap the hook does NOT
#       give up silently: it emits a final systemMessage naming the re-arm lever, then allows the stop.
#
# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
# accidental non-zero exit could force a false continuation. Every actuation path ends `exit 0`.

# ── Shared sentinel-path SSOT (G-P6-6b / a19 I-1) ─────────────────────────────────
# The sentinel PATH formula lives in hooks/lib/continue-sentinel.sh so boundary-handoff's
# compose-guard computes the IDENTICAL path (it used to hardcode a path this hook never writes →
# a dead no-op guard). Resolve the lib next to this script (works for the repo AND a symlinked
# ~/.claude/hooks/ install), then fall back to the config-dir / ~/.claude hooks/lib.

# ── B-3 telemetry — one IDL record + one log line per DECISION (audit 09 D-11) ────────────────
# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
# times per chain, and it was the ONLY Stop hook writing nothing at all (completion-assert,
# boundary-handoff and anti-deference-nudge all write IDL), so a runaway continuation or a wrongly
# SUPPRESSED one was forensically invisible. Record shape + jq-encoding of every field mirrors
# hooks/completion-assert.sh:39-49 — a step string carrying a quote/newline must never emit a
# malformed IDL line, because one malformed line aborts cc-audit's `jq -rs` slurp and that reads
# as "no records" (silently flipping the un-gameable detector green).
#
# Deliberately NOT logged: the disarmed steady state (actuation with no sentinel). That is the
# common case on EVERY Stop of EVERY session, and the sentinel's absence is itself the record —
# logging it would add a line per turn-close to an already-18 MB IDL while telling us nothing the
# D-11 forensics need. Every state CHANGE is logged: armed · cleared (cli / kill-switch /
# sid-mismatch / cap) · fired.
IDL="${CONTINUE_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
CLOG="${CONTINUE_LOG:-$HOME/.claude/logs/session-continue.log}"
SC_SID="?"
log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
  local ts extra
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  mkdir -p "${IDL%/*}" "${CLOG%/*}" 2>/dev/null || true
  printf '[%s] %s sid=%s reason=%s\n' "$ts" "$1" "$SC_SID" "$2" >> "$CLOG" 2>/dev/null || true
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --arg ts "$ts" --arg sid "$SC_SID" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"session-continue",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}

_scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_lib="$_scd/lib/continue-sentinel.sh"
[ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/continue-sentinel.sh"
[ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
# shellcheck source=lib/continue-sentinel.sh
# shellcheck disable=SC1091  # source path resolved at runtime (fallback chain); static-follow needs -x, the
# ship-land gate runs shellcheck without it → SC1091(info) would red a change to this file (matches boundary-handoff.sh)
if ! . "$_lib" 2>/dev/null; then
  # Fail LOUD but SAFE: a missing path-SSOT is a misconfig, not a runtime state. A Stop hook must
  # never block on error (→ exit 0 allow); a CLI mode signals the failure to the agent (→ exit 2).
  printf 'session-continue: FATAL — cannot source %s (continuation loop inert).\n' "$_lib" >&2
  log_idl abstained "no-sentinel-lib"
  case "${1:-}" in set|clear|status) exit 2 ;; *) exit 0 ;; esac
fi
mkdir -p "$(continue_state_dir)" 2>/dev/null

# thin local alias → the shared SSOT (keeps the body below unchanged)
sentinel_for() { continue_sentinel_for "$1"; }

# ---- Agent CLI mode -------------------------------------------------------------
case "${1:-}" in
  set)
    f=$(sentinel_for "$PWD")
    printf '%s' "${2:-Continue the in-scope work.}" > "$f"
    rm -f "${f}.count" 2>/dev/null   # fresh chain → reset the loop counter (D-7 re-arm lever)
    # (b) sid-bind: stamp the arming session so a same-cwd successor can't inherit this sentinel.
    # Empty sid ⇒ write no bind (actuation then skips the sid check — conservative, never a wrong clear).
    csid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
    if [ -n "$csid" ]; then printf '%s' "$csid" > "${f}.sid"; else rm -f "${f}.sid" 2>/dev/null; fi
    # cwd-stamp: the sentinel NAME is a hash of (config-dir|cwd), so nothing can invert it back to a
    # directory. Without this sidecar, a `clear` run from the wrong worktree can say "an armed
    # sentinel exists for this sid" but never say WHERE — which is the actionable half. One line at
    # arm time is what makes the cross-cwd answer below nameable.
    printf '%s' "$PWD" > "${f}.cwd" 2>/dev/null || true
    echo "armed → $f"
    SC_SID="${csid:-?}"
    log_idl armed "cli-set" "$(jq -cn --arg s "${2:-Continue the in-scope work.}" --arg c "$PWD" \
      '{step:$s,cwd:$c}' 2>/dev/null)"
    exit 0 ;;
  clear)
    f=$(sentinel_for "$PWD")
    # DID IT ACTUALLY DISARM ANYTHING? The sentinel is $PWD-KEYED, and `rm -f` on an absent file
    # exits 0 — so the verb used to print "cleared" whether it disarmed a live chain or looked in the
    # wrong directory and touched nothing (claimed-outcome ≠ checked-outcome). MEASURED 2026-08-11
    # (session a28e8b9c): armed from the main checkout, cleared from a worktree, got "cleared", and
    # the next Stop replayed the same step — `status` read ARMED at the checkout and inactive in the
    # worktree, with nothing in between to say so. Sample BEFORE the rm; report what the rm did.
    was_armed=0; [ -f "$f" ] && was_armed=1
    rm -f "$f" "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
    # `clear` means "this dirt is deliberate — stop asking", which is exactly what the mechanical
    # arm's own block message instructs. So SPEND its budget rather than deleting it: deleting would
    # let the next Stop re-arm and re-block, making clear/re-arm a two-cycle the operator cannot
    # exit. Marking it spent is the difference between an off switch and a snooze button.
    # UNCONDITIONAL on purpose: the mech budget is a property of THIS cwd (where the mechanical arm
    # would fire), not of whether an agent-set sentinel happened to be armed here.
    SC_SID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-?}}"
    printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3}" > "${f}.mech" 2>/dev/null || true
    if [ "$was_armed" = 1 ]; then
      echo "cleared → $f"
    else
      # NOT AN ERROR, and NOT a failure exit (rc stays 0): clearing where nothing is armed is the
      # normal shape of a deliberate park. What was missing is the fact, and the cwd it was true of.
      echo "nothing to clear — no sentinel was armed for this cwd: $PWD"
      # A cross-cwd clear is ANSWERABLE, because `set` stamps a .cwd sidecar next to the .sid one, so
      # this scan can name the directory to re-run it from. Cheap: the state dir is FLAT (one
      # continue-<hash> per worktree, per hooks/lib/continue-sentinel.sh), so this is a single glob,
      # never a filesystem walk. Sentinels armed before the .cwd stamp existed report their path
      # instead of a lie — the sentinel NAME is a one-way hash of (config-dir|cwd).
      if [ -n "${SC_SID:-}" ] && [ "$SC_SID" != "?" ]; then
        _others=""
        for _s in "$(continue_state_dir)"/continue-*.sid; do
          [ -f "$_s" ] || continue
          _b="${_s%.sid}"; [ -f "$_b" ] || continue          # .sid without its sentinel = already disarmed
          [ "$(cat "$_s" 2>/dev/null)" = "$SC_SID" ] || continue
          _w="$(cat "${_b}.cwd" 2>/dev/null || true)"
          [ -n "$_w" ] || _w="cwd unknown (armed before the .cwd stamp) — sentinel $_b"
          _others="${_others}
  · $_w"
        done
        # shellcheck disable=SC2016  # the backticks are MARKDOWN around a command the agent reads, not
        # a substitution — single quotes are exactly right, and the only interpolation is %s.
        [ -n "$_others" ] && printf 'but THIS session still has an armed sentinel elsewhere — re-run `session-continue.sh clear` from:%s\n' "$_others"
      fi
    fi
    log_idl cleared "cli-clear" "$(jq -cn --arg c "$PWD" --argjson d "$was_armed" \
      '{cwd:$c,disarmed:($d==1)}' 2>/dev/null)"
    exit 0 ;;
  status)
    f=$(sentinel_for "$PWD")
    if [ -f "$f" ]; then
      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo '?')): $(cat "$f")"
    else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recognized arg; JSON on stdin) ----------------
SC_LED_CACHE=""   # one wrap-ledger sample per Stop, shared mechanical-arm → ship-floor (review #7)
input=$(cat 2>/dev/null || printf '{}')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"
f=$(sentinel_for "$cwd")
cur_sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$cur_sid" ] || cur_sid="${CLAUDE_CODE_SESSION_ID:-}"
# SC_SID — the telemetry's sid field. Aliased to $cur_sid rather than re-parsed: the cherry-picked
# commit (cd064644) computed its own SC_SID from the same stdin, but trunk had since hoisted
# $cur_sid for the SID-BIND path. Two independent parses of one value is how they drift.
SC_SID="${cur_sid:-?}"

# ── SHARED kill-switch detection (hoisted for the WAKE FLOOR) ─────────────────────────────────────
# Was inline in the sentinel path only. The wake floor below can also BLOCK a stop, so it must honour
# the same operator override — a floor that blocks after the operator typed "stop" would be the D-8
# bug in a new place. One definition, two callers.
# Kill phrases (resident CLAUDE.md kill-switch + explicit-pause list):
#   …and [then] stop · no auto-continue · just do X · stop here · come back to this · bare stop/halt
KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
# Read the LAST genuine user message (string content, or array-of-text; tool_result-only records
# carry no text and are skipped). No transcript path ⇒ can't read ⇒ caller falls through.
last_user_msg() {
  local tp
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  jq -r 'select(.type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end
         | select(. != "")' "$tp" 2>/dev/null | tail -1
}
# Bias to DETECT: a false positive merely allows one stop the model re-arms on its next 🔧 turn; a
# false negative is the D-8 bug (forcing work when told to stop).
kill_switch_active() {
  local m; m="$(last_user_msg)" || return 1
  [ -n "$m" ] || return 1
  printf '%s' "$m" | grep -iqE "$KILL_RE"
}

# ── v2 comms LAG-ACK (UNCONDITIONAL — must run on EVERY Stop, before the exits below) ────────────────
# A Stop proves a turn ran, so whatever the drain SURFACED last cycle (.seen) is now CONSUMED (.acked).
# Since mailbox-drain acks nothing (ack_now=0), .acked advances ONLY here — and a Stop with NO armed
# continuation is the COMMON case, so gating this on the sentinel (as the mail FOLD below is) would leave
# .acked lagging .seen forever and make cc-inbox-guard false-alarm on already-consumed mail. Promoting is
# safe unconditionally: it only advances .acked→.seen (never past what was emitted), so it can never mark
# undelivered mail consumed. TAKING new mail stays gated in the fold (a take whose body is NOT delivered
# in a decision:block reason would advance .seen and silently DROP the mail). Missing lib ⇒ skip; never block.
_mbxlib="$_scd/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
# goal-state lib (LIVE-/goal predicate). The wake floor below must never instruct the exact arm
# that DISABLES an armed /goal (CC skips goal evaluation at any Stop with a non-terminal
# background Bash — docs/research/goal-in-handoff-2026-08-08.md). Optional: absent → the floor
# keeps its pre-goal-aware behaviour.
_goalslib="$_scd/lib/goal-state.sh"
[ -f "$_goalslib" ] || _goalslib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/goal-state.sh"
[ -f "$_goalslib" ] || _goalslib="$HOME/.claude/hooks/lib/goal-state.sh"
if [ -f "$_goalslib" ]; then
  # shellcheck source=lib/goal-state.sh
  # shellcheck disable=SC1091
  . "$_goalslib" 2>/dev/null || true
fi
_ouid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _ouid="${_ouid##*:}"
# KEEP THE RAW PANE KEY. The canonicalisation below deliberately rewrites $_ouid to the SESSION-keyed
# mailbox key — right for every mailbox read, wrong for the teardown marker, which is PANE-keyed (and
# sid-keyed) by all three of its writers. A reader using the canonicalised value would look up a key
# those writers never write. Captured here, at the one place the pane uuid is still the pane uuid.
_opane="$_ouid"
if [ -f "$_mbxlib" ] && command -v jq >/dev/null 2>&1; then
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  if . "$_mbxlib" 2>/dev/null; then
    # CANONICALISE the box key before ANY use below (2026-07-29). _ouid above is the PANE uuid, but
    # mailbox-drain.sh reads the SESSION-keyed box whenever it knows its session id (its :64-68,
    # CC_MBX_SESSION_KEY default 1) and writes the pane→session alias on the way. Every _ouid consumer
    # below is a mailbox READ against that box — mailbox_promote_acked (:213), mailbox_wake_armed and
    # mailbox_pending_count in the floor, mailbox_take in the fold — so each must ask the key the drain
    # actually fills. mailbox_resolve_key is the lib's one implementation of that mapping, and it falls
    # back to the pane when no alias exists, so a never-drained pane still resolves to its own box.
    #
    # WHAT THIS BLOCK NO LONGER DOES (2026-07-31, a079cfdf). It was once ALSO the fix for the two
    # advisories naming different keys: the WAKE FLOOR advertised a PANE-keyed arm while the drain read
    # the SESSION-keyed box, so following it armed a watcher on a key nothing writes to, and each side
    # then re-checked its OWN key and nagged forever. That is history. The floor (:416) and
    # mailbox-drain.sh (:224) now both advertise NO id, and the watcher covers its own whole key space
    # (bin/cc-await-ping `_keys()` → mailbox_keyset). The invariant is COVERAGE, not agreement.
    #
    # WRITTEN AS A POINTER ON PURPOSE — the reason is worth more than the fix. This comment used to
    # assert "`bin/cc-await-ping` resolves NO alias — it watches the key it is handed literally". True
    # the day it was written, FALSE the moment a079cfdf gave the watcher mailbox_keyset, and nothing
    # anywhere went red: the code contract is pinned by tests, the prose about it is pinned by nothing.
    # A reader trusted it eight days later, quoted it into docs/plans/GROUND_UP_DISPATCH.md, and it
    # minted backlog 6b04aee261bb — a session dispatched to fix a defect that had been dead for a week.
    # A restated fact about a sibling file rots silently; a named symbol rots loudly, at the grep that
    # cannot find it. State the neighbour's behaviour by pointing at the symbol that implements it.
    case "$_ouid" in
      # ADDRESS SHAPE: a safe filename component, NOT "hex-shaped". `hdl-<hex>` is a real pane
      # address (bin/cc-pane-headless:124/:197); the hex spelling refused it. SSOT rationale:
      # hooks/session-register.sh. Backlog 4b9d5e93b40a (writer) + 5d1b5dd9b3db (this consumer).
      ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;;
      *) if command -v mailbox_resolve_key >/dev/null 2>&1; then
           _rk="$(mailbox_resolve_key "$_ouid" 2>/dev/null || true)"
           # Adopt ONLY a valid uuid: an empty or malformed resolve must never blank the key, or every
           # guard below would skip and the wake floor would go silently inert — the exact class of
           # failure this hook exists to prevent.
           case "$_rk" in ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;; *) _ouid="$_rk" ;; esac
           unset _rk
         fi ;;
    esac
    case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;; *) mailbox_promote_acked "$_ouid" ;; esac
  fi
fi

# ── THE FLOOR'S MISSING THIRD STATE: terminating / lead-owned (2026-07-29) ─────────────────────────
# The floor below reads exactly two states — ACTIVE (a sentinel is armed) and IDLE (nothing is). It
# had no read on a session that is ENDING, nor on one whose wake path is not the mailbox at all. Both
# gaps were measured live: an Agent-Teams assignee that had ACCEPTED a shutdown_request could not end
# a turn for ~4 HOURS, because every attempt to honour the shutdown re-entered this hook, which
# blocked and demanded it arm a 4-hour cc-await-ping first.
#
# WHY THE EXISTING BOUND DID NOT BOUND IT — the non-obvious part. CC_WAKE_FLOOR_MAX caps attempts per
# session, but the already-armed branch RESETS that budget (`rm -f "$sf"`, deliberate self-healing).
# So a COMPLIANT session arms → budget cleared → its watcher dies with the teardown it is obeying →
# unarmed again with count=0 → the floor fires again. Compliance is what defeats the cap, so for the
# one case that matters the bound is not a bound. That is why this needed a state gate rather than a
# smaller number.
#
# Both ways out that the floor left are things the surrounding design already forbids:
#   · arm anyway — a watcher on a session under teardown is precisely the orphan that cc-await-ping's
#     own OWNER GUARD exists to kill, and an assignee dies by FORCE close (`it2 session close -f`),
#     which skips the EXIT trap and strands the `.watching` heartbeat.
#   · keep looping at Stop — the blocking-hook anti-pattern CLAUDE.md § Session Close names by name.
#
# TWO independent abstains. Neither subsumes the other, because they become true at DIFFERENT times:
#
#  (A) ASSIGNEE — lead-owned wake path. An Agent-Teams assignee is reached by its LEAD over the
#      teammate channel, which the harness wakes directly; it has no SendMessage and is not a mailbox
#      peer. So the floor's premise ("nothing will wake it") is false at EVERY assignee idle, not just
#      its last — TeammateIdle fires 3-4× per teammate. THIS is the abstain that breaks the deadlock,
#      and (B) cannot do it: the lead's closer runs ON TeammateIdle, i.e. it waits for the very idle
#      transition this hook was preventing, so its teardown marker is written AFTER an idle that never
#      happened. A marker-only fix would have been too late by construction, not merely racy.
#
#  (B) TERMINATING — a fresh teardown marker naming THIS session: the durable structured signal that
#      handoff-fire (self-close), cc-teardown (delegated close) and teammate-auto-shutdown
#      (TeammateIdle) all already write. Covers what (A) does not — a self-closing lead, a
#      cc-teardown'd orphan.
#
# FAIL-SAFE DIRECTION IS ASYMMETRIC AND DELIBERATE: no evidence ⇒ do NOT abstain ⇒ the floor applies
# exactly as before. Abstaining on ignorance would silently disarm the entire fleet — the same
# reasoning by which cc-await-ping's owner guard refuses to read reparenting as death.
# Seams: CC_WAKE_FLOOR_TEARDOWN (0 disables both) · CC_WF_PSTABLE_FILE · CC_WF_MAX_HOPS ·
#        CC_WF_TEARDOWN_FRESH_S · CC_TEARDOWN_DIR.

# (A) Am I an Agent-Teams assignee? — MOVED to hooks/lib/agent-identity.sh (2026-08-02) so that
# completion-assert can ask the SAME question with the SAME answer. Two copies of a discriminator
# this load-bearing rot apart invisibly. The rationale (three-flag ancestry conjunction, and the
# team-config cross-confirmation that closes the argv-in-a-brief false positive) lives with the code.
# Resolution mirrors the idl-log.sh tiering below: $0's own symlink first, so a brand-new lib is
# found on the same fast-forward that delivers this hook, before install.sh has run.
# AGENT_IDENTITY_LIB is a HARD override, deliberately not the head of the fallback chain — the
# completion-assert.sh:236 pattern, added here for the same measured reason (review 2026-08-10 #2):
# the assignee oracle reads the RUNNING PROCESS's ancestry, so any suite driving this hook from an
# agent-spawned runner IS "a confirmed/unknown assignee" and every floor abstains — 4/10 ship-floor
# cases red purely by who ran them. Pointing the override at a missing file yields the stub
# ("not an assignee"), which is the fixture's truth. Without the seam the suite is unpinnable: the
# $0-first chain always finds the real lib.
if [ -n "${AGENT_IDENTITY_LIB:-}" ]; then
  _ailib="$AGENT_IDENTITY_LIB"
else
  _ailib="$_scd/lib/agent-identity.sh"
  [ -f "$_ailib" ] || { _ait="$0"; [ -L "$_ait" ] && _ait="$(readlink "$_ait")"
    _ailib="$(cd "$(dirname "$_ait")" 2>/dev/null && pwd)/lib/agent-identity.sh"; }
  [ -f "$_ailib" ] || _ailib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/agent-identity.sh"
  [ -f "$_ailib" ] || _ailib="$HOME/.claude/hooks/lib/agent-identity.sh"
fi
# FAIL-SAFE: no lib ⇒ define a stub that says "not an assignee". That is the SAME direction the
# abstain already takes on no evidence (never abstain on ignorance), so a missing lib cannot
# silently disarm the floor for the whole fleet — it degrades to exactly the pre-abstain behaviour.
# shellcheck source=lib/agent-identity.sh
# shellcheck disable=SC1091
if ! . "$_ailib" 2>/dev/null; then
  agent_assignee_argv() { return 1; }
  agent_team_member_confirms() { return 2; }
fi

# (B) Is a fresh teardown marker naming THIS session? Marker contract and the 30-min freshness window
# are the reader's, taken verbatim from hooks/lead-crash-watchdog.sh classify_death (:255-278) so the
# two consumers of one marker cannot disagree about what it means.
# The PANE-keyed lookup needs marker_owns_sid's rule (:112-118): an in-place `--recycle` leaves the
# PREDECESSOR's marker on a pane that now hosts the SUCCESSOR, and the successor must still get the
# floor — so a marker naming a DIFFERENT non-empty sid is not evidence here. An EMPTY sid is the
# legitimate pane-only case and IS accepted: the real self-close path blanks SESSION_ID.
wf_teardown_marked() { # → 0 = a fresh teardown marker names this session
  local tdir fresh now mt got f
  tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  [ -d "$tdir" ] || return 1
  fresh="${CC_WF_TEARDOWN_FRESH_S:-1800}"; case "$fresh" in ''|*[!0-9]*) fresh=1800 ;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  for f in "${cur_sid:+$tdir/$cur_sid.json}" "${_opane:+$tdir/$_opane.json}"; do
    { [ -n "$f" ] && [ -f "$f" ]; } || continue
    mt="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
    [ "$(( now - mt ))" -le "$fresh" ] 2>/dev/null || continue
    # A sid-keyed hit needs no ownership check — the FILENAME is this session.
    [ -n "$cur_sid" ] && [ "$f" = "$tdir/$cur_sid.json" ] && return 0
    got="$(sed -n 's/.*"sid":"\([^"]*\)".*/\1/p' "$f" 2>/dev/null | head -n1)"
    { [ -z "$got" ] || [ "$got" = "$cur_sid" ]; } && return 0
  done
  return 1
}

# ── WAKE FLOOR (v3 R1) — a session must not reach IDLE without a wake path ────────────────────────
# THE DEFECT IT CLOSES: the wake mechanism works (proved end-to-end 2026-07-26 on CC 2.1.219 —
# armed watcher → cc-notify write → detected in one poll → exit → harness task-completion
# notification re-invoked the model), but NOTHING actuated it. Every cc-await-ping call site in the
# repo was a doc telling the model to arm, or a lint detecting that it hadn't. Measured result:
# 0 armed watchers across 74 mailboxes holding 1,300 unacked lines. A capability that depends on an
# agent choosing to invoke it before every idle is inert by construction.
#
# WHY HERE and not a new hook: mailbox-drain.sh:8-10 (critique fix B) forbids a COMPETING Stop
# blocker — in-loop mail delivery was deliberately folded into this hook, the ONE that already
# blocks at Stop. The floor folds into the same place for the same reason.
#
# WHY IT MUST RECUR: cc-await-ping deletes its own .watching in its EXIT trap (correctly — a stale
# heartbeat would make cc-notify promise a wake that cannot happen). So a session is deaf again the
# instant it has been woken. Arming once per session is insufficient BY CONSTRUCTION; the floor
# re-checks at every idle transition.
#
# BOUNDED, and it degrades to LOUD rather than looping (the session-continue.sh:33 shape):
#   · only a pane with an inbox identity, only when the lib+jq are present  → else silently allow
#   · only when NOT already armed                                          → armed clears the budget
#   · only on the FIRST idle of this session, or when mail is actually pending
#   · at most CC_WAKE_FLOOR_MAX attempts per session, no sooner than CC_WAKE_FLOOR_TTL_S apart
#   · NEVER after an operator kill-switch phrase (kill_switch_active) — that stop was asked for
#   · budget exhausted ⇒ a human-visible systemMessage naming the lever, then ALLOW the stop
# A repeating Stop hook is not evidence that more work exists, so this one can only ever fire a
# bounded number of times and then get out of the way.
#
# TIMEOUT CHOICE: the suggested arm uses a LONG timeout on purpose. cc-await-ping's timeout exit is
# itself a task completion, so it also wakes the model — a short timeout would churn every idle
# session in the fleet on a fixed period. Long timeout ⇒ a timeout-wake is a rare, self-healing
# re-arm rather than a treadmill.
# Seams (tests): CC_WAKE_FLOOR (0 disables) · CC_WAKE_FLOOR_MAX · CC_WAKE_FLOOR_TTL_S ·
#                CC_WAKE_FLOOR_TIMEOUT_S · CC_MAILBOX_DIR.
wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 0 ;; esac

  local mbxd sf now cnt ts prev_sid maxa ttl pend armcmd reason warnmsg
  mbxd="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  sf="$mbxd/$_ouid.wakefloor"

  # Already reachable → clear the budget so a LATER unarmed episode starts fresh (self-healing).
  if mailbox_wake_armed "$_ouid"; then rm -f "$sf" 2>/dev/null; return 0; fi

  now="$(date +%s 2>/dev/null || echo 0)"
  cnt=0; ts=0; prev_sid=""
  if [ -f "$sf" ]; then
    prev_sid="$(sed -n 's/^sid=//p' "$sf" 2>/dev/null | head -n1)"
    cnt="$(sed -n 's/^count=//p' "$sf" 2>/dev/null | head -n1)"
    ts="$(sed -n 's/^ts=//p'    "$sf" 2>/dev/null | head -n1)"
  fi
  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
  case "$ts"  in ''|*[!0-9]*) ts=0  ;; esac
  # A new session in the same pane gets a FRESH budget (the .sid discipline of the sentinel, applied
  # here: a successor must not inherit a predecessor's exhausted attempts).
  [ -n "$prev_sid" ] && [ -n "$cur_sid" ] && [ "$prev_sid" != "$cur_sid" ] && { cnt=0; ts=0; }

  pend="$(mailbox_pending_count "$_ouid" 2>/dev/null || echo 0)"
  case "$pend" in ''|*[!0-9]*) pend=0 ;; esac

  # ── HEADLESS: this session has no terminal, so a WATCHER is not its wake path (F6 of
  #    docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md, test T16) ────────────
  # A pane session is woken by an armed cc-await-ping whose EXIT rides the harness's task-completion
  # notification back into the model. A resident `--input-format stream-json` agent has no such
  # boundary: its only turn boundary is a WRITE TO ITS STDIN, which is what `bin/cc-wake-headless`
  # performs against the fifo `bin/cc-pane-headless` spawns it on. Blocking such a session's Stop
  # therefore demands a continuation the substrate cannot produce, and the measured outcome is not a
  # nag but a DEATH: `Error: Input must be provided`.
  #
  # THE DISCRIMINATOR IS THE WRITER'S ENV, NOT THE ADDRESS'S SHAPE. The spec wrote this abstain as
  # "pane-less", i.e. an EMPTY id — and the `_ouid` guard at the top of this function already returns
  # on that. But gap 1 did not land the empty-pane fallthrough it prescribed: `cc-pane-headless:124`
  # mints `hdl-<16hex>` and `:197` exports it as CC_PANE_ID, so a headless session reaches here with a
  # perfectly ordinary NON-EMPTY address and sails past that guard. The property held; the prescribed
  # diff never landed. So the test cannot be emptiness, and it must not be the `hdl-` prefix either:
  # `hooks/session-register.sh:134-145` states in terms that reading the surface off an id's SHAPE is
  # "the exact mistake", because only the writer knows it. This hook RUNS IN the writer's own
  # environment, so it can use that file's predicate verbatim rather than re-deriving it — the same
  # expression, at the one other site that needs the same answer.
  #
  # Placed with the other abstains, BEFORE the state-file write: an abstain must never consume a
  # budget attempt. And it is not silent when it costs something — with mail actually pending it
  # names the count and the primitive that delivers it, because a floor that stands down quietly over
  # unread mail is the silent-cap defect.
  if [ -n "${CC_PANE_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ]; then
    printf 'session-continue: wake floor ABSTAINS (pane-less session — its wake is the spawner stdin write, not a watcher).\n' >&2
    if [ "$pend" -gt 0 ]; then
      jq -nc --arg m "ℹ Wake floor stood down (pane-less session — a watcher is not its wake path), but ${pend} message(s) are unread in this session's inbox. A headless session has no next turn to drain on: something must call cc-wake-headless ${_ouid} to give it one." \
        '{systemMessage:$m}' 2>/dev/null || true
    fi
    return 0
  fi

  # ── FOURTH STATE: a LIVE /goal ⇒ the goal IS the wake path, and the watcher would DISABLE it ─────
  # CC deletes the /goal Stop hook at any Stop where a non-terminal background Bash exists, then
  # silently restores it (measured on 2.1.220 — docs/research/goal-in-handoff-2026-08-08.md
  # § RESOLVED). The `cc-await-ping` arm this floor instructs is exactly such a task, parked for 4 h
  # — so this block used to be the INSTRUCTION-INJECTOR that made armed goals inert fleet-wide. A
  # goal-driven session is not deaf while unarmed either: an unmet evaluation blocks the stop, the
  # session keeps taking turns, and mailbox-drain delivers pending mail at every boundary those
  # turns produce. Placed before the state-file write: an abstain must not consume a budget attempt.
  #
  # ── FLIPPED FROM ABSTAIN TO "INSTRUCT THE SAFE FORM" (2026-08-16, goal-safe-2way-comms §4 C7) ────
  # The abstain above closed the starvation pole and left the session in the SPIN one: bare, blocking
  # every stop on an unmet goal, re-judging a world nothing has changed — 90 consecutive unmet
  # evaluations in 76 minutes on the type specimen, and 15 cap force-idles fleet-wide in three days.
  # It also assumed the goal keeps the session awake, which holds only BELOW the block cap; above it
  # the harness force-idles and the session is deaf until someone types. So a live goal is no longer
  # a reason for this floor to say nothing — it is a reason to instruct a DIFFERENT arm.
  #
  # STILL BUDGETED, STILL TTL'd, STILL KILL-SWITCHED — this returns into the ordinary floor below
  # rather than growing a second policy. The only thing the goal changes is WHICH command the block
  # names. The mode's own arm gate is what keeps that safe: if this session in fact has pending mail,
  # a live sibling watcher, or no readable turn beat, cc-await-ping REFUSES (exit 6) and parks
  # nothing, so the worst case of a wrongly-instructed arm is a loud no-op, never a disabled goal.
  #
  # PENDING MAIL IS THE ONE CASE THAT STILL ABSTAINS: with mail waiting the session HAS work, the
  # idle-scoped arm would be refused for exactly that reason, and the goal-forced turns deliver it —
  # so blocking to demand an arm that is designed to fail would be a pure round-trip.
  local _wf_goal=""
  if command -v goal_live_condition >/dev/null 2>&1; then
    local _wf_tp
    _wf_tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    _wf_goal="$(goal_live_condition "$_wf_tp" 2>/dev/null)" || _wf_goal=""
    if [ -n "$_wf_goal" ] && [ "$pend" -gt 0 ]; then
      printf 'session-continue: wake floor ABSTAINS (a /goal is LIVE and mail is already pending — the goal-forced turns deliver it, and the idle-scoped arm would refuse over pending mail anyway).\n' >&2
      jq -nc --arg m "ℹ Wake floor stood down (a /goal is live); ${pend} pending message(s) will surface at the next turn boundary the goal forces." \
        '{systemMessage:$m}' 2>/dev/null || true
      return 0
    fi
  fi

  # W2 CUSTODY (CLOSE_INTEGRITY): open dispatched work is a wake-relevant fact exactly like pending
  # mail — the ping that discharges it arrives through the same inbox, so an originator idling DEAF
  # over open custody is the wave-abandonment generator itself (62 stranded commits, 5 wave-day
  # spikes). Best-effort count; absent binary (the ADD-not-live window) or any failure ⇒ 0.
  # (Composes with the /goal abstain above: a goal-driven originator is already kept awake by the
  # goal itself, which is a stronger wake path than any watcher.)
  #
  # ATTRIBUTED, like the SHIP FLOOR (2026-08-17, backlog 9581119669f9). This used to count
  # `cc-custody count --open --cwd "$cwd"` — cwd and ONLY cwd — and then tell whoever was stopping
  # "you are their ORIGINATOR, their pings arrive through THIS inbox". In a SHARED checkout
  # (claude-infrastructure is one: many sessions cd into it) both halves are false for every session
  # that merely shares the directory. It fired on the healthy case, which is the alarm-polarity
  # defect — a page that cannot distinguish an originator from a bystander carries no bits — and it
  # instructed an innocent session to await work that can never reach it and to `cc-custody return`
  # a marker it does not own, while making ✅ unreachable for a session with nothing open.
  # The store already carries the discriminator: every row cc-custody opens holds `originatorPane`
  # (handoff-fire passes --originator-pane) and `notifyBack`. So: count only rows this PANE owns —
  # the same shape as session_unlanded_mine, which exists precisely so a sibling's state cannot
  # convict you. $_opane is the RAW pane key captured at :197 (deliberately NOT the canonicalised
  # mailbox key), the same value handoff-fire writes as originatorPane.
  # WHAT IS DELIBERATELY *NOT* DROPPED: a row carrying NEITHER field cannot be attributed either
  # way, and cc-custody's own header (POLARITY, v1) rejects the direction that silently DROPS
  # custody — a per-pane key loses it across the measured resume-loses-pane-id case. So an
  # unattributable row still counts, and the message HEDGES instead of asserting originatorship.
  # Same when this session has no pane id at all: no discriminator ⇒ the old cwd count, hedged.
  local cust=0 cust_mine=0 cust_unk=0 _cb="" _cj="" _cc="" _custmsg=""
  # CC_CUSTODY_BIN is a TEST SEAM, and it is first for the same reason every other oracle in this
  # repo has one (CC_WTGC_CC_NOTIFY, CC_WTGC_LSOF, …): the probe below resolves the REAL binary out
  # of the checkout, so a suite could only ever exercise this arm against the operator's live
  # custody store — i.e. not at all, which is why the arm shipped with no test. Unset in production,
  # where the probe order is unchanged.
  for _cb in ${CC_CUSTODY_BIN:+"$CC_CUSTODY_BIN"} \
             "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../bin/cc-custody" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-custody" "$HOME/.claude/bin/cc-custody"; do
    [ -x "$_cb" ] && break; _cb=""
  done
  if [ -n "$_cb" ]; then
    if [ -n "$_opane" ] && command -v jq >/dev/null 2>&1 \
       && _cj="$("$_cb" list --open --cwd "$cwd" --json 2>/dev/null)" && [ -n "$_cj" ]; then
      # notifyBack is a SECOND ownership spelling, not a fallback: handoff-fire arms it as either the
      # bare pane ("386") or "<worktree>-<pane>" ("wt-pool-2-415"), so the "-" anchor is required —
      # a bare suffix match would let pane 15 claim pane 415's row.
      _cc="$(printf '%s' "$_cj" | jq -r --arg p "$_opane" '
              def known: ((.originatorPane // "") != "") or ((.notifyBack // "") != "");
              def mine:  ((.originatorPane // "") == $p)
                      or ((.notifyBack // "") == $p)
                      or ((.notifyBack // "") | endswith("-" + $p));
              [ (map(select(known and mine)) | length), (map(select(known | not)) | length) ]
              | map(tostring) | join(" ")' 2>/dev/null || true)"
      cust_mine="${_cc%% *}"; cust_unk="${_cc##* }"
      case "$cust_mine" in ''|*[!0-9]*) cust_mine=0 ;; esac
      case "$cust_unk"  in ''|*[!0-9]*) cust_unk=0  ;; esac
      cust=$(( cust_mine + cust_unk ))
    else
      # No pane identity (or no jq / unreadable store) ⇒ attribution is IMPOSSIBLE, not negative.
      # Keep the pre-attribution behaviour and let the wording carry the uncertainty.
      cust_unk="$("$_cb" count --open --cwd "$cwd" 2>/dev/null || echo 0)"
      case "$cust_unk" in ''|*[!0-9]*) cust_unk=0 ;; esac
      cust="$cust_unk"
    fi
  fi

  # ── THIRD STATE: terminating / lead-owned ⇒ this gate does not APPLY (see the block above) ────────
  # PLACED HERE, before the state file is written: an abstain must not consume a budget attempt, or a
  # session that was merely an assignee for a while would arrive at a genuine unarmed idle with its
  # attempts already spent. Reading $sf above is free; only the write below costs.
  # NOT SILENT WHEN IT COSTS SOMETHING: with mail actually pending, an abstain leaves that mail for the
  # next turn, so it says so where a human can see it rather than dropping the fact (the "no silent
  # caps" rule). Blocking would not have delivered that mail either — the block only asks the model to
  # ARM a watcher — so the abstain forfeits nothing the floor could have won.
  if [ "${CC_WAKE_FLOOR_TEARDOWN:-1}" = 1 ]; then
    local _wf_aid _wf_why="" _wf_c=2
    if _wf_aid="$(agent_assignee_argv)" && [ -n "$_wf_aid" ]; then
      agent_team_member_confirms "$_wf_aid" && _wf_c=0 || _wf_c=$?
      case "$_wf_c" in
        0) _wf_why="team assignee ${_wf_aid} (confirmed by its team config) — its lead wakes it over the teammate channel, not the mailbox" ;;
        2) _wf_why="team assignee ${_wf_aid} (argv evidence only — no readable team config) — its lead wakes it over the teammate channel, not the mailbox" ;;
        *) : ;;   # REFUTED: the team's own config knows no such member ⇒ argv prose, not an assignee
      esac
    fi
    if [ -z "$_wf_why" ] && wf_teardown_marked; then
      _wf_why="a fresh teardown marker names this session — it is terminating, not going idle"
    fi
    if [ -n "$_wf_why" ]; then
      printf 'session-continue: wake floor ABSTAINS (%s).\n' "$_wf_why" >&2
      if [ "$pend" -gt 0 ]; then
        jq -nc --arg m "ℹ Wake floor stood down (${_wf_why}), but ${pend} message(s) are still unread in this session's inbox — they will surface on its next turn, if it has one." \
          '{systemMessage:$m}' 2>/dev/null || true
      fi
      return 0
    fi
  fi

  # Fire on the first idle of the session, any idle where mail is actually waiting, or any idle
  # while dispatched work THIS PANE OWNS (or that nothing can attribute away from it) has not
  # returned — the originator's one job while waiting is to be wakeable. A row a sibling in this
  # shared checkout fired is not in $cust at all, so it can no longer re-fire this floor over a
  # session with nothing open. Otherwise a session that already declined once is left alone.
  [ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0

  maxa="${CC_WAKE_FLOOR_MAX:-2}"; case "$maxa" in ''|*[!0-9]*) maxa=2 ;; esac
  ttl="${CC_WAKE_FLOOR_TTL_S:-600}"; case "$ttl" in ''|*[!0-9]*) ttl=600 ;; esac
  # Absolute, not "~/…": the model pastes this verbatim, and a tilde inside a quoted string is not a
  # path (SC2088). $HOME also keeps the message truthful under a fixture $HOME in the suites.
  # NO-ARG (2026-07-31) — supersedes the 2026-07-29 box-key agreement above, which fixed the two
  # advisories' DISAGREEMENT by pointing both at the key mailbox-drain.sh reads. That agreed on the
  # wrong key: nothing WRITES the session box directly. cc-notify addresses panes (cc-roles/desk and
  # every cc-registry row hold pane uuids) and resolves no alias, so a session-keyed watcher waits out
  # its full timeout while the line sits in <pane>.md, harvested only by a boundary — the very thing
  # the watcher exists to cause. Measured on one write: session-keyed rc 2 (deaf), pane-keyed woke in
  # one poll. Passing NO id makes cc-await-ping derive ${ITERM_SESSION_ID##*:}, the same expression
  # cc-notify resolves a target with, and cover that key's whole set — reader ⊇ writer by construction
  # rather than by two hooks agreeing. The armed-check above stays keyed on $_ouid and still works:
  # the watcher writes a .watching marker under EVERY key of the set, so either question answers true.
  armcmd="$HOME/.claude/bin/cc-await-ping --timeout ${CC_WAKE_FLOOR_TIMEOUT_S:-14400} --interval 15"
  # UNDER A LIVE GOAL, a DIFFERENT command (C7). Not a longer sentence about the same one: the bare
  # form is denied at the chokepoint (hooks/validate-bash.sh) under a live goal, so instructing it
  # here would hand the model a command its own guard refuses — the exact loop the E1 notice defect
  # is made of. The sid is mandatory, because the idle-scoped exit condition IS this session's turn
  # beat; without a resolvable id the tool refuses rather than parking blind.
  if [ -n "$_wf_goal" ]; then
    if [ -n "$cur_sid" ]; then
      armcmd="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid $cur_sid"
    else
      armcmd="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid <this session's id>"
    fi
  fi

  # Budget exhausted → do NOT block. Say it where a human can see it, then allow the stop.
  if [ "$cnt" -ge "$maxa" ]; then
    warnmsg="⚠ No inbox wake path armed — peers can write to this session but nothing will wake it. Mail will sit until your next turn. Arm it with: ${armcmd}"
    [ "$pend" -gt 0 ] && warnmsg="⚠ ${pend} message(s) waiting and NO wake path armed — nothing will wake this session. Arm it with: ${armcmd}"
    printf 'session-continue: wake floor exhausted (%s/%s) — allowing stop, unarmed.\n' "$cnt" "$maxa" >&2
    jq -nc --arg m "$warnmsg" '{systemMessage:$m}' 2>/dev/null || true
    return 0
  fi
  # Re-attempt no sooner than the TTL (a burst of short turns must not re-block every one of them).
  [ "$(( now - ts ))" -ge "$ttl" ] 2>/dev/null || return 0
  # The operator asked to stop → never block; the exhausted-branch warning is the right surface.
  if kill_switch_active; then
    jq -nc --arg m "⚠ No inbox wake path armed — this session will not be woken by peer mail. Arm: ${armcmd}" '{systemMessage:$m}' 2>/dev/null || true
    return 0
  fi

  printf 'sid=%s\ncount=%s\nts=%s\n' "$cur_sid" "$(( cnt + 1 ))" "$now" > "$sf" 2>/dev/null || true

  reason="🔔 WAKE FLOOR — you are about to go idle with NO wake path armed, so a peer's message would land in your inbox and sit there unread until someone types at you.

Arm your inbox watcher NOW, then stop. Run it as a Bash tool call with run_in_background=true:

  ${armcmd}

It blocks until a line lands in your inbox, prints it, and exits — and that exit rides the harness's task-completion notification back into you. That IS the wake; it is the only way an external write can reach an idle session.

Re-arm after every wake: the watcher removes its own heartbeat when it exits, so once it has woken you, you are deaf again until you arm a new one."
  [ -n "$_wf_goal" ] && reason="${reason}

A /goal is LIVE here, which is why the command above is the --idle-scoped form and not the ordinary 4-hour arm (that one is denied under a live goal — it would make Claude Code skip your goal's evaluation at every Stop, silently, for as long as it runs). The idle-scoped watcher additionally stands itself down the moment this session takes another turn, so it defers your goal for exactly as long as you are genuinely idle and no longer: your goal is then judged once per new-information event instead of never (parked) or ninety times over an unchanged world (bare).

Arm it as your LAST action, on a clean committed state. It REFUSES to arm (exit 6, which the harness will label 'failed' — read the verdict) if mail is already pending, if a sibling watcher is already live, or if it cannot read this session's turn beat. Each of those means 'you are not actually idle-and-safe yet', not 'something broke'."
  [ "$pend" -gt 0 ] && reason="📬 ${pend} message(s) are pending in your inbox RIGHT NOW.

${reason}"
  # TWO SPELLINGS, because the two facts are different (see the attribution block above). Rows this
  # pane OWNS support the originator claim; rows that merely cannot be attributed do not, and saying
  # so is what keeps the alarm informative for the session that actually fired the wave.
  if [ "$cust_mine" -gt 0 ]; then
    _custmsg="🧵 ${cust_mine} dispatched session(s) YOU fired have NOT returned (\`cc-custody list --open --cwd . --json\` — the rows whose originatorPane is this pane). You are their ORIGINATOR — their completion pings arrive through this inbox, so idling deaf is how a wave gets abandoned. Await them armed; when one reports, collect + synthesize + land its work, then \`cc-custody return <marker-or-slug>\` (or \`cc-custody abandon <token> --why …\` if superseded)."
    [ "$cust_unk" -gt 0 ] && _custmsg="${_custmsg} (${cust_unk} further open row(s) here carry no originator field at all, so whether they are also yours cannot be decided from the store.)"
  elif [ "$cust_unk" -gt 0 ]; then
    _custmsg="🧵 ${cust_unk} dispatched session(s) are open against this cwd, and the store cannot say whose (\`cc-custody list --open --cwd . --json\` — no originatorPane/notifyBack on those rows, or this pane has no id). If you fired them, their pings arrive through this inbox and idling deaf is how a wave gets abandoned — await them armed, then \`cc-custody return <marker-or-slug>\`. If a sibling session sharing this checkout fired them, this is NOT yours: it is that pane's debt, and nothing here is owed by you."
  else
    _custmsg=""
  fi
  [ -n "$_custmsg" ] && reason="${_custmsg}

${reason}"
  jq -nc --arg r "$reason" --arg m "🔔 Wake floor: arming this session's inbox watcher (no wake path was armed)." \
    '{decision:"block",reason:$r,systemMessage:$m}'
  return 1
}

# ── MECHANICAL 🔧 — loose ends must not need the model to REMEMBER (operator crux 2026-08-01) ─────
# THE DEFECT: this loop was armed by the model and only by the model. Measured over the live IDL —
# 393 `armed/cli-set` against 902 completion-assert Stop invocations — so on most closes no sentinel
# existed, and a session that had edited files could go idle with them uncommitted while every Stop
# arm waved it through. completion-assert cannot cover it either: it fires only on a done-ASSERTION,
# and its single largest disposition is `no-close-tell` (503/902 = 56%) — a turn that simply ends
# without claiming anything never reaches the ledger at all. The operator's words: "loose-ends and
# remaining tasks are supposed to continue the agent session without a return to idle, so those
# shouldn't be the case in the first place." A discipline the model can forget is not a mechanism.
#
# WHY THIS IS NOT THE BANNED SCOPE-BLIND STOP HOOK (this file's own header, :3-8). That ban was
# written when nothing could tell in-scope dirt from anyone else's; scripts/wrap-ledger.sh now
# computes the rung from live facts, and lib/session-writes.sh attributes each dirty path to the
# session that actually wrote it. Scope judgment is still not being guessed — it is being READ.
#
# THE PREDICATE IS DELIBERATELY NARROW: dirty tree ∧ ≥1 dirty path written BY THIS SESSION. The two
# rejected candidates matter more than the accepted one:
#   · GATE STALE — structurally permanent here. CLAUDE.md § Session Close says so outright: the
#     `gate-green` marker the land path cannot advance "has been red since long before your diff".
#     Looping on it is the infinite-loop-wearing-diligence's-clothes case, by name.
#   · DoD REMAINDER — the durable DoD accumulates frozen scopes across weeks BY DESIGN (it is
#     INTEGRATE-only), so a remainder is the steady state, not a loose end. Firing on it would block
#     every close in this worktree forever.
# Both stay with completion-assert's ledger arm, which acts only against a done-ASSERTION and so
# cannot loop. What is left — "I edited files and am about to go idle without committing them" — is
# the one 🔧 that is unambiguously this turn's, unambiguously losable, and SELF-CLEARING: the moment
# the model commits, the tree is clean and this cannot fire again. Bounded from both ends.
#
# COMPOSITION: this only ARMS the sentinel and falls through into the ordinary armed path below, so
# it inherits every existing safety property rather than duplicating one — kill-switch, SID-BIND,
# the CLAUDE_CONTINUE_MAX cap and its named re-arm lever, and the IDL record. A second loop with its
# own bound is how two caps that must agree drift apart.
# Seams: CC_MECH_CONTINUE (0 disables) · WRAP_LEDGER_BIN · SESSION_WRITES_LIB
TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
# ── the wrap-ledger memo's EVENT key (P0-4, scripts/wrap-ledger.sh § THE MEMO) ──
# Seven Stop-hook call sites each pay a full ~180 ms / 19-git ledger on every close, and TWO of them
# are in this file (the mechanical arm and the ship floor, which already share one sample via
# SC_LED_CACHE). They are one event, so they should observe one snapshot: handing the ledger this
# session's transcript is what lets it serve one. Absent ⇒ that script computes as it always has.
_sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
[ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
mechanical_arm() {   # rc 0 = armed (fall through to the armed path) · rc 1 = did not arm
  [ "${CC_MECH_CONTINUE:-1}" = "0" ] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  # The operator asked to stop → never manufacture a continuation. Checked HERE as well as in the
  # armed path so a kill-switch turn does not churn a sentinel into existence just to delete it.
  kill_switch_active && return 1
  # ── PEER EXEMPTION (2026-09-02) ────────────────────────────────────────────────────────────────
  # Both sibling floors stand down for a peer: ship_floor at :865-869, wake_floor at :587-608. This
  # arm checked NEITHER, so one hook gave three different answers about the same class of session —
  # a confirmed Agent-Teams assignee with its own dirty files was exempt from the ship floor, exempt
  # from the wake floor, and blocked here.
  #
  # That asymmetry is worse than it looks, because an assignee's close is not its own: it is the
  # LEAD's harvest. Blocking it forces the assignee to keep taking turns over dirt the lead is about
  # to collect and commit, and the assignee cannot discharge it — the merge is not its to do. The
  # dirty tree is real, so the ledger is right; the ACTOR is wrong, which is the who-vs-when split
  # this hook's own attribution work (session-writes.sh:13-22) exists to respect.
  #
  # Semantics copied from ship_floor deliberately — rc 0 (confirmed) OR rc 2 (cannot tell) both
  # exempt. NOT wake_floor's, which also exempts argv-only and treats a REFUTED rc 1 as non-exempt
  # (:589-594): the three floors are not interchangeable and this is the one that matches an arm
  # whose remedy is "commit your own paths".
  local _ma_aid _ma_c
  if _ma_aid="$(agent_assignee_argv)" && [ -n "$_ma_aid" ]; then
    agent_team_member_confirms "$_ma_aid"; _ma_c=$?
    if [ "$_ma_c" -eq 0 ] || [ "$_ma_c" -eq 2 ]; then
      log_idl cleared "mechanical-assignee"
      return 1
    fi
  fi
  # A session already torn down is not going to commit anything; nudging it is pure noise.
  wf_teardown_marked && { log_idl cleared "mechanical-teardown"; return 1; }

  local swlib
  swlib="${SESSION_WRITES_LIB:-$_scd/lib/session-writes.sh}"
  # A BRAND-NEW hooks/lib file has no ~/.claude/hooks/lib symlink until install.sh runs, and when
  # this hook runs from ~/.claude/hooks/ every tier below resolves to that same missing path — so
  # the mechanical arm would land INERT and silently never fire. Resolve $0's own symlink into the
  # checkout first (same fix, same reason, as hooks/completion-assert.sh:99-105).
  [ -f "$swlib" ] || { local _swt="$0"; [ -L "$_swt" ] && _swt="$(readlink "$_swt")"
    swlib="$(cd "$(dirname "$_swt")" 2>/dev/null && pwd)/lib/session-writes.sh"; }
  [ -f "$swlib" ] || swlib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/session-writes.sh"
  [ -f "$swlib" ] || swlib="$HOME/.claude/hooks/lib/session-writes.sh"
  [ -f "$swlib" ] || return 1
  # shellcheck source=lib/session-writes.sh
  # shellcheck disable=SC1091
  . "$swlib" 2>/dev/null || return 1

  # Ledger first: it is the cheap read, and a non-🔧 rung ends this immediately. The bare-📦 SILENT
  # idle is no longer waved through wholesale — that is the SHIP FLOOR's bounded job below (the
  # 2026-08-10 recon convicted the old blanket refusal as the load-bearing leak); this arm still
  # owns only 🔧. The ledger output is CACHED for the ship floor (review #7: two full wrap-ledger
  # runs — git forks + a cc-decide fork each — per unarmed idle Stop, on a chain measured 3688ms).
  local wrap led rung
  wrap="${WRAP_LEDGER_BIN:-}"
  if [ -z "$wrap" ]; then
    for wrap in "$_scd/../scripts/wrap-ledger.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
      [ -f "$wrap" ] && break
    done
  fi
  [ -n "$wrap" ] && [ -f "$wrap" ] || return 1
  led="$( cd "$cwd" 2>/dev/null && bash "$wrap" --machine 2>/dev/null || true )"
  [ -n "$led" ] || return 1
  SC_LED_CACHE="$led"
  rung="$(printf '%s' "$led" | grep -E '^RUNG=' | head -1 | cut -d= -f2-)"
  [ "$rung" = "🔧" ] || return 1

  # Attribution. rc 2 (cannot tell) must NOT arm: a Stop hook may never block a turn on its own
  # inability to read something.
  local mineout mrc n_files shown
  mineout="$(session_dirty_mine "$TP_MECH" "$cwd")"; mrc=$?
  [ "$mrc" -eq 0 ] || return 1
  [ -n "$mineout" ] || return 1

  n_files="$(printf '%s\n' "$mineout" | grep -c . 2>/dev/null || echo 0)"
  case "$n_files" in ''|*[!0-9]*) n_files=0 ;; esac
  [ "$n_files" -gt 0 ] || return 1
  shown="$(printf '%s\n' "$mineout" | head -8 | tr '\n' ' ' | sed 's/ *$//')"
  [ "$n_files" -gt 8 ] && shown="$shown … (+$(( n_files - 8 )) more)"

  # ── THE BUDGET THAT SURVIVES THE CAP (defect caught by its own bats case, 2026-08-01) ──────────
  # First cut did `rm -f "${f}.count"` here, mirroring the CLI `set`. That made the loop UNBOUNDED:
  # the armed path hits CLAUDE_CONTINUE_MAX, clears the sentinel and allows the stop — and the very
  # next Stop finds no sentinel, re-enters this function, and re-arms with a zeroed counter. The cap
  # was reset by the thing it was supposed to bound. That is exactly MEMORY.md
  # bounded-gate-unbounded-by-compliance ("a budget the demanded action RESETS never binds"), and
  # the model would have been re-blocked forever on dirt it may have had a good reason to leave.
  #
  # So the mechanical arm carries its OWN budget in `${f}.mech`, keyed by session id, and that file
  # is deliberately NOT removed when the sentinel is cleared. It bounds mechanical arms per session,
  # independently of how many continuations each arm then drives. A DIFFERENT session id resets it
  # (a successor deserves its own budget); the same session does not get a second wind.
  # The counter never has to be cleared on success, because success IS the tree going clean, and a
  # clean tree cannot reach this line at all.
  # THE BOUND IS A PRODUCT, NOT A SUM — state it, because it is the number that actually binds:
  # each mechanical arm starts a FRESH continuation chain (the cap path deletes `.count` when it
  # fires), so the worst case is CC_MECH_MAX × CLAUDE_CONTINUE_MAX forced turns, not CC_MECH_MAX.
  # At the old default of 3 that was 24 consecutive blocks — bounded, but far past the point where
  # a session that cannot commit is being helped rather than harassed. 2 keeps the escape hatch
  # meaningful (`clear` spends the budget outright) while still catching the second lapse.
  local mfile mline msid mcnt mmax
  mfile="${f}.mech"; mmax="${CC_MECH_MAX:-2}"
  mcnt=0
  if [ -f "$mfile" ]; then
    mline="$(cat "$mfile" 2>/dev/null || true)"
    msid="${mline%% *}"; mcnt="${mline##* }"
    case "$mcnt" in ''|*[!0-9]*) mcnt=0 ;; esac
    # A stale budget from another session must not bind this one.
    [ "$msid" = "${cur_sid:-?}" ] || mcnt=0
  fi
  if [ "$mcnt" -ge "$mmax" ]; then
    printf 'session-continue: mechanical 🔧 budget spent (%s/%s) — allowing stop.\n' "$mcnt" "$mmax" >&2
    log_idl cleared "mechanical-budget" "$(jq -cn --argjson n "$mcnt" --argjson m "$mmax" \
      '{count:$n,max:$m}' 2>/dev/null)"
    return 1
  fi
  printf '%s %s' "${cur_sid:-?}" "$(( mcnt + 1 ))" > "$mfile" 2>/dev/null || true

  printf '%s' "You are about to go idle with ${n_files} file(s) you edited THIS TURN still uncommitted: ${shown}. Finish the in-scope work, run the repo's gate, and commit with explicit paths (then land per the repo's ship policy). If this dirt is deliberately parked, or is not yours to commit, run \`~/.claude/hooks/session-continue.sh clear\` and say so in your close." > "$f" 2>/dev/null || return 1
  [ -n "$cur_sid" ] && printf '%s' "$cur_sid" > "${f}.sid" 2>/dev/null
  # Same cwd-stamp the CLI `set` writes. A MECHANICALLY armed sentinel is the one most likely to be
  # cleared from the wrong directory — the model never chose where it was armed — so it needs the
  # sidecar that lets `clear` name the cwd at least as much as an agent-set one does.
  printf '%s' "$cwd" > "${f}.cwd" 2>/dev/null || true
  log_idl armed "mechanical-dirty" "$(jq -cn --arg c "$cwd" --argjson n "${n_files:-0}" \
    '{cwd:$c,files:$n,source:"session-writes"}' 2>/dev/null)"
  return 0
}

# ── SHIP FLOOR (CLOSE_INTEGRITY W2b) — silent 📦/🚀 idles were the load-bearing leak ─────────────
# The mechanical arm's own header (above) says "📦 must NOT fire — committed-but-unlanded is
# operator-readout's surface and the ship policy's business, not a loop." The 2026-08-10 recon's
# verdict is that this decision IS the gap the fleet keeps bleeding through: the ship policy had no
# actuator, 58% of stops assert nothing (`no-close-tell` is completion-assert's modal outcome), so
# a session idling on committed-unlanded work passed every rail — 53/60 recent closes were clean
# exit-0 on sessions that simply chose to end, and the operator's close of a done-looking pane was
# the last domino, not the generator (report-adversarial candidate 2; report-census wave-abandonment).
# This floor reverses that decision in BOUNDED form, not as a loop:
#   · fires ONCE per HEAD-sha (a new commit deserves one fresh nudge), ≤ CC_SHIP_FLOOR_MAX/session
#   · 📦 only when the unlanded commits contain THIS session's OWN writes — the #105 sibling-dirt
#     lesson applied to commits; attribution rc≠0 or oracle absent ⇒ abstain, never nudge on
#     ignorance. 🚀 only with positive write evidence this session (a repo-wide converger outage
#     must not nudge every idle session — alarm polarity).
#   · assignee / terminating abstain (the lead owns an assignee's merge; a teardown is not an idle)
#   · kill-switch honoured; budget exhaustion is silent (operator-readout still renders 📦/🚀)
# Seams: CC_SHIP_FLOOR (0 disables) · CC_SHIP_FLOOR_MAX · WRAP_LEDGER_BIN · SESSION_WRITES_LIB
ship_floor() { # → echoes JSON to BLOCK (rc 1); rc 0 otherwise (never emits on rc 0). Never fails.
  [ "${CC_SHIP_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  kill_switch_active && return 0
  local _sf_aid _sf_c
  if _sf_aid="$(agent_assignee_argv)" && [ -n "$_sf_aid" ]; then
    agent_team_member_confirms "$_sf_aid"; _sf_c=$?
    { [ "$_sf_c" -eq 0 ] || [ "$_sf_c" -eq 2 ]; } && return 0
  fi
  wf_teardown_marked && return 0

  local wrap led rung ahead shas trunk
  # Reuse the mechanical arm's ledger read when it got that far (review #7 — the two floors run in
  # ONE Stop invocation, so a shared sample is the same read, not a stale one).
  led="${SC_LED_CACHE:-}"
  if [ -z "$led" ]; then
    wrap="${WRAP_LEDGER_BIN:-}"
    if [ -z "$wrap" ]; then
      for wrap in "$_scd/../scripts/wrap-ledger.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
        [ -f "$wrap" ] && break
      done
    fi
    [ -n "$wrap" ] && [ -f "$wrap" ] || return 0
    led="$( cd "$cwd" 2>/dev/null && bash "$wrap" --machine 2>/dev/null || true )"
  fi
  [ -n "$led" ] || return 0
  rung="$(printf '%s' "$led" | grep -E '^RUNG=' | head -1 | cut -d= -f2-)"
  case "$rung" in "📦"|"🚀") : ;; *) return 0 ;; esac

  # Attribution oracle — the shared lib, resolved through $0's own symlink first (a brand-new fn
  # must be reachable on the same fast-forward that delivers this hook).
  local swlib
  swlib="${SESSION_WRITES_LIB:-$_scd/lib/session-writes.sh}"
  [ -f "$swlib" ] || { local _st="$0"; [ -L "$_st" ] && _st="$(readlink "$_st")"
    swlib="$(cd "$(dirname "$_st")" 2>/dev/null && pwd)/lib/session-writes.sh"; }
  [ -f "$swlib" ] || swlib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/session-writes.sh"
  [ -f "$swlib" ] || swlib="$HOME/.claude/hooks/lib/session-writes.sh"
  [ -f "$swlib" ] || return 0
  # shellcheck source=lib/session-writes.sh
  # shellcheck disable=SC1091
  . "$swlib" 2>/dev/null || return 0
  if [ "$rung" = "📦" ]; then
    command -v session_unlanded_mine >/dev/null 2>&1 || return 0
    trunk="$(printf '%s' "$led" | grep -E '^TRUNK=' | head -1 | cut -d= -f2-)"
    { [ -n "$trunk" ] && [ "$trunk" != none ]; } || return 0
    session_unlanded_mine "$TP_MECH" "$cwd" "$trunk" >/dev/null 2>&1 || return 0
  else
    command -v session_writes_paths >/dev/null 2>&1 || return 0
    session_writes_paths "$TP_MECH" >/dev/null 2>&1 || return 0
  fi

  # One shot per HEAD-sha + a per-session cap, in one sidecar. A same-sid same-sha re-idle is
  # silent; a new commit re-arms; a successor session gets a fresh budget.
  local sfile line psid psha pcnt maxs head_sha
  head_sha="$(cd "$cwd" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo '?')"
  sfile="${f}.ship"; maxs="${CC_SHIP_FLOOR_MAX:-2}"; case "$maxs" in ''|*[!0-9]*) maxs=2 ;; esac
  psid=""; psha=""; pcnt=0
  if [ -f "$sfile" ]; then
    line="$(cat "$sfile" 2>/dev/null || true)"
    psid="$(printf '%s' "$line" | cut -d' ' -f1)"
    psha="$(printf '%s' "$line" | cut -d' ' -f2)"
    pcnt="$(printf '%s' "$line" | cut -d' ' -f3)"
    case "$pcnt" in ''|*[!0-9]*) pcnt=0 ;; esac
    [ "$psid" = "${cur_sid:-?}" ] || { pcnt=0; psha=""; }
  fi
  [ "$psha" = "$head_sha" ] && return 0
  if [ "$pcnt" -ge "$maxs" ]; then
    printf 'session-continue: ship floor budget spent (%s/%s) — allowing stop on %s.\n' "$pcnt" "$maxs" "$rung" >&2
    return 0
  fi
  printf '%s %s %s' "${cur_sid:-?}" "$head_sha" "$(( pcnt + 1 ))" > "$sfile" 2>/dev/null || true

  ahead="$(printf '%s' "$led" | grep -E '^AHEAD=' | head -1 | cut -d= -f2-)"
  shas="$(printf '%s' "$led" | grep -E '^SHAS=' | head -1 | cut -d= -f2-)"
  local reason
  if [ "$rung" = "📦" ]; then
    reason="📦 SHIP FLOOR — you are going idle on committed-but-unlanded work YOU wrote (${ahead:-?} commit(s): ${shas:-?}). Committed ≠ landed: a branch only this machine can see is one crash or forgotten worktree from lost — the measured top loss class (62 stranded commits across 21 abandoned-wave branches). Apply the ship policy NOW: /ship it (auto-fire by default; where THIS repo's own CLAUDE.md says landing spends money, offer it and park instead). If this park is DELIBERATE, say so in your close — this floor is already spent for the current commit and re-fires at most once per NEW commit (≤${maxs}/session). (ship floor $(( pcnt + 1 ))/${maxs})"
  else
    reason="🚀 SHIP FLOOR — your landed work is NOT live: the enforcing store has breached its converge budget, so the machine still runs the old bytes. Run the converger NOW — \`bash \$(git rev-parse --show-toplevel)/scripts/deploy-live.sh\` — then re-read the ledger (\`/wrap\`). If the converger refuses, file it (\`cc-backlog needs\`) and close on 👤 — never sit on 🚀 and never call it ✅. (ship floor $(( pcnt + 1 ))/${maxs})"
  fi
  log_idl fired "ship-floor" "$(jq -cn --arg r "$rung" --arg a "${ahead:-?}" --argjson n "$(( pcnt + 1 ))" --argjson m "$maxs" \
    '{rung:$r,ahead:$a,count:$n,max:$m}' 2>/dev/null)"
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  return 1
}

# No sentinel → the agent did NOT request continuation → the session is going IDLE. This is the one
# transition the floors guard; a sentinel-blocked stop is not idle, so it needs no floor.
# Floor order: mechanical 🔧 (uncommitted own writes) → ship floor (📦/🚀 own work) → wake floor
# (reachability). At most ONE floor emits per Stop — the hook prints a single JSON object.
if [ ! -f "$f" ]; then
  rm -f "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
  if ! mechanical_arm; then
    if ! _sf_json="$(ship_floor)"; then
      printf '%s' "$_sf_json"
      exit 0      # decision:block travels in the JSON; the hook itself always exits 0
    fi
    if ! _wf_json="$(wake_floor)"; then
      printf '%s' "$_wf_json"
      exit 0
    fi
    [ -n "${_wf_json:-}" ] && printf '%s' "$_wf_json"
    exit 0
  fi
  # Armed mechanically → fall through into the armed path below, which applies the kill-switch,
  # SID-BIND and cap checks and emits the block. No second code path, no second bound.
fi

# ── (a) KILL-SWITCH — operator stop ALWAYS wins over a stale sentinel (I-2 / D-8) ──
# A kill phrase ⇒ clear + allow. (Detection is the shared kill_switch_active above, which the wake
# floor also consults so it can never block a stop the operator asked for.)
if kill_switch_active; then
  rm -f "$f" "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
  printf 'session-continue: kill-switch phrase in last user message — cleared sentinel, allowing stop.\n' >&2
  log_idl cleared "kill-switch"
  exit 0
fi
# NOTE ON THIS RESOLUTION (cherry-pick cd064644): the picked commit carried its own INLINE copy of
# the kill-phrase detection here. Trunk had since hoisted that logic into the shared
# kill_switch_active() above — deliberately, so the WAKE FLOOR consults the same predicate and can
# never block a stop the operator asked for. Trunk's structure is kept and only the telemetry line
# (`log_idl cleared "kill-switch"`) is grafted on; re-introducing the inline copy would have
# resurrected a second, drifting definition of the one predicate that must never disagree with
# itself.

# ── (b) SID-BIND — a same-cwd successor must not inherit a predecessor's sentinel (S-12) ──
# Clear + allow when the stored arming-sid differs from the actuating session's sid. Acts ONLY when
# BOTH sids are known (a missing sid = no evidence = never a wrong clear). $cur_sid is computed above.
stored_sid=$(cat "${f}.sid" 2>/dev/null || true)
if [ -n "$stored_sid" ] && [ -n "$cur_sid" ] && [ "$stored_sid" != "$cur_sid" ]; then
  rm -f "$f" "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
  printf 'session-continue: sentinel sid=%s ≠ session sid=%s (inherited across succession) — cleared, allowing stop.\n' "$stored_sid" "$cur_sid" >&2
  log_idl cleared "sid-mismatch" "$(jq -cn --arg a "$stored_sid" --arg b "$cur_sid" \
    '{stored_sid:$a,session_sid:$b}' 2>/dev/null)"
  exit 0
fi

# ── (c) CAP — hard loop cap (guards a stuck gate / non-progressing agent), with a NAMED re-arm ──
MAX="${CLAUDE_CONTINUE_MAX:-8}"
n=$(cat "${f}.count" 2>/dev/null); [ -n "$n" ] || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" -ge "$MAX" ]; then
  step=$(cat "$f" 2>/dev/null)
  rm -f "$f" "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
  # NOT a silent give-up (D-7): name the re-arm lever, then ALLOW the stop (non-blocking).
  capmsg="session-continue: hit the continuation cap (${MAX}); allowing this stop. If in-scope work genuinely remains, re-arm with \`session-continue.sh set \"<next step>\"\` (a fresh set zeroes .count). Last step was: ${step}"
  printf '%s\n' "$capmsg" >&2
  jq -nc --arg m "$capmsg" '{systemMessage:$m}' 2>/dev/null || true
  log_idl cleared "cap-reached" "$(jq -cn --argjson n "$n" --argjson m "$MAX" --arg s "$step" \
    '{count:$n,max:$m,step:$s}' 2>/dev/null)"
  exit 0   # non-2 exit → does NOT block; the cap is a backstop, not a wedge
fi
n=$((n + 1))
printf '%s' "$n" > "${f}.count"

# ── v2 comms fold (critique B): carry any pending inbox mail in THIS block reason. ───────────────────
# session-continue is the ONE hook already blocking the in-loop desk, so folding delivery here means NO
# competing Stop blocker (no standalone mailbox-drain Stop hook, no 4-hook yield-guards, no wall-clock
# TTL). The lag-ack (promote .acked=.seen) already ran UNCONDITIONALLY above; here we only TAKE this
# cycle's NEW mail with ack_now=0 (the Stop channel is less certain than additionalContext, so the
# cc-inbox-guard's .acked watch is the backstop). The lib is already sourced and $_ouid computed above;
# a take is confined HERE because its body is about to be delivered in the decision:block reason below.
mail=""
if command -v mailbox_take >/dev/null 2>&1; then
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;; *) mail="$(mailbox_take "$_ouid" 0)" ;; esac
fi

step=$(cat "$f")
reason="🔧 Loose ends remain — do NOT stop yet. Next: ${step}

Re-arm each 🔧 turn: run \`~/.claude/hooks/session-continue.sh set \"<next step>\"\` to refresh the step AND reset the continuation counter (a fresh set zeroes .count — this is how a long grind stays under the ${MAX}-cap). When done (✅/📦), blocked on the user (⛔), or out of context (📤), run \`~/.claude/hooks/session-continue.sh clear\` so the session can close. (continuation ${n}/${MAX})"

# v2 fold: PREPEND pending peer mail (higher priority than self-continuation — a peer is trying to reach
# you). The re-arm reminder stays in $reason below it, so folding never starves the continuation counter (F14).
_sysmsg=""
if [ -n "$mail" ]; then
  _mn="$(printf '%s\n' "$mail" | grep -c '')"
  reason="📬 INBOX — ${_mn} new peer message(s), delivered as CONTEXT (never typed into your input):
${mail}

Triage these first (a reaper/supervisor page, a back-channel ping, a peer) — reply with cc-notify <uuid> \"…\" — THEN continue the loop below.

${reason}"
  # v3 D11 — the SAME human-visible line the drain hook emits, so a delivery is visible to the operator
  # on EVERY channel, not just the two additionalContext boundaries. Without this the in-loop desk (the
  # heaviest mail consumer of all) would be the one place mail still arrived invisibly.
  _mfrom="$(printf '%s\n' "$mail" | sed -n 's/^[^[]*\[\([^]]*\)\].*$/\1/p' \
            | awk '!seen[$0]++' | head -3 | paste -sd, - 2>/dev/null)"
  [ -n "$_mfrom" ] || _mfrom="peer session"
  _sysmsg="📬 ${_mn} message(s) from ${_mfrom} — delivered to this session's context (cc-thread --me to read the thread)"
fi

# decision:block blocks the stop; reason is fed back to the model as the next turn. systemMessage rides
# ALONGSIDE the block (a universal top-level field, precedent at :502) so the human sees the delivery the
# model just got — without it the in-loop desk, the heaviest mail consumer, stays the one silent channel.
if [ -n "$_sysmsg" ]; then
  jq -nc --arg r "$reason" --arg s "$_sysmsg" '{decision:"block",reason:$r,systemMessage:$s}'
else
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
fi
log_idl fired "continue" "$(jq -cn --argjson n "$n" --argjson m "$MAX" --arg s "$step" \
  --argjson mail "$([ -n "$mail" ] && printf 'true' || printf 'false')" \
  '{count:$n,max:$m,step:$s,mail_folded:$mail}' 2>/dev/null)"
exit 0
