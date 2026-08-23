#!/bin/bash
# backlog-handback.sh — carry a ledger VERDICT home from a venue that cannot write the ledger.
#
#   scripts/backlog-handback.sh record <id> --verb done  --evidence "<sha…>" [--project P] [--note N]
#   scripts/backlog-handback.sh record <id> --verb block --needs "<the exact operator step>" […]
#   scripts/backlog-handback.sh list [--json]
#   scripts/backlog-handback.sh render
#   CONFIRM=1 scripts/backlog-handback.sh apply [--dry-run]
#   scripts/backlog-handback.sh --selftest
#
# ── WHY THIS EXISTS: A ROW THAT CANNOT BE CLOSED IS A ROW THAT RE-DISPATCHES FOREVER ─────────────
# The work ledger lives at ~/.claude/autonomy/backlog.jsonl, on the operator's box and nowhere else.
# A cloud Claude Code VM has no ~/.claude, so EVERY terminal verb it owes the ledger — `done` after
# it finished the work, `block` to park an operator-gated row OUT of the wave — returns `unknown id`
# there. cc-notify is `unresolvable` for the same reason. A cloud worker can therefore record NO
# verdict at all: it can only leave prose in a plan doc and hope a human transcribes it.
#
# Measured, on one row: backlog `354c73ebd400` (ship-land BRANCH / postland bisect) had its cure
# LANDED on 2026-08-16/17 (`6ce67de9`, plus the bisect floor proof at postland-verify.sh:2137). It
# was then dispatched a SECOND time on 2026-08-19 and re-confirmed done, and a THIRD time on
# 2026-08-23 and re-confirmed done again — three worker slots spent re-deriving one already-landed
# answer, because the close verb cannot run at the venue the row is dispatched to. Both earlier
# passes named the missing piece in the same words ("until a hand-back exists…") and neither could
# build one from inside the loop. This is that piece.
#
# It is the same shape as scripts/offbox-green-pull.sh, in the opposite direction and one step
# weaker: a verdict nobody transports is a verdict nobody enforces (memory:
# conclusion-must-reach-the-enforcing-store). That script PULLS a GitHub verdict onto the box; this
# one lets an off-box worker PUSH a ledger verdict into the only channel the two venues share.
#
# ── THE CHANNEL IS GIT, BECAUSE GIT IS THE ONLY CHANNEL THEY SHARE ───────────────────────────────
# A cloud VM and the box have no mailbox, no socket, no filesystem and no `gh` in common. They have
# exactly one: the cloud VM pushes a `claude/*` branch and scripts/cloud-reconcile.sh lands it. So
# the record rides IN THE REPO — one JSON file per record under autonomy/handback/ — and arrives on
# the box by the same land that brings the work home. That also means the transport cannot silently
# fail while the work succeeds: the record and the diff are the same commit.
#
# ONE FILE PER RECORD, never an append-only file in the repo. Two cloud workers on two branches
# appending to one tracked JSONL is a merge conflict on every land — the transport would break
# exactly when the fleet is busiest. Distinct filenames never conflict.
#
# ── WHAT THIS MAY DO TO THE LEDGER, STATED AS A CEILING ──────────────────────────────────────────
# A record is data written at another venue. It is treated as untrusted input, and the ceiling on
# what it can do is enforced here rather than described:
#
#   1. IT CAN NEVER CREATE A ROW. There is no `add` verb and an id absent from the ledger is
#      REPORTED (state UNKNOWN), never filed. The transport can only ever advance a row the box
#      already knows about, so a malicious or malformed record cannot inject work into the wave.
#   2. TWO VERBS ONLY — `done` and `block`. Those are the two verdicts a worker owes and cannot
#      record; every other verb (add/reopen/claim/venue/…) is refused at parse time. A narrow
#      surface is the whole security argument, so it is a whitelist, not a blacklist.
#   3. NO eval, EVER. Records are parsed with jq and every field is validated against a pattern
#      before use; the payload reaches cc-backlog as argv, never as shell text. (A declaration
#      store read with `eval` is an injection seam — cloud-reconcile.sh:36 pays for the same rule.)
#   4. APPLY IS DEFAULT-OFF. `apply` refuses without CONFIRM=1, the repo's dominant convention.
#      `list` / `render` are read-only and always allowed. So the unattended path can SURFACE a
#      pending verdict but can never spend it — a false `done` from a bad record costs a glance,
#      not a closed row.
#
# ── "CANNOT FOLD" IS NEVER "NOTHING PENDING" ─────────────────────────────────────────────────────
# `cc-backlog list --all --json` prints `[]` rc 0 against a MISSING ledger, which is byte-identical
# to an empty one. Reading that as "no such row" would make every record on a cloud VM report
# UNKNOWN — a sensor failure wearing an answer's clothes (memory:
# sensor-default-off-makes-blindness-the-shipping-path). So the ledger FILE is probed directly: no
# file ⇒ state NO-LEDGER on every record, `apply` refuses (exit 65), and the count of pending
# records is reported as unknown rather than zero.
#
# ── RECORDS ARE EVIDENCE, SO THEY ARE APPEND-ONLY ────────────────────────────────────────────────
# An applied record is NOT deleted. `list` stops reporting it because the ledger fold now agrees
# with it (state APPLIED), which is a stronger statement than its absence would be: the file is the
# receipt that this venue asserted the verdict, and the ledger is the proof the box accepted it.
# `record` is idempotent on (id, verb, payload) — a fourth dispatch of an already-recorded row
# re-uses the existing file instead of littering the store.
#
# EXITS. 0 ok · 64 usage · 65 refusal (no CONFIRM · apply with no foldable ledger) ·
#   66 at least one record in the store is malformed (reported, never silently skipped) ·
#   70 at least one apply failed.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO_DIR="${CC_HANDBACK_REPO:-$(cd "$(dirname "$SELF")/.." && pwd)}"
STORE="${CC_HANDBACK_DIR:-$REPO_DIR/autonomy/handback}"
LEDGER="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
CB="${CC_BACKLOG_BIN:-$REPO_DIR/bin/cc-backlog}"
JQ="${CC_HANDBACK_JQ:-jq}"
# Fixed by the caller ONLY in the selftest, so a record's timestamp is reproducible there. Real
# invocations always stamp now.
NOW="${CC_HANDBACK_NOW:-}"

