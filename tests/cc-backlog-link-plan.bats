#!/usr/bin/env bats
# cc-backlog `link --plan` — the BULK form (backlog aee48ef0ffcf).
#
# THE DEFECT. `link <id> --condition <c>` asks the store two whole-ledger questions per row —
# `has_id` over every raw record, then the full `fold` — so applying an N-row grouping plan folded a
# ledger that the plan's own N link records were growing. Measured 2026-08-12 during W2's 418-row
# apply against a ~2400-line store: ~4 s per link at the start, ~20 s per link by the end, and over
# an hour of wall clock to write a single condition field onto 418 rows.
#
# WHAT IS ACTUALLY PINNED HERE, and it is not "the batch is fast". A wall-clock assertion on shared
# CI hardware is a flake generator, so the cost is pinned STRUCTURALLY: a `--plan` apply must fold
# the store a CONSTANT number of times regardless of how many rows it carries. That is the property
# the fix is, it is countable rather than timed, and it reds if anyone re-introduces a per-row fold
# (memory: alarm-polarity-and-attention-budget — a timing assertion that flakes gets muted, and a
# muted assertion defends nothing).
#
# EVERY GUARD IS TESTED THROUGH BOTH FORMS. The two entry points share ONE arbiter (`link_apply`)
# precisely so the single-row rc contract and the batch verdicts cannot drift, and a suite that only
# exercised the new path would pass a refactor that quietly loosened the old one
# (memory: make-the-actuator-the-arbiter).

setup() {
  # Project labels here are FIXTURES, not projects; `add` WARNS on an explicit --project outside the
  # dispatch set and bats folds that into $output. Dispatchability is not this suite's subject —
  # tests/cc-backlog-project-dispatch.bats owns it.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  # $HOME first, then the explicit seams. cc-backlog defaults the ledger, the IDL and the kick
  # marker under $HOME, so an unfixtured suite writes fixture rows into the operator's live autonomy
  # state (memory: unfixtured-sensor-executes-the-deployed-subject).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
}

# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. These return non-zero directly and so fail anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

add() { bash "$CB" add --project P --title "$1" --source "${2:-fx}"; }
# `// ""` is load-bearing: cmd_list RE-OMITS an empty condition, so a bare `.condition` yields null
# and `jq -r` prints the four-character string "null" — non-empty, so every `[ -z ... ]` negative
# would pass vacuously (memory: verification-harness-vacuous-pass-traps).
cond_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|(.condition // "")'; }
# `grep -c` PRINTS 0 and EXITS 1 on no match, so the obvious `|| echo 0` appends a SECOND zero and
# every `-eq` against the result dies with "integer expression expected". cc-backlog's own
# valid_records carries the same warning; this suite paid for it once before reading it.
n_link_records() { c="$(grep -c '"event":"link"' "$CC_BACKLOG_FILE" 2>/dev/null)" || true
                   case "$c" in ''|*[!0-9]*) c=0 ;; esac; printf '%s' "$c"; }
n_lines() { c="$(grep -c '' "$CC_BACKLOG_FILE" 2>/dev/null)" || true
            case "$c" in ''|*[!0-9]*) c=0 ;; esac; printf '%s' "$c"; }

# ── the cost property, pinned structurally ──────────────────────────────────────────────────────

