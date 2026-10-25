# shellcheck shell=bash
# fixture-289.bash — the world of husk pane 289 (2026-10-24), for tests/pane-289-replay.bats.
#
# Session 7555024a ran in ~/Development/personal, edited two files of its own (NOTES.md, scene.py),
# committed them, wrote "Good to close: yes" and self-closed. Its pane was the last one of a
# native-fullscreen kitty window, so the fullscreen guard kept it as a bare shell; every reader of that
# shell then judged the session by the WHOLE cwd's porcelain, six sibling changes under deadlines/items/
# it never touched. docs/research/husk-history-2026-10-24/FIX-DESIGN.md §5 specifies this world.
#
# Every subject runs from REPO (CC_REPLAY_REPO, else this checkout), so an archived tree replays
# unchanged. Every seam each subject reads is pinned under $BATS_TEST_TMPDIR, and every kitty, it2, ps,
# kill, pager and osascript a subject could reach is a logging stub: nothing here touches the live
# terminal or the real ~/.claude. The stubs find the world through $FX_T, so a caller that clears the
# environment (env -i) passes FX_T itself.
# shellcheck disable=SC2034,SC2016  # the world's names are read by the suite; stub lines are literal

FX_FS_LINE='kitty-fullscreen-guard: refused (refused-fs) kitty window 289 scope=pane mode=refuse: state=FS types=[4] onscreen=False'
FX_RUNNER_ARGV='--window 289 --mode refuse --scope pane --tool cc-pane-runner'
NOTES=reso-walkthrough/short/C-scenes/NOTES.md SCENE=reso-walkthrough/short/C-scenes/scene.py