say()  { printf 'handback: %s\n' "$1"; }
warn() { printf 'handback: %s\n' "$1" >&2; }
die()  { printf '!! handback: %s\n' "$2" >&2; exit "$1"; }
usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

# ── validation ───────────────────────────────────────────────────────────────────────────────────
# Every one of these guards a value that came from ANOTHER VENUE. They are checked on the way IN
# (record) and again on the way OUT (list/apply), because the file between them is a git artifact
# that a later commit can edit without ever going through `record`.
valid_id()   { [[ "$1" =~ ^[0-9a-f]{6,40}$ ]]; }
valid_verb() { [[ "$1" = "done" || "$1" = "block" ]]; }
# Printable, single line, bounded. `evidence` carries shas and `needs` carries an operator step, so
# both are prose — but a control character or a newline in either would corrupt the readout that
# renders them, and a 4 KB one would bury it.
valid_text() { [[ ${#1} -le 500 ]] && [[ "$1" != *$'\n'* ]] && [[ "$1" != *$'\r'* ]] && [[ "$1" != *$'\t'* ]]; }

now_stamp() { [ -n "$NOW" ] && { printf '%s' "$NOW"; return 0; }; date -u +%Y-%m-%dT%H:%M:%SZ; }

have_jq() { command -v "$JQ" >/dev/null 2>&1; }

# ── the fold oracle ──────────────────────────────────────────────────────────────────────────────
# LEDGER_JSON holds `cc-backlog list --all --json`; LEDGER_OK=1 iff it could be read at all.
LEDGER_JSON="[]"; LEDGER_OK=0
load_ledger() {
  LEDGER_OK=0; LEDGER_JSON="[]"
  [ -f "$LEDGER" ] || return 1          # the cloud case — see "CANNOT FOLD" above
  [ -x "$CB" ] || command -v "$CB" >/dev/null 2>&1 || return 1
  local out; out="$("$CB" list --all --json 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out" | "$JQ" -e 'type == "array"' >/dev/null 2>&1 || return 1
  LEDGER_JSON="$out"; LEDGER_OK=1; return 0
}

row_field() {  # <id> <field> → value, empty when the id is not in the ledger
  # Every single-quoted block below is a jq PROGRAM, not shell: `$i` / `$f` are jq's own `--arg`
  # bindings and must reach jq unexpanded. Double-quoting them is what SC2016 asks for and is
  # exactly the injection seam this script refuses to have.
  # shellcheck disable=SC2016
  printf '%s' "$LEDGER_JSON" \
    | "$JQ" -r --arg i "$1" --arg f "$2" 'map(select(.id == $i)) | if length == 0 then "" else (.[0][$f] // "" | tostring) end' 2>/dev/null
}

record_state() {  # <id> <verb> → NO-LEDGER | UNKNOWN | APPLIED | PENDING
  [ "$LEDGER_OK" = 1 ] || { printf 'NO-LEDGER'; return 0; }
  local st; st="$(row_field "$1" status)"
  [ -n "$st" ] || { printf 'UNKNOWN'; return 0; }
  case "$2" in
    # `wasDone` is the DONE LATCH — the field cc-dispatch reads to keep a finished row out of the
    # wave. It is what this whole transport exists to set, so it, not the momentary status, is what
    # says the verdict arrived: a row reopened after a done still carries it.
    done)  [ "$(row_field "$1" wasDone)" = "true" ] && printf 'APPLIED' || printf 'PENDING' ;;
    block) [ "$st" = "blocked" ] && printf 'APPLIED' || printf 'PENDING' ;;
  esac
}

# ── store iteration ──────────────────────────────────────────────────────────────────────────────
# Sets R_ID R_VERB R_EVIDENCE R_NEEDS. → 0 ok · 1 malformed (reported, never silently skipped).
# Only the four fields the reader ACTS on are parsed out. `project` / `note` / `origin` / `session`
# stay in the file as provenance — the record is the receipt, and a receipt carries more than the
# transaction needs.
R_ID=""; R_VERB=""; R_EVIDENCE=""; R_NEEDS=""
# ONE jq CALL PER FIELD, deliberately, rather than one `@tsv` row split by the shell. `IFS=$'\t'
# read` collapses RUNS of tabs, because tab is an IFS *whitespace* character — so a record with two
# adjacent empty fields (the common shape: a `done` record has no `needs`, `project` or `note`)
# shifts every later value one column left, and `origin` lands in `needs`. Measured here before it
# shipped. Seven forks over a store of a handful of files is not a cost worth a delimiter hazard.
rfield() {  # <file> <key> → the value as a string ("" when absent)
  # shellcheck disable=SC2016  # a jq program; $k is jq's --arg binding
  "$JQ" -r --arg k "$2" '.[$k] // "" | tostring' "$1" 2>/dev/null
}
read_record() {  # <file>
  local f="$1"
  # ONLY THE FOUR FIELDS THE READER ACTS ON. `project` / `note` / `origin` / `session` stay in the
  # file as provenance and are never parsed here — the record is a receipt, and a receipt carries
  # more than the transaction needs. Parsing a field nothing consumes would also widen the untrusted
  # surface for nothing.
  R_ID=""; R_VERB=""; R_EVIDENCE=""; R_NEEDS=""
  "$JQ" -e 'type == "object"' "$f" >/dev/null 2>&1 \
    || { warn "MALFORMED (not a JSON object): $f"; return 1; }
  R_ID="$(rfield "$f" id)";             R_VERB="$(rfield "$f" verb)"
  R_EVIDENCE="$(rfield "$f" evidence)"; R_NEEDS="$(rfield "$f" needs)"
  valid_id "${R_ID:-}"     || { warn "MALFORMED (id '${R_ID:-}' is not a backlog id): $f"; return 1; }
  valid_verb "${R_VERB:-}" || { warn "MALFORMED (verb '${R_VERB:-}' is not done|block): $f"; return 1; }
  # Re-validated here and not only at record time: the file is a git artifact and a later commit
  # can edit it without ever passing through `record`.
  valid_text "${R_EVIDENCE:-}" || { warn "MALFORMED (evidence unusable): $f"; return 1; }
  valid_text "${R_NEEDS:-}"    || { warn "MALFORMED (needs unusable): $f"; return 1; }
  [ "$R_VERB" = "block" ] && [ -z "$R_NEEDS" ] && { warn "MALFORMED (block with no --needs — the park would name no step): $f"; return 1; }
  return 0
}

store_files() {  # every record, name-sorted; silent when the store does not exist yet
  local f
  for f in "$STORE"/*.json; do [ -e "$f" ] || continue; printf '%s\n' "$f"; done | sort
}

# ── verbs ────────────────────────────────────────────────────────────────────────────────────────
cmd_record() {
  local id="" verb="" evidence="" needs="" project="" note=""
  [ $# -ge 1 ] || die 64 "record needs an id. Run with --help."
  id="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --verb)     verb="${2:-}"; shift 2 ;;
      --evidence) evidence="${2:-}"; shift 2 ;;
      --needs)    needs="${2:-}"; shift 2 ;;
      --project)  project="${2:-}"; shift 2 ;;
      --note)     note="${2:-}"; shift 2 ;;
      *) die 64 "record: unknown argument '$1'" ;;
    esac
  done
  valid_id "$id"     || die 64 "record: '$id' is not a backlog id (6-40 hex)."
  valid_verb "$verb" || die 64 "record: --verb must be done or block (got '${verb:-}'). Those are the two verdicts this transport carries; nothing else may reach the ledger through it."
  valid_text "$evidence" || die 64 "record: --evidence must be one bounded line."
  valid_text "$needs"    || die 64 "record: --needs must be one bounded line."
  [ "$verb" = "done" ]  && [ -z "$evidence" ] && die 64 "record: done needs --evidence. A close with no evidence is the false-done this ledger exists to refuse."
  [ "$verb" = "block" ] && [ -z "$needs" ]    && die 64 "record: block needs --needs \"<the exact operator step>\". A park that names no step is a row nobody can unblock."
  have_jq || die 64 "record: jq not found (set CC_HANDBACK_JQ)."

  mkdir -p "$STORE" 2>/dev/null || die 64 "record: cannot create the store at $STORE"

  # IDEMPOTENT on (id, verb, payload): a re-dispatch of an already-recorded row re-uses its file.
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_record "$f" || continue
    [ "$R_ID" = "$id" ] && [ "$R_VERB" = "$verb" ] && [ "$R_EVIDENCE" = "$evidence" ] && [ "$R_NEEDS" = "$needs" ] && {
      say "already recorded — $f"; printf '%s\n' "$f"; return 0; }
  done <<EOF
$(store_files)
EOF

  local ts; ts="$(now_stamp)"
  local slug; slug="$(printf '%s' "$ts" | tr -cd '0-9')"
  local out="$STORE/${slug}-${id}-${verb}.json"
  local n=0
  while [ -e "$out" ]; do n=$((n + 1)); out="$STORE/${slug}-${id}-${verb}-${n}.json"; done

  # shellcheck disable=SC2016  # a jq program; every $name is a --arg binding
  "$JQ" -n --arg ts "$ts" --arg id "$id" --arg verb "$verb" --arg ev "$evidence" \
           --arg needs "$needs" --arg project "$project" --arg note "$note" \
           --arg sid "${CLAUDE_CODE_SESSION_ID:-}" \
    '{schema:1, ts:$ts, id:$id, verb:$verb, evidence:$ev, needs:$needs,
      project:$project, note:$note, origin:"offbox", session:$sid}' > "$out" \
    || die 64 "record: could not write $out"
  say "recorded $verb for $id → $out"
  printf '%s\n' "$out"
}

# Sets P_* counters and, with $1 = "print", renders the table.
P_PENDING=0; P_APPLIED=0; P_UNKNOWN=0; P_BAD=0; P_NOLEDGER=0
scan() {  # [print]
  local print="${1:-}" f state
  P_PENDING=0; P_APPLIED=0; P_UNKNOWN=0; P_BAD=0; P_NOLEDGER=0
  [ "$print" = print ] && printf 'STATE\tID\tVERB\tDETAIL\n'
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! read_record "$f"; then P_BAD=$((P_BAD + 1)); continue; fi
    state="$(record_state "$R_ID" "$R_VERB")"
    case "$state" in
      PENDING)   P_PENDING=$((P_PENDING + 1)) ;;
      APPLIED)   P_APPLIED=$((P_APPLIED + 1)) ;;
      UNKNOWN)   P_UNKNOWN=$((P_UNKNOWN + 1)) ;;
      NO-LEDGER) P_NOLEDGER=$((P_NOLEDGER + 1)) ;;
    esac
    [ "$print" = print ] && printf '%s\t%s\t%s\t%s\n' "$state" "$R_ID" "$R_VERB" \
      "$([ "$R_VERB" = "done" ] && printf '%s' "${R_EVIDENCE}" || printf '%s' "${R_NEEDS}")"
  done <<EOF
$(store_files)
EOF
  return 0
}

cmd_list() {
  local as_json=0
  [ "${1:-}" = "--json" ] && as_json=1
  have_jq || die 64 "list: jq not found (set CC_HANDBACK_JQ)."
  load_ledger || true
  if [ "$as_json" = 1 ]; then
    scan
    # shellcheck disable=SC2016  # a jq program; every $name is an --argjson binding
    "$JQ" -n --argjson p "$P_PENDING" --argjson a "$P_APPLIED" --argjson u "$P_UNKNOWN" \
             --argjson b "$P_BAD" --argjson n "$P_NOLEDGER" --argjson ok "$LEDGER_OK" \
      '{ledger_readable:($ok==1), pending:$p, applied:$a, unknown:$u, malformed:$b, unfoldable:$n}'
  else
    scan print
    if [ "$LEDGER_OK" = 1 ]; then
      say "$P_PENDING pending · $P_APPLIED applied · $P_UNKNOWN unknown-to-the-ledger · $P_BAD malformed."
    else
      # Never "0 pending". This venue cannot see the ledger, so it knows nothing about any record.
      say "CANNOT FOLD — no ledger at $LEDGER (this venue does not own it). $P_NOLEDGER record(s) carried, verdicts unknown here. Run this on the box that holds the ledger."
    fi
  fi
  [ "$P_BAD" -gt 0 ] && return 66
  return 0
}

cmd_render() {  # the ONE command, and only when there is something to run
  have_jq || return 0
  load_ledger || true
  scan
  [ "$LEDGER_OK" = 1 ] || return 0        # nothing to offer at a venue that cannot apply it
  [ "$P_PENDING" -gt 0 ] || return 0      # silence is the answer when nothing is pending
  printf '%s\n' "▶ Run this:"
  printf '\n'
  # shellcheck disable=SC2016  # the backticks are the operator readout's inline-code span, not a subshell
  printf '`CONFIRM=1 %s apply`\n' "$SELF"
  printf '\n'
  printf '  (%s off-box ledger verdict(s) came home with a land and have not been folded in yet.)\n' "$P_PENDING"
  return 0
}

cmd_apply() {
  local dry=0
  [ "${1:-}" = "--dry-run" ] && dry=1
  have_jq || die 64 "apply: jq not found (set CC_HANDBACK_JQ)."
  [ "${CONFIRM:-0}" = "1" ] || die 65 "refusing to write the ledger without CONFIRM=1 — re-run as: CONFIRM=1 $SELF apply. (list and render need no confirmation and never write.)"
  load_ledger || die 65 "no ledger at $LEDGER — this venue does not own it, so there is nothing to fold into. This is 'cannot look', NOT 'nothing pending'."
  [ -x "$CB" ] || command -v "$CB" >/dev/null 2>&1 || die 65 "cc-backlog not found at $CB (set CC_BACKLOG_BIN)."

  local f state failed=0 done_n=0 bad=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! read_record "$f"; then bad=$((bad + 1)); continue; fi
    state="$(record_state "$R_ID" "$R_VERB")"
    case "$state" in
      APPLIED) continue ;;
      # REPORTED, NEVER FILED. Creating the row here would let a record from another venue inject
      # work into the wave; the ceiling on this transport is that it can only advance rows the box
      # already knows (see item 1 in the header).
      UNKNOWN) warn "· ${R_ID} ${R_VERB} — the ledger has no such row; reported, not filed ($f)"; continue ;;
    esac
    if [ "$dry" = 1 ]; then say "would apply: $R_VERB $R_ID"; done_n=$((done_n + 1)); continue; fi
    local rc=0
    if [ "$R_VERB" = "done" ]; then
      "$CB" "done" "$R_ID" --evidence "$R_EVIDENCE" >/dev/null 2>&1 || rc=$?
    else
      "$CB" block "$R_ID" --needs "$R_NEEDS" >/dev/null 2>&1 || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
      warn "✗ ${R_ID} ${R_VERB} — cc-backlog exited $rc ($f)"; failed=$((failed + 1)); continue
    fi
    # VERIFIED BY RE-READING THE LEDGER, not by cc-backlog's exit code: `done` on an unknown id
    # exits 0 with a message, so the exit code alone cannot tell an applied verdict from a no-op.
    load_ledger || true
    if [ "$(record_state "$R_ID" "$R_VERB")" = "APPLIED" ]; then
      say "✓ ${R_ID} ${R_VERB} applied."; done_n=$((done_n + 1))
    else
      warn "✗ ${R_ID} ${R_VERB} — cc-backlog exited 0 but the ledger fold does not carry it ($f)"; failed=$((failed + 1))
    fi
  done <<EOF
$(store_files)
EOF

  say "$done_n applied, $failed failed$([ "$bad" -gt 0 ] && printf ', %s malformed' "$bad")."
  [ "$failed" -gt 0 ] && return 70
  [ "$bad" -gt 0 ] && return 66
  return 0
}

# ── selftest ─────────────────────────────────────────────────────────────────────────────────────
# Fixture-driven and hermetic: its own STORE, its own LEDGER, the repo's REAL cc-backlog. It exists
# so the transport can be exercised at the venue that WRITES records (a cloud VM with no ledger),
# where the bats suite's box-side assumptions do not hold.
selftest() {
  local pass=0 fail=0
  t() { if eval "$2" >/dev/null 2>&1; then printf '  ok   %s\n' "$1"; pass=$((pass + 1));
        else printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); fi; }
  local tmp; tmp="$(mktemp -d)" || { echo "selftest: no tmpdir" >&2; return 2; }
  export CC_HANDBACK_DIR="$tmp/store" CC_BACKLOG_FILE="$tmp/ledger.jsonl"
  export CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_KICK=off
  STORE="$CC_HANDBACK_DIR"; LEDGER="$CC_BACKLOG_FILE"

  t "record refuses a verb outside done|block"        "! $SELF record aaaaaaaaaaaa --verb reopen"
  t "record refuses a non-id"                          "! $SELF record 'nope; rm -rf /' --verb done --evidence x"
  t "record refuses done with no evidence"             "! $SELF record aaaaaaaaaaaa --verb done"
  t "record refuses block with no needs"               "! $SELF record aaaaaaaaaaaa --verb block"
  t "record writes one file"                           "$SELF record aaaaaaaaaaaa --verb done --evidence 'sha1' && [ \"\$(ls -1 $tmp/store | wc -l)\" -eq 1 ]"
  t "record is idempotent on the same payload"         "$SELF record aaaaaaaaaaaa --verb done --evidence 'sha1' && [ \"\$(ls -1 $tmp/store | wc -l)\" -eq 1 ]"
  # THE CLOUD CASE, which is the venue this half runs at: no ledger ⇒ no verdict, and never "0 pending".
  t "no ledger ⇒ list says CANNOT FOLD"                "$SELF list > $tmp/out0; grep -q 'CANNOT FOLD' $tmp/out0"
  t "no ledger ⇒ render offers nothing"                "[ -z \"\$($SELF render)\" ]"
  t "no ledger ⇒ apply refuses (65)"                   "CONFIRM=1 $SELF apply; [ \$? -eq 65 ]"
  t "apply refuses without CONFIRM (65)"               "$SELF apply; [ \$? -eq 65 ]"

  # THE BOX CASE: a real ledger, the real cc-backlog.
  local rid
  rid="$("$CB" add --title 'handback selftest row' --project claude-infrastructure 2>/dev/null)"
  # Double-quoted so $rid EXPANDS — `[ -n '$rid' ]` tests the literal string and is true forever,
  # which is a test that cannot fail and therefore proves nothing (memory: control-must-replay).
  t "fixture row filed"                                "[ -n \"$rid\" ]"
  t "record for the real row"                          "$SELF record '$rid' --verb done --evidence 'deadbeef'"
  # `cmd | grep -q` is NOT usable as an assertion under `set -o pipefail`: grep exits at the first
  # match, the producer takes SIGPIPE, and the pipeline reports 141 — so a PASSING assertion fails,
  # intermittently, depending on where the matching row happens to sit in the output. Measured here
  # before it shipped. Every assertion therefore captures the output first and greps the capture.
  L="$tmp/out"
  t "it folds as PENDING"                              "$SELF list > $L; grep -q '^PENDING	$rid	done' $L"
  t "render now offers the one command"                "$SELF render > $L; grep -q 'CONFIRM=1' $L"
  t "dry-run applies nothing"                          "CONFIRM=1 $SELF apply --dry-run && $SELF list > $L && grep -q '^PENDING	$rid' $L"
  t "apply lands the verdict"                          "CONFIRM=1 $SELF apply && $SELF list > $L && grep -q '^APPLIED	$rid	done' $L"
  t "apply is idempotent"                              "CONFIRM=1 $SELF apply"
  t "render is silent once applied"                    "[ -z \"\$($SELF render)\" ]"
  # THE CEILING: an id the ledger never heard of is reported, never filed.
  t "unknown id is reported, not created"              "$SELF record bbbbbbbbbbbb --verb done --evidence x && CONFIRM=1 $SELF apply && $CB list --all --json > $tmp/led && ! grep -q bbbbbbbbbbbb $tmp/led"
  # MALFORMED IS REPORTED, NEVER SILENTLY SKIPPED.
  printf '{"id":"cccccccccccc","verb":"nuke"}\n' > "$tmp/store/99999999-bad.json"
  t "a bad verb in the store is reported (66)"         "$SELF list; [ \$? -eq 66 ]"
  printf 'not json at all\n' > "$tmp/store/99999998-bad.json"
  t "unparseable record is reported (66)"              "$SELF list; [ \$? -eq 66 ]"
  t "a malformed record does not stop the good ones"   "CONFIRM=1 $SELF apply; [ \$? -eq 66 ]"

  rm -rf "$tmp"
  printf 'backlog-handback: --selftest %s (%s ok, %s failed)\n' \
    "$([ "$fail" -eq 0 ] && echo PASS || echo FAILED)" "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# ── dispatch ─────────────────────────────────────────────────────────────────────────────────────
[ $# -ge 1 ] || { usage; exit 64; }
case "$1" in
  record) shift; cmd_record "$@" ;;
  list)   shift; cmd_list "$@" ;;
  render) shift; cmd_render "$@" ;;
  apply)  shift; cmd_apply "$@" ;;
  --selftest) selftest ;;
  -h|--help) usage ;;
  *) die 64 "unknown verb '$1' — record | list | render | apply. Run with --help." ;;
esac
