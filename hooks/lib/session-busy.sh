#!/usr/bin/env bash
# hooks/lib/session-busy.sh — "is this session WORKING, or IDLING?" — the operator's first axis.
#
# WHY (CLOSE_SCANNABILITY_2026-08-23 D8, backlog a3eaa0dc1be2). The operator's recurring question
# has three axes — *current tasks and decisions · working or idling · good to close* — and only the
# middle one had no producer anywhere: 0 of wrap-ledger's machine fields and 0 `ps`/`pgrep` in
# either renderer. So `🔧 Unchanged.` was indistinguishable from a 20-minute gate and from a stuck
# poll loop, and the operator cannot obtain the answer for themselves — a backgrounded job is
# invisible to them by construction.
#
# TWO QUESTIONS, NOT ONE (docs/research/exhaustive-drive-2026-09-08/A10-idle-visibility.md §4 —
# a measured correction to D8's build order, and the reason this file leads with the beat):
#
#   Q1  "is this pane working or idling?"  — asked MID-FLIGHT, out of band. Truth condition: the
#       session is inside a turn. Sensor: the presence BEAT's `kind` field. O(1), no process scan,
#       measured 25/27 live-session coverage against the statusline telemetry's 19/27.
#   Q2  "did I leave a backgrounded job running?" — asked AT STOP. Truth condition: a descendant
#       job of mine is executing. Sensor: the D8 process scan (sb_busy_jobs, below).
#
# Neither answers the other: at a Stop the model is by definition not thinking, so `kind` cannot
# see a backgrounded gate; away from a Stop a descendant scan is blind to a session that is merely
# thinking. Both arms are here, tried in that order.
#
# THREE IDLE-SIDE STATES, NEVER TWO. BUSY / IDLE-ARMED / IDLE-DEAF. Collapsing the last two
# re-creates the wake-floor blindness: "idle with a wake path armed" is a session that will resume
# by itself, and "idle with none" is a session that will sit there forever. They read identically
# from outside and demand opposite actions.
#
# FAIL DIRECTION, CHOSEN ON PURPOSE, AND ONLY SAFE WITH THE EVIDENCE ATTACHED. Inside the job scan,
# an unrecognised process reads WORK — because a false IDLE is silent and actively misleading (it
# told an operator nothing was happening while a pane sat wedged on a permission prompt for 48
# minutes), whereas a false BUSY is self-diagnosing THE MOMENT the renderer names its sample: an
# operator who sees `job:caffeinate` knows instantly it is noise. That is why every reader here
# returns EVIDENCE and never a bare count. At the whole-sensor level the opposite rule holds and
# comes from wrap-ledger's house rule: an instrument that could not read anything reports UNKNOWN,
# never a manufactured state — `BUSY_SRC=error` is a fact, "IDLE" would be a fabrication.
#
# GONE IS NOT BUSY. A frozen beat from a dead session reads `kind=prompt` forever, which is the
# measured false-BUSY (`bin/cc-await-ping:954` names beat-kind a refuted discriminator — for the
# LIVENESS question, and its own line 535 uses it positively for this one). The cure is the
# liveness leg below, not a timeout.
#
# CONTRACT: pure reader. No writes, no side effects on source. bash 3.2 + jq. Empty + non-zero on
# every miss, so a hook sourcing this under `set -u` degrades to UNKNOWN rather than dying.
#
# Env seams (tests): CC_BUSY_NOW · CC_BUSY_SUSPECT_S · CC_BUSY_CONFIG_ROOTS · CC_BUSY_UTIL_INFRA ·
#   CC_BUSY_CUSTODY_OPEN · CC_PERMPEND_DIR · CC_BUSY_LIB_DIR — plus every seam of the libs it
#   sources (CC_BEAT_DIR, CC_PROC_SCOPE_PS/CWD, CC_MAILBOX_DIR).

_sb_dir() {  # where THIS file lives, so its siblings resolve from the same layer it was loaded from
  printf '%s' "${CC_BUSY_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)}"
}

