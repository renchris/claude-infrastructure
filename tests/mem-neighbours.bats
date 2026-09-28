#!/usr/bin/env bats
# New-topic neighbour advisory (truememory-2026-09-27.md §3.10): a Write that CREATES a memory topic
# or lesson is shown its two nearest existing files. Pinned here: the RENDERED hook JSON (exactly one
# object, carrying the canon rewrite too), every exit path logging to both stores with tool_use_id,
# the lib resolved through the dereferenced self-path (X1), and the nightly outcome classes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/backup-before-write.sh"
  OUTC="$REPO/scripts/mem-neighbours-outcome.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  unset CC_MEM_NEIGHBOURS CC_MEMPATH_CANON CC_MEM_NEIGH_BUDGET CC_MEM_NEIGH_DUP_SCORE
  mkdir -p "$HOME/.claude/projects/-proj/memory" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  MEM="$(cd -P "$HOME/.claude/projects/-proj/memory" && pwd -P)"
  NLOG="$HOME/.claude/state/mem-neighbours.jsonl"
  topic "$MEM/nohup-detach.md" nohup-detach "nohup from a tool call does not detach the child process group"
  topic "$MEM/pipefail-grep.md" pipefail-grep "pipefail turns a grep no-match into a failed pipeline"
  topic "$MEM/tui-colors.md" tui-colors "truecolor grays instead of dim SGR-2 text in the terminal UI"
  NEWC="$(topic - nohup-not-detached "a nohup child of a tool call is not detached, it is reaped with the process group")"
}

eq()  { [ "$1" = "$2" ] || { printf 'expected [%s]\n     got [%s]\n' "$2" "$1" >&2; return 1; }; }
has() { printf '%s' "$1" | grep -qF -- "$2" || { printf 'missing [%s] in [%s]\n' "$2" "$1" >&2; return 1; }; }
topic() { # <path|-> <name> <description> — a memory topic file (to stdout for -)
  local body
  body="$(printf -- '---\nname: %s\ndescription: %s\n---\n\n%s\n' "$2" "$3" "$3")"
  if [ "$1" = - ]; then printf '%s' "$body"; else printf '%s\n' "$body" > "$1"; fi
}
write() { # <file_path> [content] [hook] → hook stdout
  jq -nc --arg f "$1" --arg c "${2:-$NEWC}" \
    '{tool_name:"Write", tool_use_id:"toolu_T1", session_id:"s1", tool_input:{file_path:$f, content:$c}}' \
    | bash "${3:-$HOOK}"
}
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // "NONE"'; }
row() { tail -n 1 "$NLOG" | jq -r "$1"; }

@test "a new memory topic yields ONE object naming its twin first, in post-hoc wording" {
  out="$(write "$MEM/nohup-again.md")"
  eq "$(printf '%s' "$out" | jq -s length)" 1
  c="$(ctx "$out")"
  has "$c" "You just created nohup-again.md; its nearest existing files are nohup-detach.md ("
  has "$c" "leave nohup-again.md for compact-memory's orphan sweep; if it corrects one, add superseded_by"
  [ "${#c}" -le 400 ]
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" none
  eq "$(row .disposition)" fired
  eq "$(row .tool_use_id)" toolu_T1
  eq "$(row .path)" "$MEM/nohup-again.md"
  eq "$(row '.top | length')" 2
  eq "$(row '.top[0].path')" "$MEM/nohup-detach.md"
  eq "$(row .rm_friction)" not-auto-allowed
  eq "$(tail -n 1 "$CC_IDL" | jq -r '.hook + " " + .disposition + " " + .top[0].path')" \
     "backup-before-write:neighbours fired $MEM/nohup-detach.md"
}

@test "a symlinked-spelling new path yields ONE object carrying BOTH updatedInput and additionalContext" {
  out="$(write "$HOME/.claude-next/projects/-proj/memory/nohup-again.md")"
  eq "$(printf '%s' "$out" | jq -s length)" 1
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.file_path')" "$MEM/nohup-again.md"
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.content')" "$NEWC"
  has "$(ctx "$out")" "nearest existing files are nohup-detach.md"
  eq "$(row .path)" "$MEM/nohup-again.md"
}

