#!/bin/bash
# propose-goal-flag-watch.sh — the standing watch behind cc-backlog `2a65b9bf722d`
# ("ProposeGoal (`tengu_propose_goal`) is default-off upstream — adopt when the flag flips").
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────────
# That row is a `not-yet-true` WATCH row: nothing in the tree is watching the flag, so the only thing
# that can ever close it is its own falsifier going true. Its stored falsifier is one line:
#
#     jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json
#
# and `docs/research/propose-goal-flag-recheck-2026-09-10.md` §5 identified the hole it carries — the
# probe cannot tell "the flag is off" from "nobody asked GrowthBook lately", because a config dir that
# has not been launched in weeks answers `false` for the second reason while looking exactly like the
# first. Left alone that makes the row UNFALSIFIABLE IN THE LIMIT: once every cache goes stale the
# probe answers `false` forever and no reading can change it.
#
# §5 also establishes that the fix CANNOT be a staleness clause folded into the falsifier — `any` over
# an empty array is already `false`, so the guarded and unguarded probes return the identical `false`
# in exactly the case that needed distinguishing. Freshness has to be a SECOND READING, because it is
# a question about the INSTRUMENT and not about the flag. This script is that pair, plus the
# version-proof binary read from §4, with each arm carrying its own control.
#
# Measured 2026-09-11 on a cloud VM, which is what turned §5's hole from a hypothesis into a defect:
# run there verbatim, the stored falsifier prints `false` and exits **2** —
#
#     jq: error: Could not open file /root/.claude*/.claude.json: No such file or directory
#     false
#     rc=2
#
# — because the desk-shaped glob matches nothing on a box whose only cache is `$HOME/.claude.json`.
# An unmatched glob stays literal, jq fails to open it, and the WORD PRINTED is byte-identical to a
# genuine negative. So a consumer reading the printed `false`, or reading only `rc != 0`, reads
# "instrument could not answer" as "flag is off". That is the same conflation §5 named, arriving
# through the population rather than through staleness.
#
# ── EXIT CODES (uniform across modes: 0 = SIGNAL · 1 = no signal · 2 = NON-VERDICT) ───────────────
# The 2 is the whole point. A mode that cannot answer must not spend the "no" code, because every
# consumer of the stored falsifier treats non-zero as "keep the row open" and would therefore never
# learn its instrument had gone blind.
#
#   --falsify   0 = RETRACT THE ROW: `tengu_propose_goal == true` in a cache refreshed inside the
#                   freshness window. This is the ONLY arm that should ever close the row.
#               1 = observed off, on a healthy instrument — keep waiting.
#               2 = NON-VERDICT: no readable cache, or every readable cache is stale. Means "nobody
#                   asked", NOT "off". Go launch a session; do not read this as a negative.
#   --health    0 = at least one cache was refreshed inside the window (so --falsify's 1 means "off")
#               1 = every readable cache is stale
#               2 = no readable cache at all
#   --binary    0 = SIGNAL, one of two shapes §4 names: the gate's default literal is `!0` (flipped),
#                   or the gate pattern does not match WHILE `ProposeGoal` is still present (minified
#                   past the pattern — read it by hand, do not read the miss as a removal).
#               1 = gate still reads `!1` — default false, unchanged.
#               2 = NON-VERDICT: no readable subject, or the subject fails its own tripwire.
#               3 = `ProposeGoal` absent from a subject that passes the tripwire — the feature looks
#                   REMOVED upstream, which retires the row for a different reason than a flip.
#                   Verify by hand before acting: this is a signal to look, not an auto-retraction.
#   --report    prints every arm with per-member detail. 0 if any arm signals, 1 if none does and
#               every instrument was healthy, 2 if none does and an instrument could not answer.
#   --selftest  runs the fixture table below (§5's seven cache arms + the binary arms) and exits
#               non-zero if any row disagrees with its expected verdict.
#
# ── WHY PER-MEMBER AND NOT AN AGGREGATE ───────────────────────────────────────────────────────────
# Every cache is read on its own and reported by NAME with its age and its value. An aggregate over
# the population ("does anything say true") can only ever detect a TOTAL zero, and the healthy members
# are precisely what keep it quiet while one member goes blind — the shape MEMORY records as
# `aggregate-control-cannot-see-a-per-member-zero`. Reading files one at a time also means a single
# unreadable cache degrades to one NON-VERDICT member rather than killing the whole read, which is
# what `jq -es` over a glob does today.
#
# ── THE POPULATION, AND WHY IT IS WIDER THAN THE STORED GLOB ──────────────────────────────────────
# §5 keeps `~/.claude*/.claude.json` and notes it EXCLUDES `$HOME/.claude.json`, on the strength of an
# A12-skeptic2 measurement that that file was stale since 2026-08-11. That exclusion is a perishable
# fact standing in for a criterion: the criterion is "do not read a stale cache", and the freshness
# filter enforces it directly, for every member, at read time. So `$HOME/.claude.json` is included and
# the filter decides — which on the desk reproduces the stored behaviour whenever the old measurement
# still holds, and on a cloud VM (where it is the ONLY cache, written at this session's own boot) is
# the difference between a reading and the rc-2 above. Seam: PGW_CONFIG_PATHS overrides the whole set.
#
# ── SEAMS ─────────────────────────────────────────────────────────────────────────────────────────
#   PGW_MAXAGE_S       freshness window in seconds (default 604800 = 7 d)
#   PGW_CONFIG_PATHS   newline-separated cache paths; overrides the default enumeration entirely
#   PGW_CLAUDE_BIN     subject for --binary. SET-BUT-EMPTY disables the binary arm (--report skips it,
#                      --binary exits 2), which is the honest state on a box with no native build.
#   PGW_NOW            epoch seconds, for fixtures
#
# This script READS. It flips no flag, writes no setting and touches no live file (C10).