_sb_src_once() {  # <basename> — source a sibling lib iff its probe function is not already defined
  command -v "$2" >/dev/null 2>&1 && return 0
  local f
  f="$(_sb_dir)/$1"
  [ -f "$f" ] || f="$HOME/.claude/hooks/lib/$1"
  [ -f "$f" ] || return 1
  # shellcheck disable=SC1090
  . "$f" 2>/dev/null || return 1
}

_sb_now() { local n="${CC_BUSY_NOW:-}"; case "$n" in ''|*[!0-9]*) date +%s ;; *) printf '%s' "$n" ;; esac; }

# ── LSTART DIALECT — MATCH THE PRODUCER, NOT THE CANON ───────────────────────────────────────────
# hooks/session-beat.sh:93 writes `TZ=UTC ps -o lstart= | tr -s ' '` — UTC, but in the READER'S
# AMBIENT LOCALE and with runs of spaces squeezed. A reader that compares against the canonical
# `TZ=UTC LC_ALL=C` rendering this repo pins everywhere else MISMATCHES 100% OF THE TIME:
#     recorded by the producer   [Thu 10 Sep 07:05:51 2026]     (TZ=UTC, ambient en_CA)
#     TZ=UTC LC_ALL=C ps         [Thu Sep 10 07:05:51 2026]     ← never equal
# and since a mismatch means GONE, and GONE must never render BUSY, the sensor would have read
# "not working" for every live session on the box — silently, in the exact direction this file
# calls the dangerous one. This is the same class land-inflight.sh documents at length (C31/C33:
# two producers writing opposite dialects, 100% miss, not an intermittent one) and MEMORY
# `process-start-time-renders-in-ambient-timezone`; it is repeated here because the DIALECT IS THE
# PRODUCER'S, and only reading that producer tells you which one it is.
#
# Both renderings are accepted, for land-inflight's own reason: every candidate is a rendering of
# the SAME pid at the SAME instant, so no rendering of a DIFFERENT start instant can equal the
# record — the fallback cannot manufacture a false match, it can only forgive a dialect.
_sb_lstart_matches() {  # <recorded> <pid> → 0 iff <recorded> is evidence <pid> is the SAME process
  local rec cur
  rec="$(printf '%s' "${1:-}" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$rec" ] || return 1                 # never recorded ⇒ cannot exonerate a recycled pid
  cur="$(TZ=UTC ps -o lstart= -p "${2:-}" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$cur" ] && [ "$rec" = "$cur" ] && return 0                     # the PRODUCER's dialect
  cur="$(TZ=UTC LC_ALL=C ps -o lstart= -p "${2:-}" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$cur" ] && [ "$rec" = "$cur" ] && return 0                     # the house canon
  return 1
}

# ── Q2: THE JOB SCAN ─────────────────────────────────────────────────────────────────────────────
# Scoping is SOURCED from hooks/lib/proc-scope.sh, never re-derived: those helpers carry physical-
# path resolution and argv-POSITION matching out of a SIGKILL selector, and a re-derivation loses
# both in silence (the first draft of that selector picked a live peer's `claude` for SIGKILL).
#
# The classifier is the composition D8 addendum 2 settled after every single-rule candidate was
# falsified on a nameable member of the live population:
#   1. INFRA when argv[0] or argv[1] resolves under a CONFIG ROOT (~/.claude and its siblings).
#      Structural, not a name list — new hooks install there too, so it covers the growing
#      population instead of rotting (MEMORY: denylist-enumerates-spellings-not-the-class).
#   2. INFRA when argv0's basename is a harness-spawned session utility. This one IS a list, and is
#      written down as such: short, stable, re-checked when it grows.
#   3. Otherwise WORK — the unknown case reads BUSY, with its sample printed.
# The naive form of this scan was FALSIFIED before a line was built: its negative control returned
# 9, not 0, and all 9 were wake/watchdog infrastructure — i.e. precisely IDLE-ARMED. A count that
# is never zero cannot answer "working or idling".
_sb_config_roots() {
  if [ -n "${CC_BUSY_CONFIG_ROOTS:-}" ]; then printf '%s' "$CC_BUSY_CONFIG_ROOTS"; return 0; fi
  printf '%s' "$HOME/.claude:$HOME/.claude-next:$HOME/.claude-tertiary:$HOME/.claude-quaternary:${CLAUDE_CONFIG_DIR:-}"
}

