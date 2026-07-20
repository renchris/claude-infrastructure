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
#   no-desk          role file stale/empty · no registry row · dead pid → page + budgeted replacement fire
#   budget-exhausted no-desk but ≥MAX fires in the window → page only, NEVER a respawn loop
#
# Selftest: `desk-invariant.sh --selftest` — stubbed it2/registry/transcript/wait dirs, RED-proven.
# Launchd: launchd/com.claude.desk-invariant.plist (300s StartInterval, PATH incl ~/.claude/bin).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── config (ALL overridable — the override surface is what makes --selftest hermetic) ─────────────
ROLE="${DESK_INVARIANT_ROLE:-desk}"
ROLES_DIR="${DESK_INVARIANT_ROLES_DIR:-$HOME/.claude/cc-roles}"
REGISTRY_DIR="${DESK_INVARIANT_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
PROJECT_ROOTS="${DESK_INVARIANT_PROJECT_ROOTS:-$HOME/.claude*/projects}"   # glob, intentionally unquoted below
WAIT_DIR="${DESK_INVARIANT_WAIT_DIR:-$HOME/.claude/wait-contracts}"
STATE_DIR="${DESK_INVARIANT_STATE_DIR:-$HOME/.claude/autonomy/desk-invariant}"
IDL="${DESK_INVARIANT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
IT2="${DESK_INVARIANT_IT2:-$HOME/.claude/bin/it2}"
PUSH="${DESK_INVARIANT_PUSH:-$HOME/.claude/hooks/push-critical.sh}"
NOTIFY_CMD="${DESK_INVARIANT_NOTIFY:-}"                                    # empty → builtin osascript
FIRE_BIN="${DESK_INVARIANT_FIRE_BIN:-$HOME/.claude/scripts/handoff-fire.sh}"
CANNED_CWD="${DESK_INVARIANT_CANNED_CWD:-$HOME/Development/claude-infrastructure}"
BRIEF="${DESK_INVARIANT_BRIEF:-$SCRIPT_DIR/../docs/templates/desk-boot-brief.md}"
STALE_MIN="${DESK_INVARIANT_STALE_MIN:-45}"
RESPAWN_MAX="${DESK_INVARIANT_RESPAWN_MAX:-2}"
RESPAWN_WINDOW_S="${DESK_INVARIANT_RESPAWN_WINDOW_S:-21600}"               # 6h
DEDUP_WINDOW_S="${DESK_INVARIANT_DEDUP_WINDOW_S:-3600}"                    # re-page at most 1/h per (sid,state)
REPROMPT_TEXT="${DESK_INVARIANT_REPROMPT_TEXT:-resume: read /wrap, run cc-backlog list --open, continue per /goal}"

STALE_S=$(( STALE_MIN * 60 ))
PANE=""; SID=""; PID=""   # resolved per run; SID/PANE flow into idl()

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
    osascript -e "display notification \"${msg//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

push_page() { # <msg> — Pushover break-through; a no-op (exit 0) when unarmed
  local msg="$1"
  [ -x "$PUSH" ] || return 0
  "$JQ" -cn --arg m "$msg" --arg c "$CANNED_CWD" '{message:$m,cwd:$c}' | "$PUSH" >/dev/null 2>&1 || true
}

reprompt() { # <uuid> <text> → 0 if BOTH keystrokes sent (type text, then submit with CR)
  local uuid="$1" text="$2"
  [ -x "$IT2" ] || return 1
  "$IT2" session send -s "$uuid" "$text" >/dev/null 2>&1 || return 1
  "$IT2" session send -s "$uuid" $'\r'   >/dev/null 2>&1 || return 1
  return 0
}

