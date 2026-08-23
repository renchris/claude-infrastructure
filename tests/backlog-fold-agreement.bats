#!/usr/bin/env bats
# THE TWO FOLDS OVER ONE LEDGER MUST AGREE — cc-backlog `list` vs cc-backlog `reap`.
#
# THE DEFECT. cc-backlog holds two independent status folds over the same append-only JSONL:
#   fold()        (cmd_list) — a reduce whose unmodelled events CARRY THE PREVIOUS STATUS FORWARD
#                              (`else ($p.status // "open")`).
#   REAP_FOLD_JQ  (cmd_reap) — read the LAST record of the trail and map its event, with every
#                              unrecognised event mapping to "open".
# Several verbs append a NON-status record after a status one as a matter of course: `block`
# auto-links its condition, so a `link` lands after nearly every block; `falsify`, `venue` and
# `update` do the same. On those trails the reap read `blocked` (or `done`, or `claimed`) as OPEN.
#
# WHY THAT MATTERS: the reap excludes terminal rows by construction
# (`select(.status != "done" and .status != "blocked")`), because `blocked` is the operator-gated
# status and `done` is closed work. A row mis-folded to open DEFEATS ITS OWN EXCLUSION and re-enters
# the sweep — so the reap could re-adjudicate rows a human had blocked and rows already finished,
# and cc-dispatch could be handed work that is genuinely blocked.
#
# MEASURED 2026-08-18 on the live ledger, before the fix: 53 of 2341 rows folded differently —
# 50 blocked-read-as-open (47 after `link`, 2 after `venue`, 2 after `falsify`... and one after
# `update` reading claimed-as-open, plus one DONE read as open). After: 0 of 2341.
#
# WHY THIS FILE EXISTS AT ALL, beyond the 53 rows. Two sibling auditors over ONE population
# disagreed silently for as long as the reap fold was unobservable — its only external trace is
# which rows it declines to scan, and a row it wrongly folds to open looks exactly like an open row.
# `cc-backlog fold-audit` exposes THE PRODUCTION PROGRAM (same $REAP_FOLD_JQ, $keepall=true), so the
# agreement arm below compares the real fold, never a re-derivation of it — re-deriving it here
# would rebuild the exact defect this file is for (memory: sibling-auditors-must-share-the-state-
# model, control-must-replay-the-real-artifact).
#
# EVERY ASSERTION HERE IS RED ON THE PRE-FIX FOLD. Point CC_TEST_BIN_DIR at a bin/ whose cc-backlog
# folds `st($g[-1].event)` and the four fold cases fail; the two CONTROLS stay green in BOTH
# directions, so the fix cannot be mistaken for "the reap stopped scanning things".

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="${CC_TEST_BIN_DIR:-$REPO/bin}"
  CB="$BIN/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  : > "$CC_BACKLOG_FILE"
  TS=0
}

# rec <id> <event> [k=v ...] — append one raw record. Raw rather than driven through the verbs
# because the point is the SHAPE OF THE TRAIL, and several of these shapes (a `link` after a
# `block`) are written by cc-backlog itself as a side effect rather than by a callable verb.
# Timestamps are monotonic and explicit: both folds sort on ts, so a fixture that let two records
# share a second would be testing sort stability instead of the fold.
rec() {
  local id="$1" ev="$2"; shift 2
  TS=$((TS + 60))
  local ts; ts="$(date -u -r "$((1750000000 + TS))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                  || date -u -d "@$((1750000000 + TS))" +%Y-%m-%dT%H:%M:%SZ)"
  local args=(--arg id "$id" --arg event "$ev" --arg ts "$ts")
  local filter='{id: $id, event: $event, ts: $ts, project: "p"}'
  local kv
  for kv in "$@"; do
    args+=(--arg "${kv%%=*}" "${kv#*=}")
    filter="$filter + {\"${kv%%=*}\": \$${kv%%=*}}"
  done
  jq -nc "${args[@]}" "$filter" >> "$CC_BACKLOG_FILE"
}

