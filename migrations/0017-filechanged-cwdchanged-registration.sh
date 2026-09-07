#!/bin/bash
# migration-class: c10
# migration-step: wire FileChanged + CwdChanged as the ONE three-part unit § 3e prescribes — an absolute-path matcher to ARM, a '*' sibling to DISPATCH, and a CwdChanged re-arm — so the dynamic watch list survives a `cd` instead of emptying on the first one; it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0017-filechanged-cwdchanged-registration.sh
# migration-subject: ~/.claude/hooks/file-changed.sh
# migration-verify: jq -e --arg w "$HOME/.claude/file-watch-paths" '[.hooks.FileChanged[]? | select(.matcher == $w) | .hooks[]?.command] as $arm | [.hooks.FileChanged[]? | select(.matcher == "*") | .hooks[]?.command] as $disp | [.hooks.CwdChanged[]?.hooks[]?.command] as $rearm | ($arm | any(. == "~/.claude/hooks/file-changed.sh")) and ($disp | any(. == "~/.claude/hooks/file-changed.sh")) and ($rearm | any(. == "~/.claude/hooks/file-changed.sh"))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0017 — the FileChanged + CwdChanged wiring (docs/plans/HOOK_SURFACE_100P.md § 3e; § 2 "What W3
# should wire" item 3). It is deliberately SEPARATE from 0016, and the separation is the point.
#
# 🚨 THIS IS ONE WIRING IN THREE PARTS, AND NONE OF THEM IS OPTIONAL. § 3e refutes the obvious
# prescription ("use a bare filename; absolute measured 0 rows") by showing ARMING and DISPATCH are
# different mechanisms that a row count can only ever observe the second of:
#
#   part 1  an ABSOLUTE-path matcher   → ARMS the watch durably. `isAbsolute(x)?x:join(cwd,x)`
#                                        passes absolutes through untouched, so this survives a cd.
#                                        It never dispatches, and it is not supposed to.
#   part 2  a `*` matcher sibling      → DISPATCHES. The matcher is regex-tested against
#                                        basename(file_path) (220:430421), so nothing absolute can
#                                        ever match; `*` measured 3 rows in the same run the
#                                        absolute arm measured 0.
#   part 3  a CwdChanged registration  → RE-ARMS. `onCwdChanged` OVERWRITES the dynamic watch list
#                                        wholesale with whatever the CwdChanged hooks return
#                                        (`r = A.watchPaths`). With no CwdChanged registration that
#                                        list is EMPTY after the first `cd`, silently.
#
# A bare-basename matcher alone — the shape the original advice prescribed — is the actively
# dangerous case: a `cd` re-bases it onto the new cwd, so it keeps firing for a DIFFERENT file of
# the same name and looks healthy the whole time.
#
# WHY THIS IS 0017 AND NOT PART OF 0016. Part 3 had NO WORKING IMPLEMENTATION until this wave.
# hooks/file-changed.sh guarded on `file_path` with an early `exit 0` sitting ABOVE its watchPaths
# emit, and a CwdChanged payload carries no file_path — so the handler returned EMPTY stdout on
# exactly the event it was to re-arm on. Measured on both arms 2026-09-07 with
# CC_FILECHANGED_WATCHLIST set:
#     CwdChanged  → stdout EMPTY        FileChanged → {"hookSpecificOutput":{"…","watchPaths":[…]}}
# Registering part 3 before fixing that would have produced a migration whose own verifier read
# GREEN — the command string is present in settings.json either way — over a hook that could not
# perform the one job it was registered for. The guard is now scoped to the LOGGING path
# (tests/file-changed.bats arms 26-29 pin both directions), so this registration is now a working
# wiring rather than a present one.
#
# WHY THE ARMING MATCHER IS THE WATCHLIST FILE ITSELF. Part 1 needs one concrete absolute path, and
# the fleet has no committed watch target yet — the real paths arrive dynamically through
# hooks/file-changed.sh's own `watchPaths` emit, read from $HOME/.claude/file-watch-paths. Arming on
# that file makes the SSOT self-propagating: an edit to the watchlist is itself a watched change, so
# the hook dispatches and re-emits the NEW list without waiting for an unrelated file to move. The
# default posture is unaffected — with no watchlist file the hook emits nothing, exactly as its
# tests pin, so this wiring adds a watch and no behaviour until the operator opts in.
#
# 🚨 AND THIS IS THE ONE STRING HERE THAT IS DELIBERATELY $HOME-EXPANDED, unlike every command.
# The command strings stay the literal `~/.claude/hooks/...` because CC expands those at hook-RUN
# time. A MATCHER is not a command and is not expanded: the arming resolver asks `isAbsolute(x)`,
# and a literal `~/…` is NOT absolute, so it would be joined onto cwd and silently become a
# relative arm — the precise failure part 1 exists to prevent. All five config dirs live under one
# $HOME on one machine, so expanding here is correct rather than a portability slip.
#
# WHY c10. It edits settings.json. Staged, never self-run (migrations/README.md).
set -uo pipefail

