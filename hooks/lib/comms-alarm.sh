#!/bin/bash
# comms-alarm — the SINGLE write chokepoint for the comms alarm store
# (~/.claude/autonomy/comms-alarms), and the store's own hermeticity assertion.
#
# WHY THIS EXISTS (measured 2026-07-29, backlog 817faf3a4968). The store held 1273 records and
# 511 of them (40.1%) were TEST FIXTURE DATA written by a bats suite into the operator's LIVE
# directory: `{"kind":"enqueue-failed","target":"AAAAAAAA-1111-2222-3333-444444444444",
# "msg":"cannot persist"}` — the literal triple `tests/cc-notify.bats` passes when it exercises the
# inbox-unwritable path. The suite fixtured CC_REGISTRY_DIR and CC_MAILBOX_DIR but not
# CC_COMMS_ALARM_DIR, so every run appended to live telemetry. Two costs, both real:
#
#   1. cc-inbox-guard PHONES THE OPERATOR for each enqueue-fail record, then marks it `.handled`.
#      All 510 `.handled` fixture records are 510 pages about a failure that never happened.
#   2. Every rebuild that re-derives its constants from primary disk truth (the ground-up method
#      requires exactly that) reads a 40%-fixture denominator. Row 3 caught it only because it
#      cross-checked; a row that trusted the store would have designed against fabricated rates.
#
# WHY A CHOKEPOINT AND NOT A LINT. The suite-side fix (fixture the dir) is one line, and it was
# applied — but it only fixes the suites that exist today. A lint over the tree would make every
# author answerable for every other author's suite (a fleet-wide hard stop; see the
# whole-tree-lint memory), and a lint over the STORE would block every land for as long as the
# operator's live directory stayed dirty. Neither is the enforcement this needs. The write path is:
# a fixture-context write CANNOT reach the live root, because the only function that writes here
# refuses to put it there. Contamination becomes structurally impossible rather than detected late.
#
# THE RULE: a write whose actor resolves to a bats/fixture context, into the LIVE default dir, is
#   (a) stamped `test_origin` so no reader ever has to pattern-match a magic UUID,
#   (b) DIVERTED into <dir>/test-leak/ so the live root stays clean and cc-inbox-guard's
#       `enqueue-fail-*.json` glob (root-only) never pages the operator for it, and
#   (c) LOUD on stderr plus rc=1 — a real verdict a caller or suite can assert on.
# It is deliberately NOT a hard failure of the calling tool: every one of these call sites is a
# fail-loud backstop on a fire-and-forget path (`|| true`), and turning a test-hygiene problem into
# a production abort would be a worse bug than the one being fixed. The evidence is preserved, the
# shout is unmissable, and the store stays honest.
#
# A write into a FIXTURED dir is stamped too but not diverted — that dir is the suite's own tmpdir
# and is exactly where the record belongs. Stamping it anyway keeps `test_origin` a total signal:
# present on every fixture-written record everywhere, so `--assert-clean` and cc-inbox-guard can key
# on one field instead of inferring origin from a path.
#
# Env seams: CC_COMMS_ALARM_DIR (the dir; set by suites) · CC_COMMS_ALARM_TEST_ORIGIN (force/declare
# a fixture context for harnesses bats does not run — selftests, non-bats suites).

# The live default. Kept as a function, not a constant, because $HOME is itself the seam every
# caller varies (a gate clones $HOME per run) — resolving it at call time is what makes the
# divert decision correct inside a cloned-$HOME gate as well as in a real session.
comms_alarm_live_default() { printf '%s\n' "$HOME/.claude/autonomy/comms-alarms"; }

comms_alarm_dir() { printf '%s\n' "${CC_COMMS_ALARM_DIR:-$(comms_alarm_live_default)}"; }

# Print a token naming the fixture context, or nothing. rc 0 = fixture context, 1 = production.
#
# bats exports BATS_TEST_FILENAME / BATS_TEST_TMPDIR / BATS_RUN_TMPDIR into the subject's
# environment (verified 2026-07-29 with a probe suite: a plain script invoked from a @test body
# sees all three). So the subject can name its own caller without the suite cooperating — which is
# the point: a leak is by definition a suite that FORGOT to cooperate.
#
# BATS_TEST_FILENAME is checked first because it names the file, and a shout that names the file is
# a two-line fix; the tmpdir vars are the setup_file/teardown_file fallback where it is unset.
comms_alarm_test_origin() {
  if [ -n "${CC_COMMS_ALARM_TEST_ORIGIN:-}" ]; then
    printf '%s\n' "$CC_COMMS_ALARM_TEST_ORIGIN"; return 0
  fi
  if [ -n "${BATS_TEST_FILENAME:-}" ]; then
    printf 'bats:%s\n' "$(basename "$BATS_TEST_FILENAME")"; return 0
  fi
  if [ -n "${BATS_TEST_TMPDIR:-}" ] || [ -n "${BATS_RUN_TMPDIR:-}" ]; then
    printf 'bats:unknown-suite\n'; return 0
  fi
  return 1
}

# comms_alarm_write <name-prefix> <compact-json-object>
#   rc 0 = written where it belongs · 1 = fixture-context write DIVERTED out of the live root
#   rc 2 = could not write at all (no jq, unwritable dir) — the caller's own backstop is already
#          `|| true`, but a distinct code keeps "diverted" from reading as "storage broke".
#
# The name shape stays `<prefix>-<UTCstamp>-<pid>-<rand>.json`: cc-inbox-guard globs
# `enqueue-fail-*.json` in the root, so the prefix is a contract. $RANDOM is new — cc-notify's old
# `<prefix>-<stamp>-<pid>.json` collided silently whenever one pid wrote twice inside one second,
# which on the enqueue-fail path (a loop over dead panes) is not hypothetical.
comms_alarm_write() {
  local prefix="$1" json="$2" dir origin out target rc=0
  command -v jq >/dev/null 2>&1 || return 2
  dir="$(comms_alarm_dir)"
  origin="$(comms_alarm_test_origin || true)"

  if [ -n "$origin" ]; then
    json="$(printf '%s' "$json" | jq -c --arg o "$origin" '. + {test_origin:$o}' 2>/dev/null)" || return 2
    [ -n "$json" ] || return 2
    if [ "$dir" = "$(comms_alarm_live_default)" ]; then
      # The leak case. Divert, shout, and report it — never a silent append to live telemetry.
      target="$dir/test-leak"
      rc=1
    else
      target="$dir"
    fi
  else
    target="$dir"
  fi

  mkdir -p "$target" 2>/dev/null || return 2
  out="$target/$prefix-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)-$$-${RANDOM}.json"
  printf '%s\n' "$json" > "$out" 2>/dev/null || return 2

  if [ "$rc" = 1 ]; then
    echo "comms-alarm: HERMETICITY VIOLATION — a FIXTURE-context write ($origin) tried to append to the" >&2
    echo "  operator's LIVE alarm store. Diverted to $out and stamped test_origin; the live root is" >&2
    echo "  untouched. FIX THE SUITE: export CC_COMMS_ALARM_DIR=\"\$BATS_TEST_TMPDIR/comms-alarms\" in" >&2
    echo "  setup() — per-test does not count, it leaves every other test in the file pointed at live." >&2
  fi
  return "$rc"
}
