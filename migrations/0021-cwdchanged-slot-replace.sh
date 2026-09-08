#!/bin/bash
# migration-class: c10
# migration-step: REPLACE file-changed.sh with cwd-changed.sh in the CwdChanged slot — the slot holds the SILENT emitter, so a re-arm that carried nothing is indistinguishable from one that never fired. Edits settings.json ⇒ C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0021-cwdchanged-slot-replace.sh
# migration-subject: ~/.claude/hooks/cwd-changed.sh
# migration-verify: jq -e '([.hooks.CwdChanged[]?.hooks[]?.command] | any(test("cwd-changed"))) and ([.hooks.CwdChanged[]?.hooks[]?.command] | all(test("file-changed") | not))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0021 — found by claude-infrastructure-330 (backlog e35329880deb) and owned here because the
# handler is this wave's (W3-E). Migration 0017 registered `file-changed.sh` into the **CwdChanged**
# slot across all five config dirs; measured 2026-09-07 that command is the ONLY thing in
# `.hooks.CwdChanged`, and `cwd-changed.sh` — built for this slot, landed, 24 tests, 14-site
# red-proof — is registered NOWHERE.
#
# WHY THAT IS A DEFECT AND NOT A COSMETIC PREFERENCE. Both handlers re-emit `watchPaths` on a
# CwdChanged payload, so the watch survives a `cd` either way. But `file-changed.sh` writes **no log
# row** on that path, and § 3e's failure class is exactly that `onCwdChanged` OVERWRITES the dynamic
# watch list with whatever the hooks return — so a re-arm that rebuilt an EMPTY list looks identical
# to one that never fired. `cwd-changed.sh` exists to close that: it logs one row per transition
# carrying the COUNT re-armed, **including the count-0 case**, which is the only row that
# distinguishes the two. The slot currently holds the emitter that cannot tell you which happened.
#
# WHY REPLACE AND NOT APPEND — and the first version of this header got the REASON wrong, which is
# worth keeping rather than quietly fixing.
#
# It argued that a second emitter was UNSAFE: `onCwdChanged` sets the watch list to what the hooks
# RETURN, so with two registered the outcome would depend on provider N-hook resolution order (first
# non-empty? last? union?), which § 3b listed as EXPLICITLY UNSETTLED. That is no longer true.
# 2026-09-07 the order was SETTLED by READING THE 220 BINARY — the route § 3b itself prescribes, and
# with no second observer registered anywhere, so the § 4 prohibition was never approached:
#
#     async function Zop(e,t){ let r = await vL({hookInput:e,timeoutMs:t});
#                              let n = r.flatMap((i) => i.watchPaths ?? []);   // ← UNION
#                              return {results:r, watchPaths:n, ...} }
#     function Ttn(e,t,r){ ... hook_event_name:"CwdChanged" ...; return Zop(n,r) }    // 237754921+
#     // consumer: let A = await Ttn(y,T)...;  r = A.watchPaths;                      // 232532309+
#
# It is a flatMap UNION over every registered hook in registration order, extracted event-agnostically
# (`"watchPaths" in O.hookSpecificOutput ? … : void 0`, 237815300+), then de-duped at
# watcher-construction (`Co([...C,...r])`). So APPENDING IS MECHANICALLY SAFE. The old reason is
# refuted; § 3b item 2 carries the full extract and the trap that nearly produced the opposite
# answer (the streaming parser's switch assigns `watchPaths` only under `case "SessionStart"`).
#
# REPLACE is still correct, on the reason that SURVIVES the measurement: both handlers read ONE
# watchlist through one env seam and emit a byte-identical array — `tests/cwd-changed.bats`'s
# agreement arm asserts exactly that — so a second emitter contributes ZERO new paths. It buys
# nothing, doubles the fork cost on a path that runs at every `cd`, and gives one list two writers.
# The receipt is the entire point of this change, and a receipt wants exactly one author.
#
# WHY THE REPLACE IS SAFE, from a mechanical proof and not from inspection. `tests/cwd-changed.bats`
# carries an AGREEMENT arm: it writes one watchlist, feeds the same payload to BOTH handlers, and
# asserts `.hookSpecificOutput.watchPaths` is byte-identical. They share the file and the
# `CC_FILECHANGED_WATCHLIST` env seam, so the emission does not change — only the observability is
# added. Change either reader without the other and that arm goes red.
#
# FileChanged's own registrations are NOT touched: `file-changed.sh` stays in the FileChanged slot,
# where § 3e's arm/dispatch pair needs it. Only the CwdChanged slot is rewritten.
#
# WHY c10. It edits settings.json — staged, never self-run (migrations/README.md).
set -uo pipefail

# shellcheck disable=SC2088  # tildes are DELIBERATELY literal: stored INTO settings.json, where CC
# expands them at hook-run time. Expanding here hard-codes this machine's $HOME into five configs.
OLD_CMD='~/.claude/hooks/file-changed.sh'
# shellcheck disable=SC2088  # same literal-tilde reason; a directive binds to the NEXT construct
# only, so OLD_CMD's does not cover this line — the exact trap this repo's lint-directive memory names.
NEW_CMD='~/.claude/hooks/cwd-changed.sh'
NEW_FILE="$HOME/.claude/hooks/cwd-changed.sh"
rc=0

command -v jq >/dev/null 2>&1 || { printf '0021: jq required\n' >&2; exit 1; }

# Precondition re-derived at CONSUMPTION, not trusted from the header: a registration naming a path
# that does not run is a registered no-op, and it reads GREEN (MEMORY.md discovery-critic-premise-goes-stale).
if [ ! -x "$NEW_FILE" ]; then
  printf '0021: NOT applied — %s is missing or not executable.\n' "$NEW_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi

