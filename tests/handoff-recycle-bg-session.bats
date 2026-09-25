#!/usr/bin/env bats
# --recycle REFUSES a BACKGROUNDED session (scripts/handoff-fire.sh hf_bg_hosted / hf_bg_recycle_refusal).
#
# Claude Code 2.1.280 backgrounds a session into its daemon; the pane's TUI becomes a viewer, and /exit
# there only DETACHES it — the session keeps running and the pane drops to the agents view, not a shell
# (docs/research/bg-session-semantics-2026-09-25.md § Q3). Until hooks/session-register.sh learned to
# restore a bg session's address, --recycle refused on the missing address and this was unreachable;
# now the address resolves, so the recycle must refuse on the true reason instead of typing /exit into
# a viewer and relaunching a second live copy. --dry-run stops before every side effect.
#
# Harness shape copied from tests/handoff-selfclose-kitty-identity.bats § 3 (hermetic $HOME, stubbed
# it2 + cc-in-kitty, a nonexistent kitty binary, $WORK outside any git repo).

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_UNDER_TEST:-$REPO/scripts/handoff-fire.sh}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry" "$HOME/.claude/cc-roles" "$HOME/.claude/cc-fired"
  export CC_FIRED_DIR="$HOME/.claude/cc-fired"
  export CC_TERM_KITTY="$HOME/.claude/bin/no-such-kitty"
  # Seams the hermeticity lint names for --recycle; ABSENT paths, so the sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  printf '#!/bin/bash\nexit "${FAKE_CIK_RC:-1}"\n' > "$HOME/.claude/bin/cc-in-kitty"
  chmod +x "$HOME/.claude/bin/cc-in-kitty"
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  if ( cd "$WORK" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    echo "FIXTURE BROKEN: \$WORK is inside a git repo" >&2; return 1
  fi
  PF="$BATS_TEST_TMPDIR/prompt.txt"; printf 'probe\n' > "$PF"
}

rcy() { # $1 = CLAUDE_CODE_SESSION_KIND ("" to unset) — the address is the one session-register restores
  run env -u ITERM_SESSION_ID -u CC_TERM -u KITTY_WINDOW_ID -u CLAUDE_CODE_SESSION_KIND \
      CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-quaternary" FAKE_CIK_RC=0 \
      KITTY_WINDOW_ID=405 ITERM_SESSION_ID=w0t0p0:405 ${1:+CLAUDE_CODE_SESSION_KIND=$1} \
      /bin/bash -c 'cd "$1" || exit 99; exec /bin/bash "$2" --recycle --prompt-file "$3" --dry-run' \
      _ "$WORK" "$HF" "$PF"
}

@test "--recycle in a backgrounded session REFUSES, names why, and types nothing" {
  rcy bg
  [ "$status" -eq 2 ] || { echo "rc=$status"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -F 'is BACKGROUNDED' >/dev/null || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -F 'Nothing was typed' >/dev/null || { echo "$output"; false; }
}

@test "control: the SAME pane and address without the bg marker still recycles (dry-run resolves 405)" {
  rcy ""
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -F 'recycle — this pane: 405' >/dev/null || { echo "$output"; false; }
}

# ── the ANCESTRY oracle, for the remote form (lr-handoff --in-place names another session's pane) ──
# A remote recycle cannot read the target's environment, so it asks the process table: is an ANCESTOR
# of the row's pid `claude --bg-pty-host …`? Table shape measured on the incident box.
_bg_harness() { # $1 = pid → rc of hf_bg_hosted
  local stub="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stub"
  cat > "$BATS_TEST_TMPDIR/pstable" <<'TABLE'
92384|92118|/x/claude.exe --session-id bb4e00d0 --fork-session --resume /p/e44c8e8c.jsonl
92118|91697|/x/claude.exe --bg-pty-host /tmp/cc-daemon-501/136fa815/pty/bb4e00d0.sock 30 46 -- /x/claude.exe
91697|76287|/x/claude.exe daemon run --origin transient
76287|76180|/x/claude --permission-mode auto --resume e44c8e8c
76180|1|bash /x/cc-close-attrib /x/claude
7001|7000|/x/claude --permission-mode auto brief text mentioning --bg-pty-host as prose
7000|1|/bin/zsh
TABLE
  cat > "$stub/ps" <<'PS'
#!/usr/bin/env bash
field=""; pid=""
while [ $# -gt 0 ]; do
  case "$1" in -o) field="$2"; shift 2 ;; -p) pid="$2"; shift 2 ;; *) shift ;; esac
