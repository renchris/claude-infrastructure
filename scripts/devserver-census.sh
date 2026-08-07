#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom is
# intentional — okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B
# fails" cannot occur.
#
# devserver-census — the census + idle-reaper for per-worktree `next dev` servers.
#
# WHY THIS FILE EXISTS (backlog 2b1045b13b03, evidence docs/research/machine-lag-and-kitty-2026-08-06.md
# §7-bis(c)): `grep -rl 'next-server|pnpm dev|next dev' scripts/ bin/ hooks/` returned NOTHING. A commit
# gate is transient and self-terminating; a dev server is a PERMANENT per-worktree allocation that
# nobody collects. R1 does not bind — reaping an idle server is not admission control, and a dev server
# is not a gate.
#
# ── WHAT THE MEASUREMENT CHANGED ABOUT THE SPEC (2026-08-07, live) ────────────────────────────────
# The item asked to reap the BIGGEST server: pid 24847 at 5.82 GB, "still growing". Measured at the
# build:
#
#   pid    worktree               RSS      CPU Δ/sample   owner   browser-conns
#   24847  wt-cc-001759-77337     4.6 GB   +49 s          LIVE    0
#   42743  bs-spacing-header      444 MB   +0.04 s        none    0
#   65219  bs-deck-retarget       667 MB   +0.03 s        none    0
#   70584  wt-cc-225106-82355     661 MB   +0.03 s        LIVE    0
#
# The 4.6 GB server the item names is the BUSIEST PROCESS ON THE BOX and its worktree holds a LIVE
# claude session. Reaping by size kills the one server that is provably working — the never-reap-the-
# living violation that scripts/reap-guard.sh exists to prevent, in a new family. A SAFE reaper
# collects the two unowned servers (~1.1 GB of the 6.2 GB total), not the ~7 GB the item implies.
# That yield gap is the finding, and it is why this module leads with `census`, not `--reap`.
#
# ── THE THREE SIGNALS, AND WHY EACH IS ONE-DIRECTIONAL ────────────────────────────────────────────
# Every gate below can only ever cause a KEEP. That asymmetry is deliberate (worktree-gc.sh's gate-4
# rule: "over-matching is SAFE here, it can only ever cause a KEEP").
#
#   D-a OWNER      — a live `claude` session whose CWD is at/under the server's worktree ⇒ DEFER.
#                    CWD, never argv: a session's argv carries its whole BRIEF, so a brief that merely
#                    MENTIONS a path would convict it (memory: pgrep-f-matches-agent-briefs).
#                    ⚠️ The oracle deliberately OMITS worktree-gc's "any process holding files open
#                    under it" leg. The dev server itself holds files under its own worktree, so that
#                    leg is satisfied BY THE SUBJECT and would defer 100% of the population forever —
#                    a guard firing on its own harness.
#   D-b ACTIVITY   — browser/HMR connections ON THE DEV PORT > 0, or CPU-time delta over a sample
#                    window ≥ CC_DEVGC_CPU_EPS ⇒ DEFER (it is compiling or serving).
#                    ⚠️ Connections are a KEEP signal ONLY, never a REAP signal. Measured: ALL FOUR
#                    live servers had ZERO established connections on their dev port, including the
#                    two with live owner sessions. A browser holds the HMR socket only while a tab is
#                    open; absence is the NORMAL state and proves nothing. And the connections a naive
#                    `lsof -p <pid> -sTCP:ESTABLISHED` counts are the server's OWN internal IPC
#                    (ephemeral→ephemeral on 127.0.0.1) — so the count MUST be scoped to the listening
#                    port or it reads 1-2 for an entirely unused server.
#                    The CPU gate FLAPS, on purpose. An idle `next dev` is not quiescent — it ticks in
#                    bursts (measured 2026-08-07: bs-spacing-header gained 48 CPU-s and
#                    bs-deck-retarget 43 over one session, while reading 0.00 s across three
#                    consecutive 1 s samples). Two runs 28 s apart therefore returned `reaped=0 kept=4`
#                    and `reaped=2 kept=2` for an unchanged population. That is the gate working: a
#                    burst-sampling run errs toward KEEP, and the hourly cadence converges on a server
#                    that is genuinely quiet. A reaper that flapped toward REAP would be the bug.
#   D-c GRACE      — age < CC_DEVGC_GRACE_S ⇒ DEFER. A just-started server is indistinguishable from a
#                    finished one by quietness alone (reap-guard's R-a, same shape). bs-deck-retarget
#                    was 16 min old and perfectly quiet at the build.
#   D-d ABSTENTION — EVERY decision (reap|defer, with its cause) writes an outcome record. A silent
#                    reaper cannot be audited (reap-guard's R-c).
#
# An ORPHAN — a server whose worktree no longer exists — skips D-a/D-b/D-c: there is no owner to
# protect and no work to lose. It still records (D-d).
#
# ── DISCOVERY IS COMMAND-POSITION ANCHORED ────────────────────────────────────────────────────────
# `next dev` renames its child's process title to exactly `next-server (vX.Y.Z)`. A SUBSTRING match
# over the process table read 9 where the truth was 4 — the extra rows are agent briefs and wrapper
# argv that merely contain the string. The command must START WITH `next-server`.
#
# Usage:
#   devserver-census.sh [census]           # the default: render the join table, ACT ON NOTHING
#   devserver-census.sh census --json      # same population, machine-readable
#   devserver-census.sh decide --pid <pid> # exit 0 REAP · 10 DEFER-owner · 11 DEFER-activity
#                                          #        12 DEFER-grace · 2 usage error
#   devserver-census.sh --reap [--dry-run] # act on every REAP verdict (dry-run prints, kills nothing)
#   devserver-census.sh --selftest         # RED-provable fixtures for D-a/b/c/d
#
# Env seams (all default to the real thing; the suite shims them so it never reads the host):
#   CC_DEVGC_PS · CC_DEVGC_LSOF · CC_DEVGC_RECORDS_DIR · CC_DEVGC_GRACE_S · CC_DEVGC_SAMPLE_S
#   CC_DEVGC_CPU_EPS
set -uo pipefail