# shellcheck disable=SC2088  # literal tilde: data written INTO settings.json, expanded by CC at
# hook-run time. See the header for why the matcher below is the opposite case.
HOOK_CMD='~/.claude/hooks/file-changed.sh'
HOOK_FILE="$HOME/.claude/hooks/file-changed.sh"

# Part 1's absolute arming path — expanded, for the reason in the header.
ARM_MATCHER="$HOME/.claude/file-watch-paths"
DISPATCH_MATCHER='*'
TIMEOUT=5

command -v jq >/dev/null 2>&1 || { printf '0017: jq required\n' >&2; exit 1; }

rc=0

# ── precondition, re-derived at CONSUMPTION rather than trusted from this header ─────────────────
# A registration naming a path that does not run is a no-op that reads GREEN on every verifier.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0017: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi

# ── ASSERT OUR OWN MATCHERS BEFORE WRITING THEM ─────────────────────────────────────────────────
# The silent no-op this whole migration exists to avoid lives in the REGISTRATION, so no runtime
# behaviour of the hook can ever detect it — by the time the hook would notice, it has already
# failed to be called. `--check-matcher` is the predicate, and it is kept inside the handler so the
# rule and the payload reader cannot drift apart. It judges by ROLE: an absolute matcher is correct
# for `arm` and wrong for `dispatch`, which is exactly the asymmetry § 3e turns on.
if ! "$HOOK_FILE" --check-matcher "$ARM_MATCHER" --role arm; then
  printf '0017: the ARMING matcher was refused by the handler'\''s own check; nothing written\n' >&2
  exit 1
fi
if ! "$HOOK_FILE" --check-matcher "$DISPATCH_MATCHER"; then
  printf '0017: the DISPATCH matcher was refused by the handler'\''s own check; nothing written\n' >&2
  exit 1
fi

# ── register one command into one event key of one settings file ────────────────────────────────
# `//= []` then append, so a sibling registration is never clobbered. Groups are matched on the
# (event, matcher, command) triple, not the command alone: this migration writes the SAME command
# twice under FileChanged with two different matchers, and a command-only idempotence test would
# see part 1 and decide part 2 was already done — leaving a wiring that arms and never dispatches.
register() { # <settings-file> <event> <command> <timeout> <matcher-or-empty> <label>
  local f="$1" ev="$2" cmd="$3" to="$4" matcher="$5" label="$6"

  if jq -e --arg c "$cmd" --arg e "$ev" --arg m "$matcher" \
       '[.hooks[$e][]? | select((.matcher // "") == $m) | .hooks[]?.command] | any(. == $c)' \
       "$f" >/dev/null 2>&1; then
    printf '0017: %s [%s %s] — already registered\n' "$f" "$ev" "$label"
    return 0
  fi

  local bak tmp
  bak="$f.bak-0017-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0017: %s — backup FAILED, not touching it\n' "$f" >&2; return 1; }

  tmp="$f.tmp-0017-$$"
  if jq --arg c "$cmd" --arg e "$ev" --arg m "$matcher" --argjson t "$to" \
       '($m | length > 0) as $has |
        (if $has then {"matcher":$m,"hooks":[{"type":"command","command":$c,"timeout":$t}]}
                 else {"hooks":[{"type":"command","command":$c,"timeout":$t}]} end) as $grp |
        .hooks //= {} |
        .hooks[$e] //= [] |
        if (.hooks[$e] | length) == 0
        then .hooks[$e] = [$grp]
        else .hooks[$e] += [$grp]
        end' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify BY CONTENT before it replaces the live file — one malformed settings.json silently
    # kills every registration already in it.
    if jq -e --arg c "$cmd" --arg e "$ev" --arg m "$matcher" \
         '[.hooks[$e][]? | select((.matcher // "") == $m) | .hooks[]?.command] | any(. == $c)' \
         "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0017: %s [%s %s] — registered (backup: %s)\n' "$f" "$ev" "$label" "$bak"
    else
      rm -f "$tmp"; printf '0017: %s [%s %s] — edit did not contain the hook; left unchanged\n' "$f" "$ev" "$label" >&2; return 1
    fi
  else
    rm -f "$tmp"; printf '0017: %s [%s %s] — jq edit FAILED; left unchanged\n' "$f" "$ev" "$label" >&2; return 1
  fi
  return 0
}

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet-config discriminator borrowed from a DIFFERENT event, for 0014's reason: neither
  # FileChanged nor CwdChanged exists in any config yet, so testing for one would skip all five
  # dirs and still exit 0 — a migration that always succeeds by doing nothing.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0017: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  register "$f" FileChanged "$HOOK_CMD" "$TIMEOUT" "$ARM_MATCHER"      "part1/arm"      || rc=1
  register "$f" FileChanged "$HOOK_CMD" "$TIMEOUT" "$DISPATCH_MATCHER" "part2/dispatch" || rc=1
  # CwdChanged takes no matcher — there is no sub-selector on a directory change, and the handler
  # must run on every one of them or the list it re-emits is not the list that was armed.
  register "$f" CwdChanged  "$HOOK_CMD" "$TIMEOUT" ""                  "part3/re-arm"   || rc=1
done

exit "$rc"
