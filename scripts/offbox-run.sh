#!/bin/bash
# offbox-run.sh — run a shard of the hermetic partition, and fold shards into ONE verdict.
#
#   offbox-run.sh shard <i> <n> [--out FILE]   run shard i of n; write a per-suite TSV
#   offbox-run.sh all [--out FILE]             run the whole partition in one process
#   offbox-run.sh census [--out FILE]          run EVERY tests/*.bats, partition or not (see below)
#   offbox-run.sh verdict <dir|file...>        fold TSVs into the off-box stamp JSON on stdout
#   offbox-run.sh --selftest                   RED-proves the classifier and the fold
#
# ONE IMPLEMENTATION, TWO CALLERS. `.github/workflows/hermetic.yml` runs this, and so can a human
# reproducing a CI red on their own box — same classifier, same bound, same fold. A workflow that
# inlines its own shell is a second implementation of the verdict, and the two drift on the first
# edit nobody makes twice.
#
# ── THE $HOME PROBE IS THE HERMETICITY ORACLE, NOT A TIDINESS MEASURE ────────────────────────────
# Every suite runs with `HOME` pointed at a FRESH EMPTY DIRECTORY, so `~/.claude` does not exist.
# That exact probe is what `scripts/host-suites.manifest` used to de-list five suites that had been
# excluded for a property none of them had (*"each suite was run in a fresh detached worktree with
# HOME pointed at an EMPTY directory … A suite whose subject is the deployed layer CANNOT pass
# that"*). Running the off-box corpus under it makes the CI strictly stronger than a plain
# `bats tests/`: a suite that silently reads the runner's home is a suite that would read the
# operator's, and here it goes red where it is cheap to see rather than flaky where it is not.
#
# ── A CUT IS NOT A RED (R6), AND THE TAP BODY IS THE DISCRIMINATOR ───────────────────────────────
# `LAND_PIPELINE_V2` R6 — *"a non-verdict is never a red"* — is the rule this repo already enforces
# on the land path and violated on the deploy path, at a measured cost of scoring 3 non-verdicts as
# failures. It binds here too, and bats makes it easy to get wrong: bats exits non-zero for a
# FAILING TEST and for a suite that died having named nothing, so the exit code cannot tell a
# verdict from a wedge. The honest discriminator is the TAP body:
#     `not ok` lines > 0                 ⇒ red   — a claim about the CODE
#     rc != 0 and zero `not ok` lines    ⇒ cut   — a claim about the MACHINE; proves nothing
#     rc == 0 and `ok` lines > 0         ⇒ green
#     rc == 0 and zero test lines        ⇒ empty — a suite that asserted nothing is not a green
# `empty` exists because a green over zero tests is the vacuous pass this repo has paid for before;
# it is folded as NOT-green so it can never manufacture a verdict from an empty file.
#
# ── WHAT THE FOLD MAY AND MAY NOT CONCLUDE ───────────────────────────────────────────────────────
# GREEN iff every suite in the partition ran and every one is `green`. Any `red` ⇒ red. Otherwise
# (any `cut`/`empty`/`missing`) ⇒ `cut` — never green, never red. The asymmetry is the whole point of
# a second opinion: this corpus is a SUBSET, so it can acquit only what it actually ran, and a
# machine failure on a runner we do not own is not evidence about anyone's code.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="${CC_OFFBOX_ROOT:-$(cd "$(dirname "$SELF")/.." && pwd)}"
PARTITION_SH="${CC_OFFBOX_PARTITION:-$(dirname "$SELF")/offbox-partition.sh}"

# Per-suite wall bound. A suite that overruns is a CUT (proves nothing), never a red — so this
# number can never convict anyone's code, only withhold an acquittal. Default sized off the on-box
# corpus, where the slowest single suite is documented at ~50 min solo: anything near that is not a
# candidate for a per-commit second opinion and should earn an exclusion line with that measurement.
SUITE_BOUND_S="${CC_OFFBOX_SUITE_BOUND_S:-300}"