@test "a --plan apply folds the store a CONSTANT number of times, whatever the row count" {
  # THE MEASUREMENT THE ITEM IS ABOUT, made countable. `fold` is a shell function inside cc-backlog,
  # so it cannot be counted from outside — but every fold ends in a `jq -s` over the record stream,
  # and jq is a BINARY on PATH. Shimming jq with a counting wrapper therefore counts the real work
  # without the subject knowing it is observed, and the count is deterministic on any hardware.
  shimdir="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shimdir"
  counter="$BATS_TEST_TMPDIR/jq-calls"
  real_jq="$(command -v jq)"
  cat > "$shimdir/jq" <<SHIM
#!/usr/bin/env bash
printf 'x' >> "$counter"
exec "$real_jq" "\$@"
SHIM
  chmod +x "$shimdir/jq"

  # Ten rows and thirty rows, applied identically. A per-row fold makes the jq count scale with the
  # row count; one fold for the whole plan makes the DIFFERENCE small and bounded.
  for i in $(seq 1 40); do add "cost probe row $i" >/dev/null; done
  ids=()
  while IFS= read -r line; do ids+=("$line"); done < <(bash "$CB" list --all --json | jq -r '.[].id')

  plan10="$BATS_TEST_TMPDIR/plan10"; plan30="$BATS_TEST_TMPDIR/plan30"
  : > "$plan10"; : > "$plan30"
  for i in $(seq 0 9);  do printf '%s cost-probe-small\n' "${ids[$i]}"  >> "$plan10"; done
  for i in $(seq 10 39); do printf '%s cost-probe-large\n' "${ids[$i]}" >> "$plan30"; done

  : > "$counter"
  PATH="$shimdir:$PATH" bash "$CB" link --plan "$plan10" >/dev/null 2>&1
  small=$(wc -c < "$counter")

  : > "$counter"
  PATH="$shimdir:$PATH" bash "$CB" link --plan "$plan30" >/dev/null 2>&1
  large=$(wc -c < "$counter")

  # Both applies actually happened — a shim that broke the subject would make this assertion vacuous.
  [ "$(cond_of "${ids[0]}")"  = "cost-probe-small" ]
  [ "$(cond_of "${ids[39]}")" = "cost-probe-large" ]

  # THE ASSERTION. 3x the rows must not cost 3x the jq invocations. A CEILING rather than an
  # equality: the plan reader and the verdict renderer legitimately grow with plan size in a way a
  # future refactor may shift, while a per-row FOLD would put `large` at or above 3x `small`
  # (memory: exact-count-assertion-tripwires-its-own-subject).
  [ "$large" -lt $(( small * 2 )) ]
}

@test "CONTROL — the per-row form really does pay per row, so the ceiling above is not vacuous" {
  # Without this, a subject whose jq count had become constant for an unrelated reason (say a caching
  # layer) would pass the ceiling above while the defect was untouched. This asserts the OLD shape
  # still has the OLD cost — which is what makes the new shape's flatness meaningful.
  shimdir="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shimdir"
  counter="$BATS_TEST_TMPDIR/jq-calls"
  real_jq="$(command -v jq)"
  cat > "$shimdir/jq" <<SHIM
#!/usr/bin/env bash
printf 'x' >> "$counter"
exec "$real_jq" "\$@"
SHIM
  chmod +x "$shimdir/jq"

  for i in $(seq 1 8); do add "control row $i" >/dev/null; done
  ids=()
  while IFS= read -r line; do ids+=("$line"); done < <(bash "$CB" list --all --json | jq -r '.[].id')

  : > "$counter"
  for i in $(seq 0 1); do
    PATH="$shimdir:$PATH" bash "$CB" link "${ids[$i]}" --condition control-per-row >/dev/null 2>&1
  done
  two=$(wc -c < "$counter")

  : > "$counter"
  for i in $(seq 2 7); do
    PATH="$shimdir:$PATH" bash "$CB" link "${ids[$i]}" --condition control-per-row >/dev/null 2>&1
  done
  six=$(wc -c < "$counter")

  [ "$(cond_of "${ids[7]}")" = "control-per-row" ]
  # 3x the calls costs at least ~3x the jq invocations, because each one re-folds the whole store.
  [ "$six" -ge $(( two * 2 )) ]
}

# ── equivalence: the batch must mean exactly what the loop meant ────────────────────────────────

@test "a batch writes the SAME record shape the per-row form writes" {
  a=$(add "row alpha"); b=$(add "row beta")
  bash "$CB" link "$a" --condition master-shape >/dev/null
  printf '%s master-shape\n' "$b" | bash "$CB" link --plan - >/dev/null 2>&1
  # Same keys, same order, same event — only id and ts may differ.
  single=$(grep '"event":"link"' "$CC_BACKLOG_FILE" | head -1 | jq -Sc 'keys')
  batched=$(grep '"event":"link"' "$CC_BACKLOG_FILE" | tail -1 | jq -Sc 'keys')
  [ "$single" = "$batched" ]
  [ "$(cond_of "$a")" = "master-shape" ]
  [ "$(cond_of "$b")" = "master-shape" ]
}

