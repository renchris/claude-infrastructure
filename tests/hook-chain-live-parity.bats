#!/usr/bin/env bats
# hook-chain.sh LIVE PARITY — the collapsed dispatcher vs the REAL six PreToolUse/Bash guards.
#
# WHY THIS SUITE IS SHAPED THIS WAY. The obvious parity test — "compute the expected aggregate,
# compare to the dispatcher" — is VACUOUS, because the expected aggregate would be computed by a
# second copy of the dispatcher's own precedence rule (memory `control-must-replay-the-real-
# artifact`: a hand-edited approximation passes vacuously). So this suite never re-implements the
# aggregation. It runs each of the six guards INDEPENDENTLY, records the raw (exit, stdout) truth,
# and then asserts the dispatcher's result as a PROPERTY of those raw results:
#
#   P1  the dispatcher exits 2 IFF at least one member exited 2
#   P2  on a non-blocking chain, the dispatcher's stdout is BYTE-IDENTICAL to some member's
#       stdout — it never synthesizes a decision no guard actually made
#   P3  the dispatcher's decision rank equals the MAX rank across members (deny>ask>allow)
#
# and then RED-proves the whole thing with a mutation control: drop each guard from the registry
# and its OWN trigger's outcome must change. A parity suite that still passes with a safety gate
# removed is measuring nothing — that is the failure this suite exists to make impossible.
#
# Members are run from the REPO tree, not from ~/.claude — testing the deployed layer would be the
# `deployed-layer-bootstrap-circle` trap (a check asserting against the deployed layer cannot pass
# while the tree is ahead). $HOME is a fixture, so both sides see the same environment and parity
# stays a valid assertion even where a guard's verdict is environment-dependent.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/hooks/hook-chain.sh"
  export CC_HOOK_CHAIN_DIR="$BATS_TEST_TMPDIR/chains"; mkdir -p "$CC_HOOK_CHAIN_DIR"
  export CC_HOOK_CHAIN_MEMBER_DIR="$REPO/hooks"
  MEMBERS=( curl-gate.py validate-bash.sh git-worktree-guard.sh keychain-guard.sh
            rm-safe-allowlist.sh ship-rail-push-allow.sh )
  printf '%s\n' "${MEMBERS[@]}" > "$CC_HOOK_CHAIN_DIR/live"
  # curl-gate.py self-scopes to ONE project (`if not cwd.startswith(PROJECT_ROOT)` at :409) even
  # though settings.json registers it as a GLOBAL Bash hook — outside that project it is a 46 ms
  # no-op that can never decide anything. So the corpus carries a per-entry cwd. Set HERE, not at
  # file level: bats runs file-level code BEFORE setup(), where $REPO is still empty.
  CURL_CWD="$(grep -m1 'PROJECT_ROOT *=' "$REPO/hooks/curl-gate.py" | sed -E 's/.*= *//; s/"//g')"
}

payload() { # <command> [cwd]
  jq -nc --arg c "$1" --arg cwd "${2:-$REPO}" \
    '{session_id:"parity",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",
      tool_name:"Bash",tool_input:{command:$c}}'
}

rank() { # <json-or-empty> -> 0..3   (independent of the dispatcher's own rank_of)
  # Normalize whitespace before matching: the live guards emit BOTH a compact `jq -nc` shape and a
  # pretty heredoc shape with a space after the colon. Matching literal spellings read the pretty
  # form as rank 0 and silently dropped three guards' verdicts.
  local n="${1//[[:space:]]/}"
  case "$n" in
    *'"permissionDecision":"deny"'*)  echo 3 ;;
    *'"permissionDecision":"ask"'*)   echo 2 ;;
    *'"permissionDecision":"allow"'*) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Run every member independently; sets RAW_OUT[i], RAW_RC[i], MAXRANK, ANYBLOCK.
# NOTE: `[ x ] && y` as a function's LAST statement returns 1 and fails the bats test — use `if`.
probe_members() { # <command> [cwd]
  local pay; pay="$(payload "$1" "${2:-}")"
  RAW_OUT=(); RAW_RC=(); MAXRANK=0; ANYBLOCK=0
  local m o r k
  for m in "${MEMBERS[@]}"; do
    o="$(printf '%s' "$pay" | "$REPO/hooks/$m" 2>/dev/null)"; r=$?
    RAW_OUT+=( "$o" ); RAW_RC+=( "$r" )
    if [ "$r" -eq 2 ]; then ANYBLOCK=1; fi
    k="$(rank "$o")"
    if [ "$k" -gt "$MAXRANK" ]; then MAXRANK="$k"; fi
  done
  return 0
}