# ── BATS MUST BE THE REAL BINARY, NEVER THE ADMISSION WRAPPER ────────────────────────────────────
# MEASURED while writing this file, by the F6f control below going red before CI had ever run. On
# the operator's box the bare name `bats` PATH-resolves to `~/.claude/bin/cc-bats`, a QoS/admission
# WRAPPER — and it CREATES `$HOME/.claude/state/bats-roots.d` on every invocation. Controls, run
# side by side against one empty $HOME:
#     /opt/homebrew/bin/bats  → $HOME/.claude does NOT appear
#     ~/.claude/bin/cc-bats   → $HOME/.claude/state/bats-roots.d DOES
# Two distinct costs, and the second is the one that would have been invisible. (1) The harness
# writes into the very fixture home it created to prove nothing writes there, so the empty-$HOME
# oracle would be measuring its own residue. (2) cc-bats can REFUSE admission under load — a
# deliberate non-verdict that is "not a test result" by its own documentation — so a wrapper
# refusal would enter this corpus as a suite outcome. Neither happens in CI, where no wrapper
# exists; both happen to a human reproducing a CI red locally, which is exactly when the two must
# agree (memory: version-identity-is-the-running-process-not-the-launcher).
# So: resolve past any bats living under the live layer. An explicit CC_OFFBOX_BATS always wins.
resolve_bats() {
  if [ -n "${CC_OFFBOX_BATS:-}" ]; then printf '%s\n' "$CC_OFFBOX_BATS"; return 0; fi
  local c live="${HOME:-/nonexistent}/.claude"
  # `command -v` gives the FIRST match; walk every PATH entry so a wrapper earlier on PATH is
  # skipped rather than merely detected.
  local IFS=:
  for c in $PATH; do
    case "$c" in "$live"|"$live"/*) continue ;; esac
    if [ -x "$c/bats" ]; then printf '%s\n' "$c/bats"; return 0; fi
  done
  # Nothing outside the live layer. Fall back to the bare name so the ordinary "bats is missing"
  # error is what the caller sees, rather than a silent skip.
  printf 'bats\n'
}
BATS_BIN="$(resolve_bats)"

die() { printf 'offbox-run: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

# Resolve a bounded-run prefix. macOS ships no `timeout`; the box under test has GNU coreutils, so
# both names are tried. ABSENCE IS FATAL rather than silently unbounded: an unbounded suite in a
# sharded CI job does not fail, it hangs the job until the runner is reaped, and a reaped job
# reports nothing at all — the least informative possible outcome.
resolve_timeout() {
  local c
  for c in timeout gtimeout; do
    if command -v "$c" >/dev/null 2>&1; then printf '%s\n' "$c"; return 0; fi
  done
  return 1
}

# Classify ONE suite run. Echoes: <state> <ok> <notok> <rc> <secs>
run_one() {
  local suite="$1" tmo="$2"
  local home out rc start el ok notok state

  home="$(mktemp -d)" || { printf 'cut 0 0 99 0\n'; return 0; }
  start="$(date +%s)"
  # env -i so the runner's own environment cannot leak in; the allowlist below is exactly what a
  # suite may assume. TMPDIR is fresh per suite so two suites cannot collide on a scratch path
  # (rule 4 of scripts/test-hermeticity-lint.sh, the per-run-uniqueness rule).
  mkdir -p "$home/tmp"
  # CWD is the repo root, matching how scripts/postland-verify.sh runs the corpus: suites resolve
  # sibling paths relative to the checkout, so running from anywhere else changes what is under test.
  # `trap - TERM` RESTORES the default disposition for the suite: run_list ignores SIGTERM to survive
  # a process-killing suite (see § THE RUNNER IGNORES SIGTERM), and an ignored disposition is
  # inherited across exec — leaving it set would make the suite immune to its own `timeout`, which
  # is the bound that keeps a wedged suite from eating the job.
  out="$(cd "$ROOT" && trap - TERM && env -i \
        HOME="$home" \
        TMPDIR="$home/tmp" \
        PATH="${PATH}" \
        TERM=dumb \
        LC_ALL=C \
        CC_OFFBOX=1 \
        "$tmo" -k 10 "$SUITE_BOUND_S" "$BATS_BIN" "$suite" </dev/null 2>&1)"
  rc=$?
  el=$(( $(date +%s) - start ))

  ok="$(printf '%s\n' "$out"    | grep -c '^ok '     || true)"
  notok="$(printf '%s\n' "$out" | grep -c '^not ok ' || true)"

  # Quoted deliberately: `cut` is also a real binary, and an unquoted `state=cut` trips SC2209 —
  # the lint is right that the two readings are indistinguishable at a glance.
  if   [ "$notok" -gt 0 ];                     then state="red"
  elif [ "$rc" -ne 0 ];                        then state="cut"
  elif [ "$ok" -gt 0 ];                        then state="green"
  else                                              state="empty"
  fi

  # A red's TAP body is the only actionable artifact a CI red produces; keep it next to the TSV.
  if [ "$state" = red ] || [ "$state" = cut ]; then
    if [ -n "${CC_OFFBOX_LOGDIR:-}" ]; then
      mkdir -p "$CC_OFFBOX_LOGDIR" 2>/dev/null
      printf '%s\n' "$out" > "$CC_OFFBOX_LOGDIR/$(basename "$suite").log" 2>/dev/null
    fi
  fi

  rm -rf "$home" 2>/dev/null
  printf '%s %s %s %s %s\n' "$state" "$ok" "$notok" "$rc" "$el"
}

# ── THE RUNNER IGNORES SIGTERM, BECAUSE SOME SUITES KILL PROCESSES FOR A LIVING ──────────────────
# MEASURED twice on trunk. Run 31371884433: shard 6 exited **143 (SIGTERM)** the instant after
# tests/pkill-scope.bats reported GREEN, losing the 34 suites behind it. Run 31373386826: shard 10
# died the same way at tests/cc-reaper.bats. The suites pass their own assertions and then kill the
# process running them — this repo's own land docs record the mechanism, that `pkill -f bats…`
# reaches every bats process on a box because they all share a command-line substring, and a CI
# runner is simply another box where that is true.
#
# A PROCESS GROUP DOES NOT HELP, which is why this is a trap and not an isolation trick: the
# per-suite `timeout` already gives each suite its own group, and a kill that selects by command
# line — or by a pid a reaper discovered — crosses groups by design. That is the point of the tools
# under test, so the runner cannot out-isolate them; it can only decline to die.
#
# THE COST, STATED: this shard will not honour a SIGTERM-based cancellation. That is bounded by the
# job's own `timeout-minutes`, which escalates to SIGKILL, so the worst case is a cancelled job
# taking its full timeout instead of stopping promptly. Against that: a lost shard is 34 suites of
# evidence AND a short fold that refuses the whole run's green, so the trade is heavily one-sided.
#
# THE PAYOFF BEYOND SURVIVAL: with the trap, the hostile suite's own row still gets written, so the
# TSV NAMES it instead of ending mid-file. Each of the two measured instances above cost a ~25-minute
# diagnose-land-rerun cycle to identify from a log tail; after this they identify themselves.
#
# THE SUITE LIST ARRIVES ON STDIN, SO EVERY CHILD MUST BE SEALED OFF FROM IT — see the `</dev/null`
# in run_one. MEASURED on the first real CI run (2026-08-10, run 31362043861): shards 1, 4 and 9
# stopped after 3, 25 and 17 suites of their 37-38, each one immediately after a suite that reads
# stdin — the suite consumed the REST OF THE SHARD LIST out of this loop's pipe. The step exited 0
# and its log simply ended, so the failure looked like nothing at all; only the fold's short-count
# rule caught it (306 ran against 373 expected ⇒ `cut`, never a green over what reported).
# `scripts/postland-verify.sh:2189` and `scripts/ship-land.sh:875` both already carry `</dev/null`
# on their bats invocation for this exact reason — the answer was in the tree twice, and this file
# had to rediscover it in CI.
run_list() {
  # shellcheck disable=SC2064  # intentional: ignore TERM for the whole loop, restored per suite.
  trap '' TERM
  local out="${1:-/dev/stdout}"; shift
  local tmo; tmo="$(resolve_timeout)" || die "no timeout(1) or gtimeout(1) on PATH — refusing to run unbounded (a hung shard reports nothing at all)" 2

  command -v "$BATS_BIN" >/dev/null 2>&1 || die "bats not found on PATH as '$BATS_BIN'" 2

  printf '# suite\tstate\tok\tnotok\trc\tsecs\n' > "$out"
  local suite line
  while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    if [ ! -e "$ROOT/$suite" ]; then
      printf '%s\tmissing\t0\t0\t0\t0\n' "$suite" >> "$out"
      continue
    fi
    line="$(run_one "$suite" "$tmo")"
    # shellcheck disable=SC2086
    set -- $line
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$suite" "$1" "$2" "$3" "$4" "$5" >> "$out"
    printf '%-52s %-6s ok=%-4s notok=%-3s %ss\n' "$suite" "$1" "$2" "$3" "$5" >&2
  done
}

cmd_shard() {
  local i="${1:-}" n="${2:-}"; shift 2 2>/dev/null || true
  local out=/dev/stdout
  [ "${1:-}" = "--out" ] && { out="${2:?--out needs a path}"; }
  bash "$PARTITION_SH" shard "$i" "$n" | run_list "$out"
}

cmd_all() {
  local out=/dev/stdout
  [ "${1:-}" = "--out" ] && { out="${2:?--out needs a path}"; }
  bash "$PARTITION_SH" list | run_list "$out"
}

# CENSUS — run EVERY suite, partition or not. This is the arm that keeps the exclusion manifest
# HONEST in the direction a green producer is blind to: an excluded suite that passes off-box run
# after run has lost its reason to be excluded, and only a run that INCLUDES it can say so. Never
# gating; its output is evidence for the next edit to the manifest.
cmd_census() { # [<i> <n>] [--out FILE] — sharded exactly like the partition, or whole if unsharded
  local i="" n=""
  case "${1:-}" in [0-9]*) i="$1"; n="${2:?census: shard index needs a count}"; shift 2 ;; esac
  local out=/dev/stdout
  [ "${1:-}" = "--out" ] && { out="${2:?--out needs a path}"; }
  # `find`, not `ls` (SC2012) — and it also matches how offbox-partition.sh and postland-verify.sh
  # enumerate the corpus, so the census and the partition cannot disagree about what a suite is.
  local all; all="$( cd "$ROOT" && find tests -maxdepth 1 -type f -name '*.bats' 2>/dev/null | LC_ALL=C sort )"
  if [ -n "$i" ]; then
    [ "$i" -ge 1 ] && [ "$i" -le "$n" ] || die "census: shard index $i out of range 1..$n" 2
    printf '%s\n' "$all" | awk -v i="$i" -v n="$n" 'NR % n == (i % n)' | run_list "$out"
  else
    printf '%s\n' "$all" | run_list "$out"
  fi
}

cmd_verdict() {
  [ $# -ge 1 ] || die "verdict: need a directory or TSV files" 2
  local files=()
  local a
  for a in "$@"; do
    if [ -d "$a" ]; then
      while IFS= read -r f; do files+=("$f"); done < <(find "$a" -type f -name '*.tsv' | LC_ALL=C sort)
    else
      files+=("$a")
    fi
  done
  [ "${#files[@]}" -gt 0 ] || die "verdict: no TSV inputs found" 2

  # The partition is read as a LIST, not merely counted. Counting can only tell you that suites are
  # missing; the list is what lets the fold NAME them, and a hole nobody can name is a hole nobody
  # fixes — measured below.
  local plist; plist="$(mktemp)"
  bash "$PARTITION_SH" list >"$plist" 2>/dev/null || :
  cat "${files[@]}" | awk -v plist="$plist" '
    BEGIN {
      FS="\t"; green=0; red=0; cut=0; empty=0; missing=0; n=0; secs=0; part_n=0
      while ((getline line < plist) > 0) if (line != "") { want[line]=1; ord[part_n++]=line }
    }
    /^#/ { next }
    NF < 6 { next }
    {
      n++; secs += $6; seen[$1]=1
      if ($2 == "green")   green++
      else if ($2 == "red") { red++;  fails[nf++] = $1 }
      else if ($2 == "cut") { cut++;  nonv[nn++]  = $1 }
      else if ($2 == "empty") { empty++; nonv[nn++] = $1 }
      else { missing++; nonv[nn++] = $1 }
    }
    END {
      # A fold over FEWER suites than the partition holds is itself a non-verdict: a shard that never
      # reported is indistinguishable, in the numbers alone, from a partition that got smaller.
      for (i = 0; i < part_n; i++) if (!(ord[i] in seen)) unrep[un++] = ord[i]
      short = (part_n > 0 && (n < part_n || un > 0))

      # UNREPORTED OUTRANKS RED, and that ordering is the fix. A shard whose job DIES leaves no row
      # of any state — not green, not red, not cut — so every counter above is blind to it, and the
      # old red-first test published "red, 7 failing" over a corpus in which 41 suites were never
      # judged at all. short was computed and then discarded in exactly the runs where it mattered.
      # MEASURED on run 31570936250: the shard-1 job was CANCELLED by a runner shutdown signal, and
      # "if: always()" does not survive a cancelled job, so its artifact never uploaded; the
      # unreported set is set-identical to the 41 suites of shard 1. Four consecutive runs died the
      # same way. The old shape also fed the paste-ready cure block in the workflow, which invited
      # manifest entries for 7 suites while 41 went unexamined — an exclusion list grown from a
      # measurement that was itself incomplete.
      #
      # NOTE FOR THE NEXT EDITOR: this awk program is single-quoted, so an apostrophe anywhere in
      # these comments TERMINATES it and the rest parses as shell. Write around it.
      if (short)                         v = "cut"
      else if (red > 0)                  v = "red"
      else if (cut+empty+missing > 0)    v = "cut"
      else if (n > 0)                    v = "green"
      else                               v = "cut"

      printf "{\"verdict\":\"%s\",\"suites\":%d,\"expected\":%d,\"green\":%d,\"red\":%d,\"nonverdict\":%d,\"unreported\":%d,\"run_s\":%d,\"failing\":[", v, n, part_n, green, red, cut+empty+missing, un, secs
      for (i = 0; i < nf; i++) printf "%s\"%s\"", (i ? "," : ""), fails[i]
      printf "],\"nonverdict_suites\":["
      for (i = 0; i < nn; i++) printf "%s\"%s\"", (i ? "," : ""), nonv[i]
      printf "],\"unreported_suites\":["
      for (i = 0; i < un; i++) printf "%s\"%s\"", (i ? "," : ""), unrep[i]
      printf "]}\n"
    }'
  rm -f "$plist"
}

# ── SELFTEST ─────────────────────────────────────────────────────────────────────────────────────
st_fail=0
chk() { # chk <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s — wanted [%s] got [%s]\n' "$1" "$2" "$3" >&2; st_fail=1; fi
}

cmd_selftest() {
  # NOT `local` — an EXIT trap runs after the function's frame is gone (see the same note in
  # scripts/offbox-partition.sh; a local expands to nothing exactly when the cleanup is due).
  ST_TMP="$(mktemp -d)" || die "selftest: mktemp failed" 1
  trap 'rm -rf "${ST_TMP:-}"' EXIT
  local tmp="$ST_TMP"
  local v

  fold() { CC_OFFBOX_PARTITION="$tmp/fakepart.sh" bash "$SELF" verdict "$1"; }
  # A stub partition of 3 so `expected` is deterministic and the short-fold law is testable.
  printf '#!/bin/bash\nprintf "tests/a.bats\\ntests/b.bats\\ntests/c.bats\\n"\n' > "$tmp/fakepart.sh"

  hdr() { printf '# suite\tstate\tok\tnotok\trc\tsecs\n' > "$1"; }

  # F1 all green over the full expected count ⇒ green
  hdr "$tmp/1.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tgreen\t2\t0\t0\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n' >> "$tmp/1.tsv"
  v="$(fold "$tmp/1.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"
  chk "F1 all green ⇒ green" green "$v"

  # F2 one red ⇒ red, and it names the file
  hdr "$tmp/2.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tred\t1\t2\t1\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n' >> "$tmp/2.tsv"
  v="$(fold "$tmp/2.tsv")"
  chk "F2 a red ⇒ red" red "$(printf '%s' "$v" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"
  case "$v" in *'"failing":["tests/b.bats"]'*) printf 'ok   F2b red names the suite\n' ;;
               *) printf 'FAIL F2b red did not name the suite: %s\n' "$v" >&2; st_fail=1 ;; esac

  # F3 a CUT is not a red AND not a green — the R6 law, in both directions
  hdr "$tmp/3.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tcut\t0\t0\t124\t300\ntests/c.bats\tgreen\t1\t0\t0\t1\n' >> "$tmp/3.tsv"
  chk "F3 a cut ⇒ cut (never red, never green)" cut "$(fold "$tmp/3.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"

  # F4 an EMPTY suite cannot manufacture a green
  hdr "$tmp/4.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tempty\t0\t0\t0\t1\ntests/c.bats\tgreen\t1\t0\t0\t1\n' >> "$tmp/4.tsv"
  chk "F4 an empty suite ⇒ cut" cut "$(fold "$tmp/4.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"

  # F5 THE SHORT FOLD — a missing shard is a non-verdict, not a green over what did report. This is
  # the control for the failure mode that would otherwise be invisible: a dropped matrix job.
  hdr "$tmp/5.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tgreen\t2\t0\t0\t1\n' >> "$tmp/5.tsv"
  chk "F5 a short fold ⇒ cut, never a green over what reported" cut "$(fold "$tmp/5.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"

  # F5c control: the SAME two rows plus the third ⇒ green, so F5 is about the count and nothing else.
  chk "F5c control — the third row flips it green" green "$(fold "$tmp/1.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"

  # F5d UNREPORTED OUTRANKS RED. F5 above only proves a short fold cannot mint a GREEN; it says
  # nothing about a short fold that also contains a red, and that is the case the real runs hit —
  # `red > 0` was tested first, so the verdict published "red" over a corpus in which a whole dead
  # shard was never judged. A red is a claim about the suites that RAN; it cannot also speak for the
  # ones that did not. Two rows, one of them red, against a partition of three.
  hdr "$tmp/5d.tsv"
  printf 'tests/a.bats\tgreen\t3\t0\t0\t1\ntests/b.bats\tred\t1\t2\t1\t1\n' >> "$tmp/5d.tsv"
  v="$(fold "$tmp/5d.tsv")"
  chk "F5d a red beside an UNREPORTED suite ⇒ cut, not red" cut "$(printf '%s' "$v" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"
  case "$v" in *'"unreported":1'*'"unreported_suites":["tests/c.bats"]'*)
                 printf 'ok   F5e the fold NAMES the suite that never reported\n' ;;
               *) printf 'FAIL F5e unreported suite not named: %s\n' "$v" >&2; st_fail=1 ;; esac
  # F5f control — the same red with NOTHING missing is still a red, so F5d is about the hole and
  # not a blanket demotion of every red to a non-verdict.
  chk "F5f control — a red over a COMPLETE fold is still red" red "$(fold "$tmp/2.tsv" | sed 's/.*"verdict":"\([a-z]*\)".*/\1/')"

  # F6 THE LIVE CLASSIFIER, end to end against real bats. F1-F5 exercise only the fold, and a fold
  # test passes unchanged even if run_one classified every suite backwards — so without F6 the half
  # that actually reads bats output would ship unproven. Each case is a real suite, really run.
  if command -v "$BATS_BIN" >/dev/null 2>&1 && resolve_timeout >/dev/null 2>&1; then
    mkdir -p "$tmp/tests"
    printf '@test "p" { true; }\n'   > "$tmp/tests/pass.bats"
    printf '@test "f" { false; }\n'  > "$tmp/tests/fail.bats"
    printf '# no tests here\n'       > "$tmp/tests/none.bats"
    # A suite that outruns the bound: the CUT case. Bound is 2s so this costs ~2s, not 300.
    printf '@test "slow" { sleep 30; }\n' > "$tmp/tests/slow.bats"

    local case_pair name want got partsh
    for case_pair in "pass.bats:green" "fail.bats:red" "none.bats:empty" "slow.bats:cut"; do
      name="${case_pair%%:*}"; want="${case_pair##*:}"
      partsh="$tmp/part-$name.sh"
      printf '#!/bin/bash\nprintf "tests/%s\\n"\n' "$name" > "$partsh"
      got="$(CC_OFFBOX_ROOT="$tmp" CC_OFFBOX_PARTITION="$partsh" CC_OFFBOX_SUITE_BOUND_S=2 \
             bash "$SELF" all 2>/dev/null | awk -F'\t' '$1 ~ /^tests\// {print $2}')"
      chk "F6 live classifier: $name ⇒ $want" "$want" "$got"
    done

    # F6e THE DISCRIMINATOR ITSELF — a red and a cut both exit non-zero, so an implementation that
    # keyed on the exit code would call them the same thing. This asserts they came out DIFFERENT,
    # which is the one property the four cases above could each pass while still being wrong.
    if [ "$st_fail" -eq 0 ]; then
      printf 'ok   F6e red and cut are distinguished (both exit non-zero, only the TAP body separates them)\n'
    fi

    # F6f THE $HOME PROBE IS LIVE — a suite that reads $HOME must see the fixture, not the runner's
    # home. Without this control the empty-HOME oracle could be silently absent and every case above
    # would still pass.
    # shellcheck disable=SC2016  # the single quotes are the POINT: $HOME must expand INSIDE the
    # generated suite at bats runtime, not here. Only the %s — the outer $HOME this run must differ
    # from — is substituted now.
    printf '@test "home is fixtured" { [ "$HOME" != "%s" ]; [ ! -d "$HOME/.claude" ]; }\n' "$HOME" \
      > "$tmp/tests/homeprobe.bats"
    printf '#!/bin/bash\nprintf "tests/homeprobe.bats\\n"\n' > "$tmp/part-home.sh"
    got="$(CC_OFFBOX_ROOT="$tmp" CC_OFFBOX_PARTITION="$tmp/part-home.sh" CC_OFFBOX_SUITE_BOUND_S=30 \
           bash "$SELF" all 2>/dev/null | awk -F'\t' '$1 ~ /^tests\// {print $2}')"
    chk "F6f the empty-\$HOME probe is actually applied" green "$got"

    # F6g A SUITE THAT READS STDIN MUST NOT TRUNCATE THE RUN. The regression control for the defect
    # that cost three shards on the first real CI run: the suite list arrives on this loop's stdin,
    # so a child that reads stdin eats the remainder and the loop ends CLEANLY at exit 0. Two suites
    # here, the first a stdin-eater — a runner without `</dev/null` reports ONE row instead of two.
    printf '@test "eats stdin" { cat >/dev/null; }\n' > "$tmp/tests/aa-stdin-eater.bats"
    printf '@test "after" { true; }\n'                 > "$tmp/tests/zz-after-eater.bats"
    printf '#!/bin/bash\nprintf "tests/aa-stdin-eater.bats\\ntests/zz-after-eater.bats\\n"\n' > "$tmp/part-stdin.sh"
    got="$(CC_OFFBOX_ROOT="$tmp" CC_OFFBOX_PARTITION="$tmp/part-stdin.sh" CC_OFFBOX_SUITE_BOUND_S=30 \
           bash "$SELF" all 2>/dev/null | awk -F'\t' '$1 ~ /^tests\// {n++} END {print n+0}')"
    chk "F6g a stdin-reading suite does not eat the rest of the shard list" 2 "$got"

    # F6h A SUITE THAT SIGTERMS ITS RUNNER MUST NOT TRUNCATE THE RUN. The regression control for the
    # two measured trunk losses (pkill-scope, cc-reaper), each of which cost a whole shard. The
    # fixture walks its OWN ancestor chain and TERMs it — scoped to this process tree, so unlike a
    # bare `pkill -f` it cannot reach a concurrent runner on the same box. A runner without the
    # `trap '' TERM` reports ONE row instead of two.
    # COLLECT the ancestor chain first, THEN kill from the TOP DOWN. Killing upward as you walk is
    # what the first version did and it made this control VACUOUS: hops 1-3 are the suite's own bats
    # processes, so TERMing them killed the walker before it ever reached the runner at hop 5-6, and
    # the control passed against a runner with no trap at all. Measured — real and mutant both
    # reported 2 rows until the order was reversed.
    cat > "$tmp/tests/aa-killer.bats" <<'KILLER'
@test "terminates its own runner" {
  p=$PPID
  chain=""
  for _ in 1 2 3 4 5 6 7; do
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [ -n "$p" ] && [ "$p" -gt 1 ] || break
    chain="$p $chain"          # prepend ⇒ farthest ancestor ends up FIRST
  done
  for q in $chain; do kill -TERM "$q" 2>/dev/null || true; done
  true
}
KILLER
    printf '@test "after the killer" { true; }\n' > "$tmp/tests/zz-after-killer.bats"
    printf '#!/bin/bash\nprintf "tests/aa-killer.bats\\ntests/zz-after-killer.bats\\n"\n' > "$tmp/part-kill.sh"
    got="$(CC_OFFBOX_ROOT="$tmp" CC_OFFBOX_PARTITION="$tmp/part-kill.sh" CC_OFFBOX_SUITE_BOUND_S=30 \
           bash "$SELF" all 2>/dev/null | awk -F'\t' '$1 ~ /^tests\// {n++} END {print n+0}')"
    chk "F6h a suite that SIGTERMs its runner does not truncate the run" 2 "$got"
  else
    printf 'ok   F6 SKIPPED — no bats/timeout on PATH (classifier not exercised)\n'
  fi

  [ "$st_fail" -eq 0 ] || { printf '\noffbox-run --selftest: FAILED\n' >&2; return 1; }
  printf '\noffbox-run --selftest: all controls green\n'
  return 0
}

case "${1:-}" in
  shard)      shift; cmd_shard "$@" ;;
  all)        shift; cmd_all "$@" ;;
  census)     shift; cmd_census "$@" ;;
  verdict)    shift; cmd_verdict "$@" ;;
  --selftest) shift; cmd_selftest "$@" ;;
  -h|--help)  usage ;;
  '')         usage; exit 2 ;;
  *)          die "unknown verb: $1 (try --help)" 2 ;;
esac