set -uo pipefail

PGW_MAXAGE_S="${PGW_MAXAGE_S:-604800}"

pgw_now() { printf '%s\n' "${PGW_NOW:-$(date +%s)}"; }

# ── cache enumeration ─────────────────────────────────────────────────────────────────────────────
# Existence-filtered and de-duplicated. An unmatched glob stays literal in bash, so the -f test is
# what keeps a literal `…/.claude*/.claude.json` out of the set instead of handing it to jq.
pgw_cache_paths() {
  if [ -n "${PGW_CONFIG_PATHS+set}" ]; then
    printf '%s\n' "$PGW_CONFIG_PATHS" | while IFS= read -r p; do
      [ -n "$p" ] && [ -f "$p" ] && printf '%s\n' "$p"
    done
    return 0
  fi
  local p
  { for p in "$HOME"/.claude*/.claude.json; do [ -f "$p" ] && printf '%s\n' "$p"; done
    [ -f "$HOME/.claude.json" ] && printf '%s\n' "$HOME/.claude.json"
  } | awk '!seen[$0]++'
}

# Reads ONE cache. Prints "<ts_ms>\t<value>" and returns 0, or returns 1 if the file cannot be parsed.
# `value` is one of: true · false · ABSENT (no such key) · NOCACHE (no feature object at all).
# Deliberately NOT written with jq's `//`, which treats a literal `false` as null and would report a
# key that is present-and-false as ABSENT — the one conflation this whole file exists to avoid.
pgw_read_cache() {
  jq -r '
    [ (.cachedGrowthBookFeaturesAt // 0),
      ( if (.cachedGrowthBookFeatures | type) != "object" then "NOCACHE"
        elif (.cachedGrowthBookFeatures | has("tengu_propose_goal")) then (.cachedGrowthBookFeatures.tengu_propose_goal | tostring)
        else "ABSENT" end )
    ] | @tsv' "$1" 2>/dev/null
}

pgw_age_h() {  # $1 = ts_ms (0 = no stamp), $2 = now
  [ "$1" -gt 0 ] || { printf 'no-stamp'; return 0; }
  printf '%dh' $(( ( $2 - $1 / 1000 ) / 3600 ))
}

# ── the cache arms ────────────────────────────────────────────────────────────────────────────────
# Sets: PGW_N_TOTAL PGW_N_FRESH PGW_N_UNREADABLE PGW_FRESH_TRUE PGW_STALE_TRUE, and PGW_ROWS (a
# rendered per-member table). Callers read those rather than re-walking the population.
pgw_scan_caches() {
  local now ts_ms value age fresh path row
  now="$(pgw_now)"
  PGW_N_TOTAL=0; PGW_N_FRESH=0; PGW_N_UNREADABLE=0; PGW_FRESH_TRUE=0; PGW_STALE_TRUE=0; PGW_ROWS=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    PGW_N_TOTAL=$((PGW_N_TOTAL + 1))
    row="$(pgw_read_cache "$path")"
    if [ -z "$row" ]; then
      PGW_N_UNREADABLE=$((PGW_N_UNREADABLE + 1))
      PGW_ROWS="${PGW_ROWS}  ⚠️  ${path} — UNREADABLE (not JSON, or no read permission)"$'\n'
      continue
    fi
    ts_ms="${row%%	*}"; value="${row#*	}"
    case "$ts_ms" in ''|*[!0-9]*) ts_ms=0 ;; esac
    age=$(( now - ts_ms / 1000 ))
    if [ "$ts_ms" -gt 0 ] && [ "$age" -lt "$PGW_MAXAGE_S" ]; then
      fresh=fresh; PGW_N_FRESH=$((PGW_N_FRESH + 1))
      [ "$value" = "true" ] && PGW_FRESH_TRUE=$((PGW_FRESH_TRUE + 1))
    else
      fresh=STALE
      [ "$value" = "true" ] && PGW_STALE_TRUE=$((PGW_STALE_TRUE + 1))
    fi
    PGW_ROWS="${PGW_ROWS}$(printf '  %-6s %-9s tengu_propose_goal=%-8s %s' \
      "$fresh" "$(pgw_age_h "$ts_ms" "$now")" "$value" "$path")"$'\n'
  done < <(pgw_cache_paths)
}

