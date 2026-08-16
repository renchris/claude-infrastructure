#!/usr/bin/env bats
# Phase 3 autonomy — handoff-fire.sh pre-trust: fired sessions skip the workspace-trust dialog
# (a gate separate from --permission-mode auto) so a --notify-back peer never stalls.
#
# The two helpers are self-contained, so we extract + source them to test the real code, plus
# assert the dir-resolution via --dry-run (no real fire).

setup() {
  # M11 pins — this suite reaches the real fire path via --dry-run, so without them the
  # BOX'S MOOD is a test input. Measured 2026-07-31 on a PRISTINE tree at load 41.72 on
  # 10 cores (4.17/core vs the 2.0 ceiling): tests 10, 11, 17 and 23 went RED with exit 9
  # — the capacity gate's refusal, not a defect in anything they assert. Because
  # ship-land reports any red as "a VERDICT about your diff", that blocked EVERY land in
  # the repo, including diffs nowhere near handoff-fire.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # config_dir_for_launcher now asks the accounts.json-generated map FIRST (item 64828ce9c5a5), so
  # the map must be loaded or the SSOT branch would hit an undefined command, return non-zero, and
  # fall through to the digit fallback — the test would then pass while exercising only the half it
  # is not there to pin. Sourced from the real generated file (never a hand-written stand-in, which
  # would pass against an approximation), and HARD-FAILED if absent so the vacuum can never be quiet.
  ACCT_MAP="$REPO/lib/account-map.generated.sh"
  [ -r "$ACCT_MAP" ] || { echo "missing $ACCT_MAP — regenerate with scripts/gen-account-map.sh" >&2; return 1; }
  # shellcheck source=/dev/null
  . "$ACCT_MAP"
  eval "$(sed -n '/^config_dir_for_launcher() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pre_trust() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^write_role() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^refresh_roles_for() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^check_goal_length() {/,/^}/p' "$HF")"
}

# A minimal side-effect-free fire harness (HOME isolates config/projects/registry/roles; IT2_BIN
# stubs the it2 transport; the shim must EXIST so the REAL_IT2 sed|head probe doesn't abort under
# pipefail). Shared by the --as-role E2E and the /goal-guard tests below.
_fire_harness() {
  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/projects/p" "$HOMEDIR/.claude/cc-registry" "$HOMEDIR/.claude/bin" "$BATS_TEST_TMPDIR/bin"
  PANE="FAKEPANE-0000-0000-0000-000000000001"
  cat > "$BATS_TEST_TMPDIR/bin/it2" <<STUB
#!/bin/bash
LAST="$BATS_TEST_TMPDIR/it2-last-send"
case "\$1 \$2" in
  "session send"|"session run") printf '%s' "\${!#}" > "\$LAST" ;;
esac
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  *"session read"*)  cat "\$LAST" 2>/dev/null ;;
  *) : ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/it2"
  cp "$BATS_TEST_TMPDIR/bin/it2" "$HOMEDIR/.claude/bin/it2"
}

@test "pre_trust: marks an untrusted dir trusted (hasTrustDialogAccepted:true)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  run pre_trust /tmp/untrusted-abc "$cfg"
  [ "$status" -eq 0 ]
  run jq -r '.projects["/tmp/untrusted-abc"].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]
}

@test "pre_trust: canonicalizes — trusts the RESOLVED path (/tmp → /private/tmp), not the raw one" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  real="$(mktemp -d /tmp/pt-canon-XXXXXX)"           # /tmp/… which macOS resolves to /private/tmp/…
  resolved="$(cd "$real" && pwd -P)"
  pre_trust "$real" "$cfg"
  run jq -r --arg d "$resolved" '.projects[$d].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]                              # stored under the resolved path Claude checks
  if [ "$real" != "$resolved" ]; then                # …and NOT under the raw /tmp path
    run jq -r --arg d "$real" '.projects[$d] // "absent"' "$cfg/.claude.json"
    [ "$output" = "absent" ]
  fi
  rm -rf "$real"
}

