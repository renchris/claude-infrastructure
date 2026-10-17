#!/usr/bin/env bats
# qos-rewrite-git-grep.bats — differential lab for hooks/qos-rewrite.sh transform (d), which reads a
# `git grep -E` (or flagless BRE) pattern through the PCRE engine by swapping one token.
#
# The claim under test: within the transform's subset, the rewritten command selects the SAME lines
# with the SAME exit code on text files, and on binary files PCRE reports a superset of what the ERE
# path reported (the platform regex stops at a NUL; PCRE does not).
#
# Corpus: every `git grep` command in ~/.claude/logs/bash-execution.log* from the last 30 days that
# the SHIPPED hook rewrites (classified by running it, not by restating its rule), plus hand cases.
# Each case is replayed in a throwaway repo — real text files copied from this checkout, edge-case
# text (non-ASCII case folds, Latin-1 bytes, CRLF), and binary files — with its original flags and
# pattern against the rewritten flags and pattern. Pathspecs, `-C` and timeouts are dropped: they
# select files, which the lab fixes.

REAL_HOME="${HOME:-}"

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO
  LAB="$BATS_FILE_TMPDIR/lab"
  export LAB
  mkdir -p "$LAB/text" "$LAB/bin"
  local f
  for f in "$REPO"/hooks/*.sh "$REPO"/hooks/lib/*.sh "$REPO"/config/*.patterns; do
    [ -f "$f" ] && cp "$f" "$LAB/text/"
  done
  printf 'K: \342\204\252elvin sign\nS: \305\277hort long s\ncafe: caf\351 latin1\nplain kelvin ks\r\ncrlf line\r\n\ttabbed foo|bar\n' \
    > "$LAB/text/edges.txt"
  head -c 4096 /dev/urandom > "$LAB/bin/random1.bin"
  head -c 4096 /dev/urandom > "$LAB/bin/random2.bin"
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001' > "$LAB/bin/tiny.png"
  printf 'header\000table_match foo bar git grep -E\nemit CMD exit\000tail\n' > "$LAB/bin/nul-text.bin"
  ( cd "$LAB" && git init -q . && git add -A \
      && git -c user.email=t@e -c user.name=t commit -qm lab ) >/dev/null 2>&1

  # Corpus: leading `git grep` commands from the last 30 days of the execution log.
  local logdir="${QOS_GG_LOGDIR:-$REAL_HOME/.claude/logs}" cands="$BATS_FILE_TMPDIR/cands.txt"
  : > "$cands"
  if [ -d "$logdir" ]; then
    find "$logdir" -maxdepth 1 -name 'bash-execution.log*' -mtime -31 2>/dev/null | while read -r f; do
      case "$f" in *.gz) gzip -dc "$f" 2>/dev/null ;; *) cat "$f" ;; esac
    done | sed -E 's/^\[[^]]*\] \[[^]]*\] //; s/ \| Exit: [0-9]+$//' \
      | grep -E '^((g?timeout) [0-9]+[smhd]? )?git (-C [^ ]+ )?grep ' | LC_ALL=C sort -u > "$cands" || true
  fi
  printf '%s\n' "$(grep -c . "$cands" || true)" > "$BATS_FILE_TMPDIR/ncands"
  hand_cases >> "$cands"

  # Classify by running the shipped hook; keep the ones it rewrites.
  : > "$BATS_FILE_TMPDIR/orig.txt"; : > "$BATS_FILE_TMPDIR/new.txt"
  local c out
  while IFS= read -r c; do
    out=$(hook_out "$c")
    [ -n "$out" ] || continue
    printf '%s\n' "$c" >> "$BATS_FILE_TMPDIR/orig.txt"
    printf '%s\n' "$out" >> "$BATS_FILE_TMPDIR/new.txt"
  done < "$cands"
}

# Hand cases: always in the corpus, so the lab never depends on the log alone.
hand_cases() {
  cat <<'EOF'
git grep -n -E 'table_match|emit' -- hooks/
git grep -nE 'CC_QOS_[A-Z]+' hooks/qos-rewrite.sh
git grep -l -E 'set -uo pipefail'
git grep -c -E '^#!/bin/bash'
git grep -n -i -E 'kelvin|elvin'
git grep -n -i -E 'k'
git grep -n -i 's'
git grep -n 'foo.*bar'
git grep -n 'caf.'
git grep -n -E 'caf.'
git grep -n -E '[^a-z]elvin'
git grep -n -E 'x(a|b)*y'
git grep -n -E 'a+b?c*'
git grep -n -E '^(emit|exit) '
git grep -n -E 'exit 0$'
git grep -n '^exit 0$'
git grep -n -E '[]a-z]+'
git grep -n -E '[^]a-z]x'
git grep -h -I -E 'grep -[qE]+'
git grep -q -E 'definitely-not-present-zz'
git grep -n -e 'tabbed foo'
git grep -A2 -n -E 'TRANSFORM \(a\)'
git grep -n -E 'git grep -E' | head -3
git grep --count -E 'table|match'
gtimeout 30 git grep -n -E 'readlink'
git -C /tmp grep -n -E 'readlink'
EOF
}

hook_out() { # <command> → the rewritten command, or nothing
  jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | HOME="$BATS_FILE_TMPDIR/home" CC_QOS_CC_BATS="" /bin/bash "$REPO/hooks/qos-rewrite.sh" \
    | jq -r '.hookSpecificOutput.updatedInput.command // empty'
}

# gg_split <command> → FLAGS (words between `grep ` and the pattern) and PAT (the first '…' token).
gg_split() {
  local pre="${1%%\'*}" rest="${1#*\'}"
  PAT="${rest%%\'*}"
  FLAGS="${pre#* grep }"
}

@test "corpus: text lines and exit codes identical, binary lines a superset" {
  local n i=0 fail=0 orig new fo fn p rco rcn
  n=$(grep -c . "$BATS_FILE_TMPDIR/orig.txt" || true)
  echo "corpus: $(cat "$BATS_FILE_TMPDIR/ncands") log candidates; $n rewritten cases (with hand cases)" >&3
  [ "$n" -ge 15 ]
  local seen="$BATS_FILE_TMPDIR/seen"; : > "$seen"
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1))
    orig=$(sed -n "${i}p" "$BATS_FILE_TMPDIR/orig.txt"); new=$(sed -n "${i}p" "$BATS_FILE_TMPDIR/new.txt")
    gg_split "$orig"; fo="$FLAGS"; p="$PAT"
    gg_split "$new"; fn="$FLAGS"
    [ "$PAT" = "$p" ] || { echo "pattern moved: $orig → $new"; fail=1; continue; }
    if grep -qxF -- "$fo	$p" "$seen"; then continue; fi
    printf '%s\t%s\n' "$fo" "$p" >> "$seen"
    rco=0; rcn=0
    # shellcheck disable=SC2086  # FLAGS are plain option words, split on purpose
    ( cd "$LAB" && git grep $fo "$p" -- text/ ) > "$BATS_TEST_TMPDIR/t.o" 2>&1 || rco=$?
    # shellcheck disable=SC2086
    ( cd "$LAB" && git grep $fn "$p" -- text/ ) > "$BATS_TEST_TMPDIR/t.n" 2>&1 || rcn=$?
    if [ "$rco" != "$rcn" ] || ! cmp -s "$BATS_TEST_TMPDIR/t.o" "$BATS_TEST_TMPDIR/t.n"; then
      echo "TEXT DIVERGES ($rco/$rcn): $orig"; diff "$BATS_TEST_TMPDIR/t.o" "$BATS_TEST_TMPDIR/t.n" | head -5
      fail=1
    fi
    rco=0; rcn=0
    # shellcheck disable=SC2086
    ( cd "$LAB" && git grep $fo "$p" -- bin/ ) 2>&1 | LC_ALL=C sort > "$BATS_TEST_TMPDIR/b.o" || true
    # shellcheck disable=SC2086
    ( cd "$LAB" && git grep $fn "$p" -- bin/ ) 2>&1 | LC_ALL=C sort > "$BATS_TEST_TMPDIR/b.n" || true
    case " $fo " in
      *" --count "*|*" -"[A-Za-z]*c*) ;;          # counts: superset does not apply line-wise
      *) if [ -n "$(LC_ALL=C comm -23 "$BATS_TEST_TMPDIR/b.o" "$BATS_TEST_TMPDIR/b.n")" ]; then
           echo "BINARY NOT A SUPERSET: $orig"; LC_ALL=C comm -23 "$BATS_TEST_TMPDIR/b.o" "$BATS_TEST_TMPDIR/b.n" | head -3
           fail=1
         fi ;;
    esac
  done
  echo "distinct flag+pattern replays: $(grep -c . "$seen")" >&3
  [ "$fail" -eq 0 ]
}

@test "a binary file the ERE path under-reports is found through PCRE" {
  local o n
  o=$(cd "$LAB" && git grep -l -E 'emit CMD' -- bin/ || true)
  n=$(cd "$LAB" && git grep -l -P 'emit CMD' -- bin/ || true)
  echo "E=[$o] P=[$n]"
  [ "$n" = "bin/nul-text.bin" ]
  [ -z "$o" ] || [ "$o" = "$n" ]
}

@test "outside the subset: no rewrite" {
  local c
  for c in "git grep -o -E 'x'" "git grep -F 'x'" "git grep -P 'x'" "git grep --column -E 'x'" \
           "git grep -a -E 'x'" "git grep -E 'a\\d'" "git grep -E 'a{2}'" "git grep -E '[[:alpha:]]'" \
           "git grep 'a+b'" "git grep -E \"x\"" "git grep -w -E 'x'" "git grep -v -E 'x'" \
           "git grep -E '(?:x)'" "git grep -E 'a**'" "git grep -E '()'" "git grep -E 'a|'" \
           "git grep -n 'a^b'" "git grep -E '[z-a]'" "git grep -n -e 'a' -e 'b'" \
           "git grep --extended-regexp 'x'" "git grep -nE -- 'x'" "git grep -E 'caf"$'\351'"'" \
           "FOO=1 git grep -E 'x'" "git grep -L -E 'x'" "git grep --color=always -E 'x'"; do
    [ -z "$(hook_out "$c")" ] || { echo "rewritten: $c → $(hook_out "$c")"; return 1; }
  done
}

@test "a pipeline tail is byte-identical after the rewrite" {
  # shellcheck disable=SC2016  # the $1 is awk's, inside the command text under test
  local c='git grep -n -E '"'"'a|b'"'"' -- x | sort | awk '"'"'{print $1}'"'"' > /tmp/o.txt; echo "done (ok)"'
  local out
  out=$(hook_out "$c")
  [ "$out" = "${c/ -E / -P }" ]
  [ "${out#*-P}" = "${c#*-E}" ]
}

@test "a flagless BRE gets -P right after grep, every other byte kept" {
  local out
  out=$(hook_out "gtimeout 20 git -C /tmp grep -n 'foo.*bar' -- '*.sh'")
  [ "$out" = "gtimeout 20 git -C /tmp grep -P -n 'foo.*bar' -- '*.sh'" ]
}

@test "a simple command still gets its table prefixes after the rewrite" {
  local t="$BATS_TEST_TMPDIR/bound.patterns" out
  printf '30\t^git grep\n' > "$t"
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bin/cc-cpubound"
  chmod +x "$BATS_TEST_TMPDIR/bin/cc-cpubound"
  out=$(CC_QOS_BOUND_PATTERNS="$t" CC_QOS_CPUBOUND="$BATS_TEST_TMPDIR/bin/cc-cpubound" hook_out "git grep -n -E 'x'")
  [ "$out" = "$BATS_TEST_TMPDIR/bin/cc-cpubound 30 git grep -n -P 'x'" ]
}

@test "a bats command is transform (a)'s; (d) does not run" {
  mkdir -p "$BATS_TEST_TMPDIR/b"; printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/b/cc-bats"
  chmod +x "$BATS_TEST_TMPDIR/b/cc-bats"
  local out
  out=$(jq -cn --arg c "/opt/x/bats t.bats | git grep -E 'x'" '{tool_input:{command:$c}}' \
    | HOME="$BATS_TEST_TMPDIR" CC_QOS_CC_BATS="$BATS_TEST_TMPDIR/b/cc-bats" /bin/bash "$REPO/hooks/qos-rewrite.sh" \
    | jq -r '.hookSpecificOutput.updatedInput.command')
  [ "$out" = "$BATS_TEST_TMPDIR/b/cc-bats t.bats | git grep -E 'x'" ]
}

@test "git worktree remove and prune: no output at all" {
  local c raw
  for c in 'git worktree remove x' 'git worktree prune' 'git worktree remove --force ../wt'; do
    raw=$(jq -cn --arg c "$c" '{tool_input:{command:$c}}' \
      | HOME="$BATS_TEST_TMPDIR" /bin/bash "$REPO/hooks/qos-rewrite.sh" 2>&1)
    [ -z "$raw" ]
  done
}

@test "a git-grep-led compound that would also ignite: only one of the two hooks emits" {
  mkdir -p "$BATS_TEST_TMPDIR/g"; printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/g/cc-ignition-gate"
  chmod +x "$BATS_TEST_TMPDIR/g/cc-ignition-gate"
  local c="git grep -n -E 'x' && npm run build" q k
  q=$(hook_out "$c")
  k=$(jq -cn --arg c "$c" '{tool_input:{command:$c}}' \
    | CC_COLDCOMPILE_GATE="$BATS_TEST_TMPDIR/g/cc-ignition-gate" /bin/bash "$REPO/hooks/coldcompile-admit.sh")
  [ "$q" = "git grep -n -P 'x' && npm run build" ]
  [ -z "$k" ]
}

@test "the kill switch turns (d) off" {
  local out
  out=$(CC_QOS_GITGREP=off hook_out "git grep -n -E 'x' | head")
  [ -z "$out" ]
}

@test "both /usr/bin/git and Homebrew git accept -P" {
  local g ran=0
  for g in /usr/bin/git /opt/homebrew/bin/git; do
    [ -x "$g" ] || continue
    ( cd "$LAB" && "$g" grep -c -P 'table_match' -- text/qos-rewrite.sh ) > /dev/null
    ran=$((ran + 1))
  done
  [ "$ran" -gt 0 ] || skip "neither /usr/bin/git nor /opt/homebrew/bin/git is present"
  [ -x /usr/bin/git ] && [ -x /opt/homebrew/bin/git ] || skip "only one of the two gits is present ($ran ran green)"
}