@test "an existing file gets the past-tense OVERWRITE GUARD and no neighbour text or row" {
  printf 'old\n' > "$MEM/nohup-again.md"
  out="$(write "$MEM/nohup-again.md")"
  c="$(ctx "$out")"
  has "$c" "OVERWRITE GUARD: You just OVERWROTE 'nohup-again.md' (1 lines before the write)."
  ! printf '%s' "$c" | grep -q 'nearest existing' || false
  [ ! -e "$NLOG" ]
}

@test "MEMORY.md and archive/ never fire and log nothing" {
  mkdir -p "$MEM/archive"
  eq "$(write "$MEM/MEMORY.md")" ""
  eq "$(write "$MEM/archive/MEMORY_ARCHIVE_2026-H2.md")" ""
  [ ! -e "$NLOG" ]
  [ ! -e "$CC_IDL" ]
}

@test "a new docs/lessons file fires against its sibling lessons" {
  L="$BATS_TEST_TMPDIR/repo/docs/lessons"; mkdir -p "$L"
  printf '# nohup does not detach from a tool call\n\nThe child is reaped with the process group.\n' > "$L/nohup-reaped.md"
  printf '# right click does not move focus\n\nA menu reads the previous focus.\n' > "$L/right-click.md"
  out="$(write "$L/nohup-child-reaped.md" "$(printf '# a nohup child is reaped with its tool call\n\nprocess group.\n')")"
  eq "$(printf '%s' "$out" | jq -s length)" 1
  has "$(ctx "$out")" "nearest existing files are nohup-reaped.md ("
  eq "$(row '.top[0].path')" "$L/nohup-reaped.md"
}

@test "a memory store whose slug resolves to a repo also pools that repo's lessons" {
  RP="$BATS_TEST_TMPDIR/some.repo"; mkdir -p "$RP/docs/lessons"; RP="$(cd -P "$RP" && pwd -P)"
  printf '# pipefail turns a grep miss into a failed pipeline\n\nUse || true.\n' > "$RP/docs/lessons/pipefail-miss.md"
  SM="$HOME/.claude/projects/$(printf '%s' "$RP" | sed 's/[^A-Za-z0-9]/-/g')/memory"; mkdir -p "$SM"
  topic "$SM/tui.md" tui "truecolor grays in the terminal UI"
  out="$(write "$SM/grep-pipefail.md" "$(topic - grep-pipefail "grep no-match under pipefail fails the pipeline")")"
  eq "$(row '.top[0].path')" "$RP/docs/lessons/pipefail-miss.md"
  has "$(ctx "$out")" "nearest existing files are $RP/docs/lessons/pipefail-miss.md ("
}

@test "kill switch logs abstained:kill-switch and emits nothing" {
  out="$(CC_MEM_NEIGHBOURS=off write "$MEM/nohup-again.md")"
  eq "$out" ""
  eq "$(row '.disposition + ":" + .reason')" abstained:kill-switch
  eq "$(row .tool_use_id)" toolu_T1
}

@test "an empty pool logs abstained:empty-pool and emits nothing" {
  mkdir -p "$HOME/.claude/projects/-empty/memory"
  out="$(write "$(cd -P "$HOME/.claude/projects/-empty/memory" && pwd -P)/first.md")"
  eq "$out" ""
  eq "$(row '.disposition + ":" + .reason + ":" + (.top | length | tostring)')" abstained:empty-pool:0
}

