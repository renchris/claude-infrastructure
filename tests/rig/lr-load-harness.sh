#!/bin/bash
# lr-load-harness.sh — the live load harness (B1 Tier L, LR_SUSTAINED_LOAD W4): two concurrent rig arms
# under the box's real band mix, every member's death → detect → first attempt → retries → engaged,
# and one honest verdict line with a power control.
#
#   bash tests/rig/lr-load-harness.sh preflight [--matrix F] [--arms cure,red] [--selftest]
#   bash tests/rig/lr-load-harness.sh run --matrix F [--arms cure,red] [--red band|tree:<sha>@31|tree:<sha>@20]
#        [--bg-topup N] [--df-topup N] [--typed-relaunch] [--kitty main] [--out DIR] [--detach]
#   bash tests/rig/lr-load-harness.sh status ID | wait ID [--max 270] | stop [ID] | calibrate | analyze DIR…
#
# Arms. cure: `git archive HEAD` in /tmp/lr-harness/trees/<sha> (C14: never the live worktree a /ship
# may be rebasing), at the caller's band, which must read 31 — anything less is
# `NO-VERDICT band:caller-clamped`, exit 3, before anything is created. red: the same tree under
# `taskpolicy -c utility` (20/20), or `--red tree:<parent sha>@31` for a wave's DoD (same band, the
# parent's code: power then means the item's change, not A1's band fix, F16).
# The long-lived part runs in Python (load_lib.py drive): the reaper TERMs orphaned bash at 10 min.
#
# Two open operator packets bound the defaults; nothing adds load until the operator rules:
#   4eee30ac4de4 — may the harness add top-up load? Default: neither. --bg-topup / --df-topup refuse
#                  unless LR_HARNESS_TOPUP names them (bg | df | bg,df).
#   75bb72581c54 — test windows in the main terminal? Default: the main kitty. --kitty private is not
#                  built and refuses.
# A run below the premise floor (load1/core < 15) is NO-VERDICT, never a wait.
#
# Exit (run, wait): 0 PASS · 1 FAIL · 2 usage · 3 NO-VERDICT (retry later) · 4 SIGNAL-DEAD · 5 PASS with
# pass-length power only · 75 (wait) still running: call wait again.
# Kill switches: `bash tests/rig/lr-load-harness.sh stop`; `touch /tmp/lr-harness/OFF` (blocks new runs,
# stops a running sampler and generator within a sample). Every live file is under /tmp.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
H="${LR_HARNESS_DIR:-/tmp/lr-harness}"
PY=(/usr/bin/python3 -I)

die() { echo "lr-load-harness: $*" >&2; exit 2; }
nv() { echo "NO-VERDICT $*"; exit 3; }
band_self() { "${PY[@]}" "$REPO/scripts/limit-recover/lr_recon/band.py" "$$" 2>/dev/null | head -1; }

b=""
gate_band() { # sets b: the caller's own band, read first (B1 §4); a clamped parent cannot make a 31 child
  b="$(band_self)"
  case "$b" in ''|*[!0-9]*) nv "band:caller-unreadable (band.py read '$b')" ;; esac
  [ "$b" -ge 31 ] || nv "band:caller-clamped (base $b < 31: cc-bats clamps to utility, postland runs at background, a launchd job without ProcessType runs at 20)"
}

load1() { /usr/sbin/sysctl -n vm.loadavg | awk '{print $2}'; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
MATRIX="" ARMS="cure,red" RED="band" BG=0 DF=0 TYPED=0 KITTY=main OUT="" DETACH=0 MAXW=270 SELFTEST=0
parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --matrix) MATRIX="$2"; shift 2 ;;
      --arms) ARMS="$2"; shift 2 ;;
      --red) RED="$2"; shift 2 ;;
      --bg-topup) BG="$2"; shift 2 ;;
      --df-topup) DF="$2"; shift 2 ;;
      --typed-relaunch) TYPED=1; shift ;;
      --kitty) KITTY="$2"; shift 2 ;;
      --out) OUT="$2"; shift 2 ;;
      --detach) DETACH=1; shift ;;
      --max) MAXW="$2"; shift 2 ;;
      --selftest) SELFTEST=1; shift ;;
      --level) [ "$2" = ambient ] || die "--level $2: only ambient (top-up is --bg-topup/--df-topup)"; shift 2 ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done
}
ARGS=()
parse "$@"

