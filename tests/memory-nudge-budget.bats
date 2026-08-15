#!/usr/bin/env bats
# memory-nudge.sh — UserPromptSubmit hook: periodic crystallization nudge + the
# APPEND-TIME BUDGET that keeps MEMORY.md under the harness read limit.
#
# The defect this pins: the index is loaded with hard caps past which the loader SILENTLY
# DROPS THE TAIL — the newest entries. Three manual compaction passes each re-inflated within
# days because nothing measured the budget at the moment of APPEND. Measured 2026-07-31:
# 27796 B / 96 entries, ~2811 B over.
#
# UNITS, CORRECTED 2026-08-15 (cc-backlog 7a56de4c54ab). The caps are 25000 CHARS and 200 LINES
# of the content AFTER YAML frontmatter and block HTML comments are stripped and the result
# trimmed — never the raw bytes on disk. Every expected figure below is therefore DERIVED from
# hooks/lib/memory-index-measure.sh at test time rather than hand-computed in bytes, so a fixture
# whose punctuation changes cannot quietly stop discriminating.
#
# RED-proof coverage: the over-limit gate fires on the FIRST prompt (not the
# periodic slot); each of the three diagnoses (hook-length / both / cardinality)
# is selected by the arithmetic, not asserted; a HEALTHY index never raises the
# alarm (polarity control) and never blocks; every fail-safe path exits 0 with no
# output; output is always valid JSON; the counter is sandboxed per config dir.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a
# non-final `[[ ]]` in a bats body evaluates and DISCARDS its result — the test
# passes vacuously (scripts/bats-assert-liveness.py; this file was written that
# way first and the ratchet caught 17 of them).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/memory-nudge.sh"
  # Fixture $HOME: the hook falls back to $HOME/.claude for both the config dir and
  # the counter, so an unfixtured suite would read and write the operator's live ~/.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  # shellcheck source=../hooks/lib/memory-index-measure.sh
  . "$REPO/hooks/lib/memory-index-measure.sh"
  LIMIT="$(mim_limit)"
  LINE_LIMIT="$(mim_line_limit)"
}

# The size the LOADER checks — what every figure in this suite is denominated in.
eff()  { m="$(mim_measure_file "$1")"; printf '%s' "${m%% *}"; }

# ── errexit-live assertion helpers (function calls are ordinary simple commands) ──
has()    { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt()  { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }
starts() { case "$1" in "$2"*) return 0 ;; *) return 1 ;; esac; }

# Build an index fixture: $1 entries, each with a $2-byte hook.
mkindex() {
  local n="$1" hooklen="$2" dir f i pad
  dir="$BATS_TEST_TMPDIR/idx-$n-$hooklen"; mkdir -p "$dir"; f="$dir/MEMORY.md"
  pad="$(head -c "$hooklen" /dev/zero | tr '\0' x)"
  : >"$f"
  for ((i=0; i<n; i++)); do printf -- '- [T%s](t%s.md) — %s\n' "$i" "$i" "$pad" >>"$f"; done
  printf '%s' "$f"
}

