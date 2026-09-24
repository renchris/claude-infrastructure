#!/usr/bin/env bats
# rules-hook-budget-lint.sh — the always-loaded rules file must stay a HOOK tier.
#
# Each case is red-proved: the fixture it uses fails on a lint mutated to drop that arm. The
# NON-VERDICT arm matters most — a lint whose anchor stops matching must say so rather than
# report a clean file, because a silent 0 here is a permanently un-gated always-loaded surface.

setup() {
  # Hermetic: the lint reads only the file it is given, but a suite that leaves $HOME ambient
  # can never PROVE that — and two concurrent runs would share the operator's live ~/.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/rules-hook-budget-lint.sh"
  TMP="$BATS_TEST_TMPDIR"
}

@test "selftest passes and exercises all four arms" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"PASS (4 arms)"* ]] || false
}

@test "a well-formed hook is clean" {
  printf '# r\n\n- [Ok](../../docs/lessons/a.md) — a hook that states its rule.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"clean"* ]] || false
}

@test "a bodyless bullet is REFUSED and its line is named" {
  printf '# r\n\n- [Ok](../../docs/lessons/a.md) — fine.\n- [Bad](.) — pasted whole.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *":4: BODYLESS"* ]] || false
}

@test "an over-budget bullet is REFUSED and its size is named" {
  { printf '# r\n\n- [Fat](../../docs/lessons/b.md) — '
    awk 'BEGIN{for(i=0;i<500;i++)printf "x"}'; printf '\n'; } > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"OVER BUDGET"* ]] || false
}

@test "a file the anchor cannot parse is a NON-VERDICT, never a pass" {
  printf '# r\n\nprose only, no bullets\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"NON-VERDICT"* ]] || false
}

@test "a missing file is a NON-VERDICT, never a pass" {
  run "$LINT" --file "$TMP/does-not-exist.md"
  [ "$status" -eq 2 ] || false
}

@test "prose bullets and the header are not judged as lessons" {
  printf '# r\n\nsome header prose that is very long %s\n\n- [Ok](../../docs/lessons/a.md) — fine.\n' \
    "$(awk 'BEGIN{for(i=0;i<600;i++)printf "y"}')" > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
}

# The live file must remain PARSEABLE, not globally clean. Asserting cleanliness here would
# contradict the own-scope design one screen down: the gate blocks only on lines a land ADDS, so a
# pre-existing bodyless bullet is legitimate and persistent by construction. That assertion was
# tried and it went red the moment a sibling landed an untiered lesson onto trunk while this branch
# was gating — a content event in someone else's diff, surfacing as a failure in this suite. What
# genuinely must never happen is the anchor drifting off the file's bullet shape, because a lint
# that parses 0 bullets would silently un-gate an always-loaded surface while reporting success.
# rc 2 is the only forbidden answer; 0 and 1 are both real verdicts.
@test "the live rules file still PARSES — rc 2 would mean the anchor has drifted" {
  run "$LINT" --file "$REPO/.claude/rules/agent-operating-lessons.md"
  [ "$status" -ne 2 ] || false
  [[ "$output" != *"NON-VERDICT"* ]] || false
  [[ "$output" == *"bullet(s)"* ]] || false
}

# -- own-scope: block on what THIS land added, report the rest ------------------------------------
# Fixture is a real two-commit repo: the BASE already carries a sibling bodyless bullet, HEAD adds
# one of our own. Without --own-range both are blocking; with it, only ours is. This is the case the
# lint's first live run got wrong, so it is pinned. Identity is passed transiently (git -c ...) so
# it can never persist into a shared .git/config.
_own_fixture() {  # -> echoes the repo dir
  local d="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$d/.claude/rules"
  git -C "$BATS_TEST_TMPDIR/repo" init -q
  printf '# r\n\n- [Sib](.) - a sibling bullet already on the base.\n' > "$d/.claude/rules/x.md"
  git -C "$BATS_TEST_TMPDIR/repo" add -A
  git -C "$BATS_TEST_TMPDIR/repo" -c user.email=t@t -c user.name=t commit -qm base
  printf '# r\n\n- [Sib](.) - a sibling bullet already on the base.\n- [Mine](.) - added by this land.\n' > "$d/.claude/rules/x.md"
  git -C "$BATS_TEST_TMPDIR/repo" add -A
  git -C "$BATS_TEST_TMPDIR/repo" -c user.email=t@t -c user.name=t commit -qm head
  echo "$d"
}

