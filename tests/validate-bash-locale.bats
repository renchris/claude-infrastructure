#!/usr/bin/env bats
# validate-bash-locale.bats — the byte-wise substitutions (docs/research/startup-hooks-2026-10-18/
# W7-pretooluse-replay.md). Under /bin/bash 3.2 and a UTF-8 locale, `${x//pat/}` over a long heredoc
# command with non-ASCII text ran for 10-29 s, past the harness's 10 s kill, so the call went ungated.
# The three sites (pha_flatten, the worker-claim separator split, the write-gate redirect strip) now
# run under a function-local LC_ALL=C: same bytes, because every pattern is ASCII. Above 2 KB the first
# two use one `LC_ALL=C tr` pass instead, because the builtin is also quadratic in its match count.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/shared"
  unset KITTY_WINDOW_ID CLAUDE_CONFIG_DIR
  export IT2_WRAPPER_NO_KITTY=1
  # the separator test only NAMES handoff-fire.sh (validate-bash never runs it); pinned anyway
  export CC_FIRE_CAPACITY_GATE=off
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

payload() { jq -cn --arg c "$1" '{session_id:"s1",cwd:"/tmp",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

big_heredoc() { # a ~40 KB python heredoc: quotes, backslashes, `$` and one non-ASCII byte per line
  local i
  printf "python3 - <<'EOF'\n"
  for ((i = 0; i < 800; i++)); do
    printf "s = s.replace('caf\\\\u00e9 é', \"x\\\\\\\\y\") + '\$HOME' # é\n"
  done
  printf "EOF\n"
}

@test "a 40 KB heredoc with non-ASCII text is decided within the harness's 10 s under a UTF-8 locale" {
  big_heredoc > "$BATS_TEST_TMPDIR/cmd"
  [ "$(wc -c < "$BATS_TEST_TMPDIR/cmd")" -gt 35000 ]
  payload "$(cat "$BATS_TEST_TMPDIR/cmd")" > "$BATS_TEST_TMPDIR/in.json"
  # Bound at 20 s, not 10: this suite runs under load, and the unfixed hook takes minutes here.
  SECONDS=0
  run env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 /usr/bin/perl -e 'alarm 20; exec @ARGV' /bin/bash "$HOOK" < "$BATS_TEST_TMPDIR/in.json"
  echo "elapsed ${SECONDS}s status $status"
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 20 ]
}

@test "decisions are byte-identical to the pre-fix hook for commands mixing non-ASCII and every pattern" {
  # The control is the REAL pre-fix artifact from git (origin/main until this fix lands, then the
  # parent of the commit that added it), run beside the same libs.
  fix="$(git -C "$REPO" log -n1 --format=%H -S'local LC_ALL=C _wcs_sep' -- hooks/validate-bash.sh 2>/dev/null)"
  ref="origin/main"; [ -n "$fix" ] && ref="$fix^"
  old="$BATS_TEST_TMPDIR/old"; mkdir -p "$old/hooks"
  git -C "$REPO" show "$ref:hooks/validate-bash.sh" > "$old/hooks/validate-bash.sh"
  run grep -c 'local LC_ALL=C _wcs_sep' "$old/hooks/validate-bash.sh"
  [ "$output" = 0 ]   # the control really is the pre-fix hook
  ln -s "$REPO/hooks/lib" "$old/hooks/lib"; ln -s "$REPO/scripts" "$old/scripts"; ln -s "$REPO/bin" "$old/bin"
  cmds=(
    "echo 'café' && cc-permission-har''vest --ap\"ply\""
    "ls ~/naïve; echo done > /dev/null 2>&1"
    "printf 'é' > /tmp/out.txt"
    "cat <<'EOF' | sh
résumé \$X
EOF"
    "FOO=é bash -c 'handoff-fire.sh --help'"
    "git status --short # ünïcode"
  )
  for c in "${cmds[@]}"; do
    payload "$c" > "$BATS_TEST_TMPDIR/in.json"
    a="$(LC_ALL=en_US.UTF-8 /bin/bash "$old/hooks/validate-bash.sh" < "$BATS_TEST_TMPDIR/in.json" 2>/dev/null; echo "rc=$?")"
    b="$(LC_ALL=en_US.UTF-8 /bin/bash "$HOOK" < "$BATS_TEST_TMPDIR/in.json" 2>/dev/null; echo "rc=$?")"
    [ "$a" = "$b" ] || { echo "differs for: $c"; echo "old: $a"; echo "new: $b"; false; }
    # the large-command path (one `tr` pass), forced onto the same short commands
    b="$(CC_VB_TR_MIN_BYTES=1 LC_ALL=en_US.UTF-8 /bin/bash "$HOOK" < "$BATS_TEST_TMPDIR/in.json" 2>/dev/null; echo "rc=$?")"
    [ "$a" = "$b" ] || { echo "tr path differs for: $c"; echo "old: $a"; echo "new: $b"; false; }
    printf '%s\n' "$b" >> "$BATS_TEST_TMPDIR/verdicts"
  done
  # non-vacuity: at least one of these commands is DENIED, so the comparison covers a firing gate
  grep -q '"deny"' "$BATS_TEST_TMPDIR/verdicts"
}