@test "pre_trust: creates the projects entry when the dir is absent" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{}' > "$cfg/.claude.json"
  pre_trust /tmp/brand-new "$cfg"
  run jq -r '.projects["/tmp/brand-new"].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]
}

@test "pre_trust: preserves existing project keys (surgical merge, not overwrite)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"
  echo '{"projects":{"/x":{"allowedTools":["Bash"],"hasTrustDialogAccepted":false}}}' > "$cfg/.claude.json"
  pre_trust /x "$cfg"
  run jq -c '.projects["/x"]' "$cfg/.claude.json"
  [[ "$output" == *'"allowedTools":["Bash"]'* ]] || false
  [[ "$output" == *'"hasTrustDialogAccepted":true'* ]]
}

@test "pre_trust: idempotent — an already-trusted dir leaves the file byte-identical" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"
  echo '{"projects":{"/x":{"hasTrustDialogAccepted":true}}}' > "$cfg/.claude.json"
  before="$(cat "$cfg/.claude.json")"
  pre_trust /x "$cfg"
  [ "$(cat "$cfg/.claude.json")" = "$before" ]
}

@test "pre_trust: keeps --permission-mode auto tool-safety (sets ONLY trust/onboarding keys)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  pre_trust /x "$cfg"
  run jq -r '.projects["/x"] | keys | join(",")' "$cfg/.claude.json"
  [ "$output" = "hasCompletedProjectOnboarding,hasTrustDialogAccepted" ]
}

@test "pre_trust: missing .claude.json is a clean no-op" {
  run pre_trust /x "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 0 ]
}

@test "pre_trust: empty dir arg is a no-op" {
  run pre_trust "" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "config_dir_for_launcher maps launcher → account config dir" {
  # RE-ADJUDICATED 2026-08-08 (item 64828ce9c5a5). This assertion used to read
  #   [ "$(config_dir_for_launcher claude)" = "$HOME/.claude" ]
  # and was WRONG — it pinned the bug. Its comment reasoned that the trailing digit is the key and
  # that `claude`, carrying none, "MUST fall through to the account-1 default arm". The premise is
  # right and the conclusion does not follow: account 1's config dir is ~/.claude-NEXT, so the
  # default arm answers the wrong file, and pre_trust wrote its trust record where the fired session
  # would never look. The 2026-08-01 claudeN rename is what made this live, and the same change
  # hardened this test around it — which is why it survived: the digit heuristic was re-affirmed at
  # exactly the moment it acquired a counter-example.
  #
  # The next two lines are the discriminating pair, and they must stay adjacent. `claude` and
  # `claude-prev` are BOTH account 1 and BOTH carry no digit, yet resolve to DIFFERENT dirs (eval
  # track vs stable track). No rule keyed on the name's shape can separate them — only the SSOT can.
  # So the pair is mutation-killing in both directions: revert to a pure digit map and `claude`
  # fails; drop the digit fallback and `claude-prev` fails.
  [ "$(config_dir_for_launcher claude)"      = "$HOME/.claude-next" ]   # SSOT (accounts.json)
  [ "$(config_dir_for_launcher claude-prev)" = "$HOME/.claude" ]        # digit fallback, correct here
  [ "$(config_dir_for_launcher claude2)" = "$HOME/.claude-secondary" ]
  [ "$(config_dir_for_launcher claude3)" = "$HOME/.claude-tertiary" ]
  [ "$(config_dir_for_launcher claude4)" = "$HOME/.claude-quaternary" ]
  # A non-`claudeN` stem the SSOT does not declare still maps by its digit — `--launcher` is
  # unvalidated and can name the stable track. (This slot used to be claude-fable2; that family is
  # deleted, but the prefix-agnostic property it pinned is what matters and claude-prev2 pins it
  # with a name that still exists.)
  [ "$(config_dir_for_launcher claude-prev2)" = "$HOME/.claude-secondary" ]
}

# The durable invariant behind the table above: for EVERY account the SSOT declares, the launcher→dir
# answer must equal the account→dir answer. The table pins today's four names and goes stale the day
# a name changes or a 5th account lands; this derives both sides from accounts.json, so it keeps
# testing the real contract — the two directions of one mapping may never disagree — without naming
# anything. It is exactly the disagreement that shipped: launcher_for() was migrated to the SSOT and
# config_dir_for_launcher() was left deriving, so the pair silently drifted apart for account 1.
@test "config_dir_for_launcher agrees with the SSOT for every declared account" {
  local acct launcher dir_from_launcher dir_from_account n=0
  while read -r acct; do
    [ -n "$acct" ] || continue
    launcher="$(cc_acct_launcher_for_name "$acct")" || { echo "no launcher declared for $acct" >&2; return 1; }
    cc_acct_dir_for_name "$acct" || { echo "no config_dir declared for $acct" >&2; return 1; }
    dir_from_account="$CC_ACCT_DIR"
    dir_from_launcher="$(config_dir_for_launcher "$launcher")"
    [ "$dir_from_launcher" = "$dir_from_account" ] \
      || { echo "DISAGREEMENT for $acct: launcher '$launcher' → $dir_from_launcher, account → $dir_from_account" >&2; return 1; }
    n=$((n + 1))
  done <<< "$(jq -r '.accounts[].name' "$REPO/accounts.json")"
  # FLOOR, not an exact count — an exact one would red on the suite's own growth when a 5th account
  # lands, which is the change this test most needs to survive. The floor only has to prove the loop
  # ran over a real population rather than an empty one (an empty `while read` passes vacuously).
  [ "$n" -ge 4 ]
}

@test "dry-run: --worktree fire pre-trusts the worktree path in the account config" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --worktree wslug --account next2 --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'pre-trust: .*/\.worktrees/wslug → \.claude-secondary'
}

