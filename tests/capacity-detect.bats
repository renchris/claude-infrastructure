#!/usr/bin/env bats
# capacity-detect.bats — the record-only detectors D1-D9 (scripts/lib/capacity-detect.py) over synthetic
# series. Design: docs/research/load-root-cause-2026-10-17/DESIGN.md §4.2.
#
# Every series is generated here under $BATS_TEST_TMPDIR, never read from the real logs. Each raise
# assertion is paired with a control that stays just under its line (2000 forks/s raises, 1999 does not;
# 4097 MB raises, 4000 does not), so a detector that raised on everything could not pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  DET="$REPO/scripts/lib/capacity-detect.py"
  D="$BATS_TEST_TMPDIR"
  OUT="$D/out.jsonl"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_CAP_DETECT_OUT="$D/default-out.jsonl" CC_CAP_DETECT_NOMINAL_S=60
  export CC_CAP_DETECT_WTGC_LAST="$D/absent.last" CC_CAP_DETECT_WTGC_WAKE="$D/worktree-gc.wake"
}

# gen <file> <python> — the python calls emit(t, **fields) for a row t seconds after T0. Defaults are a
# quiet tick: el_s 60, forks 500/s. Fields set to None are dropped, so a row can omit an input key.
gen() {
  python3 -c '
import json, sys, time
T0 = 1791900000
fh = open(sys.argv[1], "w")
def emit(t, **kw):
    r = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(T0 + t)), "v": 1, "el_s": 60.0,
         "forks_per_s": 500.0}
    r.update(kw)
    fh.write(json.dumps({k: v for k, v in r.items() if v is not None}) + "\n")
exec(sys.argv[2])
' "$1" "$2"
}

replay() { # <series> [args...] — always exit 0 and always leaves $OUT
  run python3 "$DET" --replay "$1" --out "$OUT" "${@:2}"
  [ "$status" -eq 0 ]
  [ -f "$OUT" ]
}

n() { # <jq select expression> — count of matching records in $OUT
  jq -c "select($1)" "$OUT" > "$D/sel"
  wc -l < "$D/sel" | tr -d ' '
}

GATES2='[{"repo":"/tmp/r","worktree":"/tmp/r/wt-b","kind":"pytest"},{"repo":"/tmp/r","worktree":"/tmp/r/wt-a","kind":"bats"}]'

@test "D1: two full gates in one repo for 3 ticks raise once; 10 min without gates clears the same key" {
  gen "$D/s" "
g = json.loads('$GATES2')
for i in range(3): emit(60 * i, gates=g)
for i in range(3, 15): emit(60 * i, gates=[])"
  replay "$D/s"
  [ "$(n '.det=="D1" and .event=="raise"')" = 1 ]
  [ "$(jq -r 'select(.det=="D1" and .event=="raise") | .key' "$OUT")" = "gates:/tmp/r:/tmp/r/wt-a,/tmp/r/wt-b" ]
  [ "$(jq -r 'select(.det=="D1" and .event=="raise") | .would' "$OUT")" = page ]
  [ "$(n '.det=="D1" and .event=="clear" and .key=="gates:/tmp/r:/tmp/r/wt-a,/tmp/r/wt-b" and .would=="retract"')" = 1 ]
  [ "$(n '.mode!="record-only"')" = 0 ]
  # control: 9 min under the low line is not 10 — no clear yet
  head -n 12 "$D/s" > "$D/s9"; rm -f "$OUT"
  replay "$D/s9"
  [ "$(n '.det=="D1" and .event=="raise"')" = 1 ]
  [ "$(n '.det=="D1" and .event=="clear"')" = 0 ]
  # control: 2 ticks over is not 3
  head -n 2 "$D/s" > "$D/s2"; rm -f "$OUT"
  replay "$D/s2"
  [ "$(n '.event=="raise"')" = 0 ]
}

@test "a gate-free hour of quiet rows raises nothing" {
  gen "$D/s" "
for i in range(60): emit(60 * i, gates=[{'repo': '/tmp/r', 'worktree': '/tmp/r', 'kind': 'bats'}], vnode=None)"
  replay "$D/s"
  [ "$(wc -l < "$D/s" | tr -d ' ')" = 60 ]
  [ "$(n '.event=="raise"')" = 0 ]
}

