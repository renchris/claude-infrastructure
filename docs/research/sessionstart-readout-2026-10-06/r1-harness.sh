#!/bin/bash
# r1-harness.sh — A/B wall-time harness for SessionStart hooks (SESSIONSTART_READOUT R1).
#
# Usage: bash /tmp/ssr-research/r1-harness.sh <N> <hookA> [hookB]
#
#   Times N runs of "<interp> <hook> < payload > /dev/null" per hook. With two hooks the runs are
#   INTERLEAVED A,B,A,B,... so machine-load drift lands on both arms equally. Timer: python3
#   time.perf_counter_ns around one subprocess.run (fork+exec+wait), from a single long-lived
#   python process, so the per-run harness cost is constant across arms.
#   Prints n / p50 / p90 / p99 / max / mean in ms per arm (nearest-rank percentiles) plus the
#   `uptime` load averages before and after the batch, and writes every raw sample to
#   $R1_OUT_DIR/r1-raw-<label>.csv.
#
# Env knobs (all optional):
#   R1_BASH_A / R1_BASH_B   interpreter per arm (default /bin/bash). Use the SAME hook twice with
#                           R1_BASH_B=/opt/homebrew/bin/bash for an interpreter A/B.
#   R1_LABEL_A / R1_LABEL_B labels for the output rows (default: <basename>@<interp>).
#   R1_PAYLOAD              stdin payload file (default: the R1 startup payload, written below).
#   R1_BOARD_MODE           fresh (default: board copy touched to now) | stale (touched 10 min ago)
#                           | keep (leave the copy's mtime alone).
#   R1_WARMUP               untimed warm-up runs per arm before timing (default 3). The first
#                           warm-up run's stdout is kept in $R1_OUT_DIR/r1-out-<label>.txt as a
#                           receipt of WHICH path (fresh/stale/...) was measured.
#   R1_CWD                  working directory of every run (default: the sessionstart-readout worktree).
#   R1_OUT_DIR              default /tmp/ssr-research.
#
# Sandboxing (always on): DL_DIR=$R1_OUT_DIR/dl-sandbox (a copy of the real deadlines .state/, so
# the operator's once-a-day banner latch is never consumed) and CC_ACCOUNTS_BOARD=$R1_OUT_DIR/r1-board.txt
# (a copy of /tmp/claude-accounts-board.txt). CLAUDE_CODE_ENTRYPOINT=cli is exported, as Claude Code
# does for an interactive session, so dl_banner() walks its real gate instead of exiting at the top.
#
# Safety: refuses to time the SessionStart children that write state outside the sandbox
# (session-start.sh, setup-plan-symlinks.sh, setup-task-symlinks.sh, session-index-start.sh),
# config-mirror-assert.sh while CLAUDE_CONFIG_DIR names an account dir (its _cc_sync_account
# rewrites symlinks there), and session-start-dispatch.sh unless CC_SSD_CHILDREN is set to a list
# free of those children.
set -uo pipefail

N="${1:-}"; A="${2:-}"; B="${3:-}"
case "$N" in ''|*[!0-9]*|0) echo "usage: bash $0 <N> <hookA> [hookB]" >&2; exit 2 ;; esac
[ -n "$A" ] || { echo "usage: bash $0 <N> <hookA> [hookB]" >&2; exit 2; }

OUT="${R1_OUT_DIR:-/tmp/ssr-research}"
WT="/Users/chrisren/Development/.worktrees/sessionstart-readout"
mkdir -p "$OUT"

WRITERS="session-start.sh setup-plan-symlinks.sh setup-task-symlinks.sh session-index-start.sh"
guard() {  # <hook>
  local b; b="$(basename "$1")"
  [ -f "$1" ] || { echo "r1-harness: no such hook: $1" >&2; exit 2; }
  case " $WRITERS " in *" $b "*) echo "r1-harness: REFUSED — $b writes state outside the sandbox" >&2; exit 3 ;; esac
  if [ "$b" = config-mirror-assert.sh ]; then
    case "${CLAUDE_CONFIG_DIR:-}" in ''|"$HOME/.claude") ;;
      *) echo "r1-harness: REFUSED — config-mirror-assert.sh with CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR runs _cc_sync_account (writes); unset it" >&2; exit 3 ;;
    esac
  fi
  if [ "$b" = session-start-dispatch.sh ]; then
    [ -n "${CC_SSD_CHILDREN:-}" ] || { echo "r1-harness: REFUSED — dispatch without CC_SSD_CHILDREN runs every child, including writers" >&2; exit 3; }
    local c; for c in $CC_SSD_CHILDREN; do
      case " $WRITERS " in *" $c "*) echo "r1-harness: REFUSED — CC_SSD_CHILDREN contains writer $c" >&2; exit 3 ;; esac
    done
  fi
}
guard "$A"; [ -n "$B" ] && guard "$B"

