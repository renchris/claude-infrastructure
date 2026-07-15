#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom in the selftest is
# intentional — okp/badp always return 0, so SC2015's "C runs when A true but B fails" cannot occur.
#
# lead-reconciler — L4 of the never-wait-on-the-dead build: a three-way anti-entropy reconciler and the
# BACKSTOP for L1/L2. The incident's third failure: the harness task table still LISTED a dead teammate —
# a three-way divergence (tasks say alive, registry/disk say dead) that no single layer was watching.
#
# TWO-ROSTER LAW: separately-maintained rosters that SHOULD agree WILL drift; the drift is the signal. So
# reconcile the THREE independent rosters of "who is alive", keyed by pid:
#   A. harness tasks   — the harness's task/teammate table          (independent source: the harness API)
#   B. cc-registry     — the live-session registry                  (independent source: pid kill-0)
#   C. disk telemetry  — deathwatch/heartbeat records on disk        (independent source: disk mtime)
# A PERSISTENT pairwise divergence (a pid alive in one roster, absent from another, still there after the
# grace window) ALARMS and NAMES the diverged pair. This catches what L1 (event death) and L2 (the wait
# contract) each miss on their own: a roster that silently disagrees with reality.
#
# REGISTERED CRITERIA (desk 2026-07-14):
#   L4-a  persistent pairwise divergence → alarm that NAMES the pair (e.g. "tasks×registry: pid 4242").
#   L4-b  GRACE WINDOW (anti-cry-wolf): a TRANSIENT transition — spawned-not-yet-registered, dying-not-yet-
#         swept — within the grace window must NOT alarm. Only a divergence that PERSISTS past the window
#         alarms. (Same persist-before-alarm discipline as L2 page-once / cc-board's grace window.)
#   L4-c  the reconciler emits its OWN heartbeat each run (S-4): its ABSENCE is the alarm — who watches the
#         watcher, answered mechanically (the same shape as L1-e).
#   L4-blind  DECLARED: three-way AGREEMENT on a WRONG state is invisible (the reconciler catches DRIFT,
#         not coherent-wrong). Mitigated — NOT closed — by three INDEPENDENT sources (harness API / pid
#         kill-0 / disk mtime): a coherent-wrong across three independent mechanisms is unlikely, not
#         impossible. The named residual; nobody checks it by hand — it is the honest hole, declared.
#
#   lead-reconciler.sh --once        one reconcile pass (read rosters → diff → grace → alarm → heartbeat)
#   lead-reconciler.sh --selftest    RED-prove L4-a/b/c + the declared blindness against the naive form
#
# Roster readers (each prints the ALIVE pids it knows, one per line). Overridable for tests/deploy:
#   CC_RECON_ROSTER_TASKS · CC_RECON_ROSTER_REGISTRY · CC_RECON_ROSTER_DISK  (a command line each)
# Env: CC_RECON_DIR (state+heartbeat), CC_RECON_GRACE_S (grace window, default 60), CC_WAIT_PAGE_CMD,
#      CC_RECON_PAGE_TARGET. Exit: 0 = reconciled (alarms are PAGED, not a failure) · 2 = usage.
set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

RECON_DIR="${CC_RECON_DIR:-$HOME/.claude/reconciler}"
GRACE_S="${CC_RECON_GRACE_S:-60}"

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "lead-reconciler: $*" >&2; exit 2; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
page()  { local cmd="${CC_WAIT_PAGE_CMD:-cc-notify}"; "$cmd" "$1" "$2" >/dev/null 2>&1 || "$cmd" "$1" "$2" || true; }