fx_iso()   { TZ=UTC date -r "$1" '+%Y-%m-%dT%H:%M:%S.000Z'; }
fx_local() { date -r "$1" '+%Y-%m-%d %H:%M:%S'; }
fx_slug()  { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }
fx_lst()   { date -u -r "$2" '+%a %b %d %T %Y' > "$T/ps/lstart.$1"; }
fx_git()   { /usr/bin/git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
fx_stub()  { # DIR NAME LINE… → a #!/bin/bash stub of those lines (cc-stub's no-kalloc form)
  local d="$1" n="$2"; shift 2
  cc_stub "$d" "$n" "$(printf '#!/bin/bash\n'; printf '%s\n' "$@")"
}
fx_logger() { # DIR NAME [LINE…] → a stub appending its argv to $FX_T/NAME.log, then running LINE…
  local d="$1" n="$2"; shift 2
  fx_stub "$d" "$n" "printf '%s\n' \"\$*\" >> \"\$FX_T/$n.log\"" "$@"
}

fx289_world() {
  REPO="${CC_REPLAY_REPO:-$BATS_TEST_DIRNAME/..}"
  T="$BATS_TEST_TMPDIR"; S="$T/bin"; P="$T/personal"; FX_KPID=$$
  SID=7555024a-5b1e-4c0d-9a2e-000000000289 SID304=d0d00017-4e2a-4b11-8c3d-000000000304
  NOW=$(date +%s); KST=$((NOW - 36000)); REG=$((NOW - 7200)); XT=$((NOW - 600))
  mkdir -p "$S" "$T/cbin" "$T/ps" "$T/acct" "$T/pane-exit" "$T/fired" "$T/custody" "$T/reg" "$T/beats" \
    "$T/succ" "$T/pv" "$T/dev" "$T/roles" "$T/jetsam" "$T/teardown" "$HOME/.claude/logs"
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID KITTY_PID ITERM_SESSION_ID TMUX CC_PANE_ID CC_TERM CC_TERM_KITTY \
    CLAUDE_CONFIG_DIR CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_PANE_CLOSE_ON_EXIT \
    CC_PANE_RUNNER_OWNS_CLOSE CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED LR_RUN_DIR CC_SAY_VERBOSE \
    LCW_ORPHAN_CLOSE CC_PANE_SUCCESSOR CC_PANE_CLOSE_REMOTE CC_PANE_HOLD_MAX_POLLS GIT_DIR GIT_WORK_TREE \
    GIT_INDEX_FILE CLAUDE_RC FX_INTERACTIVE
  export FX_T="$T" PATH="$S:/usr/bin:/bin"
  # the runner (KITTY_WINDOW_ID, KITTY_PID and SHELL ride on each fx_runner call, never the suite)
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_PANE_CLOSE_QUEUE_DIR="$HOME/.claude/state/pane-close-queue" \
    CC_SAY_LOG="$T/say.jsonl" CC_PANE_RUNNER_TTY="$T/tty289" CC_PANE_VERDICT_KITTY_BIN="$S/kitty" \
    CC_PANE_VERDICT_DIR="$T/pv" CC_PANE_VERDICT_COLS=80 CC_KITTY_FS_GUARD="$S/fsguard" \
    CC_REGISTRY_DIR="$T/reg" CC_BEAT_DIR="$T/beats" CC_PANE_WEDGE_WATCH=0 CC_PANE_SUCCESSOR_DIR="$T/succ" \
    CC_TERM_KITTY_TO="unix:$T/no-kitty" CC_PANE_HOLD_STEP_S=0
  # the closer, and lib/pane-end.sh under it (custody is read from CC_CUSTODY_DIR's store files)
  export CC_PANE_CLOSE_EXIT_DIR="$T/pane-exit" CC_PANE_CLOSE_FIRED_DIR="$T/fired" CC_FIRED_DIR="$T/fired" \
    CC_PANE_CLOSE_WATCHDOG_LOG="$T/watchdog.log" CC_PANE_CLOSE_STORES="$T/acct" \
    CC_PANE_CLOSE_PS_BIN="$T/cbin/ps" CC_PANE_CLOSE_KILL_BIN="$T/cbin/kill" CC_PANE_CLOSE_IT2="$S/it2" \
    CC_PANE_CLOSE_KITTY_PID=610 CC_PANE_CLOSE_LOG="$T/close.jsonl" CC_PANE_CLOSE_HANDOFFS_LOG="$T/handoffs.jsonl" \
    CC_PANE_CLOSE_FIND_BIN="$S/cc-find" CC_PANE_CLOSE_SETTLE_S=0 CC_PANE_CLOSE_REAP_S=0 \
    CC_CUSTODY_DIR="$T/custody" CC_CRASH_LOG="$T/crashes.jsonl"
  # the sweep
  export CC_HUSK_PANES_JSON="$T/panes.json" CC_HUSK_PS_FILE="$T/ps.txt" CC_HUSK_CRASH_LOG="$T/crashes.jsonl" \
    CC_HUSK_WATCHDOG_LOG="$T/watchdog.log" CC_HUSK_STORES="$T/acct" CC_HUSK_IT2="$S/husk-it2" \
    CC_HUSK_LOG="$T/husk.jsonl" CC_HUSK_HANDOFFS_LOG="$T/handoffs.jsonl" CC_HUSK_KITTY_START_EPOCH="$KST" \
    CC_HUSK_LIVE_SIDS="$T/live-sids" CC_HUSK_SESSIONS="$S/cc-sessions" LR_STATE_DIR="$T/lr-state" \
    CC_HUSK_CUSTODY_LIB="$REPO/lib/pane-custody.sh" CC_HUSK_LR_LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  # the crash watchdog's pane verdict (its closer is a recorder: B4 reads the watchdog's own state)
  export CC_PANE_VERDICT_TTY_PROCS="$T/procs" CC_PANE_VERDICT_SETTLE_S=0 CC_PANE_VERDICT_DEV="$T/dev" \
    CC_PANE_VERDICT_CWD="$P" CC_PANE_VERDICT_PANE=289 CC_PANE_VERDICT_TTY=ttys046 CC_PANE_VERDICT_CFG="$T/acct" \
    CC_ROLES_DIR="$T/roles" CC_ACCOUNT_BASES="$T/acct" CC_JETSAM_DIRS="$T/jetsam" CC_TEARDOWN_DIR="$T/teardown" \
    CC_SESSIONS_LOG="$T/sessions.log" CC_DEATH_PAGER="$S/pager" CC_DEATH_OSA_BIN="$S/osascript" \
    CC_PANE_CLOSE_BIN="$S/wd-closer" CC_PANE_VERDICT_CLOSE_GRACE_S=0 CC_PANE_VERDICT_TOOL=on
  fx289_stubs; fx289_repo; fx289_records
}

fx289_stubs() {
  fx_stub "$S" claude '[ -z "${CC_PANE_STARTED_FILE:-}" ] || : > "$CC_PANE_STARTED_FILE"' 'exit "${CLAUDE_RC:-0}"'
  fx_logger "$S" git 'exec /usr/bin/git "$@"'
  # `-c LINE [ARG…]` runs the line with its arguments; bare (the fallback shell) it records that it ran
  fx_stub "$S" fakeshell 'while [ $# -gt 0 ]; do [ "$1" = -c ] && { shift; exec /bin/bash -c "$@"; }; shift; done' \
    ': > "$FX_T/shell-ran"' 'exit 7'
  # the guard: one `rc<TAB>stderr` line per call from guard-seq (anyfs-seq for --any-fs), the last one
  # repeating; no seq file answers rc 0. It ignores TERM/INT (A1g signals the runner's whole group).
  fx_stub "$S" fsguard 'trap "" TERM INT' 'printf "%s\n" "$*" >> "$FX_T/guard-log"' \
    'case " $* " in *" --any-fs "*) q="$FX_T/anyfs-seq" ;; *) q="$FX_T/guard-seq" ;; esac' \
    'n=$(( $(cat "$q.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$q.n"' \
    '[ "$n" != 1 ] || [ ! -s "$FX_T/guard-sleep" ] || /bin/sleep "$(cat "$FX_T/guard-sleep")"' \
    'l=$(sed -n "${n}p" "$q" 2>/dev/null); [ -n "$l" ] || l=$(tail -n 1 "$q" 2>/dev/null)' \
    'IFS="$(printf "\t")" read -r rc e <<<"$l"; [ -z "$e" ] || printf "%s\n" "$e" >&2' 'exit "${rc:-0}"'
  local n; for n in kitty kitten osascript terminal-notifier pcq-verdict; do fx_logger "$S" "$n"; done
  fx_logger "$S" it2 'case "$1 $2" in "session list") echo "[{\"id\":289},{\"id\":304}]" ;; esac'
  fx_logger "$S" husk-it2
  fx_logger "$S" pager 'echo os=posted'
  fx_logger "$S" wd-closer 'echo "pane 289: WOULD CLOSE — recorder"'
  fx_logger "$S" pcq-close 'echo "pane 289: REFUSED — recorder"' 'exit 1'
  fx_stub "$S" pcq-sock 'echo "unix:/tmp/kitty-$FX_KPID"'
  fx_stub "$S" cc-find 'exit 0'
  fx_stub "$S" cc-sessions 'echo "[]"'
  # the closer's ps: `-o lstart= -p P` and `-o stat= -p P` from ps/lstart.P, `-t TTY` rows from ps/tty.TTY
  fx_stub "$T/cbin" ps 'for a; do p="$a"; done' 'case "$2" in' \
    '  lstart=) cat "$FX_T/ps/lstart.$p" 2>/dev/null ;;' '  stat=) [ ! -f "$FX_T/ps/lstart.$p" ] || echo Ss ;;' \
    '  tty=) ;;' '  *) cat "$FX_T/ps/tty.$p" 2>/dev/null ;;' 'esac'
  fx_logger "$T/cbin" kill
}

fx289_repo() { # a dozen committed files, the session's two landed, then the siblings' dirt
  local f
  /usr/bin/git init -q -b master "$P"
  mkdir -p "$P/reso-walkthrough/short/C-scenes" "$P/deadlines/items" "$P/notes"
  for f in README.md old.md notes/a.md notes/b.md notes/c.md deadlines/items/d1.md deadlines/items/d2.md \
           deadlines/items/d3.md deadlines/items/d4.md deadlines/items/d5.md; do echo "$f" > "$P/$f"; done
  echo C1 > "$P/$NOTES"; echo 'print(1)' > "$P/$SCENE"
  fx_git add -A; fx_git commit -q -m init
  echo C2 >> "$P/$NOTES"; echo 'print(2)' >> "$P/$SCENE"; fx_git commit -q -am "C scenes"
  # 2 modified + 3 untracked an hour before the session, 1 untracked after its exit = 6 changes
  echo sib >> "$P/deadlines/items/d1.md"; echo sib >> "$P/deadlines/items/d2.md"
  for f in n1 n2 n3; do echo "$f" > "$P/deadlines/items/$f.md"; done
  for f in d1 d2 n1 n2 n3; do touch -t "$(date -r $((REG - 3600)) +%Y%m%d%H%M.%S)" "$P/deadlines/items/$f.md"; done
  echo late > "$P/deadlines/items/late.md"
}

fx289_records() {
  printf '[%s] registered session=%s pid=7000 tty=ttys046 pane=289\n' "$(fx_local "$REG")" "$SID" > "$T/watchdog.log"
  fx_crash RECYCLE clean-exit; fx_exit 0
  printf 'Ss+ -zsh\n' > "$T/procs"; : > "$T/dev/ttys046"; : > "$T/tty289"; : > "$T/live-sids"
  printf '[{"id":"289","pid":5000,"cwd":"%s"}]\n' "$P" > "$T/panes.json"
  printf '%s\n' "5000 1 login -fp chris" "5001 5000 -zsh" "5100 1 login -fp chris" "5101 5100 -zsh" > "$T/ps.txt"
  fx_lst 610 "$KST"; fx_lst 5000 $((REG - 4)); fx_lst 5001 $((REG - 4))
  printf '5000 610 /usr/bin/login\n5001 5000 -zsh\n' > "$T/ps/tty.ttys046"
  TX="$T/acct/projects/$(fx_slug "$P")/$SID.jsonl"; mkdir -p "${TX%/*}"
  { fx_tx_head; fx_text "C scenes landed. Good to close: yes — nothing open"; fx_selfclose; } > "$TX"
}

fx_crash() { printf '{"sid":"%s","class":"%s","cause":"%s"}\n' "$SID" "$1" "$2" > "$T/crashes.jsonl"; }
fx_exit() { # rc [pane] [ts] [tail] → the runner's exit record
  printf '{"rc":%s,"claude_started":true,"launch_sha":"","ts":%s%s}\n' "$1" "${3:-$XT}" "${4:+,\"tail\":\"$4\"}" \
    > "$T/pane-exit/${2:-289}.json"
}
fx_guard() { # 3fs | 3u | <rc> … → the guard's answers, in call order
  local a; : > "$T/guard-seq"
  for a; do case "$a" in
    3fs) printf '3\t%s\n' "$FX_FS_LINE" ;;
    3u)  printf '3\t%s\n' 'kitty-fullscreen-guard: refused (kitten-failed) kitty window 289 scope=pane mode=refuse: state=UNKNOWN types=None' ;;
    *)   printf '%s\t\n' "$a" ;;
  esac >> "$T/guard-seq"; done
}

