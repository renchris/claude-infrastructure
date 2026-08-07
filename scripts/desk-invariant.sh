#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom is
# shellcheck disable=SC2016  # file-wide: jq program bodies are intentionally single-quoted ($x = jq var)
# desk-invariant.sh — P0-14: THE desk-existence + engagement invariant (the missing organ).
#
# Thesis (a17 §Bottom-line): the whole desk stack's only verbs are CLOSE, PAGE, and REFUSE — no
# component can CREATE a desk or RE-ENGAGE a stunned one, and every terminal branch drains to an
# absent human through a provably-disconnected page channel. This script is the one asset class the
# repo had ZERO instances of: a launchd-side, **API-budget-independent**, bash-only observer that
# asserts "a registered desk session exists AND took an assistant turn ≤N min (or holds a fresh owned
# wait-contract); else re-prompt the stunned one (OS-level, no model turn) / fire one from a canned
# brief" — the SO-6 fix: the wake path must NOT share the API failure domain it watches.
#
# DESIGN LAW (binding): PAGES + a BOUNDED re-prompt/respawn budget only. It NEVER kills a session,
# NEVER edits a session, NEVER auto-recovers beyond one keystroke / one budgeted fire. Every branch
# writes an IDL record (abstention-logged). C10: this is machinery the OPERATOR loads via launchd —
# it does not install itself.
#
# BRANCHES (each RED-proven in --selftest):
#   healthy          desk pane resolves, pid alive, assistant turn ≤N min OR fresh owned wait-contract
#   stunned          pid alive + stale + transcript tail matches cap/billing/classifier-outage text
#                    (incl. 'monthly spend limit' + 'cannot determine the safety') → OS page
#                    (osascript + push-critical if armed) + ONE re-prompt keystroke (dedup sid+state)
#   stale            pid alive + stale + no cap text → ONE re-prompt keystroke to re-engage (FM2)
#   no-desk          role file stale · no registry row · dead pid → page + budgeted replacement fire
#   budget-exhausted no-desk but ≥MAX fires in the window → page only, NEVER a respawn loop
#   not-opted-in     role file ABSENT/EMPTY and CC_DESK_OPTIN unset → abstain, zero side effects
#                    (D6: a desk that was never wired is a deliberate state, not a fault; a desk
#                    wired-THEN-broken still takes the no-desk path above — see handle_no_desk)
#
# Selftest: `desk-invariant.sh --selftest` — stubbed it2/registry/transcript/wait dirs, RED-proven.
# Launchd: launchd/com.claude.desk-invariant.plist (300s StartInterval, PATH incl ~/.claude/bin).
set -uo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled job. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: DSI_OSA_TIMEOUT_S · DSI_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
DSI_OSA_TIMEOUT_S="${DSI_OSA_TIMEOUT_S:-5}"
if [ -n "${DSI_OSA_TIMEOUT_BIN+set}" ]; then
  DSI_OSA_TB="${DSI_OSA_TIMEOUT_BIN}"
else
  DSI_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { DSI_OSA_TB="$_c"; break; }
  done
fi
dsi_osa() {
  if [ -z "$DSI_OSA_TB" ] || [ ! -x "$DSI_OSA_TB" ]; then "$@"; return $?; fi
  "$DSI_OSA_TB" -k 3 "$DSI_OSA_TIMEOUT_S" "$@"
}


SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# SCRIPT_DIR must be SYMLINK-RESOLVED: it anchors $BRIEF (the canned boot brief in the checkout),
# and the live entry point ~/.claude/scripts/desk-invariant.sh is a per-file symlink INTO the
# checkout. Unresolved, "$SCRIPT_DIR/../docs/…" became ~/.claude/docs/… — a path that does not
# exist — so fire_replacement()'s `[ -f "$BRIEF" ]` guard failed and the desk-existence invariant
# could NOT respawn a dead desk ("nothing can CREATE a desk", a17's organ, silently broken). Prod
# survived only because launchd/com.claude.desk-invariant.plist passes an absolute
# DESK_INVARIANT_BRIEF override; ANY other entry point (a hand-run sweep, a new caller) hit the
# dead default. bash 3.2-safe — macOS has no `readlink -f`.
_di_self="${BASH_SOURCE[0]}"
while [ -L "$_di_self" ]; do
  _di_dir="$(cd -P "$(dirname "$_di_self")" 2>/dev/null && pwd)" || break
  _di_self="$(readlink "$_di_self")"
  case "$_di_self" in /*) ;; *) _di_self="$_di_dir/$_di_self" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_di_self")" && pwd)"

# ── config (ALL overridable — the override surface is what makes --selftest hermetic) ─────────────
ROLE="${DESK_INVARIANT_ROLE:-desk}"
ROLES_DIR="${DESK_INVARIANT_ROLES_DIR:-$HOME/.claude/cc-roles}"
REGISTRY_DIR="${DESK_INVARIANT_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
PROJECT_ROOTS="${DESK_INVARIANT_PROJECT_ROOTS:-$HOME/.claude*/projects}"   # glob, intentionally unquoted below
WAIT_DIR="${DESK_INVARIANT_WAIT_DIR:-$HOME/.claude/wait-contracts}"
STATE_DIR="${DESK_INVARIANT_STATE_DIR:-$HOME/.claude/autonomy/desk-invariant}"
IDL="${DESK_INVARIANT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
# cc-notify — the INBOX transport for re-engagement (F7: no keystrokes into a live composer). Resolve:
# env seam → repo bin → ~/.claude/bin → PATH (mirrors the autonomy-sweep resolve order).
NOTIFY_BIN="${DESK_INVARIANT_NOTIFY_BIN:-}"
if [ -z "$NOTIFY_BIN" ]; then
  for _c in "$SCRIPT_DIR/../bin/cc-notify" "$HOME/.claude/bin/cc-notify" "$(command -v cc-notify 2>/dev/null || true)"; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NOTIFY_BIN="$_c"; break; }
  done
