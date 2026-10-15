#!/usr/bin/env bats
# completion-assert-durations.bats — a done claim over a large dirty tree, and a close that hands
# work over in prose, are answered as before at a bounded cost (docs/plans/LOAD_AND_PROMPT_HOOK_
# TIMEOUTS.md, Wave 4b).
#
# The defect: replayed on a real cancelled Stop (~/Development/personal, 507 dirty records),
# completion-assert took 24 s against its 5 s timeout and would have answered `decision: block` —
# the live hook was killed instead, so the gate failed OPEN. The time was the attribution terms
# (one stat and one grep per record, four `git status -uall`, sixteen reads of one transcript) and
# D1's uncached `cc-backlog list --blocked` (a 10 MB fold, 2.1 s, once past its 5 s bound).
#
# Parity is against the real pre-change hook rebuilt from git; budgets count external commands via
# PATH stubs and each carries an old-arm CONTROL showing the fixture reaches the per-record regime.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers

# Trunk just before Wave 4b.
SHF_BASE=4b1224be5f1319ae68d0a50e021e0309bd21b34c

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID WRAP_SESSION_ID ITERM_SESSION_ID \
        KITTY_WINDOW_ID CC_PANE_ID WRAP_LEDGER_BIN CLAUDE_CONFIG_DIR AGENT_IDENTITY_LIB CC_BACKLOG_BIN SW_RUN_MEMO
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  shf_old_tree "$OLD" "$REPO" hooks/completion-assert.sh hooks/lib/session-writes.sh hooks/lib/peer-owned.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_IDL="$BATS_TEST_TMPDIR/cc-idl.jsonl"
  export WRAP_TRUNK="origin/main"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-repo"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export PEER_OWNED_HOMES="$BATS_TEST_TMPDIR/acct-none"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-programs.json"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-cache"
  export WRAP_BACKLOG_CACHE=off
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  export CC_PROC_SCOPE_PS="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  : > "$CC_BACKLOG_FILE"
  W="$BATS_TEST_TMPDIR/w"
  shf_mkrepo "$W"
}

blank() {
  local d
  for d in "$HOME" "$COMPLETION_STATE_DIR" "$CC_POSTLAND_DIR" "$CC_DECISIONS_DIR" "$CC_FIRED_DIR" \
           "$CC_CUSTODY_DIR" "$CC_REGISTRY_DIR" "$CC_MAILBOX_DIR" "$BATS_TEST_TMPDIR/tmp"; do
    rm -rf "$d"; mkdir -p "$d"
  done
  rm -f "$COMPLETION_IDL" "$CC_IDL"
}

iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z; }

# transcript <close text> — a write-free session bracketing NOW by an hour each way, so every
# attribution term reaches its per-record walk rather than bailing on an unreadable start.
transcript() {
  local tp="$BATS_TEST_TMPDIR/t.jsonl" now; now="$(date +%s)"
  jq -cn --arg ts "$(iso $((now - 3600)))" '{type:"user",timestamp:$ts,message:{role:"user",content:"make the change"}}' > "$tp"
  jq -cn --arg ts "$(iso $((now + 3600)))" --arg t "$1" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:$t}]}}' >> "$tp"
  printf '%s' "$tp"
}
payload() { jq -cn --arg c "$W" --arg t "${1:-}" '{session_id:"sidA",cwd:$c,transcript_path:$t}'; }

stop() { # <old|new> <label>
  local root="$REPO"
  [ "$1" = old ] && root="$OLD"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" shf_run "$2" "$root/hooks/completion-assert.sh" || true
  shf_keep "$2" "$COMPLETION_IDL" "$COMPLETION_STATE_DIR"
}

big_dirt() { # 300 untracked files in new directories, 5 modified tracked files
  local d i
  for d in 1 2 3 4 5 6; do mkdir -p "$W/assets/d$d"; for i in $(seq 1 50); do echo x > "$W/assets/d$d/f$i.bin"; done; done
  for i in 1 2 3 4 5; do echo "t$i" > "$W/t$i.txt"; done
  git -C "$W" add t1.txt t2.txt t3.txt t4.txt t5.txt
  git -C "$W" -c user.email=t@e.com -c user.name=t commit -qm t
  git -C "$W" push -q origin main 2>/dev/null; git -C "$W" rev-parse HEAD > "$W/.git/gate-green"
  for i in 1 2 3 4 5; do echo mod >> "$W/t$i.txt"; done
}

@test "A1 PARITY: a done claim over 305 dirty records answers exactly as before" {
  big_dirt
  local tp; tp="$(transcript 'All done — everything is complete and landed.')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  cat "$SHF_OUT_DIR/o.idl"
  jq -e -s 'length > 0' "$SHF_OUT_DIR/o.idl" >/dev/null
  shf_same o n
}

