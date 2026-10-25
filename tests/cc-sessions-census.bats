#!/usr/bin/env bats
# bin/cc-sessions — the census is ONE jq and ONE ps for the whole registry (R19, reboot-resume
# 2026-10-21, docs/research/reboot-resume-2026-10-21/REPORT.md item 19). It used to fork 3-4 jq and
# one ps per row; the restore heartbeat bounds the census at 30-75 s, and on 2026-10-18 it took
# 4 min 25 s at load 40/core for 2.6 s of CPU, so the heartbeat carried a stale roster tick after tick.
#
# Hermetic: the registry is a fixture dir, it2 and cc-cloud are absent (no pane list, no off-box
# rows), and jq/ps are PATH shims that count their own calls before running the real binary.
# RED-proof, run against cc1d441f6's bin/cc-sessions: the fork-count case fails (60 rows took 180+
# jq calls; measured 241), and the null-startedAt case fails (the placeholder row is kept for ever).

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$D/reg" IT2_BIN="$D/absent-it2" CC_CLOUD_BIN="$D/absent-cloud"
  mkdir -p "$CC_REGISTRY_DIR" "$D/shim"
  for b in jq ps; do
    printf '#!/bin/sh\necho x >> "%s/%s.calls"\nexec %s "$@"\n' "$D" "$b" "$(command -v "$b")" > "$D/shim/$b"
    chmod +x "$D/shim/$b"
  done
  export PATH="$D/shim:$PATH"
  LIVE=$$
  LIVE_LS="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$LIVE" | tr -s ' ' | sed 's/^ //;s/ $//')"
  sleep 0 & DEAD=$!; wait "$DEAD"
}

reg() { # <uuid> <pid> <lstart> <startedAt-json> — one registry row
  printf '{"paneUUID":"%s","pid":%s,"lstart":"%s","startedAt":%s,"name":"n-%s","account":"next","cwd":"/w/%s","session_id":"s-%s"}\n' \
    "$1" "$2" "$3" "$4" "$1" "$1" "$1" > "$CC_REGISTRY_DIR/$1.json"
}
calls() { cat "$D/$1.calls" 2>/dev/null | wc -l | tr -d ' '; }

# The wall-clock bound here is loose (60 s) on purpose: at load 266 (2026-10-21) one `ps -o lstart=
# -p <pid>` of a bats process measured 0.5-12 s by itself, so a tight bound would grade the box,
# not the code. The FORK COUNT is the deterministic proof (the old census made 3-4 jq and 1 ps per
# row); the report's under-10-s figure is measured on the live registry after the deploy.
@test "R19: 60 rows are read with one jq and one ps (plus the --json render)" {
  now_ms="$(( $(date +%s) * 1000 ))"
  i=0; while [ "$i" -lt 40 ]; do reg "L$i" "$LIVE" "$LIVE_LS" "$now_ms"; i=$((i + 1)); done
  i=0; while [ "$i" -lt 20 ]; do reg "D$i" "$DEAD" "$LIVE_LS" "$now_ms"; i=$((i + 1)); done
  t0="$(date +%s)"
  run "$REPO/bin/cc-sessions" --json
  t1="$(date +%s)"
  nj="$(calls jq)"; np="$(calls ps)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | /usr/bin/env jq length)" = 40 ]
  [ "$nj" -le 2 ] || { echo "jq calls: $nj"; false; }
  [ "$np" -le 1 ] || { echo "ps calls: $np"; false; }
  [ $((t1 - t0)) -lt 60 ] || { echo "census took $((t1 - t0)) s"; false; }
  # dead rows are retained (inside CC_REG_RETAIN_H), so --all still lists them
  run "$REPO/bin/cc-sessions" --json --all
  [ "$(printf '%s' "$output" | /usr/bin/env jq length)" = 60 ]
}

@test "R19: a live pid whose start time differs (pid reused) is stale, read from the one ps; a day-first lstart still matches" {
  now_ms="$(( $(date +%s) * 1000 ))"
  reg reused "$LIVE" "Thu Jan  1 00:00:00 2026" "$now_ms"
  # shellcheck disable=SC2086  # splitting the lstart into its five fields is the point
  set -- $LIVE_LS
  reg dayfirst "$LIVE" "$1 $3 $2 $4 $5" "$now_ms"
  reg same "$LIVE" "$LIVE_LS" "$now_ms"
  run "$REPO/bin/cc-sessions" --names
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "n-dayfirst n-same " ]
}