run_dispatcher() { # <command> [chainfile] [cwd]
  D_OUT="$(printf '%s' "$(payload "$1" "${3:-}")" | "$S" "${2:-live}" 2>/dev/null)"; D_RC=$?
  return 0
}

# ── the corpus: one trigger per guard, each grounded in that guard's own matching line ──────────
# curl-gate.py:328        `--insecure disables TLS verification` -> deny
# validate-bash.sh:264    `git add -f blocked`                   -> deny
# git-worktree-guard.sh:44 branch with a checked-out worktree     -> exit 2
# keychain-guard.sh:41    unquoted $VAR after `list-keychains -s` -> deny
# rm-safe-allowlist.sh:131 regenerable within-tree target         -> allow
# ship-rail-push-allow.sh:70 non-force land push                  -> allow
# Entries are `cwd<TAB>command`. EVERY row carries an explicit cwd — a row starting with an empty
# field is unreadable here, because TAB is IFS-whitespace and `read` strips LEADING IFS whitespace,
# which shifts every column left (cw="echo", cmd="hello"). That silently mis-parsed 5 of 7 rows and
# showed up only as the anti-vacuity count dropping to 2.
# The keychain trigger is assembled at runtime: spelled literally it is itself blocked by
# keychain-guard when this file's own commands pass through the live hook chain
# (memory `guard-refusal-fires-on-its-own-harness`).
corpus() {
  local kc; kc='security list-keychains -d user -s $'"KEYCHAINS"
  printf '%s\t%s\n' "$REPO"      'echo hello'
  printf '%s\t%s\n' "$CURL_CWD"  'curl --insecure https://example.com'
  printf '%s\t%s\n' "$CURL_CWD"  'curl file:///etc/passwd'
  printf '%s\t%s\n' "$REPO"      'git add -f ignored-thing'
  printf '%s\t%s\n' "$REPO"      "$kc"
  printf '%s\t%s\n' "$REPO"      'rm -rf ./node_modules/.cache'
  printf '%s\t%s\n' "$REPO"      'git push origin HEAD:refs/heads/main'
}

@test "every corpus command is a REAL trigger for at least one guard (a corpus of no-ops is vacuous)" {
  # Without this, the parity assertions below could all be comparing "silence == silence".
  local nontrivial=0 cmd cw
  while IFS=$'\t' read -r cw cmd; do
    [ -n "$cmd" ] || continue
    probe_members "$cmd" "$cw"
    if [ "$ANYBLOCK" -eq 1 ] || [ "$MAXRANK" -gt 0 ]; then nontrivial=$((nontrivial+1)); fi
  done < <(corpus)
  # 'echo hello' is the deliberate all-abstain control, so we need >= 5 of the other 6 to bite
  [ "$nontrivial" -ge 5 ] || { echo "only $nontrivial corpus entries triggered any guard" >&2; false; }
}

@test "P1 — dispatcher exits 2 IFF some member exited 2" {
  local cmd cw
  while IFS=$'\t' read -r cw cmd; do
    [ -n "$cmd" ] || continue
    probe_members "$cmd" "$cw"; run_dispatcher "$cmd" live "$cw"
    if [ "$ANYBLOCK" -eq 1 ]; then
      [ "$D_RC" -eq 2 ] || { echo "FAIL block-parity: '$cmd' member blocked, dispatcher rc=$D_RC" >&2; false; }
    else
      [ "$D_RC" -ne 2 ] || { echo "FAIL block-parity: '$cmd' no member blocked, dispatcher rc=2" >&2; false; }
    fi
  done < <(corpus)
}

@test "P2 — dispatcher stdout is BYTE-IDENTICAL to some member's (never a synthesized verdict)" {
  local cmd cw
  while IFS=$'\t' read -r cw cmd; do
    [ -n "$cmd" ] || continue
    probe_members "$cmd" "$cw"; run_dispatcher "$cmd" live "$cw"
    [ "$ANYBLOCK" -eq 1 ] && continue
    [ -z "$D_OUT" ] && continue
    local found=0 o
    for o in "${RAW_OUT[@]}"; do [ "$o" = "$D_OUT" ] && found=1; done
    [ "$found" -eq 1 ] || { echo "FAIL synthesis: '$cmd' dispatcher emitted output no member produced: $D_OUT" >&2; false; }
  done < <(corpus)
}