@test "without --own-range both the sibling and our bullet block" {
  d="$(_own_fixture)"
  run "$LINT" --file "$d/.claude/rules/x.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"bodyless=2"* ]] || false
}

@test "with --own-range only OUR added line blocks; the sibling is advisory" {
  d="$(_own_fixture)"
  cd "$d"
  run "$LINT" --file ".claude/rules/x.md" --own-range "HEAD~1..HEAD"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"bodyless=1"* ]] || false
  [[ "$output" == *"advisory: "* ]] || false
}

@test "a land that adds NOTHING to the file is not convicted for the sibling bullet" {
  d="$(_own_fixture)"
  cd "$d"
  run "$LINT" --file ".claude/rules/x.md" --own-range "HEAD..HEAD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"advisory"* ]] || false
}

@test "an unreadable range is a NON-VERDICT, never an all-advisory pass" {
  printf '# r\n\n- [Bad](.) - x.\n' > "$TMP/f.md"
  cd "$TMP"
  run "$LINT" --file "f.md" --own-range "no-such-ref..HEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"NON-VERDICT"* ]] || false
}

# -- duplicate link targets: one rule resident twice -----------------------------------------------
# Found live, twice over: a rebase re-introduced three already-tiered lessons, and one pair predated
# the land. Always blocking (never own-scoped) because a duplicate is a property of the PAIR.
@test "two bullets linking one body are REFUSED" {
  printf '# r\n\n- [A](../../docs/lessons/x.md) - one.\n- [B](../../docs/lessons/x.md) - two.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"DUPLICATE"* ]] || false
}

@test "distinct bodies are not flagged as duplicates" {
  printf '# r\n\n- [A](../../docs/lessons/x.md) - one.\n- [B](../../docs/lessons/y.md) - two.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 0 ] || false
}

# The tally line is what a reader acts on, and it used to attribute DUPLICATE findings to the
# over-budget bucket (`over=$((over+1))` in the duplicate arm), sending them hunting for long
# bullets that do not exist. Found live 2026-09-18 on the failed chore/rules-lesson-tiering ref,
# whose own file lints as 5 bodyless + 4 duplicates and reported `bodyless=5 over-budget=4` with
# zero bullets actually over budget. The per-finding lines were always right; only the tally lied.
@test "the tally counts duplicates as duplicates, not as over-budget" {
  printf '# r\n\n- [A](../../docs/lessons/x.md) - one.\n- [B](../../docs/lessons/x.md) - two.\n' > "$TMP/f.md"
  run "$LINT" --file "$TMP/f.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"duplicate=1"* ]] || false
  [[ "$output" == *"over-budget=0"* ]] || false
}

# -- two files since the 2026-09-23 split (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md)
# With no --file the lint judges the resident file AND agent-operating-lessons-situational.md, and
# flags a body linked from both, which neither per-file scan can see.
_split_fixture() {  # _split_fixture <situational-body> -> echoes the dir
  local d="$BATS_TEST_TMPDIR/split"; mkdir -p "$d/.claude/rules"
  printf '# r\n\n- [A](../../docs/lessons/a.md) — rule a.\n' > "$d/.claude/rules/agent-operating-lessons.md"
  [ -n "$1" ] && printf '%b' "$1" > "$d/.claude/rules/agent-operating-lessons-situational.md"
  echo "$d"
}

@test "no --file lints both files" {
  d="$(_split_fixture '# s\n\n- [B](../../docs/lessons/b.md) — rule b.\n')"
  cd "$d"; run "$LINT"
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | grep -c 'clean — 1 bullet')" -eq 2 ] || false
}

@test "no --file: a bodyless bullet in the situational file is REFUSED" {
  d="$(_split_fixture '# s\n\n- [B](.) — pasted whole.\n')"
  cd "$d"; run "$LINT"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"agent-operating-lessons-situational.md:3: BODYLESS"* ]] || false
}

@test "no --file: one body linked from both files is a DUPLICATE" {
  d="$(_split_fixture '# s\n\n- [A2](../../docs/lessons/a.md) — rule a again.\n')"
  cd "$d"; run "$LINT"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"both files link ../../docs/lessons/a.md"* ]] || false
}

@test "no --file: a project without the situational file lints the one file" {
  d="$(_split_fixture '')"
  cd "$d"; run "$LINT"
  [ "$status" -eq 0 ] || false
}

@test "the live situational file still PARSES" {
  run "$LINT" --file "$REPO/.claude/rules/agent-operating-lessons-situational.md"
  [ "$status" -ne 2 ] || false
  [[ "$output" == *"bullet(s)"* ]] || false
}