# Account 1 gets its own call-site test because it is the account the mapping got WRONG (item
# 64828ce9c5a5), and because the two tests above both name a DIGIT account — so between them they
# could not distinguish a correct function from a correct function handed the wrong argument. The
# assertion deliberately includes the trailing " (" : `.claude` is a strict prefix of `.claude-next`,
# so a looser pattern would match the buggy output too and pass while asserting nothing.
@test "dry-run: --worktree fire on account 1 pre-trusts in ~/.claude-next, not ~/.claude" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --worktree wslug --account next --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'pre-trust: .*/\.worktrees/wslug → \.claude-next \('
}

@test "dry-run: --cwd fire pre-trusts the cwd in the account config" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --cwd /tmp/somedir --in-place --account next4 --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'pre-trust: /tmp/somedir → .claude-quaternary'
}

# The PLAIN recycle — no relocation, no account re-pick — used to be the one fire path that skipped
# pre_trust entirely, on the premise that "the running session in that dir already proves it is
# trusted". Measured FALSE on 2026-08-15: `.claude-tertiary` recorded
# /Users/chrisren/Development/personal as hasTrustDialogAccepted:false (and carried no
# hasCompletedProjectOnboarding key, so pre_trust had provably never written it) while that same
# entry's lastDuration showed a 2.3 h session had run there on that account. The consequence is not
# the trust dialog — it is that Claude Code drops project-scoped SETTINGS in a folder its config dir
# has not recorded as trusted (v2.1.196+), so the repo's own settings.local.json approval of its
# .mcp.json servers went inert and the recycled pane stalled at "2 new MCP servers found in this
# project" with the brief unread behind it.
#
# `--session-id` + `env -u ITERM_SESSION_ID` is what makes this hermetic: without it the recycle
# resolves its target from the firing pane, so the test would pass at a desk and abort under
# launchd. `CC_RECYCLE_REPICK=off` is load-bearing in the other direction — a re-pick sets
# RECYCLE_REPICK_FROM, which reaches pre_trust through the OLD branch, so without the kill switch
# this test could pass while the plain path stayed broken.
@test "dry-run: a PLAIN recycle (no reloc, no re-pick) still pre-trusts the launch dir" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run env -u ITERM_SESSION_ID CC_RECYCLE_REPICK=off \
      bash "$HF" --recycle --session-id FAKE-0000-0000-0000-000000000001 \
                 --prompt-file "$BATS_TEST_TMPDIR/p.txt" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^pre-trust: .+ → \.claude'
}