@test "A2 BUDGET: the attribution walk forks no stat or grep per record (control: the old hook forks hundreds)" {
  big_dirt
  local tp; tp="$(transcript 'All done — everything is complete and landed.')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  echo "# done claim over 305 records: $(shf_total o) external calls before, $(shf_total n) after" >&3
  echo "# after: $(shf_census n)" >&3
  [ "$(shf_calls o stat)" -ge 290 ]
  [ "$(shf_calls n stat)" -le 20 ]
  [ "$(shf_total n)" -le $(( $(shf_total o) / 2 )) ]
}

@test "A3 the -uall snapshot runs BESIDE the ledger, not after it (dropping the prefetch makes this red)" {
  big_dirt
  local tp real s e o n
  tp="$(transcript 'All done — everything is complete and landed.')"
  # Both reads made slow: the ledger by 2 s, and ONLY the attribution snapshot (`status … -uall`)
  # by 2 s through a git wrapper first on PATH. Serial: >= 4 s. Overlapped: ~2 s.
  real="$(command -v git)"
  mkdir -p "$BATS_TEST_TMPDIR/slowbin"
  printf '#!/bin/bash\ncase " $* " in *" status "*" -uall "*) sleep 2 ;; esac\nexec %q "$@"\n' "$real" > "$BATS_TEST_TMPDIR/slowbin/git"
  printf '#!/bin/bash\nsleep 2\nexec bash %q "$@"\n' "$REPO/scripts/wrap-ledger.sh" > "$BATS_TEST_TMPDIR/slow-ledger.sh"
  chmod +x "$BATS_TEST_TMPDIR/slowbin/git"
  export WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/slow-ledger.sh"
  # The control is the SAME new hook with the prefetch switched off, so only the overlap differs.
  for arm in old serial new; do
    local root="$REPO" sw=on; [ "$arm" = old ] && root="$OLD"; [ "$arm" = serial ] && sw=off
    blank
    s="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    payload "$tp" | PATH="$BATS_TEST_TMPDIR/slowbin:$PATH" TMPDIR="$BATS_TEST_TMPDIR/tmp" CC_CA_PREFETCH="$sw" \
      /bin/bash "$root/hooks/completion-assert.sh" > "$SHF_OUT_DIR/t$arm.out" 2>/dev/null || true
    e="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    echo $(( e - s )) > "$SHF_OUT_DIR/t$arm.ms"
  done
  o="$(cat "$SHF_OUT_DIR/tserial.ms")"; n="$(cat "$SHF_OUT_DIR/tnew.ms")"
  echo "# -uall + ledger both slow: prefetch off $o ms, on $n ms (pre-change hook $(cat "$SHF_OUT_DIR/told.ms") ms)" >&3
  cmp "$SHF_OUT_DIR/told.out" "$SHF_OUT_DIR/tnew.out"
  cmp "$SHF_OUT_DIR/tserial.out" "$SHF_OUT_DIR/tnew.out"
  [ "$o" -ge 4000 ]
  [ $(( n + 1500 )) -le "$o" ]
}

# The D1 arm: a close that hands work over in prose, and a blocked row THIS session filed — the
# disk record that makes the prose legitimate — so D1 must NOT fire.
filed_row() {
  "$REPO/bin/cc-backlog" needs "rotate the key" --class needs-human --session sidA >/dev/null 2>&1
}
# fill the shared cache exactly as operator-readout does — its own function, cut out of the hook.
fill_cache() {
  sed -n '/^blg_list_cached()/,/^}/p' "$REPO/hooks/operator-readout.sh" > "$BATS_TEST_TMPDIR/blc.sh"
  /bin/bash -c 'BLG_FILE="$1"; . "$2"; blg_list_cached "$3" --blocked --json >/dev/null' \
    _ "$CC_BACKLOG_FILE" "$BATS_TEST_TMPDIR/blc.sh" "$REPO/bin/cc-backlog"
}

@test "C1 PARITY: D1 answers the same with the shared cache warm, cold, and against the live fold" {
  filed_row
  "$REPO/bin/cc-backlog" list --blocked --json | jq -e 'any(.[]; .session == "sidA")' >/dev/null
  local tp; tp="$(transcript "Landed. You'll need to rotate the key yourself.")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new cold
  fill_cache
  [ -n "$(find "$CC_ORB_BLG_CACHE_DIR" -type f 2>/dev/null)" ]
  blank; payload "$tp" | stop new warm
  shf_same o cold
  shf_same o warm
}

@test "C2 the warm entry IS what D1 reads (control: a poisoned entry flips D1), keyed as operator-readout keys it" {
  filed_row
  fill_cache
  local f tp; f="$(find "$CC_ORB_BLG_CACHE_DIR" -type f | head -1)"
  [ -n "$f" ]
  tp="$(transcript "Landed. You'll need to rotate the key yourself.")"
  blank; payload "$tp" | stop new real
  printf '[]\n' > "$f"
  blank; payload "$tp" | stop new poisoned
  ! grep -q 'operator-only step is not an escape hatch' "$SHF_OUT_DIR/real.out" || false
  grep -q 'operator-only step is not an escape hatch' "$SHF_OUT_DIR/poisoned.out"
}