run_dir() { # ID or the last run
  local id="${ARGS[0]:-}"
  [ -n "$id" ] || id="$(cat "$H/last" 2>/dev/null)"
  [ -n "$id" ] && [ -d "$H/$id" ] || die "no run ${id:-recorded} under $H"
  printf '%s\n' "$H/$id"
}

case "$cmd" in
  preflight)
    gate_band
    [ -e "$H/OFF" ] && nv "off: $H/OFF exists"
    echo "caller band $b · load1 $(load1)"
    "${PY[@]}" "$HERE/load_lib.py" prod-gate || exit 3
    n=10; [ -n "$MATRIX" ] && n="$("${PY[@]}" -c 'import json,sys;sys.path.insert(0,sys.argv[2]);import rig_lib;f=json.load(open(sys.argv[1]));print(len(rig_lib.expand(f))+int(f.get("busy_extra") or 0))' "$MATRIX" "$HERE")"
    na="$(printf '%s' "$ARMS" | tr ',' '\n' | grep -c .)"
    CC_TERM_KITTY_TO="$("$REPO/bin/cc-kitty-socket" 2>/dev/null | head -1)" \
      "${PY[@]}" "$HERE/load_lib.py" preflight "$(( na * (n + (n + 1) / 2) ))" "$na" || exit 3
    if [ "$SELFTEST" = 1 ]; then
      # the generator's stop path at its cap (S6), from this band-31 context only: never in the gate
      echo "selftest: loadgen --bg 200, gone within 10 s of OFF (load1 $(load1), band $b)"
      "${PY[@]}" "$HERE/loadgen.py" stop-test --bg 200 --hold 15 || exit 1
    fi
    exit 0 ;;

  run)
    [ -n "$MATRIX" ] && [ -f "$MATRIX" ] || die "run: --matrix FILE"
    case "$KITTY" in
      main) ;;
      private) die "--kitty private is not built: packet 75bb72581c54 is undecided and its default is the main kitty" ;;
      *) die "--kitty $KITTY (main)" ;;
    esac
    allow=",${LR_HARNESS_TOPUP:-},"
    [ "$BG" = 0 ] || case "$allow" in *,bg,*) ;; *) die "--bg-topup refused: packet 4eee30ac4de4 (may the harness add load?) is undecided, default neither; set LR_HARNESS_TOPUP=bg once the operator allows it" ;; esac
    [ "$DF" = 0 ] || case "$allow" in *,df,*) ;; *) die "--df-topup refused: packet 4eee30ac4de4 is undecided, default neither; set LR_HARNESS_TOPUP=df once the operator allows it" ;; esac
    case "$BG" in *[!0-9]*) die "--bg-topup N" ;; esac; [ "$BG" -le 200 ] || die "--bg-topup caps at 200"
    case "$DF" in *[!0-9]*) die "--df-topup N" ;; esac; [ "$DF" -le 16 ] || die "--df-topup caps at 16"
    [ -e "$H/OFF" ] && nv "off: $H/OFF exists"
    gate_band   # before anything is created
    SOCK="${CC_TERM_KITTY_TO:-$("$REPO/bin/cc-kitty-socket" 2>/dev/null | head -1)}"
    [ -n "$SOCK" ] || nv "setup: no live kitty socket"
    SHA="$(git -C "$REPO" rev-parse HEAD)" || die "git rev-parse"
    mkdir -p "$H/trees" || die "mkdir $H"
    tree() { # $1 sha → a frozen tree (git archive only reads objects)
      local t="$H/trees/$1"
      if [ ! -d "$t/scripts/limit-recover/lr_recon" ]; then
        mkdir -p "$t.part" && git -C "$REPO" archive "$1" | tar -x -C "$t.part" && mv "$t.part" "$t" \
          || die "git archive $1"
      fi
      printf '%s\n' "$t"
    }
    CURE_TREE="$(tree "$SHA")" || exit 2
    [ -f "$CURE_TREE/tests/rig/load_lib.py" ] || die "HEAD $SHA has no committed tests/rig/load_lib.py (the cure tree is git archive HEAD)"
    RED_TREE="$CURE_TREE" RED_SHA="$SHA" RED_BAND=utility
    case "$RED" in
      band) ;;
      tree:*@31|tree:*@20)
        spec="${RED#tree:}"; RED_SHA="$(git -C "$REPO" rev-parse "${spec%@*}^{commit}")" || die "--red $RED: unknown sha"
        RED_TREE="$(tree "$RED_SHA")" || exit 2
        [ "${spec##*@}" = 31 ] && RED_BAND=inherit ;;
      incident:*) die "--red incident:… is retired (F16: 58885750c is not an incident tree); use --red tree:<sha>@20" ;;
      *) die "--red band | tree:<sha>@31 | tree:<sha>@20" ;;
    esac
    ID="$(date -u +%Y%m%dT%H%M%SZ)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
    RUN="$H/$ID"; mkdir -p "$RUN" || die "mkdir $RUN"
    printf '%s\n' "$ID" > "$H/last"
    AUTOREC=off; [ -e "$HOME/.reso/limit-recover/recon/autorecover.on" ] && AUTOREC=on   # mirror production (§6.3), read-only
    "${PY[@]}" - "$RUN" "$ID" "$MATRIX" "$ARMS" "$SHA" "$CURE_TREE" "$RED_SHA" "$RED_TREE" "$RED_BAND" \
      "$SOCK" "$BG" "$DF" "$TYPED" "$AUTOREC" "$OUT" "$HERE" <<'PY' || die "meta"
