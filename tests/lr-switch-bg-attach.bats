#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# cc-lr switch of a Claude Code BACKGROUND session that has NO spawner pane (2026-10-04).
# Subject: scripts/limit-recover/lr-upgrade.sh — the switch census's bg rows, lru_switch_bg_drive,
#          lru_live_store, lru_relaunch_why, lru_mint_launcher's switch roles; bin/cc-lr switch --sid.
#
# THE PRIME EXAMPLE (live, read-only measurements): bg session d425afab, job 032aa97f on next4. Its
# daemon's spawner (wt-pool-7, pid 7524) was dead, so the census said bg-no-pane while kitty window
# 191 showed the session through `claude attach 032aa97f` — a window whose ROOT process is the attach
# (ppid = kitty itself), so quitting the viewer closes the window. Its transcript was half-moved:
# next4 held only `.jsonl.handed-off` plus a tombstone naming next2, where the live copy sat, never
# relaunched, ending on a five_hour limit with 5 workflow agents dead on the same limit.
# Three amendments, one section each:
#   A. the attach viewer is the host (census row, split beside a root viewer, quit it first);
#   L. the transplant reads the LIVE copy (lock / tombstone chain), proven before anything is touched;
#   P. a session that died on a limit relaunches with `/limit-recover recover …`, others prompt-free.
# [RED] cases fail on the pre-change tree (bg-no-pane; --from the husk; the upgrade prompt).
# Review amendments (2026-10-04): a detach re-execs the viewer as `claude agents` on the SAME pid
# (A4/A5/A7b), a viewer under a claude or behind a foreground claude is bg-attach-occupied (A7c/A7d),
# every it2 call opens the wrapper's kitty gate under launchd (A8b), the split-brain guard (L6).
#
# Hermetic: every store is a fixture under $HOME, `ps` is a snapshot FILE, kitty's window list is a
# FILE (LRU_KITTY_LS), cc-tui.sh is a stub library, it2 / claude / lr-transplant are recorders that
# log to ONE file so the ORDER is observable. Fixture pids and windows are NOT the live ones.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_KITTY_LS="$BATS_TEST_TMPDIR/kitty-ls.json"; echo '[]' > "$LRU_KITTY_LS"
  export LRU_COMPOSER=off LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s\n' "$BATS_TEST_TMPDIR/notify.log" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_SWITCH_POLL_S=0 LRU_SWITCH_VERIFY_S=3 LRU_GAP_S=0
  printf 'versions:\n  opus_latest: claude-opus-5-5\n' > "$BATS_TEST_TMPDIR/model-config.yaml"
  export LRU_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"   # an attach argv carries no --model
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID CLAUDE_CONFIG_DIR LR_CONFIG_DIRS LR_STATE_DIR
  unset CC_TERM CC_TERM_KITTY_TO LRU_IT2_KITTY_PIN LRU_BG_ATTACH_STRICT LRU_BG_ATTACH_QUIT_KEY
  A="$BATS_TEST_TMPDIR/actions.log"; : > "$A"
}

LST="Tue Sep 22 06:47:13 2026"
LATER="Tue Sep 22 07:47:13 2026"
BIN="/opt/cc/.claude-280/node_modules/.bin/claude"
ASID=d425afab-0000-4000-8000-000000000001
AJOB=032aa97f
AWIN=391
Q() { printf '%s' "$HOME/.claude-quaternary/projects/-x"; }
S() { printf '%s' "$HOME/.claude-secondary/projects/-x"; }
T() { printf '%s' "$HOME/.claude-tertiary/projects/-x"; }
LIM='{"type":"assistant","timestamp":"2026-10-04T07:59:47.602Z","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"quotaLimits":{"rateLimitType":"five_hour"},"message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You have hit your session limit"}]}}'
OKT='{"type":"assistant","timestamp":"2026-10-04T07:55:04.997Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}'

# attachfix <status> [viewer: root|shell|none|other|twice] — the d425afab process shape, fixture pids:
# daemon 71093 (spawned by DEAD pid 7524) → bg-pty-host 71222 → bg-spare 71268; kitty 68854; the
# attach viewer 72282 is window 391's own process (root) or runs under its shell 68900 (shell).
attachfix() {
  local st="$1" view="${2:-root}" av="/opt/cc/.claude-284/node_modules/.bin/claude attach" vpar=68854 wpid=72282
  {
    printf '%d 1 %s %s\n' 71093 "$LST" '/x/claude.exe daemon run --origin transient --spawned-by {"label":"claude","cwd":"/w","pid":7524}'
    printf '%d 71093 %s %s\n' 71222 "$LST" 'claude bg-pty-host --bg-pty-host /tmp/a.pty.sock 200 50 -- claude.exe --bg-spare /tmp/a.claim.sock'
    printf '%d 71222 %s %s\n' 71268 "$LST" 'claude bg-spare --bg-spare /tmp/a.claim.sock'
    printf '%d 1 %s %s\n' 68854 "$LST" '/Applications/kitty.app/Contents/MacOS/kitty'
    if [ "$view" = shell ]; then
      printf '%d 68854 %s %s\n' 68900 "$LST" '-zsh'; vpar=68900; wpid=68900
    fi
    case "$view" in
      root|shell|twice) printf '%d %d %s %s\n' 72282 "$vpar" "$LST" "$av $AJOB" ;;
      other) printf '%d %d %s %s\n' 72282 "$vpar" "$LST" "$av ffffffff" ;;
    esac
    [ "$view" = twice ] && printf '%d 68854 %s %s\n' 72283 "$LST" "$av $AJOB"
  } >> "$LRU_PS_SNAPSHOT"
  mkdir -p "$HOME/.claude-quaternary/sessions"
  printf '{"pid":71268,"sessionId":"%s","cwd":"%s","kind":"bg","jobId":"%s","status":"%s","procStart":"%s"}\n' \
    "$ASID" "$BATS_TEST_TMPDIR" "$AJOB" "$st" "$LST" > "$HOME/.claude-quaternary/sessions/71268.json"
  printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":%d,"pid":%d,"cmdline":["claude","attach","%s"],"foreground_processes":[{"pid":72282}]},{"id":7,"pid":60001,"cmdline":["-zsh"],"foreground_processes":[{"pid":60001}]}]}]}]\n' \
    "$AWIN" "$wpid" "$AJOB" > "$LRU_KITTY_LS"
}
# nestfix <nested|stopped> [reg] — window 200's shell (68950) is NOT the viewer's to own:
#   nested  — 68950 → an interactive claude X (68960) → its `!` shell (68970) → `claude attach`; the
#             attach is even in the foreground (the worst case), so only the claude between refuses it;
#   stopped — 68950 runs claude Y (68960) in the foreground beside a SUSPENDED `claude attach` job;
#   sibling — the attach IS 68950's foreground child and claude Y (68960) is a background sibling:
#             ancestry and foreground both pass, so only Y's registry row (pass `reg`) can refuse it.
# reg: a LIVE registry row names window 200 (X's or Y's own pane).
nestfix() {
  local XS=e55c0000-0000-4000-8000-000000000009 av="/opt/cc/.claude-284/node_modules/.bin/claude attach"
  attachfix idle none
  {
    printf '%d 68854 %s %s\n' 68950 "$LST" '-zsh'
    printf '%d 68950 %s %s\n' 68960 "$LST" "$BIN --model claude-opus-5-5"
    if [ "$1" = nested ]; then
      printf '%d 68960 %s %s\n' 68970 "$LST" '/bin/zsh'
      printf '%d 68970 %s %s\n' 72282 "$LST" "$av $AJOB"
    else
      printf '%d 68950 %s %s\n' 72282 "$LST" "$av $AJOB"
    fi
  } >> "$LRU_PS_SNAPSHOT"
  local fg=72282; [ "$1" != stopped ] || fg=68960
  printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":200,"pid":68950,"foreground_processes":[{"pid":%d}]}]}]}]\n' "$fg" > "$LRU_KITTY_LS"
  if [ "${2:-}" = reg ]; then
    printf '{"paneUUID":"200","pid":68960,"session_id":"%s","account":"claude-tertiary","cwd":"/w","lstart":"%s"}\n' "$XS" "$LST" > "$LRU_REG_DIR/200.json"
  fi
}
# transcript shapes: halfmoved <limit|healthy> (quaternary retired + tombstone → secondary live, the
# prime example) · home <limit|healthy> (live in the job's own store, never moved)
tx_body() { if [ "$1" = limit ]; then printf '%s\n%s\n' "$OKT" "$LIM"; else printf '%s\n' "$OKT"; fi; }
halfmoved() {
  mkdir -p "$(Q)" "$(S)" "$HOME/.claude-tertiary/projects"
  { printf '{"type":"agent-name","agentName":"bg job","sessionId":"%s"}\n' "$ASID"; tx_body "${1:-limit}"; } > "$(S)/$ASID.jsonl"
  cp -p "$(S)/$ASID.jsonl" "$(Q)/$ASID.jsonl.handed-off"
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"2026-10-04T08:56:18Z","lock":"%s","cause":"limit","confirm_len":%s}\n' \
    "$HOME/.claude-secondary" "$(S)/$ASID.jsonl" "$LRU_STATE/locks/$ASID.lock" "$(wc -c < "$(S)/$ASID.jsonl" | tr -d ' ')" \
    > "$(Q)/$ASID.HANDOFF.json"
}
home() { mkdir -p "$(Q)"; tx_body "${1:-healthy}" > "$(Q)/$ASID.jsonl"; }