# ── the transcript: one record per call, 10 s apart from the registration; FX_X merges into each ──
_fx_rec() { # type role content-json
  local x="${FX_X:-}"; [ -n "$x" ] || x='{}'
  _FX_N=$((_FX_N + 1))
  jq -cn --arg ty "$1" --arg r "$2" --argjson c "$3" --argjson x "$x" --arg cwd "$P" --arg sid "$SID" \
    --arg ts "$(fx_iso $((REG + _FX_N * 10)))" '{type:$ty,cwd:$cwd,sessionId:$sid,timestamp:$ts,message:{role:$r,content:$c}} + $x'
}
fx_user()  { _fx_rec user user "$(jq -cn --arg t "$1" '$t')"; }
fx_text()  { _fx_rec assistant assistant "$(jq -cn --arg t "$1" '[{type:"text",text:$t}]')"; }
fx_think() { _fx_rec assistant assistant "$(jq -cn --arg t "$1" '[{type:"thinking",thinking:$t}]')"; }
fx_tool()  { # id name input-json [open] → a tool_use, then its tool_result unless `open`
  _fx_rec assistant assistant "$(jq -cn --arg i "$1" --arg n "$2" --argjson in "$3" '[{type:"tool_use",id:$i,name:$n,input:$in}]')"
  [ "${4:-}" = open ] || _fx_rec user user "$(jq -cn --arg i "$1" '[{type:"tool_result",tool_use_id:$i,content:"ok"}]')"
}
fx_tx_head() {
  _FX_N=0
  fx_user "walk the C scenes"
  fx_tool tu1 Edit "$(jq -cn --arg f "$P/$NOTES" '{file_path:$f,old_string:"C1",new_string:"C2"}')"
  fx_tool tu2 Write "$(jq -cn --arg f "$P/$SCENE" '{file_path:$f,content:"print(2)"}')"
}
fx_selfclose() { fx_tool tu9 Bash '{"command":"~/.claude/scripts/handoff-fire.sh self-close --terminal"}' open; }