import json, math, os, re, sys, time
(run, rid, matrix, arms, sha, ctree, rsha, rtree, rband, sock, bg, df, typed, autorec, out, here) = sys.argv[1:]
sys.path.insert(0, here)
import rig_lib, load_lib
f = json.load(open(matrix))
n = len(rig_lib.expand(f))
boot = min(600, 30 + 10 * n)
t_done = load_lib.max_t_done(f)
hb_red = 600 if rband == "utility" else 60
length = load_lib.run_length(f, hb_red, boot)
ncpu, pc = load_lib.ncpu_topology()
m = re.search(r"kitty-(\d+)", sock)
tag = re.sub(r"[^0-9A-Za-z]", "", rid)
arm = {}
for a in arms.split(","):
    if a == "cure":
        arm["cure"] = {"root": "/tmp/lrh-%s-cure" % tag, "tree": sha, "tree_dir": ctree, "band": "inherit", "hb_wait_s": 60}
    elif a == "red":
        arm["red"] = {"root": "/tmp/lrh-%s-red" % tag, "tree": rsha, "tree_dir": rtree, "band": rband, "hb_wait_s": hb_red}
    else:
        sys.exit("unknown arm %s" % a)
now = time.time()
n_extra = int(f.get("busy_extra") or 0) + sum(b["rows"] for b in rig_lib.batches(f))  # W4b move rows are panes too
meta = {"id": rid, "matrix": os.path.abspath(matrix), "n": n, "n_extra": n_extra, "arms": arm,
        "cure_tree": ctree, "sock": sock, "kitty_pid": int(m.group(1)) if m else 0, "ncpu": ncpu, "pcores": pc,
        "started": now, "deadline": now + length + 900, "max_s": length + 900, "boot_wait_s": boot,
        "arm_timeout_s": int(t_done + 300), "every_s": 5, "census_every_s": 15, "bg_topup": int(bg), "df_topup": int(df),
        "typed_relaunch": typed == "1", "autorecover": autorec, "out": os.path.abspath(out) if out else "",
        "expect_file": os.path.join(ctree, "tests", "rig", "load-expect.json"), "load1_at_start": os.getloadavg()[0]}
