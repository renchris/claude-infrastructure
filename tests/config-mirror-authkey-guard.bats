#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# SC2317/SC2329: bats invokes each @test body through the runner, so the linter reads them as dead
# code. File-level, because it is a property of the harness rather than of any single line.
# (NB: no comment line here may BEGIN with the linter's own name — it parses as a directive.)
#
# config-mirror.zsh — the account-pinning auth-key guard must inspect the settings.json the account
# dir ACTUALLY LOADS, not the one the mirror wishes it shared.
#
# WHY THIS SUITE EXISTS. The guard's own former wording, "the SHARED settings.json", was the whole
# bug: it greps a path, and asserted a sharing relationship it never checked. settings.json is in no
# isolate list, so the share loop tries to symlink it, finds a real file, and (outside --convert)
# leaves the fork in place — which makes the fork the steady state. Measured 2026-09-08, all four
# live account dirs hold a REAL settings.json (120/77/59/78 diff lines vs ~/.claude), none a
# symlink, so a key in any of them was invisible while the guard reported cleanly.
#
# The src case below is the POSITIVE CONTROL: without it, a fix that merely swapped $src for $dst
# would pass while silently dropping the coverage the guard already had.

setup() {
  # Hermetic $HOME: this suite drives a tool whose defaults are $HOME/.claude/... — without it a
  # leaked default reads the operator's LIVE config and the verdict depends on the fleet.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"
  D="$BATS_TEST_TMPDIR"
  KEY='  "apiKeyHelper": "/bin/echo sk-pinned",'

  # A fixture whose $dst settings.json is a REAL FORK — the live shape, not a symlink.
  # $1 = fake-HOME dir to build under; $2 = "src" or "dst" (which file carries the key).
  mk_fixture() {
    local h="$1" where="$2"
    mkdir -p "$h/.claude" "$h/.claude-next"
    printf '{}\n' > "$h/.claude/.claude.json"
    if [ "$where" = src ]; then
      printf '{\n%s\n  "x": 1\n}\n' "$KEY" > "$h/.claude/settings.json"
      printf '{\n  "x": 2\n}\n'            > "$h/.claude-next/settings.json"
    else
      printf '{\n  "x": 1\n}\n'            > "$h/.claude/settings.json"
      printf '{\n%s\n  "x": 2\n}\n' "$KEY" > "$h/.claude-next/settings.json"
    fi
    [ ! -L "$h/.claude-next/settings.json" ]   # the fixture must model a FORK, never a symlink
  }
}

@test "a key in the account dir's OWN forked settings.json is reported (the fixed hole)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mk_fixture "$D/fh-dst" dst
  export HOME="$D/fh-dst"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  # Keyed on the PATH, so a warning about $src can never satisfy this assertion.
  if ! printf '%s\n' "$output" | grep -q "\.claude-next/settings.json has an account-pinning auth key"; then
    echo "GUARD BLIND: a pinning key in the dir's own settings.json went unreported" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  # And the file really was a fork the mirror declined to replace.
  [ ! -L "$HOME/.claude-next/settings.json" ]
}

@test "POSITIVE CONTROL: a key in ~/.claude/settings.json is still reported" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mk_fixture "$D/fh-src" src
  export HOME="$D/fh-src"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  if ! printf '%s\n' "$output" | grep -q "\.claude/settings.json has an account-pinning auth key"; then
    echo "COVERAGE LOST: the original \$src arm of the guard no longer fires" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
}

@test "a clean pair warns about neither file" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mkdir -p "$D/fh-clean/.claude" "$D/fh-clean/.claude-next"
  printf '{}\n'            > "$D/fh-clean/.claude/.claude.json"
  printf '{\n  "x": 1\n}\n' > "$D/fh-clean/.claude/settings.json"
  printf '{\n  "x": 2\n}\n' > "$D/fh-clean/.claude-next/settings.json"
  export HOME="$D/fh-clean"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  n="$(printf '%s\n' "$output" | grep -c "account-pinning auth key" || true)"
  [ "${n:-0}" -eq 0 ] || { echo "FALSE POSITIVE: warned over a clean pair" >&2; return 1; }
}

@test "NON-VACUITY: restore the src-only grep and the same fixture goes silent" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # Replays the PRE-FIX subject: the mutant narrows the loop back to "$src/settings.json" alone.
  # If the first test still passes against this, it is keyed on something other than the fix.
  local mut="$D/mirror-authkey-mutant.zsh"
  # python3, not sed: the anchor line carries "$" and quotes that collide with sed's parsing, and a
  # mutant built by a quoting accident is an inert control.
  python3 -c '
import sys
src, dst = sys.argv[1], sys.argv[2]
out, hit = [], 0
for line in open(src):
    if line.strip().startswith("for _cm_f in "):
        out.append("  for _cm_f in \"$src/settings.json\"; do\n"); hit += 1
    else:
        out.append(line)
open(dst, "w").writelines(out)
sys.exit(0 if hit == 1 else 1)
' "$MIRROR" "$mut" || { echo "MUTANT NOT APPLIED — anchor did not match exactly once; control is inert" >&2; return 1; }
  grep -q 'for _cm_f in "\$src/settings.json"; do' "$mut" || {
    echo "MUTANT NOT APPLIED — narrowed loop absent, so this control is inert" >&2; return 1; }
  mk_fixture "$D/fh-mut" dst
  export HOME="$D/fh-mut"
  run zsh -fc "source '$mut'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  n_mut="$(printf '%s\n' "$output" | grep -c "account-pinning auth key" || true)"
  [ "${n_mut:-0}" -eq 0 ] || {
    echo "MUTANT STILL REPORTS — the first assertion is not keyed on the fix" >&2; return 1; }
  return 0
}