@test "R19: a dead row with a null startedAt is reaped by its file's age, not kept for ever" {
  reg old-null "$DEAD" "$LIVE_LS" null
  reg new-null "$DEAD" "$LIVE_LS" null
  touch -t 202601010000 "$CC_REGISTRY_DIR/old-null.json"
  run "$REPO/bin/cc-sessions" --json --all
  [ "$status" -eq 0 ]
  [ ! -e "$CC_REGISTRY_DIR/old-null.json" ]
  [ -e "$CC_REGISTRY_DIR/new-null.json" ]
  [ "$(printf '%s' "$output" | /usr/bin/env jq -r '[.[].paneUUID] | join(" ")')" = new-null ]
}

@test "R19: one corrupt row does not cost the census: it is swept and every good row still resolves" {
  now_ms="$(( $(date +%s) * 1000 ))"
  reg a "$LIVE" "$LIVE_LS" "$now_ms"; reg b "$LIVE" "$LIVE_LS" "$now_ms"
  printf '{not json' > "$CC_REGISTRY_DIR/m-corrupt.json"
  printf '{"pid":1}' > "$CC_REGISTRY_DIR/n-nouuid.json"
  run "$REPO/bin/cc-sessions" --names
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "n-a n-b " ]
  [ ! -e "$CC_REGISTRY_DIR/m-corrupt.json" ]
  [ ! -e "$CC_REGISTRY_DIR/n-nouuid.json" ]
}

# 2026-10-25: `ps -o … -p a,b` WITHOUT -x hung indefinitely on Darwin 24.6 (dead pids too; one pid,
# or the same list with -x, was instant) and wedged every handoff-fire census for 50+ min. The stub
# reproduces exactly that: a multi-pid -p list without -x hangs; anything else is the real ps.
# RED-proof, run against ba9e991dc's bin/cc-sessions: the bulk read hangs to CC_SESSIONS_PS_TIMEOUT,
# ps.hung is written, and the census falls back to one ps per row (3 calls, not 1).
@test "multi-pid ps: the one bulk read passes -x, so a ps that hangs without it never wedges the census" {
  cc_stub "$D/shim" ps - <<STUB
#!/bin/sh
echo "\$*" >> "$D/ps.argv"; echo x >> "$D/ps.calls"
x=0; multi=0; prev=
for a in "\$@"; do
  [ "\$a" = -x ] && x=1
  [ "\$prev" = -p ] && case "\$a" in *,*) multi=1 ;; esac
  prev="\$a"
done
if [ "\$multi" = 1 ] && [ "\$x" = 0 ]; then echo hung >> "$D/ps.hung"; exec sleep 300; fi
exec /bin/ps "\$@"
STUB
  PAR=$PPID
  PAR_LS="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$PAR" | tr -s ' ' | sed 's/^ //;s/ $//')"
  now_ms="$(( $(date +%s) * 1000 ))"
  reg self "$LIVE" "$LIVE_LS" "$now_ms"; reg parent "$PAR" "$PAR_LS" "$now_ms"
  reg reused "$PAR" "Thu Jan  1 00:00:00 2026" "$now_ms"
  CC_SESSIONS_PS_TIMEOUT=5 run "$REPO/bin/cc-sessions" --names
  [ "$status" -eq 0 ]
  [ ! -e "$D/ps.hung" ] || { echo "ps hung on: $(cat "$D/ps.argv")"; false; }
  [ "$(calls ps)" = 1 ] || { echo "ps calls: $(calls ps): $(cat "$D/ps.argv")"; false; }
  grep -qx -- "-x -o pid=,lstart= -p [0-9][0-9]*,[0-9][0-9]*" "$D/ps.argv"
  [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "n-parent n-self " ]
}

@test "R19: the table renders every live row with one jq" {
  now_ms="$(( $(date +%s) * 1000 ))"
  reg a "$LIVE" "$LIVE_LS" "$now_ms"; reg b "$LIVE" "$LIVE_LS" "$now_ms"
  run "$REPO/bin/cc-sessions"
  [ "$status" -eq 0 ]
  [ "$(calls jq)" -le 2 ]
  [[ "$output" == *n-a*a*next* ]] || false
  [[ "$output" == *n-b*b*next* ]]
}