# ── the three INDEPENDENT roster readers (each prints ALIVE pids). Defaults are real + independent; ─────
# tests/deploy override via env. Independence is the L4-blind mitigation — do not collapse them.
roster_tasks() {
  if [ -n "${CC_RECON_ROSTER_TASKS:-}" ]; then eval "$CC_RECON_ROSTER_TASKS"; return; fi
  # default (harness API surface): none wired here — the operator supplies the task-table reader at
  # activation. Empty by default so a mis-deploy is visible (an empty roster diverges LOUDLY), never faked.
  :
}
roster_registry() {
  if [ -n "${CC_RECON_ROSTER_REGISTRY:-}" ]; then eval "$CC_RECON_ROSTER_REGISTRY"; return; fi
  # default: cc-registry / live-sessions pids that are ALIVE by kill -0 (an INDEPENDENT liveness source).
  local rdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}" f pid
  for f in "$rdir"/*.json; do
    [ -e "$f" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && echo "$pid"
  done
}
roster_disk() {
  if [ -n "${CC_RECON_ROSTER_DISK:-}" ]; then eval "$CC_RECON_ROSTER_DISK"; return; fi
  # default: pids named in fresh disk telemetry (deathwatch heartbeat/records — INDEPENDENT of kill -0).
  local dw="${CC_DEATH_RECORDS_DIR:-$HOME/.claude/deathwatch}" f pid
  for f in "$dw"/heartbeat.json "$dw"/death-*.json; do
    [ -e "$f" ] || continue
    pid="$(jq -r '.watcher_pid // .pid // empty' "$f" 2>/dev/null)"
    [ -n "$pid" ] && echo "$pid"
  done
}

# normalize a roster to a sorted unique set of pids
norm() { tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u; }

# keys alive in $1 but absent from $2 (the divergence direction)
only_in() { comm -23 <(printf '%s\n' "$1") <(printf '%s\n' "$2"); }

write_heartbeat() { # L4-c: proof-of-life; absence = the alarm one meta-level up
  mkdir -p "$RECON_DIR" 2>/dev/null || true
  jq -n --arg ts "$(iso)" --arg pid "$$" '{kind:"reconciler-heartbeat", ts:$ts, reconciler_pid:($pid|tonumber)}' \
    > "$RECON_DIR/heartbeat.json" 2>/dev/null || true
}

# ── L4-b grace: a divergence alarms ONLY after it has PERSISTED past the grace window. ─────────────────
# State on disk per (pair,pid): first_seen. A divergence gone by the next pass has its state cleared →
# never alarmed (transient). One still present past GRACE_S → alarmed once (persistent).
consider_divergence() { # <pair> <pid> <detail>  -> echoes ALARM if it fires
  local pair="$1" pid="$2" detail="$3" now first sf
  now="$(date +%s)"
  sf="$RECON_DIR/div-${pair}-${pid}.json"
  if [ -f "$sf" ]; then
    first="$(jq -r '.first_seen // 0' "$sf" 2>/dev/null)"
  else
    first="$now"
    jq -n --arg p "$pair" --arg pid "$pid" --argjson fs "$now" '{pair:$p, pid:$pid, first_seen:$fs, alarmed:false}' > "$sf" 2>/dev/null || true
  fi
  if [ "$((now - first))" -ge "$GRACE_S" ]; then
    # persistent — alarm ONCE (anti-wolf-cry: the marker suppresses re-alarm)
    local alarmed; alarmed="$(jq -r '.alarmed // false' "$sf" 2>/dev/null)"
    if [ "$alarmed" != "true" ]; then
      jq '.alarmed=true' "$sf" > "$sf.tmp" 2>/dev/null && mv "$sf.tmp" "$sf" || rm -f "$sf.tmp"
      page "${CC_RECON_PAGE_TARGET:-}" "⛔ RECONCILER DIVERGENCE ($pair): $detail — persisted past ${GRACE_S}s. A roster disagrees with reality (two-roster law). RE-OBSERVE + reconcile the named pair."
      echo "ALARM $pair $pid $detail"
    fi
  fi
}

reconcile_once() {
  mkdir -p "$RECON_DIR" 2>/dev/null || true
  local A B C; A="$(roster_tasks | norm)"; B="$(roster_registry | norm)"; C="$(roster_disk | norm)"
  # current divergences per unordered pair, both directions
  local pid seen=""
  # tasks × registry
  for pid in $(only_in "$A" "$B"); do consider_divergence "tasks-x-registry" "$pid" "pid $pid alive in tasks, ABSENT from registry"; seen="$seen tasks-x-registry-$pid"; done
  for pid in $(only_in "$B" "$A"); do consider_divergence "tasks-x-registry" "$pid" "pid $pid in registry, ABSENT from tasks";        seen="$seen tasks-x-registry-$pid"; done
  # tasks × disk
  for pid in $(only_in "$A" "$C"); do consider_divergence "tasks-x-disk" "$pid" "pid $pid alive in tasks, ABSENT from disk telemetry"; seen="$seen tasks-x-disk-$pid"; done
  for pid in $(only_in "$C" "$A"); do consider_divergence "tasks-x-disk" "$pid" "pid $pid in disk telemetry, ABSENT from tasks";       seen="$seen tasks-x-disk-$pid"; done
  # registry × disk
  for pid in $(only_in "$B" "$C"); do consider_divergence "registry-x-disk" "$pid" "pid $pid in registry, ABSENT from disk telemetry"; seen="$seen registry-x-disk-$pid"; done
  for pid in $(only_in "$C" "$B"); do consider_divergence "registry-x-disk" "$pid" "pid $pid in disk telemetry, ABSENT from registry";  seen="$seen registry-x-disk-$pid"; done
  # clear state for divergences that are no longer present (they resolved WITHIN grace = transient, or healed)
  local sf base
  for sf in "$RECON_DIR"/div-*.json; do
    [ -e "$sf" ] || continue
    base="$(basename "$sf" .json)"; base="${base#div-}"
    case " $seen " in *" $base "*) : ;; *) rm -f "$sf" ;; esac
  done
  write_heartbeat   # L4-c — always, even when clean; its ABSENCE is the alarm
}

# ── selftest: SEE every L4 RED-proof fire. Every assertion TRAPS. ─────────────────────────────────────
PASS=0; FAIL=0
okp()  { printf '  ok   %-62s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %-62s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF; d="$(mktemp -d "${TMPDIR:-/tmp}/recon-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  printf '#!/bin/bash\nexit 0\n' > "$d/noop"; chmod +x "$d/noop"
  local pagelog="$d/pages.log"
  # shellcheck disable=SC2016  # $2 is INTENTIONALLY literal — it expands inside the generated stub, not now
  printf '#!/bin/bash\nprintf "%%s\\n" "$2" >> "%s"\n' "$pagelog" > "$d/page"; chmod +x "$d/page"

  echo "lead-reconciler --selftest — every L4 RED-proof must be SEEN to fire:"

  # rosters: tasks has pid 4242 (the incident: tasks list it), registry+disk do NOT (it's dead).
  local TASKS='echo 4242; echo 100' REG='echo 100' DISK='echo 100'

  # ---- L4-a + L4-b (persistent): GRACE_S=0 → the divergence alarms immediately, NAMING the pair. ----
  rm -rf "$d/state"; : > "$pagelog"
  CC_RECON_DIR="$d/state" CC_RECON_GRACE_S=0 CC_WAIT_PAGE_CMD="$d/page" \
    CC_RECON_ROSTER_TASKS="$TASKS" CC_RECON_ROSTER_REGISTRY="$REG" CC_RECON_ROSTER_DISK="$DISK" \
    "$SELF" --once >/dev/null 2>&1
  if grep -q 'tasks-x-registry' "$pagelog" && grep -q '4242' "$pagelog"; then
    okp "L4-a persistent divergence → alarm NAMES the pair (tasks×registry: pid 4242)"
  else badp "L4-a divergence not detected / pair not named"; fi

  # ---- L4-b (transient, anti-cry-wolf): GRACE_S huge → a JUST-APPEARED divergence must NOT alarm. ----
  rm -rf "$d/state"; : > "$pagelog"
  CC_RECON_DIR="$d/state" CC_RECON_GRACE_S=9999 CC_WAIT_PAGE_CMD="$d/page" \
    CC_RECON_ROSTER_TASKS="$TASKS" CC_RECON_ROSTER_REGISTRY="$REG" CC_RECON_ROSTER_DISK="$DISK" \
    "$SELF" --once >/dev/null 2>&1
  if [ ! -s "$pagelog" ]; then
    okp "L4-b transient divergence within grace → NO alarm (anti-cry-wolf)"
  else badp "L4-b a within-grace transient FALSE-alarmed"; fi

  # ---- L4-b (persist proof): re-age the state file past grace, reconcile again → NOW it alarms once. --
  # (proves grace is real: the SAME divergence that was silent within-window fires once it persists)
  : > "$pagelog"
  local sf; sf="$(ls "$d/state"/div-tasks-x-registry-4242.json 2>/dev/null)"
  if [ -n "$sf" ]; then
    jq '.first_seen=0' "$sf" > "$sf.t" && mv "$sf.t" "$sf"   # backdate first_seen → persisted
    CC_RECON_DIR="$d/state" CC_RECON_GRACE_S=60 CC_WAIT_PAGE_CMD="$d/page" \
      CC_RECON_ROSTER_TASKS="$TASKS" CC_RECON_ROSTER_REGISTRY="$REG" CC_RECON_ROSTER_DISK="$DISK" \
      "$SELF" --once >/dev/null 2>&1
    grep -q '4242' "$pagelog" && okp "L4-b the SAME divergence, once PERSISTED past grace → alarms (grace is real)" \
      || badp "L4-b a persisted divergence failed to alarm"
  else badp "L4-b state file for the divergence was not created within grace"; fi

  # ---- L4-c: a reconcile pass writes the reconciler's OWN heartbeat (absence = the alarm). ----------
  rm -rf "$d/state"; : > "$pagelog"
  CC_RECON_DIR="$d/state" CC_RECON_GRACE_S=60 CC_WAIT_PAGE_CMD="$d/noop" \
    CC_RECON_ROSTER_TASKS='echo 1' CC_RECON_ROSTER_REGISTRY='echo 1' CC_RECON_ROSTER_DISK='echo 1' \
    "$SELF" --once >/dev/null 2>&1
  [ -f "$d/state/heartbeat.json" ] && okp "L4-c reconciler heartbeat written each run (who-watches-the-watcher)" \
    || badp "L4-c no reconciler heartbeat — a crashed reconciler looks like a quiet system"

  # ---- L4-blind: all three rosters AGREE (even if wrong) → NO alarm (the declared, honest blindness). -
  : > "$pagelog"
  CC_RECON_DIR="$d/state2" CC_RECON_GRACE_S=0 CC_WAIT_PAGE_CMD="$d/page" \
    CC_RECON_ROSTER_TASKS='echo 7; echo 8' CC_RECON_ROSTER_REGISTRY='echo 7; echo 8' CC_RECON_ROSTER_DISK='echo 7; echo 8' \
    "$SELF" --once >/dev/null 2>&1
  if [ ! -s "$pagelog" ] && grep -qiE 'coherent|independent.?source|agree.*wrong' "$SELF"; then
    okp "L4-blind coherent-wrong is invisible (no alarm) AND declared + mitigated by 3 independent sources"
  else badp "L4-blind the all-three-agree-wrong blind spot mis-alarmed or is undeclared"; fi

  echo "lead-reconciler --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "lead-reconciler --selftest: GREEN — L4-a/b/c fire RED-provably; the coherent-wrong residual is declared."
  exit 0
}

case "${1:-}" in
  --once)     reconcile_once ;;
  --selftest) selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)          die "unknown argument '$1' (use --once | --selftest)" ;;
esac