@test "one row per plan line — a batch never writes a record for a row it did not link" {
  a=$(add "row alpha"); b=$(add "row beta"); c=$(add "row gamma")
  bash "$CB" link "$c" --condition already-there >/dev/null
  before=$(n_link_records)
  printf '%s master-one\n%s master-one\n%s master-one\n' "$a" "$b" "$c" | run bash "$CB" link --plan -
  # c is refused (already conditioned, no --force), so exactly TWO records are appended.
  [ "$(n_link_records)" -eq $(( before + 2 )) ]
  [ "$(cond_of "$c")" = "already-there" ]
}

@test "IDEMPOTENT — re-running the same plan appends nothing" {
  a=$(add "row alpha"); b=$(add "row beta")
  plan="$BATS_TEST_TMPDIR/plan"
  printf '%s master-idem\n%s master-idem\n' "$a" "$b" > "$plan"
  bash "$CB" link --plan "$plan" >/dev/null 2>&1
  settled=$(n_lines)
  run bash "$CB" link --plan "$plan"
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$settled" ]
  [ "$(printf '%s' "$output" | grep -c 'verdict=noop')" -eq 2 ]
}

# ── the two failure classes, and the split between them ─────────────────────────────────────────

@test "a slug carrying a MEASUREMENT refuses the WHOLE plan and writes nothing" {
  # Whole-batch, not per-row: a bad slug is knowable with no reference to the store and will be
  # exactly as wrong on the re-run, so writing the plan's good rows would leave a half-applied plan
  # nobody can tell from a completed one.
  a=$(add "row alpha"); b=$(add "row beta")
  before=$(n_lines)
  run bash -c "printf '%s good-slug\n%s bad-9\n' '$a' '$b' | bash '$CB' link --plan -"
  [ "$status" -eq 2 ]
  [ "$(n_lines)" -eq "$before" ]
  [ -z "$(cond_of "$a")" ]
  [ "$(printf '%s' "$output" | grep -c 'NOTHING written')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'bad-9')" -ge 1 ]
}

@test "the digit ban is the SAME rule the single-row form enforces, not a second copy" {
  # Both forms call valid_condition. If a future edit loosened one, this pair separates.
  a=$(add "row alpha"); b=$(add "row beta")
  run bash "$CB" link "$a" --condition sha-4f2c
  [ "$status" -eq 2 ]
  run bash -c "printf '%s sha-4f2c\n' '$b' | bash '$CB' link --plan -"
  [ "$status" -eq 2 ]
  [ -z "$(cond_of "$a")" ]
  [ -z "$(cond_of "$b")" ]
}

@test "one id asking for TWO conditions refuses the whole plan — order must not decide a group" {
  a=$(add "row alpha")
  before=$(n_lines)
  run bash -c "printf '%s alpha-group\n%s beta-group\n' '$a' '$a' | bash '$CB' link --plan -"
  [ "$status" -eq 2 ]
  [ "$(n_lines)" -eq "$before" ]
  [ -z "$(cond_of "$a")" ]
  [ "$(printf '%s' "$output" | grep -c 'more than one condition')" -ge 1 ]
}

@test "the same id twice on the SAME condition is not a conflict — it collapses" {
  a=$(add "row alpha")
  run bash -c "printf '%s master-dup\n%s master-dup\n' '$a' '$a' | bash '$CB' link --plan -"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$a")" = "master-dup" ]
  [ "$(n_link_records)" -eq 1 ]
}

@test "an unknown id is per-row and NEVER fatal — its siblings still land, rc 5" {
  # A store the whole fleet appends to moves under any pass long enough to need this verb. Failing
  # the batch on one row would make the bulk path unusable on exactly the busy days it exists for.
  a=$(add "row alpha")
  run bash -c "printf 'zzzzzzzzzzzz master-mixed\n%s master-mixed\n' '$a' | bash '$CB' link --plan -"
  [ "$status" -eq 5 ]
  [ "$(cond_of "$a")" = "master-mixed" ]
  [ "$(printf '%s' "$output" | grep -c 'verdict=unknown')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'verdict=link')" -eq 1 ]
}