fi
PUSH="${DESK_INVARIANT_PUSH:-$HOME/.claude/hooks/push-critical.sh}"
NOTIFY_CMD="${DESK_INVARIANT_NOTIFY:-}"                                    # empty → builtin osascript
FIRE_BIN="${DESK_INVARIANT_FIRE_BIN:-$HOME/.claude/scripts/handoff-fire.sh}"
CANNED_CWD="${DESK_INVARIANT_CANNED_CWD:-$HOME/Development/claude-infrastructure}"
ISOLATION_SKIP="${DESK_INVARIANT_ISOLATION_SKIP:-1}"   # 1 = desk exempt from worktree isolation (fire_replacement)
BRIEF="${DESK_INVARIANT_BRIEF:-$SCRIPT_DIR/../docs/templates/desk-boot-brief.md}"
STALE_MIN="${DESK_INVARIANT_STALE_MIN:-45}"
RESPAWN_MAX="${DESK_INVARIANT_RESPAWN_MAX:-2}"
RESPAWN_WINDOW_S="${DESK_INVARIANT_RESPAWN_WINDOW_S:-21600}"               # 6h
DEDUP_WINDOW_S="${DESK_INVARIANT_DEDUP_WINDOW_S:-3600}"                    # re-page at most 1/h per (sid,state)
REPROMPT_TEXT="${DESK_INVARIANT_REPROMPT_TEXT:-resume: read /wrap, run cc-backlog list --open, continue per /goal}"
# handoff-fire writes cc-fired/<pane>.json keyed by the NEW pane on a confirmed self-retiring fire
# (T-P3-4, mark_fired_peer) — the fired-pane SOURCE for the no-desk role heal below. Overridable for
# hermetic tests.
FIRED_DIR="${DESK_INVARIANT_FIRED_DIR:-$HOME/.claude/cc-fired}"
# Age past which paged-*-stale damping markers are pruned (7d). The (sid,state) dedup markers are never
# otherwise cleaned — paged-*-stale.marker files pile up in the state dir over time.
STALE_MARKER_MAX_AGE_S="${DESK_INVARIANT_MARKER_MAX_AGE_S:-604800}"

STALE_S=$(( STALE_MIN * 60 ))
PANE=""; SID=""; PID=""   # resolved per run; SID/PANE flow into idl()
FIRE_ERR=""               # fire_replacement's captured stderr; flows into the fire-failed idl record

JQ="$(command -v jq || true)"
[ -n "$JQ" ] || { printf 'desk-invariant: jq required\n' >&2; exit 3; }