# The drive's world, modelled on the 2.1.284 attach client (review 2026-10-04): a DETACH does not end
# the viewer's pid. Each completed ^C^C round (every 2nd ^C) acts on pid 72282:
#   attach → detach: execve in place to `claude agents` (same pid, new argv); viewer-spawns models
#            the spawnSync fallback instead (the attach parent waits on a `claude agents` child 72300);
#            viewer-slow ignores the first round; viewer-holds ignores every key;
#   agents → exits (the pid leaves ps), unless agents-holds; claude-takes-window then puts a live
#            interactive claude's registry row on window 391 the moment the shell is back.
# Ctrl+Z (only when LRU_BG_ATTACH_QUIT_KEY=ctrl-z) detaches too, unless viewer-needs-ctrlc.
# it2 split answers pane 300 unless split-fails; it2 run plays the relaunch and writes the registry row
# of the pane it ran in; every it2 call records its terminal env in it2-env.log.
attach_actors() {
  export LRU_CLAUDE_BIN_CMD="$STUBS/cc-claude-bin" LRU_TRANSPLANT="$STUBS/lr-transplant" LRU_IT2_BIN="$STUBS/it2"
  export LRU_TUI_LIB="$BATS_TEST_TMPDIR/tui.sh" LRU_BG_POLL_S=0 LRU_BG_STOP_S=2 LRU_BG_QUIT_S=1 LRU_BG_CTRLC_GAP_S=0
  export LRU_RETYPE_MAX=1 LRU_BG_PROMPT_WAIT_S=0 LRU_BG_PROMPT_POLL_S=0
  export LRU_BG_ATTACH_QUIT=keys   # the key path these cases model; A11 owns the SIGTERM lead
  export LRU_CA_LIB="$BATS_TEST_TMPDIR/ca.sh"   # admission is stubbed: admit + mint, unless ca-refuse exists
  cat > "$LRU_CA_LIB" <<'STUB'
cc_capacity_probe() { echo "probe $*" >> "$(dirname "$A")/probe.log"; [ ! -e "$(dirname "$A")/ca-refuse" ]; }
cc_capacity_admit_reason() { echo "segments 95% > 90%"; }
cc_capacity_token_mint() { echo "tok-$1"; }
STUB
  export A ASID AJOB LST BIN AWIN
  printf '#!/bin/bash\necho %s\n' "$STUBS/claude" > "$STUBS/cc-claude-bin"
  cat > "$STUBS/claude" <<'STUB'
#!/bin/bash
echo "stop $2 cfg=$CLAUDE_CONFIG_DIR" >> "$A"
[ -e "$(dirname "$A")/stop-fails" ] && exit 0
grep -v '^71268 ' "$LRU_PS_SNAPSHOT" > "$LRU_PS_SNAPSHOT.t"; mv "$LRU_PS_SNAPSHOT.t" "$LRU_PS_SNAPSHOT"
STUB
  cat > "$STUBS/lr-transplant" <<'STUB'
#!/bin/bash
echo "transplant $*" >> "$A"
from=""; to=""; phase=""
while [ $# -gt 0 ]; do case "$1" in --from) from="$2"; shift 2 ;; --to) to="$2"; shift 2 ;; --phase) phase="$2"; shift 2 ;; *) shift ;; esac; done
[ -f "$from/projects/-x/$ASID.jsonl" ] || exit 2          # the real script's "no transcript" refusal
if [ "$phase" = confirm ]; then
  mkdir -p "$to/projects/-x"; cp -p "$from/projects/-x/$ASID.jsonl" "$to/projects/-x/"
  mv "$from/projects/-x/$ASID.jsonl" "$from/projects/-x/$ASID.jsonl.handed-off"
fi
exit 0
STUB
  cat > "$LRU_TUI_LIB" <<'STUB'
cc_tui_rpc() {
  local d k n line; d="$(dirname "$A")"; k="${*: -1}"
  case "$k" in $'\x1a') echo "ctrl-z $3" >> "$A" ;; $'\x03') echo "ctrl-c $3" >> "$A" ;; *) return 0 ;; esac
  [ -e "$d/viewer-holds" ] && return 0
  if [ "$k" = $'\x1a' ]; then [ -e "$d/viewer-needs-ctrlc" ] && return 0
  else
    n=$(( $(cat "$d/cc-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/cc-n"
    [ $((n % 2)) -eq 0 ] || return 0                                  # half a round
    if [ -e "$d/viewer-slow" ] && [ "$n" -eq 2 ]; then return 0; fi
  fi
  line="$(grep '^72282 ' "$LRU_PS_SNAPSHOT")"
  case "$line" in
    *" attach $AJOB")
      if [ -e "$d/viewer-spawns" ]; then printf '%d 72282 %s %s\n' 72300 "$LST" "${line##* $LST }" | sed 's/ attach .*/ agents/' >> "$LRU_PS_SNAPSHOT"
      else sed "s| attach $AJOB\$| agents|" "$LRU_PS_SNAPSHOT" > "$LRU_PS_SNAPSHOT.t"; mv "$LRU_PS_SNAPSHOT.t" "$LRU_PS_SNAPSHOT"; fi ;;
    *" agents")
      [ -e "$d/agents-holds" ] && return 0
      grep -v '^72282 ' "$LRU_PS_SNAPSHOT" > "$LRU_PS_SNAPSHOT.t"; mv "$LRU_PS_SNAPSHOT.t" "$LRU_PS_SNAPSHOT"
      if [ -e "$d/claude-takes-window" ]; then
        printf '%d 68900 %s %s\n' 68999 "$LST" "$BIN --model claude-opus-5-5" >> "$LRU_PS_SNAPSHOT"
        printf '{"paneUUID":"%s","pid":68999,"session_id":"e66c0000-0000-4000-8000-000000000001","account":"claude-tertiary","cwd":"/w","lstart":"%s"}\n' "$AWIN" "$LST" > "$LRU_REG_DIR/$AWIN.json"
      fi ;;
  esac
  return 0
}
STUB
  cat > "$STUBS/it2" <<'STUB'
