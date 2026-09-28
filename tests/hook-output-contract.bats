#!/usr/bin/env bats
# hook-output-contract.bats — a STATIC lint over what hooks and bin tools hand the model.
#
# THE DEFECT CLASS (docs/research/truememory-2026-09-27.md §3.1). TrueMemory's context hooks
# printed a top-level `{"additionalContext":…}`, which Claude Code logs as unrecognized and drops;
# its test checked the PRODUCER's shape and never the consumer's. Our own version of "tested the
# producer, not what reaches the model": `claudeMdExcludes` drops the situational rules file while
# six strings told the model it "loads by default", and one told it to delete the only resident
# pointer on that basis. These checks read the SOURCE, so they cost nothing per hook and cover
# every emitter at once, including ones no suite fires.
#
#   (a) every `additionalContext` KEY sits under `hookSpecificOutput` — never at the object root;
#   (b) no line pairs the situational rules file (or a variable holding it) with "loads by default";
#   (c) a hook registered for MORE THAN ONE event takes `hookEventName` from the payload's
#       `hook_event_name`, never a literal — CC throws or drops a name that does not match the
#       event that fired it.
#
# Each check is a function run over the live tree AND over a planted bad fixture, so a check that
# silently matches nothing (the vacuous lint) goes red on its own fixture. Assertions are simple
# commands only: bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]` would pass vacuously.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  F="$BATS_TEST_TMPDIR/fx"; mkdir -p "$F"
  # Hermetic: nothing here reads $HOME, and the fixture keeps it that way if a helper ever does.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# The scanned population: every hook, every hook lib, and every TEXT file in bin/ (Python