# -- the land's own invocation: --file per changed half (ship-land.sh, rules_own loop) ----------
# The cross-file arm must run there too, or a rebase through `merge=union` that copies the
# original's tail back into the resident file lands clean
# (docs/research/token-efficiency-2026-09-23/implement/F4-project-rules-split.review.md, major 1-2).
@test "--file on the resident half: a body linked from both files is a DUPLICATE" {
  d="$(_split_fixture '# s\n\n- [A2](../../docs/lessons/a.md) — rule a again.\n')"
  cd "$d"; run "$LINT" --file .claude/rules/agent-operating-lessons.md
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"both files link ../../docs/lessons/a.md"* ]] || false
}

@test "--file on the situational half: a body linked from both files is a DUPLICATE" {
  d="$(_split_fixture '# s\n\n- [A2](../../docs/lessons/a.md) — rule a again.\n')"
  run "$LINT" --file "$d/.claude/rules/agent-operating-lessons-situational.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"both files link ../../docs/lessons/a.md"* ]] || false
}

@test "--file: an unlinked bullet line in both files is a DUPLICATE, indentation ignored" {
  d="$(_split_fixture '# s\n\n- [B](../../docs/lessons/b.md) — rule b.\n  - demoted pointer x.md — kept.\n')"
  printf -- '- demoted pointer x.md — kept.\n' >> "$d/.claude/rules/agent-operating-lessons.md"
  run "$LINT" --file "$d/.claude/rules/agent-operating-lessons.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"this line is in both files: - demoted pointer x.md"* ]] || false
}

@test "--file: distinct halves are clean" {
  d="$(_split_fixture '# s\n\n- [B](../../docs/lessons/b.md) — rule b.\n')"
  run "$LINT" --file "$d/.claude/rules/agent-operating-lessons.md"
  [ "$status" -eq 0 ] || false
}

# -- resident adds: new lessons go to the situational half ----------------------------------------
# A real two-commit repo. The base is a split pair; $1 is a shell snippet run in the repo to make
# the head commit.
_resident_fixture() {
  local d="$BATS_TEST_TMPDIR/radd"; mkdir -p "$d/.claude/rules"
  git -C "$d" init -q
  printf '# r\n\n- [A](../../docs/lessons/a.md) — rule a.\n' > "$d/.claude/rules/agent-operating-lessons.md"
  printf '# s\n\n- [B](../../docs/lessons/b.md) — rule b.\n  - `c.md` — nested c.\n' \
    > "$d/.claude/rules/agent-operating-lessons-situational.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -qm base
  (cd "$d" && eval "$1")
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -qm head
  echo "$d"
}
R_=.claude/rules/agent-operating-lessons.md
S_=.claude/rules/agent-operating-lessons-situational.md

@test "--own-range: a new bullet added to the resident file is REFUSED" {
  d="$(_resident_fixture "printf -- '- [N](../../docs/lessons/n.md) — new.\n' >> $R_")"
  cd "$d"; run "$LINT" --file "$R_" --own-range HEAD~1..HEAD
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"RESIDENT ADD"*"- [N](../../docs/lessons/n.md)"* ]] || false
}

@test "--own-range: RULES_RESIDENT_ADD_OK=1 turns a resident add advisory" {
  d="$(_resident_fixture "printf -- '- [N](../../docs/lessons/n.md) — new.\n' >> $R_")"
  cd "$d"; RULES_RESIDENT_ADD_OK=1 run "$LINT" --file "$R_" --own-range HEAD~1..HEAD
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"advisory: "*"RESIDENT ADD"* ]] || false
}

@test "--own-range: a bullet moved or re-indented into the resident file is not an add" {
  d="$(_resident_fixture "printf '# s\n\n' > $S_; printf -- '- [B](../../docs/lessons/b.md) — rule b.\n- \`c.md\` — nested c.\n' >> $R_")"
  cd "$d"; run "$LINT" --file "$R_" --own-range HEAD~1..HEAD
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"RESIDENT ADD"* ]] || false
}

@test "--own-range: a new bullet in the situational file is not a resident add" {
  d="$(_resident_fixture "printf -- '- [N](../../docs/lessons/n.md) — new.\n' >> $S_")"
  cd "$d"; run "$LINT" --file "$S_" --own-range HEAD~1..HEAD
  [ "$status" -eq 0 ] || false
  cd "$d"; run "$LINT" --file "$R_" --own-range HEAD~1..HEAD
  [ "$status" -eq 0 ] || false
}