# …and the test above alone is NOT enough, because the dry-run ANNOUNCEMENT and the real pre_trust
# CALL are two different lines in two different branches. A revert that re-guarded only the call
# would leave the announcement unconditional and that test green — an assertion whose span is
# narrower than its subject. The call site itself lives in top-level dispatch code that cannot be
# sourced without running a fire, so this pins it structurally: within the `elif [ "$RECYCLE" = 1 ]`
# branch, pre_trust must not sit inside a conditional. Deliberately narrow — it asserts only the
# absence of a guard, so ordinary edits to that branch do not trip it.
@test "the recycle branch calls pre_trust UNCONDITIONALLY (the dry-run echo is not the subject)" {
  local branch
  branch="$(sed -n '/^elif \[ "\$RECYCLE" = 1 \]; then/,/^  recycle_fire$/p' "$HF")"
  [ -n "$branch" ] || { echo "could not locate the recycle dispatch branch in $HF" >&2; return 1; }
  printf '%s\n' "$branch" | grep -qE '^  pre_trust "\$LAUNCH_DIR"' \
    || { echo "pre_trust is not called at the recycle branch's top level:"; printf '%s\n' "$branch"; return 1; }
  # The guard that used to wrap it. Its return would silently restore the 2026-08-15 stall.
  # BLOCK FORM, not `A && { …; return 1; }` — that spelling is dead under bats errexit and the
  # dead-assertion ratchet reds the land for it (it caught this very line). Verified in BOTH
  # directions with a mutant: re-wrapping pre_trust in the old `if [ "$RECYCLE_RELOC" = 1 ]` guard
  # makes this test fail, and the unguarded tree passes it.
  if printf '%s\n' "$branch" | grep -qE 'if \[ "\$RECYCLE_RELOC" = 1 \]'; then
    echo "pre_trust is guarded again by RECYCLE_RELOC/REPICK — the plain recycle is unprotected"
    return 1
  fi
  return 0
}

# ---- P0-15 role indirection (SO-1 ping-to-dead-pane break) -----------------------------------

@test "write_role: writes the pane uuid to cc-roles/<role>" {
  dir="$BATS_TEST_TMPDIR/roles"
  write_role "$dir" operator PANE-NEW-0001
  [ "$(cat "$dir/operator")" = "PANE-NEW-0001" ]
}

@test "write_role: empty pane arg is a no-op (no file created)" {
  dir="$BATS_TEST_TMPDIR/roles2"
  write_role "$dir" operator ""
  [ ! -e "$dir/operator" ]
}

@test "refresh_roles_for: repoints a role naming the OLD pane to the successor (self-close)" {
  dir="$BATS_TEST_TMPDIR/roles3"; mkdir -p "$dir"
  printf 'OLD-PANE\n' > "$dir/operator"
  refresh_roles_for "$dir" OLD-PANE SUCCESSOR-PANE
  [ "$(cat "$dir/operator")" = "SUCCESSOR-PANE" ]
}

@test "refresh_roles_for: post-recycle role file still points at the (same-pane) successor" {
  dir="$BATS_TEST_TMPDIR/roles4"; mkdir -p "$dir"
  printf 'SID-PANE\n' > "$dir/operator"      # recycle keeps the pane: old == new == SID
  refresh_roles_for "$dir" SID-PANE SID-PANE
  [ "$(cat "$dir/operator")" = "SID-PANE" ]
}

@test "refresh_roles_for: a role NOT naming the old pane is left untouched" {
  dir="$BATS_TEST_TMPDIR/roles5"; mkdir -p "$dir"
  printf 'SOMEONE-ELSE\n' > "$dir/monitor"
  refresh_roles_for "$dir" OLD-PANE SUCCESSOR-PANE
  [ "$(cat "$dir/monitor")" = "SOMEONE-ELSE" ]
}

