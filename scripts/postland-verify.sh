#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# postland-verify.sh — the ASYNC post-land full-suite net.
#
# WHY: the pre-push gate is fast-and-partial (typecheck + touched-file lint) and the FULL bats suite
# runs only nightly — a red landed at 09:00 sits unseen until 04:00. This closes that window: every
# 5 min launchd asks "is origin/main's TREE already stamped green?"; if not, it runs the full
# check-set against that exact tree. TREE-keyed, so a rebase/amend to an identical tree is free.
# CRITICAL — checks NEVER run in $REPO: its working tree IS the live ~/.claude layer (176 symlinks
# point into it), so a `checkout --detach <sha>` there would DEPLOY an untested sha to the live
# fleet. Everything runs in a disposable detached $WORKTREE (`git clean -fd` — NEVER -x).
# CHECK-SET (in $WORKTREE at the target sha, private TMPDIR + nice 10): bash -n on every tracked
# *.sh / bash-shebang file (cheap, VERDICT-AFFECTING) · `bats tests/` (THE verdict) · a whole-tree
# lint (sc) finding COUNT, recorded as shellcheck_advisory ONLY (baseline unproven, never a verdict).
# RETRY LADDER: a red suite re-runs each failing FILE alone twice more; >=2/3 fails = REPRODUCIBLE,
# 1/3 = flake (→ flakes.jsonl, excluded from the verdict; all-flake ⇒ GREEN-WITH-FLAKES).
# ON REPRODUCIBLE RED: `git bisect run` FIRST (culprit sha), then a STATE-KEYED page + backlog item
# + notification (a fixed page key gets path-dedup-swallowed for 7 days). last-green stays put.
# STATES: GREEN · RED (a named, reproducible failure) · HUNG (the suite never returned AND the
# suspect file wedges again ALONE on a pristine checkout — a proven property of the TREE: stamped,
# paged at that file, fix = timeout-wrap the un-stubbed seam, never a bisect) · CUT (truncated by a
# MACHINE event — a peer pkill, OOM, starvation: nothing was proven, never stamped green or red,
# retried next sweep, honest page + cool-off at CUT_MAX). HUNG vs CUT is the load-bearing split:
# "retry when quieter" is the right answer to one and the one answer guaranteed never to clear the
# other. Bounds: POSTLAND_SUITE_TIMEOUT_S (2700) · POSTLAND_FILE_TIMEOUT_S (300); unbounded, HUNG is
# UNPROVABLE (nothing can return 124) so every hang candidate honestly degrades to a CUT.
# Verbs: --run-if-needed (launchd) · --run <sha> · bisect <file> <good> <bad> · is-green <sha> ·
#        status · --selftest.   Kill switch: POSTLAND_VERIFY=off (runtime-read ⇒ instantly inert).
# C10: OPERATOR loads the plist (docs/activation/pending-activation/09-postland-verify-activate.sh).
set -uo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled job. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: PLV_OSA_TIMEOUT_S · PLV_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
PLV_OSA_TIMEOUT_S="${PLV_OSA_TIMEOUT_S:-5}"
if [ -n "${PLV_OSA_TIMEOUT_BIN+set}" ]; then
  PLV_OSA_TB="${PLV_OSA_TIMEOUT_BIN}"
else
  PLV_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { PLV_OSA_TB="$_c"; break; }
  done
fi
plv_osa() {
  if [ -z "$PLV_OSA_TB" ] || [ ! -x "$PLV_OSA_TB" ]; then "$@"; return $?; fi
  "$PLV_OSA_TB" -k 3 "$PLV_OSA_TIMEOUT_S" "$@"
}