#!/bin/bash
d="$(dirname "$A")"
echo "$2 CC_TERM=${CC_TERM:-} TO=${CC_TERM_KITTY_TO:-} KWID=${KITTY_WINDOW_ID:-}" >> "$d/it2-env.log"
case "$2" in
  split) echo "it2-split $3 $4 $5" >> "$A"; [ -e "$d/split-fails" ] && exit 1; echo "Created new pane: 300" ;;
  close) echo "it2-close $3 $4 $5" >> "$A" ;;
  run)   echo "it2-run $3 $4 | $5" >> "$A"
         printf '{"paneUUID":"%s","pid":88001,"session_id":"%s","account":"claude-tertiary","cwd":"/w","lstart":"%s"}\n' "$4" "$ASID" "$LST" > "$LRU_REG_DIR/$4.json"
         printf '%d 1 %s %s\n' 88001 "$LST" "$BIN --resume $ASID" >> "$LRU_PS_SNAPSHOT"
         run="$(printf '%s' "$5" | sed 's/.*&& nocorrect bash //; s|/launch.sh$||')"
         [ -e "$d/submit-ok" ] && echo '{"state":"submitted","stage":"submit"}' >> "$run/events.jsonl" ;;
esac
exit 0
STUB
  chmod +x "$STUBS/cc-claude-bin" "$STUBS/claude" "$STUBS/lr-transplant" "$STUBS/it2"
}
# fresh <n> — a second, untouched fixture root for a control half (new HOME, registry, ps, kitty, log)
# (the real lr-transplant reads LR_STATE_DIR / LR_CONFIG_DIRS: re-pointed too, or a control half
# would read the FIRST half's custody lock and refuse for the wrong reason)
fresh() {
  export HOME="$BATS_TEST_TMPDIR/home$1"; mkdir -p "$HOME"
  export LRU_CFG_ROOT="$HOME" LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LR_STATE_DIR="$LRU_STATE" LR_CONFIG_DIRS="$HOME/.claude-quaternary:$HOME/.claude-secondary:$HOME/.claude-tertiary"
  rm -f "$BATS_TEST_TMPDIR/cc-n" "$BATS_TEST_TMPDIR/it2-env.log"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg$1"; mkdir -p "$LRU_REG_DIR"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps$1.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_KITTY_LS="$BATS_TEST_TMPDIR/kitty-ls$1.json"; echo '[]' > "$LRU_KITTY_LS"
  A="$BATS_TEST_TMPDIR/actions$1.log"; : > "$A"; export A
}
res() { jq -r ".$1" "$LRU_STATE/results/switch-$ASID.json"; }
order() { cut -d' ' -f1 "$A" | tr '\n' ' '; }
launcher() { grep '^it2-run ' "$A" | head -1 | sed 's/.*&& nocorrect bash //'; }
row_of() { printf '%s\n' "$output" | awk -F'\t' -v s="$1" '$2 == s'; }
drive() { run bash "$LRU" --switch-drive "$ASID" "${1:-$AWIN}" next3 --requested-by 999 --req-id "${2:-t}"; }

# ── A. THE ATTACH VIEWER IS THE HOST ──────────────────────────────────────────────────────────────

@test "A1 [RED] census: a dead spawner + ONE live attach viewer reads as the viewer's window, bg-session; lookalike argvs never count" {
  attachfix idle root
  printf '%d 68854 %s %s\n' 72290 "$LST" "/opt/cc/.claude-284/node_modules/.bin/claude attach ${AJOB}X" >> "$LRU_PS_SNAPSHOT"
  printf '%d 1 %s %s\n' 72291 "$LST" "grep attach $AJOB" >> "$LRU_PS_SNAPSHOT"
  run bash "$LRU" --switch-census --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(row_of "$ASID" | cut -f1,3,6,7)" = "$AWIN"$'\t'"next4"$'\t'"71268"$'\t'"bg-session" ] || { echo "$output"; false; }
  # CONTROL: the kill switch gives the pre-change answer, proving the fixture reaches the new arm
  LRU_BG_ATTACH=off run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "-"$'\t'"bg-no-pane" ] || { echo "$output"; false; }
}

