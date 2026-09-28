#!/usr/bin/env bats
# memory-fleet-sweep.sh — the fleet-wide measurement the machine did not have.
#
# The defect this pins: hooks/memory-nudge.sh resolves the index from the SESSION'S OWN cwd, so
# only the project you happen to have open is ever measured — while cc-memory-rotate's header
# claims "the next prompt ANYWHERE rotates it back under budget". Measured 2026-09-03,
# doc-classifier sat 2,256 units over the cap for ELEVEN DAYS with its 9 newest memories loading
# in zero sessions, archive/ and .rotate.log both absent, and no launchd or cron job watching.
#
# RED-proof coverage: DARK is proven in BOTH directions on hand-built fixtures (a metric that only
# ever reads 0 proves nothing — the over-cap fixture must produce a non-zero DARK); report-only is
# proven by byte-comparison, not by absence of a message; the tmp-fixture exclusion is proven to be
# COUNTED rather than silent; and the dedupe is exercised through two config dirs pointing at one
# tree, which is the live shape (.claude and .claude-quaternary resolve together here).
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]`
# evaluates and DISCARDS its result (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/memory-fleet-sweep.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

# mkidx <config-dir-name> <slug> <n-entries> <entry-pad> → an index with n entries of a given size
mkidx() {
  local cfg="$HOME/$1" slug="$2" n="$3" pad="$4" d i
  d="$cfg/projects/$slug/memory"; mkdir -p "$d"
  printf '# Project Memory\n' >"$d/MEMORY.md"
  i=0
  while [ "$i" -lt "$n" ]; do
    printf -- '- [e%02d %s](e%02d.md) — hook\n' "$i" "$(head -c "$pad" /dev/zero | tr '\0' x)" "$i" >>"$d/MEMORY.md"
    printf -- '---\nname: e%02d\nmetadata:\n  type: project\n---\nbody\n' "$i" >"$d/e$(printf '%02d' $i).md"
    i=$(( i + 1 ))
  done
  printf '%s' "$d/MEMORY.md"
}

@test "a healthy fleet reports ok and exits 0" {
  mkidx .claude proj-small 3 40 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  has "$output" 'proj-small'
  has "$output" '0 over cap'
}

@test "DARK is non-zero for an over-cap index — the whole point of the tool" {
  # 40 entries × ~700 chars ≈ 28,000 > the 25,000 cap, so the tail entries start past the cut and
  # load in NO session. If DARK reported 0 here the metric would be decorative.
  mkidx .claude proj-over 40 700 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  has "$output" 'OVER'
  has "$output" '1 over cap'
  # the DARK column for that row must be a positive integer
  dark="$(printf '%s' "$output" | awk '/proj-over/ {print $5}')"
  [ "$dark" -gt 0 ]
}

@test "DARK is zero for an index that fits — the negative control on the same metric" {
  mkidx .claude proj-fits 10 200 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  dark="$(printf '%s' "$output" | awk '/proj-fits/ {print $5}')"
  [ "$dark" -eq 0 ]
}

@test "report-only by default: the index is byte-identical after a sweep of an OVER index" {
  idx="$(mkidx .claude proj-ro 40 700)"
  cp "$idx" "$BATS_TEST_TMPDIR/ro.before"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  cmp -s "$idx" "$BATS_TEST_TMPDIR/ro.before"
}

@test "the entries column is a single number — grep -c prints 0 AND exits 1" {
  # An index with a header and no entry bullets at all. `|| printf 0` on a grep -c that already
  # printed its own 0 rendered the column as two lines and shifted every column after it.
  d="$HOME/.claude/projects/proj-empty/memory"; mkdir -p "$d"
  printf '# Project Memory\n' >"$d/MEMORY.md"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'proj-empty')" -eq 1 ]
  [ "$(printf '%s' "$output" | awk '/proj-empty/ {print NF}')" -eq 6 ]
}

@test "tmp probe fixtures are skipped, and the skip is COUNTED not silent" {
  mkidx .claude -private-tmp-memprobe-row9 40 700 >/dev/null
  mkidx .claude proj-real 3 40 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 0 ]                      # the fixture must not make the fleet look breached
  hasnt "$output" 'memprobe-row9'
  has "$output" '1 tmp fixture(s) skipped'
}

@test "one tree reached through two config dirs is swept ONCE" {
  mkidx .claude proj-dup 3 40 >/dev/null
  ln -s "$HOME/.claude" "$HOME/.claude-quaternary"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'proj-dup')" -eq 1 ]
  has "$output" '1 index(es) swept'
}

@test "--rotate acts only on the OVER index, and leaves the healthy one alone" {
  over="$(mkidx .claude proj-hot 40 700)"
  fine="$(mkidx .claude proj-cool 3 40)"
  cp "$fine" "$BATS_TEST_TMPDIR/cool.before"
  before_hot="$(wc -c <"$over" | tr -d ' ')"
  run "$SCRIPT" --rotate
  has "$output" 'rotating'
  cmp -s "$fine" "$BATS_TEST_TMPDIR/cool.before"
  # The hot index may shrink (rotated) or hold (every entry protected), but a sweep must NEVER
  # grow one — and asserting that is what makes capturing the path meaningful rather than dead.
  after_hot="$(wc -c <"$over" | tr -d ' ')"
  [ "$after_hot" -le "$before_hot" ]
  # the rotor is the only thing that may have touched the hot one; either it rotated or it
  # reported a verdict, but the tool must not have silently rewritten anything itself
  has "$output" 'verdict='
}

@test "invoked THROUGH a symlink it still finds the real repo root" {
  # scripts/self-path-lint.sh ratchets this scar and caught this file on its first land attempt.
  # Reached as ~/.claude/scripts/memory-fleet-sweep.sh, a bare `dirname "$0"/..` derives ~/.claude
  # as the root and resolves the measure lib and the rotor to the wrong tree — silently, because
  # the symlink farm makes wrong-but-present the likely outcome rather than a clean failure.
  mkdir -p "$BATS_TEST_TMPDIR/farm"
  ln -sf "$SCRIPT" "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh"
  mkidx .claude proj-link 3 40 >/dev/null
  run bash "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh"
  [ "$status" -eq 0 ]
  has "$output" 'proj-link'
}

# ── --reach ─────────────────────────────────────────────────────────────────────────────────────
# A real project dir on disk, its store under the temp HOME keyed by the project's slug, a topic
# the index links (a.md), and a topic cited ONLY by the situational rules file (b.md) — the
# delivered-surface shape §3.8 measured. The settings fixture decides whether that file loads.
mkreach() {
  PROJ="$BATS_TEST_TMPDIR/work/proj-reach"
  mkdir -p "$PROJ/.claude/rules"
  PROJ="$(cd "$PROJ" && pwd -P)"
  SLUG="$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')"
  STORE="$HOME/.claude/projects/$SLUG/memory"; mkdir -p "$STORE"
  printf -- '- [A](a.md) — hook\n' >"$STORE/MEMORY.md"
  printf 'a\n' >"$STORE/a.md"; printf 'b\n' >"$STORE/b.md"
  printf '# Project\nNothing here names the situational file.\n' >"$PROJ/CLAUDE.md"
  printf -- '- [B](b.md) — only here\n' >"$PROJ/.claude/rules/agent-operating-lessons-situational.md"
  export RULES_LOADED_SETTINGS="$BATS_TEST_TMPDIR/settings.json"
  printf '{"claudeMdExcludes":["**/.claude/rules/agent-operating-lessons-situational.md"],"model":"claude-opus-5-5"}\n' \
    >"$RULES_LOADED_SETTINGS"
}

# mkcache <path> <features-json> → a .claude.json holding that cachedGrowthBookFeatures object
mkcache() { mkdir -p "$(dirname "$1")"; printf '{"cachedGrowthBookFeatures":%s}\n' "$2" >"$1"; }
OFF='{"tengu_passport_quail":false,"tengu_slate_thimble":false,"tengu_onyx_plover":{"enabled":false},"tengu_sepia_cormorant":[],"tengu_umber_petrel":false}'

@test "--reach absent: the table and the exit code are exactly what they were" {
  mkreach
  mkidx .claude proj-over 40 700 >/dev/null
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  plain="$output"
  hasnt "$plain" 'REACH'
  hasnt "$plain" 'NATIVE'
  hasnt "$plain" 'HISTORY'
  run "$SCRIPT" --reach
  [ "$status" -eq 1 ]                      # --reach reports; it never changes the exit contract
  [ "$(printf '%s\n' "$output" | grep -v -E '^(REACH|NATIVE|HISTORY)')" = "$plain" ]
}

@test "--reach: a topic cited only by an excluded, unnamed rules file is a dark destination" {
  mkreach
  run "$SCRIPT" --reach
  [ "$status" -eq 0 ]
  row="$(printf '%s\n' "$output" | grep "^REACH store=$SLUG ")"
  has "$row" 'topics=2 hop1=1 excl_bullets=1 excl_only_topics=1 dark_dest=1'
  has "$output" 'REACH-VERDICT dark_dest=1 unknown=0'
}

@test "--reach: the same store with the exclusion lifted is not dark" {
  mkreach
  printf '{"claudeMdExcludes":[],"model":"claude-opus-5-5"}\n' >"$RULES_LOADED_SETTINGS"
  run "$SCRIPT" --reach
  row="$(printf '%s\n' "$output" | grep "^REACH store=$SLUG ")"
  has "$row" 'hop1=2 excl_bullets=0 excl_only_topics=0 dark_dest=0'
  has "$output" 'REACH-VERDICT dark_dest=0 unknown=0'
}

@test "--reach: an excluded file that a delivered file NAMES is not a dark destination" {
  mkreach
  printf 'Situational lessons: agent-operating-lessons-situational.md\n' >>"$PROJ/CLAUDE.md"
  run "$SCRIPT" --reach
  has "$output" 'excl_only_topics=1 dark_dest=0'
  has "$output" 'REACH-VERDICT dark_dest=0'
}

@test "--reach: unreadable settings make dark_dest unknown, never 0" {
  mkreach
  export RULES_LOADED_SETTINGS="$BATS_TEST_TMPDIR/absent.json"
  run "$SCRIPT" --reach
  has "$output" 'dark_dest=?'
  has "$output" 'REACH-VERDICT dark_dest=0 unknown=1'
}

@test "--reach: all-off caches read nondefault=0; one flipped flag reads non-zero" {
  mkreach
  mkcache "$HOME/.claude.json" "$OFF"
  mkcache "$HOME/.claude-next/.claude.json" "$OFF"
  run "$SCRIPT" --reach
  has "$output" "NATIVE root=$HOME/.claude.json quail=false slate=false onyx_enabled=false onyx_available=false moth=false stone=false linen=false haze=false killswitch=0"
  has "$output" 'NATIVE-VERDICT nondefault=0 unknown=0'
  mkcache "$HOME/.claude-next/.claude.json" '{"tengu_passport_quail":true}'
  run "$SCRIPT" --reach
  has "$output" "NATIVE root=$HOME/.claude-next/.claude.json quail=true"
  has "$output" 'NATIVE-VERDICT nondefault=1 unknown=0'
}

@test "--reach: the kill switch fires only when umber_petrel is on AND a listed substring is in the model" {
  mkreach
  mkcache "$HOME/.claude.json" '{"tengu_umber_petrel":true,"tengu_sepia_cormorant":["opus-5"]}'
  run "$SCRIPT" --reach
  has "$output" 'killswitch=1'
  has "$output" 'NATIVE-VERDICT nondefault=1'
  mkcache "$HOME/.claude.json" '{"tengu_umber_petrel":false,"tengu_sepia_cormorant":["opus-5"]}'
  run "$SCRIPT" --reach
  has "$output" 'killswitch=0'
  mkcache "$HOME/.claude.json" '{"tengu_umber_petrel":true,"tengu_sepia_cormorant":["haiku"]}'
  run "$SCRIPT" --reach
  has "$output" 'killswitch=0'
  has "$output" 'NATIVE-VERDICT nondefault=0 unknown=0'
}

@test "--reach: an unreadable cache is status=unreadable and counts as unknown" {
  mkreach
  mkdir -p "$HOME/.claude-tertiary"; printf '{not json' >"$HOME/.claude-tertiary/.claude.json"
  run "$SCRIPT" --reach
  has "$output" "NATIVE root=$HOME/.claude-tertiary/.claude.json status=unreadable"
  has "$output" 'NATIVE-VERDICT nondefault=0 unknown=1'
}

@test "--reach: a store holding .consolidate-lock reads consolidate_lock=1" {
  mkreach
  : >"$STORE/.consolidate-lock"
  run "$SCRIPT" --reach
  has "$output" "NATIVE-STORE store=$SLUG consolidate_lock=1 team_dir=0 logs_dir=0"
  has "$output" 'NATIVE-VERDICT nondefault=1'
}

@test "--reach: a memory_saved transcript newer than the stamp counts once, then not again" {
  mkreach
  mkdir -p "$HOME/.claude/state" "$HOME/.claude/projects/$SLUG"
  touch -t 202601010000 "$HOME/.claude/state/memory-fleet-sweep.native-stamp"
  printf '{"type":"system","subtype":"memory_saved"}\n' >"$HOME/.claude/projects/$SLUG/s.jsonl"
  run "$SCRIPT" --reach
  has "$output" 'NATIVE-TRANSCRIPTS memory_saved_records=1 scanned=1 since=2026-01-01'
  has "$output" 'NATIVE-VERDICT nondefault=1'
  run "$SCRIPT" --reach
  has "$output" 'NATIVE-TRANSCRIPTS memory_saved_records=0 scanned=0'
}

@test "--reach: HISTORY reads the out-of-store gitdir, and says none when there is none" {
  mkreach
  run "$SCRIPT" --reach
  has "$output" "HISTORY store=$SLUG status=none"
  export CC_MEMORY_HISTORY_ROOT="$BATS_TEST_TMPDIR/hist"
  gd="$CC_MEMORY_HISTORY_ROOT/$(cd "$STORE" && pwd -P | tr '/' '-').git"
  git init -q --bare "$gd"
  tree="$(git --git-dir="$gd" mktree </dev/null)"
  c="$(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
       GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git --git-dir="$gd" commit-tree "$tree" -m snap)"
  git --git-dir="$gd" update-ref refs/heads/main "$c"
  run "$SCRIPT" --reach
  row="$(printf '%s\n' "$output" | grep "^HISTORY store=$SLUG ")"
  has "$row" 'age_s='
  has "$row" 'newest_mtime_age_s='
  has "$row" 'behind=1'                    # the store's files are newer than a January snapshot
}

@test "--reach invoked THROUGH a symlink still resolves both libs" {
  mkreach
  mkdir -p "$BATS_TEST_TMPDIR/farm"
  ln -sf "$SCRIPT" "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh"
  run bash "$BATS_TEST_TMPDIR/farm/memory-fleet-sweep.sh" --reach
  [ "$status" -eq 0 ]
  has "$output" 'REACH-VERDICT dark_dest=1'
}