# THE CLASSIFIER, EXPRESSED ONCE — in awk, because it runs over the WHOLE process table.
# Measured on this box: the same rules as a bash `while read` loop with three function calls per row
# cost 2.36 s over 1,309 rows, on a path that runs at every Stop; as one awk pass, ~0.05 s. That is
# why this is awk and not the obvious shell loop — and why _sb_is_infra below CALLS it rather than
# restating it. A second, faster copy of a classifier is how the fast path and the readable path
# drift, and the readable path is what the tests pin.
#
# ── WHAT A ROOT IS, AND WHY THE RULE MOVED ───────────────────────────────────────────────────────
# D8 addendum 2 composed a rule that reads WORK unless a process is infrastructure (argv[0..1] under
# `~/.claude/`, or a named session utility), and chose to fail toward WORK. Re-measured against the
# live population while building this, that rule STILL reads BUSY in an idle worktree — the exact
# falsification D8 performed on the naive form (negative control 9, not 0), surviving its own fix:
#
#     /bin/zsh -c source …/shell-snapshots/snapshot-zsh-…   the harness's own tool-call shell
#     sleep 25 · sleep 30                                    harness furniture
#     /bin/bash /Users/…/claude-infrastructure/bin/cc-pane-runner × 2
#     tee -a /Users/…/.claude/logs/close-records/.stderr…
#     …/Python.app/Contents/MacOS/Python - /var/folders/…/cc…   the SA_SIGINFO side-cars
#
# Two independent reasons the infra rule cannot see them, and BOTH generalise:
#   (a) `~/.claude/bin/*` and `~/.claude/hooks/*` are PER-FILE SYMLINKS into the live checkout, so
#       infrastructure routinely runs under its SOURCE path and a prefix test on the config dir is
#       structurally blind to it (this repo's own landed-vs-live lesson, one process table over).
#   (b) the rest name their real argument at argv[2] or beyond, and widening the scan to the whole
#       command line is the defect proc-scope.sh exists to prevent.
#
# So the ROOT test is the ALLOWLIST direction, which separates every member above cleanly:
#
#     a root's cwd is under the worktree AND argv[0] or argv[1], RESOLVED AGAINST THAT CWD,
#     is an existing path under the worktree.
#
# `bash /wt/scripts/ship-land.sh` and `./scripts/ship-land.sh` both qualify; `sleep 25`, `zsh -c`,
# `tee -a`, `Python -` and a sibling repo's `cc-pane-runner` all fail on argv POSITION, not on a
# name. D8's own falsifier for this direction — `bats-exec-test`, whose worktree path sits at
# argv[2] — dissolves: its PARENT `bats tests/foo.bats` resolves argv[1] against its cwd, matches,
# and the descendant closure picks the whole suite up. That is why the closure is not optional.
#
# THE FAIL DIRECTION THEREFORE FLIPS FOR THIS ARM, DELIBERATELY, AND IT IS SAFE ONLY BECAUSE THIS
# ARM IS NO LONGER THE ONLY SENSOR. D8 chose fail-toward-BUSY when the process scan was the whole
# design; A10 §4 then showed the beat answers "am I working" directly, exactly, and for free, and
# demoted the scan to the Stop-time question it is actually good at — "did I leave a backgrounded
# job running?", where the job is by construction a repo script or a test runner started from the
# repo. A scan that reads BUSY in an idle worktree answers nothing at all (MEMORY:
# alarm-polarity-and-attention-budget), which is a worse failure than a missed exotic job.
# KNOWN RESIDUAL, named rather than hidden: a job whose argv names no worktree path — `pnpm build`
# from the repo root is the shape — is MISSED by this arm. It is still caught by the beat whenever
# the session is inside a turn; only a backgrounded one at a Stop is invisible. Seam for extending:
# CC_BUSY_JOB_EXTRA (space-separated argv0 basenames always treated as work).
#
# The infra rules are KEPT under the allowlist rather than deleted: a hook or watcher launched from
# inside the worktree can name a worktree path (a repo script IS what most of them are), and
# "wake/watchdog infrastructure is not work" is the distinction that makes IDLE-ARMED meaningful.
_sb_filter_candidates() {  # <exclude-set> ; table on stdin → surviving "<pid>" lines on stdout
  awk -v ex=" ${1:-} " -v roots="$(_sb_config_roots)" \
      -v utils="${CC_BUSY_UTIL_INFRA:-caffeinate pmset}" '
    function base(p,  n,a) { n = split(p, a, "/"); return a[n] }
    BEGIN { nr = split(roots, R, ":"); nu = split(utils, U, " ") }
    {
      pid = $1; if (pid !~ /^[0-9]+$/) next
      if (index(ex, " " pid " ")) next
      t0 = $3; t1 = $4
      b0 = base(t0)
      if (b0 == "claude" || b0 == "node" || b0 ~ /^claude-/) next
      if (index($0, "/node_modules/.bin/claude")) next
      for (i = 1; i <= nr; i++) {
        if (R[i] == "") continue
        if (index(t0, R[i] "/") == 1) next
        if (index(t1, R[i] "/") == 1) next
      }
      for (i = 1; i <= nu; i++) if (b0 == U[i]) next
      line = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", line)
      print pid "\t" line
    }'
}