# ── payload ────────────────────────────────────────────────────────────────────────────────────
PAYLOAD="${R1_PAYLOAD:-$OUT/r1-payload.json}"
if [ -z "${R1_PAYLOAD:-}" ]; then
  printf '%s\n' '{"source":"startup","cwd":"/Users/chrisren/Development/.worktrees/sessionstart-readout","transcript_path":""}' > "$PAYLOAD"
fi

# ── deadlines sandbox (the real latch is never touched) ───────────────────────────────────────
REAL_STATE="$HOME/Development/personal/deadlines/.state"
SANDBOX="$OUT/dl-sandbox"
mkdir -p "$SANDBOX/.state"
[ -d "$REAL_STATE" ] && cp -Rp "$REAL_STATE/." "$SANDBOX/.state/"
export DL_DIR="$SANDBOX"

# ── board copy, fresh or stale ─────────────────────────────────────────────────────────────────
BOARD="$OUT/r1-board.txt"
[ -f /tmp/claude-accounts-board.txt ] && cp /tmp/claude-accounts-board.txt "$BOARD"
case "${R1_BOARD_MODE:-fresh}" in
  fresh) touch "$BOARD" ;;
  stale) touch -t "$(date -v-10M +%Y%m%d%H%M.%S)" "$BOARD" ;;
  keep)  : ;;
  *) echo "r1-harness: R1_BOARD_MODE must be fresh|stale|keep" >&2; exit 2 ;;
esac
export CC_ACCOUNTS_BOARD="$BOARD"
export CLAUDE_CODE_ENTRYPOINT=cli

export R1_N="$N" R1_A="$A" R1_B="$B" R1_PAYLOAD_F="$PAYLOAD" R1_OUT="$OUT"
export R1_BASH_A="${R1_BASH_A:-/bin/bash}" R1_BASH_B="${R1_BASH_B:-/bin/bash}"
export R1_CWD="${R1_CWD:-$WT}" R1_WARMUP="${R1_WARMUP:-3}"

echo "load_start: $(uptime | sed 's/.*load averages*: //')"
python3 - <<'PY'
import os, subprocess, time, math
N=int(os.environ["R1_N"]); out=os.environ["R1_OUT"]; cwd=os.environ["R1_CWD"]
payload=os.environ["R1_PAYLOAD_F"]; warm=int(os.environ["R1_WARMUP"])
arms=[("A",os.environ["R1_A"],os.environ["R1_BASH_A"])]
if os.environ.get("R1_B"): arms.append(("B",os.environ["R1_B"],os.environ["R1_BASH_B"]))
def ver(interp):
    try: return subprocess.run([interp,"-c","echo $BASH_VERSION"],capture_output=True,text=True).stdout.strip()
    except Exception as e: return "?"
labels={}
for k,h,i in arms:
    labels[k]=os.environ.get("R1_LABEL_"+k) or f"{os.path.basename(h)}@{i}"
    if k=="B" and labels["B"]==labels["A"]: labels["B"]+="-B"
devnull=open(os.devnull,"wb")
def run(h,i,sink):
    with open(payload,"rb") as p:
        t0=time.perf_counter_ns()
        subprocess.run([i,h],stdin=p,stdout=sink,stderr=subprocess.DEVNULL,cwd=cwd)
        return (time.perf_counter_ns()-t0)/1e6
for k,h,i in arms:
    for w in range(warm):
        if w==0:
            with open(f"{out}/r1-out-{labels[k].replace('/','_')}.txt","wb") as f: run(h,i,f)
        else: run(h,i,devnull)
samples={k:[] for k,_,_ in arms}
for n in range(N):
    for k,h,i in arms:
        samples[k].append(run(h,i,devnull))
def pct(s,q):
    s=sorted(s); return s[max(0,math.ceil(q*len(s))-1)]
for k,h,i in arms:
    s=samples[k]
    with open(f"{out}/r1-raw-{labels[k].replace('/','_')}.csv","w") as f:
        f.write("run,ms\n"); f.writelines(f"{j},{v:.3f}\n" for j,v in enumerate(s))
    print(f"{labels[k]}  interp={i} (bash {ver(i)})  n={len(s)}  p50={pct(s,.5):.1f}  p90={pct(s,.9):.1f}  p99={pct(s,.99):.1f}  max={max(s):.1f}  mean={sum(s)/len(s):.1f} ms")
PY
echo "load_end: $(uptime | sed 's/.*load averages*: //')"