@test "P3 — dispatcher decision rank equals the MAX rank across members" {
  local cmd cw
  while IFS=$'\t' read -r cw cmd; do
    [ -n "$cmd" ] || continue
    probe_members "$cmd" "$cw"; run_dispatcher "$cmd" live "$cw"
    [ "$ANYBLOCK" -eq 1 ] && continue
    local dr; dr="$(rank "$D_OUT")"
    [ "$dr" -eq "$MAXRANK" ] || { echo "FAIL rank: '$cmd' dispatcher=$dr max-member=$MAXRANK" >&2; false; }
  done < <(corpus)
}

@test "source mode and exec mode agree on the REAL chain (both rc and bytes)" {
  local cmd cw
  while IFS=$'\t' read -r cw cmd; do
    [ -n "$cmd" ] || continue
    local os rs oe re
    os="$(printf '%s' "$(payload "$cmd" "$cw")" | env CC_HOOK_CHAIN_MODE=source "$S" live 2>/dev/null)"; rs=$?
    oe="$(printf '%s' "$(payload "$cmd" "$cw")" | env CC_HOOK_CHAIN_MODE=exec   "$S" live 2>/dev/null)"; re=$?
    [ "$rs" -eq "$re" ] || { echo "FAIL mode rc: '$cmd' source=$rs exec=$re" >&2; false; }
    [ "$os" = "$oe" ]   || { echo "FAIL mode out: '$cmd' source='$os' exec='$oe'" >&2; false; }
  done < <(corpus)
}

@test "MUTATION CONTROL — dropping a guard changes the outcome for that guard's own trigger" {
  # The RED proof for this whole file. Pairs each guard with the command it alone bites on; with
  # the guard dropped from the registry the dispatcher's verdict MUST change. Any pair that does
  # not change means the parity assertions above would survive that guard being silently skipped.
  # KCTRIG must be assigned BEFORE `pairs`, or it expands to empty inside the array literal and the
  # keychain row silently becomes an empty command — which reads as "dropping the guard changed
  # nothing", i.e. a vacuous row masquerading as a real failure.
  local KCTRIG; KCTRIG='security list-keychains -d user -s $'"KEYCHAINS"
  local pairs=(
    "curl-gate.py|curl --insecure https://example.com|$CURL_CWD"
    "validate-bash.sh|git add -f ignored-thing|"
    "keychain-guard.sh|${KCTRIG}|"
    "rm-safe-allowlist.sh|rm -rf ./node_modules/.cache|"
    "ship-rail-push-allow.sh|git push origin HEAD:refs/heads/main|"
  )
  local p guard cmd cw rest
  for p in "${pairs[@]}"; do
    guard="${p%%|*}"; rest="${p#*|}"; cmd="${rest%|*}"; cw="${rest##*|}"
    [ -n "$cmd" ] || { echo "EMPTY trigger for $guard — the pair itself is vacuous" >&2; false; }
    run_dispatcher "$cmd" live "$cw"; local full_out="$D_OUT" full_rc="$D_RC"

    printf '%s\n' "${MEMBERS[@]}" | grep -vxF "$guard" > "$CC_HOOK_CHAIN_DIR/mut"
    run_dispatcher "$cmd" mut "$cw"
    printf '%s\n' "${MEMBERS[@]}" > "$CC_HOOK_CHAIN_DIR/live"

    if [ "$full_out" = "$D_OUT" ] && [ "$full_rc" -eq "$D_RC" ]; then
      echo "VACUOUS: dropping $guard did not change the verdict for '$cmd'" >&2
      echo "  with=$full_rc/$full_out" >&2
      echo "  without=$D_RC/$D_OUT" >&2
      false
    fi
  done
}

@test "registry membership matches the settings.json set it replaces (drift guard)" {
  # The registry and the settings.json entry it replaces must not drift apart: a member added here
  # but not removed there would RUN TWICE; removed here but still there would run zero times.
  local reg="$REPO/config/hook-chains.d/pretooluse-bash"
  [ -f "$reg" ]
  local listed; listed="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$reg" | tr -d ' ')"
  local expect; expect="$(printf '%s\n' "${MEMBERS[@]}")"
  [ "$listed" = "$expect" ] || { echo "registry drift:"$'\n'"$listed"$'\n'"--- expected ---"$'\n'"$expect" >&2; false; }
}