# ── bounding the CHECK-SET itself ────────────────────────────────────────────────────────────────
# Separate from plv_osa above, which bounds only the notification fork. Unbounded, a suite that
# WEDGES never returns: it holds this runner's mutex until LOCK_TTL, emits no verdict, and the job
# just disappears — there is no rc to classify, so a hang is not merely misfiled, it is INVISIBLE.
# rc 124 is the bound firing, and it is the primary HUNG discriminator below. PATH alone is not
# enough: this runs under launchd, whose PATH has no Homebrew — exactly where coreutils installs
# timeout(1). Same resolution ladder as bin/it2-wrapper.
_resolve_timeout() {
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" \
           "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout \
           /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
# UNSET ⇒ resolve one. SET (including set to EMPTY) ⇒ honored verbatim, so CC_POSTLAND_TIMEOUT_BIN=
# genuinely disables bounding — `${VAR:-}` cannot tell unset from set-empty, and a seam that cannot
# turn a thing OFF is not a seam.
if [ -n "${CC_POSTLAND_TIMEOUT_BIN+set}" ]; then TIMEOUT_BIN="$CC_POSTLAND_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_timeout || true)"; fi

bounded() { # <secs> <cmd…> — rc 124 = OUR bound fired. Unbounded (never blocked) with no timeout(1).
  local secs="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 10 "$secs" "$@"   # no --foreground ⇒ its own process group ⇒ the whole bats tree
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATE="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
REPO="${CC_POSTLAND_REPO:-$HOME/Development/claude-infrastructure}"
WORKTREE="${CC_POSTLAND_WORKTREE:-$HOME/Development/.worktrees/ci-postland}"
PAGES="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"
NOTIFY_BIN="${CC_POSTLAND_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"    # author notify (best-effort)
NOTIFY_CMD="${CC_POSTLAND_NOTIFY:-}"                                   # empty → builtin osascript
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LANDLOG="${CC_POSTLAND_LANDLOG:-${LAND_LOG:-$HOME/.claude/land.log}}"
BATS_BIN="${CC_POSTLAND_BATS:-bats}"
# ── PATH NORMALIZATION — the 0-green-stamp root cause (reproduced 2026-07-26) ────────────────────
# The verdict is only meaningful if the suite runs in the environment a real session runs in. When
# this script is driven from a daemon/launchd-ish context its PATH lacks $HOME/.claude/bin and
# $HOME/bin, so every suite that shells out to a cc-* helper fails — and because the retry ladder
# (:216) re-runs each red FILE alone twice and convicts at >=2/3, a PATH-dependent failure
# reproduces deterministically and is written as a HARD red, not a flake. That is the mechanism
# behind 15/15 red stamps and deploy-live sitting fail-closed at 0 green while trunk was in fact
# green (measured: full 137-suite clean-room run at 03606baf = 2096 ok / 0 not-ok).
#
# REPRO (10s):  env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin TERM=dumb \
#                 bash -c 'cd <worktree> && bats tests/deploy-parity.bats'
#               => "not ok 8 the real repo passes its own assertion" — 8/8 under a session PATH.
#
# Why normalize rather than make the suites PATH-hermetic: the affected assertions are HOST checks
# by design ("the real repo passes its own assertion (guards the live host deployment)"), so
# stubbing their tools would delete the thing they verify. This mirrors the prescription already
# carried in the infra-green brief. Prepend-only and idempotent: an explicitly-set CC_POSTLAND_PATH
# wins, entries already present are not duplicated, and nothing is ever removed — so an
# interactive run (which already has these) is completely unaffected.
if [ -n "${CC_POSTLAND_PATH:-}" ]; then
  PATH="$CC_POSTLAND_PATH"
else
  for _p in "$HOME/.claude/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
    [ -d "$_p" ] || continue
    case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
  done
fi
export PATH
LOCK_TTL="${CC_POSTLAND_LOCK_TTL:-3600}"
SUITE_TO="${POSTLAND_SUITE_TIMEOUT_S:-2700}"   # full-suite bound — makes a HUNG observable at all
FILE_TO="${POSTLAND_FILE_TIMEOUT_S:-300}"      # per-file bound (retry ladder + the hang confirm)
STAMPS="$STATE/stamps"
LOCK="$STATE/run.lock.d"
LOG="$STATE/runner.log"
FLAKES="$STATE/flakes.jsonl"
LASTGREEN="$STATE/last-green"
QUEUE="$STATE/queue"
CUTS="$STATE/cuts"                                     # "<tree> <consecutive-n> <epoch>"
CUT_MAX="${CC_POSTLAND_CUT_MAX:-3}"                    # consecutive cuts on one tree before paging
CUT_COOLOFF="${CC_POSTLAND_CUT_COOLOFF:-1800}"         # ...and before the box is fed another suite

FAILING=(); SYNTAX_BAD=(); RETRIES=0; NFLAKE=0; FAILTEST=""; RUN_TMP=""; IDL_DONE=0; ENV_FP='{}'; CUT=0
# ── hang evidence (reset per run_target) ─────────────────────────────────────────────────────────
DEATH_SIG=""         # sig:9 | timeout:2700s | exit:1 — what ended the run
WEDGE_AT=""          # "<completed>/<planned>" at the moment it stopped making progress
SUSPECT=""           # tests/<file>.bats the run wedged IN (best effort — see the CONFIRM note)
REPRODUCED=false     # did the suspect file wedge AGAIN, alone, in this pristine worktree?

now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }
ensure_dirs() { mkdir -p "$STAMPS" "$PAGES" "$(dirname "$IDL")" 2>/dev/null || true; }
log() { printf '%s postland-verify: %s\n' "$(now_iso)" "$1" >> "$LOG" 2>/dev/null || true; }

# ONE IDL line per invocation (guarded) — the abstention monitor reads this file.
idl() { # <fired|abstained> <reason> [sha]
  [ "$IDL_DONE" = 1 ] && return 0
  IDL_DONE=1
  printf '{"ts":"%s","check":"postland-verify","decision":"%s","reason":"%s","sha":"%s"}\n' \
    "$(now_iso)" "$1" "$2" "${3:-}" >> "$IDL" 2>/dev/null || true
}
notify() { # <title> <msg> — OS-level, API-independent
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$1" "$2" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    plv_osa osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
}
json_array() { local out="" i; for i in "$@"; do out="$out,\"$i\""; done; printf '[%s]' "${out#,}"; }
sha12() { printf '%s' "$1" | cut -c1-12; }
tree_of() { git -C "$REPO" rev-parse "$1^{tree}" 2>/dev/null; }
env_fingerprint() { # sets ENV_FP — a verdict is NOT a pure function of the tree (tool bumps happen
  local b c l                                # constantly), so a stale-env green stamp stays diagnosable
  b="$("$BATS_BIN" --version 2>/dev/null | awk '{print $2}')"
  c="${CLAUDE_CODE_EXECPATH:-}"; [ -n "$c" ] && c="$(basename "$c")" || c=unknown
  l="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"                 # 1-min, at run start
  ENV_FP="$(printf '{"bats":"%s","cc":"%s","load":"%s"}' "${b:-unknown}" "${c:-unknown}" "${l:-0}")"
}

# ════ mutex — shape copied from land-lock.sh (a LIVE holder is never reaped; dead pid → instant) ═══
try_acquire() {
  mkdir "$LOCK" 2>/dev/null && { printf '%s\n' "$$" > "$LOCK/pid"; return 0; }
  local holder age stale
  holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
  age="$(( $(now_epoch) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))"
  stale=0
  if [ -z "$holder" ]; then { [ "$age" -ge 5 ] || [ "$age" -gt "$LOCK_TTL" ]; } && stale=1
  elif kill -0 "$holder" 2>/dev/null; then stale=0     # holder ALIVE → NEVER reaped (wait it out)
  else stale=1; fi                                     # holder pid DEAD → reap immediately
  if [ "$stale" = 1 ]; then
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null && { printf '%s\n' "$$" > "$LOCK/pid"; return 0; }
  fi
  return 1
}
# shellcheck disable=SC2329  # invoked indirectly: `trap release_lock EXIT`
release_lock() {
  [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ] && rm -rf "$LOCK"
  [ -n "$RUN_TMP" ] && rm -rf "$RUN_TMP"
  return 0
}

# ════ disposable worktree ═════════════════════════════════════════════════════════════════════════
prepare_worktree() { # <sha> — created ONCE if absent; per-run fetch + detach + clean (NEVER -x)
  local sha="$1" wtp repop
  wtp="$(cd "$WORKTREE" 2>/dev/null && pwd -P || printf '%s' "$WORKTREE")"
  repop="$(cd "$REPO" 2>/dev/null && pwd -P || printf '%s' "$REPO")"
  # the load-bearing guard: never check in $REPO (its working tree is the LIVE ~/.claude layer)
  [ "$wtp" = "$repop" ] && { log "REFUSED: worktree resolves to the live repo ($repop)"; return 1; }
  if [ ! -e "$WORKTREE/.git" ]; then
    mkdir -p "$(dirname "$WORKTREE")" 2>/dev/null || true
    git -C "$REPO" worktree add --detach "$WORKTREE" "$sha" >/dev/null 2>&1 || return 1
  fi
  git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true      # never inherit a wedged bisect
  git -C "$WORKTREE" fetch origin main >/dev/null 2>&1 || true # best-effort
  git -C "$WORKTREE" checkout --detach "$sha" >/dev/null 2>&1 || return 1
  git -C "$WORKTREE" clean -fd >/dev/null 2>&1 || true
  return 0
}
shell_files() { # tracked *.sh + bash/sh-shebang files, worktree-relative
  local f first
  while IFS= read -r f; do
    [ -f "$WORKTREE/$f" ] || continue
    case "$f" in *.sh) printf '%s\n' "$f"; continue ;; esac
    first="$(head -1 "$WORKTREE/$f" 2>/dev/null)"
    case "$first" in '#!'*bash*|'#!'*/sh|'#!'*env\ sh) printf '%s\n' "$f" ;; esac
  done <<EOF