_sb_is_infra() {  # <command line> → 0 when this process is wake/watchdog infrastructure, not work.
                  # REFERENCE spelling of the rule, for readers and tests — it runs the SAME awk
                  # over one synthetic row, so it cannot disagree with the bulk path.
  [ -z "$(printf '1 0 %s\n' "${1:-}" | _sb_filter_candidates "")" ]
}

sb_busy_jobs() {  # [<dir>] → "<n> <sample-argv>" on stdout, rc 0, when a job of mine is executing;
                  #           empty + rc 1 otherwise (including every unreadable case).
                  # THE SAMPLE IS NOT A NICETY — it is what makes the fail-toward-WORK correctable.
  _sb_src_once proc-scope.sh ps_scope_all || return 1
  local root snap ex roots sel n sample cand candrows first _sb_tf _sb_up _sb_dn
  root="$(ps_scope_physical "${1:-.}")" || return 1
  snap="$(ps_scope_all 2>/dev/null)"; [ -n "$snap" ] || return 1
  # SELF EXCLUSION IS BOTH DIRECTIONS. Ancestors, because this reader must never count the hand
  # holding it. DESCENDANTS too, because a `$(…)` subshell INHERITS its parent's argv — so a probe
  # whose command line names a repo file re-selects itself and reports its own reader as work
  # (measured while building this: the sample came back as this very function's invocation). That
  # is the fixture lesson in tests/pkill-scope.bats one layer down — argv is not identity — arriving
  # from the other side. A genuinely backgrounded job is not in this subtree: it outlives the shell
  # that spawned it and is reparented, which is precisely the case this arm exists to catch.
  _sb_up="$(ps_scope_ancestors "$$" "$snap")"
  _sb_dn="$(ps_scope_descendants "$$ " "$snap" "")"
  ex=" $(printf '%s %s' "$_sb_up" "$_sb_dn" | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ')"
  # TWO PASSES, because cwd is the expensive fact. Pass 1 narrows by the CHEAP argv-position rules
  # (self/ancestor · a session is not a job · infrastructure); pass 2 resolves cwd for the survivors
  # in ONE lsof. Per-pid resolution over the whole table is what made the naive form unusably slow.
  candrows="$(printf '%s\n' "$snap" | _sb_filter_candidates "$ex")"
  [ -n "$candrows" ] || return 1
  cand="$(printf '%s\n' "$candrows" | cut -f1 | tr '\n' ' ')"
  [ -n "$cand" ] || return 1
  # Containment in awk for the same reason the filter is: this is ~1,000 rows on a Stop-hook path.
  # `index(cwd, root) == 1` with the explicit at-root case IS `ps_scope_under`, and the root is
  # PHYSICAL (resolved above), which is the property that makes a prefix test a real scope.
  # Pass 2, in awk for the same reason: ~1,000 rows on a Stop-hook path. It joins each candidate's
  # cwd to its argv and applies BOTH halves of the root test — containment (a real, physical-path
  # scope) and the argv-position path rule above. `-v x=` carries the extend seam.
  # Pass 2, in awk for the same reason: ~1,000 rows on a Stop-hook path. It joins each candidate's
  # cwd to its argv and applies BOTH halves of the root test — containment (a real, physical-path
  # scope) and the argv-position path rule above. The `test -e` fork runs ONLY for processes that
  # already passed containment (9 of 1,309 on the measured box), never per candidate.
  _sb_tf="$(mktemp "${TMPDIR:-/tmp}/sb-cand.XXXXXX" 2>/dev/null)" || return 1
  printf '%s\n' "$candrows" > "$_sb_tf"
  roots="$(ps_scope_cwd_map "$cand" | awk -F'\t' -v r="$root" -v x="${CC_BUSY_JOB_EXTRA:-}" \
                                          -v maxtok="${CC_BUSY_MAX_ARGV:-8}" '
      function base(p,  n,a) { n = split(p, a, "/"); return a[n] }
      function under(p) { return (p == r || index(p, r "/") == 1) }
      # A TOKEN-WISE PATH RESOLUTION, which is NOT the substring scan proc-scope.sh forbids: each
      # argv token is resolved against the process cwd and must EXIST under the worktree. `case
      # "$rest" in *ship-land.sh*` matches a peer that merely NAMES the file; this matches only a
      # token that IS a file in this worktree. The one population that could still defeat it — a
      # Claude session, whose argv embeds a whole prompt and so can contain a real repo path — is
      # already dropped by the session test above, which is why widening past argv[0..1] is safe
      # HERE and was not safe THERE. Bounded to the first `maxtok` tokens so a pathological argv
      # cannot turn this into an unbounded stat loop.
      function names_wt(cmd, c,  n, a, i, q) {
        n = split(cmd, a, " ")
        if (n > maxtok) n = maxtok
        for (i = 1; i <= n; i++) {
          q = a[i]
          if (q == "" || substr(q,1,1) == "-") continue
          if (substr(q,1,1) != "/") q = c "/" q
          gsub(/\/\.\//, "/", q)
          if (!under(q)) continue
          if (system("test -e \"" q "\"") == 0) return 1
        }
        return 0
      }
      NR == FNR { if (NF >= 2) CMD[$1] = $2 ; next }
      NF == 2 && $2 != "" && under($2) {
        if (nx == 0 && x != "") nx = split(x, X, " ")
        if (nx > 0) { split(CMD[$1], B, " "); for (i = 1; i <= nx; i++) if (base(B[1]) == X[i]) { printf "%s ", $1; next } }
        if (names_wt(CMD[$1], $2)) printf "%s ", $1
      }' "$_sb_tf" -)"
  rm -f "$_sb_tf"
  [ -n "$roots" ] || return 1
  sel="$(ps_scope_descendants "$roots" "$snap" "$ex")"
  n="$(printf '%s' "$sel" | tr ' ' '\n' | awk 'NF' | sort -u | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] 2>/dev/null || return 1
  # Sample = the FIRST root's argv, trimmed to 140 chars. NOT 90: a worktree path is ~60 characters
  # before the program name even starts, so the shorter cap truncated the one token the operator
  # needs — the sample was `bash /private/var/folders/.../wt/sc` with `ship-land.sh` cut off. The
  # sample is what makes this arm's fail direction correctable, so a cap that hides the program
  # defeats it. (Caught by tests/session-busy.bats, not by reading.) A root is a process whose own cwd is in the worktree,
  # so it names the job rather than one of its incidental children.
  first="$(printf '%s' "$roots" | tr ' ' '\n' | awk 'NF' | sort -n | head -1)"
  sample="$(printf '%s\n' "$snap" | awk -v q="$first" '$1==q {$1="";$2="";sub(/^ +/,"");print substr($0,1,140); exit}')"
  printf '%s %s' "$n" "$sample"
}

# ── IDLE ARMS — every one already has an O(1) reader; none needs a process scan ──────────────────
# goal · continue sentinel · undrained peer mail · open custody debt. Custody is INJECTED
# (CC_BUSY_CUSTODY_OPEN) rather than re-read: wrap-ledger already computes it, and a second reader
# of one store is the drift this repo has paid for before.
sb_idle_arms() {  # [<dir>] [<transcript>] → space-separated arm names ("" when none)
  local dir="${1:-.}" tp="${2:-}" arms="" u pdir
  # PHYSICAL PATH, and it is load-bearing rather than tidy: session-continue.sh keys its sentinel on
  # hash(config-dir | cwd), and the producer's cwd is physical — so on macOS a `/tmp/...` spelling
  # hashes DIFFERENTLY from the `/private/tmp/...` the writer used, the file test misses, and an
  # ARMED session reports IDLE-DEAF. Measured on the first draft of this function.
  _sb_src_once proc-scope.sh ps_scope_physical >/dev/null 2>&1 || true
  pdir="$(ps_scope_physical "$dir" 2>/dev/null)" || pdir=""
  [ -n "$pdir" ] || pdir="$( cd "$dir" 2>/dev/null && pwd -P )" || pdir="$dir"
  [ -n "$pdir" ] || pdir="$dir"
  if [ -n "$tp" ] && [ -f "$tp" ] && _sb_src_once goal-state.sh goal_live_condition; then
    goal_live_condition "$tp" >/dev/null 2>&1 && arms="$arms goal"
  fi
  if _sb_src_once continue-sentinel.sh continue_sentinel_for; then
    [ -f "$(continue_sentinel_for "$pdir" 2>/dev/null)" ] 2>/dev/null && arms="$arms continue"
  fi
  u="${CC_PANE_ID:-}"; [ -n "$u" ] || u="${ITERM_SESSION_ID##*:}"
  if [ -n "$u" ] && _sb_src_once mailbox-pending.sh mailbox_has_pending; then
    mailbox_has_pending "$u" >/dev/null 2>&1 && arms="$arms mail"
  fi
  case "${CC_BUSY_CUSTODY_OPEN:-0}" in ''|0|*[!0-9]*) : ;; *) arms="$arms custody" ;; esac
  printf '%s' "${arms# }"
}