# ── worlds a few arms add ───────────────────────────────────────────────────────────────────────
fx_remote() { # origin: a bare repo holding master, origin/HEAD → origin/master
  /usr/bin/git init -q --bare -b master "$T/origin.git"
  fx_git remote add origin "$T/origin.git"; fx_git push -q origin master 2>/dev/null
  fx_git remote set-head origin master
}
fx_peer_push() { # $1=path → another checkout lands a change to it on origin
  /usr/bin/git clone -q "$T/origin.git" "$T/peer" 2>/dev/null; echo peer >> "$T/peer/$1"
  /usr/bin/git -C "$T/peer" -c user.email=p@p -c user.name=p commit -q -am peer
  /usr/bin/git -C "$T/peer" push -q origin master 2>/dev/null
}
fx_custody_return() { # pane 289's orchestrator opened custody after the session began, then returned it
  local o='"cwd":"/o","originatorPane":"12","targetPane":"289","marker":"m289","slug":"c-scenes"'
  printf '{"ts":"%s","kind":"open",%s}\n{"ts":"%s","kind":"return",%s}\n' \
    "$(fx_iso $((REG + 60)))" "$o" "$(fx_iso $((XT + 60)))" "$o" > "$T/custody/o.jsonl"
}
fx_pane304() { # $1=none|empty — pane 304: registered, exited clean, and no transcript (or a 0-record one)
  printf '[%s] registered session=%s pid=7100 tty=ttys047 pane=304\n' "$(fx_local $((REG + 30)))" "$SID304" >> "$T/watchdog.log"
  printf '{"sid":"%s","class":"RECYCLE","cause":"clean-exit"}\n' "$SID304" >> "$T/crashes.jsonl"
  fx_exit 0 304
  fx_lst 5100 $((REG + 26)); fx_lst 5101 $((REG + 26)); printf '5100 610 /usr/bin/login\n5101 5100 -zsh\n' > "$T/ps/tty.ttys047"
  printf '[{"id":"304","pid":5100,"cwd":"%s"}]\n' "$P" > "$T/panes.json"
  [ "$1" = none ] || : > "${TX%/*}/$SID304.jsonl"
}
fx_watcher_home() { # the __selfclose watcher's HOME (it2 closes with $IT2_CLOSE_RC) and its PATH shims
  mkdir -p "$T/wh/.claude/bin" "$T/wh/.claude/cc-roles" "$T/wbin"
  fx_logger "$T/wh/.claude/bin" it2 'case "$1 $2" in "session list") printf "289\nSUCC\n" ;; "session close") exit "${IT2_CLOSE_RC:-0}" ;; esac'
  fx_logger "$T/wh/.claude/bin" cc-notify
  # every tty reads as a bare shell: root 700010, no claude beneath it
  fx_stub "$T/wbin" ps 'case " $* " in' '  *" -g "*) echo "700010 zsh" ;;' '  *" -axo "*|*" -Ao "*) echo "700010 1" ;;' \
    '  *" -p "*) case "$*" in *comm=*) echo zsh ;; *) echo -zsh ;; esac ;;' '  *" -t "*) echo 700010 ;;' 'esac'
}
fx_lr_tail() { # $1=lr_rc → $T/lr-tail.sh: lr-fire-resume.sh from the post-expect stty to its final exec, as is
  { printf '_lrf_say() { :; }; _lrf_detail() { :; }\nlr_rc=%s lr_tty_saved="" SID=%s\n' "$1" "$SID"
    sed -n '/^\[ -z "\$lr_tty_saved" \]/,/^exec "\${SHELL:-\/bin\/zsh}" -l -i$/p' "$REPO/scripts/limit-recover/lr-fire-resume.sh"
  } > "$T/lr-tail.sh"
}

