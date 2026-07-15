#!/bin/bash
# wait-contract-lint — the AUDITOR of the L2 wait-contract layer (the keeper of the never-wait-on-the-dead
# set). Turning its --selftest green IS the L2 bar in scripts/wait-safety-gate.sh. Sibling discipline to
# s3b-lint.sh: build to the LAW, never the grep ("criteria rot toward their grep the same way checks rot
# toward their spine") — so the discrimination lives in RED-provable fixtures the selftest SEES fire, not
# in a single grep anyone could out-write.
#
# FOUR REGISTERED CRITERIA (desk 2026-07-14, NO VETO), each RED-provable against its naive/absent form:
#   L2-a  uncontracted-wait RED   — a raw cc-await-ping / bare mailbox poll-loop owned by NOBODY lints RED;
#         a wait through cc-wait (which writes a disk contract BEFORE blocking) is GREEN. No unowned waits
#         by construction — BIND applied to waiting. BLIND TO: a wait that bypasses the primitives entirely
#         (a hand-rolled `read` on a fifo); covered by L4's roster divergence + the static poll-loop probe.
#   L2-b  deadline/on-timeout RED — a contract missing either field lints RED; an infinite wait is an
#         orphan-in-waiting. (cc-wait ALSO fail-closes at the producer; the lint is the disk backstop.)
#   L2-c  dead-waiter divergence  — the watchdog (--sweep) enforces contracts INDEPENDENT of the waiter's
#         liveness (it is a DISK scan run by the supervisor/reconciler, not by the waiter — so it survives
#         the waiter's death, which is the whole point). {pid,start-time} liveness (a recycled pid is NOT
#         the same waiter). THREE OPEN states, page-once each (declared receiver-attention/wolf-cry
#         blindness → mitigated by page-once + escalate-on-repeat, NOT re-cried every sweep):
#           · dead-waiter          → PAGE the escalation target once, escalate on repeat  (orphaned wait)
#           · live-waiter PAST due → PAGE the waiter once (it may have missed its own wake), then escalate
#           · live-waiter in-window→ silence
#         SATISFIED-but-unclosed = HYGIENE flag, never an alarm. BLIND TO: nothing L4 does not also cover
#         (a coherent-wrong roster) — this is where L2 and L4 meet.
#   L2-d  non-allowlisted action RED — on_timeout_action must be a STRUCTURED enum from {reobserve, page,
#         escalate}; anything else (a reap/kill disposition, or free prose) lints RED. An allowlist beats
#         a denylist substring scan from BOTH directions — a hostile 'cleanup' is not in the set; an
#         innocent note 'never reap' is not the action field. The S-3b law: a deadline RE-OBSERVES the
#         effect, never a disposition from silence (§3h — a busy waitee that ignores its deadline is alive).
#
# Modes:
#   wait-contract-lint.sh <file>              L2-a static lint of one script (uncontracted wait -> RED)
#   wait-contract-lint.sh --contracts <dir>   L2-b + L2-d disk validation of every contract in <dir>
#   wait-contract-lint.sh --sweep <dir>       L2-c watchdog: divergence -> page (three-state, page-once)
#   wait-contract-lint.sh --selftest          RED-prove all four + LOUD-on-indeterminate (the gate calls this)
#
# 🚨 D9 LAW: an indeterminate check that passes is indistinguishable from a working one. Every unknown here
# is a LOUD non-zero exit (2), NEVER a silent 0.
# Exit: 0 = GREEN (contracted / valid / no divergence) · 1 = RED (a registered violation) · 2 = LOUD
# indeterminate (missing/empty target). Env overrides (tests): CC_WAIT_PAGE_CMD, CC_WAIT_PAGE_TARGET.
set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