@test "E2E: --as-role writes cc-roles/<role> = the FIRED pane on an engaged fire" {
  _fire_harness
  # Engagement needs a real ASSISTANT turn, not just a transcript carrying the marker (transcript
  # BIRTH is what a rejected/never-submitted prompt also produces — item ff2d6609a33e).
  { printf '{"type":"user","message":{"role":"user","content":"brief ROLE-MARK ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n'
  } > "$HOMEDIR/.claude/projects/p/s.jsonl"
  printf 'BRIEF\n' > "$BATS_TEST_TMPDIR/brief.md"
  run env HOME="$HOMEDIR" IT2_BIN="$BATS_TEST_TMPDIR/bin/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 FIRE_ENGAGE_MARKER=ROLE-MARK \
    bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/brief.md" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire --as-role operator
  [ "$status" -eq 0 ]
  [ "$(cat "$HOMEDIR/.claude/cc-roles/operator")" = "$PANE" ]
}

# ---- P0-16 /goal >4000-char guard (a19 D-11) ------------------------------------------------
# (GOAL_MAX_CHARS shrinks the 4000 cap so fixtures stay tiny.)

@test "check_goal_length: a /goal body over the cap fails loud (exit 1, names the size + pointer fix)" {
  printf '/goal %s\n' "$(head -c 30 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qE '/goal condition is [0-9]+ chars'
  printf '%s\n' "$output" | grep -q 'POINTER form'
}

@test "check_goal_length: /goal body exactly at the cap passes (0)" {
  printf '/goal %s\n' "$(head -c 20 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "check_goal_length: no /goal line -> ok (0)" {
  printf 'a normal brief\nmore lines\n' > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "check_goal_length: a long NON-/goal line does not trip the guard" {
  printf 'DELIVERABLE: %s\n' "$(head -c 50 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "E2E: over-cap /goal is rejected PRE-fire (--dry-run), non-zero, no command printed" {
  printf '/goal %s\n' "$(head -c 30 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  run env GOAL_MAX_CHARS=20 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/g.md" \
    --launcher claude-test --cwd "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'HARD-CAPS /goal'
  ! printf '%s\n' "$output" | grep -q 'command:'
}

# This E2E isolates THIS section's subject — check_goal_length (the /goal LENGTH guard) — proving it
# ADMITS an under-cap /goal. Since item c89b9c7b1526 the sibling check_slash_head runs immediately
# after and REFUSES any leading slash command regardless of length, so a bare under-cap /goal now
# exits 1 at that second guard. FIRE_ALLOW_SLASH_HEAD=1 bypasses ONLY check_slash_head (it is the
# first line of that function), leaving check_goal_length fully active — which is exactly what this
# test must exercise. The universalized slash-head refusal has its own coverage in
# fire-engagement.bats and handoff-payload-gates.bats.
@test "E2E: an under-cap /goal passes the LENGTH guard (--dry-run exit 0, slash-head escape on)" {
  printf '/goal do the thing\n\nbrief body\n' > "$BATS_TEST_TMPDIR/g.md"
  run env GOAL_MAX_CHARS=4000 FIRE_ALLOW_SLASH_HEAD=1 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/g.md" \
    --launcher claude-test --cwd "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
}

# NEW (c89b9c7b1526): the same under-cap /goal, WITHOUT the escape, is now refused at the pre-fire
# chokepoint — the E2E proof that the universalized guard fires through the whole script, not just as
# an extracted unit. This is the [S2] hole closed: a slash-headed payload no longer reaches spawn.
@test "E2E: an under-cap /goal is REFUSED pre-fire by the universalized slash-head guard" {
  printf '/goal do the thing\n\nbrief body\n' > "$BATS_TEST_TMPDIR/g2.md"
  run env GOAL_MAX_CHARS=4000 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/g2.md" \
    --launcher claude-test --cwd "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q "STARTS with the slash command '/goal'"
  ! printf '%s\n' "$output" | grep -q 'command:'
}
