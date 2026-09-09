#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# SC2317/SC2329 ("appears unreachable" / "never invoked") are the standard bats false-positives:
# the linter cannot see that `@test` bodies are invoked by the bats runner. File-level, because it
# is a property of the harness rather than of any single line.
# (NB: no comment line here may BEGIN with the linter's own name — it would parse as a directive,
# SC1073/SC1072, and abort the scan of this entire file.)
#
# config-mirror.zsh :: _cc_oauth_token_env — the per-account `claude setup-token` loader.
#
# WHY THIS SUITE IS SHAPED AROUND THE *UNSET* ARM. CLAUDE_CODE_OAUTH_TOKEN is read from the
# environment and is GLOBAL to the shell. Every launcher (claude, claude2/3/4, cc2/3/4,
# claude-prev2/3/4) is a shell FUNCTION, so several launches share one long-lived interactive
# shell. A set-only loader therefore does not just "miss a case" — it actively CROSS-WIRES:
# `claude3` exports account 3's token, and the next `claude-prev2` in that same shell bearers it
# for account 2. Every assertion below that looks like it is testing "nothing happens" is really
# testing that the previous launch's token was actively cleared.
#
# The positive controls matter as much as the negative ones: a suite that only asserted "the var
# is unset" would pass just as well against a loader that had been deleted outright.

setup() {
  # Hermetic $HOME: this loader reads $HOME/.claude/oauth-tokens/*.token. Without an isolated
  # HOME a leaked default would read the operator's LIVE minted secrets, and the verdict would
  # start depending on which accounts happen to be wired. Enforced by ship-land's hermeticity
  # ratchet, which blocks the land rather than letting the suite look green against live state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"

  # Run the loader in a clean `zsh -f` (the same shell the assert hook uses) with a PRE-EXISTING
  # token in the environment, then print what survived. `$1` is the config dir handed to the
  # loader. The pre-set value is the whole point: it stands in for the previous launcher.
  run_loader() {
    zsh -fc "source '$MIRROR'
             export CLAUDE_CODE_OAUTH_TOKEN=STALE-FROM-PREVIOUS-LAUNCH
             _cc_oauth_token_env '$1'
             printf 'rc=%s\n' \"\$?\"
             printf 'tok=%s\n' \"\${CLAUDE_CODE_OAUTH_TOKEN-<UNSET>}\""
  }
  mktok() {  # $1=account stem, $2=file contents (backslash escapes interpreted)
    # `mkdir -p -m 700` would apply the mode to the DEEPEST component only, leaving the parents
    # at the default umask — chmod separately so the 0700 the real store relies on is exact.
    mkdir -p "$HOME/.claude/oauth-tokens"; chmod 700 "$HOME/.claude/oauth-tokens"
    # '%b' rather than "$2"-as-format: the escape interpretation is wanted (cases below pass
    # '\n' and '\t' as token bodies) but a '%' inside a token body must stay literal.
    printf '%b' "$2" > "$HOME/.claude/oauth-tokens/$1.token"
    chmod 600 "$HOME/.claude/oauth-tokens/$1.token"
  }
}

@test "the loader is version-controlled in the repo (not an unversioned live-only file)" {
  [ -f "$MIRROR" ]
  git -C "$REPO" ls-files --error-unmatch lib/config-mirror.zsh >/dev/null 2>&1
}

# --- the SET arm: positive control ---------------------------------------------------------

@test "EFFECT: a minted token for the launched account IS exported" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next3 'tok-tertiary-abc123'
  run run_loader "$HOME/.claude-tertiary"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=tok-tertiary-abc123' || { echo "got: $output" >&2; return 1; }
}

@test "EFFECT: each of the four config dirs picks up its OWN account file, never a sibling's" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next  'TOK-NEXT'   ; mktok next2 'TOK-NEXT2'
  mktok next3 'TOK-NEXT3'  ; mktok next4 'TOK-NEXT4'
  # The mapping is the one place a typo silently bearers the wrong account's credential at the
  # API, which is invisible from inside the session — so assert all four, not a sample.
  for pair in ".claude-next:TOK-NEXT" ".claude-secondary:TOK-NEXT2" \
              ".claude-tertiary:TOK-NEXT3" ".claude-quaternary:TOK-NEXT4"; do
    run run_loader "$HOME/${pair%%:*}"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx "tok=${pair##*:}" || {
      echo "CROSS-WIRED: ${pair%%:*} did not get ${pair##*:} — got: $output" >&2; return 1; }
  done
}

@test "EFFECT: surrounding whitespace in a hand-pasted token file is trimmed off" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next2 '  tok-with-space \n'
  run run_loader "$HOME/.claude-secondary"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=tok-with-space' || { echo "got: $output" >&2; return 1; }
}