@test "D2: 2500 forks/s for 60 s raises on a stable key; 1999 does not; 6 h unattributed files one gap" {
  gen "$D/s" "
for i in range(6): emit(20 * (i + 1), el_s=20.0, forks_per_s=2500.0 + 100 * i)
for i in range(400): emit(120 + 60 * (i + 1), forks_per_s=900.0)"
  replay "$D/s"
  [ "$(n '.det=="D2" and .event=="raise"')" = 1 ]
  [ "$(jq -r 'select(.det=="D2" and .event=="raise") | .key' "$OUT")" = "forks:unattributed" ]
  # no named cause ⇒ only records, never would-page
  [ "$(jq -r 'select(.det=="D2" and .event=="raise") | .would' "$OUT")" = null ]
  [ "$(jq -r 'select(.det=="D2" and .event=="raise") | .ts' "$OUT")" = "$(date -u -r 1791900060 +%Y-%m-%dT%H:%M:%SZ)" ]
  [ "$(n '.det=="D2" and .event=="clear"')" = 1 ]
  [ "$(n '.det=="D2" and .event=="instrument-gap"')" = 1 ]

  gen "$D/c" "
for i in range(10): emit(20 * (i + 1), el_s=20.0, forks_per_s=1999.0)"
  rm -f "$OUT"; replay "$D/c"
  [ "$(n '.det=="D2" and .event=="raise"')" = 0 ]

  gen "$D/l" "
for i in range(4): emit(60 * (i + 1), forks_per_s=3000.0 + i, fork_lineage={'comm': 'zsh', 'pid': 41, 'start': 'Sat Oct 17 09:00:00 2026'})"
  rm -f "$OUT"; replay "$D/l"
  [ "$(n '.det=="D2" and .event=="raise" and .key=="forks:zsh:41@Sat Oct 17 09:00:00 2026" and .would=="page"')" = 1 ]
}

@test "D7: a tick over 3x nominal for 3 ticks raises and 10 min of nominal ticks clears; 2 ticks do not" {
  gen "$D/s" "
t = 0
for el in [60, 60, 200, 200, 200] + [60] * 12:
    t += el; emit(t, el_s=float(el))"
  replay "$D/s"
  [ "$(n '.det=="D7" and .event=="raise" and .key=="job:com.claude.capacity-attrib"')" = 1 ]
  [ "$(n '.det=="D7" and .event=="clear" and .key=="job:com.claude.capacity-attrib"')" = 1 ]
  gen "$D/c" "
t = 0
for el in [60, 200, 200, 60, 200, 200, 60]:
    t += el; emit(t, el_s=float(el))"
  rm -f "$OUT"; replay "$D/c"
  [ "$(n '.det=="D7" and .event=="raise"')" = 0 ]
}

BIG='{"pid":4242,"start":"S1","comm":"git","argv2":"git grep","phys_mb":900,"session_pid":100,"session_start":"S0","sid":"abc","cwd":"/tmp/x"}'

@test "D9: one tick at lifetime 4097 MB raises once, not every tick; clears when the pid is gone; 4000 never" {
  gen "$D/s" "
p = json.loads('$BIG'); p['lifetime_max_mb'] = 4097
for i in range(5): emit(60 * i, procs_big=[p])
for i in range(5, 8): emit(60 * i, procs_big=[])"
  replay "$D/s"
  [ "$(n '.det=="D9" and .event=="raise"')" = 1 ]
  [ "$(jq -r 'select(.det=="D9" and .event=="raise") | .ts' "$OUT")" = "$(date -u -r 1791900000 +%Y-%m-%dT%H:%M:%SZ)" ]
  [ "$(jq -r 'select(.det=="D9" and .event=="raise") | .key' "$OUT")" = "mem:git:git grep:100@S0:/tmp/x" ]
  jq -r 'select(.det=="D9" and .event=="raise") | .remedy' "$OUT" | grep -q -- "-P"
  [ "$(n '.det=="D9" and .event=="clear"')" = 1 ]
  [ "$(jq -r 'select(.det=="D9" and .event=="clear") | .ts' "$OUT")" = "$(date -u -r 1791900300 +%Y-%m-%dT%H:%M:%SZ)" ]
  gen "$D/c" "
p = json.loads('$BIG'); p['lifetime_max_mb'] = 4000
for i in range(5): emit(60 * i, procs_big=[p])"
  rm -f "$OUT"; replay "$D/c"
  [ "$(n '.det=="D9" and .event=="raise"')" = 0 ]
}

@test "abstain: rows with no vnode key give one D3 abstain per 6 h and never a raise" {
  gen "$D/s" "
for i in range(780): emit(60 * i, forks_per_s=900.0)"
  replay "$D/s"
  [ "$(n '.det=="D3" and .event=="abstain" and .key=="input:vnode"')" = 3 ]
  [ "$(n '.det=="D3" and .event!="abstain"')" = 0 ]
}