reap_status() { bash "$CB" fold-audit 2>/dev/null | awk -F'\t' -v i="$1" '$1==i {print $2}'; }
list_status() { bash "$CB" list --all --json 2>/dev/null | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

# ── THE FOUR MIS-FOLDS, one per non-status verb that lands after a status record ────────────────
# Each is its own case rather than one loop so a partial regression names the verb that broke.

@test "FOLD: blocked then link — the reap must read blocked, not open (47 live rows)" {
  rec b1 add title="blocked row auto-linked to its condition"
  rec b1 block needs="a human must decide" by=someone
  rec b1 link condition="cond-x"          # what `block` appends for itself
  [ "$(list_status b1)" = blocked ]       # the oracle: fold() has always been right here
  [ "$(reap_status b1)" = blocked ]       # PRE-FIX: "open"
}

@test "FOLD: done then link — a CLOSED row must not read open" {
  rec d1 add title="closed row with a later link"
  rec d1 "done" evidence="landed"
  rec d1 link condition="cond-y"
  [ "$(list_status d1)" = "done" ]
  [ "$(reap_status d1)" = "done" ]          # PRE-FIX: "open" — closed work back in the reap pool
}

@test "FOLD: blocked then venue / falsify — annotations must not clear a block" {
  rec v1 add title="blocked row later annotated with a venue"
  rec v1 block needs="a human must decide" by=someone
  rec v1 venue venue=cloud
  rec f1 add title="blocked row later given a falsifier"
  rec f1 block needs="a human must decide" by=someone
  rec f1 falsify falsifier="test -f /nope"
  # One assertion per line: `A && B` is absorbed by errexit, so B could never red the test
  # (scripts/bats-assert-liveness-lint — a dead assertion is a control that cannot fail).
  [ "$(list_status v1)" = blocked ]
  [ "$(reap_status v1)" = blocked ]
  [ "$(list_status f1)" = blocked ]
  [ "$(reap_status f1)" = blocked ]
}

@test "FOLD: claimed then update — a HELD row must not read open" {
  rec u1 add title="claimed row later updated"
  rec u1 claim by=worker-1 venue=local
  rec u1 update title="claimed row later updated, retitled"
  [ "$(list_status u1)" = claimed ]
  [ "$(reap_status u1)" = claimed ]       # PRE-FIX: "open" — the live claim disappears
}

# ── THE EXCLUSION THIS PROTECTS — the mis-fold is only harmful because of what it lets through ──

@test "FOLD: a blocked-then-link row is NOT scanned by the reap" {
  rec b2 add title="blocked row auto-linked to its condition"
  rec b2 block needs="a human must decide" by=someone
  rec b2 link condition="cond-z"
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  # `blocked` is operator-gated: the sweep must not even consider the row.
  [[ "$output" == *"0 non-terminal item(s) scanned"* ]]   # PRE-FIX: 1
}

# ── WHOLE-LEDGER AGREEMENT — the general claim, not the four instances ─────────────────────────

@test "FOLD: list and reap agree on EVERY row of a ledger covering all verb pairs" {
  local st nonst i=0
  for st in "done" block unblock claim reopen; do
    for nonst in link venue falsify update add; do
      i=$((i + 1))
      local id; id="$(printf 'x%03d' "$i")"
      rec "$id" add title="row $i covering $st then $nonst"
      rec "$id" "$st" needs="n" by=someone evidence="e" venue=local
      rec "$id" "$nonst" condition="c" venue=cloud falsifier="f" title="row $i retitled"
    done
  done
  # A row with NO status-bearing record at all — both folds must seed it "open".
  rec bare add title="never acted on"
  rec bare link condition="c"

  bash "$CB" fold-audit 2>/dev/null | LC_ALL=C sort > "$BATS_TEST_TMPDIR/reap"
  bash "$CB" list --all --json 2>/dev/null | jq -r '.[]|[.id,.status]|@tsv' \
    | LC_ALL=C sort > "$BATS_TEST_TMPDIR/list"
  # A vacuous pass is the trap here: an empty audit would diff clean against an empty list
  # (memory: verification-harness-vacuous-pass-traps). Floor the population first.
  [ "$(wc -l < "$BATS_TEST_TMPDIR/reap")" -eq 26 ]
  run diff -u "$BATS_TEST_TMPDIR/list" "$BATS_TEST_TMPDIR/reap"
  [ "$status" -eq 0 ]
}

# ── CONTROLS — green in BOTH directions, so a fix that merely muted the reap fails here ────────

@test "CONTROL: a genuinely open row still folds open and IS scanned" {
  rec o1 add title="ordinary open row"
  [ "$(list_status o1)" = open ]
  [ "$(reap_status o1)" = open ]
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 non-terminal item(s) scanned"* ]]
}

@test "CONTROL: unblock after block still returns the row to the wave" {
  rec o2 add title="row a human unblocked"
  rec o2 block needs="a human must decide" by=someone
  rec o2 link condition="cond-q"
  rec o2 unblock by=human
  [ "$(list_status o2)" = open ]
  [ "$(reap_status o2)" = open ]
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 non-terminal item(s) scanned"* ]]
}

# ── THE THIRD AUDITOR: `cc-backlog fold` and its --as-of replay (row 5e35b5b1070b) ─────────────
#
# The row: drain pings cite population figures ("ungrouped 133->132") that no tool rendered, so a
# verifier could not audit them. Its diagnosis — PRIVATE DEFINITIONS — is refuted on its own primary
# exhibit: the shipped verb replays #127's window to 133 -> 132 EXACTLY under the plainest reading.
# What was missing is TIME. The ledger is append-only over a board siblings mutate, so a verifier
# replaying LIVE necessarily lands on a different number, which is indistinguishable from a made-up
# one. `--as-of` is therefore the load-bearing half, and the arms below are ordered to prove that:
# the agreement arm pins that the verb did NOT introduce a fourth model of the population, and the
# refusal arm pins the one failure that would be WORSE than the unauditable figure it replaces.
#
# ts_of <id> <event> → the ledger's OWN timestamp for that record. Deriving the pin from the file
# rather than recomputing the rec() epoch arithmetic keeps the fixture self-anchoring: a change to
# rec()'s clock moves the pin with it instead of silently pinning the wrong instant.
ts_of() { jq -r --arg i "$1" --arg e "$2" 'select(.id==$i and .event==$e)|.ts' "$CC_BACKLOG_FILE" | tail -1; }
fold_rows() { if [ -z "${1:-}" ]; then bash "$CB" fold --json; else bash "$CB" fold --as-of "$1" --json; fi; }
ungrouped_open() { fold_rows "${1:-}" | jq -r '[.conditions[]|select(.condition=="ungrouped")|.open][0] // 0'; }

@test "AS-OF: a pinned fold drops every record written after the pin" {
  rec a1 add title="row that existed at the pin"
  local pin; pin="$(ts_of a1 add)"
  rec a2 add title="row that arrived after the pin"
  [ "$(fold_rows ""     | jq -r '.rows')" -eq 2 ]
  [ "$(fold_rows "$pin" | jq -r '.rows')" -eq 1 ]
}

@test "AS-OF: replays a population figure the LIVE fold no longer shows — the row's actual defect" {
  rec u1 add title="ungrouped row present when the figure was cited"
  local pin; pin="$(ts_of u1 add)"
  rec u2 add title="ungrouped row a sibling filed afterwards"
  rec u3 add title="another ungrouped row a sibling filed afterwards"
  # This IS the row's '+offset at both endpoints': the citation was right, the live replay is not.
  [ "$(ungrouped_open "$pin")" -eq 1 ]
  [ "$(ungrouped_open "")"     -eq 3 ]
}

@test "AS-OF: a pinned fold sees a status as it stood, not as it later became" {
  rec s1 add title="row blocked after the pin"
  local pin; pin="$(ts_of s1 add)"
  rec s1 block needs="a human must decide" by=someone
  rec s1 link condition="cond-later"
  [ "$(fold_rows "$pin" | jq -r '.status.open // 0')"    -eq 1 ]
  [ "$(fold_rows "$pin" | jq -r '.status.blocked // 0')" -eq 0 ]
  [ "$(fold_rows ""     | jq -r '.status.blocked // 0')" -eq 1 ]
}

@test "AS-OF: a MALFORMED pin REFUSES — it never renders a live fold under a pinned heading" {
  rec m1 add title="a row that exists"
  # Each of these sorts ABOVE every real ISO timestamp or truncates one, so an unvalidated compare
  # would select the WHOLE ledger and print a LIVE answer wearing a PINNED heading — strictly worse
  # than the unauditable figure this verb replaces (absent-range-endpoint-selects-everything).
  local bad
  for bad in yesterday 2026-08-22 2026-08-22T05:23:37 now 9999; do
    run bash "$CB" fold --as-of "$bad"
    [ "$status" -eq 2 ]
    [ "$(printf '%s' "$output" | grep -c 'CONDITION FOLD')" -eq 0 ]
  done
}

@test "FOLD: the new verb agrees with list --all --json on every status stratum" {
  # A fourth model of one population is the exact defect the rest of this file pins, so the verb is
  # compared against the PRODUCTION reader rather than a re-derivation of it.
  rec g1 add title="open ungrouped"
  rec g2 add title="blocked and conditioned"
  rec g2 block needs="a human must decide" by=someone
  rec g2 link condition="cond-z"
  rec g3 add title="closed row"
  rec g3 "done" evidence="landed"
  rec g4 add title="held row"
  rec g4 claim by=worker-1 venue=local
  local a b
  a="$(bash "$CB" fold --json | jq -Sc '.status')"
  b="$(bash "$CB" list --all --json | jq -Sc 'group_by(.status)|map({key:.[0].status,value:length})|from_entries')"
  [ "$a" = "$b" ]
}

@test "FOLD: renders its own predicate, and 'ungrouped' means no condition key" {
  rec p1 add title="conditioned row"
  rec p1 link condition="cond-z"
  rec p2 add title="row with no condition key"
  run bash "$CB" fold
  [ "$status" -eq 0 ]
  # The predicate line is the row's remedy itself — a figure whose definition ships with it.
  [ "$(printf '%s' "$output" | grep -c '^predicate: ')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'no condition key')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -cE '^cond-z +open=1 ')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -cE '^ungrouped +open=1 ')" -eq 1 ]
}
