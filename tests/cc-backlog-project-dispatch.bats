#!/usr/bin/env bats
# cc-backlog add — EXPLICIT --project validated against the dispatch set (backlog df2b6a40a5dc).
#
# project_default() refuses a label that names no project, but only when --project is ABSENT. An
# explicit label reaches the store having passed through none of those normalizations, so
# `--project reso` (2026-08-07; ~/Development/reso does not exist, the project is
# reso-management-app) minted an item that was journalled {verdict:"skip",
# reason:"project-not-dispatched"} on every dispatch pass until a human migrated it by hand.
#
# The contract under test, in both directions:
#   WARN  — an explicit label outside scripts/dispatch-projects.conf's dispatch set says so, loudly,
#           on stderr, and names the nearest dispatchable label.
#   NEVER REFUSE — the item is still filed, rc is still 0, and the id is still the ONLY thing on
#           stdout, because the ledger is shared and a new project must stay fileable.
#
# Hermetic: HOME, the ledger, the IDL and the conf are all fixtures under $BATS_TEST_TMPDIR, so the
# suite never reads the operator's live ledger and never depends on today's real conf — EXCEPT the
# two production-path tests at the bottom, which exist precisely to prove the unfixtured default
# resolves (a validator that silently validates nothing is the defect, not the fix).

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # A fixture dispatch set, not the live one: this suite tests the VALIDATOR, and pinning it to
  # today's real rows would make it go red the day a project is promoted or retired.
  CONF="$BATS_TEST_TMPDIR/dispatch-projects.conf"
  export CC_DISPATCH_PROJECTS_CONF="$CONF"
  cat > "$CONF" <<'EOF'
# fixture dispatch set
claude-infrastructure  repo=~/Development/claude-infrastructure
widget-app             repo=~/Development/widget-app   # inline comment, stripped
half-declared          repo=
widget-qa              skip=no open items; repo present if promoted
wt-closeout            skip=NOT a project — a worktree basename
EOF
  # Both levers are pinned DETERMINISTICALLY rather than inherited (hermeticity rule 6). The
  # warn switch matters most: a shell that exported CC_BACKLOG_PROJECT_WARN=off would turn every
  # assertion below vacuously green — a suite that cannot fail is the one shape this file must not
  # have, since it is the only place the validator is exercised at all.
  export CC_BACKLOG_PROJECT_WARN=on
  unset CC_DISPATCH_PROJECT
}

# The id is a 12-hex event key. Asserting the SHAPE (not merely non-emptiness) is what catches a
# warning that leaked onto stdout: a polluted capture is still non-empty.
is_id() { printf '%s' "$1" | grep -qE '^[0-9a-f]{12}$'; }

@test "an explicit --project outside the dispatch set WARNS — and still files the item" {
  run --separate-stderr bash "$CB" add --project brand-new-thing --title "wire it" --source t
  [ "$status" -eq 0 ]
  is_id "$output"
  [[ "$stderr" == *"WARNING"* ]] || { echo "no warning: $stderr"; return 1; }
  [[ "$stderr" == *"brand-new-thing"* ]] || return 1
  [[ "$stderr" == *"not in the dispatch set"* ]] || return 1
  [[ "$stderr" == *"project-not-dispatched"* ]] || return 1
  # NOT a refusal: the row is really in the ledger and really open.
  [ "$(jq -s --arg i "$output" '[.[]|select(.id==$i and .event=="add")]|length' "$CC_BACKLOG_FILE")" -eq 1 ]
  run bash "$CB" list --open
  [ "$status" -eq 0 ]
  [[ "$output" == *"brand-new-thing"* ]] || return 1
}

@test "the id is the ONLY thing on stdout — the warning cannot corrupt id=\$(cc-backlog add …)" {
  run --separate-stderr bash "$CB" add --project brand-new-thing --title "capture me" --source t
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  is_id "$output"
  [ -n "$stderr" ]                      # the diagnosis exists — it is simply not on stdout
}

@test "a DISPATCHABLE project is silent — the conf is the predicate, not the presence of --project" {
  run --separate-stderr bash "$CB" add --project widget-app --title "real work" --source t
  [ "$status" -eq 0 ]
  is_id "$output"
  [ -z "$stderr" ] || { echo "unexpected stderr: $stderr"; return 1; }
}

@test "a repo= row with an EMPTY value is not a declaration — it warns like an undeclared label" {
  run --separate-stderr bash "$CB" add --project half-declared --title "empty verb" --source t
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not in the dispatch set"* ]] || return 1
}

@test "a skip= row reports its DECLARED reason and the promote move, not add-a-row advice" {
  run --separate-stderr bash "$CB" add --project wt-closeout --title "worktree label" --source t
  [ "$status" -eq 0 ]
  is_id "$output"
  [[ "$stderr" == *"declared NOT DISPATCHED"* ]] || return 1
  [[ "$stderr" == *"a worktree basename"* ]] || return 1     # the conf's own words, not a paraphrase
  [[ "$stderr" == *"promote its row"* ]] || return 1
  # The row already exists, so telling its author to add one would be advice they cannot follow.
  [ "$(printf '%s' "$stderr" | grep -c 'Declare it in')" -eq 0 ]
}