@test "A2 census: a viewer of ANOTHER job is not this session's; no owning window or an unreadable kitty is bg-attach-nowin; two viewers are bg-attach-ambiguous; none is waitable" {
  attachfix idle other
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "-"$'\t'"bg-no-pane" ] || { echo "$output"; false; }
  : > "$LRU_PS_SNAPSHOT"; attachfix idle root
  echo '[{"id":1,"tabs":[{"id":1,"windows":[{"id":7,"pid":60001}]}]}]' > "$LRU_KITTY_LS"
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "-"$'\t'"bg-attach-nowin" ] || { echo "$output"; false; }
  LRU_KITTY_LS="$BATS_TEST_TMPDIR/absent.json" run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f7)" = bg-attach-nowin ] || { echo "$output"; false; }
  : > "$LRU_PS_SNAPSHOT"; attachfix idle twice
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "-"$'\t'"bg-attach-ambiguous" ] || { echo "$output"; false; }
  run bash "$LRU" --switch-waitable bg-attach-ambiguous; [ "$status" -eq 1 ]
  run bash "$LRU" --switch-waitable bg-attach-nowin; [ "$status" -eq 1 ]
}

@test "A3 [RED] spawner pin: a spawner pid recycled into a live registry claude (started AFTER the daemon) binds nothing; LRU_BG_SPAWNER_PIN=off restores the old binding; a genuine spawner still wins over a viewer" {
  attachfix idle root
  # the daemon names pid 76287 as its spawner; 76287 is now a LATER-started claude in pane 405
  sed -i.bak 's/"pid":7524/"pid":76287/' "$LRU_PS_SNAPSHOT"
  printf '{"paneUUID":"405","pid":76287,"session_id":"e44c8e8c-0000-4000-8000-000000000001","account":"claude-tertiary","cwd":"/w","lstart":"%s"}\n' "$LATER" > "$LRU_REG_DIR/405.json"
  printf '%d 1 %s %s\n' 76287 "$LATER" "$BIN --model claude-opus-5-5" >> "$LRU_PS_SNAPSHOT"
  mkdir -p "$HOME/.claude-tertiary/projects/-x"
  printf '%s\n' '{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}' > "$HOME/.claude-tertiary/projects/-x/e44c8e8c-0000-4000-8000-000000000001.jsonl"
  run bash "$LRU" --switch-census --target next2
  [ "$(row_of "$ASID" | cut -f1,7)" = "$AWIN"$'\t'"bg-session" ] || { echo "$output"; false; }
  [ "$(row_of e44c8e8c-0000-4000-8000-000000000001 | cut -f7)" = mid-turn ] || { echo "the recycled pid's pane was called bg-host: $output"; false; }
  LRU_BG_SPAWNER_PIN=off run bash "$LRU" --switch-census --target next2
  [ "$(row_of "$ASID" | cut -f1)" = 405 ] || { echo "$output"; false; }
  [ "$(row_of e44c8e8c-0000-4000-8000-000000000001 | cut -f7)" = bg-host ] || { echo "$output"; false; }
  # EQUIVALENCE: a spawner that started before its daemon is the host, viewer or not
  sed -i.bak "s/$LATER/$LST/" "$LRU_REG_DIR/405.json" "$LRU_PS_SNAPSHOT"
  run bash "$LRU" --switch-census --target next2
  [ "$(row_of "$ASID" | cut -f1)" = 405 ] || { echo "$output"; false; }
}

@test "A4 [RED] drive, viewer is the window's ROOT process: a pane is split beside it, the viewer quits first, then stop + transplant, the launcher runs in the NEW pane — SWITCHED on ITS registry flip" {
  attachfix idle root; halfmoved healthy; attach_actors
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  [ "$(order)" = "it2-split ctrl-c ctrl-c stop transplant transplant it2-run " ] || { cat "$A"; false; }
  grep -qx "it2-split -v -s $AWIN" "$A" || { cat "$A"; false; }
  [ "$(grep -c '^ctrl-c id:391$' "$A")" -eq 2 ] || { cat "$A"; false; }
  grep -q '^it2-run -s 300 ' "$A" || { cat "$A"; false; }
  # the viewer DETACHED and did not exit: the same pid is the agents view now (the pre-fix wait for
  # the pid to leave ps timed out on exactly this, and reported NOTMOVED)
  grep -q '^72282 68854 .*claude agents$' "$LRU_PS_SNAPSHOT" || { cat "$LRU_PS_SNAPSHOT"; false; }
  [ "$(jq -r '.session_id + " " + .account' "$LRU_REG_DIR/300.json")" = "$ASID claude-tertiary" ] || false
  [ "$(res pane)" = "$AWIN" ] || { echo "the result must stay keyed on the requested pane"; false; }
  [[ "$(res reason)" == *"viewer window 391 (claude attach $AJOB) quit on ctrl-c"*"pane 300 relaunched it on next3"* ]] || { res reason; false; }
  L="$(launcher)"
  grep -q "$HOME/.claude-tertiary" "$L" || { cat "$L"; false; }
  grep -q "$ASID" "$L" || { cat "$L"; false; }
  grep -q -- '--model claude-opus-5-5 --effort high --permission-mode auto' "$L" || { cat "$L"; false; }
}

@test "A5 drive, viewer under a SHELL: no split; one ^C^C detaches it, a second quits the agents view it became, and the launcher is typed once the shell is back" {
  attachfix idle shell; halfmoved healthy; attach_actors
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(order)" = "ctrl-c ctrl-c ctrl-c ctrl-c stop transplant transplant it2-run " ] || { cat "$A"; false; }
  grep -q '^it2-run -s 391 ' "$A" || { cat "$A"; false; }
  [ "$(jq -r .session_id "$LRU_REG_DIR/391.json")" = "$ASID" ] || false
  [[ "$(res reason)" == *"quit on ctrl-c, agents view quit on ctrl-c ctrl-c"* ]] || { res reason; false; }
}

@test "A6 a slow viewer detaches on the fallback round; the opt-in Ctrl+Z lead falls back to ^C^C when Ctrl+Z does nothing; the reason says which keys ended it" {
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/viewer-slow"
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(order)" = "it2-split ctrl-c ctrl-c ctrl-c ctrl-c stop transplant transplant it2-run " ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"quit on ctrl-c, then ctrl-c ctrl-c"* ]] || { res reason; false; }
  fresh 2
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/viewer-needs-ctrlc"; rm -f "$BATS_TEST_TMPDIR/viewer-slow"
  LRU_BG_ATTACH_QUIT_KEY=ctrl-z drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(order)" = "it2-split ctrl-z ctrl-c ctrl-c stop transplant transplant it2-run " ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"quit on ctrl-z, then ctrl-c ctrl-c"* ]] || { res reason; false; }
}

@test "A7 a viewer that never detaches: NOTMOVED, nothing stopped or transplanted, and the pane opened beside it is closed" {
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/viewer-holds"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = NOTMOVED ] || { res reason; false; }
  [ "$(order)" = "it2-split ctrl-c ctrl-c ctrl-c ctrl-c it2-close " ] || { cat "$A"; false; }
  grep -qx 'it2-close -f -s 300' "$A" || { cat "$A"; false; }
  cmp -s "$(S)/$ASID.jsonl" "$(Q)/$ASID.jsonl.handed-off" || { echo "the live copy was touched"; false; }
}

