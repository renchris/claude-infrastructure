#!/usr/bin/env bats
# scripts/devname-hazard-lint.sh — the watchdog-path ban on forms that walk /dev (incident 2026-10-25,
# DESIGN.md I4 and C8). One poisoned devfs node hung 23 `ps`, 17 `login` and every new zsh in
# ttyname → devname → lstat; the lint keeps those forms out of hooks/ and the lockwatch dirs.
#
# RED-proof: the pre-fix hooks at 660d21989 (the base this lane was cut from) are the REAL artifacts,
# and the lint goes RED on exactly their known sites; the fixed copies in this tree are clean.
# Hermetic: the lint runs from a fixture repo, so --file paths resolve against the fixture.

BASE=660d21989

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FX/scripts/lockwatch" "$FX/hooks/lib"
  cp "$REPO/scripts/devname-hazard-lint.sh" "$FX/scripts/"
  LINT=(/bin/bash "$FX/scripts/devname-hazard-lint.sh")
}

@test "selftest discriminates" {
  run "${LINT[@]}" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest: "*" pass"* ]] || false
}

@test "each banned form is flagged, with its reason" {
  cat > "$FX/hooks/bad.sh" <<'EOF'
t="$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
lcw_bounded 5 /bin/ps -t "$1" -o stat=,command= 2>/dev/null || true
x=$(ps -axM)
y=$(ps -o pid= -p 1,2)
z=$(lsof -w -a -p "$pid" -d 1 -Fn)
ls -la /dev/ttys0*
n=$(tty)
EOF
  run "${LINT[@]}" --file hooks/bad.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"hooks/bad.sh:1: ps -o tty= calls devname()"* ]] || false
  [[ "$output" == *"hooks/bad.sh:2: ps -t stats /dev/<tty>"* ]] || false
  [[ "$output" == *"hooks/bad.sh:3: ps -M forces a TT column"* ]] || false
  [[ "$output" == *"hooks/bad.sh:4: multi-pid ps -p without -x"* ]] || false
  [[ "$output" == *"hooks/bad.sh:5: lsof lstat-scans /dev"* ]] || false
  [[ "$output" == *"hooks/bad.sh:6: ls /dev walks devfs"* ]] || false
  [[ "$output" == *"hooks/bad.sh:7: tty calls ttyname(0)"* ]] || false
}

@test "strict tier: pgrep without -a and zsh are flagged in the lockwatch dirs only" {
  printf 'k=$(pgrep -x kitty)\n/bin/zsh -fc true\n' > "$FX/scripts/lockwatch/probe.sh"
  printf 'k=$(pgrep -x kitty)\n' > "$FX/hooks/ok.sh"
  run "${LINT[@]}" --file scripts/lockwatch/probe.sh --file hooks/ok.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/lockwatch/probe.sh:1: pgrep without -a"* ]] || false
  [[ "$output" == *"scripts/lockwatch/probe.sh:2: zsh runs ttyname()"* ]] || false
  [[ "$output" != *"hooks/ok.sh"* ]] || false
}

@test "the pre-fix hooks are RED at their known sites; the fixed tree is clean" {
  git -C "$REPO" cat-file -e "$BASE^{commit}" || skip "base $BASE not in this clone"
  for f in accounts-board lead-crash-watchdog teammate-auto-shutdown; do
    git -C "$REPO" show "$BASE:hooks/$f.sh" > "$FX/hooks/$f.sh"
  done
  run "${LINT[@]}" --file hooks/accounts-board.sh --file hooks/lead-crash-watchdog.sh --file hooks/teammate-auto-shutdown.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"hooks/accounts-board.sh:139: ps -o tty="* ]] || false
  [[ "$output" == *"hooks/lead-crash-watchdog.sh:1628: ps -t"* ]] || false
  [[ "$output" == *"hooks/lead-crash-watchdog.sh:2275: ps -o tty="* ]] || false
  [[ "$output" == *"hooks/teammate-auto-shutdown.sh:602: ps -o tty="* ]] || false
  for f in accounts-board lead-crash-watchdog teammate-auto-shutdown; do
    cp "$REPO/hooks/$f.sh" "$FX/hooks/$f.sh"
  done
  run "${LINT[@]}" --file hooks/accounts-board.sh --file hooks/lead-crash-watchdog.sh --file hooks/teammate-auto-shutdown.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 file(s) clean"* ]] || false
}

@test "--diff judges only ADDED lines: a legacy hazard passes, a new one is RED" {
  cd "$FX"
  git init -q . && git config user.email t@t && git config user.name t
  printf 'old=$(ps -o tty= -p 1)\n' > hooks/legacy.sh
  git add -A && git commit -qm base
  printf 'echo unrelated\n' >> hooks/legacy.sh
  git commit -qam touch
  run "${LINT[@]}" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  printf 'new=$(ps -t ttys001)\n' >> hooks/legacy.sh
  git commit -qam hazard
  run "${LINT[@]}" --diff HEAD~1..HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"hooks/legacy.sh:3: ps -t"* ]] || false
  [[ "$output" != *"hooks/legacy.sh:1:"* ]] || false
}

@test "an allow annotation and out-of-scope paths are not judged" {
  printf 'x=$(ps -o tty= -p 1)  # devname-hazard-lint:allow fixture\n' > "$FX/hooks/allowed.sh"
  mkdir -p "$FX/bin" && printf 'x=$(ps -o tty= -p 1)\n' > "$FX/bin/elsewhere.sh"
  run "${LINT[@]}" --file hooks/allowed.sh --file bin/elsewhere.sh
  [ "$status" -eq 0 ]
}