@test "D3: staged vnode churn over 4x the median and 10k/s for 5 min raises; abstains are not raises" {
  gen "$D/s" "
c, t = 0, 0
for i in range(7 * 60): t += 60; c += 1000 * 60; emit(t, vnode={'num_newvnode_calls': c})
for i in range(6): t += 60; c += 50000 * 60; emit(t, vnode={'num_newvnode_calls': c})"
  replay "$D/s"
  [ "$(n '.det=="D3" and .event=="raise" and .key=="vnode-churn:unattributed" and .sink=="backlog-chronic"')" = 1 ]
}

@test "D4, D5, D6, D8: each raises on its staged input" {
  printf '2026-10-17 05:10:26  rc=3  removed=0  worktrees=48\n' > "$D/gc.last"
  export CC_CAP_DETECT_WTGC_LAST="$D/gc.last"
  gen "$D/s" "
for i in range(70):
    emit(60 * i,
         zombies=[{'parent_comm': 'kitty', 'parent_pid': 7, 'parent_start': 'K', 'count': 150 + i}],
         mcp={'servers': [{'name': 'ms365', 'ppid': 1}], 'live_sessions': 3},
         fseventsd={'pid': 90, 'start': 'F', 'cpu_s_per_s': 0.1, 'footprint_mb': 1500})"
  replay "$D/s"
  [ "$(n '.det=="D4" and .event=="raise" and .key=="zombies:kitty:7@K"')" = 1 ]
  [ "$(n '.det=="D5" and .event=="raise" and .key=="mcp:ms365"')" = 1 ]
  [ "$(n '.det=="D6" and .event=="raise" and .key=="worktrees:all:gc-failed" and .would_touch!=null')" = 1 ]
  [ "$(n '.det=="D8" and .event=="raise" and .key=="fseventsd:90@F" and .would=="page"')" = 1 ]
  # record-only: the D6 wake file is named, never touched
  [ ! -e "$CC_CAP_DETECT_WTGC_WAKE" ]
}

@test "flapping: 7 raise/clear cycles in a day give exactly one detector-flapping record" {
  gen "$D/s" "
p = json.loads('$BIG'); p['lifetime_max_mb'] = 5000
for i in range(9): emit(120 * i, procs_big=[p]); emit(120 * i + 60, procs_big=[])"
  replay "$D/s"
  [ "$(n '.det=="D9" and .event=="raise"')" = 9 ]
  [ "$(n '.det=="D9" and .event=="detector-flapping"')" = 1 ]
  [ "$(jq -sr '[.[] | select(.det=="D9" and .event=="raise")] | [.[5].would, .[6].would] | map(tostring) | join(",")' "$OUT")" = "page,null" ]
}

@test "state round-trip: half, persist, the rest == one full replay" {
  gen "$D/s" "
g = json.loads('$GATES2'); p = json.loads('$BIG'); p['lifetime_max_mb'] = 6000
for i in range(40):
    emit(60 * i, gates=g if i < 5 else [], forks_per_s=2600.0 if 10 <= i < 13 else 700.0,
         procs_big=[p] if 20 <= i < 22 else [], el_s=200.0 if 25 <= i < 28 else 60.0,
         vnode={'num_newvnode_calls': 1000 * i})"
  replay "$D/s"
  mv "$OUT" "$D/full.jsonl"
  [ "$(jq -c 'select(.event=="raise")' "$D/full.jsonl" | wc -l | tr -d ' ')" -ge 4 ]
  head -n 20 "$D/s" > "$D/a"; tail -n +21 "$D/s" > "$D/b"
  replay "$D/a" --state "$D/st.json"
  replay "$D/b" --state "$D/st.json"
  cmp "$OUT" "$D/full.jsonl"
  [ "$(wc -c < "$D/st.json")" -lt 65536 ]
}

@test "fail-open: a non-JSON line and a torn last line exit 0 and the other rows still count" {
  gen "$D/s" "
for i in range(3): emit(60 * (i + 1), forks_per_s=2500.0)"
  { head -n 1 "$D/s"; echo 'not json at all'; tail -n +2 "$D/s"; printf '{"ts":"2026-10-17T1'; } > "$D/t"
  replay "$D/t"
  [ "$(n '.det=="D2" and .event=="raise"')" = 1 ]
  run python3 "$DET" --replay "$D/no-such-series" --out "$OUT"
  [ "$status" -eq 0 ]
}

@test "the module never forks" {
  run grep -c 'subprocess\|os.system\|Popen' "$DET"
  [ "$output" = 0 ]
}