@test "A7b the spawnSync detach (attach parent waiting on a claude agents child) counts as detached in a root window; in a SHELL window an agents view that will not quit is NOTMOVED with nothing stopped and nothing typed" {
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/viewer-spawns"
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(res verdict)" = SWITCHED ] || { echo "$output"; cat "$A"; res reason; false; }
  grep -q '^72282 68854 .*claude attach '"$AJOB"'$' "$LRU_PS_SNAPSHOT" || { echo "the parent should still be waiting"; cat "$LRU_PS_SNAPSHOT"; false; }
  # the shell half: detached, then the agents view holds — the launcher must never be typed into it
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  rm -f "$BATS_TEST_TMPDIR/viewer-spawns"; touch "$BATS_TEST_TMPDIR/agents-holds"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(res verdict)" = NOTMOVED ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(order)" = "ctrl-c ctrl-c ctrl-c ctrl-c " ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"agents view it left (pid 72282) did not quit"* ]] || { res reason; false; }
  grep -q '^71268 ' "$LRU_PS_SNAPSHOT" || { echo "the job was stopped"; false; }
}

@test "A7c a claude that takes the viewer's shell window in the gap before the launcher: FAILED with the line to run, and nothing is typed into it" {
  attachfix idle shell; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/claude-takes-window"
  drive
  [ "$status" -eq 1 ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(res verdict)" = FAILED ] || { echo "$output"; cat "$A"; res reason; false; }
  ! grep -q '^it2-run' "$A" || { cat "$A"; false; }
  [[ "$(res reason)" == *"window 391 is not free to type into (a live registry row names window 391)"*"run in a free shell: cd "* ]] || { res reason; false; }
  # CONTROL: the kill switch types into it, which is the defect the last look prevents
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  LRU_BG_ATTACH_STRICT=off drive
  grep -q '^it2-run -s 391 ' "$A" || { cat "$A"; false; }
}

@test "A7d nested and suspended viewers never bind to the window above them: bg-attach-occupied in the census, NOTMOVED with no key at the drive; LRU_BG_ATTACH_STRICT=off shows the old binding" {
  # nested: window 200 → zsh → interactive claude X → zsh → attach (attach in the foreground)
  nestfix nested
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-attach-occupied" ] || { echo "$output"; false; }
  attach_actors; halfmoved healthy
  drive 200
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ ! -s "$A" ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = NOTMOVED ] || { res reason; false; }
  [[ "$(res reason)" == *bg-attach-occupied* ]] || { res reason; false; }
  run bash "$LRU" --switch-waitable bg-attach-occupied; [ "$status" -eq 1 ]
  LRU_BG_ATTACH_STRICT=off run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-session" ] || { echo "$output"; false; }
  # the same window with X's registry row: occupied by the row as well
  fresh 2; nestfix nested reg
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-attach-occupied" ] || { echo "$output"; false; }
  # stopped: the attach is a suspended job, claude Y is the foreground
  fresh 3; nestfix stopped
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-attach-occupied" ] || { echo "$output"; false; }
  attach_actors; halfmoved healthy
  drive 200
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ ! -s "$A" ] || { echo "$output"; cat "$A"; false; }
  # sibling: only the LIVE registry row on window 200 says it is a claude's; without the row it binds
  fresh 4; nestfix sibling reg
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-attach-occupied" ] || { echo "$output"; false; }
  rm -f "$LRU_REG_DIR/200.json"
  run bash "$LRU" --switch-census --target next3
  [ "$(row_of "$ASID" | cut -f1,7)" = "200"$'\t'"bg-session" ] || { echo "$output"; false; }
}

@test "A8 a refused split touches nothing; LRU_BG_ATTACH_SPLIT=off refuses before any act" {
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$BATS_TEST_TMPDIR/split-fails"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = NOTMOVED ] || { echo "$output"; cat "$A"; false; }
  [ "$(order)" = "it2-split " ] || { cat "$A"; false; }
  rm -f "$BATS_TEST_TMPDIR/split-fails"; : > "$A"
  LRU_BG_ATTACH_SPLIT=off drive
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -s "$A" ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"window 391's own process"*"LRU_BG_ATTACH_SPLIT=off"* ]] || { res reason; false; }
}

@test "A8b [RED] under launchd (no KITTY_WINDOW_ID, no CC_TERM) every it2 call carries CC_TERM=kitty beside the socket, so the wrapper reaches it2-kitty; LRU_IT2_KITTY_PIN=off is the old socket-only call" {
  attachfix idle root; halfmoved healthy; attach_actors
  export CC_TERM_KITTY_TO=unix:/tmp/kitty-fixture
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  grep -qx 'split CC_TERM=kitty TO=unix:/tmp/kitty-fixture KWID=' "$BATS_TEST_TMPDIR/it2-env.log" || { cat "$BATS_TEST_TMPDIR/it2-env.log"; false; }
  grep -qx 'run CC_TERM=kitty TO=unix:/tmp/kitty-fixture KWID=' "$BATS_TEST_TMPDIR/it2-env.log" || { cat "$BATS_TEST_TMPDIR/it2-env.log"; false; }
  ! grep -v 'CC_TERM=kitty' "$BATS_TEST_TMPDIR/it2-env.log" || false
  # the close on a refused move goes the same way
  fresh 2
  attachfix idle root; halfmoved healthy; attach_actors; touch "$BATS_TEST_TMPDIR/viewer-holds"
  drive
  grep -qx 'close CC_TERM=kitty TO=unix:/tmp/kitty-fixture KWID=' "$BATS_TEST_TMPDIR/it2-env.log" || { cat "$BATS_TEST_TMPDIR/it2-env.log"; false; }
  # CONTROL: the kill switch is the pre-fix call, the one the wrapper sends to iTerm2
  fresh 3
  attachfix idle root; halfmoved healthy; attach_actors; rm -f "$BATS_TEST_TMPDIR/viewer-holds"
  LRU_IT2_KITTY_PIN=off drive
  grep -qx 'split CC_TERM= TO=unix:/tmp/kitty-fixture KWID=' "$BATS_TEST_TMPDIR/it2-env.log" || { cat "$BATS_TEST_TMPDIR/it2-env.log"; false; }
  ! grep -q 'CC_TERM=kitty' "$BATS_TEST_TMPDIR/it2-env.log" || false
}