pgw_falsify() {
  pgw_scan_caches
  [ "$PGW_FRESH_TRUE" -gt 0 ] && return 0
  [ "$PGW_N_FRESH" -gt 0 ] && return 1
  return 2
}

pgw_health() {
  pgw_scan_caches
  [ "$PGW_N_FRESH" -gt 0 ] && return 0
  [ "$PGW_N_TOTAL" -gt "$PGW_N_UNREADABLE" ] && return 1
  return 2
}

# ── the binary arm ────────────────────────────────────────────────────────────────────────────────
# §4: cite the gate by its ARGUMENT, never by its symbol or offset. The symbol is minified and moves
# every release — measured `mct` (A12, 2026-09-08), `cgt` (2.1.267, 2026-09-10), `syt` (2.1.268,
# 2026-09-11) — so a re-check that greps for last month's symbol finds nothing, which reads exactly
# like the feature was removed. The argument string is what is stable.
#
# Written with BRACKET EXPRESSIONS rather than backslash escapes: `\(` and `\{` in an ERE are
# "undefined" by POSIX and only literal by convention, so the escaped spelling is a bet on which
# regex implementation reads it. `[(]` and `[{]` are literal in every one. This matters because the
# subject runs on the operator's macOS box (BSD grep) and in CI, and a pattern that silently fails
# to compile leaves PGW_GATE empty — which this file reads as "minified past the pattern", i.e. a
# SIGNAL. A portability bug would therefore surface as a false retraction of the row.
PGW_GATE_RE='function [A-Za-z0-9_$]+[(][)][{]return [A-Za-z0-9_$]+[(]"tengu_propose_goal",![01][)][}]'

pgw_resolve_bin() {
  if [ -n "${PGW_CLAUDE_BIN+set}" ]; then
    # set-but-EMPTY disables the arm verbatim; a set value is used as given, never second-guessed.
    [ -n "$PGW_CLAUDE_BIN" ] && [ -r "$PGW_CLAUDE_BIN" ] && printf '%s\n' "$PGW_CLAUDE_BIN"
    return 0
  fi
  local c
  for c in /opt/claude-code/bin/claude "$HOME/.local/share/claude/bin/claude"; do
    [ -r "$c" ] && [ ! -d "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  # A PATH `claude` is taken only when it is not a script: §4 measured an unrelated npm cli.js at
  # 2.1.42 sitting beside the native build, and greps against IT return 0 for all three strings —
  # i.e. the wrong subject answers "feature removed" with total confidence.
  c="$(command -v claude 2>/dev/null)" || return 0
  [ -n "$c" ] || return 0
  [ -r "$c" ] || return 0
  # Captured, not piped. `head -c 2 … | grep -q` has grep exit on its first match, SIGPIPE the head,
  # and under pipefail the whole pipeline then reads FALSE on a MATCH — the polarity inverts exactly
  # where the guard matters, and the wrong subject is accepted.
  local magic; magic="$(head -c 2 "$c" 2>/dev/null)" || true
  case "$magic" in '#!') return 0 ;; esac
  printf '%s\n' "$c"
  return 0
}