# included — the counter-example was Python).
scan_files() {
  local f
  for f in "$REPO"/hooks/*.sh "$REPO"/hooks/lib/*.sh; do printf '%s\n' "$f"; done
  for f in "$REPO"/bin/*; do
    [ -f "$f" ] && grep -Iq . "$f" && printf '%s\n' "$f"
  done
  return 0
}

# (a) → prints FILE:LINE for each offending additionalContext KEY; silent when clean.
# Two arms: a root-shape arm (the first `{` on the line opens `additionalContext`, e.g.
# `jq -nc '{additionalContext:$c}'` or `json.dumps({"additionalContext": …})`), and a window arm
# (the key must have `hookSpecificOutput` on its own line or within the 10 before it — heredoc and
# multi-line jq builders put the parent a few lines up; measured 0 misses at 6, so 10 has margin).
check_a() {
  awk -v W=10 '
    FNR == 1 { delete buf; n = 0 }
    {
      n++; buf[n % W] = $0
      if ($0 ~ /^[[:space:]]*#/) next
      if ($0 ~ /^[^{#]*\{[[:space:]]*"?additionalContext"?[[:space:]]*:/) { print FILENAME ":" FNR ": root"; next }
      if ($0 ~ /"additionalContext"[[:space:]]*:/ || $0 ~ /(^|[{,[:space:]])additionalContext[[:space:]]*:/) {
        ok = 0
        for (i = 0; i < W && n - i > 0; i++) if (buf[(n - i) % W] ~ /hookSpecificOutput/) { ok = 1; break }
        if (!ok) print FILENAME ":" FNR ": no-parent"
      }
    }' "$@"
}

# (b) → prints FILE:LINE for any "loads by default" (any case) on a line, or within the 3 after a
# line, that names the situational file or one of the variables the six sites hold it in.
check_b() {
  awk '
    FNR == 1 { delete buf; n = 0 }
    {
      n++; buf[n % 4] = $0
      if (tolower($0) !~ /loads by default/) next
      for (i = 0; i < 4 && n - i > 0; i++) {
        l = buf[(n - i) % 4]
        if (tolower(l) ~ /situational/ || l ~ /\$\{?(RULES|RULES_HINT|RULES_FILE|dest)\}?([^A-Za-z0-9_]|$)/) {
          print FILENAME ":" FNR; break
        }
      }
    }' "$@"
}

# (c) The multi-event registrations, pinned by hand from ~/.claude/settings.json on 2026-09-27
# (the test must not read live settings). Refresh this list when a hook gains a second event.
MULTI_EVENT_HOOKS="cc-permission-beacon.sh dod-persist.sh live-session-registry.sh log-bash.sh mailbox-drain.sh notify.sh session-beat.sh teammate-checkpoint.sh"

# Exempt ONLY where every emit provably runs under one event arm, and the premise is re-checked
# below rather than trusted: dod-persist.sh emits solely from its `SessionStart)` dispatch arm.
C_EXEMPT="dod-persist.sh"

# check_c <file> → prints FILE:LINE for each LITERAL hookEventName in a hookSpecificOutput emitter.
check_c() {
  grep -q 'hookSpecificOutput' "$1" || return 0
  grep -nE 'hookEventName\\?"?[[:space:]]*:[[:space:]]*\\?"[A-Za-z]+' "$1" | grep -v '^[0-9]*:[[:space:]]*#' \
    | sed "s|^|$1:|" || true
}

# ── (a) ──────────────────────────────────────────────────────────────────────────────────────────

@test "a: every additionalContext key in hooks/ and bin/ sits under hookSpecificOutput" {
  n=0; while IFS= read -r _; do n=$((n + 1)); done < <(scan_files)
  [ "$n" -gt 100 ]                          # the population is real, not an empty glob
  files=(); while IFS= read -r f; do files+=("$f"); done < <(scan_files)
  run check_a "${files[@]}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a: RED on a planted root-level additionalContext — jq, JSON heredoc, and Python" {
  printf '%s\n' "jq -nc --arg c \"\$m\" '{additionalContext:\$c}'" >"$F/jq.sh"
  printf '%s\n' 'cat <<EOF' '{' '  "additionalContext": "x"' '}' 'EOF' >"$F/heredoc.sh"
  printf '%s\n' 'print(json.dumps({"additionalContext": msg}))' >"$F/py"
  run check_a "$F/jq.sh"; [ -n "$output" ]
  run check_a "$F/heredoc.sh"; [ -n "$output" ]
  run check_a "$F/py"; [ -n "$output" ]
}

@test "a: CONTROL — the sanctioned nested shapes are not flagged" {
  printf '%s\n' "jq -nc --arg c \"\$m\" '{hookSpecificOutput:{hookEventName:\$e,additionalContext:\$c}}'" >"$F/ok1.sh"
  printf '%s\n' 'cat <<EOF' '{' '  "hookSpecificOutput": {' '    "hookEventName": "PreToolUse",' '    "additionalContext": "x"' '  }' '}' 'EOF' >"$F/ok2.sh"
  run check_a "$F/ok1.sh" "$F/ok2.sh"
  [ -z "$output" ]
}

# ── (b) ──────────────────────────────────────────────────────────────────────────────────────────

@test "b: no hook or bin line pairs the situational rules file with 'loads by default'" {
  files=(); while IFS= read -r f; do files+=("$f"); done < <(scan_files)
  run check_b "${files[@]}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# shellcheck disable=SC2016  # the fixtures ARE literal `${RULES}` / `$RULES_HINT` source text
@test "b: RED on the planted pre-fix shapes — a path literal, a \${RULES} string, a \$RULES_HINT string" {
  printf '%s\n' '# `.claude/rules/agent-operating-lessons-situational.md`, which also loads by default.)' >"$F/b1.sh"
  printf '%s\n' 'CTX="ALREADY CITED in ${RULES}, which loads by default, so DELETE it"' >"$F/b2.sh"
  printf '%s\n' 'NUDGE="belongs in $RULES_HINT, which loads by default and has no cap"' >"$F/b3.sh"
  run check_b "$F/b1.sh"; [ -n "$output" ]
  run check_b "$F/b2.sh"; [ -n "$output" ]
  run check_b "$F/b3.sh"; [ -n "$output" ]
}

@test "b: CONTROL — replaying the REAL pre-fix files flags every one of the 8 known lines" {
  # bd9a0c982 is the last trunk commit before the fix; a planted fixture proves the regex fires on
  # a shape we imagined, this proves it fires on the artifact that actually shipped.
  base=bd9a0c982
  git -C "$REPO" cat-file -e "$base^{commit}" 2>/dev/null || skip "history for $base not present"
  for f in hooks/memory-index-drain.sh hooks/memory-nudge.sh bin/cc-memory-rotate hooks/lib/memory-index-budget.sh; do
    git -C "$REPO" show "$base:$f" >"$F/$(basename "$f")"
  done
  run check_b "$F/memory-index-drain.sh" "$F/memory-nudge.sh" "$F/cc-memory-rotate" "$F/memory-index-budget.sh"
  [ "$(printf '%s\n' "$output" | sed 's|.*/||' | tr '\n' ' ')" = \
    "memory-index-drain.sh:249 memory-index-drain.sh:275 memory-index-drain.sh:284 memory-nudge.sh:537 memory-nudge.sh:560 cc-memory-rotate:29 cc-memory-rotate:522 memory-index-budget.sh:348 " ]
}