@test "A9 [RED] cc-lr: the prime example's --dry-run names the viewer window; --sid --no-wait queues it with source_pane 391" {
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" > "$STUBS/launchctl"; chmod +x "$STUBS/launchctl"
  export PATH="$STUBS:$PATH" LR_STATE_DIR="$LRU_STATE" CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999
  attachfix idle root; halfmoved limit
  run bash "$REPO/bin/cc-lr" switch --sid d425afab --target next3 --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq "^391 +d425afab +next4 → next3 +bg-session$" || { echo "$output"; false; }
  [[ "$output" == *"1 to move · DRY RUN"* ]] || { echo "$output"; false; }
  run bash "$REPO/bin/cc-lr" switch --sid d425afab --target next3 --no-wait
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.kind + " " + .source_pane + " " + .from + " " + .target' "$LRU_STATE/requests/cc-lr-switch-$ASID.json")" = "switch 391 next4 next3" ] \
    || { cat "$LRU_STATE/requests/cc-lr-switch-$ASID.json"; false; }
  [[ "$output" == *"relaunches it in (or beside) pane 391"* ]] || { echo "$output"; false; }
}

@test "A10 [RED] the prime example end to end through the drainer: SWITCHED, stopped under the husk's config, moved from the live copy, /limit-recover typed, mailed" {
  attachfix idle root; halfmoved limit; attach_actors
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"switch","sid":"%s","source_pane":"391","target":"next3","req_id":"e2e","requested_by":"999"}\n' "$ASID" > "$LRU_STATE/upgrade-queue/e2e.json"
  run bash "$LRU" --drain
  [ "$(res verdict)" = SWITCHED ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(res req_id)" = e2e ] || { echo "$output"; cat "$A"; res reason; false; }
  grep -qx "stop $AJOB cfg=$HOME/.claude-quaternary" "$A" || { cat "$A"; false; }
  grep -q -- "--sid $ASID --from $HOME/.claude-secondary --to $HOME/.claude-tertiary --phase admit" "$A" || { cat "$A"; false; }
  [ -f "$(T)/$ASID.jsonl" ] || { ls -R "$HOME"; false; }
  [ -f "$(S)/$ASID.jsonl.handed-off" ] || { ls -R "$HOME"; false; }
  grep -q -- '--prompt /limit-recover' "$(launcher)" || { cat "$(launcher)"; false; }
  grep -q '^999 CC-LR-SWITCH pane 391 .*verdict=SWITCHED' "$BATS_TEST_TMPDIR/notify.log" || { cat "$BATS_TEST_TMPDIR/notify.log"; false; }
  ! grep -q '^71268 ' "$LRU_PS_SNAPSHOT" || { echo "the bg job came back"; false; }
}

# ── L. THE TRANSPLANT READS THE LIVE COPY ─────────────────────────────────────────────────────────

@test "A11 [RED] the viewer is ended by SIGTERM first (no keys): SWITCHED, and the reason names the signal" {
  attachfix idle root; halfmoved healthy; attach_actors
  export LRU_BG_ATTACH_QUIT=term LRU_KILL_CMD="$STUBS/kill"
  cat > "$STUBS/kill" <<'STUB'
#!/bin/bash
echo "term $2" >> "$A"
[ -e "$(dirname "$A")/term-ignored" ] && exit 0
grep -v "^$2 " "$LRU_PS_SNAPSHOT" > "$LRU_PS_SNAPSHOT.t"; mv "$LRU_PS_SNAPSHOT.t" "$LRU_PS_SNAPSHOT"
STUB
  chmod +x "$STUBS/kill"
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  grep -qx 'term 72282' "$A" || { cat "$A"; false; }
  ! grep -q '^ctrl-c' "$A" || { echo "keys were sent although the signal ended the viewer"; cat "$A"; false; }
  [[ "$(res reason)" == *"quit on SIGTERM to the viewer"* ]] || { res reason; false; }
}

@test "A11b CONTROL: a viewer that survives SIGTERM still detaches on ^C^C" {
  attachfix idle root; halfmoved healthy; attach_actors
  export LRU_BG_ATTACH_QUIT=term LRU_KILL_CMD="$STUBS/kill"
  printf '#!/bin/bash\necho "term $2" >> "$A"\n' > "$STUBS/kill"; chmod +x "$STUBS/kill"
  drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  grep -qx 'term 72282' "$A" || { cat "$A"; false; }
  [ "$(grep -c '^ctrl-c id:391$' "$A")" -eq 2 ] || { cat "$A"; false; }
}

@test "A11c CONTROL: LRU_BG_ATTACH_QUIT=keys sends no signal and quits the viewer on ^C^C" {
  attachfix idle root; halfmoved healthy; attach_actors
  export LRU_BG_ATTACH_QUIT=keys LRU_KILL_CMD="$STUBS/kill"
  printf '#!/bin/bash\necho "term $2" >> "$A"\n' > "$STUBS/kill"; chmod +x "$STUBS/kill"
  drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  ! grep -q '^term' "$A" || { cat "$A"; false; }
  [ "$(grep -c '^ctrl-c id:391$' "$A")" -eq 2 ] || { cat "$A"; false; }
}

@test "T1 [RED] the relaunch carries a one-shot admission token minted before any act, so the pane's gate admits it first time" {
  attachfix idle root; halfmoved healthy; attach_actors
  drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  grep -q '^probe ' "$(dirname "$A")/probe.log" || { echo "no admission probe ran"; false; }
  grep -q "^export LR_ADMIT_TOKEN=tok-$ASID$" "$(launcher)" || { cat "$(launcher)"; false; }
}

@test "T2 a capacity refusal parks the move before anything is touched: NOTMOVED, no split, no key, no stop" {
  attachfix idle root; halfmoved healthy; attach_actors
  touch "$(dirname "$A")/ca-refuse"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = NOTMOVED ] || { res reason; false; }
  [[ "$(res reason)" == *"capacity refused the relaunch before anything was touched: segments 95% > 90%"* ]] || { res reason; false; }
  grep -q '^probe ' "$(dirname "$A")/probe.log" || false
  [ ! -s "$A" ] || { echo "a refused probe must touch nothing"; cat "$A"; false; }
}

@test "T3 CONTROL: LRU_BG_ADMIT_TOKEN=off neither probes nor mints, the pre-fix launcher" {
  attachfix idle root; halfmoved healthy; attach_actors
  export LRU_BG_ADMIT_TOKEN=off
  drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  [ ! -s "$(dirname "$A")/probe.log" ] || { cat "$(dirname "$A")/probe.log"; false; }
  grep -q "^export LR_ADMIT_TOKEN=''$" "$(launcher)" || { cat "$(launcher)"; false; }
}