json.dump(meta, open(os.path.join(run, "meta.json"), "w"), indent=1)
print("run %s · n %d · arms %s · max T_done go+%.0fs · run length ≤ %ds" % (rid, n, arms, t_done, length))
PY
    echo "caller band $b · load1 $(load1) · cure tree ${SHA:0:9} · red $RED (${RED_SHA:0:9}, band $RED_BAND)"
    DRV=("${PY[@]}" "$CURE_TREE/tests/rig/load_lib.py" drive "$RUN")
    if [ "$DETACH" = 1 ]; then
      # shellcheck source=/dev/null
      . "$REPO/scripts/lib/detach.sh"
      pid="$(detach "$RUN/driver.out" "${DRV[@]}")" || die "detach"
      echo "$ID detached (driver pid $pid) · follow: bash tests/rig/lr-load-harness.sh wait $ID"
      exit 0
    fi
    "${DRV[@]}"; exit $? ;;

  status|wait)
    R="$(run_dir)" || exit 2
    [ "$MAXW" -le 270 ] 2>/dev/null || die "--max ≤ 270 (one Bash call never holds 4.5 min)"
    t0=$(date +%s)
    while :; do
      if [ -s "$R/done.json" ]; then
        cat "$R/verdict.line" 2>/dev/null
        rc="$("${PY[@]}" -c 'import json,sys;print(json.load(open(sys.argv[1]))["rc"])' "$R/done.json")"
        exit "$rc"
      fi
      if [ "$cmd" = status ] || [ $(( $(date +%s) - t0 )) -ge "$MAXW" ]; then
        tail -3 "$R/driver.log" 2>/dev/null
        tail -1 "$R/samples.jsonl" 2>/dev/null | "${PY[@]}" -c 'import json,sys
for ln in sys.stdin:
    s = json.loads(ln); print("last sample: load1 %s · arms %s" % (s["load"][0], {k: v["daemon"] for k, v in s.get("arms", {}).items()}))' 2>/dev/null
        echo "still running: $(basename "$R") (load1 $(load1)); call wait again"
        exit 75
      fi
      sleep 5
    done ;;

  stop)
    # every run still open (or the named one): stop files first, then verified kills, then each arm's
    # own teardown, then the lock if its owner is gone
    runs=()
    if [ -n "${ARGS[0]:-}" ]; then runs=("$H/${ARGS[0]}"); else
      for d in "$H"/*/; do [ -f "$d/meta.json" ] && [ ! -s "$d/done.json" ] && runs+=("${d%/}"); done
    fi
    for R in ${runs[@]+"${runs[@]}"}; do
      : > "$R/sampler.stop"
      "${PY[@]}" - "$R" "$HERE" <<'PY'
import json, os, signal, sys
run, here = sys.argv[1:]
sys.path.insert(0, here)
import load_lib
meta = load_lib.load(os.path.join(run, "meta.json"), {}) or {}
for a in meta.get("arms", {}).values():
    try:
        open(os.path.join(a["root"], "stop"), "a").close()
    except OSError:
        pass
pid, idt = int(meta.get("harness_pid") or 0), meta.get("harness_ident") or ""
if pid and idt and load_lib.ident(pid) == idt:  # S2: only the driver this run recorded
    os.kill(pid, signal.SIGTERM)
    print("stopped driver %d" % pid)
PY
      [ -f "$R/loadgen.ctl.pid" ] && "${PY[@]}" "$HERE/loadgen.py" kill --ctl "$R/loadgen.ctl"
      for root in $("${PY[@]}" -c 'import json,sys;print(" ".join(a["root"] for a in json.load(open(sys.argv[1]))["arms"].values()))' "$R/meta.json"); do
        LR_RIG_ROOT="$root" bash "$HERE/lr-recon-rig.sh" --teardown
      done
      [ -s "$R/done.json" ] || printf '{"rc": 3, "line": "NO-VERDICT stopped (lr-load-harness.sh stop)"}\n' > "$R/done.json"
      [ -s "$R/verdict.line" ] || echo "NO-VERDICT stopped (lr-load-harness.sh stop)" > "$R/verdict.line"
      echo "stopped $(basename "$R")"
    done
    if [ -d "$H/lock" ]; then
      "${PY[@]}" - "$H/lock" "$HERE" <<'PY'
import os, sys
d, here = sys.argv[1:]
sys.path.insert(0, here)
import load_lib
o = load_lib.load(os.path.join(d, "owner.json"), {}) or {}
if not (o.get("pid") and o.get("ident") and load_lib.ident(int(o["pid"])) == o["ident"]):
    load_lib.lock("release", d, o.get("run", ""), int(o.get("pid") or 0))
    print("lock released (owner gone)")
PY
    fi
    exit 0 ;;

  calibrate) "${PY[@]}" "$HERE/load_lib.py" calibrate; exit $? ;;
  analyze) "${PY[@]}" "$HERE/load_lib.py" analyze ${ARGS[@]+"${ARGS[@]}"}; exit $? ;;
  -h|--help|"") sed -n '2,32p' "$0"; exit 0 ;;
  *) die "unknown command $cmd" ;;
esac
