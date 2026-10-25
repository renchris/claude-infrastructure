#!/usr/bin/env bats
# cc-dispatch's surface-unavailable backoff (lockup incident 2026-10-25,
# ~/incident-2026-10-25/solution/DESIGN.md C4 R2). handoff-fire exits 76 when its anchor probe cannot
# see the terminal; the dispatcher used to file that as an item failure and re-fired 69 times into a
# deaf terminal. Now a 76 releases the claim, abstains the whole pass, backs off 5 → 10 → 20 → 40 min,
# writes the brownout latch (V4), and the first successful fire resets all of it. A 75 (brownout or
# the kitty RC breaker) abstains the pass with no backoff.
#
# Full passes against stubs (the harness of tests/cc-dispatch-firegate.bats): a stub backlog, a stub
# wave planner, and a stub spawn whose exit code is the case's input. HOME and every store are fixtured.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home"
  export HOME="$C/home"
  cat > "$C/stubs/backlog" <<EOF
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*) cat "$C/items.json" ;;
      *) cat "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  block)  printf 'block %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
esac
exit 0
EOF
  cat > "$C/stubs/waveplan" <<EOF
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt"),"--cwd",(\$d+"/wt/wt-"+.id)] } ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
printf '%s CALLER=%s\n' "\$*" "\${CC_ADMIT_CALLER:-}" >> "$C/spawn.log"
exit "\$(cat "$C/spawn.rc" 2>/dev/null || echo 0)"
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"
  printf 'proj  repo=%s\n' "$C/repos/proj" > "$C/dispatch-projects.conf"
  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECTS_CONF="$C/dispatch-projects.conf" \
         CC_DISPATCH_PROJECT="proj" \
         CC_DISPATCH_MAX_SPAWN=9 CC_DISPATCH_CEILING=9 \
         CC_DISPATCH_SID="bats"
  mk_repo "$C/repos/proj"
  printf '%s' '[{"id":"i1","project":"proj","status":"open","title":"first piece of work","ts":"2026-07-01T00:00:00Z"},
                {"id":"i2","project":"proj","status":"open","title":"second piece of work","ts":"2026-07-02T00:00:00Z"},
                {"id":"i3","project":"proj","status":"open","title":"third piece of work","ts":"2026-07-03T00:00:00Z"}]' > "$C/items.json"
  T=1792900000
  STATE="$C/cc-dispatch-surface.state"; LATCH="$C/brownout.json"
}

mk_repo() {
  local d="$1" o="$1.origin"
  rm -rf "$d" "$o"; mkdir -p "$d" "$o"
  git -C "$o" init -q --bare -b main
  git -C "$d" init -q -b main
  echo one > "$d/f"; git -C "${d:?}" add f
  git -C "${d:?}" -c user.email=t@t -c user.name=t commit -qm one
  git -C "$d" remote add origin "$o"; git -C "$d" push -q origin main
  git -C "$d" fetch -q origin
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

pass() { # $1=epoch $2=spawn rc → runs one --once pass
  : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; rm -rf "$C/dispatch.lock"
  printf '%s\n' "$2" > "$C/spawn.rc"
  CC_DISPATCH_NOW="$1" perl -e 'alarm 300; exec @ARGV' -- "$DISP" --once > "$C/out.txt" 2>&1 || true
}
spawns() { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }
abstained() { jq -r 'select(.action == "abstained") | .detail' "$C/idl.jsonl"; }

@test "01 a stub fire returning 76: one spawn, the claim is released, the pass abstains, backoff step 1 + latch" {
  pass "$T" 76
  [ "$(spawns)" -eq 1 ] || { echo "spawns=$(spawns)"; cat "$C/out.txt"; false; }
  grep -q 'CALLER=cc-dispatch' "$C/spawn.log" || false                # the fire carries its class
  grep -q '^reopen ' "$C/backlog.log" || false                        # the claim was released
  [[ "$(abstained)" == "surface-unavailable rc=76:"* ]] || { abstained; false; }
  [ "$(cat "$STATE")" = "1 $(( T + 300 ))" ] || { cat "$STATE"; false; }
  [ "$(jq -r '[.surface_unavailable_since, .by] | @tsv' "$LATCH")" = "$(printf '%s\tcc-dispatch' "$T")" ] || false
  ! jq -e 'select(.action == "failed")' "$C/idl.jsonl" >/dev/null || { echo "76 was filed as an item failure"; false; }
}

@test "02 the backoff runs 5 → 10 → 20 → 40 min, holds every pass inside its window, and caps at 40" {
  local t="$T" want
  for want in 300 600 1200 2400 2400; do
    pass "$t" 76
    [ "$(spawns)" -eq 1 ] || { echo "at $t: spawns=$(spawns)"; false; }
    [ "$(cut -d' ' -f2 "$STATE")" = "$(( t + want ))" ] || { echo "at $t want +$want: $(cat "$STATE")"; false; }
    # a pass one second before the window ends: no claim, no spawn
    pass "$(( t + want - 1 ))" 76
    [ "$(spawns)" -eq 0 ] || { echo "a pass inside the hold spawned"; false; }
    [[ "$(abstained)" == "surface-unavailable backoff:"* ]] || false
    [ ! -s "$C/backlog.log" ] || { echo "a held pass claimed: $(cat "$C/backlog.log")"; false; }
    t=$(( t + want ))
  done
  # the latch keeps the FIRST rc 76 of the episode, so V4's 30-min window starts when the terminal went deaf
  [ "$(jq -r '.surface_unavailable_since' "$LATCH")" = "$T" ] || false
}

@test "03 the first successful fire resets the backoff and clears the dispatcher's own latch" {
  pass "$T" 76
  pass "$(( T + 300 ))" 0
  [ "$(spawns)" -eq 3 ] || { echo "spawns=$(spawns)"; false; }
  [ ! -e "$STATE" ] || { echo "backoff survived a success: $(cat "$STATE")"; false; }
  [ ! -e "$LATCH" ] || false
  pass "$(( T + 301 ))" 76
  [ "$(cat "$STATE")" = "1 $(( T + 301 + 300 ))" ] || { echo "did not restart at step 1: $(cat "$STATE")"; false; }
  # a latch another writer set (the operator's hold) is not the dispatcher's to clear
  printf '{"surface_unavailable_since":%s,"by":"operator"}\n' "$T" > "$LATCH"
  pass "$(( T + 3000 ))" 0
  [ "$(jq -r '.by' "$LATCH")" = operator ] || false
}

@test "04 a 75 (brownout or breaker) abstains the pass with no backoff and no latch" {
  pass "$T" 75
  [ "$(spawns)" -eq 1 ] || false
  [[ "$(abstained)" == "surface-unavailable rc=75:"* ]] || false
  [ ! -e "$STATE" ] || false
  [ ! -e "$LATCH" ] || false
  pass "$(( T + 1 ))" 75
  [ "$(spawns)" -eq 1 ] || { echo "a 75 left a hold behind"; false; }
}

@test "05 control: any other non-zero is still an item failure and the pass goes on" {
  pass "$T" 9
  [ "$(spawns)" -eq 3 ] || { echo "spawns=$(spawns)"; false; }
  [ "$(jq -r 'select(.action == "failed") | .detail' "$C/idl.jsonl" | grep -c 'spawn rc=9')" -eq 3 ] || false
  [ -z "$(abstained)" ] || false
  [ ! -e "$STATE" ] || false
}
