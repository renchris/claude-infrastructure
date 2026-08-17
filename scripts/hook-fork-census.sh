#!/bin/bash
# hook-fork-census.sh — measure the EXECUTED-PATH external-process cost of a PreToolUse hook
# (default subject: hooks/validate-bash.sh), per corpus class.
#
# WHY THIS EXISTS. docs/plans/HOOK_CHAIN_COST.md R-3 (backlog 8942f3b1506d) carries the figure
# "12 grep forks, ~42 ms" for validate-bash.sh. That file is now 1012 lines with 32 static grep
# sites, and §2.2 of the plan says explicitly that a STATIC count is not the target: the hook is
# a long ladder of early returns, so most invocations execute a small prefix of it and a denied
# one executes even less. The only honest unit is "externals actually EXEC'd on the path THIS
# input takes". That is what this harness counts.
#
# ── THE DEFECT THIS HARNESS IS BUILT NOT TO REPEAT ───────────────────────────────────────────
# The first attempt at this measurement used the right idea — a shim directory first on PATH,
# one wrapper per external, each appending a line to a log — and destroyed its own measurement:
# every shim body was
#       exec grep "$@"
# while PATH still had the shim directory FIRST. The bare name re-resolved to the shim, which
# exec'd itself, forever: 772,768 log lines, which is one infinite loop wearing a measurement's
# clothes. A count that large does not read as broken, it reads as a finding — which is what
# makes the failure mode expensive.
#
# THE FIX, and it is the whole design constraint of this file:
#   1. Every shim body execs an ABSOLUTE path (`exec /usr/bin/grep "$@"`), never a bare name.
#   2. Absolute paths are resolved with `command -v` BEFORE the shim directory is built and
#      BEFORE it is ever prepended to PATH, so resolution cannot see the shims.
#   3. build_shims() REFUSES to write a shim whose resolved target is inside the shim directory.
#   4. Every shim carries a depth tripwire (_FC_DEPTH): exec replaces the process, so depth can
#      only grow through NESTING, which is exactly the self-exec signature. Above _FC_MAXDEPTH
#      the shim aborts loudly instead of spinning.
#   5. smoke_test() is a positive control: it proves one exec produces exactly one log line
#      before any real measurement is trusted.
#
# ── TWO INDEPENDENT INSTRUMENTS ──────────────────────────────────────────────────────────────
#   A. THE SHIM LOG   — exact ground truth for "how many external programs were exec'd, and with
#                       what argv". Cannot attribute to a source line.
#   B. THE XTRACE     — `bash -x` with PS4 carrying ${BASH_SOURCE}:${LINENO}, filtered to lines
#                       whose first word is a shimmed tool. Gives file:line attribution, and is
#                       derived from a different mechanism than (A), so agreement between the two
#                       is real corroboration rather than one instrument restating itself.
# They are reported side by side. A disagreement is a finding about the harness, not a rounding
# error — the report prints both counts rather than reconciling them silently.
#
# ── WHAT IS COUNTED, AND WHAT IS NOT ─────────────────────────────────────────────────────────
# COUNTED: external programs EXEC'd (the unit R-3's "12 grep forks" is stated in).
# NOT COUNTED: the subshell fork that a pipeline or a `$( … )` costs even when every stage is a
# shell builtin. `printf '%s' "$CMD" | grep -qE …` is TWO forked processes but ONE exec of an
# external. So the exec count reported here is a LOWER BOUND on processes created. The wall-clock
# numbers do not care — they measure the whole thing — which is why both are reported.
#
# ── WALL-CLOCK IS LOAD-CONDITIONAL ───────────────────────────────────────────────────────────
# Every millisecond in this plan is conditional on machine load (HOOK_CHAIN_COST.md §8), so the
# report stamps the load average and CPU count at the start AND end of the run, and a figure is
# never emitted without them. The shim itself costs a process per exec, so shimmed and UNSHIMMED
# medians are measured and reported SEPARATELY — quoting the shimmed number as the hook's cost
# would inflate it by roughly one extra process per external.
#
# USAGE
#   scripts/hook-fork-census.sh [--runs N] [--corpus FILE] [--hook FILE] [--out DIR] [--quick]
#
#   --runs N     timed repetitions per class (default 40; median reported, first 3 discarded)
#   --corpus F   corpus TSV (default tests/fixtures/hook-fork-census-corpus.tsv)
#   --hook F     hook under test (default hooks/validate-bash.sh, relative to repo root)
#   --out DIR    artifact directory (default a fresh mktemp -d)
#   --quick      runs=8, for a smoke run of the harness itself
#
# Exit 0 on a completed census; 1 on a harness fault (a fault is never reported as a measurement).