$(git -C "$WORKTREE" ls-files 2>/dev/null)
EOF
}
syntax_check() { # bash -n — cheap and verdict-affecting
  local f
  SYNTAX_BAD=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    bash -n "$WORKTREE/$f" 2>/dev/null || SYNTAX_BAD+=("$f")
  done <<EOF
$(shell_files)
EOF
}
sc_count() { # whole-tree lint finding count — ADVISORY, never verdict-affecting
  command -v shellcheck >/dev/null 2>&1 || { printf '0\n'; return 0; }
  ( cd "$WORKTREE" && shell_files | tr '\n' '\0' | xargs -0 shellcheck -f gcc 2>/dev/null ) | grep -c ':'
}
record_flake() { # <file> <test> <rc>
  local sig load
  if [ "$3" -gt 128 ]; then sig="sig:$(( $3 - 128 ))"; else sig="exit:$3"; fi
  load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
  printf '{"ts":"%s","file":"%s","test":"%s","sha":"%s","phase":"postland","outcome":"1-of-3","signal":"%s","loadavg":"%s"}\n' \
    "$(now_iso)" "$1" "$2" "${CUR_SHA:-}" "$sig" "${load:-0}" >> "$FLAKES" 2>/dev/null || true
  NFLAKE=$((NFLAKE+1))
}
# ════ HUNG — the one state a CUT cannot express ═══════════════════════════════════════════════════
# A CUT says "the run was truncated, nothing was proven, retry next sweep". That is exactly right for
# a peer's pkill, an OOM, or load starvation — a MACHINE event: unactionable, self-clearing, and its
# own honest page names no test. It is exactly WRONG for a suite that simply never returns. That is a
# property OF THE TREE (an un-stubbed external seam), it reproduces on a quiet box, and retrying it
# every sweep forever is the precise opposite of the right response — the tree is never verified and
# the box burns a full suite per tick on it. So HUNG is carved OUT of the cut population as a real
# verdict: stamped (the tree is decided), paged at the FILE that wedged, routed to the seam owner.
# Everything else that reaches here stays a CUT, with trunk's ledger and cool-off untouched.
int_or_zero() { case "${1:-}" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
tap_plan() { # <tap> → N from the `1..N` plan line (0 when it never even planned)
  int_or_zero "$(sed -n 's/^1\.\.\([0-9][0-9]*\).*$/\1/p' "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_done() { # <tap> → completed tests. bats emits `ok`/`not ok` only AFTER a test returns, so this
  # is exactly "how far did it get". (`grep -c` prints 0 AND exits 1 on no-match — never `|| printf 0`.)
  int_or_zero "$(grep -acE '^(ok|not ok) [0-9]+' "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_signal() { # <tap> → the job-control death line, if the shell printed one. `# `-prefixed lines
  # are a TEST'S OWN captured output (this repo has reaper/kill suites that print those very words),
  # so they are excluded — the needle is the shell's `Killed: 9` / `Terminated: 15` shape. Needed
  # because bats can OUTLIVE the child it lost and exit 1, so rc alone never sees that signal.
  grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$1" 2>/dev/null | head -1 \
    | grep -oE '(Killed|Terminated): *[0-9]+' | head -1 | tr -d '\n'
}
suite_files() { # the suite in the order `bats tests/` runs it — bats' OWN expansion (bats:480 is
  # `find -L … -type f -name "*.bats" -print0 | sort -z`; no test filename here contains a newline,
  # so the line-delimited form is byte-equivalent and stays readable).
  find -L "$WORKTREE/tests" -type f -name '*.bats' 2>/dev/null | sort
}
suite_file_at() { # <1-based test index> → tests/<file>.bats (empty when unmappable)
  local want="$1" f n acc=0
  case "$want" in ''|*[!0-9]*) return 1 ;; esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n="$(int_or_zero "$(bounded 20 "$BATS_BIN" --count "$f" 2>/dev/null | tr -d '\n')")"  # parses, never executes
    acc=$(( acc + n ))
    if [ "$want" -le "$acc" ]; then printf '%s\n' "${f#"$WORKTREE"/}"; return 0; fi
  done <<EOF
$(suite_files)
EOF
  return 1
}
confirm_hang() { # <suspect-file> — THE clean discriminator: the file, ALONE, bounded, right here in
  # the pristine detached worktree. 0 = it wedged again (HUNG); 1 = it completed, so the wedge was
  # environmental and we refuse to invent a verdict from it.
  local rc=0
  # `bounded` is a FUNCTION, so it must be the outer call — `nice` execs a binary and could never
  # run it. timeout-then-nice also keeps the bound owning the process group.
  ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" bounded "$FILE_TO" nice -n 10 "$BATS_BIN" "$1" ) >/dev/null 2>&1 || rc=$?
  RETRIES=$((RETRIES+1))
  [ "$rc" -eq 124 ]
}
classify_hang() { # <tapfile> <rc> — 0 = HUNG (sets SUSPECT/WEDGE_AT/DEATH_SIG/REPRODUCED), 1 = CUT
  local tap="$1" rc="$2" plan ndone sig
  plan="$(tap_plan "$tap")"; ndone="$(tap_done "$tap")"; sig="$(tap_signal "$tap")"
  WEDGE_AT="$ndone/$plan"; SUSPECT=""; REPRODUCED=false
  # (1) OUR bound. FIRST, and the ordering is the whole point: timeout(1) SIGTERMs the group, so a
  #     hang's own TAP carries `Terminated: 15` — a signal-first ladder files every hang as a kill.
  if [ "$rc" -eq 124 ]; then DEATH_SIG="timeout:${SUITE_TO}s"
  # (2)/(3) an EXTERNAL signal — either straight through as rc-128, or seen only in the TAP because
  #     bats outlived the child it lost. Either way a MACHINE event ⇒ trunk's CUT, not a hang.
  elif [ "$rc" -gt 128 ]; then DEATH_SIG="sig:$(( rc - 128 ))"; return 1
  elif [ -n "$sig" ]; then DEATH_SIG="${sig// /}"; return 1
  # (4) it planned and then completed NOTHING, with nobody to blame — fe21305312ec's signature.
  elif [ "$plan" -gt 0 ] && [ "$ndone" -eq 0 ]; then DEATH_SIG="exit:$rc"
  # (5) neither shape fits ⇒ undecidable, which is what a CUT already says honestly.
  else DEATH_SIG="exit:$rc"; return 1
  fi
  SUSPECT="$(suite_file_at "$(( ndone + 1 ))" 2>/dev/null || true)"
  if [ -n "$SUSPECT" ]; then
    # CONFIRM. A mis-mapped suspect can therefore only LOSE a hang (it degrades to a CUT and is
    # retried), never invent one — the failure mode we can afford.
    if confirm_hang "$SUSPECT"; then REPRODUCED=true; return 0; fi
    DEATH_SIG="$DEATH_SIG/not-reproduced"; SUSPECT=""; return 1
  fi
  # Unmappable suspect. Our own bound firing is still direct evidence the run never returned, so
  # HUNG stands — flagged unreproduced, because nothing was re-run to prove it. Without the bound
  # (CC_POSTLAND_TIMEOUT_BIN=) nothing can ever return 124, so a hang is simply unprovable and
  # degrades to a CUT: no bound, no hang verdict. We never fabricate one.
  [ "$rc" -eq 124 ]
}
classify_failures() { # <tapfile> — retry ladder: >=2/3 = REPRODUCIBLE, 1/3 = flake
  local pairs f t rc i tdir fails notok
  # TAP: `not ok N <name>` followed by a `# (in test file tests/X.bats, line N)` diagnostic.
  pairs="$(awk '/^not ok /{p=1; n=$0; sub(/^not ok [0-9]+ /,"",n); next}
                /^#/ && p { if (match($0, /[A-Za-z0-9_.\/-]+\.bats/)) { print substr($0,RSTART,RLENGTH) "\t" n; p=0 } }' "$1" \
             | awk -F'\t' '!seen[$1]++')"
  if [ -z "$pairs" ]; then
    # CUT ≠ RED. No attributable pair has TWO causes, and they need opposite handling:
    #   (a) the TAP contains ZERO `not ok` at all  ⇒ the run was TRUNCATED (killed / starved),
    #       so nothing failed — stamping it red is a LIE, and a costly one: the red stamp is
    #       what `deploy-live.sh` and `ship-land.sh:postland_net_live` read. With every run
    #       cut, NO GREEN STAMP CAN EVER EXIST, so deploy-live refuses forever ("no GREEN
    #       stamp among the newest 200 commits") and the liveness guard silently reads
    #       "net not adopted ⇒ trust". Verified 2026-07-26: 4 of the last 5 runner.log
    #       verdicts were `failing=tests/ retries=0` — i.e. all four were cuts, not reds.
    #   (b) `not ok` lines exist but carry no `# (in test file …)` diagnostic ⇒ a GENUINE red
    #       we merely cannot attribute to a file. It stays RED — see C13b.
    notok="$(grep -c '^not ok' "$1" 2>/dev/null || true)"; notok="${notok:-0}"
    if [ "$notok" -eq 0 ]; then CUT=1; return 0; fi
    # NAME-CARRY (b): TAP names the TEST on the `not ok` line even when it never names the
    # FILE. Recording the opaque "(unattributed)" threw that name away, leaving a page that
    # reads exactly like the signal-death case (a) it was just separated from — the operator
    # cannot tell "a real failure we could not attribute" from "no verdict at all", which is
    # the whole distinction this branch exists to draw. Keep the sentinel only as a fallback.
    FAILING=("tests/")
    FAILTEST="$(sed -n 's/^not ok [0-9]* //p' "$1" 2>/dev/null | head -1 | cut -c1-120)"
    [ -n "$FAILTEST" ] || FAILTEST="(unattributed)"
    return 0
  fi
  while IFS="$(printf '\t')" read -r f t; do
    [ -n "$f" ] || continue
    fails=1; rc=1
    for i in 1 2; do                                     # each re-run gets a FRESH private TMPDIR
      # SHED BEFORE EACH RETRY. The ladder's whole premise is that a re-run discriminates a real
      # failure from an environmental one — but it re-ran under the SAME sustained load that caused
      # the first failure, so a load-sensitive test fails all three times and is promoted to
      # "REPRODUCIBLE". That is how the 2026-07-26 genuine-looking stamp (retries=12) convicted six
      # suites that each pass cleanly on a quiet box. Re-running is only evidence if the environment
      # actually changed — the complement to CUT ≠ RED, which stops a cut from lying about itself.
      gate_admit "retry $i of $f"
      tdir="$(mktemp -d "$RUN_TMP/retry.XXXXXX")"
      # BOUNDED for the same reason the full suite is: a file that WEDGES would hold the ladder —
      # and this runner's mutex — open forever, turning one hung test into a dead post-land net.
      ( cd "$WORKTREE" && TMPDIR="$tdir" bounded "$FILE_TO" nice -n 10 "$BATS_BIN" "$f" ) >/dev/null 2>&1
      rc=$?; RETRIES=$((RETRIES+1)); [ "$rc" -eq 0 ] || fails=$((fails+1)); rm -rf "$tdir"
    done
    if [ "$fails" -ge 2 ]; then FAILING+=("$f"); [ -n "$FAILTEST" ] || FAILTEST="$t"
    else record_flake "$f" "$t" "$rc"; fi
  done <<EOF
$pairs
EOF
}
# ════ admission control — bounded, fail-OPEN load shedding ════════════════════════════════════════
# Deliberately SELF-CONTAINED (a near-twin lives in ship-land.sh) rather than a shared sibling lib:
# this whole incident began with a sibling file that could not be resolved, and a load shedder that
# silently no-ops because its lib is missing would re-arm the exact herd it exists to damp.
# CONTRACT: bounded (always proceeds by CC_GATE_ADMIT_MAX_WAIT) · env-overridable
# (CC_GATE_MAX_LOAD=0|off is the kill switch) · fail-OPEN on an unreadable sensor · never called
# while a lock is held that another runner needs — postland holds only its OWN single-slot mutex,
# and a second instance abstains instantly rather than queueing, so waiting here blocks nobody.
gate_admit() { # <what>
  local what="${1:-suite}" max budget step waited=0 load jit
  max="${CC_GATE_MAX_LOAD:-8}"; budget="${CC_GATE_ADMIT_MAX_WAIT:-600}"; step="${CC_GATE_ADMIT_POLL:-15}"
  { [ "$max" = "0" ] || [ "$max" = "off" ]; } && return 0
  case "$max" in ''|*[!0-9.]*) return 0 ;; esac                        # ceiling: numeric (awk-compared)
  case "$budget$step" in ''|*[!0-9]*) return 0 ;; esac                 # waits: INTEGER seconds
  [ "$step" -gt 0 ] || return 0                                        # a 0 poll would spin ⇒ fail OPEN
  while [ "$waited" -lt "$budget" ]; do
    load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
    [ -n "$load" ] || return 0                                         # unreadable sensor ⇒ fail OPEN
    if awk -v l="$load" -v m="$max" 'BEGIN{exit !(l+0 < m+0)}'; then
      [ "$waited" -gt 0 ] && log "ADMIT ok after ${waited}s (load $load < $max) — starting $what"
      return 0
    fi
    [ "$waited" -eq 0 ] && log "ADMIT-DEFER $what — load $load >= ceiling $max (waiting up to ${budget}s)"
    # JITTER (see ship-land.sh's twin): de-synchronise wakeups so deferred runners do not all
    # restart on the same boundary and re-form the herd the shedder exists to break up.
    jit=$(( RANDOM % 8 ))
    sleep "$(( step + jit ))"; waited=$(( waited + step + jit ))
  done
  log "ADMIT-PROCEED $what — budget ${budget}s exhausted (load $load >= $max), starting anyway (bounded by design)"
  return 0
}