@test "L1 [RED] a half-moved bg session is stopped under its own config but transplanted FROM the live copy; LRU_BG_LIVE_SOURCE=off reproduces the old failure" {
  attachfix idle shell; halfmoved healthy; attach_actors
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  grep -qx "stop $AJOB cfg=$HOME/.claude-quaternary" "$A" || { cat "$A"; false; }
  [ "$(grep -c -- "--from $HOME/.claude-secondary --to $HOME/.claude-tertiary" "$A")" -eq 2 ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"transcript moved $HOME/.claude-secondary -> $HOME/.claude-tertiary"* ]] || { res reason; false; }
  # CONTROL, fresh fixture: the old source choice dies AFTER the stop
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  LRU_BG_LIVE_SOURCE=off drive
  [ "$status" -eq 1 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = FAILED ] || { echo "$output"; cat "$A"; false; }
  grep -q -- "--from $HOME/.claude-quaternary " "$A" || { cat "$A"; false; }
}

@test "L2 no store provably holds a live copy (a tombstone to an empty store, or none at all): NOTMOVED, nothing stopped" {
  attachfix idle shell; halfmoved healthy; attach_actors
  rm -f "$(S)/$ASID.jsonl"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ "$(res verdict)" = NOTMOVED ] || { echo "$output"; cat "$A"; false; }
  [ ! -s "$A" ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"no store provably holds a live transcript"*"only a retired copy"* ]] || { res reason; false; }
  rm -f "$(Q)/$ASID.HANDOFF.json"
  drive
  [ "$status" -eq 3 ] && [ ! -s "$A" ] || { echo "$output"; cat "$A"; false; }
}

@test "L3 a live copy SHORTER than the husk's retired copy is refused before anything is touched" {
  attachfix idle shell; halfmoved healthy; attach_actors
  echo '{"type":"user","message":{"content":"extra"}}' >> "$(Q)/$ASID.jsonl.handed-off"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; false; }
  [ ! -s "$A" ] || { echo "$output"; cat "$A"; false; }
  [[ "$(res reason)" == *"SHORTER than the retired copy"* ]] || { res reason; false; }
}

@test "L4 a live copy already under the target is not transplanted again; the custody lock leads there" {
  attachfix idle shell; halfmoved healthy; attach_actors
  mkdir -p "$(T)"; mv "$(S)/$ASID.jsonl" "$(T)/$ASID.jsonl"
  # the tombstone still says next2 and next2 is empty: only the LOCK knows where the copy went
  mkdir -p "$LRU_STATE/locks"
  printf '{"sid":"%s","from":"%s","to":"%s","owner":"%s"}\n' "$ASID" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-tertiary" > "$LRU_STATE/locks/$ASID.lock"
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  [ "$(order)" = "ctrl-c ctrl-c ctrl-c ctrl-c stop it2-run " ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"the transcript was already under $HOME/.claude-tertiary"* ]] || { res reason; false; }
}