# 🚨 AND `-x` IS NOT ENOUGH, FOR THE REASON 0017 LEARNED ON THIS EXACT SLOT THIS MORNING.
# `-x` asserts the file EXISTS AND RUNS. It says nothing about it being the VERSION whose behaviour
# the registration depends on, and `~/.claude/hooks/cwd-changed.sh` is a SYMLINK into the shared
# checkout — an INDEPENDENT question from what is on trunk (`landed ≠ live`), so no git-side check
# answers it. 0017 measured that trap live: its subject symlink resolved to a copy 9 commits behind,
# which was perfectly executable and could not do the one job it was being registered for.
# (MEMORY.md registration-precondition-must-assert-version-not-executability.)
#
# So the precondition is a BEHAVIOUR PROBE against the copy that will actually run — and it asserts
# the DISCRIMINATING behaviour, not merely a working one. It requires BOTH:
#   1. the re-arm  — `watchPaths` on stdout for a CwdChanged payload; and
#   2. THE RECEIPT — one log row for that transition, carrying the COUNT re-armed.
# Requirement 2 is what makes this probe non-vacuous, and it is the whole design of this migration:
# `hooks/file-changed.sh` — the handler being REPLACED — satisfies 1 and deliberately fails 2. A
# probe that checked only the emit would pass on the very file whose silence is the defect, i.e. it
# would clear the swap while being blind to the property the swap exists to gain. It tests the
# capability rather than a marker string or a version number, so it cannot be satisfied by a file
# that merely looks recent, and it stays true if either half is ever reimplemented.
# Side-effect free: the watchlist and the log dir are both redirected into a mktemp -d removed on
# the way out, so the probe can never write a row into the operator's real cwd-changed.log.
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/0021-probe.XXXXXX") || {
  printf '0021: could not create a probe sandbox; not applied\n' >&2; exit 1; }
printf '/0021/probe/marker\n' > "$probe_dir/watchlist"
probe_out=$(printf '%s' '{"session_id":"0021-probe","hook_event_name":"CwdChanged","cwd":"/0021/from","old_cwd":"/0021/from","new_cwd":"/0021/to"}' \
  | CC_FILECHANGED_WATCHLIST="$probe_dir/watchlist" CC_CWDCHANGED_LOG_DIR="$probe_dir/logs" \
    "$NEW_FILE" 2>/dev/null) || probe_out=""
probe_rows=$(grep -c '/0021/to' "$probe_dir/logs/cwd-changed.log" 2>/dev/null || printf '0')
rm -rf "$probe_dir"

if ! printf '%s' "$probe_out" | jq -e '.hookSpecificOutput.hookEventName == "CwdChanged"
                                       and (.hookSpecificOutput.watchPaths | index("/0021/probe/marker") != null)' \
     >/dev/null 2>&1; then
  printf '0021: NOT applied — the LIVE %s does not re-arm on a CwdChanged payload.\n' "$NEW_FILE" >&2
  printf '      It emitted: %s\n' "${probe_out:-<nothing>}" >&2
  printf '      Swapping the slot to a handler that cannot re-arm would EMPTY the watch list on the\n' >&2
  printf '      first cd, and it would read GREEN. The live layer is likely BEHIND trunk; converge:\n' >&2
  printf '        bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' >&2
  exit 1
fi

if [ "$probe_rows" -lt 1 ]; then
  printf '0021: NOT applied — the LIVE %s re-armed but wrote NO receipt row.\n' "$NEW_FILE" >&2
  printf '      The receipt is the ONLY thing this migration buys: without it a re-arm that carried\n' >&2
  printf '      nothing is indistinguishable from one that never fired, which is the exact defect\n' >&2
  printf '      the slot already has. Swapping to a second silent emitter would be a no-op that\n' >&2
  printf '      reads GREEN on every sensor. Converge the live layer first:\n' >&2
  printf '        bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  if ! jq -e '.hooks.CwdChanged | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0021: %s — no CwdChanged array; skipped (0017 has not run here)\n' "$f"
    continue
  fi

  if jq -e --arg c "$NEW_CMD" '[.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0021: %s — already replaced\n' "$f"
    continue
  fi

  if ! jq -e --arg o "$OLD_CMD" '[.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $o)' "$f" >/dev/null 2>&1; then
    printf '0021: %s — CwdChanged holds neither command; left ALONE for a human\n' "$f" >&2; rc=1; continue
  fi

  bak="$f.bak-0021-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0021: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0021-$$"
  # REPLACE in place, scoped to the CwdChanged subtree only — FileChanged's own entries are
  # untouched because the walk never leaves .hooks.CwdChanged.
  # shellcheck disable=SC2016  # $o/$c are JQ variables bound by --arg, not shell expansions
  if jq --arg o "$OLD_CMD" --arg c "$NEW_CMD" \
       '.hooks.CwdChanged |= map(.hooks |= map(if .command == $o then .command = $c else . end))' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT before it replaces the live file: the new command present, the old GONE from
    # this slot, FileChanged's own registrations intact, and the load-bearing arrays still there.
    if jq -e --arg o "$OLD_CMD" --arg c "$NEW_CMD" \
         '([.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $c))
          and ([.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $o) | not)
          and ([.hooks.FileChanged[]?.hooks[]?.command] | length) > 0
          and (.hooks.Stop | type == "array" and length > 0)
          and (.hooks.PreToolUse | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0021: %s — CwdChanged slot now runs cwd-changed.sh (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0021: %s — edit failed its content check; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0021: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