@test "b: the per-prompt nudge states the load CONDITIONALLY and keeps the pointer when excluded" {
  line="$(grep -E '^NUDGE="MEMORY CHECK' "$REPO/hooks/memory-nudge.sh")"
  [ -n "$line" ]
  printf '%s' "$line" | grep -qF 'loads unless claudeMdExcludes lists it'
  printf '%s' "$line" | grep -qF 'keep the MEMORY.md bullet'
  run grep -ciF 'loads by default' <<<"$line"
  [ "$output" = "0" ]
  # and it pays no settings read per prompt: the hook never touches claudeMdExcludes itself
  run grep -nE 'rules_file_loads|settings\.json' "$REPO/hooks/memory-nudge.sh"
  [ "$status" -ne 0 ]
}

# ── (c) ──────────────────────────────────────────────────────────────────────────────────────────

@test "c: every multi-event hook that emits hookSpecificOutput takes hookEventName from the payload" {
  for h in $MULTI_EVENT_HOOKS; do
    [ -f "$REPO/hooks/$h" ]                 # a renamed hook must fail here, not drop out of scope
    case " $C_EXEMPT " in *" $h "*) continue ;; esac
    run check_c "$REPO/hooks/$h"
    [ -z "$output" ] || { printf 'literal hookEventName in %s\n' "$output" >&2; false; }
  done
}

@test "c: the dod-persist exemption still holds — its only literal is SessionStart, emitted from that arm" {
  f="$REPO/hooks/dod-persist.sh"
  run bash -c "grep -oE 'hookEventName:\"[A-Za-z]+\"' '$f' | sort -u"
  [ "$output" = 'hookEventName:"SessionStart"' ]
  grep -q 'hook_event_name' "$f"            # it dispatches on the payload's event
  arm="$(awk '/^  PreCompact\)/,/^    ;;/' "$f")"
  [ -n "$arm" ]
  run grep -cE 'hookSpecificOutput|_dod_inject_lineage_only' <<<"$arm"
  [ "$output" = "0" ]
}

@test "c: RED on a planted multi-event hook with a literal hookEventName (jq and JSON forms)" {
  printf '%s\n' "jq -nc --arg c x '{hookSpecificOutput:{hookEventName:\"PostToolUse\",additionalContext:\$c}}'" >"$F/c1.sh"
  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "x"}}' >"$F/c2.sh"
  run check_c "$F/c1.sh"; [ -n "$output" ]
  run check_c "$F/c2.sh"; [ -n "$output" ]
  # CONTROL: the payload-derived form passes
  printf '%s\n' "jq -nc --arg e \"\$EVT\" --arg c x '{hookSpecificOutput:{hookEventName:\$e,additionalContext:\$c}}'" >"$F/c3.sh"
  run check_c "$F/c3.sh"; [ -z "$output" ]
}