# Sets PGW_BIN PGW_GATE PGW_N_PROPOSEGOAL PGW_TRIPWIRE; returns the --binary exit code.
pgw_binary() {
  local n
  PGW_BIN="$(pgw_resolve_bin)"; PGW_GATE=""; PGW_N_PROPOSEGOAL=0; PGW_TRIPWIRE=0
  [ -n "$PGW_BIN" ] || return 2

  # Tripwire FIRST. Without it an absence of `ProposeGoal` in some file that is not a Claude Code
  # build at all would be reported as "removed upstream" — a confident retraction signal minted by
  # pointing the instrument at the wrong subject. `tengu_` is carried by every build regardless of
  # this feature, so its absence means "wrong subject", not "no feature".
  n="$(grep -a -c -F 'tengu_' "$PGW_BIN" 2>/dev/null)" || true
  case "${n:-0}" in ''|*[!0-9]*) n=0 ;; esac
  PGW_TRIPWIRE="$n"
  [ "$PGW_TRIPWIRE" -gt 0 ] || return 2

  # `tr -dc '0-9'` is load-bearing, not defensive: BSD `wc -l` PADS its output with leading blanks
  # (`      18`) where GNU `wc -l` does not, so the guard below — which rejects any non-digit — read
  # the padded form as garbage and silently scored 0. On macOS that made `bin_minified` (no gate
  # match, feature present) return 3 "the feature is gone" instead of 0 "read it by hand": a false
  # RETRACTION signal for the row, from a platform difference in a count nobody looks at. Green on
  # Linux, red on the operator's box — which is exactly how the land gate found it.
  n="$(grep -a -o -F 'ProposeGoal' "$PGW_BIN" 2>/dev/null | wc -l | tr -dc '0-9')" || true
  case "${n:-0}" in ''|*[!0-9]*) n=0 ;; esac
  PGW_N_PROPOSEGOAL="$n"

  PGW_GATE="$(grep -a -o -E "$PGW_GATE_RE" "$PGW_BIN" 2>/dev/null | head -1)" || true

  if [ -n "$PGW_GATE" ]; then
    case "$PGW_GATE" in
      *',!0)}') return 0 ;;   # the default literal flipped — THE signal
      *) return 1 ;;          # still `,!1)}`
    esac
  fi
  # No gate match. §4's two readings, and they are opposite verdicts:
  [ "$PGW_N_PROPOSEGOAL" -gt 0 ] && return 0   # present but minified past the pattern → read by hand
  return 3                                     # genuinely absent from a verified subject
}

# ── report ────────────────────────────────────────────────────────────────────────────────────────
pgw_report() {
  local frc brc
  pgw_falsify; frc=$?
  pgw_binary;  brc=$?

  echo "propose-goal-flag-watch — cc-backlog 2a65b9bf722d (adopt ProposeGoal when tengu_propose_goal flips)"
  echo
  printf '(1) FALSIFIER  rc=%d  %s\n' "$frc" \
    "$(case $frc in 0) echo '🚩 FLAG IS TRUE on a fresh cache — RETRACT THE ROW';;
                    1) echo 'off, on a healthy instrument — keep waiting';;
                    *) echo '⚠️  NON-VERDICT — nobody asked GrowthBook inside the window; this is NOT "off"';;
       esac)"
  printf '    window %ss · %d cache(s) · %d fresh · %d unreadable · fresh-true %d · stale-true %d\n' \
    "$PGW_MAXAGE_S" "$PGW_N_TOTAL" "$PGW_N_FRESH" "$PGW_N_UNREADABLE" "$PGW_FRESH_TRUE" "$PGW_STALE_TRUE"
  [ -n "$PGW_ROWS" ] && printf '%s' "$PGW_ROWS"
  [ "$PGW_N_TOTAL" -eq 0 ] && echo "  ⚠️  no cache file in the population at all (PGW_CONFIG_PATHS to name one)"
  [ "$PGW_STALE_TRUE" -gt 0 ] && [ "$PGW_N_FRESH" -eq 0 ] && \
    echo "  ⚠️  a STALE cache reads true and nothing fresh disagrees — launch a session and re-read before acting"
  echo
  printf '(2) BINARY     rc=%d  %s\n' "$brc" \
    "$(case $brc in 0) echo '🚩 SIGNAL — the gate default moved, or the gate minified past the pattern';;
                    1) echo 'gate still default-false';;
                    3) echo '🚩 ProposeGoal ABSENT from a verified build — feature may be gone upstream';;
                    *) echo '⚠️  NON-VERDICT — no readable subject, or the subject failed its tripwire';;
       esac)"
  printf '    subject %s\n' "${PGW_BIN:-<none>}"
  printf '    gate    %s\n' "${PGW_GATE:-<no match for the argument-keyed pattern>}"
  printf '    control ProposeGoal×%s · tripwire tengu_×%s\n' "$PGW_N_PROPOSEGOAL" "$PGW_TRIPWIRE"
  echo
  if [ "$frc" -eq 0 ] || [ "$brc" -eq 0 ] || [ "$brc" -eq 3 ]; then
    echo "⇒ SIGNAL. Re-read by hand, then dispose of cc-backlog 2a65b9bf722d citing what you read."
    return 0
  fi
  if [ "$frc" -eq 2 ] || [ "$brc" -eq 2 ]; then
    echo "⇒ NON-VERDICT. An instrument could not answer; nothing here says the flag is off."
    return 2
  fi
  echo "⇒ still off, on healthy instruments. The row stays open; there is nothing to adopt yet."
  return 1
}