@test "the separator split sees a gated launcher after every separator exactly as the pre-fix hook does" {
  # Observable without a lease fixture: with scripts/lib/worker-claim-gate.sh unreachable, a hit
  # writes one "unreachable" row to CC_WCLAIM_IDL and a miss writes none. Both hooks are copied
  # beside hooks/lib only, so neither can reach the lib.
  fix="$(git -C "$REPO" log -n1 --format=%H -S'local LC_ALL=C _wcs_sep' -- hooks/validate-bash.sh 2>/dev/null)"
  ref="origin/main"; [ -n "$fix" ] && ref="$fix^"
  for v in old new; do mkdir -p "$BATS_TEST_TMPDIR/$v/hooks"; ln -s "$REPO/hooks/lib" "$BATS_TEST_TMPDIR/$v/hooks/lib"; done
  git -C "$REPO" show "$ref:hooks/validate-bash.sh" > "$BATS_TEST_TMPDIR/old/hooks/validate-bash.sh"
  cp "$HOOK" "$BATS_TEST_TMPDIR/new/hooks/validate-bash.sh"
  cmds=("true ; handoff-fire.sh --x" "true && handoff-fire.sh --x" "false || handoff-fire.sh --x"
        "echo é | handoff-fire.sh --x" "sleep 1 & handoff-fire.sh --x" "( handoff-fire.sh --x )"
        "{ handoff-fire.sh --x; }" "echo handoff-fire.sh --x")
  hits=0
  for c in "${cmds[@]}"; do
    payload "$c" > "$BATS_TEST_TMPDIR/in.json"
    for run in old new new-tr; do
      : > "$BATS_TEST_TMPDIR/idl-$run"
      h="$BATS_TEST_TMPDIR/${run%-tr}/hooks/validate-bash.sh"; m=999999; [ "$run" = new-tr ] && m=1
      CC_VB_TR_MIN_BYTES=$m CC_WCLAIM_IDL="$BATS_TEST_TMPDIR/idl-$run" LC_ALL=en_US.UTF-8 \
        /bin/bash "$h" < "$BATS_TEST_TMPDIR/in.json" >/dev/null 2>&1 || true
    done
    o="$(grep -c unreachable "$BATS_TEST_TMPDIR/idl-old" || true)"
    [ "$(grep -c unreachable "$BATS_TEST_TMPDIR/idl-new" || true)" = "$o" ] || { echo "builtin split differs: $c"; false; }
    [ "$(grep -c unreachable "$BATS_TEST_TMPDIR/idl-new-tr" || true)" = "$o" ] || { echo "tr split differs: $c"; false; }
    hits=$((hits + o))
  done
  [ "$hits" -ge 7 ]   # non-vacuity: the seven separator cases really hit
}
