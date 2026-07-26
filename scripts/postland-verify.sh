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
# Verbs: --run-if-needed (launchd) · --run <sha> · bisect <file> <good> <bad> · is-green <sha> ·
#        status · --selftest.   Kill switch: POSTLAND_VERIFY=off (runtime-read ⇒ instantly inert).
# C10: OPERATOR loads the plist (docs/activation/pending-activation/09-postland-verify-activate.sh).
set -uo pipefail
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
LOCK_TTL="${CC_POSTLAND_LOCK_TTL:-3600}"
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
    osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
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
    #       we merely cannot attribute to a file. That keeps the old sentinel.
    notok="$(grep -c '^not ok' "$1" 2>/dev/null || true)"; notok="${notok:-0}"
    if [ "$notok" -eq 0 ]; then CUT=1; return 0; fi
    FAILING=("tests/"); FAILTEST="(unattributed)"; return 0
  fi
  while IFS="$(printf '\t')" read -r f t; do
    [ -n "$f" ] || continue
    fails=1; rc=1
    for i in 1 2; do                                     # each re-run gets a FRESH private TMPDIR
      tdir="$(mktemp -d "$RUN_TMP/retry.XXXXXX")"
      ( cd "$WORKTREE" && TMPDIR="$tdir" nice -n 10 "$BATS_BIN" "$f" ) >/dev/null 2>&1
      rc=$?; RETRIES=$((RETRIES+1)); [ "$rc" -eq 0 ] || fails=$((fails+1)); rm -rf "$tdir"
    done
    if [ "$fails" -ge 2 ]; then FAILING+=("$f"); [ -n "$FAILTEST" ] || FAILTEST="$t"
    else record_flake "$f" "$t" "$rc"; fi
  done <<EOF
$pairs
EOF
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
run_target() { # <sha> — the whole check-set + verdict for ONE sha
  local sha="$1" tree tap rc adv t0 run_s n
  CUR_SHA="$sha"
  tree="$(tree_of "$sha")"
  [ -n "$tree" ] || { log "cannot resolve tree for $sha"; return 1; }
  prepare_worktree "$sha" || { log "worktree prepare FAILED for $(sha12 "$sha")"; return 1; }
  t0="$(now_epoch)"; env_fingerprint            # captured at run START — a green is env-relative
  RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/postland-run.XXXXXX")" || return 1
  FAILING=(); FAILTEST=""; RETRIES=0; NFLAKE=0; CUT=0
  syntax_check
  tap="$RUN_TMP/bats.tap"
  ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" nice -n 10 "$BATS_BIN" tests/ ) > "$tap" 2>&1; rc=$?
  adv="$(sc_count)"
  [ "$rc" -eq 0 ] || classify_failures "$tap"
  [ "${#SYNTAX_BAD[@]}" -eq 0 ] || FAILING+=("${SYNTAX_BAD[@]}")
  run_s="$(( $(now_epoch) - t0 ))"
  if [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ]; then
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
    rm -f "$PAGES"/postland-red-*.page "$PAGES"/postland-cut-*.page 2>/dev/null || true  # now-passing state clears standing pages
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
    [ -n "$tree" ] && [ -f "$STAMPS/$tree.json" ] && break
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
stamp_is_verdict() { # <tree> — 0 when the tree carries a REAL verdict (green|red), 1 for cut/absent
  grep -qE '"verdict":"(green|red)"' "$STAMPS/$1.json" 2>/dev/null
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
    env POSTLAND_VERIFY="${POSTLAND_VERIFY:-on}" CC_POSTLAND_DIR="$d/state" CC_POSTLAND_REPO="$d/src" \
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