set -uo pipefail

# Symlink hops resolved before the root is derived. ~/.claude/scripts/ is per-file symlinks into the
# checkout, so an unresolved `dirname $0/..` yields ~/.claude — which has no tests/fixtures, so the
# census would find no corpus and report nothing rather than fail. Canonical loop: ship-land.sh:199
# (no `readlink -f` — GNU-only, this box is BSD).
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [[ -L "$p" ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF_PATH="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
REPO_ROOT="$(cd "$(dirname "$SELF_PATH")/.." && pwd)"
RUNS=40
CORPUS="$REPO_ROOT/tests/fixtures/hook-fork-census-corpus.tsv"
HOOK="$REPO_ROOT/hooks/validate-bash.sh"
OUTDIR=""
_FC_MAXDEPTH=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)   RUNS="$2"; shift 2 ;;
    --corpus) CORPUS="$2"; shift 2 ;;
    --hook)   HOOK="$2"; shift 2 ;;
    --out)    OUTDIR="$2"; shift 2 ;;
    --quick)  RUNS=8; shift ;;
    -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$CORPUS" ]] || { echo "FAULT: corpus not found: $CORPUS" >&2; exit 1; }
[[ -f "$HOOK"   ]] || { echo "FAULT: hook not found: $HOOK" >&2; exit 1; }
[[ -n "$OUTDIR" ]] || OUTDIR="$(mktemp -d /tmp/hook-fork-census.XXXXXX)"
mkdir -p "$OUTDIR" || exit 1

SHIMDIR="$OUTDIR/shims"
CENSUS_LOG="$OUTDIR/execs.log"
REPORT="$OUTDIR/report.txt"

# ── The externals to shim ────────────────────────────────────────────────────────────────────
# Anything the subject file or its sourced libraries can reach. Over-shimming is free (an
# unexec'd shim costs nothing); under-shimming would silently undercount, which is the direction
# that matters, so this list is deliberately wider than the static grep of the subject.
TOOLS=(grep egrep fgrep sed awk cut tr basename dirname jq python3 python git date wc head tail
       sort uniq cat readlink realpath stat find xargs id env printf ls mkdir touch rm shasum
       md5 perl node comm diff sleep pgrep ps)