PS_CMD="${CC_DEVGC_PS:-ps}"
LSOF_CMD="${CC_DEVGC_LSOF:-lsof}"
RECORDS_DIR="${CC_DEVGC_RECORDS_DIR:-$HOME/.claude/devserver-gc}"
GRACE_S="${CC_DEVGC_GRACE_S:-1800}"     # 30 min — worktree-gc.sh's idle floor, same calibration
SAMPLE_S="${CC_DEVGC_SAMPLE_S:-5}"
CPU_EPS="${CC_DEVGC_CPU_EPS:-1}"        # CPU-seconds over the sample window that count as "working"

die() { printf 'devserver-census: %s\n' "$1" >&2; exit 2; }

# ── ps/lsof primitives ────────────────────────────────────────────────────────────────────────────

# Every live next-server pid. Command-position anchored (see header).
discover_pids() {
  "$PS_CMD" -eo pid=,command= 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' \
    | awk '{ pid=$1; $1=""; sub(/^ /,""); if ($0 ~ /^next-server([ (]|$)/) print pid }'
}

proc_cwd()   { "$LSOF_CMD" -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
proc_rss_kb(){ "$PS_CMD" -o rss= -p "$1" 2>/dev/null | tr -d ' '; }

# CPU seconds as an integer. ps renders [[dd-]hh:]mm:ss.ss — parse right-to-left so every width works.
proc_cpu_s() {
  "$PS_CMD" -o time= -p "$1" 2>/dev/null | tr -d ' ' | awk -F: '
    { n=NF; s=0; m=1
      for (i=n; i>=1; i--) { f=$i; sub(/^.*-/,"",f); s += f*m; m *= 60 }
      # a leading dd- carries days on the FIRST field
      if ($1 ~ /-/) { split($1,d,"-"); s += d[1]*86400 }
      printf "%d", s }'
}

# Elapsed seconds since start. ps etime renders [[dd-]hh:]mm:ss — same right-to-left parse.
proc_age_s() {
  "$PS_CMD" -o etime= -p "$1" 2>/dev/null | tr -d ' ' | awk -F: '
    { n=NF; s=0; m=1
      for (i=n; i>=1; i--) { f=$i; sub(/^.*-/,"",f); s += f*m; m *= 60 }
      if ($1 ~ /-/) { split($1,d,"-"); s += d[1]*86400 }
      printf "%d", s }'
}

# The TCP port this pid listens on (the dev port). First LISTEN wins; the 9xxx inspector port is
# 127.0.0.1-bound and sorts after the *:PORT dev port in lsof output, so filter to the wildcard form.
proc_port() {
  "$LSOF_CMD" -nP -p "$1" -a -i 2>/dev/null \
    | awk '/LISTEN/ { split($9,a,":"); if (a[1] == "*") { print a[2]; exit } }'
}

# Established connections ON THE DEV PORT only — never a bare per-pid count (see header D-b).
port_conns() {
  local port="$1" pid="$2" n
  [ -z "$port" ] && { printf '0'; return; }
  # NOTE: no `| grep -q` here. Under pipefail a matching grep exits first, SIGPIPEs the producer and
  # the pipeline reports 141 — the probe reads FALSE on a MATCH (memory: pipefail-inverts-early-exit).
  n=$("$LSOF_CMD" -nP -iTCP:"$port" -sTCP:ESTABLISHED 2>/dev/null | awk -v p="$pid" '$2 == p' | wc -l)
  printf '%d' "$((n))"
}

# ── D-e: the ORACLE POSITIVE CONTROL — fail-closed when lsof is inoperable ────────────────────────
# 🚨 THE PRECEDENT, ON THIS BOX: reso's worktree reaper shipped a launchd PATH without /usr/sbin.
# `lsof` lives there, not in /usr/bin. Under launchd it was command-not-found, so EVERY liveness gate
# returned empty, every worktree read as unowned, and it reaped a LIVE one (wt-cc-233227-53597,
# 2026-06-19; the account is in scripts/worktree-gc-infra-run.sh's header).
#
# This module is strictly MORE exposed: D-a (owner) and D-b (browser) BOTH resolve through lsof, and
# a silent empty from either is indistinguishable from "nobody is using it". An absent oracle would
# turn this script into a reaper that kills every dev server on the machine, including the 4.7 GB one
# with a live owner.
#
# So the oracle is POSITIVELY CONTROLLED, never merely assumed: lsof must be able to report THIS
# process's own cwd — a fact that is true by construction whenever lsof works at all. A lookup miss
# is not an absence; if the control cannot answer, the module refuses to decide (memory:
# lookup-miss-is-not-absence, positive-control-the-denominator).
ORACLE_OK=unknown
assert_oracle() {
  [ "$ORACLE_OK" = ok ] && return 0
  local self
  self="$("$LSOF_CMD" -a -p "$$" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  if [ -z "$self" ]; then
    printf 'devserver-census: REFUSING TO DECIDE — the liveness oracle (%s) cannot report this\n' "$LSOF_CMD" >&2
    printf '  process'"'"'s own cwd. lsof lives in /usr/sbin; a PATH without it makes every owner\n' >&2
    printf '  check return empty and every server look unowned. Fix PATH, do not run this blind.\n' >&2
    exit 3
  fi
  ORACLE_OK=ok
}

# ── D-a: the owner oracle ─────────────────────────────────────────────────────────────────────────
# Live `claude` process CWDs, one per line. Over-matching is safe: it can only cause a KEEP.
live_session_cwds() {
  "$LSOF_CMD" -a -d cwd -c claude -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u
}

has_live_owner() {
  local wt="$1" cwd
  [ -z "$wt" ] && return 1
  while IFS= read -r cwd; do
    [ -z "$cwd" ] && continue
    # at-or-under the worktree; the trailing-slash form stops /foo matching /foobar
    [ "$cwd" = "$wt" ] && return 0
    case "$cwd" in "$wt"/*) return 0 ;; esac
  done < <(live_session_cwds)
  return 1
}

# ── the decision ──────────────────────────────────────────────────────────────────────────────────
# Sets the globals VERDICT_CODE and VERDICT_TEXT ("<verdict> <cause>"). It deliberately prints
# NOTHING and is never called inside `$( )`: command substitution runs the function in a SUBSHELL, so
# the exit code it computes dies with the child. The first cut of this module captured it as
# out="$(decide_pid ...)" and `decide` exited 0 for EVERY verdict — including a live-owner DEFER —
# while `census`, which only reads the text, looked correct. A caller branching on that code would
# have reaped an owned server (memory: subshell-erases-the-cleanup-record).
VERDICT_CODE=0
VERDICT_TEXT=""
decide_pid() {
  local pid="$1" wt cwd age conns port cpu0 cpu1 delta
  [ -z "$pid" ] && die "decide: --pid required"
  assert_oracle
  cwd="$(proc_cwd "$pid")"
  [ -z "$cwd" ] && { VERDICT_CODE=11; VERDICT_TEXT='DEFER unreadable-cwd'; return; }

  wt="$cwd"
  if [ ! -d "$wt" ]; then
    # ORPHAN — the worktree is gone. No owner to protect, no work to lose.
    VERDICT_CODE=0; VERDICT_TEXT='REAP orphan-worktree-gone'; return
  fi

  if has_live_owner "$wt"; then
    VERDICT_CODE=10; VERDICT_TEXT='DEFER live-owner-session'; return
  fi

  age="$(proc_age_s "$pid")"; age="${age:-0}"
  if [ "$age" -lt "$GRACE_S" ]; then
    VERDICT_CODE=12; VERDICT_TEXT="$(printf 'DEFER birth-grace(%ss<%ss)' "$age" "$GRACE_S")"; return
  fi

  port="$(proc_port "$pid")"
  conns="$(port_conns "$port" "$pid")"
  if [ "$conns" -gt 0 ]; then
    VERDICT_CODE=11; VERDICT_TEXT="$(printf 'DEFER browser-attached(%s conns on :%s)' "$conns" "$port")"; return
  fi

  cpu0="$(proc_cpu_s "$pid")"; cpu0="${cpu0:-0}"
  sleep "$SAMPLE_S"
  cpu1="$(proc_cpu_s "$pid")"; cpu1="${cpu1:-0}"
  delta=$(( cpu1 - cpu0 ))
  if [ "$delta" -ge "$CPU_EPS" ]; then
    VERDICT_CODE=11; VERDICT_TEXT="$(printf 'DEFER working(+%ss cpu in %ss)' "$delta" "$SAMPLE_S")"; return
  fi

  VERDICT_CODE=0; VERDICT_TEXT="$(printf 'REAP idle-unowned(age=%ss cpuΔ=%ss)' "$age" "$delta")"
}

# ── D-d: the abstention law ───────────────────────────────────────────────────────────────────────
record() { # pid verdict cause rss_kb cwd
  mkdir -p "$RECORDS_DIR" 2>/dev/null || return 0
  printf '{"ts":"%s","pid":%s,"verdict":"%s","cause":"%s","rss_kb":%s,"cwd":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "${4:-0}" "${5:-}" \
    >> "$RECORDS_DIR/decisions.jsonl"
}

# ── the reap ──────────────────────────────────────────────────────────────────────────────────────
# TERM the whole `pnpm dev → next dev → next-server` chain root-first; killing the leaf alone lets the
# supervisor respawn it. Never SIGKILL: next dev flushes its build cache on TERM.
reap_pid() {
  local pid="$1" dry="$2" chain=() p ppid
  p="$pid"
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    # ${chain[@]+...} guard: under `set -u` bash 3.2 calls a bare "${chain[@]}" on an EMPTY array
    # unbound, so the first append aborts the script — on the reap path only, after the REAP line has
    # already printed. It read as a successful decision followed by a crash.
    chain=("$p" ${chain[@]+"${chain[@]}"})
    ppid="$("$PS_CMD" -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [ -z "$ppid" ] && break
    case "$("$PS_CMD" -o command= -p "$ppid" 2>/dev/null)" in
      *"next dev"*|*"next/dist/bin/next"*|*"pnpm dev"*|*"pnpm"*" dev"*) p="$ppid" ;;
      *) break ;;
    esac
  done
  if [ "$dry" = "yes" ]; then
    printf '    would TERM: %s\n' "${chain[*]}"
    return 0
  fi
  for p in "${chain[@]}"; do kill -TERM "$p" 2>/dev/null; done
  printf '    TERMed: %s\n' "${chain[*]}"
}

# ── census ────────────────────────────────────────────────────────────────────────────────────────
census() {
  local json="$1" pid cwd rss age port conns out verdict cause total=0 reapable=0 reclaim=0 first=1
  [ "$json" = "yes" ] && printf '['
  [ "$json" = "no" ] && printf '%-8s %-30s %9s %9s %7s %6s  %s\n' PID WORKTREE RSS_MB AGE PORT CONNS VERDICT
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    cwd="$(proc_cwd "$pid")"
    rss="$(proc_rss_kb "$pid")"; rss="${rss:-0}"
    age="$(proc_age_s "$pid")"; age="${age:-0}"
    port="$(proc_port "$pid")"
    conns="$(port_conns "$port" "$pid")"
    decide_pid "$pid"; out="$VERDICT_TEXT"
    verdict="${out%% *}"; cause="${out#* }"
    total=$(( total + 1 ))
    if [ "$verdict" = "REAP" ]; then reapable=$(( reapable + 1 )); reclaim=$(( reclaim + rss )); fi
    record "$pid" "$verdict" "$cause" "$rss" "$cwd"
    if [ "$json" = "yes" ]; then
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"pid":%s,"cwd":"%s","rss_kb":%s,"age_s":%s,"port":"%s","conns":%s,"verdict":"%s","cause":"%s"}' \
        "$pid" "$cwd" "$rss" "$age" "$port" "$conns" "$verdict" "$cause"
    else
      printf '%-8s %-30s %9s %9s %7s %6s  %s %s\n' \
        "$pid" "$(basename "${cwd:-?}")" "$(( rss / 1024 ))" "$(( age / 60 ))m" "${port:-?}" "$conns" "$verdict" "$cause"
    fi
  done < <(discover_pids)
  if [ "$json" = "yes" ]; then
    printf ']\n'
  else
    printf '\n%d server(s) · %d reapable · %d MB reclaimable\n' "$total" "$reapable" "$(( reclaim / 1024 ))"
    [ "$total" -gt 0 ] && [ "$reapable" = 0 ] && printf 'nothing to collect — every server is owned, busy, or young.\n'
  fi
  return 0
}

do_reap() {
  local dry="$1" pid out verdict cause n=0
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    decide_pid "$pid"; out="$VERDICT_TEXT"; verdict="${out%% *}"; cause="${out#* }"
    record "$pid" "$verdict" "$cause" "$(proc_rss_kb "$pid")" "$(proc_cwd "$pid")"
    if [ "$verdict" = "REAP" ]; then
      printf '  REAP pid %s — %s\n' "$pid" "$cause"
      reap_pid "$pid" "$dry"; n=$(( n + 1 ))
    else
      printf '  keep pid %s — %s\n' "$pid" "$cause"
    fi
  done < <(discover_pids)
  printf '%s: %d reaped\n' "$([ "$dry" = yes ] && echo 'dry-run' || echo 'reap')" "$n"
}

# ── selftest — a DISCRIMINATOR PAIR per gate (a suite that only asserts the KEEP half would pass
# against a module that never reaps anything) ─────────────────────────────────────────────────────
selftest() {
  local PASS=0 FAIL=0
  okp(){  printf '  ✅ %-5s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
  badp(){ printf '  ⛔ %-5s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
  # T is GLOBAL on purpose: the EXIT trap fires after this function's locals are gone.
  T="$(mktemp -d "${TMPDIR:-/tmp}/devgc-selftest.XXXXXX")" || die "mktemp failed"
  # BSD mktemp takes only TRAILING Xs — a mid-string XXXXXX mints a CONSTANT name.
  trap 'rm -rf "${T:-}"' EXIT

  # ⚠️ Assign the MODULE globals, not just the env. PS_CMD/LSOF_CMD/RECORDS_DIR bind at script load
  # from ${CC_DEVGC_*:-default}, so exporting the env vars here is too late — the first cut of this
  # suite exported them, ran against the HOST's real process table, and 2 gates reported PASS off a
  # verdict (11) they never earned. A shim that does not take effect is a vacuous pass.
  RECORDS_DIR="$T/records"; SAMPLE_S=0; GRACE_S=1800; CPU_EPS=1
  export CC_DEVGC_RECORDS_DIR="$RECORDS_DIR"
  mkdir -p "$T/wt" "$T/bin"

  # ps shim: pid 100 lives in $T/wt. Fields are driven by files so a test can flip one at a time.
  echo 0     > "$T/cpu";  echo 99999 > "$T/etime"
  cat > "$T/bin/ps" <<PSEOF
#!/usr/bin/env bash
case "\$*" in
  *"-eo pid=,command="*) echo "  100 next-server (v16.2.12)"; echo "  101 claude --brief mentions next-server here" ;;
  *"-o rss="*)   echo " 500000" ;;
  *"-o time="*)  echo " 0:\$(cat $T/cpu)" ;;
  *"-o etime="*) echo " \$(cat $T/etime)" ;;
  *"-o ppid="*)  echo " 1" ;;
  *"-o command="*) echo "next-server (v16.2.12)" ;;
esac
PSEOF
  chmod +x "$T/bin/ps"

  echo "" > "$T/owners"
  cat > "$T/bin/lsof" <<LSEOF
#!/usr/bin/env bash
case "\$*" in
  *"-d cwd -c claude"*) sed 's/^/n/' $T/owners ;;
  *"-d cwd"*)           echo "n$T/wt" ;;
  *"-iTCP:"*)           cat $T/conns 2>/dev/null ;;
  *"-i"*)               echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP *:3033 (LISTEN)" ;;
esac
LSEOF
  chmod +x "$T/bin/lsof"
  : > "$T/conns"
  PS_CMD="$T/bin/ps"; LSOF_CMD="$T/bin/lsof"

  # discovery — command-position anchor: pid 101's argv MENTIONS next-server and must NOT be counted.
  local found; found="$(discover_pids | tr '\n' ' ')"
  [ "$found" = "100 " ] && okp "D-0" "discovery is command-position anchored (a brief that MENTIONS next-server is not a server)" \
                        || badp "D-0" "discovery matched '$found' — expected only pid 100"

  # D-a discriminator pair
  echo "$T/wt" > "$T/owners"
  decide_pid 100; [ "$VERDICT_CODE" = 10 ] \
    && okp "D-a+" "live owner session at the worktree ⇒ DEFER(10)" \
    || badp "D-a+" "owner present but code=$VERDICT_CODE (expected 10)"
  echo "$T/unrelated" > "$T/owners"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-a-" "no owner ⇒ REAP(0) — the gate can CLEAR, so D-a+ is not vacuous" \
    || badp "D-a-" "no owner but code=$VERDICT_CODE (expected 0)"
  # a sibling path sharing a prefix must NOT read as an owner
  echo "${T}/wt-other" > "$T/owners"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-a/" "a prefix-sharing sibling path (\$wt-other) is not an owner of \$wt" \
    || badp "D-a/" "prefix sibling convicted the server (code=$VERDICT_CODE)"

  # D-b discriminator pair — connections
  echo "$T/unrelated" > "$T/owners"
  echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP 127.0.0.1:3033->127.0.0.1:5555 (ESTABLISHED)" > "$T/conns"
  decide_pid 100; [ "$VERDICT_CODE" = 11 ] \
    && okp "D-b+" "a browser attached on the DEV PORT ⇒ DEFER(11)" \
    || badp "D-b+" "conn present but code=$VERDICT_CODE (expected 11)"
  # a connection owned by ANOTHER pid on that port must not defer this one
  echo "node 999 chrisren 29u IPv4 0x0 0t0 TCP 127.0.0.1:3033->127.0.0.1:5555 (ESTABLISHED)" > "$T/conns"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-b/" "a conn belonging to a DIFFERENT pid does not defer this server" \
    || badp "D-b/" "another pid's conn convicted this one (code=$VERDICT_CODE)"
  : > "$T/conns"

  # D-b discriminator pair — CPU
  echo 0 > "$T/cpu"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-b0" "quiet server (cpuΔ=0) ⇒ REAP(0)" \
    || badp "D-b0" "quiet server code=$VERDICT_CODE (expected 0)"
  # make the SECOND sample larger than the first: the shim reads the file each call
  cat > "$T/bin/ps" <<PSEOF2
#!/usr/bin/env bash
case "\$*" in
  *"-eo pid=,command="*) echo "  100 next-server (v16.2.12)" ;;
  *"-o rss="*)   echo " 500000" ;;
  *"-o time="*)  n=\$(cat $T/cpu); echo " 0:\$n"; echo \$((n+30)) > $T/cpu ;;
  *"-o etime="*) echo " \$(cat $T/etime)" ;;
  *"-o ppid="*)  echo " 1" ;;
  *"-o command="*) echo "next-server (v16.2.12)" ;;
esac
PSEOF2
  chmod +x "$T/bin/ps"; echo 0 > "$T/cpu"
  decide_pid 100; [ "$VERDICT_CODE" = 11 ] \
    && okp "D-b1" "a server burning CPU between samples ⇒ DEFER(11) — the 4.6 GB incident case" \
    || badp "D-b1" "working server code=$VERDICT_CODE (expected 11)"

  # D-c discriminator pair — birth grace
  cat > "$T/bin/ps" <<PSEOF3
#!/usr/bin/env bash
case "\$*" in
  *"-eo pid=,command="*) echo "  100 next-server (v16.2.12)" ;;
  *"-o rss="*)   echo " 500000" ;;
  *"-o time="*)  echo " 0:0" ;;
  *"-o etime="*) echo " \$(cat $T/etime)" ;;
  *"-o ppid="*)  echo " 1" ;;
  *"-o command="*) echo "next-server (v16.2.12)" ;;
esac
PSEOF3
  chmod +x "$T/bin/ps"
  echo "16:00" > "$T/etime"   # 16 min — the bs-deck-retarget case
  decide_pid 100; [ "$VERDICT_CODE" = 12 ] \
    && okp "D-c+" "a 16-min-old quiet server ⇒ DEFER(12) birth-grace" \
    || badp "D-c+" "young server code=$VERDICT_CODE (expected 12)"
  echo "02:11:42" > "$T/etime"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-c-" "the same server past grace ⇒ REAP(0) — grace CLEARS, so D-c+ is not vacuous" \
    || badp "D-c-" "past-grace server code=$VERDICT_CODE (expected 0)"

  # orphan tier
  cat > "$T/bin/lsof" <<LSEOF2
#!/usr/bin/env bash
case "\$*" in
  *"-d cwd -c claude"*) echo "" ;;
  *"-d cwd"*)           echo "n$T/deleted-worktree" ;;
  *"-iTCP:"*)           echo "" ;;
  *"-i"*)               echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP *:3033 (LISTEN)" ;;
esac
LSEOF2
  chmod +x "$T/bin/lsof"
  decide_pid 100; [ "$VERDICT_CODE" = 0 ] \
    && okp "D-o" "worktree gone ⇒ REAP(0) orphan, no owner to protect" \
    || badp "D-o" "orphan code=$VERDICT_CODE (expected 0)"

  # D-e ORACLE positive control — a broken lsof must REFUSE, never read as "nobody owns it"
  cat > "$T/bin/lsof-dead" <<'DEADEOF'
#!/usr/bin/env bash
exit 127
DEADEOF
  chmod +x "$T/bin/lsof-dead"
  local rc_dead=0 rc_live=0
  ( LSOF_CMD="$T/bin/lsof-dead"; ORACLE_OK=unknown; assert_oracle ) >/dev/null 2>&1 || rc_dead=$?
  [ "$rc_dead" = 3 ] && okp "D-e+" "an inoperable lsof ⇒ REFUSE(3) — the reso PATH incident cannot recur silently" \
                     || badp "D-e+" "a dead oracle did not refuse (this is the reap-everything failure mode)"
  ( ORACLE_OK=unknown; assert_oracle ) >/dev/null 2>&1 || rc_live=$?
  [ "$rc_live" = 0 ] && okp "D-e-" "a working lsof passes the control — the refusal is not unconditional" \
                     || badp "D-e-" "the positive control cannot pass even with a working oracle"

  # D-d abstention law
  record 100 REAP test-cause 500000 "$T/wt"
  [ -s "$CC_DEVGC_RECORDS_DIR/decisions.jsonl" ] \
    && okp "D-d" "every decision writes an outcome record — no silent reap" \
    || badp "D-d" "no outcome record written"

  printf '\ndevserver-census --selftest: %d passed · %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -gt 0 ] && return 1
  return 0
}

# ── argv ──────────────────────────────────────────────────────────────────────────────────────────
MODE=census; JSON=no; DRY=no; PID=""
while [ $# -gt 0 ]; do
  case "$1" in
    census)      MODE=census ;;
    decide)      MODE=decide ;;
    --pid)       PID="${2:-}"; shift ;;
    --json)      JSON=yes ;;
    --reap)      MODE=reap ;;
    --dry-run)   DRY=yes ;;
    --selftest)  MODE=selftest ;;
    -h|--help)   sed -n '1,80p' "$0"; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done

case "$MODE" in
  census)   census "$JSON" ;;
  decide)   [ -z "$PID" ] && die "decide: --pid <pid> required"
            decide_pid "$PID"; out="$VERDICT_TEXT"
            record "$PID" "${out%% *}" "${out#* }" "$(proc_rss_kb "$PID")" "$(proc_cwd "$PID")"
            printf '%s\n' "$out"; exit "$VERDICT_CODE" ;;
  reap)     do_reap "$DRY" ;;
  selftest) selftest ;;
esac