@test "did-you-mean names the nearest DISPATCHABLE label, and never a skip row" {
  run --separate-stderr bash "$CB" add --project widget --title "the alias shape" --source t
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Did you mean"* ]] || { echo "no suggestion: $stderr"; return 1; }
  [[ "$stderr" == *"widget-app"* ]] || return 1
  # widget-qa shares the prefix but is declared skip= — suggesting it would be advice to file into
  # a second dead label.
  [ "$(printf '%s' "$stderr" | grep -c 'widget-qa')" -eq 0 ]
}

@test "an unrelated label gets no suggestion — the hint is a near-miss, not noise" {
  run --separate-stderr bash "$CB" add --project zzz-unrelated --title "no near miss" --source t
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$stderr" | grep -c 'Did you mean')" -eq 0 ]
  [[ "$stderr" == *"WARNING"* ]] || return 1     # still warned — only the hint is absent
}

@test "CC_DISPATCH_PROJECT is unioned in, exactly as cc-dispatch unions it" {
  CC_DISPATCH_PROJECT="pinned-project" run --separate-stderr \
    bash "$CB" add --project pinned-project --title "pinned" --source t
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "warned about the PINNED project: $stderr"; return 1; }
  # list-tolerant, same as the dispatcher's own parse
  CC_DISPATCH_PROJECT="a-one,pinned-two b-three" run --separate-stderr \
    bash "$CB" add --project pinned-two --title "pinned in a list" --source t
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "warned about a listed pin: $stderr"; return 1; }
}

@test "no readable conf validates NOTHING and says nothing" {
  CC_DISPATCH_PROJECTS_CONF="$BATS_TEST_TMPDIR/absent.conf" run --separate-stderr \
    bash "$CB" add --project brand-new-thing --title "no conf" --source t
  [ "$status" -eq 0 ]
  is_id "$output"
  [ -z "$stderr" ] || { echo "guessed without a conf: $stderr"; return 1; }
}

@test "CC_BACKLOG_PROJECT_WARN=off is the opt-out" {
  CC_BACKLOG_PROJECT_WARN=off run --separate-stderr \
    bash "$CB" add --project brand-new-thing --title "silenced" --source t
  [ "$status" -eq 0 ]
  is_id "$output"
  [ -z "$stderr" ] || { echo "opt-out ignored: $stderr"; return 1; }
}

@test "the DEFAULT path is untouched — no --project still resolves and still says nothing" {
  d="$BATS_TEST_TMPDIR/not-a-declared-project-9f2"
  mkdir -p "$d"
  git -C "$d" init -q
  run --separate-stderr bash -c "cd '$d' && bash '$CB' add --title 'default path' --source t"
  [ "$status" -eq 0 ]
  is_id "$output"
  [ -z "$stderr" ] || { echo "warned on the default path: $stderr"; return 1; }
  [ "$(jq -s '[.[]|select(.event=="add")]|.[0].project' "$CC_BACKLOG_FILE" | tr -d '"')" \
      = "not-a-declared-project-9f2" ]
}

@test "the warning fires on the IDEMPOTENT re-add too — a re-file is as undrainable as the first" {
  first="$(bash "$CB" add --project brand-new-thing --title "same event" --source t 2>/dev/null)"
  run --separate-stderr bash "$CB" add --project brand-new-thing --title "same event" --source t
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]                       # still idempotent
  [[ "$stderr" == *"WARNING"* ]] || return 1
}

@test "needs --project inherits the same validation (one add path, one validator)" {
  run --separate-stderr bash "$CB" needs "flip the switch" --project brand-new-thing
  [ "$status" -eq 0 ]
  is_id "$output"
  [[ "$stderr" == *"not in the dispatch set"* ]] || return 1
}

# ── the PRODUCTION path: no env override, and reached through a symlink ────────────────────────
# Production invokes this as $HOME/.claude/bin/cc-backlog, a symlink into the checkout. A
# dirname($0)-relative read would look in ~/.claude/scripts/, where a new file is absent until the
# converger runs — i.e. the validator would resolve no conf and silently validate nothing. These two
# run against the REAL scripts/dispatch-projects.conf, and they assert only what that file's own
# header guarantees forever (the incumbent is always in the set), never a row that may be retired.

@test "the real conf resolves with no override — an undeclarable label warns" {
  unset CC_DISPATCH_PROJECTS_CONF
  run --separate-stderr bash "$CB" add --project zz-not-a-real-project --title "prod path" --source t
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not in the dispatch set"* ]] || { echo "real conf not found: $stderr"; return 1; }
  # …and the incumbent, which scripts/dispatch-projects.conf guarantees is always dispatchable.
  run --separate-stderr bash "$CB" add --project claude-infrastructure --title "prod ok" --source t
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "warned about the incumbent: $stderr"; return 1; }
}

@test "a SYMLINKED invocation resolves the checkout's conf, not the symlink's own dirname" {
  unset CC_DISPATCH_PROJECTS_CONF
  mkdir -p "$BATS_TEST_TMPDIR/deployed/bin" "$BATS_TEST_TMPDIR/deployed/scripts"
  ln -s "$CB" "$BATS_TEST_TMPDIR/deployed/bin/cc-backlog"
  run --separate-stderr bash "$BATS_TEST_TMPDIR/deployed/bin/cc-backlog" \
    add --project zz-not-a-real-project --title "through the link" --source t
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not in the dispatch set"* ]] || { echo "conf lost across the symlink: $stderr"; return 1; }
}
