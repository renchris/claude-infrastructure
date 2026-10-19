#!/usr/bin/env bats
# lib/cc-say.sh (+ its twin lib/cc_say.py) — the one renderer for pane banners (lr-wake 2026-10-18,
# RC8). Every case runs the helper under /bin/bash (3.2, what launchd runs) AND zsh (what
# lib/config-mirror.zsh sources it from), because it is written in their common subset and a
# construct one of them reads differently is exactly the break this suite exists to catch.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SAY="$REPO/lib/cc-say.sh"
  export CC_SAY_LOG="$BATS_TEST_TMPDIR/pane-say.jsonl"
  export CC_SAY_TOOL=cc-say-bats
  unset NO_COLOR CC_SAY_VERBOSE CC_SAY_DETAIL CC_SAY_TARGET CC_SAY_COLOR COLUMNS CC_SAY_WIDTH
  LC_ALL=en_US.UTF-8; export LC_ALL
}

# say_in <shell> <script…> — source the helper in that shell, run the script, stderr folded in.
say_in() {
  local sh="$1"; shift
  case "$sh" in
    bash) /bin/bash -c ". '$SAY'; $*" 2>&1 ;;
    zsh)  zsh -f -c ". '$SAY'; $*" 2>&1 ;;
  esac
}

# Display cells of a string, measured independently of the helper (ANSI stripped first).
cells() { python3 -c 'import re,sys,unicodedata as u
for l in sys.stdin.read().split("\n"):
    l=re.sub(r"\x1b\[[0-9;]*m","",l)
    if l: print(sum(2 if u.east_asian_width(c) in "WF" else 1 for c in l if c!="️"))'; }

@test "bash 3.2 is what /bin/bash is (the launchd interpreter this helper must survive)" {
  run /bin/bash -c 'echo "${BASH_VERSINFO[0]}"'
  [ "$output" = 3 ] || skip "/bin/bash is not 3.2 on this host"
}

@test "one line per call, under bash 3.2 and zsh, at 37, 45 and 57 columns" {
  for sh in bash zsh; do
    for w in 37 45 57; do
      out="$(say_in "$sh" "CC_SAY_WIDTH=$w cc_say run 'resuming 2e9ed9f2' 'next3 · checks ok'")"
      [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || { echo "$sh@$w: $out"; false; }
      out="$(say_in "$sh" "CC_SAY_WIDTH=$w cc_say fail 'not resumed' 'next3 full' 'cc-lr recover 2e9e'")"
      [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || { echo "$sh@$w: $out"; false; }
    done
  done
}

@test "every row fits its width at 37, 45 and 57 columns (57 is capped at 56), colour on or off" {
  for sh in bash zsh; do
    for w in 37 45 57; do
      for c in 0 1; do
        out="$(say_in "$sh" "CC_SAY_COLOR=$c CC_SAY_WIDTH=$w cc_say fail '2e9ed9f2 not resumed' 'next3 full 9/8 because the active ceiling is eight and nothing retries' 'cc-lr recover 2e9ed9f2'")"
        max=$w; [ "$max" -gt 56 ] && max=56
        while read -r n; do [ "$n" -le "$max" ] || { echo "$sh@$w c=$c: $n cells > $max"; echo "$out"; false; }; done < <(printf '%s\n' "$out" | cells)
      done
    done
  done
}

@test "never SGR-2: zero \\e[2m across every kind, target and shell" {
  for sh in bash zsh; do
    for k in ok wait run fail warn info judge foot; do
      for t in tty sm; do
        out="$(say_in "$sh" "CC_SAY_COLOR=1 CC_SAY_TARGET=$t CC_SAY_VERBOSE=1 CC_SAY_DETAIL='why it happened' cc_say $k 'verdict here' 'a fact' 'cc-x y'")"
        [ "$(printf '%s' "$out" | grep -c $'\e\\[2m')" -eq 0 ] || { echo "$sh $k $t"; false; }
        printf '%s' "$out" | grep -q $'\e\\[38;2;' || { echo "no truecolor: $sh $k $t"; false; }
      done
    done
  done
}

@test "the ACTION bytes are left plain: nothing but the command follows the ▶ and its reset" {
  for sh in bash zsh; do
    out="$(say_in "$sh" "CC_SAY_COLOR=1 CC_SAY_WIDTH=57 cc_say fail 'not resumed' 'next3 full' 'cc-lr recover 2e9ed9f2'")"
    tail="${out##*▶}"
    tail="${tail#$'\e[39m'}"
    [ "$tail" = " cc-lr recover 2e9ed9f2" ] || { printf '%q\n' "$out"; false; }
  done
}

@test "a command too long to share the row takes its OWN row, uncut" {
  long='cc-something --with a-very-long-argument-list here'
  for sh in bash zsh; do
    out="$(say_in "$sh" "CC_SAY_WIDTH=37 cc_say warn 'x went wrong' '' '$long'")"
    [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  ▶ $long" ] || { echo "$out"; false; }
    [ "$(printf '%s\n' "$out" | grep -c .)" -eq 2 ]
  done
}

@test "the verdict is never cut to make room for the action — the action moves instead" {
  out="$(say_in bash "CC_SAY_WIDTH=45 cc_say fail '2e9ed9f2 not resumed' 'next3 full' 'cc-lr recover 2e9ed9f2'")"
  printf '%s\n' "$out" | head -1 | grep -q '^✗ 2e9ed9f2 not resumed' || { echo "$out"; false; }
}

@test "detail goes to the log only; CC_SAY_VERBOSE=1 shows it as an indented row" {
  for sh in bash zsh; do
    : > "$CC_SAY_LOG"
    out="$(say_in "$sh" "CC_SAY_DETAIL='full launch line /tmp/x' cc_say run 'resuming 2e9ed9f2'")"
    [ "$out" = "⟳ resuming 2e9ed9f2" ] || { echo "$out"; false; }
    jq -e 'select(.detail=="full launch line /tmp/x" and .kind=="run" and .tool=="cc-say-bats")' "$CC_SAY_LOG" >/dev/null
    out="$(say_in "$sh" "CC_SAY_VERBOSE=1 CC_SAY_DETAIL='full launch line /tmp/x' cc_say run 'resuming 2e9ed9f2'")"
    [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  full launch line /tmp/x" ] || { echo "$out"; false; }
    out="$(say_in "$sh" "cc_say_detail 'tombstone check' 'this IS the transplant target'")"
    [ -z "$out" ]
    jq -e 'select(.kind=="detail" and .verdict=="tombstone check")' "$CC_SAY_LOG" >/dev/null
  done
}

@test "the log record is valid JSON for quotes, backslashes, tabs and newlines in both shells" {
  # the values travel as positional arguments, so no layer of test quoting can alter them
  v='a "q" \ b'; d=$'two\nlines\tand tab'
  for sh in /bin/bash zsh; do
    : > "$CC_SAY_LOG"
    case "$sh" in
      zsh) zsh -f -c '. "$1"; cc_say_detail "$2" "$3"' _ "$SAY" "$v" "$d" ;;
      *)   /bin/bash -c '. "$1"; cc_say_detail "$2" "$3"' _ "$SAY" "$v" "$d" ;;
    esac
    run jq -r '.verdict + "|" + .detail' "$CC_SAY_LOG"
    [ "$status" -eq 0 ] || { cat "$CC_SAY_LOG"; false; }
    [ "$output" = "$v|$d" ] || { echo "$sh: $output"; false; }
  done
}

@test "CC_SAY_TARGET=sm (a systemMessage) never emits \\e[0m and re-asserts the harness gray" {
  for sh in bash zsh; do
    out="$(say_in "$sh" "CC_SAY_TARGET=sm cc_say warn 'class-B overdue' 'nothing fired' 'cc-decide list --open'")"
    ! printf '%s' "$out" | grep -q $'\e\\[0m' || false
    printf '%s' "$out" | grep -q $'\e\\[38;2;153;153;153m' || { printf '%q\n' "$out"; false; }
  done
}

@test "NO_COLOR and a non-tty fd render plain text" {
  out="$(say_in bash "NO_COLOR=1 CC_SAY_COLOR=1 cc_say ok 'landed' 'abc1234'")"
  [ "$out" = "✓ landed · abc1234" ]
  out="$(say_in zsh "cc_say ok 'landed' 'abc1234'")"
  [ "$out" = "✓ landed · abc1234" ]
}

@test "cc_say_fit keeps the command whole and cuts the prose; cc_say_width caps at 56" {
  for sh in bash zsh; do
    # the prose keeps ≥ 2/3 of itself: one row, cut at a whole fact, the command beside it
    out="$(say_in "$sh" "CC_SAY_WIDTH=52 cc_say_fit ' ◆ pile: 3 run · 231 call · 1156 esc · 12 queued' 'cc-blockers'")"
    [ "$out" = " ◆ pile: 3 run · 231 call · 1156 esc…   cc-blockers" ] || { echo "$sh: $out"; false; }
    # it would not: the command takes its own row, whole, and every row fits
    out="$(say_in "$sh" "CC_SAY_WIDTH=52 cc_say_fit ' ◆ research alpha: 2 pending concern(s) · 1 priced option(s)' 'cc-research verdict alpha'")"
    [ "$(printf '%s\n' "$out" | sed -n 2p)" = "   cc-research verdict alpha" ] || { echo "$sh: $out"; false; }
    while read -r n; do [ "$n" -le 52 ] || { echo "$sh: $out"; false; }; done < <(printf '%s\n' "$out" | cells)
    [ "$(say_in "$sh" 'COLUMNS=200 cc_say_width')" = 56 ]
    [ "$(say_in "$sh" 'CC_SAY_WIDTH=37 cc_say_width')" = 37 ]
  done
}

@test "python twin: same plain line as the shell helper, same log contract" {
  for args in "fail|2e9ed9f2 not resumed|next3 full 9/8 because the ceiling is eight|cc-lr recover 2e9ed9f2" \
              "run|resuming 2e9ed9f2|checks ok|" "warn|x went wrong||cc-something --with a-very-long-argument-list here"; do
    IFS='|' read -r k v f a <<< "$args"
    for w in 37 57; do
      sh_out="$(CC_SAY_WIDTH=$w /bin/bash -c ". '$SAY'; cc_say \"\$@\"" _ "$k" "$v" "$f" "$a" 2>&1)"
      py_out="$(CC_SAY_WIDTH=$w python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import cc_say; cc_say.say(*sys.argv[2:6])' \
                "$REPO/lib" "$k" "$v" "$f" "$a" 2>&1)"
      [ "$sh_out" = "$py_out" ] || { echo "w=$w"; echo "sh: $sh_out"; echo "py: $py_out"; false; }
    done
  done
  jq -e 'select(.verdict=="resuming 2e9ed9f2" and .kind=="run")' "$CC_SAY_LOG" >/dev/null
}