# ── selftest ──────────────────────────────────────────────────────────────────────────────────────
# The load-bearing rows are the `true`-flag ones. Without them a probe that always returns "off"
# looks identical to a correct one, and the row would be waiting on a falsifier that cannot fire.
pgw_selftest() {
  local pass=0 fail=0 tmp
  # PGW_TMP is global on purpose: an EXIT trap fires after the function's locals are gone, and a
  # `rm -rf "$tmp"` on an out-of-scope name dies `unbound variable` under `set -u` — noise printed
  # after the verdict, which is exactly where a reader stops trusting the verdict.
  PGW_TMP="$(mktemp -d)" || return 2
  tmp="$PGW_TMP"
  trap 'rm -rf "$PGW_TMP"' EXIT

  local NOW=1789000000
  local FRESH=$(( (NOW - 3600) * 1000 ))      # 1 h old
  local STALE=$(( (NOW - 30 * 86400) * 1000 )) # 30 d old

  mk() { printf '%s\n' "$2" > "$tmp/$1.json"; printf '%s\n' "$tmp/$1.json"; }
  mk fresh_true   "{\"cachedGrowthBookFeaturesAt\":$FRESH,\"cachedGrowthBookFeatures\":{\"tengu_propose_goal\":true}}" >/dev/null
  mk fresh_false  "{\"cachedGrowthBookFeaturesAt\":$FRESH,\"cachedGrowthBookFeatures\":{\"tengu_propose_goal\":false}}" >/dev/null
  mk fresh_absent "{\"cachedGrowthBookFeaturesAt\":$FRESH,\"cachedGrowthBookFeatures\":{\"tengu_other\":1}}" >/dev/null
  mk stale_true   "{\"cachedGrowthBookFeaturesAt\":$STALE,\"cachedGrowthBookFeatures\":{\"tengu_propose_goal\":true}}" >/dev/null
  mk nostamp_true "{\"cachedGrowthBookFeatures\":{\"tengu_propose_goal\":true}}" >/dev/null
  printf 'not json at all\n' > "$tmp/broken.json"

  # $1 label · $2 expected rc · $3 mode · $4 payload (a cache path list, or a binary path).
  #
  # The mode is a WORD the case below dispatches on, not a function name passed through "$@". The
  # first draft used three one-line helpers invoked as `chk`'s "$@", which shellcheck cannot follow:
  # it reports them unreachable as SC2317 up to 0.9 and as **SC2329** from 0.10, so a file carrying
  # only the SC2317 disable is clean on one shellcheck and RED on the next. That is what the land
  # gate found. Silencing the new code too would work and would stay a bet on the next rename;
  # dispatching on a word removes the indirection, so no version has anything to report.
  #
  # Each arm re-execs THIS file so the fixture reaches the real entry point rather than an in-process
  # copy of it. The assignments are prefixes to `bash`, so they do reach the child's environment —
  # which the "no subject → NON-VERDICT" arm proves by observing rc 2 rather than by assuming it. A
  # pattern moved out of argv that never arrives is how an empty selector becomes a universal one.
  chk() {
    local label="$1" want="$2" mode="$3" payload="$4" got=0
    case "$mode" in
      falsify) PGW_NOW="$NOW" PGW_CONFIG_PATHS="$payload" PGW_CLAUDE_BIN='' bash "$0" --falsify >/dev/null 2>&1; got=$? ;;
      health)  PGW_NOW="$NOW" PGW_CONFIG_PATHS="$payload" PGW_CLAUDE_BIN='' bash "$0" --health  >/dev/null 2>&1; got=$? ;;
      binary)  PGW_CLAUDE_BIN="$payload" bash "$0" --binary >/dev/null 2>&1; got=$? ;;
      *) printf '  FAIL %-38s unknown mode %s\n' "$label" "$mode"; fail=$((fail + 1)); return 0 ;;
    esac
    if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); printf '  ok   %-38s rc=%d\n' "$label" "$got"
    else fail=$((fail + 1)); printf '  FAIL %-38s rc=%d want=%d\n' "$label" "$got" "$want"; fi
  }

  echo "cache arms (§5's table, all seven rows):"
  chk "fresh+true → RETRACT"            0 falsify "$tmp/fresh_true.json"
  chk "fresh+false → off"               1 falsify "$tmp/fresh_false.json"
  chk "fresh+absent → off"              1 falsify "$tmp/fresh_absent.json"
  chk "stale+true only → NON-VERDICT"   2 falsify "$tmp/stale_true.json"
  chk "no stamp → NON-VERDICT"          2 falsify "$tmp/nostamp_true.json"
  chk "stale-true + fresh-absent → off" 1 falsify "$tmp/stale_true.json"$'\n'"$tmp/fresh_absent.json"
  chk "stale-true + fresh-true → RETRACT" 0 falsify "$tmp/stale_true.json"$'\n'"$tmp/fresh_true.json"
  chk "empty population → NON-VERDICT"  2 falsify "$tmp/does-not-exist.json"
  chk "unreadable only → NON-VERDICT"   2 falsify "$tmp/broken.json"
  echo "health arm:"
  chk "health: fresh present"           0 health "$tmp/fresh_absent.json"
  chk "health: all stale"               1 health "$tmp/stale_true.json"
  chk "health: nothing readable"        2 health "$tmp/broken.json"

  printf 'function xyz(){return I("tengu_propose_goal",!1)}\ntengu_other\nProposeGoal\n' > "$tmp/bin_off"
  printf 'function q9(){return I("tengu_propose_goal",!0)}\ntengu_other\nProposeGoal\n' > "$tmp/bin_on"
  printf 'tengu_other\nProposeGoal used here\n' > "$tmp/bin_minified"
  printf 'tengu_other\nnothing of interest\n' > "$tmp/bin_removed"
  printf 'nothing of interest at all\n' > "$tmp/bin_wrongsubject"
  echo "binary arms (§4):"
  chk "gate !1 → still off"             1 binary "$tmp/bin_off"
  chk "gate !0 → SIGNAL"                0 binary "$tmp/bin_on"
  chk "no gate + ProposeGoal → SIGNAL"  0 binary "$tmp/bin_minified"
  chk "no gate, no feature → removed"   3 binary "$tmp/bin_removed"
  chk "tripwire fails → NON-VERDICT"    2 binary "$tmp/bin_wrongsubject"
  chk "no subject → NON-VERDICT"        2 binary ""

  printf '\npropose-goal-flag-watch --selftest: %d ok · %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || return 1
  return 0
}

case "${1:---report}" in
  --falsify)  pgw_falsify; exit $? ;;
  --health)   pgw_health;  exit $? ;;
  --binary)   pgw_binary;  exit $? ;;
  --report)   pgw_report;  exit $? ;;
  --selftest) pgw_selftest; exit $? ;;
  # Prints the header to wherever it actually ends, rather than to a line number that drifts every
  # time the header grows — as it just did, leaving `--help` cut off mid-sentence at line 70.
  -h|--help)  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 && NF { exit }' "$0"; exit 0 ;;
  *) printf 'usage: %s [--report|--falsify|--health|--binary|--selftest]\n' "$(basename "$0")" >&2; exit 2 ;;
esac