# ── read-only helpers (mirror cc-classify's transcript discipline verbatim) ───────────────────────
now_epoch() { date +%s; }
now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
alive()     { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

iso_to_epoch() { # <iso8601> → epoch seconds (empty on parse fail)
  local s="${1%%.*}"; s="${s%Z}"
  [ -z "$s" ] && return 0
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$s" +%s 2>/dev/null || true
}

find_transcript() { # <sid> → path to its .jsonl (first match across the account roots)
  local sid="$1" r f
  # shellcheck disable=SC2086  # PROJECT_ROOTS is INTENTIONALLY unquoted: word-split + expand the .claude* glob
  for r in $PROJECT_ROOTS; do
    [ -d "$r" ] || continue
    f="$(find "$r" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

last_assistant_ts() { # <jsonl> → epoch of last real assistant turn (excludes sidechain + api-error)
  local f="$1" iso
  [ -f "$f" ] || return 1
  iso="$("$JQ" -rc 'select(.type=="assistant" and (.isSidechain|not) and ((.isApiErrorMessage//false)|not)) | .timestamp' "$f" 2>/dev/null | tail -1)"
  [ -n "$iso" ] && iso_to_epoch "$iso"
}

cap_stunned() { # <jsonl> → 0 if the transcript tail shows a cap/billing/classifier-outage stun.
  # Deliberately a RAW tail grep (NOT the isApiErrorMessage signal cc-classify uses): the stun that
  # took down this very wave (a17 S-0) was a permission-CLASSIFIER outage whose text is a tool error,
  # not a structured api-error — cc-classify:77 misses it. We extend the cap set to the monthly-spend
  # /billing/classifier strings (a18 #4) precisely so this observer catches what the classifier cannot.
  local f="$1"
  [ -f "$f" ] || return 1
  tail -n 80 "$f" 2>/dev/null | grep -qiE \
    'monthly spend limit|spend limit|session limit|weekly limit|usage limit|limit ·|resets|cannot determine the safety|temporarily unavailable|billing'
}

fresh_wait_contract() { # <sid> <now> → 0 if sid owns a NOT-closed wait-contract with a future deadline
  local sid="$1" now="$2" f owner closed deadline
  [ -d "$WAIT_DIR" ] || return 1
  for f in "$WAIT_DIR"/*.json; do
    [ -f "$f" ] || continue
    owner="$("$JQ" -r '.waiter // ""' "$f" 2>/dev/null)"
    [ "$owner" = "$sid" ] || continue
    closed="$("$JQ" -r '.closed // ""' "$f" 2>/dev/null)"
    [ -z "$closed" ] || continue
    deadline="$("$JQ" -r '.deadline // 0' "$f" 2>/dev/null)"
    case "$deadline" in ''|*[!0-9]*) deadline=0 ;; esac
    [ "$deadline" -gt "$now" ] && return 0
  done
  return 1
}

# ── actuators (all best-effort + overridable; a launchd sweep must never hard-fail on their I/O) ──
idl() { # <disposition> <action> <reason>
  "$JQ" -cn --arg ts "$(now_iso)" --arg role "$ROLE" --arg pane "$PANE" --arg sid "$SID" \
    --arg disp "$1" --arg act "$2" --arg reason "$3" \
    '{ts:$ts,src:"desk-invariant",role:$role,pane:$pane,sid:$sid,disposition:$disp,action:$act,reason:$reason}' \
    >> "$IDL" 2>/dev/null || true
}

notify() { # <title> <msg> — OS-level, API-independent (osascript, or a stub in selftest)
  local title="$1" msg="$2"
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$title" "$msg" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    dsi_osa osascript -e "display notification \"${msg//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

push_page() { # <msg> — Pushover break-through; a no-op (exit 0) when unarmed
  local msg="$1"
  [ -x "$PUSH" ] || return 0
  "$JQ" -cn --arg m "$msg" --arg c "$CANNED_CWD" '{message:$m,cwd:$c}' | "$PUSH" >/dev/null 2>&1 || true
}

# v2 (critique F7 — the operator's LITERAL complaint): re-engagement must NEVER keystroke a live composer.
# The old reprompt() did `it2 session send <text>` + CR into the desk pane, gated only on assistant-idle —
# which is exactly correlated with "operator stepped away and is now back typing." A 45-min-stale pane is
# not a wedged pane; injecting there corrupts the half-typed message + submits it. So re-engagement now
# ENQUEUES the resume to the desk's OWN inbox via cc-notify (drains as context at its next boundary; a
# watcher-armed desk wakes within a poll). A stale desk with no watcher can't self-wake from a mailbox
# line — the caller pages the human instead (the only safe recovery). No keystroke path remains here.
enqueue_resume() { # <uuid> <text> → cc-notify the resume into the desk's inbox; echoes cc-notify's verdict line
  # v3 D2: address the ROLE, not the uuid we sampled at :253. The uuid is still the right thing to
  # CHECK health against (registry row, pid liveness), but by send time the desk may have self-closed
  # and repointed the role at its successor — a role-addressed send follows that, and cc-notify also
  # follows a `.forward` chain / reroutes a dead target. $1 is kept for the caller's logging contract.
  local uuid="$1" text="$2"
  [ -n "$NOTIFY_BIN" ] && [ -x "$NOTIFY_BIN" ] || { echo "cc-notify unavailable"; return 1; }
  CC_ROLES_DIR="$ROLES_DIR" "$NOTIFY_BIN" --from desk-invariant --role "$ROLE" "$text" 2>&1 \
    || { echo "cc-notify --role $ROLE failed (target ${uuid:-unknown})"; return 1; }
}

fire_replacement() { # fire a fresh desk from the canned brief (role-tagged). Returns handoff-fire's rc.
  # P0-14 fix: $BRIEF is a prompt-FILE path (docs/templates/desk-boot-brief.md), and handoff-fire makes
  # --prompt-file UNCONDITIONALLY required (handoff-fire.sh:617-618) — the old `DESK_BOOT_BRIEF=… --as-role
  # --cwd` argv (no --prompt-file; env var unconsumed) exited 1 in prod, so a fully-dead desk was NEVER
  # respawned (a17's "nothing can CREATE a desk" organ, silently broken). Pass the brief as --prompt-file.
  #
  # ANCHOR fix (2026-07-25): the SAME organ was still broken for a DIFFERENT argument. handoff-fire
  # anchors a fire to the FIRING pane and REFUSES when it cannot resolve one ("no $ITERM_SESSION_ID/
  # --session-id — would REFUSE to fire; pass --session-id or --window", handoff-fire.sh:2084/2090/2096).
  # That fail-loud is CORRECT for an interactive fire (never app-frontmost drift), but this caller is a
  # LAUNCHD job — it can never have a firing pane, so every respawn exited nonzero. Prod evidence:
  # 266 `handoff-fire returned nonzero; no-registry-row` records over 41h (2026-07-23T07:35Z →
  # 2026-07-25T01:02Z) with no desk alive the whole time. The 2026-07-25 fix passed `--window`, the
  # anchor-free surface.
  #
  # SURFACE fix (2026-07-30): `--window` cured the refusal but made every respawn open a BRAND-NEW
  # iTerm2 window — the operator's long-standing "handoffs open a whole new window instead of a ⌘D
  # split" (reported 2026-07-03, fixed on trunk 2026-07-17, reintroduced here + in cc-wave-plan on
  # 2026-07-25). Surface choice belongs at the chokepoint, not in each headless caller: handoff-fire
  # now resolves a live anchor ITSELF when the caller has none (resolve_headless_anchor → desk role
  # pane → active session → any live pane) and only mints a window when iTerm2 has no live pane at
  # all. So this caller passes NO surface flag and inherits the split-right default. The anchorless
  # refusal that caused the 41h outage cannot fire here any more (ANCHOR_INTENT=0 path).
  #
  # STDERR IS CAPTURED, not discarded: the old `2>&1 >/dev/null` is why 41h of identical failures were
  # undiagnosable from the IDL. The caller puts $FIRE_ERR into the fire-failed record.
  [ -f "$BRIEF" ] || { FIRE_ERR="boot brief missing: $BRIEF"; echo "desk-invariant: $FIRE_ERR" >&2; return 1; }
  #
  # ISOLATION EXEMPT (2026-08-01): with always-isolate on, a fresh session is routed into its own
  # worktree — wrong for the desk twice over. (a) THIS is a launchd respawn path, so each fire would
  # either land back on the shared root the policy exists to drain, or mint a NEW worktree per
  # respawn — an unbounded leak. (b) The desk is long-lived and machine-wide, not the writer session
  # the policy targets. `--in-place` is handoff-fire's exemption seam and does nothing else: it
  # prefixes CLAUDE_ISOLATION_SKIP=1 onto the typed launch line (handoff-fire.sh:3070), so the new
  # desk launches IN PLACE at $CANNED_CWD. DESK_INVARIANT_ISOLATION_SKIP=0 drops it, no code edit.
  local -a fire_args=(--prompt-file "$BRIEF" --as-role "$ROLE" --cwd "$CANNED_CWD")
  [ "$ISOLATION_SKIP" = 1 ] && fire_args+=(--in-place)
  FIRE_ERR="$("$FIRE_BIN" "${fire_args[@]}" 2>&1 >/dev/null)"
  local rc=$?
  FIRE_ERR="$(printf '%s' "$FIRE_ERR" | tr '\n' ' ' | cut -c1-300)"
  return "$rc"
}

dedup_fresh() { # <state> → 0 if we already paged (sid,state) within DEDUP_WINDOW_S
  local m="$STATE_DIR/paged-${SID}-${1}.marker" mt
  [ -f "$m" ] || return 1
  mt="$(stat -f %m "$m" 2>/dev/null || echo 0)"
  [ $(( $(now_epoch) - mt )) -lt "$DEDUP_WINDOW_S" ]
}
dedup_write()  { : > "$STATE_DIR/paged-${SID}-${1}.marker" 2>/dev/null || true; }

respawn_budget_ok() { # 0 if < RESPAWN_MAX fires in the last RESPAWN_WINDOW_S (age-keyed marker files)
  local now cnt=0 f ep
  now="$(now_epoch)"
  for f in "$STATE_DIR"/respawn-*.marker; do
    [ -f "$f" ] || continue
    ep="${f##*/respawn-}"; ep="${ep%.marker}"
    case "$ep" in ''|*[!0-9]*) continue ;; esac
    [ $(( now - ep )) -lt "$RESPAWN_WINDOW_S" ] && cnt=$((cnt+1))
  done
  [ "$cnt" -lt "$RESPAWN_MAX" ]
}
respawn_marker_write() { : > "$STATE_DIR/respawn-$(now_epoch).marker" 2>/dev/null || true; }