# ── running the subjects ────────────────────────────────────────────────────────────────────────
fx_runner() { # $1=command → the real runner as pane 289 (FX_INTERACTIVE=1: a fleet launch line)
  run env KITTY_WINDOW_ID=289 KITTY_PID="$FX_KPID" SHELL="$S/fakeshell" CC_PANE_CMD="$1" \
    ${FX_INTERACTIVE:+CC_PANE_CMD_INTERACTIVE=1} /bin/bash "$REPO/bin/cc-pane-runner" </dev/null
}
fx_close()   { run /bin/bash "$REPO/bin/cc-pane-close" "$@" </dev/null; }
fx_sweep()   { run /bin/bash "$REPO/bin/cc-husk-sweep" "$@" </dev/null; }
fx_paint()   { run /bin/bash "$REPO/bin/cc-pane-verdict" "$@" </dev/null; }
fx_watchdog() { # class cause rc → the watchdog's pane verdict for 289; fx_pvs reads the state it painted
  run /bin/bash "$REPO/hooks/lead-crash-watchdog.sh" --pane-verdict "$SID" 7000 "$1" "$2" "$3" "" "$TX" </dev/null
}
fx_watcher() { # [VAR=val …] → the real __selfclose watcher for pane 289, iTerm2 transport, runner-owned
  run env HOME="$T/wh" PATH="$T/wbin:$PATH" CC_TERM=iterm2 IT2_WRAPPER_NO_KITTY=1 CC_PANE_RUNNER_OWNS_CLOSE=289 \
    IT2_CLOSE_RC=70 HF_ALARM_LR_PAGE_BIN="$S/pager" HF_SELFCLOSE_GRACE_S=0 "$@" \
    /bin/bash "$REPO/scripts/handoff-fire.sh" __selfclose 289 TTY-A </dev/null
}
fx_tail()    { jq -r '.tail // empty' "$T/pane-exit/289.json" 2>/dev/null; }
fx_pvs()     { jq -r '.state // empty' "$T/pv/0-289.json" 2>/dev/null; }
# shellcheck disable=SC2154  # $output is bats `run`'s
fx_verdict() { printf '%s\n' "$output" | grep '^{' | jq -r --arg p "${1:-289}" 'select(.pane == $p) | .verdict' 2>/dev/null; }
fx_rows()    { find "$CC_PANE_CLOSE_QUEUE_DIR" -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' '; }
fx_alarms()  { find "$T/wh/.claude/handoff-alarms" -type f 2>/dev/null | wc -l | tr -d ' '; }
fx_no_resume_words() { # FILE… → fails on the first that says RESUME, --resume or "stopped mid-task"
  local f
  for f; do
    [ -e "$f" ] || continue
    if grep -qE 'RESUME|--resume|stopped mid-task|⛔ resume' "$f"; then echo "resume words in $f:"; cat -v "$f"; return 1; fi
  done
}