do_bisect() { # <file> <good> <bad> → prints the first-bad sha (empty when undecidable)
  local file="$1" good="$2" bad="$3" runner out culprit
  [ -n "$good" ] && [ -n "$bad" ] && [ "$good" != "$bad" ] || return 1
  file="tests/$(basename "$file")"
  prepare_worktree "$bad" || return 1
  runner="$(mktemp "${TMPDIR:-/tmp}/postland-bisect.XXXXXX")" || return 1
  {                                     # 125 = SKIP: file absent, or bats ERRORED (rc>1) — not a red
    printf '#!/bin/bash\n'
    printf '[ -f "%s" ] || exit 125\n' "$file"
    printf '"%s" "%s" >/dev/null 2>&1\n' "$BATS_BIN" "$file"
    # shellcheck disable=SC2016  # authoring a script: $rc must NOT expand here
    printf 'rc=$?\n[ "$rc" -le 1 ] || exit 125\nexit "$rc"\n'
  } > "$runner"
  chmod +x "$runner"
  if git -C "$WORKTREE" bisect start "$bad" "$good" >/dev/null 2>&1; then
    out="$(git -C "$WORKTREE" bisect run "$runner" 2>/dev/null)"
    culprit="$(printf '%s\n' "$out" | sed -n 's/^\([0-9a-f]\{7,40\}\) is the first bad commit.*/\1/p' | head -1)"
  fi
  git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true
  rm -f "$runner"
  [ -n "${culprit:-}" ] || return 1
  printf '%s\n' "$culprit"
}
write_stamp() { # <tree> <commit> <verdict> <run_s> <retries> <adv> [failing…]
  local tree="$1" commit="$2" verdict="$3" run_s="$4" retries="$5" adv="$6"; shift 6
  mkdir -p "$STAMPS" 2>/dev/null || true
  printf '{"tree":"%s","commit":"%s","verdict":"%s","failing":%s,"ts":"%s","run_s":%s,"retries":%s,"checks":"bats+bash-n","shellcheck_advisory":%s,"env":%s}\n' \
    "$tree" "$commit" "$verdict" "$(json_array "$@")" "$(now_iso)" "$run_s" "$retries" "$adv" "$ENV_FP" > "$STAMPS/$tree.json"
}
red_actions() { # <sha> <file> — bisect, page, backlog, notify. Every side channel is || true-guarded.
  local sha="$1" file="$2" good culprit c12 pf sid
  good="$(cat "$LASTGREEN" 2>/dev/null || true)"
  culprit="$(do_bisect "$file" "$good" "$sha" 2>/dev/null || true)"
  [ -n "$culprit" ] || culprit="$sha"
  c12="$(sha12 "$culprit")"
  prepare_worktree "$sha" || true                            # bisect left the worktree elsewhere
  # STATE-KEYED page filename — a fixed key gets path-dedup-swallowed for 7 days.
  pf="$PAGES/postland-red-$c12.page"
  { now_epoch
    printf 'post-land RED @ %s\n' "$(now_iso)"
    printf 'culprit: %s (bisected from last-green %s)\n' "$c12" "$(sha12 "${good:-unknown}")"
    printf 'failing: %s::%s\n' "$file" "${FAILTEST:-?}"
    [ "${#FAILING[@]}" -gt 1 ] && printf 'all failing: %s\n' "${FAILING[*]}"
    printf 're-run:  cd %s && git checkout --detach %s && bats %s\n' "$WORKTREE" "$c12" "$file"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add --title "post-land RED: $file @ $c12" \
    --project claude-infrastructure --source postland-verify >/dev/null 2>&1  # sha defeats wasDone
  notify "Claude post-land RED" "$file fails at $c12 — see $pf"
  sid="$(grep -F "$culprit" "$LANDLOG" 2>/dev/null | tail -1 | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p')"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land RED: $file::${FAILTEST:-?} at $c12 (your land) — see $pf" >/dev/null 2>&1
  return 0
}
hung_actions() { # <sha> <tree> — page + backlog + notify, routed to the SEAM owner.
  # Deliberately NO bisect: a hang is a latent un-stubbed seam that surfaced when contention eased,
  # not a recent regression — and every bisect step would itself wedge for the full bound.
  local sha="$1" tree="$2" slug pf sid file="${SUSPECT:-tests/}"
  slug="$(printf '%s' "$file" | sed 's#.*/##; s/\.bats$//; s/[^A-Za-z0-9_-]/-/g')"
  [ -n "$slug" ] || slug=suite                        # unmappable suspect ⇒ still a keyable name
  pf="$PAGES/postland-hung-$slug-$(sha12 "$tree").page"
  { now_epoch
    printf 'post-land HUNG @ %s\n' "$(now_iso)"
    printf 'suite:   %s (tree %s)\n' "$(sha12 "$sha")" "$(sha12 "$tree")"
    printf 'wedged:  %s at %s completed — %s\n' "$file" "$WEDGE_AT" "$DEATH_SIG"
    printf 'proof:   re-ran %s ALONE in this pristine detached worktree; wedged again: %s\n' "$file" "$REPRODUCED"
    printf 'NOT a cut: no signal reached this run (a peer pkill shows rc>128 / a job-control line).\n'
    printf 'FIX:     find the un-stubbed external seam and timeout-wrap it (or stub it in setup()).\n'
    printf 're-run:  cd %s && git checkout --detach %s && %s %s\n' "$WORKTREE" "$(sha12 "$sha")" "${TIMEOUT_BIN:-timeout} $FILE_TO bats" "$file"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-land HUNG: $file wedged at $WEDGE_AT @ $(sha12 "$tree") — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)" \
    --project claude-infrastructure --source postland-verify >/dev/null 2>&1   # tree defeats wasDone
  notify "Claude post-land HUNG" "$file wedges at $WEDGE_AT — un-stubbed seam, see $pf"
  sid="$(grep -F "$sha" "$LANDLOG" 2>/dev/null | tail -1 | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p')"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land HUNG: $file wedged at $WEDGE_AT on your land — un-stubbed external seam, see $pf" >/dev/null 2>&1
  return 0
}
run_target() { # <sha> — the whole check-set + verdict for ONE sha
  local sha="$1" tree tap rc adv t0 run_s n
  CUR_SHA="$sha"
  tree="$(tree_of "$sha")"
  [ -n "$tree" ] || { log "cannot resolve tree for $sha"; return 1; }
  prepare_worktree "$sha" || { log "worktree prepare FAILED for $(sha12 "$sha")"; return 1; }
  t0="$(now_epoch)"; env_fingerprint            # captured at run START — a green is env-relative
  RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/postland-run.XXXXXX")" || return 1
  FAILING=(); FAILTEST=""; RETRIES=0; NFLAKE=0; CUT=0
  DEATH_SIG=""; WEDGE_AT=""; SUSPECT=""; REPRODUCED=false
  syntax_check
  tap="$RUN_TMP/bats.tap"
  gate_admit "full suite @ $(sha12 "$sha")"
  # BOUNDED: unbounded, a wedged suite holds the mutex until LOCK_TTL and no hang is ever observable
  # — the runner just disappears. rc 124 is the bound firing and is the primary HUNG discriminator.
  ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" bounded "$SUITE_TO" nice -n 10 "$BATS_BIN" tests/ ) > "$tap" 2>&1; rc=$?
  adv="$(sc_count)"
  [ "$rc" -eq 0 ] || classify_failures "$tap"
  [ "${#SYNTAX_BAD[@]}" -eq 0 ] || FAILING+=("${SYNTAX_BAD[@]}")
  run_s="$(( $(now_epoch) - t0 ))"
  if [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ] && classify_hang "$tap" "$rc"; then
    # HUNG is carved out of the cut population and IS a verdict about the tree: it reproduced here,
    # at this load, on a pristine detached checkout. Stamp it so the tree is not re-run forever, and
    # page the FILE with the fix that actually applies (timeout-wrap the seam), not "retry when
    # quieter" — which is the one response guaranteed never to clear it.
    write_stamp "$tree" "$sha" hung "$run_s" "$RETRIES" "$adv" "${SUSPECT:-tests/}"
    cut_clear                                   # a verdict was reached: the cut streak is over
    log "HUNG $(sha12 "$sha") tree=$(sha12 "$tree") suspect=${SUSPECT:-?} wedge_at=$WEDGE_AT sig=$DEATH_SIG reproduced=$REPRODUCED run_s=$run_s"
    hung_actions "$sha" "$tree"
    echo "postland-verify: HUNG $(sha12 "$sha") — ${SUSPECT:-tests/} wedged at $WEDGE_AT ($DEATH_SIG)"
  elif [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ]; then
    # A cut proves NOTHING — do not stamp green (unearned) and do not stamp red (a lie that
    # blocks deploy forever). Stamp `cut` for diagnosability: the tree stays unstamped-green,
    # so C5's abstain does not fire and the NEXT sweep retries it. No bisect, no page — you
    # cannot bisect a machine event, and paging on one trains the operator to ignore pages.
    write_stamp "$tree" "$sha" cut "$run_s" "$RETRIES" "$adv"
    n="$(cut_bump "$tree")"
    [ "$n" -ge "$CUT_MAX" ] && cut_page "$sha" "$tree" "$n"
    log "CUT $(sha12 "$sha") tree=$(sha12 "$tree") run_s=$run_s retries=$RETRIES sc_adv=$adv consecutive=$n (zero not-ok in a non-zero run - truncated; will retry)"
    echo "postland-verify: CUT $(sha12 "$sha") (${run_s}s) - run truncated, not red; retrying next sweep"
  elif [ "${#FAILING[@]}" -eq 0 ]; then
    write_stamp "$tree" "$sha" green "$run_s" "$RETRIES" "$adv"
    printf '%s\n' "$sha" > "$LASTGREEN"
    cut_clear                                   # a verdict was reached: the cut streak is over
    rm -f "$PAGES"/postland-red-*.page "$PAGES"/postland-cut-*.page \
          "$PAGES"/postland-hung-*.page 2>/dev/null || true  # now-passing state clears standing pages
    log "GREEN $(sha12 "$sha") tree=$(sha12 "$tree") run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    echo "postland-verify: GREEN $(sha12 "$sha") (${run_s}s, flakes=$NFLAKE)"
  else
    write_stamp "$tree" "$sha" red "$run_s" "$RETRIES" "$adv" "${FAILING[@]}"
    cut_clear                                   # a verdict was reached: the cut streak is over
    log "RED $(sha12 "$sha") failing=${FAILING[*]} run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    red_actions "$sha" "${FAILING[0]}"
    echo "postland-verify: RED $(sha12 "$sha") — ${FAILING[*]}"
  fi
  rm -rf "$RUN_TMP"; RUN_TMP=""
  return 0
}

# ════ verbs ═══════════════════════════════════════════════════════════════════════════════════════
do_run_if_needed() {
  local target tree new loops=0
  git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
  target="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"
  [ -n "$target" ] || { idl abstained no-origin-main; return 0; }
  tree="$(tree_of "$target")"
  if [ -n "$tree" ] && stamp_is_verdict "$tree"; then idl abstained already-stamped "$(sha12 "$target")"; return 0; fi
  # A tree the box has cut CUT_MAX times running is hostile: re-running a full suite on it every
  # tick amplifies the contention doing the cutting. Cool off (already paged), then resume retrying.
  if [ -n "$tree" ] && in_cut_cooloff "$tree"; then idl abstained cut-cooloff "$(sha12 "$target")"; return 0; fi
  try_acquire || { idl abstained lock-held "$(sha12 "$target")"; return 0; }   # 2nd instance: quiet 0
  trap release_lock EXIT
  while [ "$loops" -lt 2 ]; do                                # single-slot self-requeue, never a queue
    loops=$((loops+1))
    printf '%s\n' "$target" > "$QUEUE" 2>/dev/null || true
    run_target "$target"
    git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
    new="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || printf '%s' "$target")"
    [ "$new" = "$target" ] && break
    tree="$(tree_of "$new")"
    # SAME predicate as the entry gate above, and for the same reason: a `cut` stamp on the
    # moved-to tree means nothing was proven there, so breaking on its mere EXISTENCE hands the
    # new head straight back to the next sweep unverified. Only a real verdict ends the requeue.
    [ -n "$tree" ] && stamp_is_verdict "$tree" && break
    target="$new"
  done
  : > "$QUEUE" 2>/dev/null || true
  idl fired "ran:$(sha12 "$target")" "$(sha12 "$target")"
  return 0
}
do_run_one() { # <sha>
  local sha
  [ -n "${1:-}" ] || { echo "usage: postland-verify.sh --run <sha>" >&2; idl abstained no-sha; return 2; }
  sha="$(git -C "$REPO" rev-parse "$1^{commit}" 2>/dev/null || true)"
  [ -n "$sha" ] || { echo "postland-verify: unknown sha '$1'" >&2; idl abstained unknown-sha; return 2; }
  try_acquire || { echo "postland-verify: another run holds the mutex" >&2; idl abstained lock-held "$(sha12 "$sha")"; return 0; }
  trap release_lock EXIT
  run_target "$sha"
  idl fired "ran:$(sha12 "$sha")" "$(sha12 "$sha")"
  return 0
}
verb_bisect() { # <file> <good> <bad>
  local c
  [ "$#" -eq 3 ] || { echo "usage: postland-verify.sh bisect <file> <good> <bad>" >&2; idl abstained bad-args; return 2; }
  c="$(do_bisect "$1" "$2" "$3")"; idl fired "bisect:$1"
  [ -n "$c" ] || { echo "postland-verify: bisect undecidable" >&2; return 1; }
  echo "$c"
}
# ════ a CUT stamp is a DIAGNOSTIC, never a verdict ════════════════════════════════════════════════
# `cut` records that a run was truncated (killed / starved) — no test ever said no, so nothing was
# proven. Abstaining on it strands the tree UNVERIFIED FOREVER: the stamp file exists, so an
# existence-keyed abstain fires on every later sweep and the suite never runs again. That also keeps
# is-green false, which drives ship-land to declare the whole post-land net INERT and degrade every
# gate scoped→FULL — more full suites, more load, more cuts. Only a real verdict earns an abstain.
# `hung` IS a verdict and belongs here: unlike a cut it is a proven property of the TREE (the suspect
# file wedged again, alone, on a pristine checkout), so re-running it every sweep re-proves a decided
# fact and burns a full suite per tick doing it. It is paged at the file, and the fix lands as a new
# tree — which carries a new stamp key, so the abstain releases by construction.
stamp_is_verdict() { # <tree> — 0 when the tree carries a REAL verdict (green|red|hung), 1 cut/absent
  grep -qE '"verdict":"(green|red|hung)"' "$STAMPS/$1.json" 2>/dev/null
}
cut_bump() { # <tree> → the new CONSECUTIVE cut count for this tree
  local pt pn n
  read -r pt pn _ < "$CUTS" 2>/dev/null || true
  if [ "${pt:-}" = "$1" ]; then n=$(( ${pn:-0} + 1 )); else n=1; fi
  printf '%s %s %s\n' "$1" "$n" "$(now_epoch)" > "$CUTS" 2>/dev/null || true
  printf '%s' "$n"
}
cut_clear() { rm -f "$CUTS" 2>/dev/null || true; }
in_cut_cooloff() { # <tree> — 0 = still cooling off
  local pt pn pts
  read -r pt pn pts < "$CUTS" 2>/dev/null || return 1
  [ "${pt:-}" = "$1" ] || return 1
  [ "${pn:-0}" -ge "$CUT_MAX" ] || return 1
  [ "$(( $(now_epoch) - ${pts:-0} ))" -lt "$CUT_COOLOFF" ]
}
cut_page() { # <sha> <tree> <n> — an HONEST page: names no test, asks for no bisect
  local pf t12
  t12="$(sha12 "$2")"; pf="$PAGES/postland-cut-$t12.page"
  { now_epoch
    printf 'post-land CUT (no verdict) @ %s\n' "$(now_iso)"
    printf 'target:  %s (tree %s)\n' "$(sha12 "$1")" "$t12"
    printf 'cut:     %s consecutive runs — the suite emitted ZERO "not ok" lines, so NO test failed.\n' "$3"
    printf '         Each run was TRUNCATED before reaching a verdict (peer pkill / OOM / load).\n'
    printf 'NOT a test failure — do not bisect. Re-run on a quiet box:\n'
    printf 're-run:  cd %s && git checkout --detach %s && bats tests/\n' "$WORKTREE" "$(sha12 "$1")"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
}
verb_is_green() { # <sha> — exit 0 green-stamped, 1 not
  local tree sha
  sha="$(git -C "$REPO" rev-parse "${1:-}^{commit}" 2>/dev/null || true)"
  idl abstained "is-green:${1:-}"
  [ -n "$sha" ] || return 1
  tree="$(tree_of "$sha")"
  [ -n "$tree" ] && [ -f "$STAMPS/$tree.json" ] || return 1
  grep -q '"verdict":"green"' "$STAMPS/$tree.json" 2>/dev/null || return 1
  return 0
}

verb_status() {
  printf 'postland-verify status\n  state      : %s\n  worktree   : %s\n  last-green : %s\n' \
    "$STATE" "$WORKTREE" "$(cat "$LASTGREEN" 2>/dev/null || echo '(none)')"
  printf '  stamps     : %s\n  queue      : %s\n  lock       : %s\n  flakes     : %s\n  pages      : %s\n  last run   : %s\n' \
    "$(find "$STAMPS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" \
    "$(cat "$QUEUE" 2>/dev/null || echo '(empty)')" \
    "$([ -d "$LOCK" ] && echo "held by pid $(cat "$LOCK/pid" 2>/dev/null)" || echo free)" \
    "$(cat "$FLAKES" 2>/dev/null | wc -l | tr -d ' ')" \
    "$(find "$PAGES" -name 'postland-red-*.page' 2>/dev/null | wc -l | tr -d ' ')" \
    "$(tail -1 "$LOG" 2>/dev/null || echo '(none)')"
  idl abstained status
}

# ════ selftest — RED-provable, fixture-scoped, zero side effects outside the temp dir ═════════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d rc tree green_sha red_sha
  d="$(mktemp -d "${TMPDIR:-/tmp}/postland-selftest.XXXXXX")" || { echo mktemp failed; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  mkdir -p "$d/src/tests" "$d/state" "$d/pages"
  git init -q --bare "$d/origin.git" >/dev/null 2>&1; git init -q "$d/src" >/dev/null 2>&1
  git -C "$d/src" config user.email pv@selftest.local; git -C "$d/src" config user.name pv-selftest
  git -C "$d/src" remote add origin "$d/origin.git" >/dev/null 2>&1
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$d/src/tests/ok.bats"
  printf '#!/bin/bash\necho hi\n' > "$d/src/ok.sh"
  fixture_land() { # <msg> — commit + publish to the fixture origin
    git -C "$d/src" add -A >/dev/null 2>&1; git -C "$d/src" commit -qm "$1" >/dev/null 2>&1
    git -C "$d/src" push -q origin HEAD:main >/dev/null 2>&1
    git -C "$d/src" fetch -q origin >/dev/null 2>&1
  }
  run_fixture() {
    # CC_GATE_MAX_LOAD=0 — the selftest must never sit in admission control; it is proving verdict
    # logic, not shedding behaviour, and it frequently runs on exactly the busy box that motivated
    # the shedder. (The shedder's own contract is asserted directly, below.)
    env POSTLAND_VERIFY="${POSTLAND_VERIFY:-on}" CC_GATE_MAX_LOAD=0 \
        CC_POSTLAND_DIR="$d/state" CC_POSTLAND_REPO="$d/src" \
        CC_POSTLAND_WORKTREE="$d/wt" CC_PAGES_DIR="$d/pages" CC_IDL="$d/idl.jsonl" \
        CC_BACKLOG_BIN=/usr/bin/true CC_POSTLAND_NOTIFY=/usr/bin/true CC_POSTLAND_NOTIFY_BIN=/usr/bin/true \
        CC_POSTLAND_LANDLOG="$d/land.log" "$SELF" "$@"
  }
  fixture_land green; green_sha="$(git -C "$d/src" rev-parse HEAD)"

  echo "postland-verify --selftest:"
  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                                   # ── green path
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  [ "$rc" -eq 0 ] && okp "green: exit 0" || badp "green: exit $rc (want 0)"
  [ -f "$d/state/stamps/$tree.json" ] && okp "green: tree stamp written" || badp "green: no stamp for tree"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null && okp "green: stamp verdict green" || badp "green: stamp not green"
  [ "$(cat "$d/state/last-green" 2>/dev/null)" = "$green_sha" ] && okp "green: last-green advanced" || badp "green: last-green NOT advanced"
  [ -z "$(find "$d/pages" -name 'postland-red-*.page' 2>/dev/null)" ] && okp "green: no page written" || badp "green: page written on green"
  grep -q '"check":"postland-verify"' "$d/idl.jsonl" 2>/dev/null && okp "green: IDL line appended" || badp "green: no IDL line"
  grep -qE '"env":\{"bats":"[^"]+","cc":"[^"]*","load":"[^"]*"\}' "$d/state/stamps/$tree.json" 2>/dev/null && okp "green: stamp carries the env fingerprint" || badp "green: stamp missing env fingerprint"

  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                        # ── abstain (tree stamped)
  [ "$rc" -eq 0 ] && okp "abstain: exit 0 on an already-stamped tree" || badp "abstain: exit $rc"
  grep -q '"decision":"abstained","reason":"already-stamped"' "$d/idl.jsonl" 2>/dev/null && okp "abstain: IDL records already-stamped" || badp "abstain: IDL missing already-stamped"
  run_fixture is-green "$green_sha" >/dev/null 2>&1 && okp "is-green: exit 0 on a green sha" || badp "is-green: nonzero on a green sha"
  POSTLAND_VERIFY=off run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                # ── kill switch
  [ "$rc" -eq 0 ] && okp "kill switch: POSTLAND_VERIFY=off exits 0" || badp "kill switch: exit $rc"

  printf '#!/usr/bin/env bats\n@test "boom" { false; }\n' > "$d/src/tests/bad.bats"     # ── red path
  fixture_land red; red_sha="$(git -C "$d/src" rev-parse HEAD)"
  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  [ "$rc" -eq 0 ] && okp "red: exit 0 (the net pages, it does not fail launchd)" || badp "red: exit $rc"
  grep -q '"verdict":"red"' "$d/state/stamps/$tree.json" 2>/dev/null && okp "red: stamp verdict red" || badp "red: stamp not red"
  [ -n "$(find "$d/pages" -name 'postland-red-*.page' 2>/dev/null)" ] && okp "red: state-keyed page written" || badp "red: NO page written"
  [ "$(cat "$d/state/last-green" 2>/dev/null)" = "$green_sha" ] && okp "red: last-green NOT advanced" || badp "red: last-green advanced on red"
  find "$d/pages" -name 'postland-red-*.page' 2>/dev/null | head -1 | xargs head -1 2>/dev/null \
    | grep -qE '^[0-9]+$' && okp "red: page line 1 is an epoch" || badp "red: page line 1 not an epoch"
  find "$d/pages" -name "postland-red-$(sha12 "$red_sha").page" 2>/dev/null | grep -q . \
    && okp "red: page keyed to the bisected culprit sha" || badp "red: page not culprit-keyed"

  # ── admission control contract: bounded + fail-open + kill switch (no sleeping in the selftest)
  # a separate PROCESS, not a ( ) subshell: the probe must set LOG/CC_* without shadowing this
  # script's own globals (shellcheck SC2030/SC2031, and the gate treats any finding as red).
  { sed -n '/^gate_admit() {/,/^}/p' "$SELF"
    # shellcheck disable=SC2016  # authoring a script: $1 must NOT expand here
    printf 'log() { printf "%%s\\n" "$1" >> "%s"; }\n' "$d/admit.log"
    printf 'CC_GATE_MAX_LOAD=0 gate_admit killswitch || exit 1\n'                     # kill switch
    printf 'CC_GATE_MAX_LOAD=bogus gate_admit nonnumeric || exit 1\n'                 # fail OPEN
    printf 'CC_GATE_MAX_LOAD=0.001 CC_GATE_ADMIT_MAX_WAIT=1 CC_GATE_ADMIT_POLL=1 gate_admit bounded || exit 1\n'
  } > "$d/admit-probe.sh"
  timeout 30 bash "$d/admit-probe.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && okp "admit: kill switch + non-numeric + bounded all return 0" || badp "admit: contract violated (rc=$rc)"
  grep -q 'ADMIT-PROCEED bounded' "$d/admit.log" 2>/dev/null \
    && okp "admit: an unsatisfiable ceiling PROCEEDS after the budget (never blocks a land)" \
    || badp "admit: budget exhaustion did not proceed"

  echo "postland-verify selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

usage() {
  echo "usage: postland-verify.sh [--run-if-needed | --run <sha> | bisect <file> <good> <bad> | is-green <sha> | status | --selftest]"
  echo "  kill switch: POSTLAND_VERIFY=off   ·   state: $STATE   ·   header comment = full design notes"
}

main() {
  if [ "${POSTLAND_VERIFY:-on}" = "off" ]; then            # runtime read — instant, side-effect-free
    printf 'postland-verify: DISABLED (POSTLAND_VERIFY=off)\n' >&2
    exit 0
  fi
  ensure_dirs
  case "${1:---run-if-needed}" in
    --run-if-needed) do_run_if_needed ;;
    --run)      shift; do_run_one "${1:-}" ;;
    bisect)     shift; verb_bisect "$@" ;;
    is-green)   shift; verb_is_green "${1:-}" ;;
    status)     verb_status ;;
    --selftest) selftest ;;
    -h|--help)  usage ;;
    *) echo "postland-verify: unknown verb '$1'" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
exit $?