# --- the UNSET arm: this is the cross-account guard -----------------------------------------

@test "EFFECT: launching an account with NO token file CLEARS a previous launch's token" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next3 'tok-tertiary-abc123'          # account 3 is wired…
  run run_loader "$HOME/.claude-secondary"   # …but account 2 is the one being launched
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || {
    echo "CROSS-WIRE: account 2's launch kept a token — got: $output" >&2; return 1; }
}

@test "EFFECT: a config dir that is NOT one of the four accounts clears the token (fail-closed)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next3 'tok-tertiary-abc123'
  # ~/.claude is the stable track's own default store and is deliberately NOT in the account map.
  run run_loader "$HOME/.claude"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || { echo "got: $output" >&2; return 1; }
}

@test "EFFECT: an EMPTY or whitespace-only token file clears rather than bearering garbage" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # A truncated write (interrupted mint, full disk) must not turn into a bogus Authorization
  # header — an absent var falls back to the Keychain credential, which works.
  for body in '' '\n' '   \n\t\n'; do
    mktok next3 "$body"
    run run_loader "$HOME/.claude-tertiary"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx 'tok=<UNSET>' || {
      echo "bogus token exported for body [$body] — got: $output" >&2; return 1; }
  done
}

@test "EFFECT: an unreadable token file clears rather than exporting an empty string" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next3 'tok-tertiary-abc123'
  chmod 000 "$HOME/.claude/oauth-tokens/next3.token"
  run run_loader "$HOME/.claude-tertiary"
  chmod 600 "$HOME/.claude/oauth-tokens/next3.token"   # so BATS_TEST_TMPDIR cleanup succeeds
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || { echo "got: $output" >&2; return 1; }
}

@test "EFFECT: with NO oauth-tokens dir at all, the loader is a clean no-op that still clears" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # This is the state the repo lands in: nothing minted yet. The loader must be inert-but-correct
  # so the wiring can land BEFORE the first mint without changing any launch's behaviour.
  [ ! -d "$HOME/.claude/oauth-tokens" ]
  run run_loader "$HOME/.claude-tertiary"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || { echo "got: $output" >&2; return 1; }
}

# --- wiring into the launcher path -----------------------------------------------------------

@test "EFFECT: _cc_sync_account re-aims the token even when the mirror FAILS and returns early" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # The load-bearing ordering assertion. _cc_sync_account returns 1 early when the config mirror
  # fails; if the token load sat after that return, a failing sync would leave the PREVIOUS
  # launcher's token exported — a silent cross-account bearer on exactly the unhappy path.
  # Forced failure: no ~/.claude/.claude.json for the mirror to work from.
  mkdir -p "$HOME/.claude-tertiary"
  run zsh -fc "source '$MIRROR'
               export CLAUDE_CODE_OAUTH_TOKEN=STALE-FROM-PREVIOUS-LAUNCH
               _cc_sync_account '$HOME/.claude-tertiary' >/dev/null 2>&1
               printf 'tok=%s\n' \"\${CLAUDE_CODE_OAUTH_TOKEN-<UNSET>}\""
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || {
    echo "STALE TOKEN SURVIVED a sync failure — got: $output" >&2; return 1; }
}

@test "_cc_sync_account's own exit status is NOT changed by the token loader" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # The `claude` launcher branches on this rc to print its "config may be stale" warning, so the
  # loader must be status-transparent. Happy path: a real mirror run still exits 0 with a token set.
  mkdir -p "$HOME/.claude" "$HOME/.claude-tertiary"; printf '{}\n' > "$HOME/.claude/.claude.json"
  mktok next3 'tok-tertiary-abc123'
  run zsh -fc "source '$MIRROR'; _cc_sync_account '$HOME/.claude-tertiary' >/dev/null 2>&1
               printf 'rc=%s tok=%s\n' \"\$?\" \"\${CLAUDE_CODE_OAUTH_TOKEN-<UNSET>}\""
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'rc=0 tok=tok-tertiary-abc123' || { echo "got: $output" >&2; return 1; }
}

@test "the loader is NOT the set-only one-liner that cross-wires accounts" {
  # Guards the shape, not just the behaviour: the drafted one-liner
  #   [[ -r $f ]] && export CLAUDE_CODE_OAUTH_TOKEN="$(<$f)"
  # passes every SET-arm test above and still cross-wires, because it never clears. If someone
  # simplifies the function back to it, the EFFECT tests catch it — but this says why in one line.
  grep -q 'unset CLAUDE_CODE_OAUTH_TOKEN' "$MIRROR" || false
  # …and the token load must be reachable before the mirror's early return.
  # Both scans skip comment lines: the rationale comment above the call SAYS "return 1", and
  # matching prose instead of code inverted this assertion on first run.
  local fn_start tok_line ret_line
  fn_start=$(grep -n '^_cc_sync_account()' "$MIRROR" | cut -d: -f1)
  tok_line=$(awk -v s="$fn_start" 'NR>s && !/^[[:space:]]*#/ && /_cc_oauth_token_env/ {print NR; exit}' "$MIRROR")
  ret_line=$(awk -v s="$fn_start" 'NR>s && !/^[[:space:]]*#/ && /return 1/ {print NR; exit}' "$MIRROR")
  [ -n "$tok_line" ] && [ -n "$ret_line" ] && [ "$tok_line" -lt "$ret_line" ]
}