# L2-d — on_timeout_action is a STRUCTURED enum from a CLOSED ALLOWLIST, checked as a FIELD not prose.
# An allowlist beats a denylist substring scan from both directions: a hostile 'cleanup' is not in the
# set (rejected); an innocent note like 'never reap' is not the action field at all (never inspected).
ONTIMEOUT_ALLOW='reobserve page escalate'
is_allowed_action() { case " $ONTIMEOUT_ALLOW " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
ESCALATE_AT=3   # sweeps of the SAME persistent divergence before one louder escalation page

# strip whole-line comments so a `# never cc-await-ping raw` remark is not read as code — the exact bug
# reaper-horizon-lint.sh shipped with (a grep hit is file:line:CONTENT, so comments read as code).
strip_comments() { grep -vE '^[[:space:]]*#' "$1" 2>/dev/null; }

# ── L2-a: static uncontracted-wait lint ──────────────────────────────────────────────────────────────
lint_file() {
  local f="$1"
  [ -n "$f" ] && [ -f "$f" ] && [ -s "$f" ] || { echo "wait-contract-lint: CANNOT DETERMINE — no readable file '$f'"; return 2; }
  local code; code="$(strip_comments "$f")"
  local raw_wait=0 poll=0 contracted=0
  # a raw pull owned by nobody: cc-await-ping invoked directly.
  printf '%s\n' "$code" | grep -qE '\bcc-await-ping\b' && raw_wait=1
  # a hand-rolled poll-loop: a while-loop that sleeps while re-reading a mailbox / line count.
  printf '%s\n' "$code" | grep -qiE 'while.*(sleep|cc-await)' \
    && printf '%s\n' "$code" | grep -qiE 'mailbox|wc -l|tail -n|\.md"?$|ping' && poll=1
  # the contracted form: the wait goes through cc-wait (writes a contract before blocking).
  printf '%s\n' "$code" | grep -qE '\bcc-wait\b' && contracted=1

  if [ "$contracted" = 1 ]; then
    echo "  OK   L2-a  wait goes through cc-wait — a disk contract is written before the block (owned)"; return 0
  fi
  if [ "$raw_wait" = 1 ] || [ "$poll" = 1 ]; then
    echo "  RED  L2-a  UNCONTRACTED wait — a raw cc-await-ping / bare mailbox poll-loop owned by nobody. It exists"
    echo "            only in this context; when the context is gone the wait is orphaned (the 77-min strand)."
    echo "            Wrap it: cc-wait --waitee <id> --signal <s> --deadline <secs> --on-timeout '<re-observe>'"
    return 1
  fi
  echo "  OK   L2-a  no wait primitive present — nothing to own"; return 0
}

# ── L2-b + L2-d: disk contract validation ────────────────────────────────────────────────────────────
lint_contract() {
  local cf="$1" fail=0 dl ot st
  [ -f "$cf" ] && [ -s "$cf" ] || { echo "wait-contract-lint: CANNOT DETERMINE — no readable contract '$cf'"; return 2; }
  jq -e . "$cf" >/dev/null 2>&1 || { echo "  RED  L2-b  contract '$cf' is not valid JSON"; return 1; }
  dl="$(jq -r '.deadline // empty'          "$cf" 2>/dev/null)"
  ot="$(jq -r '.on_timeout_action // empty' "$cf" 2>/dev/null)"
  st="$(jq -r '.status // empty'            "$cf" 2>/dev/null)"
  if [ -z "$dl" ]; then echo "  RED  L2-b  contract $(basename "$cf") has NO deadline — an infinite wait is an orphan-in-waiting"; fail=1; fi
  if [ -z "$ot" ]; then echo "  RED  L2-b  contract $(basename "$cf") has NO on_timeout_action — expires into nothing"; fail=1; fi
  if [ -n "$ot" ] && ! is_allowed_action "$ot"; then
    echo "  RED  L2-d  contract $(basename "$cf") on_timeout_action '$ot' is not in the allowlist {$ONTIMEOUT_ALLOW}"
    echo "            — a disposition or free prose in the ACTION field. Silence is not a liveness signal"
    echo "            (S-3b/§3h): a deadline RE-OBSERVES / pages / escalates, it never reaps. (Notes go in"
    echo "            on_timeout_note, which the guard ignores — the field is checked, never prose.)"
    fail=1
  fi
  [ -n "$st" ] || { echo "  RED  L2-b  contract $(basename "$cf") has no status field"; fail=1; }
  [ "$fail" -eq 0 ] && echo "  OK   L2-bd $(basename "$cf") — deadline + allowlisted on-timeout ($ot), no silence-reap"
  return "$fail"
}

lint_contracts_dir() {
  local dir="$1" any=0 fail=0
  [ -d "$dir" ] || { echo "wait-contract-lint: CANNOT DETERMINE — no contracts dir '$dir'"; return 2; }
  local cf
  for cf in "$dir"/*.json; do
    [ -e "$cf" ] || continue
    any=1
    lint_contract "$cf" || fail=1
  done
  [ "$any" = 1 ] || { echo "  OK   L2-bd no contracts on disk — vacuously valid"; return 0; }
  return "$fail"
}

# ── L2-c: the watchdog sweep (INDEPENDENT of waiter liveness — a disk scan) ───────────────────────────
# {pid,start-time} liveness: a live pid whose start-time no longer matches was RECYCLED — a DIFFERENT
# process — so the original waiter is dead (the classic bare-pid false-liveness hole, L1-c/L2-c).
waiter_alive() { # <pid> <stored_start>  -> 0 alive(same proc) / 1 dead(gone or recycled)
  local pid="$1" stored="$2" cur
  [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cur="$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//;s/ *$//')"
  [ -n "$stored" ] || return 0                 # no stored start (legacy) — pid is alive, cannot guard
  [ "$cur" = "$stored" ]                        # same start-time = same process; mismatch = recycled = dead
}

# page = the durable divergence record. Default cc-notify (mailbox write survives a closed pane); a test
# stub via CC_WAIT_PAGE_CMD captures the call so page-once is provable.
page() { # <target> <message>
  local target="$1" msg="$2"
  local cmd="${CC_WAIT_PAGE_CMD:-cc-notify}"
  "$cmd" "$target" "$msg" >/dev/null 2>&1 || "$cmd" "$target" "$msg" || true
}

# record the page state ON the contract so the same fact is never re-cried every sweep (the desk's
# receiver-attention/wolf-cry note): page-once per state, one escalation at ESCALATE_AT, else silence.
mark_paged() { # <cf> <state> <count>
  local cf="$1" state="$2" count="$3" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/wcl-mark.XXXXXX")" || return 1
  if jq --arg s "$state" --argjson c "$count" '.paged_state=$s | .page_count=$c' "$cf" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$cf"; else rm -f "$tmp"; fi
}

sweep_one() { # <cf> -> echoes a state line; pages on divergence (page-once). returns 1 if it PAGED.
  local cf="$1"
  jq -e . "$cf" >/dev/null 2>&1 || { echo "  RED  sweep  $(basename "$cf") — not valid JSON"; return 1; }
  local st pid start dl now waiter ot
  st="$(jq -r '.status // "OPEN"' "$cf")"; pid="$(jq -r '.waiter_pid // 0' "$cf")"
  start="$(jq -r '.waiter_start // empty' "$cf")"; dl="$(jq -r '.deadline // 0' "$cf")"
  waiter="$(jq -r '.waiter // empty' "$cf")"; ot="$(jq -r '.on_timeout_action // empty' "$cf")"
  now="$(date +%s)"

  if [ "$st" != "OPEN" ]; then
    # hygiene, never an alarm: a satisfied/closed contract whose file lingers, or satisfied-but-unclosed.
    local closed; closed="$(jq -r '.closed // empty' "$cf")"
    if [ "$st" = "SATISFIED" ] && [ -z "$closed" ]; then
      echo "  hyg  sweep  $(basename "$cf") SATISFIED but unclosed — hygiene (not an alarm); prune on next pass"
    else
      echo "  ok   sweep  $(basename "$cf") status=$st — closed, no divergence"
    fi
    return 0
  fi

  local state
  if ! waiter_alive "$pid" "$start"; then state="dead-waiter"
  elif [ "$now" -gt "$dl" ] 2>/dev/null;   then state="past-deadline"
  else                                          state="ok"; fi

  if [ "$state" = "ok" ]; then
    echo "  ok   sweep  $(basename "$cf") OPEN, waiter alive, in-window — silence"; return 0
  fi

  local paged_state count
  paged_state="$(jq -r '.paged_state // empty' "$cf")"; count="$(jq -r '.page_count // 0' "$cf")"
  if [ "$paged_state" = "$state" ]; then
    count=$((count + 1)); mark_paged "$cf" "$state" "$count"
    if [ "$count" -eq "$ESCALATE_AT" ]; then
      page "${CC_WAIT_PAGE_TARGET:-$waiter}" "⛔ ESCALATION: wait-contract $(basename "$cf") STILL diverged ($state) after $count sweeps — orphaned wait needs a human owner (recovery is PAGED, never auto)."
      echo "  ⛔   sweep  $(basename "$cf") $state persists ($count sweeps) — ESCALATED once"; return 1
    fi
    echo "  ..   sweep  $(basename "$cf") $state already paged (sweep $count) — silence (no wolf-cry)"; return 0
  fi

  # a NEW divergence fact -> page ONCE.
  mark_paged "$cf" "$state" 1
  if [ "$state" = "dead-waiter" ]; then
    page "${CC_WAIT_PAGE_TARGET:-$waiter}" "⛔ DIVERGENCE: wait-contract $(basename "$cf") is OPEN but its WAITER (pid $pid) is DEAD — an orphaned wait nobody is holding. Re-observe the waitee's effect and assign a new owner (PAGED recovery, never auto-respawn)."
    echo "  ⛔   sweep  $(basename "$cf") DEAD-WAITER divergence — paged once (independent of the dead waiter)"
  else
    local waitee; waitee="$(jq -r '.waitee // "?"' "$cf" 2>/dev/null)"
    page "$waiter" "⏰ wait-contract $(basename "$cf") past deadline — you may have missed your own wake. RE-OBSERVE the waitee ($waitee) effect; on-timeout was: $ot"
    echo "  ⏰   sweep  $(basename "$cf") PAST-DEADLINE (waiter alive) — paged the waiter once"
  fi
  return 1
}

sweep_dir() {
  local dir="$1"
  [ -d "$dir" ] || { echo "wait-contract-lint: CANNOT DETERMINE — no contracts dir '$dir'"; return 2; }
  local cf any=0
  for cf in "$dir"/*.json; do
    [ -e "$cf" ] || continue
    any=1
    sweep_one "$cf" || true   # the sweep REPORTS + PAGES; a divergence is handled by paging, not by failing
  done
  [ "$any" = 1 ] || echo "  ok   sweep  no contracts on disk"
  return 0
}

# ── selftest: PROVE every criterion discriminates (SEE it fire RED). Every assertion TRAPS. ───────────
selftest() {
  local d pass=0 fail=0 rc
  d="$(mktemp -d "${TMPDIR:-/tmp}/wcl-selftest.XXXXXX")" || { echo "cannot mktemp" >&2; exit 2; }
  trap 'rm -rf "$d"' EXIT
  local SELF; SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  chk() { # <label> <want-rc> <cmd...>
    local label="$1" want="$2"; shift 2
    "$@" >/dev/null 2>&1; rc=$?
    if [ "$rc" = "$want" ]; then printf '  ok   %-54s (exit %s)\n' "$label" "$rc"; pass=$((pass+1))
    else printf '  FAIL %-54s (exit %s, wanted %s)\n' "$label" "$rc" "$want"; fail=$((fail+1)); fi
  }

  echo "wait-contract-lint --selftest — every registered criterion must be SEEN to fire:"

  # --- L2-a: uncontracted wait RED / contracted GREEN / missing LOUD -------------------------------
  cat >"$d/uncontracted.sh" <<'X'
#!/bin/bash
# a bare cc-await-ping loop owned by nobody (the desk's own listener shape, the first offender).
while :; do cc-await-ping "$MY_UUID" && break; done
X
  cat >"$d/contracted.sh" <<'X'
#!/bin/bash
# the owned form: the wait is a disk contract written before the block.
cc-wait --waitee peer --signal mailbox-line --deadline 3600 --on-timeout 're-observe peer effect'
X
  cat >"$d/nowait.sh" <<'X'
#!/bin/bash
echo "I do no waiting at all"
X
  chk "L2-a uncontracted cc-await-ping loop -> RED" 1 "$SELF" "$d/uncontracted.sh"
  chk "L2-a wait through cc-wait -> GREEN"          0 "$SELF" "$d/contracted.sh"
  chk "L2-a a script with no wait -> GREEN"         0 "$SELF" "$d/nowait.sh"
  chk "L2-a missing file -> LOUD (exit 2)"          2 "$SELF" "$d/does-not-exist.sh"

  # --- L2-b + L2-d: disk contract validation (allowlist action; the NOTE field is guard-ignored) ---
  mkdir -p "$d/good" "$d/note" "$d/nodeadline" "$d/noontimeout" "$d/reap"
  local NOW; NOW="$(date +%s)"
  printf '{"id":"g","waiter":"W","waiter_pid":%s,"waitee":"X","expected_signal":"ping","deadline":%s,"deadline_s":3600,"on_timeout_action":"reobserve","status":"OPEN"}\n' "$$" "$((NOW+3600))" >"$d/good/g.json"
  printf '{"id":"nt","waiter":"W","waitee":"X","expected_signal":"ping","deadline":%s,"on_timeout_action":"reobserve","on_timeout_note":"never reap this, seriously","status":"OPEN"}\n' "$((NOW+3600))" >"$d/note/n.json"
  printf '{"id":"n1","waiter":"W","waitee":"X","expected_signal":"ping","on_timeout_action":"reobserve","status":"OPEN"}\n' >"$d/nodeadline/n.json"
  printf '{"id":"n2","waiter":"W","waitee":"X","expected_signal":"ping","deadline":%s,"status":"OPEN"}\n' "$((NOW+3600))" >"$d/noontimeout/n.json"
  printf '{"id":"r","waiter":"W","waitee":"X","expected_signal":"ping","deadline":%s,"on_timeout_action":"reap X","status":"OPEN"}\n' "$((NOW+3600))" >"$d/reap/r.json"
  chk "L2-b complete contract -> GREEN"                0 "$SELF" --contracts "$d/good"
  chk "L2-d note 'never reap' ignored, action ok->GREEN" 0 "$SELF" --contracts "$d/note"
  chk "L2-b contract missing deadline -> RED"          1 "$SELF" --contracts "$d/nodeadline"
  chk "L2-b contract missing on-timeout -> RED"        1 "$SELF" --contracts "$d/noontimeout"
  chk "L2-d non-allowlisted (reap) action -> RED"      1 "$SELF" --contracts "$d/reap"
  chk "L2-b missing contracts dir -> LOUD"             2 "$SELF" --contracts "$d/nope"

  # --- L2-c: the watchdog sweep — divergence detected + PAGE-ONCE (no wolf-cry) ---------------------
  local pagelog="$d/pages.log"
  cat >"$d/fakepage" <<PG
#!/bin/bash
printf '%s | %s\n' "\$1" "\$2" >> "$pagelog"
PG
  chmod +x "$d/fakepage"
  # a dead-waiter OPEN contract: pid that cannot exist -> divergence.
  mkdir -p "$d/sweep"
  printf '{"id":"dead","waiter":"WD","waiter_pid":2147483641,"waiter_start":"stale","waitee":"X","expected_signal":"ping","deadline":%s,"deadline_s":3600,"on_timeout_action":"reobserve","status":"OPEN"}\n' "$((NOW+3600))" >"$d/sweep/dead.json"
  # SWEEP TWICE — a persistent dead-waiter must be paged EXACTLY ONCE across both (page-once, anti-wolf-cry).
  CC_WAIT_PAGE_CMD="$d/fakepage" "$SELF" --sweep "$d/sweep" >/dev/null 2>&1
  CC_WAIT_PAGE_CMD="$d/fakepage" "$SELF" --sweep "$d/sweep" >/dev/null 2>&1
  local npages; npages="$( [ -f "$pagelog" ] && wc -l <"$pagelog" | tr -d ' ' || echo 0 )"
  if [ "$npages" = 1 ]; then printf '  ok   %-54s (%s page)\n' "L2-c dead-waiter divergence PAGED ONCE across 2 sweeps" "$npages"; pass=$((pass+1))
  else printf '  FAIL %-54s (%s pages, wanted 1)\n' "L2-c dead-waiter page-once (no wolf-cry)" "$npages"; fail=$((fail+1)); fi
  # RED-prove the NEGATIVE of page-once: a naive sweep with no marker WOULD page twice. Assert our
  # marker is what suppresses the second — clear the marker and the second sweep pages again.
  jq 'del(.paged_state,.page_count)' "$d/sweep/dead.json" >"$d/sweep/dead.tmp" && mv "$d/sweep/dead.tmp" "$d/sweep/dead.json"
  CC_WAIT_PAGE_CMD="$d/fakepage" "$SELF" --sweep "$d/sweep" >/dev/null 2>&1
  local npages2; npages2="$( wc -l <"$pagelog" | tr -d ' ' )"
  if [ "$npages2" = 2 ]; then printf '  ok   %-54s (marker gone -> re-pages, proving the marker suppresses)\n' "L2-c page-once is the MARKER's doing, not luck"; pass=$((pass+1))
  else printf '  FAIL %-54s (%s total, wanted 2)\n' "L2-c marker-suppression proof" "$npages2"; fail=$((fail+1)); fi
  # a live-waiter, in-window OPEN contract -> NO page (silence).
  local pagelog2="$d/pages2.log"
  cat >"$d/fakepage2" <<PG
#!/bin/bash
printf '%s\n' "\$1" >> "$pagelog2"
PG
  chmod +x "$d/fakepage2"
  mkdir -p "$d/sweeplive"
  printf '{"id":"live","waiter":"WL","waiter_pid":%s,"waiter_start":%s,"waitee":"X","expected_signal":"ping","deadline":%s,"deadline_s":3600,"on_timeout_action":"reobserve","status":"OPEN"}\n' \
    "$$" "$(jq -n --arg s "$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')" '$s')" "$((NOW+3600))" >"$d/sweeplive/live.json"
  CC_WAIT_PAGE_CMD="$d/fakepage2" "$SELF" --sweep "$d/sweeplive" >/dev/null 2>&1
  local nlive; nlive="$( [ -f "$pagelog2" ] && wc -l <"$pagelog2" | tr -d ' ' || echo 0 )"
  if [ "$nlive" = 0 ]; then printf '  ok   %-54s (0 pages)\n' "L2-c live in-window waiter -> silence (no false page)"; pass=$((pass+1))
  else printf '  FAIL %-54s (%s pages, wanted 0)\n' "L2-c live in-window must be silent" "$nlive"; fail=$((fail+1)); fi

  echo "wait-contract-lint --selftest: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
  echo "wait-contract-lint --selftest: GREEN — L2-a/b/c/d all fire RED on the naive form, GREEN on the owned form."
  exit 0
}

case "${1:-}" in
  --selftest)  selftest ;;
  --contracts) shift; lint_contracts_dir "${1:-}"; exit $? ;;
  --sweep)     shift; sweep_dir "${1:-}"; exit $? ;;
  -h|--help|"") usage; exit 0 ;;
  --*)         echo "wait-contract-lint: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  *)           lint_file "$1"; exit $? ;;
esac