@test "a row a sibling conditioned first is REFUSED, named, and its siblings still land" {
  a=$(add "row alpha"); b=$(add "row beta")
  bash "$CB" link "$a" --condition sibling-got-here-first >/dev/null
  run bash -c "printf '%s master-mixed\n%s master-mixed\n' '$a' '$b' | bash '$CB' link --plan -"
  [ "$status" -eq 5 ]
  [ "$(cond_of "$a")" = "sibling-got-here-first" ]
  [ "$(cond_of "$b")" = "master-mixed" ]
  [ "$(printf '%s' "$output" | grep -c 'verdict=refused-conditioned')" -eq 1 ]
  # The verdict must name the group the row is ACTUALLY in — a refusal that does not say what it
  # collided with cannot be acted on.
  [ "$(printf '%s' "$output" | grep -c 'was sibling-got-here-first')" -eq 1 ]
}

@test "--force re-keys in a batch exactly as it does per row" {
  a=$(add "row alpha")
  bash "$CB" link "$a" --condition first-group >/dev/null
  run bash -c "printf '%s second-group\n' '$a' | bash '$CB' link --plan - --force"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$a")" = "second-group" ]
  [ "$(grep -c '"force":true' "$CC_BACKLOG_FILE")" -eq 1 ]
}

@test "a link carries NO status arm — a batch cannot open, close or block anything" {
  # The property the CONDITION LEASE rests on, asserted over the bulk path specifically: this is the
  # verb a consolidation wave points at hundreds of live rows at once.
  a=$(add "row alpha"); b=$(add "row beta"); c=$(add "row gamma")
  bash "$CB" claim "$b" --by "$(hostname -s)-$$" >/dev/null
  bash "$CB" block "$c" --needs "an operator step" >/dev/null
  before=$(bash "$CB" list --all --json | jq -Sc 'map({id, status}) | sort_by(.id)')
  printf '%s master-status\n%s master-status\n%s master-status\n' "$a" "$b" "$c" \
    | bash "$CB" link --plan - --force >/dev/null 2>&1
  after=$(bash "$CB" list --all --json | jq -Sc 'map({id, status}) | sort_by(.id)')
  [ "$before" = "$after" ]
  [ "$(cond_of "$c")" = "master-status" ]
}

# ── plan shapes ─────────────────────────────────────────────────────────────────────────────────

@test "both plan shapes are accepted — JSON pairs and '<id> <condition>' lines" {
  # scripts/backlog-consolidation/link.py accepts exactly these two, and a plan file must mean the
  # same thing to both readers or its producer has to know which one will consume it.
  a=$(add "row alpha"); b=$(add "row beta")
  printf '[["%s","master-json"]]' "$a" > "$BATS_TEST_TMPDIR/plan.json"
  run bash "$CB" link --plan "$BATS_TEST_TMPDIR/plan.json"
  [ "$status" -eq 0 ]
  printf '%s master-lines\n' "$b" > "$BATS_TEST_TMPDIR/plan.txt"
  run bash "$CB" link --plan "$BATS_TEST_TMPDIR/plan.txt"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$a")" = "master-json" ]
  [ "$(cond_of "$b")" = "master-lines" ]
}

@test "comments and blank lines are skipped so a plan can be reviewed before it is run" {
  a=$(add "row alpha")
  run bash -c "printf '# the whole wave\n\n%s master-commented   # why this row\n' '$a' | bash '$CB' link --plan -"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$a")" = "master-commented" ]
  [ "$(n_link_records)" -eq 1 ]
}

@test "a malformed line is reported and skipped; the good rows still land" {
  a=$(add "row alpha")
  run bash -c "printf 'lonelytoken\n%s master-partial\n' '$a' | bash '$CB' link --plan -"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$a")" = "master-partial" ]
  [ "$(printf '%s' "$output" | grep -c 'malformed plan line')" -ge 1 ]
}