# Invoke the hook once as prompt #N for a given session id.
fire() {  # fire <sid> <index-path> [cwd]
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "${3:-/nonexistent-cwd-xyz}" \
    | MEMORY_INDEX_PATH="$2" bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext'; }

# ── the gate fires, and fires EARLY ───────────────────────────────────────────

@test "over-limit index raises the alarm on the FIRST prompt, not the periodic slot" {
  idx="$(mkindex 100 250)"
  [ "$(eff "$idx")" -gt "$LIMIT" ]              # fixture really is over
  run fire s-first "$idx"
  [ "$status" -eq 0 ]
  starts "$(printf '%s' "$output" | ctx)" '🚨'
}

@test "alarm reports the true overage and that the NEWEST entries were dropped" {
  idx="$(mkindex 100 250)"; total="$(eff "$idx")"
  run fire s-num "$idx"
  out="$(printf '%s' "$output" | ctx)"
  # RAW bytes are 201 higher here (100 em-dashes at 3 bytes / 1 unit, plus the trailing
  # newline the loader trims). A hook that reported the file size fails on both lines.
  [ "$(wc -c <"$idx" | tr -d ' ')" -gt "$total" ]
  has "$out" "$total chars vs the $LIMIT char loader limit"
  has "$out" "over by $((total - LIMIT))"
  has "$out" "NEWEST"
  has "$out" "no reader can tell"
}

# ── the three diagnoses are SELECTED by arithmetic, not asserted ──────────────

@test "diagnosis: long hooks over a small overage ⇒ shortening is the lever" {
  run fire s-lev1 "$(mkindex 100 250)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'hook LENGTH is the binding lever'
  has "$out" 'more than the'                    # recovery >= overage, checked not claimed
  hasnt "$out" 'CARDINALITY'
}

@test "diagnosis: hooks already at target ⇒ CARDINALITY, shortening cannot reach it" {
  run fire s-lev2 "$(mkindex 600 40)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'CARDINALITY'
  has "$out" 'shortening CANNOT reach the limit'
  has "$out" 'DURABILITY criterion'
  hasnt "$out" 'binding lever'
}

@test "diagnosis: partial recovery ⇒ BOTH levers, never a false 'enough'" {
  # 190 entries x 130 B hooks: over the limit, but shortening to 115 B recovers
  # far less than the overage — the message must not claim shortening suffices.
  run fire s-lev3 "$(mkindex 190 130)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'BOTH levers are needed'
  has "$out" 'recovers only'
  hasnt "$out" 'more than the'
}

# The recoverable-bytes figure must be DERIVED from the live file, never measured against the
# hardcoded 115. 1676a681 fixed this one position over (the CEILING); the LEVER kept the constant,
# so it over-claimed recovery on exactly the branch that fires when the index is already breached.
# 100 entries x 250-char hooks: the allowance this index affords is 206, so the honest recovery is
# 100 x (250-206) = 4400, not the 100 x (250-115) = 13500 the constant reports. RED on the pre-fix
# hook, which emits '115 B one-governing-rule target' and '~13500 B' for this same fixture.
@test "recoverable budget is DERIVED from the live index, not measured against the 115 constant" {
  run fire s-derived "$(mkindex 100 250)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" '206 char allowance this index actually affords'
  has "$out" 'recovers ~4400 chars'
  hasnt "$out" '115 B one-governing-rule target'
  hasnt "$out" '13500'
}

# The 115 constant is not deleted — it is demoted to a FLOOR, so it still governs a CROWDED index
# where the derived allowance falls below one governing rule. 190 x 130 derives 98; claiming
# recovery down to 98 would promise hooks shorter than a sentence, so the floor holds at 115 and
# the verdict stays BOTH-levers (pinned by s-lev3 above). This asserts the floor is what bound it.
@test "the 115 target survives as a FLOOR when the derived allowance falls below it" {
  run fire s-floor "$(mkindex 190 130)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" '115 char allowance'
  hasnt "$out" '98 char allowance'
}

# ── the OTHER cap, and the strips: nothing here measured either before 2026-08-15 ──

@test "the 200-LINE cap raises its own alarm, and names cardinality rather than size" {
  # An index can sit deep inside its char budget with its newest entries already invisible:
  # 210 short entries is 4 KB against a 25000 cap and 10 lines past the line cap. Before the
  # correction this branch did not exist, so this breach had no sensor at all.
  idx="$(mkindex $(( LINE_LIMIT + 10 )) 5)"
  [ "$(eff "$idx")" -lt "$LIMIT" ]               # comfortably inside the SIZE cap...
  run fire s-lines "$idx"
  out="$(printf '%s' "$output" | ctx)"
  starts "$out" '🚨'                             # ...and still breached
  has "$out" "OVER ITS LINE LIMIT"
  has "$out" "$(( LINE_LIMIT + 10 )) lines vs the ${LINE_LIMIT}-line loader limit"
  has "$out" 'CARDINALITY cap, not the size one'
  hasnt "$out" 'OVER ITS READ LIMIT'
}

@test "frontmatter and a block comment are not counted — the budget reports the loaded size" {
  # The rotor writes a `<!-- cold tier: … -->` pointer into the index and topic-style indexes
  # carry a `--- … ---` header; the loader strips both. A raw-byte hook reports a size the
  # operator cannot act on, and at the margin declares a breach that has not happened.
  base="$(mkindex 40 250)"; d="$BATS_TEST_TMPDIR/fm/memory"; mkdir -p "$d"
  { printf -- '---\nname: idx\ntype: reference\n---\n'; \
    printf '<!-- cold tier: archive/MEMORY_ARCHIVE_2026-H2-COLD.md -->\n'; \
    cat "$base"; } >"$d/MEMORY.md"
  [ "$(wc -c <"$d/MEMORY.md" | tr -d ' ')" -gt "$(wc -c <"$base" | tr -d ' ')" ]
  [ "$(eff "$d/MEMORY.md")" -eq "$(eff "$base")" ]      # the additions cost nothing
  out=""
  for _ in $(seq 1 12); do out="$(fire s-strip "$d/MEMORY.md" || true)"; done
  has "$(printf '%s' "$out" | ctx)" "$(eff "$base")/$LIMIT chars"
}

@test "alarm carries the one-in-one-out rule and keeps the lossy half human-gated" {
  run fire s-rule "$(mkindex 100 250)"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'ONE-IN-ONE-OUT'
  has "$out" 'PROPOSE-ONLY'
}

# ── polarity control: a healthy index must NOT raise the alarm ────────────────

@test "healthy index is silent off the periodic slot (no always-on alarm)" {
  run fire s-quiet "$(mkindex 40 100)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "healthy index at the periodic slot reports budget, never the alarm" {
  idx="$(mkindex 40 100)"; out=""
  for _ in $(seq 1 12); do out="$(fire s-periodic "$idx" || true)"; done
  ctxout="$(printf '%s' "$out" | ctx)"
  has "$ctxout" 'MEMORY INDEX BUDGET (live)'
  has "$ctxout" 'headroom'
  has "$ctxout" 'entry slots left'
  hasnt "$ctxout" '🚨'                          # polarity: no alarm when healthy
  has "$ctxout" 'MEMORY CHECK (periodic)'
}

@test "budget names a per-append hard cap the model can actually apply" {
  idx="$(mkindex 40 100)"; out=""
  for _ in $(seq 1 12); do out="$(fire s-cap "$idx" || true)"; done
  has "$(printf '%s' "$out" | ctx)" 'hard cap this append:'
}

@test "runway is counted at the OBSERVED density, not the target-length ceiling" {
  # 40 entries x 250-char hooks: healthy (10739 chars), but written 2.2x longer than
  # the 115 target. The target-based ceiling leaves 147 slots; only 53 lines of the
  # length this index is actually written at fit in the headroom. Leading with 145
  # tells a caller it has 2.8x the room it has. Measured live 2026-08-06 as 37 vs
  # 11, and that inflated figure had already reached a backlog item's premise as
  # "37 free cardinality slots" — framing a cardinality-bound index as length-bound.
  idx="$(mkindex 40 250)"; out=""
  [ "$(eff "$idx")" -lt "$LIMIT" ]               # fixture is healthy, not over
  for _ in $(seq 1 12); do out="$(fire s-runway "$idx" || true)"; done
  ctxout="$(printf '%s' "$out" | ctx)"
  has "$ctxout" '~53 entry slots left'           # observed 269 chars/line
  has "$ctxout" 'ACTUALLY written at'
  has "$ctxout" '147 char-slots only if'         # ceiling kept, marked conditional
  hasnt "$ctxout" '~147 entry slots left'        # the pre-fix wording this pins
}

# ── fail-safe: a side-car must fail no wider than itself ──────────────────────

@test "missing index still emits the plain nudge at the periodic slot" {
  out=""
  for _ in $(seq 1 12); do out="$(fire s-none "$BATS_TEST_TMPDIR/absent/MEMORY.md" || true)"; done
  starts "$(printf '%s' "$out" | ctx)" 'MEMORY CHECK (periodic)'
}

@test "unreadable and empty indexes degrade to the plain nudge, never a crash" {
  empty="$BATS_TEST_TMPDIR/empty.md"; : >"$empty"
  noent="$BATS_TEST_TMPDIR/nope.md"
  n=0
  for f in "$empty" "$noent"; do
    out=""; n=$((n + 1))   # sid must stay [A-Za-z0-9_-]: the hook rejects a dot
    for _ in $(seq 1 12); do out="$(fire "s-degrade-$n" "$f" || true)"; done
    printf '%s' "$out" | jq -e . >/dev/null
    hasnt "$(printf '%s' "$out" | ctx)" '🚨'
  done
}

@test "malformed stdin and a missing session_id exit 0 silently" {
  run bash -c "printf 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf '{}' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "INTERVAL=0 is a total kill switch even with an over-limit index" {
  run bash -c "printf '{\"session_id\":\"s-off\",\"cwd\":\"/x\"}' \
    | MEMORY_NUDGE_INTERVAL=0 MEMORY_INDEX_PATH='$(mkindex 100 250)' bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── contract: the payload is always valid JSON ────────────────────────────────

@test "every firing path emits valid single-line JSON with the right event name" {
  i=0
  for idx in "$(mkindex 100 250)" "$(mkindex 600 40)" "$(mkindex 190 130)"; do
    i=$((i + 1))
    run fire "s-json-$i" "$idx"
    printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    # bats strips the trailing newline, so a compact one-line payload has 0 embedded ones
    [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  done
}

# ── resolution: a linked worktree keys on the MAIN worktree, like the harness ──

@test "index is resolved through the git COMMON dir, not the linked worktree path" {
  main="$BATS_TEST_TMPDIR/proj"; mkdir -p "$main"
  git init -q "$main"
  ( cd "$main" || exit 1; git config user.email t@e.com; git config user.name t
    echo x > a.txt; git add a.txt; git commit -q -m base ) >/dev/null 2>&1
  wt="$BATS_TEST_TMPDIR/wt-linked"
  ( cd "$main"; git worktree add -q -b wtb "$wt" ) >/dev/null 2>&1
  # Key the fixture on the PHYSICAL main path: git reports a resolved path, and in
  # production the harness slug is a real path (no /var -> /private/var confound).
  main_phys="$(cd "$main" && pwd -P)"
  slug="$(printf '%s' "$main_phys" | tr '/.' '--')"
  memdir="$CLAUDE_CONFIG_DIR/projects/$slug/memory"; mkdir -p "$memdir"
  cp "$(mkindex 100 250)" "$memdir/MEMORY.md"
  # Fire FROM the linked worktree with no MEMORY_INDEX_PATH override.
  run bash -c "printf '{\"session_id\":\"s-wt\",\"cwd\":\"$wt\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  starts "$(printf '%s' "$output" | ctx)" '🚨'
}

# ── the counter follows the config dir in play ────────────────────────────────

@test "counter is written under the configured state dir, not a hardcoded ~/.claude" {
  fire s-count "$(mkindex 40 100)" >/dev/null || true
  [ -f "$MEMORY_NUDGE_STATE_DIR/nudge-s-count.count" ]
  [ "$(cat "$MEMORY_NUDGE_STATE_DIR/nudge-s-count.count")" = "1" ]
}

# ── the dropped-entry count is EXACT, not an average ──────────────────────────
#
# Every fixture above is UNIFORM (mkindex writes one hook length), and on a uniform
# index the averaged estimator and the exact count AGREE — so a uniform fixture can
# never fail an averaged implementation, and the whole suite passed one for a week.
# The discriminating fixture is a SKEWED one: many short entries, then a long tail.
# That is also the live index's actual shape — measured 2026-08-08 the averaged form
# announced 6 dropped entries where the exact count was 4, and that number is what an
# operator sizes a compaction pass from.

# A skewed index: $1 short entries of $2 bytes, then $3 long entries of $4 bytes.
mkskewed() {
  local ns="$1" hs="$2" nl="$3" hl="$4" dir f i pads padl
  dir="$BATS_TEST_TMPDIR/skew-$ns-$hs-$nl-$hl"; mkdir -p "$dir"; f="$dir/MEMORY.md"
  pads="$(head -c "$hs" /dev/zero | tr '\0' x)"
  padl="$(head -c "$hl" /dev/zero | tr '\0' y)"
  : >"$f"
  for ((i=0; i<ns; i++)); do printf -- '- [S%s](s%s.md) — %s\n' "$i" "$i" "$pads" >>"$f"; done
  for ((i=0; i<nl; i++)); do printf -- '- [L%s](l%s.md) — %s\n' "$i" "$i" "$padl" >>"$f"; done
  printf '%s' "$f"
}

@test "dropped count is the entries that START past the limit, not overage/mean-line" {
  idx="$(mkskewed 200 100 6 900)"
  total="$(eff "$idx")"
  [ "$total" -gt "$LIMIT" ]
  # The exact answer, computed independently of the hook and in the LOADER's unit — UTF-16
  # code units of the effective content. Walked in raw BYTES over the raw file it names a
  # different entry (every offset past a multibyte char is shifted), which is the 2026-08-15
  # correction. In python, not awk: this box's awk is mawk, whose length() is bytes whatever
  # the locale says, so an awk control would silently re-introduce the bug it is checking for.
  read -r exact entry_b <<<"$(mim_effective_file "$idx" | python3 -c '
import sys
def u(s): return sum(2 if ord(c) > 0xFFFF else 1 for c in s)
lines = sys.stdin.read().split("\n")
lim, off, dropped, entry = '"$LIMIT"', 0, 0, 0
for l in lines:
    if l.startswith("- ["):
        if off >= lim: dropped += 1
        entry += u(l) + 1
    off += u(l) + 1
print(dropped, entry)')"
  # The averaged answer the old implementation produced. The fixture is only a valid
  # control if the two DISAGREE — otherwise this test passes against either one.
  n="$(grep -c '^- \[' "$idx")"
  # Kept flat: a nested `((` inside `$(( ))` reads as an arithmetic ASSERTION to
  # scripts/bats-assert-liveness.py, whose lookbehind only exempts the `$((` opener.
  mean_line=$(( entry_b / n ))
  averaged=$(( (total - LIMIT) / mean_line + 1 ))
  [ "$averaged" -ne "$exact" ]
  run fire s-exact "$idx"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" "the NEWEST $exact entries begin past the limit"
  hasnt "$out" "the NEWEST $averaged entries"
}

@test "an overage landing INSIDE the last entry still reports at least one dropped" {
  # No entry STARTS past the limit here — the limit falls mid-entry — so a bare count
  # returns 0 and the alarm would claim nothing was lost while the tail was cut.
  idx="$(mkskewed 0 0 1 40000)"
  [ "$(wc -c <"$idx" | tr -d ' ')" -gt "$LIMIT" ]
  starts_past="$(LC_ALL=C awk -v lim="$LIMIT" \
    '{ if (substr($0,1,3)=="- [" && off>=lim) n++; off+=length($0)+1 } END{ print n+0 }' "$idx")"
  [ "$starts_past" -eq 0 ]
  run fire s-inside "$idx"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" "the NEWEST 1 entries begin past the limit"
}

# ── the limit is ONE number, however many files read it ───────────────────────

@test "the three measurers share ONE limit literal, and nothing else spells it" {
  # These used to be three separate literals in three files (single-sourcing was rejected: a
  # sourced lib the host cannot resolve fails open SILENTLY and reads as landed while inert —
  # tests/memory-index-budget.bats pins that trap for the gate, and both the nudge and the rotor
  # now carry the same deref-and-degrade shape). Three literals held only while something failed
  # when they drifted, and on 2026-08-15 all three were wrong TOGETHER in the same direction —
  # a drift test cannot see a shared error. So the default now lives in ONE file and the other
  # two read it; this asserts that, and that no fourth spelling has appeared.
  n="$(grep -c 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks/lib/memory-index-measure.sh")"
  [ "$n" -eq 1 ]
  [ "$(grep -c 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks/memory-nudge.sh")" -eq 0 ]
  [ "$(grep -c 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks/lib/memory-index-budget.sh")" -eq 0 ]
  # And no THIRD spelling anywhere in the executable surface. Counted in a loop, not
  # with `grep -vc`: grep exits 1 on a zero count, so the healthy case would abort the
  # test under errexit and read as a failure of the thing it is asserting is fine.
  list="$(grep -rl 'MEMORY_INDEX_LIMIT:-' "$REPO/hooks" "$REPO/bin" "$REPO/scripts" 2>/dev/null || true)"
  others=0
  for f in $list; do
    case "$f" in
      */memory-index-measure.sh|*/cc-memory-rotate) ;;
      *) others=$(( others + 1 )) ;;
    esac
  done
  [ "$others" -eq 0 ]
}

# ── actuation: the nudge ROTATES before it advises (2026-08-10) ───────────────
# Twelve hand-compactions in 14 days proved advisory text cannot hold the line;
# cc-memory-rotate mechanizes the operator-approved cold split and this hook is
# its fleet-wide call site. Rotation runs on every over-threshold prompt
# regardless of the advisory damping; the 🚨 now means rotation COULD NOT help.

# A rotor-shaped fixture: a real */memory/ dir with typed, aged topic files.
mkmemdir() {  # mkmemdir <name> <entries> <hookbytes> → path to MEMORY.md
  local name="$1" n="$2" hb="$3" d i pad
  d="$BATS_TEST_TMPDIR/$name/memory"; mkdir -p "$d"
  pad="$(head -c "$hb" /dev/zero | tr '\0' x)"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  i=0
  while [ "$i" -lt "$n" ]; do
    printf -- '- [e%02d](e%02d.md) — %s\n' "$i" "$i" "$pad" >>"$d/MEMORY.md"
    printf -- '---\nname: e%02d\ndescription: d\nmetadata:\n  type: project\n---\nbody\n' "$i" >"$d/e$(printf '%02d' "$i").md"
    touch -t 202601011200 "$d/e$(printf '%02d' "$i").md"
    i=$((i + 1))
  done
  printf '%s' "$d/MEMORY.md"
}

rotate_env() {  # small, hand-countable budgets for the actuation tests
  export MEMORY_INDEX_LIMIT=3000 MEMORY_ROTATE_AT=1500 MEMORY_ROTATE_TARGET=1000
  export MEMORY_ROTATE_TAIL_GUARD=1 MEMORY_ROTATE_MIN_KEEP=2 MEMORY_ROTATE_MIN_AGE_DAYS=7
  export MEMORY_ROTATE_BIN="$REPO/bin/cc-memory-rotate"
}

@test "actuation is independent of advisory cadence: prompt 1 rotates the file and stays silent" {
  rotate_env
  idx="$(mkmemdir act1 20 140)"                  # ~3.2 KB: over the 3000 B limit itself
  [ "$(wc -c <"$idx" | tr -d ' ')" -gt 3000 ]
  run fire s-act1 "$idx"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                               # damped prompt: no advisory...
  [ "$(wc -c <"$idx" | tr -d ' ')" -le 1000 ]    # ...but the index was healed on disk
  ls "$(dirname "$idx")"/archive/MEMORY_ARCHIVE_*-COLD.md >/dev/null
}

@test "rotation on an advisory slot reports the post-rotation state, not the breach" {
  rotate_env
  idx="$(mkmemdir act2 20 140)"
  run bash -c "printf '{\"session_id\":\"s-act2\",\"cwd\":\"/x\"}' \
    | MEMORY_NUDGE_INTERVAL=1 MEMORY_INDEX_PATH='$idx' bash '$HOOK'"
  out="$(printf '%s' "$output" | ctx)"
  hasnt "$out" '🚨'                              # the breach never reaches the model
  has "$out" 'AUTO-ROTATED'
  has "$out" 'MEMORY INDEX BUDGET (live)'
  has "$out" 'restore = paste the line back'
}

@test "rotation that cannot clear the breach keeps the alarm and names the verdict" {
  rotate_env
  d="$BATS_TEST_TMPDIR/act3/memory"; mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  pad="$(head -c 140 /dev/zero | tr '\0' x)"
  for i in $(seq -w 1 20); do                    # dangling links: nothing is eligible
    printf -- '- [g%s](g%s.md) — %s\n' "$i" "$i" "$pad" >>"$d/MEMORY.md"
  done
  run fire s-act3 "$d/MEMORY.md"
  out="$(printf '%s' "$output" | ctx)"
  starts "$out" '🚨'
  has "$out" 'could NOT clear'
  has "$out" 'verdict=exhausted'
}

@test "band-pressure exhaustion is the designed steady state: healthy message, no failure note" {
  rotate_env
  d="$BATS_TEST_TMPDIR/act5/memory"; mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  pad="$(head -c 120 /dev/zero | tr '\0' x)"
  for i in $(seq -w 1 12); do                    # dangling: nothing eligible at any stage
    printf -- '- [g%s](g%s.md) — %s\n' "$i" "$i" "$pad" >>"$d/MEMORY.md"
  done
  sz="$(wc -c <"$d/MEMORY.md" | tr -d ' ')"
  [ "$sz" -ge 1500 ]
  [ "$sz" -lt 3000 ]                             # over ROTATE_AT, under the LIMIT
  run bash -c "printf '{\"session_id\":\"s-act5\",\"cwd\":\"/x\"}' \
    | MEMORY_NUDGE_INTERVAL=1 MEMORY_INDEX_PATH='$d/MEMORY.md' bash '$HOOK'"
  out="$(printf '%s' "$output" | ctx)"
  has "$out" 'MEMORY INDEX BUDGET (live)'
  hasnt "$out" 'could NOT clear'
  hasnt "$out" '🚨'
}

@test "an unresolvable rotor degrades to the alarm with an unavailability note" {
  rotate_env
  export MEMORY_ROTATE_BIN="$BATS_TEST_TMPDIR/no-such-rotor"
  idx="$(mkmemdir act4 20 140)"
  before="$(wc -c <"$idx" | tr -d ' ')"
  run fire s-act4 "$idx"
  out="$(printf '%s' "$output" | ctx)"
  starts "$out" '🚨'
  has "$out" 'Auto-rotation unavailable'
  [ "$(wc -c <"$idx" | tr -d ' ')" -eq "$before" ]
}