sb_permpend() {  # <sid> → "<age_s> <tool>" when a permission prompt is pending for this session
  local sid="${1:-}" d f ts
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  d="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"
  f="$d/$sid.json"; [ -f "$f" ] || return 1
  ts="$(jq -r '.ts // empty' "$f" 2>/dev/null)"
  case "$ts" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s' "$(( $(_sb_now) - ts ))" "$(jq -r '.tool_name // "?"' "$f" 2>/dev/null)"
}

# ── THE SENSOR ───────────────────────────────────────────────────────────────────────────────────
# session_busy_live <sid> [<dir>] [<transcript>]
#   stdout: "<STATE> <suspect> <age_s> <src> <evidence>"
#   rc    : 0 iff STATE=BUSY, 1 otherwise (an idle/unknown answer is not an error)
#   STATE : BUSY | IDLE-ARMED | IDLE-DEAF | GONE | UNKNOWN     src: beat | job | none | error
#
# BUSY-SUSPECT is a QUALIFIER on BUSY, not a fourth state: `kind=prompt` with a transcript that has
# not moved for CC_BUSY_SUSPECT_S (default 900 s). Measured basis: every honest BUSY pane on the
# box had written within 252 s, and the one real wedge sat at 2,846 s — so 900 s is ~3.5x above the
# working population and ~3x below the incident. When a permission beacon exists it is named in the
# evidence, because that turns a suspicion into an instruction.
session_busy_live() {
  local sid="${1:-}" dir="${2:-.}" tp="${3:-}" j kind pid ls age now jobs arms pp suspect=0 tage
  now="$(_sb_now)"

  if [ -n "$sid" ] && _sb_src_once cc-beat.sh cb_last_beat; then
    j="$(cb_last_beat "$sid" 2>/dev/null || true)"
    if [ -n "$j" ]; then
      kind="$(printf '%s' "$j" | jq -r '.kind // empty' 2>/dev/null)"
      pid="$(printf '%s'  "$j" | jq -r '.pid  // empty' 2>/dev/null)"
      ls="$(printf '%s'   "$j" | jq -r '.lstart // empty' 2>/dev/null)"
      age="$(printf '%s'  "$j" | jq -r '.t // empty' 2>/dev/null)"
      case "$age" in ''|*[!0-9]*) age=0 ;; *) age=$(( now - age )); [ "$age" -lt 0 ] && age=0 ;; esac
      case "$pid" in ''|*[!0-9]*) pid="" ;; esac
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && _sb_lstart_matches "$ls" "$pid"; then
        if [ "$kind" = "prompt" ]; then
          if [ -n "$tp" ] && [ -f "$tp" ]; then
            tage=$(( now - $(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo "$now") ))
            [ "$tage" -lt 0 ] && tage=0
            [ "$tage" -gt "${CC_BUSY_SUSPECT_S:-900}" ] 2>/dev/null && suspect=1
          fi
          pp="$(sb_permpend "$sid" 2>/dev/null || true)"
          if [ -n "$pp" ]; then
            printf 'BUSY %s %s beat permission:%s\n' "$suspect" "$age" "${pp% *}s/${pp##* }"
          else
            printf 'BUSY %s %s beat prompt\n' "$suspect" "$age"
          fi
          return 0
        fi
      else
        # The beat exists and its process does not. GONE is reported, never rendered BUSY — a
        # frozen `prompt` beat from a dead session is the one measured false-BUSY.
        jobs="$(sb_busy_jobs "$dir" 2>/dev/null || true)"
        # Age 0, not the beat's: a job-arm BUSY is evidence about a RUNNING job, and
        # reporting a 31-day-stale beat's age beside it would date the wrong fact.
        if [ -n "$jobs" ]; then printf 'BUSY 0 0 job %s\n' "$jobs"; return 0; fi
        printf 'GONE 0 %s beat pid-%s\n' "$age" "${pid:-none}"
        return 1
      fi
    else
      # No beat for this sid. Distinguish a beat-less SESSION inside a live world (suspicious) from
      # a beat-less WORLD (the producer is not deployed) — collapsing them is the absence-alarm trap
      # cc-beat.sh's own existence gate exists to prevent.
      if ! cb_system_live 2>/dev/null; then
        jobs="$(sb_busy_jobs "$dir" 2>/dev/null || true)"
        [ -n "$jobs" ] && { printf 'BUSY 0 0 job %s\n' "$jobs"; return 0; }
        printf 'UNKNOWN 0 0 none beat-system-absent\n'; return 1
      fi
    fi
  fi

  # Q2 arm: at a Stop the beat says `stop` and is RIGHT — the model is not thinking. A backgrounded
  # gate is still executing, and this is the only sensor that can see it.
  jobs="$(sb_busy_jobs "$dir" 2>/dev/null || true)"
  if [ -n "$jobs" ]; then printf 'BUSY 0 %s job %s\n' "${age:-0}" "$jobs"; return 0; fi

  arms="$(sb_idle_arms "$dir" "$tp" 2>/dev/null || true)"
  if [ -n "$arms" ]; then printf 'IDLE-ARMED 0 %s none %s\n' "${age:-0}" "$arms"; return 1; fi
  if [ -z "$sid" ]; then printf 'UNKNOWN 0 0 none no-session-id\n'; return 1; fi
  printf 'IDLE-DEAF 0 %s none no-wake-path\n' "${age:-0}"
  return 1
}