# ── role heal (no-desk) ─────────────────────────────────────────────────────────────────────────
# The no-desk branch fires precisely because the role pointer is stale/dead. After a SUCCESSFUL fire we
# heal it from disk truth: handoff-fire writes cc-fired/<pane>.json keyed by the NEW pane (mark_fired_peer,
# on a confirmed self-retiring fire — and THIS caller's --window fire IS one: SELF_RETIRE default + no
# --recycle ⇒ WANT_SELF_RETIRE=1, handoff-fire.sh:1612/2287), so the newest such stamp IS the desk we
# just fired. Newest-by-mtime is race-safe enough here — this daemon is the only headless-respawn firer
# and fires <=RESPAWN_MAX/6h; a rare wrong pick self-corrects on the next sweep. Healing means the NEXT
# sweep sees the new desk instead of re-firing against the same stale pointer that put us here. This is
# also defense-in-depth alongside handoff-fire's own --as-role write_role: desk-invariant does NOT export
# CC_ROLES_DIR to the fire, so this heal is what guarantees ITS $ROLES_DIR is the one repointed.
newest_fired_pane() { # → echo the UUID of handoff-fire's most-recent cc-fired stamp, or nothing
  local f newest="" newest_mt=0 mt pane
  [ -d "$FIRED_DIR" ] || return 0
  for f in "$FIRED_DIR"/*.json; do                          # glob loop (not `ls`) — mtime-max, filename-safe
    [ -f "$f" ] || continue
    mt="$(stat -f %m "$f" 2>/dev/null || echo 0)"
    case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
    [ "$mt" -ge "$newest_mt" ] && { newest_mt="$mt"; newest="$f"; }
  done
  [ -n "$newest" ] || return 0
  pane="$(basename "$newest" .json)"
  case "$pane" in ""|*[!0-9A-Fa-f-]*) return 0 ;; esac       # UUID-shaped only — never a stray filename
  printf '%s' "$pane"
}
heal_role() { # <pane> — atomically repoint $ROLES_DIR/$ROLE at pane (tmp+mv); best-effort, always 0
  local pane="$1" tmp
  [ -n "$pane" ] || return 0
  mkdir -p "$ROLES_DIR" 2>/dev/null || return 0
  tmp="$ROLES_DIR/.$ROLE.$$"
  if printf '%s\n' "$pane" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$ROLES_DIR/$ROLE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

# ── mailbox succession (v3 D1/D3) — the replacement must leave the dead box a POINTER ─────────────
# heal_role above re-addresses only ROLE-addressed mail. Two classes still strand without a mailbox
# pointer, and both are the desk's own back-channel:
#   (a) RAW-UUID sends — every back-channel ping ever fired at the dead desk carries its pane uuid, so
#       they keep enqueuing into a box nothing drains (the class that stranded 631/206/155 unread lines
#       in former-desk boxes; research doc §2 — "root cause is addressing, not transport").
#   (b) D3 REROUTES — cc-notify tees a dead target's mail to the DESK role's box. When the desk is the
#       thing that died, that box IS the dead one; cc-notify:676-679 detects this and DEFERS to exactly
#       here ("the '$DESK_ROLE' role still points at THIS dead pane … desk-invariant fires a
#       replacement"). So the reroute — the mechanism built to end stranding — was itself stranding.
# handoff-fire writes this pointer on a graceful self-close (write_forward_for) and desk-register on a
# hand REASSIGNMENT, but a desk that CRASHES/OOMs/is hard-reaped runs neither: this daemon is the only
# actor present on that path, so it is the only one that can write it.
# Writing the pointer also unlocks D1's tail migration for free — mailbox-drain.sh:98-108 adopts from any
# *.forward naming the starting session, so the successor inherits the predecessor's unconsumed lines.
# BEST-EFFORT BY CONSTRUCTION: a missing lib or unwritable dir must NEVER cost the respawn or the heal.
# $SCRIPT_DIR is symlink-RESOLVED (see the header) — unresolved, the live ~/.claude entry point would
# look for ~/.claude/hooks/… and silently find no lib, the same class of dead-default that broke $BRIEF.
# Dir seam is the lib's own CC_MAILBOX_DIR (_mbx_dir); mailbox_write_forward itself refuses a
# non-canonical uuid and a self-forward, so a role holding a name/session-id simply gets no pointer.
write_forward() { # <old-pane> <new-pane> → 0 iff a pointer was written
  local old="$1" new="$2" lib
  [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || return 1
  for lib in "$SCRIPT_DIR/../hooks/lib/mailbox-pending.sh" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
             "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
    # shellcheck disable=SC1090,SC1091
    [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
  done
  command -v mailbox_write_forward >/dev/null 2>&1 || return 1
  mailbox_write_forward "$old" "$new" 2>/dev/null || return 1
  return 0
}

# ── stale-marker sweep ──────────────────────────────────────────────────────────────────────────
# The (sid,state) dedup markers (dedup_write) are never pruned; paged-*-stale.marker files pile up in
# the state dir over time. Sweep any older than STALE_MARKER_MAX_AGE_S (mtime) on each run and log the
# count via idl. Literal-glob-safe (no nullglob): the [ -f ] guard skips the unexpanded pattern.
sweep_stale_markers() {
  local now f mt cnt=0
  [ -d "$STATE_DIR" ] || return 0
  now="$(now_epoch)"
  for f in "$STATE_DIR"/paged-*-stale.marker; do
    [ -f "$f" ] || continue
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    case "$mt" in ''|*[!0-9]*) mt="$now" ;; esac
    if [ $(( now - mt )) -gt "$STALE_MARKER_MAX_AGE_S" ]; then
      rm -f "$f" 2>/dev/null && cnt=$((cnt+1))
    fi
  done
  [ "$cnt" -gt 0 ] && idl maintenance marker-sweep "swept $cnt stale damping marker(s) >${STALE_MARKER_MAX_AGE_S}s from $STATE_DIR"
  return 0
}

# ── branch handlers ───────────────────────────────────────────────────────────────────────────────
handle_stunned() { # <idle_s>
  local idle="$1" act="page"
  if dedup_fresh stunned; then idl stunned abstained "page-once dedup (idle=${idle}s)"; return; fi
  notify "Claude desk STUNNED" "desk ${PANE} stalled ${idle}s — cap/billing/classifier error in transcript tail"
  push_page "DESK STUNNED (${ROLE}): pane ${PANE} idle ${idle}s, cap/billing/classifier error — human action likely needed"
  # F7: cap-modal → the human is paged above (the correct recovery for a usage cap); enqueue a resume to
  # the inbox too (drains if/when the modal clears). NO keystroke into a possibly-live composer.
  enqueue_resume "$PANE" "$REPROMPT_TEXT" >/dev/null 2>&1 && act="page+mailbox-resume"
  dedup_write stunned
  idl stunned "$act" "cap/billing/classifier stun; idle=${idle}s"
}

handle_stale() { # <idle_s>
  local idle="$1" act="mailbox-resume" out
  if dedup_fresh stale; then idl stale abstained "resume-once dedup (idle=${idle}s)"; return; fi
  notify "Claude desk idle" "desk ${PANE} took no turn in ${idle}s — enqueuing a resume to its inbox (no keystroke)"
  # F7: enqueue the resume to the desk's OWN inbox (no keystroke). cc-notify's verdict says whether a
  # watcher will WAKE it: "wake-path armed" → woken within a poll; else a stale desk can't self-wake from a
  # mailbox line, so PAGE the human (the only safe recovery — never keystroke a possibly-live composer).
  out="$(enqueue_resume "$PANE" "$REPROMPT_TEXT")"
  if printf '%s' "$out" | grep -q 'wake-path armed'; then
    act="mailbox-resume+wake"
  else
    act="mailbox-resume+page"
    push_page "DESK IDLE (${ROLE}): pane ${PANE} idle ${idle}s — resume enqueued to its inbox but NO watcher armed to wake it; re-engage it (it will otherwise drain on its next turn)"
  fi
  dedup_write stale
  idl stale "$act" "idle=${idle}s, no cap error; inbox resume (no keystroke — F7)"
}

handle_no_desk() { # <reason>
  local reason="$1"
  # ── OPT-IN GATE (D6, 2026-08-07): a desk that was NEVER WIRED is not a fault ────────────────────
  # This script was written when a desk was assumed. Under the deskless model an ABSENT role file is
  # the operator's DELIBERATE state, not a broken one — so enforcing against it means this launchd
  # job pages every 5 minutes and fires a budgeted replacement desk at a machine that asked for none.
  # (It is unloaded on this box today, which is the only reason that has not happened; it is a
  # loaded-later landmine, and "currently inert" is not a design.) Enforcement is therefore for those
  # who opted IN: export CC_DESK_OPTIN=1 to assert "a desk must exist here" and get every branch below.
  #
  # THE DISTINCTION IS THE DESIGN POINT, and it is why the gate keys on the ROLE FILE and not on the
  # caller's $reason string:
  #   ABSENT or EMPTY role file  → never wired → not opted in → abstain (this branch).
  #   PRESENT but stale/dead     → wired THEN BROKEN → an opted-in fault → the legacy path below,
  #                                unchanged (page + budgeted replacement fire). Someone registered a
  #                                desk here; its pointer rotting is exactly the incident this organ
  #                                exists for, and swallowing it would be a silent loss.
  # Resolved with evaluate()'s own idiom (head -1 | tr -d space) rather than trusting $PANE, so a
  # direct caller of this function gets the same verdict as one that came through evaluate().
  # Returns BEFORE the dedup marker, the page, the respawn budget and the fire — an abstention must
  # leave no state behind, or the first opted-in run would inherit a consumed budget it never spent.
  local role_file="$ROLES_DIR/$ROLE" role_holder=""
  [ -f "$role_file" ] && role_holder="$(head -1 "$role_file" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$role_holder" ] && [ "${CC_DESK_OPTIN:-0}" != 1 ]; then
    idl not-opted-in abstained \
      "verdict=not-opted-in — no desk role at $role_file and CC_DESK_OPTIN unset; desk enforcement is opt-in (${reason})"
    return 0
  fi
  # PAGE DEDUP: no-desk is a RECURRING 5-min poll, so an unpaced page here is a storm — the stunned/
  # stale branches already dedup (dedup_fresh/dedup_write) and this one did not. SID is empty in the
  # no-desk branch (no registry row to read one from), so the marker keys on the PANE — the only stable
  # identifier a missing desk has. Cf. memory blind-check-generators-stdin-and-sid-keys: an idempotency
  # marker for a RECURRING event must be event-keyed, never subject-keyed-by-something-absent.
  local dkey="nodesk-${PANE:-none}"
  if ! dedup_fresh "$dkey"; then
    notify "Claude desk MISSING" "no live desk (${reason}) — bounded replacement"
    push_page "NO DESK (${ROLE}): ${reason} — firing a budgeted replacement"
    dedup_write "$dkey"
  fi
  if ! respawn_budget_ok; then
    idl budget-exhausted page "respawn budget exhausted (>=${RESPAWN_MAX}/${RESPAWN_WINDOW_S}s); paged only; ${reason}"
    return
  fi
  # BUDGET CONSUMES ON ATTEMPT, NOT ON SUCCESS (2026-07-25). The marker used to be written only inside
  # the success branch, so a PERMANENTLY-FAILING fire consumed no budget and respawn_budget_ok never
  # tripped — the exact opposite of the DESIGN LAW ("a BOUNDED re-prompt/respawn budget only … NEVER a
  # respawn loop"). Prod: 266 attempts against a designed ceiling of RESPAWN_MAX=2 per 6h, because every
  # one of them failed. The bound must cover the failure mode it exists to bound, so the marker is
  # written BEFORE the attempt and both outcomes consume it.
  respawn_marker_write
  if fire_replacement; then
    # Heal the role pointer at the freshly fired desk (read from handoff-fire's cc-fired stamp) so the
    # NEXT sweep sees the new desk instead of re-firing against the stale pointer that put us here.
    local pane; pane="$(newest_fired_pane)"
    if [ -n "$pane" ]; then
      # MAIL BEFORE ROLE (deliberate order): the forward is written FIRST because the two writes fail
      # asymmetrically. A pointer without a healed role still routes mail correctly (cc-notify and the
      # reroute both resolve the chain), whereas a healed role without a pointer is precisely the strand
      # this fixes — so if the process dies between the two, lose the cheaper half. $PANE is the DEAD
      # desk (evaluate() resolved it from the role file before dispatching here); it is empty only on the
      # role-file-missing-or-empty reason, where there is no predecessor box to point anywhere.
      local fwd=""
      if [ -n "$PANE" ] && write_forward "$PANE" "$pane"; then fwd="; mail forwarded $PANE -> $pane"; fi
      heal_role "$pane"
      idl no-desk fire "fired replacement desk from canned brief (headless; anchor resolved at the chokepoint, split-right); role $ROLE healed -> $pane${fwd}; ${reason}"
    else
      idl no-desk fire "fired replacement desk from canned brief (headless; anchor resolved at the chokepoint, split-right); no cc-fired stamp yet to heal role; ${reason}"
    fi
  else
    idl no-desk fire-failed "handoff-fire returned nonzero: ${FIRE_ERR:-<no stderr captured>}; ${reason}"
  fi
}

evaluate() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true

  sweep_stale_markers   # hygiene: prune paged-*-stale damping markers >7d (best-effort; logs iff >0)

  PANE="$(head -1 "$ROLES_DIR/$ROLE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$PANE" ] || { handle_no_desk "role-file-missing-or-empty ($ROLES_DIR/$ROLE)"; return; }

  local row="$REGISTRY_DIR/$PANE.json"
  [ -f "$row" ] || { handle_no_desk "no-registry-row pane=$PANE"; return; }

  SID="$("$JQ" -r '.session_id // .sessionId // ""' "$row" 2>/dev/null)"
  PID="$("$JQ" -r '(.pid // "")|tostring' "$row" 2>/dev/null)"
  alive "$PID" || { handle_no_desk "dead-pid pid=$PID pane=$PANE"; return; }

  local now tj lat idle
  now="$(now_epoch)"
  tj="$(find_transcript "$SID" 2>/dev/null || true)"
  lat="$(last_assistant_ts "$tj" 2>/dev/null || true)"
  if [ -n "$lat" ]; then idle=$(( now - lat )); else idle=-1; fi

  # healthy: a recent real assistant turn, OR a fresh owned wait-contract (a healthy owned-wait desk)
  if [ "$idle" -ge 0 ] && [ "$idle" -le "$STALE_S" ]; then
    idl healthy none "assistant turn ${idle}s ago (<= ${STALE_MIN}m)"; return
  fi
  if fresh_wait_contract "$SID" "$now"; then
    idl healthy none "fresh owned wait-contract (idle=${idle}s)"; return
  fi

  # not healthy: alive but stale (or transcript unreadable) → re-engage, escalating on a cap stun
  if [ -n "$tj" ] && cap_stunned "$tj"; then handle_stunned "$idle"; else handle_stale "$idle"; fi
}

# ════ selftest — register-criteria-FIRST: every branch RED-proves against stubbed dirs ════════════
PASS=0; FAIL=0
okp()  { printf '  ok   %-58s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %-58s\n' "$1"; FAIL=$((FAIL+1)); }

# shellcheck disable=SC2317  # selftest helpers are reached only via the --selftest dispatch
mkstub() { # <path> — an executable that appends its argv to <path>.log and exits 0
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s.log"\nexit 0\n' "$1"; } > "$1"
  chmod +x "$1"
}
# shellcheck disable=SC2317
mkrow() { # <casedir> <uuid> <sid> <pid> <cwd>
  "$JQ" -cn --arg u "$2" --arg s "$3" --argjson p "$4" --arg c "$5" \
    '{paneUUID:$u,name:"t",cwd:$c,account:"a",pid:$p,startedAt:0,session_id:$s}' > "$1/registry/$2.json"
}
# shellcheck disable=SC2317
mk_transcript() { # <file> <iso-ts> [<cap-tail-text>]
  mkdir -p "$(dirname "$1")"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$2" > "$1"
  [ -n "${3:-}" ] && printf '{"type":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$3" >> "$1"
  return 0
}
# shellcheck disable=SC2317
setup_case() { # <casedir> — build stubs+dirs, export the full override surface
  local c="$1"
  mkdir -p "$c/roles" "$c/registry" "$c/projects/p" "$c/wait" "$c/state" "$c/stubs" "$c/fired"
  mkstub "$c/stubs/it2"; mkstub "$c/stubs/notify"; mkstub "$c/stubs/push"; mkstub "$c/stubs/fire"
  # cc-notify stub (F7 inbox transport): log argv AND emit the "wake-path armed" verdict handle_stale greps.
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s/stubs/ccnotify.log"\n' "$c"
    printf 'echo "cc-notify: delivered to inbox [T] (live session, wake-path armed)" >&2\nexit 0\n'; } > "$c/stubs/ccnotify"
  chmod +x "$c/stubs/ccnotify"
  : > "$c/brief.md"
  export DESK_INVARIANT_ROLE=desk DESK_INVARIANT_ROLES_DIR="$c/roles" \
    DESK_INVARIANT_REGISTRY_DIR="$c/registry" DESK_INVARIANT_PROJECT_ROOTS="$c/projects" \
    DESK_INVARIANT_WAIT_DIR="$c/wait" DESK_INVARIANT_STATE_DIR="$c/state" DESK_INVARIANT_IDL="$c/idl.jsonl" \
    DESK_INVARIANT_IT2="$c/stubs/it2" DESK_INVARIANT_NOTIFY="$c/stubs/notify" DESK_INVARIANT_PUSH="$c/stubs/push" \
    DESK_INVARIANT_NOTIFY_BIN="$c/stubs/ccnotify" \
    DESK_INVARIANT_FIRE_BIN="$c/stubs/fire" DESK_INVARIANT_CANNED_CWD="$c" DESK_INVARIANT_BRIEF="$c/brief.md" \
    DESK_INVARIANT_FIRED_DIR="$c/fired" DESK_INVARIANT_STALE_MIN=45
  # HERMETICITY (mandatory once the no-desk path writes a mailbox pointer): the forward write goes
  # through the mailbox lib, whose only dir seam is CC_MAILBOX_DIR (_mbx_dir, default ~/.claude/mailbox).
  # Unset, `--selftest` would drop `.forward` pointers into the OPERATOR'S LIVE mailbox — a selftest
  # mutating production state.
  export CC_MAILBOX_DIR="$c/mailbox"
}
# shellcheck disable=SC2317
disp_of() { tail -1 "$1/idl.jsonl" 2>/dev/null | "$JQ" -r '.disposition' 2>/dev/null; }

# shellcheck disable=SC2317
selftest() {
  local fresh stale rc
  # d/sp are script-scope (NOT local): the EXIT trap fires after this function returns, where a
  # `local` would be out of scope → `set -u` unbound. Guarded with ${:-} for belt-and-suspenders.
  d="$(mktemp -d "${TMPDIR:-/tmp}/desk-invariant-selftest.XXXXXX")" || { echo "mktemp failed"; exit 1; }
  fresh="$(date -u -v-1M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  stale="$(date -u -v-60M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2000-01-01T00:00:00Z)"
  sleep 300 & sp=$!
  disown "$sp" 2>/dev/null || true   # keep the trap-kill from printing a job-control "Terminated" line
  trap 'kill "${sp:-}" 2>/dev/null; rm -rf "${d:-}"' EXIT
  echo "desk-invariant --selftest — every branch must RED-prove:"

  # 1. HEALTHY — alive pid + fresh assistant turn → exit 0, no reprompt, no fire
  ( setup_case "$d/healthy"
    printf 'U-HEALTHY\n' > "$d/healthy/roles/desk"
    mkrow "$d/healthy" U-HEALTHY S1 "$sp" "$d/healthy"
    mk_transcript "$d/healthy/projects/p/S1.jsonl" "$fresh"
    "$SELF" ); rc=$?
  [ "$rc" -eq 0 ] && okp "healthy: exit 0" || badp "healthy: exit $rc (want 0)"
  [ "$(disp_of "$d/healthy")" = healthy ] && okp "healthy: idl disposition=healthy" || badp "healthy: idl disposition=$(disp_of "$d/healthy")"
  [ ! -f "$d/healthy/stubs/it2.log" ] && okp "healthy: NO re-prompt" || badp "healthy: re-prompted a healthy desk"
  [ ! -f "$d/healthy/stubs/fire.log" ] && okp "healthy: NO fire" || badp "healthy: fired against a healthy desk"

  # 2. STUNNED — alive pid + stale turn + cap text → page + reprompt (dedup sid+state)
  ( setup_case "$d/stunned"
    printf 'U-STUN\n' > "$d/stunned/roles/desk"
    mkrow "$d/stunned" U-STUN S2 "$sp" "$d/stunned"
    mk_transcript "$d/stunned/projects/p/S2.jsonl" "$stale" "reached the monthly spend limit for this account"
    "$SELF" )
  [ "$(disp_of "$d/stunned")" = stunned ] && okp "stunned: idl disposition=stunned" || badp "stunned: disposition=$(disp_of "$d/stunned")"
  [ -f "$d/stunned/stubs/ccnotify.log" ] && okp "stunned: inbox resume enqueued (cc-notify)" || badp "stunned: no inbox resume"
  [ ! -f "$d/stunned/stubs/it2.log" ] && okp "stunned: NO keystroke into the live composer (F7)" || badp "stunned: KEYSTROKED a live composer (F7 regression)"
  [ -f "$d/stunned/stubs/push.log" ] && okp "stunned: OS/push page fired" || badp "stunned: no page"
  ( setup_case "$d/stunned"      # second sweep, same (sid,state) → dedup abstains
    printf 'U-STUN\n' > "$d/stunned/roles/desk"
    mkrow "$d/stunned" U-STUN S2 "$sp" "$d/stunned"
    mk_transcript "$d/stunned/projects/p/S2.jsonl" "$stale" "reached the monthly spend limit for this account"
    "$SELF" )
  [ "$(disp_of "$d/stunned")" = stunned ] && [ "$(tail -1 "$d/stunned/idl.jsonl" | "$JQ" -r .action)" = abstained ] \
    && okp "stunned: page-once dedup on the 2nd sweep" || badp "stunned: dedup did not fire"

  # 3. STALE — alive pid + stale turn + NO cap text → reprompt (re-engage), no fire
  ( setup_case "$d/stale"
    printf 'U-STALE\n' > "$d/stale/roles/desk"
    mkrow "$d/stale" U-STALE S3 "$sp" "$d/stale"
    mk_transcript "$d/stale/projects/p/S3.jsonl" "$stale"
    "$SELF" )
  [ "$(disp_of "$d/stale")" = stale ] && okp "stale: idl disposition=stale" || badp "stale: disposition=$(disp_of "$d/stale")"
  [ -f "$d/stale/stubs/ccnotify.log" ] && okp "stale: inbox resume enqueued (cc-notify, no keystroke)" || badp "stale: no inbox resume"
  [ ! -f "$d/stale/stubs/it2.log" ] && okp "stale: NO keystroke into the live composer (F7)" || badp "stale: KEYSTROKED a live composer (F7 regression)"
  [ ! -f "$d/stale/stubs/fire.log" ] && okp "stale: NO fire (desk is alive)" || badp "stale: fired against a live desk"

  # 4. HEALTHY via owned wait-contract — stale turn but a fresh open wait-contract it owns
  ( setup_case "$d/wait"
    printf 'U-WAIT\n' > "$d/wait/roles/desk"
    mkrow "$d/wait" U-WAIT S4 "$sp" "$d/wait"
    mk_transcript "$d/wait/projects/p/S4.jsonl" "$stale"
    "$JQ" -cn --arg w S4 --argjson dl "$(( $(date +%s) + 3600 ))" '{waiter:$w,deadline:$dl,status:"OPEN"}' > "$d/wait/wait/c.json"
    "$SELF" )
  [ "$(disp_of "$d/wait")" = healthy ] && okp "owned-wait: stale-but-waiting desk is healthy" || badp "owned-wait: disposition=$(disp_of "$d/wait")"
  [ ! -f "$d/wait/stubs/it2.log" ] && okp "owned-wait: NO re-prompt (healthy owned wait)" || badp "owned-wait: re-prompted a waiting desk"

  # 5. NO-DESK — role points at a UUID with no registry row → page + budgeted fire + marker
  ( setup_case "$d/absent"
    printf 'U-GONE\n' > "$d/absent/roles/desk"
    "$SELF" )
  [ "$(disp_of "$d/absent")" = no-desk ] && okp "no-desk: idl disposition=no-desk" || badp "no-desk: disposition=$(disp_of "$d/absent")"
  [ -f "$d/absent/stubs/fire.log" ] && okp "no-desk: replacement fire invoked" || badp "no-desk: no fire"
  ls "$d/absent/state"/respawn-*.marker >/dev/null 2>&1 && okp "no-desk: respawn budget marker written" || badp "no-desk: no respawn marker"

  # 6. BUDGET-EXHAUSTED — no-desk but MAX fresh respawn markers already present → page only, NO fire
  ( setup_case "$d/budget"
    printf 'U-GONE2\n' > "$d/budget/roles/desk"
    : > "$d/budget/state/respawn-$(date +%s).marker"
    : > "$d/budget/state/respawn-$(( $(date +%s) - 5 )).marker"
    "$SELF" )
  [ "$(disp_of "$d/budget")" = budget-exhausted ] && okp "budget-exhausted: disposition=budget-exhausted" || badp "budget-exhausted: disposition=$(disp_of "$d/budget")"
  [ ! -f "$d/budget/stubs/fire.log" ] && okp "budget-exhausted: NO fire (respawn loop refused)" || badp "budget-exhausted: fired past budget"

  # 7. NO-DESK SUCCESSION — a UUID-keyed dead desk + a cc-fired stamp → the dead box becomes a POINTER
  # (v3 D1/D3). Case 5 above cannot cover this: its role holder is a NAME and its stub leaves no stamp,
  # so there is neither a canonical predecessor nor a successor to point at.
  ( setup_case "$d/succ"
    printf '11111111-2222-3333-4444-555555555555\n' > "$d/succ/roles/desk"
    # stub ALSO models handoff-fire's mark_fired_peer stamp — desk-invariant's only successor source
    { printf '#!/bin/bash\n'
      printf 'printf "%%s\\n" "$*" >> "%s/stubs/fire.log"\n' "$d/succ"
      printf 'mkdir -p "%s/fired"\n' "$d/succ"
      printf 'printf "{\\"paneUUID\\":\\"abcdef01-2345-6789-abcd-ef0123456789\\"}\\n" > "%s/fired/abcdef01-2345-6789-abcd-ef0123456789.json"\n' "$d/succ"
      printf 'exit 0\n'; } > "$d/succ/stubs/fire"
    chmod +x "$d/succ/stubs/fire"
    "$SELF" )
  [ "$(cat "$d/succ/mailbox/11111111-2222-3333-4444-555555555555.forward" 2>/dev/null)" = abcdef01-2345-6789-abcd-ef0123456789 ] \
    && okp "no-desk: dead desk's box points at the successor (D1/D3)" \
    || badp "no-desk: NO .forward — raw-uuid sends and D3 reroutes strand in the dead box"
  [ "$(cat "$d/succ/roles/desk" 2>/dev/null)" = abcdef01-2345-6789-abcd-ef0123456789 ] \
    && okp "no-desk: role healed alongside the mail pointer" \
    || badp "no-desk: role=$(cat "$d/succ/roles/desk" 2>/dev/null) (mail write must not cost the heal)"

  # 8. NOT-OPTED-IN (D6) — NO role file at all + CC_DESK_OPTIN unset → abstain with ZERO side effects.
  # Distinct from case 5 by exactly one thing: case 5's role file EXISTS and holds a dead pane (wired
  # then broken = an opted-in fault), this one was never wired. The opt-in control below re-runs the
  # SAME fixture with the switch on, so the absence assertions here cannot pass vacuously.
  ( setup_case "$d/optout"
    unset CC_DESK_OPTIN
    "$SELF" )
  [ "$(disp_of "$d/optout")" = not-opted-in ] && okp "not-opted-in: idl disposition=not-opted-in" \
    || badp "not-opted-in: disposition=$(disp_of "$d/optout")"
  [ ! -f "$d/optout/stubs/fire.log" ] && [ ! -f "$d/optout/stubs/push.log" ] \
    && okp "not-opted-in: NO page and NO fire (zero side effects)" \
    || badp "not-opted-in: paged/fired at a machine that never wired a desk"
  ls "$d/optout/state"/respawn-*.marker >/dev/null 2>&1 \
    && badp "not-opted-in: consumed respawn budget on an abstention" \
    || okp "not-opted-in: respawn budget NOT consumed"

  # 9. OPT-IN CONTROL — same never-wired fixture, CC_DESK_OPTIN=1 ⇒ every legacy branch is back.
  ( setup_case "$d/optin"
    export CC_DESK_OPTIN=1
    "$SELF" )
  [ "$(disp_of "$d/optin")" = no-desk ] && [ -f "$d/optin/stubs/fire.log" ] \
    && okp "opt-in: CC_DESK_OPTIN=1 restores the legacy no-desk fire" \
    || badp "opt-in: disposition=$(disp_of "$d/optin") fire=$([ -f "$d/optin/stubs/fire.log" ] && echo yes || echo no)"

  echo "desk-invariant --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "desk-invariant --selftest: GREEN — healthy/stunned/stale/owned-wait/no-desk/budget-exhausted/succession/not-opted-in all RED-proven."
}

# ── companion check: the desk self-recycle ARMEDNESS invariant ────────────────────────────────────
# Orthogonal to desk EXISTENCE (this script's subject): a desk can be perfectly alive and engaged
# while its deterministic self-recycle is armed-but-inert, which is exactly how waiting-recycle.sh
# reached 5425 abstains / 0 fires unnoticed. Wired HERE rather than as its own launchd job on
# purpose: com.claude.desk-invariant.plist is already bootstrapped, and adding a plist is a C10
# operator step — this fix must not sit behind one to go live. Best-effort by construction: it pages
# through its own channel and must never alter this script's exit semantics.
recycle_invariant_check() {
  local s="${DESK_INVARIANT_RECYCLE_CHECK:-$SCRIPT_DIR/desk-recycle-invariant.sh}"
  [ -x "$s" ] || return 0
  "$s" --once >/dev/null 2>&1 || true
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--once)  evaluate; recycle_invariant_check ;;
  *)          printf 'desk-invariant: unknown arg %s (use --once | --selftest)\n' "$1" >&2; exit 2 ;;
esac