@test "X1: a symlinked hook finds the lib through its real path; a copy without the lib is BLIND" {
  mkdir -p "$BATS_TEST_TMPDIR/live"
  ln -s "$HOOK" "$BATS_TEST_TMPDIR/live/backup-before-write.sh"
  out="$(write "$MEM/nohup-again.md" "$NEWC" "$BATS_TEST_TMPDIR/live/backup-before-write.sh")"
  has "$(ctx "$out")" "nohup-detach.md"
  eq "$(row .disposition)" fired
  cp "$HOOK" "$BATS_TEST_TMPDIR/live/copy.sh"
  out="$(write "$MEM/nohup-again.md" "$NEWC" "$BATS_TEST_TMPDIR/live/copy.sh")"
  eq "$out" ""
  eq "$(row '.disposition + ":" + (.reason | split(":")[0])')" abstained:neighbour-lib-missing
  eq "$(tail -n 1 "$CC_IDL" | jq -r .reason | cut -d: -f1)" neighbour-lib-missing
}

@test "an expired budget logs failed:timeout; a crashing scorer logs failed:rc=N" {
  out="$(CC_MEM_NEIGH_BUDGET=0.000001 write "$MEM/nohup-again.md")"
  eq "$out" ""
  eq "$(row '.disposition + ":" + .reason')" failed:timeout
  mkdir -p "$BATS_TEST_TMPDIR/stub"; printf '#!/bin/sh\nexit 3\n' > "$BATS_TEST_TMPDIR/stub/python3"
  chmod +x "$BATS_TEST_TMPDIR/stub/python3"
  out="$(PATH="$BATS_TEST_TMPDIR/stub:$PATH" write "$MEM/nohup-again.md")"
  eq "$out" ""
  eq "$(row '.disposition + ":" + .reason')" failed:rc=3
}

@test "every exit path writes the same row to BOTH stores, each with tool_use_id and path" {
  mkdir -p "$HOME/.claude/projects/-empty/memory"
  write "$MEM/a.md" >/dev/null
  CC_MEM_NEIGHBOURS=off write "$MEM/b.md" >/dev/null
  write "$HOME/.claude/projects/-empty/memory/c.md" >/dev/null
  CC_MEM_NEIGH_BUDGET=0.000001 write "$MEM/d.md" >/dev/null
  eq "$(jq -s length "$NLOG")" 4
  eq "$(jq -sc 'map(.tool_use_id == "toolu_T1" and (.path | length > 0)) | all' "$NLOG")" true
  eq "$(jq -sc 'map(.disposition + ":" + .reason)' "$NLOG")" \
     '["fired:top2","abstained:kill-switch","abstained:empty-pool","failed:timeout"]'
  eq "$(jq -sc 'map(del(.ts))' "$CC_IDL")" "$(jq -sc 'map(del(.ts))' "$NLOG")"
}

# ── nightly outcome check (criterion 4) ────────────────────────────────────────────────────────