fire_replacement() { # fire a fresh desk from the canned brief (role-tagged). Returns handoff-fire's rc.
  # P0-14 fix: $BRIEF is a prompt-FILE path (docs/templates/desk-boot-brief.md), and handoff-fire makes
  # --prompt-file UNCONDITIONALLY required (handoff-fire.sh:617-618) — the old `DESK_BOOT_BRIEF=… --as-role
  # --cwd` argv (no --prompt-file; env var unconsumed) exited 1 in prod, so a fully-dead desk was NEVER
  # respawned (a17's "nothing can CREATE a desk" organ, silently broken). Pass the brief as --prompt-file.
  [ -f "$BRIEF" ] || { echo "desk-invariant: boot brief missing, cannot respawn: $BRIEF" >&2; return 1; }
  "$FIRE_BIN" --prompt-file "$BRIEF" --as-role "$ROLE" --cwd "$CANNED_CWD" >/dev/null 2>&1
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

# ── branch handlers ───────────────────────────────────────────────────────────────────────────────
handle_stunned() { # <idle_s>
  local idle="$1" act="page"
  if dedup_fresh stunned; then idl stunned abstained "page-once dedup (idle=${idle}s)"; return; fi
  notify "Claude desk STUNNED" "desk ${PANE} stalled ${idle}s — cap/billing/classifier error in transcript tail"
  push_page "DESK STUNNED (${ROLE}): pane ${PANE} idle ${idle}s, cap/billing/classifier error — human action likely needed"
  reprompt "$PANE" "$REPROMPT_TEXT" && act="page+reprompt"
  dedup_write stunned
  idl stunned "$act" "cap/billing/classifier stun; idle=${idle}s"
}

handle_stale() { # <idle_s>
  local idle="$1" act="reprompt"
  if dedup_fresh stale; then idl stale abstained "reprompt-once dedup (idle=${idle}s)"; return; fi
  notify "Claude desk idle" "desk ${PANE} took no turn in ${idle}s — re-prompting to re-engage"
  if ! reprompt "$PANE" "$REPROMPT_TEXT"; then
    act="reprompt-failed"
    push_page "DESK UNREACHABLE (${ROLE}): pane ${PANE} idle ${idle}s and it2 re-prompt failed — check the pane/it2 daemon"
  fi
  dedup_write stale
  idl stale "$act" "idle=${idle}s, no cap error; re-engage attempt"
}

handle_no_desk() { # <reason>
  local reason="$1"
  notify "Claude desk MISSING" "no live desk (${reason}) — bounded replacement"
  push_page "NO DESK (${ROLE}): ${reason} — firing a budgeted replacement"
  if ! respawn_budget_ok; then
    idl budget-exhausted page "respawn budget exhausted (>=${RESPAWN_MAX}/${RESPAWN_WINDOW_S}s); paged only; ${reason}"
    return
  fi
  if fire_replacement; then
    respawn_marker_write
    idl no-desk fire "fired replacement desk from canned brief; ${reason}"
  else
    idl no-desk fire-failed "handoff-fire returned nonzero; ${reason}"
  fi
}

evaluate() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true

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
  mkdir -p "$c/roles" "$c/registry" "$c/projects/p" "$c/wait" "$c/state" "$c/stubs"
  mkstub "$c/stubs/it2"; mkstub "$c/stubs/notify"; mkstub "$c/stubs/push"; mkstub "$c/stubs/fire"
  : > "$c/brief.md"
  export DESK_INVARIANT_ROLE=desk DESK_INVARIANT_ROLES_DIR="$c/roles" \
    DESK_INVARIANT_REGISTRY_DIR="$c/registry" DESK_INVARIANT_PROJECT_ROOTS="$c/projects" \
    DESK_INVARIANT_WAIT_DIR="$c/wait" DESK_INVARIANT_STATE_DIR="$c/state" DESK_INVARIANT_IDL="$c/idl.jsonl" \
    DESK_INVARIANT_IT2="$c/stubs/it2" DESK_INVARIANT_NOTIFY="$c/stubs/notify" DESK_INVARIANT_PUSH="$c/stubs/push" \
    DESK_INVARIANT_FIRE_BIN="$c/stubs/fire" DESK_INVARIANT_CANNED_CWD="$c" DESK_INVARIANT_BRIEF="$c/brief.md" \
    DESK_INVARIANT_STALE_MIN=45
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
  [ -f "$d/stunned/stubs/it2.log" ] && okp "stunned: re-prompt keystroke sent" || badp "stunned: no re-prompt"
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
  [ -f "$d/stale/stubs/it2.log" ] && okp "stale: re-prompt keystroke sent" || badp "stale: no re-prompt"
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

  echo "desk-invariant --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "desk-invariant --selftest: GREEN — healthy/stunned/stale/owned-wait/no-desk/budget-exhausted all RED-proven."
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