sb_state()  { session_busy_live "$@" | awk '{print $1}'; }
sb_detail() { session_busy_live "$@"; }

# ── THE LINE — ONE COMPOSER, shared by the PUSH and PULL surfaces ────────────────────────────────
# D8's rejected alternatives lead with "a new skill/command would be a SECOND renderer for a
# question that already has one — two answers to reconcile instead of one to trust." That applies
# to the sentence just as much as to the facts, so the Stop hook's notice and `/wrap`'s typed
# fallback are composed HERE and nowhere else; a thin caller is fine, a parallel implementation is
# the thing being rejected.
#
# TWO MODES, because silence means opposite things on the two surfaces:
#   push (always=0) — the Stop hook. Prints ONLY what is news; a line at every close is wallpaper.
#   pull (always=1) — `/wrap`. The operator ASKED, so "working, normally" is a real answer and
#                     silence would be indistinguishable from a broken reader.
sb_render_line() {  # <state> <suspect> <age> <src> <permpend> <permpend_age> <rung> <always> <sample…>
  local st="${1:-UNKNOWN}" sus="${2:-0}" age="${3:-0}" src="${4:-none}" pp="${5:-0}" ppa="${6:-0}"
  local rung="${7:-?}" always="${8:-0}" sample; shift 8 2>/dev/null || true; sample="$*"
  case "$sus" in 1)
    printf '⏳ BUSY %ss with nothing written for longer — this pane may be WEDGED, not working.\n' "$age"
    [ "$pp" = "1" ] && printf '   Blocked on a permission prompt for %ss — it needs YOUR keystroke, in that pane.\n' "$ppa"
    [ -n "$sample" ] && printf '   evidence: %s\n' "$sample"
    return 0 ;;
  esac
  if [ "$pp" = "1" ] && [ "$st" != "BUSY" ]; then
    printf '⏳ Idle on a PERMISSION PROMPT for %ss — nothing is executing; it needs your keystroke in that pane.\n' "$ppa"
    return 0
  fi
  if [ "$st" = "IDLE-DEAF" ] && [ "$rung" != "✅" ]; then
    printf '⏳ IDLE with no wake path armed — nothing of mine is executing and nothing will resume it (rung %s).\n' "$rung"
    printf '   Not a gate running long: no goal, no continue sentinel, no pending peer mail, no open custody.\n'
    return 0
  fi
  [ "$always" = "1" ] || return 1
  case "$st" in
    BUSY)       if [ "$src" = "job" ]; then printf '⏳ WORKING — a job of mine is executing: %s\n' "${sample:-?}"
                else printf '⏳ WORKING — this session is inside a turn (beat %ss old).\n' "$age"; fi ;;
    IDLE-ARMED) printf '⏳ IDLE, but a wake path IS armed (%s) — this session will resume by itself.\n' "${sample:-?}" ;;
    IDLE-DEAF)  printf '⏳ IDLE — nothing of mine is executing, and no wake path is armed.\n' ;;
    GONE)       printf '⏳ UNKNOWN — the beat names a process that is gone (%s); no job of mine is executing.\n' "${sample:-?}" ;;
    *)          printf '⏳ UNKNOWN — the working/idling sensor could not read (%s); this is an instrument gap, not an idle verdict.\n' "$src" ;;
  esac
  return 0
}