NOW=2000000000
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
mt() { touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$1"; }
fired_row() { # <x> <a> <score> <epoch>
  jq -nc --arg ts "$(iso "$4")" --arg x "$1" --arg a "$2" --argjson s "$3" \
    '{ts:$ts, disposition:"fired", reason:"top2", tool_use_id:"t", path:$x, top:[{path:$a, score:$s}]}' >> "$NLOG"
}
outcome() { CC_MEM_NEIGH_NOW="$NOW" python3 "$OUTC"; }

@test "outcome: superseded, merged, unresolved and kept_distinct from stat and the rows" {
  mkdir -p "$HOME/.claude/state"; D="$BATS_TEST_TMPDIR/o"; mkdir -p "$D"; F=$(( NOW - 2 * 86400 ))
  printf -- '---\nname: x1\nsuperseded_by: a1.md\n---\n' > "$D/x1.md"; : > "$D/a1.md"
  : > "$D/a2.md"; mt "$D/a2.md" $(( F + 3600 ))                        # x2 gone, a2 edited after
  : > "$D/x3.md"; : > "$D/a3.md"; mt "$D/a3.md" $(( F - 3600 ))        # both left as they were
  : > "$D/x4.md"; : > "$D/a4.md"; mt "$D/a4.md" $(( F - 3600 ))        # same, but a low score
  fired_row "$D/x1.md" "$D/a1.md" 0.9 "$F"
  fired_row "$D/x2.md" "$D/a2.md" 0.9 "$F"
  fired_row "$D/x3.md" "$D/a3.md" 0.9 "$F"
  fired_row "$D/x4.md" "$D/a4.md" 0.1 "$F"
  fired_row "$D/x3.md" "$D/a3.md" 0.9 $(( NOW - 3600 ))               # < 24 h: not yet judged
  run outcome
  [ "$status" -eq 0 ]
  has "$output" "classified=4 kept_distinct=1 merged=1 superseded=1 unresolved=1 dup_score=0.900 (ESTIMATED top quartile)"
  eq "${lines[${#lines[@]}-1]}" "OUTCOME-VERDICT ok"
  eq "$(cat "$HOME/.claude/state/mem-neighbours-unresolved.txt")" "$D/x3.md	$D/a3.md	0.9	$(iso "$F")"
}

@test "outcome: more than half unresolved is unresolved-high; under 4 classified is unknown" {
  mkdir -p "$HOME/.claude/state"; D="$BATS_TEST_TMPDIR/o"; mkdir -p "$D"; F=$(( NOW - 2 * 86400 ))
  for i in 1 2 3; do : > "$D/x$i.md"; : > "$D/a$i.md"; mt "$D/a$i.md" $(( F - 60 )); fired_row "$D/x$i.md" "$D/a$i.md" 0.5 "$F"; done
  run outcome
  eq "${lines[${#lines[@]}-1]}" "OUTCOME-VERDICT unknown"
  : > "$D/x4.md"; : > "$D/a4.md"; mt "$D/a4.md" $(( F - 60 )); fired_row "$D/x4.md" "$D/a4.md" 0.5 "$F"
  run outcome
  has "$output" "unresolved=4"
  eq "${lines[${#lines[@]}-1]}" "OUTCOME-VERDICT unresolved-high"
  run env CC_MEM_NEIGH_DUP_SCORE=0.6 CC_MEM_NEIGH_NOW="$NOW" python3 "$OUTC"
  has "$output" "kept_distinct=4"
  eq "${lines[${#lines[@]}-1]}" "OUTCOME-VERDICT ok"
  eq "$(wc -c < "$HOME/.claude/state/mem-neighbours-unresolved.txt" | tr -d ' ')" 0
}

@test "outcome: no log at all is unknown, exit 0" {
  run outcome
  [ "$status" -eq 0 ]
  has "$output" "classified=0"
  eq "${lines[${#lines[@]}-1]}" "OUTCOME-VERDICT unknown"
}

# ── the expected-fires denominator (X5) ────────────────────────────────────────────────────────

@test "denom_new_memory_files counts topic births in the window, never MEMORY.md or old files" {
  D="$BATS_TEST_TMPDIR/stores/memory"; mkdir -p "$D/archive"
  for i in $(seq 1 12); do : > "$D/t$i.md"; done
  : > "$D/MEMORY.md"; : > "$D/archive/a.md"
  : > "$D/old.md"; touch -t 202001010000 "$D/old.md"                   # APFS moves birthtime back too
  reg="$BATS_TEST_TMPDIR/reg.tsv"
  printf 'branch\tdenominator-fn\twindow\tD_min\tratio_floor\n' > "$reg"
  grep '^backup-before-write:neighbours' "$REPO/scripts/idl-expected-fires.tsv" >> "$reg"
  alarm() { env CC_IDL="$CC_IDL" CC_ABSTAIN_LOG="$BATS_TEST_TMPDIR/al.log" CC_ABSTAIN_CENSUS=0 \
      CC_EXPECTED_FIRES="$reg" CC_EXPECTED_NEIGH_DIRS="$D" "$REPO/scripts/idl-abstain-alarm.sh" --run; }
  run alarm
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'SILENT  *backup-before-write:neighbours .*D=12 '
  for i in $(seq 1 12); do write "$MEM/n$i.md" >/dev/null; done
  run alarm
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'OK  *backup-before-write:neighbours .*D=12 '
}