# --- the SCOPE WARNING: an export that arms SILENTLY is the defect ---------------------------
#
# Added 2026-09-08 after the binary was read (docs/research/setup-token-scope-refutation-
# 2026-09-08.md). Exporting this token narrows the session to user:inference and bypasses the
# Keychain credential outright, and EVERY downstream consumer degrades quietly rather than
# erroring — Claude in Chrome silently disabled, claude.ai org connectors silently skipped, org
# UUID deterministically unresolved. Silence is the whole defect, so loudness is the whole fix.
#
# Red-proof status, stated honestly rather than implied: the first two cases FAIL against the
# pre-fix loader (which emitted nothing at all) and pass after. The last two are GUARDS — they
# also pass pre-fix, and exist to stop the warning being narrowed or switched off later. They are
# not evidence the fix works; the first two are.

@test "EFFECT: exporting a minted token WARNS that the session is inference-only (red-proof)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next 'TOK-NEXT'
  run run_loader "$HOME/.claude-next"
  [ "$status" -eq 0 ]
  # The token must still be exported — a warning that cost the export would be a worse bug.
  echo "$output" | grep -qx 'tok=TOK-NEXT' || { echo "export lost: $output" >&2; return 1; }
  echo "$output" | grep -q 'user:inference ONLY' || {
    echo "SILENT ARM: no scope warning on export — got: $output" >&2; return 1; }
  echo "$output" | grep -q 'next' || { echo "warning does not name the account: $output" >&2; return 1; }
}

@test "EFFECT: the warning names the CURE, not just the symptom (red-proof)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next4 'TOK-NEXT4'
  run run_loader "$HOME/.claude-quaternary"
  [ "$status" -eq 0 ]
  # Naming the exact file to delete is what makes this actionable rather than merely alarming.
  echo "$output" | grep -q "rm .*oauth-tokens/next4.token" || {
    echo "no actionable cure in the warning — got: $output" >&2; return 1; }
}

@test "GUARD: the UNSET arm is SILENT — the warning must not fire when no token is borne" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mktok next3 'TOK-NEXT3'                    # account 3 wired…
  run run_loader "$HOME/.claude-secondary"   # …account 2 launched: clears, bears nothing
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tok=<UNSET>' || { echo "got: $output" >&2; return 1; }
  # A warning that fired on every launch would carry as little information as one that never did.
  if echo "$output" | grep -q '\[oauth-token\]'; then
    echo "warning fired on the UNSET arm — got: $output" >&2; return 1
  fi
}

@test "GUARD: the scope warning has no opt-out variable" {
  # A warning each participant can silently switch off is not a warning — the same defect
  # 0fd5dc64f fixed in cc-bats. Keyed on the loader body so a future suppression flag reddens
  # here rather than shipping quietly.
  #
  # STRIP COMMENTS FIRST. The first cut of this guard matched the word "suppression" inside the
  # loader's OWN comment explaining why there is no suppression switch — it convicted the
  # documentation of being the defect it documents. A guard that reads prose is matching
  # spellings, not the class; delete the prose, then match CODE.
  local body code
  body="$(sed -n '/^_cc_oauth_token_env()/,/^}/p' "$MIRROR")"
  [ -n "$body" ]
  echo "$body" | grep -q 'print -ru2' || {
    echo "the warning is gone from the loader entirely" >&2; return 1; }
  code="$(echo "$body" | sed -e 's/[[:space:]]*#.*$//')"
  # An opt-out can only work by BRANCHING on something before the print, so look for a guarded
  # print or an early return — the shapes a switch must take — not for suggestive words.
  if echo "$code" | grep -qE '(\[\[|\[|if|&&|\|\|)[^|]*(QUIET|SILENT|SUPPRESS|NO_WARN|WARN=|VERBOSE)'; then
    echo "an opt-out switch appeared in the loader CODE — got: $code" >&2; return 1
  fi
  # And the print must not be conditional on anything at all: exactly the two unguarded lines.
  local n
  n="$(echo "$code" | grep -c 'print -ru2')"
  [ "$n" -eq 2 ] || { echo "expected 2 unguarded warning lines, found $n" >&2; return 1; }
}