@test "a plan of ONLY malformed lines refuses (rc 2) — that is a producer bug, not an empty pass" {
  before=$(n_lines)
  run bash -c "printf 'lonelytoken\nanotherlonelytoken\n' | bash '$CB' link --plan -"
  [ "$status" -eq 2 ]
  [ "$(n_lines)" -eq "$before" ]
}

@test "an EMPTY plan is a no-op at rc 0 — a producer that filtered to nothing has done its job" {
  # THE REGRESSION THIS PINS. Refusing an empty plan made scripts/backlog-consolidation/link.py exit
  # 1 on any re-run whose candidate rows were all already conditioned — three suites in
  # tests/backlog-grouping.bats red — because "nothing left to do" is the NORMAL end state of an
  # idempotent writer. Unlike `validated --batch`, an empty pass here erases nothing, so it needs no
  # refusal to stay safe.
  before=$(n_lines)
  run bash -c "printf '' | bash '$CB' link --plan -"
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$before" ]
  run bash -c "printf '# every candidate was already conditioned\n' | bash '$CB' link --plan -"
  [ "$status" -eq 0 ]
  [ "$(n_lines)" -eq "$before" ]
}

@test "a --plan file that does not exist refuses rather than reading an empty plan" {
  run bash "$CB" link --plan "$BATS_TEST_TMPDIR/no-such-plan"
  [ "$status" -eq 2 ]
  [ "$(printf '%s' "$output" | grep -c 'not readable')" -ge 1 ]
}

@test "a JSON plan that is not an array of pairs says so instead of guessing" {
  printf '[{"id":"aaaaaaaaaaaa"}]' > "$BATS_TEST_TMPDIR/bad.json"
  run bash "$CB" link --plan "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -eq 2 ]
  [ "$(printf '%s' "$output" | grep -c 'array of \[id, condition\] pairs')" -ge 1 ]
}

# ── the parser seam ─────────────────────────────────────────────────────────────────────────────

@test "--plan and a positional <id> together refuse — two sources of ids is the defect" {
  a=$(add "row alpha")
  run bash -c "printf '%s master-one\n' '$a' | bash '$CB' link '$a' --plan -"
  [ "$status" -eq 2 ]
  [ -z "$(cond_of "$a")" ]
}

@test "--plan with --condition refuses — each plan row names its own" {
  a=$(add "row alpha")
  run bash -c "printf '%s master-one\n' '$a' | bash '$CB' link --plan - --condition master-two"
  [ "$status" -eq 2 ]
  [ -z "$(cond_of "$a")" ]
}

@test "the single-row form keeps its rc contract exactly — 0 / 2 / 3 / 4 and it echoes the id" {
  # The arbiter refactor moved these rc values behind a shared writer. They are a published contract
  # (scripts/backlog-consolidation/link.py, cmd_backfill and cmd_dups all read them), so they are
  # pinned here as a group rather than trusted to survive.
  a=$(add "row alpha")
  run bash "$CB" link "$a" --condition master-rc
  [ "$status" -eq 0 ]
  [ "$output" = "$a" ]
  run bash "$CB" link "$a" --condition master-rc          # idempotent, still echoes
  [ "$status" -eq 0 ]
  [ "$output" = "$a" ]
  run bash "$CB" link "$a" --condition master-other       # re-key without --force
  [ "$status" -eq 4 ]
  run bash "$CB" link zzzzzzzzzzzz --condition master-rc  # unknown id
  [ "$status" -eq 3 ]
  run bash "$CB" link "$a" --condition sha-99             # unstable slug
  [ "$status" -eq 2 ]
  run bash "$CB" link                                     # no id at all
  [ "$status" -eq 2 ]
  [ "$(printf '%s' "$output" | grep -c -- '--plan')" -ge 1 ]
  run bash "$CB" link "$a" --nonsense
  [ "$status" -eq 2 ]
}

@test "an unknown id writes NOTHING — the batch does not mint rows it was handed" {
  before=$(n_lines)
  run bash -c "printf 'zzzzzzzzzzzz master-ghost\n' | bash '$CB' link --plan -"
  [ "$status" -eq 5 ]
  [ "$(n_lines)" -eq "$before" ]
  [ "$(bash "$CB" list --all --json | jq 'length')" -eq 0 ]
}