@test "C3 a stubbed backlog binary is never served from the shared cache" {
  filed_row
  fill_cache
  local f tp; f="$(find "$CC_ORB_BLG_CACHE_DIR" -type f | head -1)"
  printf '[]\n' > "$f"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  tp="$(transcript "Landed. You'll need to rotate the key yourself.")"
  blank; payload "$tp" | stop new stubbed
  ! grep -q 'operator-only step is not an escape hatch' "$SHF_OUT_DIR/stubbed.out"
}

@test "C4 D1's backlog read runs BESIDE the ledger, not after it (control: CC_CA_D1_PREFETCH=off)" {
  # 2026-10-15: on a replayed cancelled Stop the cold fold was 2.8 s after a 1.3 s ledger. Both made
  # slow here by 2 s; serial >= 4 s, overlapped ~2 s, and every arm answers the same.
  filed_row
  local tp s e o n arm root sw
  tp="$(transcript "Landed. You'll need to rotate the key yourself.")"
  printf '#!/bin/bash\nsleep 2\nexec %q "$@"\n' "$REPO/bin/cc-backlog" > "$BATS_TEST_TMPDIR/slow-backlog"
  printf '#!/bin/bash\nsleep 2\nexec bash %q "$@"\n' "$REPO/scripts/wrap-ledger.sh" > "$BATS_TEST_TMPDIR/slow-ledger.sh"
  chmod +x "$BATS_TEST_TMPDIR/slow-backlog"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/slow-backlog" WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/slow-ledger.sh"
  for arm in old serial new; do
    root="$REPO"; sw=on; [ "$arm" = old ] && root="$OLD"; [ "$arm" = serial ] && sw=off
    blank
    s="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    payload "$tp" | TMPDIR="$BATS_TEST_TMPDIR/tmp" CC_CA_D1_PREFETCH="$sw" \
      /bin/bash "$root/hooks/completion-assert.sh" > "$SHF_OUT_DIR/d$arm.out" 2>/dev/null || true
    e="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    echo $(( e - s )) > "$SHF_OUT_DIR/d$arm.ms"
  done
  o="$(cat "$SHF_OUT_DIR/dserial.ms")"; n="$(cat "$SHF_OUT_DIR/dnew.ms")"
  echo "# backlog + ledger both slow: D1 prefetch off $o ms, on $n ms (pre-change hook $(cat "$SHF_OUT_DIR/dold.ms") ms)" >&3
  cmp "$SHF_OUT_DIR/dold.out" "$SHF_OUT_DIR/dnew.out"
  cmp "$SHF_OUT_DIR/dserial.out" "$SHF_OUT_DIR/dnew.out"
  [ "$o" -ge 4000 ]
  [ $(( n + 1500 )) -le "$o" ]
  # nothing outlives the hook: the run memo (and the prefetch file in it) is gone
  [ -z "$(find "$BATS_TEST_TMPDIR/tmp" -name 'sw-run.*' 2>/dev/null)" ]
}

@test "C5 the ledger is asked on the SHARED key when the environment already names this session" {
  # session-continue and boundary-handoff ask without --session; Claude Code exports
  # CLAUDE_CODE_SESSION_ID, so the flag only put this hook on a memo key of its own.
  big_dirt
  local tp; tp="$(transcript 'All done — everything is complete and landed.')"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\nexec bash %q "$@"\n' "$BATS_TEST_TMPDIR/ledger-args" \
    "$REPO/scripts/wrap-ledger.sh" > "$BATS_TEST_TMPDIR/rec-ledger.sh"
  export CLAUDE_CODE_SESSION_ID=sidA
  blank; payload "$tp" | stop old o
  export WRAP_LEDGER_BIN="$BATS_TEST_TMPDIR/rec-ledger.sh"
  blank; : > "$BATS_TEST_TMPDIR/ledger-args"; payload "$tp" | stop new n
  [ "$(cat "$BATS_TEST_TMPDIR/ledger-args")" = "--machine" ]
  shf_same o n
  # a different session in the environment, or the kill switch, keeps the flag (the old call)
  export CLAUDE_CODE_SESSION_ID=sidB
  blank; : > "$BATS_TEST_TMPDIR/ledger-args"; payload "$tp" | stop new other
  [ "$(cat "$BATS_TEST_TMPDIR/ledger-args")" = "--machine --session sidA" ]
  export CLAUDE_CODE_SESSION_ID=sidA CC_CA_SHARED_LEDGER=off
  blank; : > "$BATS_TEST_TMPDIR/ledger-args"; payload "$tp" | stop new off
  [ "$(cat "$BATS_TEST_TMPDIR/ledger-args")" = "--machine --session sidA" ]
  shf_same o off
}