done
row="$(awk -F'|' -v p="$pid" '$1 == p { print; exit }' "$PSTABLE")"
[ -n "$row" ] || exit 1
case "$field" in
  ppid=) printf '%s\n' "$(printf '%s' "$row" | cut -d'|' -f2)" ;;
  args=) printf '%s\n' "$(printf '%s' "$row" | cut -d'|' -f3)" ;;
  *) echo "ps stub: unhandled -o '$field'" >&2; exit 64 ;;
esac
PS
  chmod +x "$stub/ps"
  export PSTABLE="$BATS_TEST_TMPDIR/pstable"
  PATH="$stub:$PATH"
  sed -n '/^hf_bg_hosted() {/,/^}/p' "$HF" > "$BATS_TEST_TMPDIR/subject.sh"
  [ -s "$BATS_TEST_TMPDIR/subject.sh" ] || { echo "hf_bg_hosted not found in $HF"; return 70; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/subject.sh"
  hf_bg_hosted "$1"
}
_bg_harness_extra() { # the same table plus $BATS_TEST_TMPDIR/pstable.extra
  _bg_harness 0 >/dev/null 2>&1 || true
  cat "$BATS_TEST_TMPDIR/pstable.extra" >> "$BATS_TEST_TMPDIR/pstable"
  hf_bg_hosted "$1"
}

@test "hf_bg_hosted: the daemon's worker is bg-hosted (its pty-host ancestor is argv[1] --bg-pty-host)" {
  run _bg_harness 92384
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
}

@test "hf_bg_hosted: the pane's own client is NOT bg-hosted (the daemon is its child, not its parent)" {
  run _bg_harness 76287
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
}

@test "hf_bg_hosted: the walk stops at the PARENT — a pid three hops below a pty-host is not convicted" {
  # 92384's child would be the worker's own tool shell; a remote row never names one, and a longer
  # walk is what would climb from a test fixture's pid into the runner's own bg ancestry.
  printf '9500|9400|/bin/zsh -c probe\n9400|92384|/bin/zsh\n' >> "$BATS_TEST_TMPDIR/pstable.extra"
  run _bg_harness_extra 9500
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
}

@test "hf_bg_hosted: a brief that merely MENTIONS --bg-pty-host does not convict (argv[1] only)" {
  run _bg_harness 7001
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
}

# ── the RUNNER must not inherit the mark: bin/cc-bats clears it before any exec path ─────────────
# Otherwise every --recycle case in every suite refuses when the gate runs inside a bg session.
_ccbats() { # $@ = extra env → prints what the stubbed real bats saw
  local stub="$BATS_TEST_TMPDIR/realbats"
  printf '#!/bin/bash\necho "KIND=${CLAUDE_CODE_SESSION_KIND:-unset}"\n' > "$stub"; chmod 755 "$stub"
  env -u CC_BATS_ACTIVE CC_BATS_REAL="$stub" CC_BATS_MAX_ROOTS=0 CC_BATS_ROOTS_DIR="$BATS_TEST_TMPDIR/roots" \
      CLAUDE_CODE_SESSION_KIND=bg "$@" /bin/bash "$REPO/bin/cc-bats" tests/none.bats
}

@test "cc-bats: a suite launched from a backgrounded session does not inherit CLAUDE_CODE_SESSION_KIND" {
  run _ccbats
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$(printf '%s\n' "$output" | tail -1)" = "KIND=unset" ] || { echo "$output"; false; }
}

@test "cc-bats: the mark is cleared on the kill-switch path too (CC_BATS_QOS=off)" {
  run _ccbats CC_BATS_QOS=off
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$(printf '%s\n' "$output" | tail -1)" = "KIND=unset" ] || { echo "$output"; false; }
}