@test "L5 the REAL lr-transplant, hermetic: the second hop next2 -> next3 lands, the chain records all three stores; the old source choice is refused with next2 untouched" {
  attachfix idle shell; halfmoved healthy; attach_actors
  export LRU_TRANSPLANT="$REPO/scripts/limit-recover/lr-transplant.sh" LR_STATE_DIR="$LRU_STATE"
  export LR_CONFIG_DIRS="$HOME/.claude-quaternary:$HOME/.claude-secondary:$HOME/.claude-tertiary"
  cp -p "$(S)/$ASID.jsonl" "$BATS_TEST_TMPDIR/orig.jsonl"
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; cat "$LRU_STATE"/switch/*/transplant.log; false; }
  cmp -s "$(T)/$ASID.jsonl" "$BATS_TEST_TMPDIR/orig.jsonl" || { echo "the target is not the live copy"; false; }
  [ -f "$(S)/$ASID.jsonl.handed-off" ] || { ls "$(S)"; false; }
  [ ! -e "$(S)/$ASID.jsonl" ] || { ls "$(S)"; false; }
  [ "$(jq -r .handed_off_to "$(S)/$ASID.HANDOFF.json")" = "$HOME/.claude-tertiary" ] || { cat "$(S)/$ASID.HANDOFF.json"; false; }
  # the chain's spellings mix /var and /private/var (lr-transplant resolves only --from); the STORES are what count
  [ "$(jq -c '[.chain[] | sub("/$"; "") | split("/") | last]' "$LRU_STATE/locks/$ASID.lock")" = '[".claude-quaternary",".claude-secondary",".claude-tertiary"]' ] \
    || { cat "$LRU_STATE/locks/$ASID.lock"; false; }
  [ "$(jq -r '.custody_from // empty' "$LRU_STATE/locks/$ASID.lock")" = tombstones ] || { cat "$LRU_STATE/locks/$ASID.lock"; false; }
  # CONTROL, fresh fixture: --from the husk is refused by the real script, and next2 is untouched
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  export LRU_TRANSPLANT="$REPO/scripts/limit-recover/lr-transplant.sh"
  cp -p "$(S)/$ASID.jsonl" "$BATS_TEST_TMPDIR/orig.jsonl"
  LRU_BG_LIVE_SOURCE=off drive
  [ "$(res verdict)" = FAILED ] || { res reason; false; }
  [[ "$(res reason)" == *"lr-transplant refused"* ]] || { res reason; false; }
  # refused for the reason the control claims (no live transcript in the husk), not for the first
  # half's custody lock, which fresh() no longer lets it read
  grep -q "no transcript $ASID under " "$LRU_STATE"/switch/*/transplant.log || { cat "$LRU_STATE"/switch/*/transplant.log; false; }
  cmp -s "$(S)/$ASID.jsonl" "$BATS_TEST_TMPDIR/orig.jsonl" || { echo "next2's live copy changed"; false; }
}

@test "L6 a bg job ALSO live on this conversation under the live-copy store (next2) is a split brain: NOTMOVED, nothing stopped, nothing typed" {
  attachfix idle shell; halfmoved healthy; attach_actors
  mkdir -p "$HOME/.claude-secondary/sessions"
  printf '%d 1 %s %s\n' 71300 "$LST" 'claude bg-spare --bg-spare /tmp/b.claim.sock' >> "$LRU_PS_SNAPSHOT"
  printf '{"pid":71300,"sessionId":"%s","cwd":"%s","kind":"bg","jobId":"0bbbbbbb","status":"idle","procStart":"%s"}\n' \
    "$ASID" "$BATS_TEST_TMPDIR" "$LST" > "$HOME/.claude-secondary/sessions/71300.json"
  drive
  [ "$status" -eq 3 ] || { echo "$output"; cat "$A"; res reason; false; }
  [ "$(res verdict)" = NOTMOVED ] || { echo "$output"; cat "$A"; res reason; false; }
  [ ! -s "$A" ] || { cat "$A"; false; }
  [[ "$(res reason)" == *"a bg job is also live on this conversation under $HOME/.claude-secondary"* ]] || { res reason; false; }
  # CONTROL (as L1): the second job gone, the same drive moves it
  grep -v '^71300 ' "$LRU_PS_SNAPSHOT" > "$LRU_PS_SNAPSHOT.t"; mv "$LRU_PS_SNAPSHOT.t" "$LRU_PS_SNAPSHOT"
  drive
  [ "$status" -eq 0 ] && [ "$(res verdict)" = SWITCHED ] || { echo "$output"; cat "$A"; res reason; false; }
}

# ── P. THE RELAUNCH PROMPT ────────────────────────────────────────────────────────────────────────

@test "P1 [RED] a session whose main transcript ends on a limit relaunches with /limit-recover naming both accounts; a healthy one relaunches prompt-free" {
  attachfix idle shell; halfmoved limit; attach_actors
  drive
  [ "$status" -eq 0 ] || { echo "$output"; cat "$A"; false; }
  L="$(launcher)"
  grep -q -- '--prompt /limit-recover\\ recover\\ THIS\\ session\\ in\\ place' "$L" || { cat "$L"; false; }
  grep -q 'from\\ next4\\ to\\ next3' "$L" || { cat "$L"; false; }
  grep -q "LR_SUBMIT_TOKEN=run:d425afab:recover:" "$L" || { cat "$L"; false; }
  [[ "$(res reason)" == *"relaunch prompt /limit-recover (main transcript ends on a five_hour limit): no state"* ]] || { res reason; false; }
  # CONTROL: healthy → no prompt at all, and never the old same-account upgrade text
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  drive
  L="$(launcher)"
  grep -q -- "--prompt ''" "$L" || { cat "$L"; false; }
  ! grep -q 'In-place upgrade' "$L" || { cat "$L"; false; }
  [[ "$(res reason)" == *"relaunched prompt-free (no limit evidence)"* ]] || { res reason; false; }
}

@test "P2 a healthy lead with a workflow agent dead on a limit AFTER its last healthy turn gets the prompt; one dead BEFORE it does not" {
  attachfix idle shell; halfmoved healthy; attach_actors
  d="$(S)/$ASID/subagents/workflows/wf_x"; mkdir -p "$d"
  printf '%s\n' "${LIM/07:59:47.602Z/07:56:06.000Z}" > "$d/agent-a.jsonl"
  drive
  grep -q -- '--prompt /limit-recover' "$(launcher)" || { cat "$(launcher)"; false; }
  [[ "$(res reason)" == *"1 subagent(s) died on a limit"* ]] || { res reason; false; }
  # CONTROL: the same agent record, older than the lead's last healthy turn (07:55:04)
  fresh 2
  attachfix idle shell; halfmoved healthy; attach_actors
  d="$(S)/$ASID/subagents/workflows/wf_x"; mkdir -p "$d"
  printf '%s\n' "${LIM/07:59:47.602Z/07:50:00.000Z}" > "$d/agent-a.jsonl"
  drive
  grep -q -- "--prompt ''" "$(launcher)" || { cat "$(launcher)"; false; }
}

@test "P3 kill switch and an unreachable predicate both relaunch prompt-free, each saying why" {
  attachfix idle shell; halfmoved limit; attach_actors
  LRU_BG_RELAUNCH_PROMPT=off drive
  grep -q -- "--prompt ''" "$(launcher)" || { cat "$(launcher)"; false; }
  [[ "$(res reason)" == *"LRU_BG_RELAUNCH_PROMPT=off"* ]] || { res reason; false; }
  fresh 2
  attachfix idle shell; halfmoved limit; attach_actors
  LRU_PREDICATE="$BATS_TEST_TMPDIR/absent-predicate.sh" drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  grep -q -- "--prompt ''" "$(launcher)" || { cat "$(launcher)"; false; }
  [[ "$(res reason)" == *"limit check could not run"* ]] || { res reason; false; }
}

@test "P4 the submit is reported beside the verdict: 'submitted' when lr-fire-resume records it, 'no state' otherwise — SWITCHED either way" {
  attachfix idle shell; halfmoved limit; attach_actors
  touch "$BATS_TEST_TMPDIR/submit-ok"
  drive
  [ "$(res verdict)" = SWITCHED ] || { res reason; false; }
  [[ "$(res reason)" == *"relaunch prompt /limit-recover (main transcript ends on a five_hour limit): submitted"* ]] || { res reason; false; }
}

@test "P5 one answer from either predicate shape: limit-pending is used when it answers, classify-tail when the verb is absent" {
  attachfix idle shell; halfmoved healthy; attach_actors
  # a predicate whose limit-pending says pending (agents only) — trusted as given
  printf '#!/bin/bash\n[ "$1" = limit-pending ] && { echo %s; exit 0; }\nexit 2\n' \
    "'{\"pending\":true,\"main\":{\"limit\":false},\"agents_limited\":3,\"agent_caps\":[\"five_hour\"]}'" > "$STUBS/pred-new"
  LRU_PREDICATE="$STUBS/pred-new" drive
  [[ "$(res reason)" == *"relaunch prompt /limit-recover (3 subagent(s) died on a limit)"* ]] || { res reason; false; }
  # a predicate that predates the verb (rc 2) and only classifies tails — the fallback asks it per file
  fresh 2
  attachfix idle shell; halfmoved limit; attach_actors
  printf '#!/bin/bash\n[ "$1" = limit-pending ] && exit 2\nexec bash %q "$@"\n' "$REPO/scripts/limit-recover/lr-predicate.sh" > "$STUBS/pred-old"
  LRU_PREDICATE="$STUBS/pred-old" drive
  [[ "$(res reason)" == *"relaunch prompt /limit-recover (main transcript ends on a five_hour limit)"* ]] || { res reason; false; }
}

@test "P6 the launcher stays pure ASCII: a non-ASCII account value refuses the mint; the switch role carries no prompt, switch-recover the mode in words" {
  run bash -c '. "$1"; d="$2"
    lru_mint_launcher "$d/a" /c /w "$3" m high auto "" switch-recover "" "" "next4" "nëxt3" && echo MINTED' _ "$LRU" "$BATS_TEST_TMPDIR" "$ASID"
  [[ "$output" == *"REFUSED: a launcher value is not pure ASCII"* ]] || { echo "$output"; false; }
  [[ "$output" != *MINTED* ]] || { echo "$output"; false; }
  run bash -c '. "$1"; lru_mint_launcher "$2/b" /c /w "$3" m high auto "" switch' _ "$LRU" "$BATS_TEST_TMPDIR" "$ASID"
  [ "$status" -eq 0 ] && grep -q -- "--prompt ''" "$output" && grep -q "LR_SUBMIT_TOKEN=''" "$output" || { echo "$output"; cat "$output"; false; }
}