# ── 1. Resolve absolute paths BEFORE the shim dir exists or touches PATH ──────────────────────
declare -a RESOLVED_NAMES=()
declare -a RESOLVED_PATHS=()
resolve_tools() {
  local t p
  for t in "${TOOLS[@]}"; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    # `command -v` yields a bare name for shell builtins/functions and an alias body for aliases.
    # Only a real absolute executable can be shimmed; anything else is skipped and reported, so
    # "not shimmed" is never confused with "not called".
    [[ "$p" == /* && -x "$p" ]] || { echo "  skip $t (resolves to: ${p:-<nothing>} — not an absolute executable)"; continue; }
    case "$p" in "$SHIMDIR"/*) echo "FAULT: $t already resolves inside the shim dir ($p)" >&2; exit 1 ;; esac
    RESOLVED_NAMES+=("$t"); RESOLVED_PATHS+=("$p")
  done
}

# ── 2. Build the shims ───────────────────────────────────────────────────────────────────────
build_shims() {
  local i name target
  mkdir -p "$SHIMDIR" || exit 1
  for i in "${!RESOLVED_NAMES[@]}"; do
    name="${RESOLVED_NAMES[$i]}"; target="${RESOLVED_PATHS[$i]}"
    # Constraint 3: never write a shim that points back into the shim directory.
    case "$target" in "$SHIMDIR"/*) echo "FAULT: refusing self-referential shim for $name" >&2; exit 1 ;; esac
    cat > "$SHIMDIR/$name" <<SHIM
#!/bin/bash
# census shim for $name — execs the ABSOLUTE path, never the bare name (see hook-fork-census.sh).
_FC_DEPTH=\$(( \${_FC_DEPTH:-0} + 1 ))
if [ "\$_FC_DEPTH" -gt $_FC_MAXDEPTH ]; then
  printf 'FAULT\tRECURSION\t%s\t%s\n' "$name" "\$*" >> "\${HOOK_FORK_CENSUS_LOG:-/dev/null}"
  exit 97
fi
export _FC_DEPTH
# One log LINE per exec, always. jq programs and deny bodies carry embedded newlines and tabs,
# and an unsanitised "\$*" splits one exec across several lines — which reads downstream as extra
# forks and mints tool names out of jq source fragments. Sanitised with parameter expansion only:
# a \`tr\` here would add a fork per exec and corrupt the very count being taken.
_fc_args="\$*"; _fc_args="\${_fc_args//\$'\n'/ }"; _fc_args="\${_fc_args//\$'\t'/ }"
printf '%s\t%s\n' "$name" "\$_fc_args" >> "\${HOOK_FORK_CENSUS_LOG:-/dev/null}"
exec $target "\$@"
SHIM
    chmod +x "$SHIMDIR/$name"
  done
}

# ── 3. Positive control: one exec ⇒ exactly one log line, and no loop ─────────────────────────
smoke_test() {
  local n
  : > "$CENSUS_LOG"
  HOOK_FORK_CENSUS_LOG="$CENSUS_LOG" PATH="$SHIMDIR:$PATH" "$SHIMDIR/grep" --version >/dev/null 2>&1
  n=$(wc -l < "$CENSUS_LOG" | tr -d ' ')
  if [[ "$n" != "1" ]]; then
    echo "FAULT: smoke test logged $n lines for ONE exec (expected 1)." >&2
    echo "       This is the self-exec failure mode. Not proceeding — a bad harness is worse" >&2
    echo "       than no measurement, because its output looks like data." >&2
    exit 1
  fi
  if grep -q RECURSION "$CENSUS_LOG" 2>/dev/null; then
    echo "FAULT: recursion tripwire fired during smoke test." >&2; exit 1
  fi
  echo "  smoke test OK — 1 exec ⇒ 1 log line, no recursion"
}

# ── 4. Payloads (built with the REAL jq, before any shimmed PATH is in play) ──────────────────
JQ="$(command -v jq)"
[[ -n "$JQ" ]] || { echo "FAULT: jq required to build payloads" >&2; exit 1; }

# ARITY GUARD — see scripts/validate-bash-differential.sh for the full reasoning. Tab is
# IFS-whitespace, so an empty cell shifts every later column LEFT rather than reading back empty.
# The corpus is checked in and hand-edited, so REFUSE a malformed row at the source: exactly 3
# non-empty cells per data row. Without this, an empty `bg` cell would slide the COMMAND into the
# run_in_background slot and the census would report timings for a payload nobody wrote.
#
# 🚨 THIS MUST BE CALLED AT TOP LEVEL, NOT FROM build_payloads. Its one caller is
# `NCASES="$(build_payloads)"` — a command substitution, i.e. a SUBSHELL — so an `exit 2` inside it
# ends the subshell and the parent runs on with NCASES empty. Measured while writing this: the first
# draft lived inside build_payloads, and a deliberately malformed corpus produced a full clean run,
# exit 0. A guard that cannot stop the thing it guards is decoration.
assert_corpus_arity() {
  awk -F'\t' -v f="$CORPUS" '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 3 { printf "%s:%d: has %d cells, expected 3\n", f, NR, NF > "/dev/stderr"; bad++ ; next }
    { for (i = 1; i <= NF; i++) if ($i == "") {
        printf "%s:%d: cell %d is EMPTY — it would shift every later column left\n", f, NR, i > "/dev/stderr"; bad++ } }
    END { exit (bad ? 1 : 0) }
  ' "$CORPUS" || {
    echo "FAULT: corpus fixture is malformed — refusing to measure a payload nobody wrote" >&2
    exit 2
  }
}

build_payloads() {
  local class bg cmd n=0
  : > "$OUTDIR/classes.txt"
  while IFS=$'\t' read -r class bg cmd; do
    [[ -z "${class:-}" || "${class:0:1}" == "#" ]] && continue
    [[ -n "${cmd:-}" ]] || continue
    n=$((n+1))
    # The $c/$bg/$cwd below are jq's own variables, bound by --arg above — single quotes are
    # mandatory here, since letting the shell expand them would substitute empty strings.
    # shellcheck disable=SC2016
    "$JQ" -n --arg c "$cmd" --argjson bg "${bg:-false}" --arg cwd "$REPO_ROOT" \
      '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$bg},cwd:$cwd,session_id:"census-0000"}' \
      > "$OUTDIR/payload.$n.json"
    printf '%s\t%s\n' "$n" "$class" >> "$OUTDIR/classes.txt"
  done < "$CORPUS"
  echo "$n"
}

# Keep the subject's side-effect writes out of the live stores. The hook appends IDL rows on the
# pane-spawn paths; a census must not pollute the fleet's ledgers with synthetic rows. An ARRAY,
# not a command substitution, so each assignment is one properly-quoted word by construction.
CENSUS_ENV=(
  "CC_WCLAIM_IDL=$OUTDIR/idl.jsonl"
  "CC_LINEAGE_IDL=$OUTDIR/idl.jsonl"
  "CC_ADMIT_IDL=$OUTDIR/idl.jsonl"
)

# ── 5. Exec census, per class ────────────────────────────────────────────────────────────────
run_census() {
  local n="$1" i class payload count
  {
    printf '%-14s %6s  %s\n' "CLASS" "EXECS" "BREAKDOWN (tool×count)"
    printf '%s\n' "------------------------------------------------------------------------"
  } >> "$REPORT"

  for i in $(seq 1 "$n"); do
    class="$(awk -F'\t' -v k="$i" '$1==k{print $2}' "$OUTDIR/classes.txt")"
    payload="$OUTDIR/payload.$i.json"
    : > "$CENSUS_LOG"
    env "${CENSUS_ENV[@]}" HOOK_FORK_CENSUS_LOG="$CENSUS_LOG" PATH="$SHIMDIR:$PATH" \
      "$HOOK" < "$payload" > "$OUTDIR/stdout.$i.json" 2>"$OUTDIR/stderr.$i.txt"
    echo "$?" > "$OUTDIR/rc.$i"

    if grep -q '^FAULT' "$CENSUS_LOG" 2>/dev/null; then
      echo "FAULT: recursion tripwire fired on class $class — measurement void." >&2; exit 1
    fi
    count=$(wc -l < "$CENSUS_LOG" | tr -d ' ')
    cp "$CENSUS_LOG" "$OUTDIR/execs.$class.log"
    printf '%-14s %6s  %s\n' "$class" "$count" \
      "$(cut -f1 "$CENSUS_LOG" | sort | uniq -c | sort -rn | awk '{printf "%s×%s ", $2, $1}')" >> "$REPORT"
  done
}

# ── 6. Xtrace attribution (independent instrument) ────────────────────────────────────────────
run_xtrace() {
  local n="$1" i class payload
  {
    echo
    echo "XTRACE ATTRIBUTION — external execs by source line (instrument B, independent of shims)"
    printf '%s\n' "------------------------------------------------------------------------"
  } >> "$REPORT"
  local names; names="$(IFS='|'; echo "${RESOLVED_NAMES[*]}")"
  for i in $(seq 1 "$n"); do
    class="$(awk -F'\t' -v k="$i" '$1==k{print $2}' "$OUTDIR/classes.txt")"
    payload="$OUTDIR/payload.$i.json"
    # PS4 delimiter is '@' — a single, non-regex-special character. bash repeats PS4's FIRST
    # character once per nesting level, hence the `^\+*@` anchor rather than a fixed prefix.
    # PS4 must stay single-quoted: BASH_SOURCE and LINENO have to expand in the TRACED shell, at
    # each traced line, not once here in this one.
    # shellcheck disable=SC2016
    env "${CENSUS_ENV[@]}" PS4='+@${BASH_SOURCE##*/}:${LINENO}@ ' \
      /bin/bash -x "$HOOK" < "$payload" >/dev/null 2>"$OUTDIR/xtrace.$class.txt"
    # A traced line is an external exec iff its FIRST word is one of the resolved tool names.
    awk -v pat="^($names)\$" '
      /^\+*@/ {
        s = $0; sub(/^\+*@/, "", s);
        p = index(s, "@ ");
        if (p == 0) next;
        loc = substr(s, 1, p - 1);
        split(substr(s, p + 2), w, " ");
        if (w[1] ~ pat) print loc "\t" w[1];
      }' "$OUTDIR/xtrace.$class.txt" | sort | uniq -c | sort -rn > "$OUTDIR/attrib.$class.txt"
    {
      printf '%s: %s external-exec trace lines\n' "$class" "$(awk '{s+=$1} END{print s+0}' "$OUTDIR/attrib.$class.txt")"
      sed 's/^/    /' "$OUTDIR/attrib.$class.txt"
    } >> "$REPORT"
  done
}

# ── 7. Timing: shimmed vs UNSHIMMED, median of RUNS, warmup discarded ─────────────────────────
run_timing() {
  local n="$1"
  python3 - "$OUTDIR" "$HOOK" "$SHIMDIR" "$RUNS" "$n" >> "$REPORT" <<'PY'
import json, os, statistics, subprocess, sys, time

outdir, hook, shimdir, runs, ncases = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
WARMUP = 3

classes = {}
for line in open(os.path.join(outdir, "classes.txt")):
    i, c = line.rstrip("\n").split("\t")
    classes[int(i)] = c

base_env = dict(os.environ)
for k in ("CC_WCLAIM_IDL", "CC_LINEAGE_IDL", "CC_ADMIT_IDL"):
    base_env[k] = os.path.join(outdir, "idl.jsonl")
base_env.pop("HOOK_FORK_CENSUS_LOG", None)

shim_env = dict(base_env)
shim_env["PATH"] = shimdir + ":" + base_env.get("PATH", "")
shim_env["HOOK_FORK_CENSUS_LOG"] = "/dev/null"

def timed(payload, env, k):
    xs = []
    for _ in range(k + WARMUP):
        t0 = time.perf_counter()
        subprocess.run([hook], stdin=open(payload, "rb"), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, env=env)
        xs.append((time.perf_counter() - t0) * 1000.0)
    return xs[WARMUP:]

print()
print("WALL CLOCK — median ms per invocation (%d timed runs each, %d warmup discarded)" % (runs, WARMUP))
print("-" * 72)
print("%-14s %10s %10s %10s %10s" % ("CLASS", "UNSHIM_med", "UNSHIM_p90", "SHIM_med", "shim_tax"))
rows = {}
for i in range(1, ncases + 1):
    payload = os.path.join(outdir, "payload.%d.json" % i)
    c = classes[i]
    u = timed(payload, base_env, runs)
    s = timed(payload, shim_env, runs)
    um, sm = statistics.median(u), statistics.median(s)
    up = sorted(u)[int(len(u) * 0.9) - 1]
    rows[c] = {"unshimmed_median_ms": round(um, 2), "unshimmed_p90_ms": round(up, 2),
               "shimmed_median_ms": round(sm, 2), "shim_tax_ms": round(sm - um, 2)}
    print("%-14s %10.2f %10.2f %10.2f %10.2f" % (c, um, up, sm, sm - um))
json.dump(rows, open(os.path.join(outdir, "timing.json"), "w"), indent=2)
PY
}

# ── 8. Controls: what does ONE exec actually cost, at THIS load? ──────────────────────────────
# Without this, a fork count and a millisecond figure sit side by side and nobody can tell whether
# one explains the other. The controls measure the marginal cost of a single exec of each external
# the hook actually reaches, at the same load and in the same minute as the census. The model then
# predicts each class's wall clock from its OWN measured exec counts and reports the RESIDUAL —
# the part of the hook's cost that forks do not explain. A large residual would mean the whole
# "N forks × M ms" frame is the wrong model, which is a finding, not a failure.
run_controls() {
  python3 - "$OUTDIR" "$RUNS" >> "$REPORT" <<'PY'
import json, os, statistics, subprocess, sys, time

outdir, runs = sys.argv[1], int(sys.argv[2])
WARMUP = 3

def timed(argv, k):
    xs = []
    for _ in range(k + WARMUP):
        t0 = time.perf_counter()
        subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        xs.append((time.perf_counter() - t0) * 1000.0)
    return statistics.median(xs[WARMUP:])

BASH = "/bin/bash"
# Each probe is the SAME bash -c startup plus exactly one exec of the tool, so the difference
# against the empty probe is that tool's marginal exec cost and nothing else.
probes = {
    "_empty":  [BASH, "-c", "exit 0"],
    "grep":    [BASH, "-c", "/usr/bin/grep -qE zzzz /dev/null || true"],
    "sed":     [BASH, "-c", "/usr/bin/sed -e s/a/b/ /dev/null"],
    "tr":      [BASH, "-c", "/usr/bin/tr a b < /dev/null"],
    "dirname": [BASH, "-c", "/usr/bin/dirname /a/b >/dev/null"],
    "date":    [BASH, "-c", "/bin/date -u >/dev/null"],
    "mkdir":   [BASH, "-c", "/bin/mkdir -p /tmp/fc-ctl-dir"],
    "cat":     [BASH, "-c", "/bin/cat /dev/null"],
    "readlink":[BASH, "-c", "/usr/bin/readlink -f /tmp >/dev/null"],
    "find":    [BASH, "-c", "/usr/bin/find /dev/null -maxdepth 0 >/dev/null"],
}
# jq and python3 are resolved through PATH by the probe's own shell, exactly as the hook resolves
# them — their location is homebrew/framework rather than /usr/bin, so hardcoding would drift.
probes["jq"] = [BASH, "-c", "jq -n 1 >/dev/null"]
probes["python3"] = [BASH, "-c", "python3 -c pass"]

units = {k: timed(v, max(8, runs // 2)) for k, v in probes.items()}
empty = units.pop("_empty")
marginal = {k: v - empty for k, v in units.items()}

print()
print("CONTROLS — marginal cost of ONE exec, measured at the same load, same minute")
print("-" * 72)
print("  bash -c 'exit 0' floor : %.2f ms   (the cost of starting the interpreter at all)" % empty)
for k in sorted(marginal, key=lambda x: -marginal[x]):
    print("  %-9s %8.2f ms marginal" % (k, marginal[k]))

# ── the model ────────────────────────────────────────────────────────────────────────────────
timing = json.load(open(os.path.join(outdir, "timing.json")))
classes = {}
for line in open(os.path.join(outdir, "classes.txt")):
    i, c = line.rstrip("\n").split("\t")
    classes[int(i)] = c

print()
print("MODEL — do the forks explain the wall clock?")
print("-" * 72)
print("%-14s %8s %10s %10s %10s %8s" % ("CLASS", "EXECS", "PREDICT", "MEASURED", "RESIDUAL", "%expl"))
model = {}
for i in sorted(classes):
    c = classes[i]
    logp = os.path.join(outdir, "execs.%s.log" % c)
    if not os.path.exists(logp) or c not in timing:
        continue
    counts = {}
    n = 0
    for line in open(logp, errors="replace"):
        tool = line.split("\t")[0].strip()
        if not tool:
            continue
        counts[tool] = counts.get(tool, 0) + 1
        n += 1
    predicted = empty + sum(counts.get(k, 0) * marginal.get(k, 0.0) for k in counts)
    measured = timing[c]["unshimmed_median_ms"]
    resid = measured - predicted
    pct = 100.0 * predicted / measured if measured else 0.0
    model[c] = {"execs": n, "predicted_ms": round(predicted, 2), "measured_ms": measured,
                "residual_ms": round(resid, 2), "pct_explained": round(pct, 1)}
    print("%-14s %8d %10.2f %10.2f %10.2f %7.1f%%" % (c, n, predicted, measured, resid, pct))
json.dump({"unit_marginal_ms": {k: round(v, 3) for k, v in marginal.items()},
           "bash_startup_ms": round(empty, 3), "model": model},
          open(os.path.join(outdir, "controls.json"), "w"), indent=2)
PY
}

# ── 9. Load context — a millisecond without its load is not a measurement ─────────────────────
load_stamp() {  # <label>
  printf '%-6s  loadavg=%s  ncpu=%s  utc=%s\n' "$1" \
    "$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1","$2","$3}')" \
    "$(sysctl -n hw.ncpu 2>/dev/null || echo '?')" \
    "$(date -u +%FT%TZ)"
}

# ── main ─────────────────────────────────────────────────────────────────────────────────────
: > "$REPORT"
{
  echo "HOOK FORK CENSUS"
  echo "subject : $HOOK"
  echo "corpus  : $CORPUS"
  echo "artifacts: $OUTDIR"
  echo "harness : ${BASH_SOURCE[0]} (bash $BASH_VERSION)"
  echo
} >> "$REPORT"

echo "resolving externals…"
resolve_tools
echo "building shims for ${#RESOLVED_NAMES[@]} externals…"
build_shims
smoke_test

# Record which binary each name actually resolves to under the SUBJECT's own interpreter. The
# interactive shell here rewrites `grep` to ugrep via a shell function, and a shell function is
# invisible to a `#!/bin/bash` hook — so this table, not the interactive shell, is what governs.
{
  echo "RESOLVED EXTERNALS (as the hook's own interpreter sees them)"
  printf '%s\n' "------------------------------------------------------------------------"
  for i in "${!RESOLVED_NAMES[@]}"; do
    printf '  %-10s %s\n' "${RESOLVED_NAMES[$i]}" "${RESOLVED_PATHS[$i]}"
  done
  echo
  echo "SUBJECT INTERPRETER: $(head -1 "$HOOK")"
  echo
  load_stamp START
  echo
} >> "$REPORT"

echo "building payloads…"
assert_corpus_arity          # top level, so its exit 2 can actually stop the run — see its comment
NCASES="$(build_payloads)"
echo "  $NCASES corpus cases"

echo "running exec census…"
run_census "$NCASES"
echo "running xtrace attribution…"
run_xtrace "$NCASES"
echo "running timing (${RUNS} runs × 2 configurations × ${NCASES} classes)…"
run_timing "$NCASES"
echo "running controls + fork model…"
run_controls

{ echo; load_stamp END; } >> "$REPORT"

cat "$REPORT"
echo
echo "artifacts: $OUTDIR"
