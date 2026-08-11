#!/usr/bin/env bats
# P0-14 desk-invariant — the desk-existence + engagement invariant. The tool's --selftest RED-proves
# every branch against stubbed dirs; these bats add (a) the selftest exit-code + check-count contract
# and (b) independent CLI-level end-to-end runs of `--once` through the real override surface (proving
# evaluate() works outside the in-script selftest, not just the selftest helper).

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DI="$REPO/scripts/desk-invariant.sh"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/roles" "$C/registry" "$C/projects/p" "$C/wait" "$C/state" "$C/stubs" "$C/fired"
  for s in it2 notify push; do
    { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s/stubs/%s.log"\nexit 0\n' "$C" "$s"; } > "$C/stubs/$s"
    chmod +x "$C/stubs/$s"
  done
  # fire stub REPLICATES handoff-fire's hard contract (handoff-fire.sh:617-618): --prompt-file is
  # REQUIRED and its file must exist, else exit 1 with NO log. This RED-proves P0-14 — a fire_replacement
  # that omits --prompt-file leaves no fire.log (the dead-desk recreate silently fails), exactly as prod.
  # ANCHOR CONTRACT (2026-07-25): the stub now ALSO models handoff-fire's refusal to fire without a
  # resolvable anchor. The real producer refuses when there is no $ITERM_SESSION_ID and neither
  # --session-id nor --window was passed (handoff-fire.sh:2084/2090/2096) — a launchd caller NEVER has
  # one. The old stub validated only --prompt-file, so it exited 0 where prod exited 1: the suite stayed
  # green through 41h/266 failed respawns. Cf. memory fixture-shape-parity-with-real-producer — a fixture
  # is a contract CLAIM, so it must model the producer's literal refusal, not a convenient subset.
  cat > "$C/stubs/fire" <<'FIRE'
#!/bin/bash
orig="$*"; pf=""; anchor=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) pf="${2:-}"; shift 2 ;;
    --window)      anchor=window; shift ;;
    --session-id)  anchor="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$pf" ] && [ -f "$pf" ] || exit 1
# No inherited pane in this env (ITERM_SESSION_ID is unset in the harness), so an explicit anchor is
# mandatory — mirrors the real refusal, and prints to STDERR as the real one does.
# ANCHOR (2026-07-30): an anchor flag is NO LONGER required. handoff-fire resolves a live pane
# itself for a caller with no anchor intent (resolve_headless_anchor), so a launchd respawn splits
# the operator's existing window instead of minting a new one. The stub therefore models ACCEPTANCE.
printf '%s\n' "$orig" >> "$(dirname "$0")/fire.log"
# ISOLATION (2026-08-01): model handoff-fire.sh:3070 — --in-place is ONLY an env prefix on the typed
# launch line. Writing it to fire.env lets the tests assert on the FIRED SESSION'S ENV (the property
# that matters) rather than on argv alone; the fixture-parity test pins that this mapping is real.
case " $orig " in *" --in-place "*) printf 'CLAUDE_ISOLATION_SKIP=1\n' >> "$(dirname "$0")/fire.env" ;; esac
exit 0
FIRE
  chmod +x "$C/stubs/fire"
  # cc-notify stub (F7 inbox transport): log argv + emit the "wake-path armed" verdict handle_stale greps.
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s/stubs/ccnotify.log"\n' "$C"
    printf 'echo "cc-notify: delivered to inbox [T] (live session, wake-path armed)" >&2\nexit 0\n'; } > "$C/stubs/ccnotify"
  chmod +x "$C/stubs/ccnotify"
  export DESK_INVARIANT_ROLE=desk DESK_INVARIANT_ROLES_DIR="$C/roles" \
    DESK_INVARIANT_REGISTRY_DIR="$C/registry" DESK_INVARIANT_PROJECT_ROOTS="$C/projects" \
    DESK_INVARIANT_WAIT_DIR="$C/wait" DESK_INVARIANT_STATE_DIR="$C/state" DESK_INVARIANT_IDL="$C/idl.jsonl" \
    DESK_INVARIANT_IT2="$C/stubs/it2" DESK_INVARIANT_NOTIFY="$C/stubs/notify" DESK_INVARIANT_PUSH="$C/stubs/push" \
    DESK_INVARIANT_NOTIFY_BIN="$C/stubs/ccnotify" \
    DESK_INVARIANT_FIRE_BIN="$C/stubs/fire" DESK_INVARIANT_CANNED_CWD="$C" DESK_INVARIANT_BRIEF="$C/brief.md" \
    DESK_INVARIANT_FIRED_DIR="$C/fired" DESK_INVARIANT_STALE_MIN=45
  # HERMETICITY (mandatory once the no-desk path writes a mailbox pointer): the forward write goes
  # through hooks/lib/mailbox-pending.sh, whose only dir seam is CC_MAILBOX_DIR (_mbx_dir, default
  # ~/.claude/mailbox). Unset, a green test run would drop `.forward` pointers into the OPERATOR'S LIVE
  # mailbox — a suite mutating the state it is supposed to be isolated from.
  export CC_MAILBOX_DIR="$C/mailbox"
  : > "$C/brief.md"
  # D6: the opt-in switch is read from the AMBIENT env, so a suite that inherited it from the
  # operator's shell would silently test the other branch. Unset here; the tests that want it set it.
  unset CC_DESK_OPTIN
}
row() { # <uuid> <sid> <pid> — write a registry row
  jq -cn --arg u "$1" --arg s "$2" --argjson p "$3" --arg c "$C" \
    '{paneUUID:$u,cwd:$c,pid:$p,startedAt:0,session_id:$s}' > "$C/registry/$1.json"
}
transcript() { # <sid> <iso-ts> [cap-text]
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$2" > "$C/projects/p/$1.jsonl"
  [ -n "${3:-}" ] && printf '{"type":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$3" >> "$C/projects/p/$1.jsonl"
  return 0
}
disp() { tail -1 "$C/idl.jsonl" | jq -r '.disposition'; }

@test "selftest passes and runs all 26 checks (a zero-check suite must not 'pass')" {
  run "$DI" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 26 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2 (fail-loud, no silent no-op)" {
  run "$DI" --bogus
  [ "$status" -eq 2 ]
}

@test "healthy: alive pid + fresh assistant turn → exit 0, disposition=healthy, no re-prompt/fire" {
  printf 'U1\n' > "$C/roles/desk"
  sleep 60 & local sp=$!
  row U1 S1 "$sp"
  transcript S1 "$(date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)"
  run "$DI" --once
  kill "$sp" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(disp)" = healthy ]
  [ ! -f "$C/stubs/it2.log" ]
  [ ! -f "$C/stubs/fire.log" ]
}

@test "stunned: alive pid + stale turn + 'monthly spend limit' → page + inbox resume, NO keystroke (F7)" {
  printf 'U2\n' > "$C/roles/desk"
  sleep 60 & local sp=$!
  row U2 S2 "$sp"
  transcript S2 "$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ)" "you have reached the monthly spend limit"
  run "$DI" --once
  kill "$sp" 2>/dev/null || true
  [ "$(disp)" = stunned ]
  [ -f "$C/stubs/ccnotify.log" ]      # resume enqueued to the inbox
  [ ! -f "$C/stubs/it2.log" ]         # F7: NEVER keystroked the live composer
  [ -f "$C/stubs/push.log" ]
}

@test "no-desk: role points at a UUID with no registry row → budgeted replacement fire + marker" {
  printf 'UGONE\n' > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  # P0-14: the recreate must pass --prompt-file (the brief file) — a bare --as-role/--cwd fire is
  # rejected by real handoff-fire (exit 1) and never respawns the dead desk.
  grep -q -- '--prompt-file' "$C/stubs/fire.log"
  grep -q -- "$C/brief.md" "$C/stubs/fire.log"
  ls "$C/state"/respawn-*.marker >/dev/null 2>&1
}

@test "no-desk: the respawn passes NO surface flag — it must never hardcode --window" {
  # Two regressions meet in this one assertion, so it is worth stating both:
  #  · 2026-07-25: fire_replacement passed no anchor at all, handoff-fire refused, and the desk went
  #    un-respawned for 41h / 266 failures. Fixed by passing --window.
  #  · 2026-07-30: that --window meant every respawn opened a BRAND-NEW iTerm2 window — the operator's
  #    long-standing "handoffs open a whole new window instead of a ⌘D split". Surface choice moved to
  #    the chokepoint (handoff-fire resolves a headless anchor itself), so this caller must pass NO
  #    surface flag and inherit split-right. Asserting the ABSENCE of --window is what keeps a future
  #    session from "fixing" an anchor problem here again instead of at the chokepoint.
  printf 'UANCHOR\n' > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]                       # the fire still happens (the 41h defect stays fixed)
  ! grep -q -- '--window' "$C/stubs/fire.log" || false # …and it does not mint a window
  grep -q -- '--prompt-file' "$C/stubs/fire.log"
}

# ── WORKTREE-ISOLATION EXEMPTION (2026-08-01) ────────────────────────────────────────────────────
# always-isolate routes every new interactive session into its own git worktree. The desk must be
# exempt: this is a LAUNCHD respawn path, so an isolated fire either re-lands on the shared root the
# policy exists to drain, or mints a NEW worktree per respawn — an unbounded leak that nothing here
# ever reaps. The exemption travels as handoff-fire's --in-place (env prefix, nothing else).

@test "isolation: the respawn fires --in-place — the new desk's env carries CLAUDE_ISOLATION_SKIP=1" {
  printf 'UISO\n' > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  grep -q -- '--in-place' "$C/stubs/fire.log"
  grep -qx 'CLAUDE_ISOLATION_SKIP=1' "$C/stubs/fire.env"   # …and it reaches the fired session's ENV
  grep -q -- "--cwd $C" "$C/stubs/fire.log"                # in place AT the canned cwd, not a worktree
}

@test "isolation: DESK_INVARIANT_ISOLATION_SKIP=0 drops the exemption (no --in-place, no env prefix)" {
  # The exemption is a policy call, not a law — it must be revocable without a code edit, and the
  # revocation must be TOTAL (argv and env), not merely absent from the log we happen to read.
  printf 'UISO0\n' > "$C/roles/desk"
  export DESK_INVARIANT_ISOLATION_SKIP=0
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]                               # the respawn still happens…
  ! grep -q -- '--in-place' "$C/stubs/fire.log" || false   # …carrying no exemption
  [ ! -f "$C/stubs/fire.env" ]
}

@test "isolation: --in-place IS handoff-fire's CLAUDE_ISOLATION_SKIP seam (fixture parity)" {
  # setup()'s stub MODELS the mapping; a model is a claim. Pin the producer's own two lines so a
  # rename there goes red HERE instead of silently un-exempting the desk — the failure mode is a
  # worktree leaked per respawn, which no other assertion in this suite can see.
  grep -q -- '--in-place)    IN_PLACE=1;' "$REPO/scripts/handoff-fire.sh"
  # THE SPAN IS THE TOKEN IN ITS OWN BRANCH, NOT THE WHOLE PREFIX STRING (2026-08-11). This was an
  # exact-literal `PREFIX="CLAUDE_ISOLATION_SKIP=1 "`, so it went red the moment 088875158 added a
  # legitimate CO-TENANT to the same prefix (`CC_ACCOUNT_PINNED=1`, pinning the account by env rather
  # than by launcher name). Nothing about the exemption changed; the assertion simply spanned more
  # than its subject, and a trunk red that indicts no diff blocks EVERY lander in this repo — one
  # took the whole gate red four commits later, for a diff that touched no isolation line at all.
  # Anchored on the IN_PLACE branch and the token, so a RENAME or a DELETED branch — the failure this
  # test exists to catch — still reds here, while a new co-tenant does not.
  grep -qE '^\[ "\$IN_PLACE" = 1 \] && PREFIX=".*CLAUDE_ISOLATION_SKIP=1 ?"' \
    "$REPO/scripts/handoff-fire.sh"
}

@test "isolation: CANNED_CWD still defaults to the shared root and is still overridable" {
  # The exemption is only worth anything if the cwd it launches in place AT is unchanged.
  printf 'UCWD1\n' > "$C/roles/desk"
  run "$DI" --once
  grep -q -- "--cwd $C" "$C/stubs/fire.log"                # override honoured (this suite's own setup)
  # Default path: $HOME is FIXTURED so the default expands inside the tmpdir — an unfixtured run
  # would assert against the operator's real checkout and read green for the wrong reason.
  rm -f "$C/stubs/fire.log"
  printf 'UCWD2\n' > "$C/roles/desk"
  run env -u DESK_INVARIANT_CANNED_CWD HOME="$C/home" "$DI" --once
  grep -q -- "--cwd $C/home/Development/claude-infrastructure" "$C/stubs/fire.log"
}

@test "no-desk: a FAILING fire still consumes respawn budget (no unbounded loop)" {
  # RED before the fix: respawn_marker_write ran ONLY in the success branch, so a permanently-failing
  # fire never consumed budget — 266 attempts against a ceiling of 2. The bound must cover the failure
  # mode it exists to bound. Force failure by making the brief unreadable to the stub's -f check.
  printf 'UFAIL\n' > "$C/roles/desk"
  rm -f "$C/brief.md"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ ! -f "$C/stubs/fire.log" ]                          # the fire did NOT succeed
  ls "$C/state"/respawn-*.marker >/dev/null 2>&1        # ...and budget was consumed anyway
}

@test "no-desk: the fire-failed record carries the captured stderr (not a bare 'nonzero')" {
  # RED before the fix: fire_replacement discarded stderr (>/dev/null 2>&1), which is why 41h of
  # identical failures were undiagnosable from the IDL alone.
  printf 'USTDERR\n' > "$C/roles/desk"
  cat > "$C/stubs/fire" <<'FIRE'
#!/bin/bash
echo "handoff-fire: DISTINCTIVE-STDERR-MARKER" >&2
exit 1
FIRE
  chmod +x "$C/stubs/fire"
  run "$DI" --once
  grep -q 'DISTINCTIVE-STDERR-MARKER' "$C/idl.jsonl"
}

@test "no-desk: the page is deduped across polls (a 5-min recurring event is not a storm)" {
  # RED before the fix: handle_no_desk paged on EVERY poll with no dedup, unlike the stunned/stale
  # branches. Two consecutive runs must produce exactly one page.
  printf 'UDEDUP\n' > "$C/roles/desk"
  run "$DI" --once
  local first; first="$(wc -l < "$C/stubs/push.log" | tr -d ' ')"
  run "$DI" --once
  local second; second="$(wc -l < "$C/stubs/push.log" | tr -d ' ')"
  [ "$first" = "$second" ]
}

@test "budget-exhausted: no-desk + 2 fresh respawn markers → page only, NO fire (loop refused)" {
  printf 'UGONE2\n' > "$C/roles/desk"
  : > "$C/state/respawn-$(date +%s).marker"
  : > "$C/state/respawn-$(( $(date +%s) - 3 )).marker"
  run "$DI" --once
  [ "$(disp)" = budget-exhausted ]
  [ ! -f "$C/stubs/fire.log" ]
}

@test "no-desk: a successful fire HEALS cc-roles/desk to the fired pane (atomic tmp+mv)" {
  # After a successful respawn, desk-invariant reads the NEW pane from handoff-fire's cc-fired stamp
  # (mark_fired_peer writes cc-fired/<newpane>.json on a self-retiring fire) and atomically repoints
  # the role at it — so the NEXT sweep sees the new desk instead of re-firing against the stale pointer
  # that put us here (the 41h no-desk loop). Fire stub below ALSO models mark_fired_peer.
  printf 'USTALE-ORIG\n' > "$C/roles/desk"
  cat > "$C/stubs/fire" <<'FIRE'
#!/bin/bash
orig="$*"; pf=""; anchor=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) pf="${2:-}"; shift 2 ;;
    --window)      anchor=window; shift ;;
    --session-id)  anchor="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$pf" ] && [ -f "$pf" ] || exit 1
# anchor optional since 2026-07-30 — handoff-fire resolves one itself (see setup()'s stub).
printf '%s\n' "$orig" >> "$(dirname "$0")/fire.log"
fired="$(dirname "$0")/../fired"; mkdir -p "$fired"
printf '{"paneUUID":"abcdef01-2345-6789-abcd-ef0123456789","selfRetire":true}\n' \
  > "$fired/abcdef01-2345-6789-abcd-ef0123456789.json"
exit 0
FIRE
  chmod +x "$C/stubs/fire"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  [ "$(cat "$C/roles/desk")" = "abcdef01-2345-6789-abcd-ef0123456789" ]   # role HEALED to fired pane
  grep -q 'healed -> abcdef01-2345-6789-abcd-ef0123456789' "$C/idl.jsonl"
  ! ls "$C"/roles/.desk.* >/dev/null 2>&1                                 # ATOMIC: no temp dotfile left
}

@test "no-desk: a fire that leaves NO cc-fired stamp does NOT corrupt the role file" {
  # The default fire stub succeeds but writes no cc-fired stamp. newest_fired_pane returns nothing →
  # the heal is a no-op → the role file is left exactly as it was (never truncated or half-written).
  printf 'USTALE-KEEP\n' > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]                              # fire succeeded...
  [ -z "$(ls -A "$C/fired" 2>/dev/null)" ]                # ...but wrote no cc-fired stamp
  [ "$(cat "$C/roles/desk")" = "USTALE-KEEP" ]            # role file UNCORRUPTED
  grep -q 'no cc-fired stamp yet to heal role' "$C/idl.jsonl"
  ! ls "$C"/roles/.desk.* >/dev/null 2>&1
}

@test "stale-marker sweep: paged-*-stale >7d pruned, <7d kept, count logged via idl" {
  # The (sid,state) dedup markers are otherwise never cleaned. Each run prunes paged-*-stale markers
  # older than 7d (mtime) and logs the count. Healthy desk so the run itself is a clean no-op branch.
  printf 'UH\n' > "$C/roles/desk"
  sleep 60 & local sp=$!
  row UH SH "$sp"
  transcript SH "$(date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)"
  : > "$C/state/paged-FRESHSID-stale.marker"                                   # mtime = now → kept
  : > "$C/state/paged-OLDSID-stale.marker"
  touch -t "$(date -v-8d +%Y%m%d%H%M)" "$C/state/paged-OLDSID-stale.marker"   # 8d old → swept
  run "$DI" --once
  kill "$sp" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ ! -f "$C/state/paged-OLDSID-stale.marker" ]           # >7d swept
  [ -f "$C/state/paged-FRESHSID-stale.marker" ]           # <7d kept
  grep -q 'swept 1 stale damping marker' "$C/idl.jsonl"   # count logged via idl
}

# ── MAILBOX SUCCESSION on the replacement path (v3 D1/D3) ─────────────────────────────────────────
# A fire stub that ALSO models handoff-fire's mark_fired_peer stamp (cc-fired/<newpane>.json) — the only
# source desk-invariant has for the successor's pane. Otherwise identical to setup()'s default stub
# (--prompt-file required; anchor OPTIONAL since 2026-07-30), so the producer contract stays mirrored.
fire_stub_with_stamp() {
  cat > "$C/stubs/fire" <<'FIRE'
#!/bin/bash
orig="$*"; pf=""; anchor=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) pf="${2:-}"; shift 2 ;;
    --window)      anchor=window; shift ;;
    --session-id)  anchor="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$pf" ] && [ -f "$pf" ] || exit 1
# anchor optional since 2026-07-30 — handoff-fire resolves one itself (see setup()'s stub).
printf '%s\n' "$orig" >> "$(dirname "$0")/fire.log"
fired="$(dirname "$0")/../fired"; mkdir -p "$fired"
printf '{"paneUUID":"abcdef01-2345-6789-abcd-ef0123456789","selfRetire":true}\n' \
  > "$fired/abcdef01-2345-6789-abcd-ef0123456789.json"
exit 0
FIRE
  chmod +x "$C/stubs/fire"
}

@test "no-desk: a successful replacement fire writes the DEAD desk's mailbox .forward (D1/D3)" {
  # Healing cc-roles/desk re-addresses only ROLE-addressed mail. Two classes still strand without a
  # pointer: (a) every back-channel ping ever fired at the dead desk carries its RAW pane uuid, and
  # (b) cc-notify's D3 reroute tees a dead target's mail to the DESK role's box — which, when the desk
  # is the thing that died, IS the dead box. cc-notify:676-679 says exactly that and DEFERS here ("the
  # desk-invariant replacement path exists for" it), so this is the missing half of a wired mechanism.
  # Writing the pointer also unlocks D1's tail migration for free: mailbox-drain.sh:98-108 adopts from
  # any *.forward naming the starting session.
  printf '%s\n' "11111111-2222-3333-4444-555555555555" > "$C/roles/desk"
  fire_stub_with_stamp
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  # the dead box is now a POINTER at the successor
  [ "$(cat "$C/mailbox/11111111-2222-3333-4444-555555555555.forward")" = "abcdef01-2345-6789-abcd-ef0123456789" ]
  grep -q 'mail forwarded 11111111-2222-3333-4444-555555555555 -> abcdef01-2345-6789-abcd-ef0123456789' "$C/idl.jsonl"
  ! ls "$C"/mailbox/.*.tmp >/dev/null 2>&1     # ATOMIC tmp+mv: no temp dotfile left behind
}

@test "no-desk: a NON-UUID role holder gets no .forward, and the heal still succeeds (best-effort)" {
  # A role file legitimately holds a uuid, a session id, or a pane NAME. mailbox_write_forward refuses
  # anything non-canonical, so a name-keyed holder simply gets no pointer — and that refusal must never
  # cost the role heal, which is the branch that stops the re-fire loop.
  printf 'USTALE-NAME\n' > "$C/roles/desk"
  fire_stub_with_stamp
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ "$(cat "$C/roles/desk")" = "abcdef01-2345-6789-abcd-ef0123456789" ]   # heal still happened
  [ -z "$(ls -A "$C/mailbox" 2>/dev/null)" ]                             # no pointer for a name key
  ! grep -q 'mail forwarded' "$C/idl.jsonl"
}

@test "no-desk: an unwritable mailbox dir never fails the sweep nor blocks the role heal" {
  # The forward is best-effort BY CONSTRUCTION — a desk-existence invariant must never lose its respawn
  # or its heal because a mailbox dir was unwritable. Blocked via a REGULAR FILE standing where the dir's
  # parent must be, so mkdir -p fails deterministically for any uid (a chmod 000 test would pass
  # vacuously under a root runner).
  printf '%s\n' "11111111-2222-3333-4444-555555555555" > "$C/roles/desk"
  fire_stub_with_stamp
  : > "$C/blocker"
  export CC_MAILBOX_DIR="$C/blocker/mbx"
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ "$(cat "$C/roles/desk")" = "abcdef01-2345-6789-abcd-ef0123456789" ]   # heal UNBLOCKED by the mail failure
  ! grep -q 'mail forwarded' "$C/idl.jsonl"
}

# ── D6: DESK ENFORCEMENT IS OPT-IN (2026-08-07) ──────────────────────────────────────────────────
# This organ was written when a desk was assumed. Under the deskless model a machine that never wired
# one is in a DELIBERATE state, and enforcing there means a 5-minute page loop plus a budgeted
# replacement desk fired at an operator who asked for none. The gate keys on the ROLE FILE, never on
# the caller's reason string — which is exactly what the two controls below pin: a role file that
# EXISTS and rots is a wired-then-broken desk, i.e. an opted-in fault, and must still take the legacy
# path. An over-broad gate (one keyed on "no-desk-ness") would swallow those and read green here
# without them.

@test "opt-in: NO role file + CC_DESK_OPTIN unset → not-opted-in, NO page, NO fire, no budget spent" {
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = not-opted-in ]
  grep -q 'verdict=not-opted-in' "$C/idl.jsonl"           # the IDL row carries the verdict token
  [ ! -f "$C/stubs/fire.log" ]                            # nothing fired…
  [ ! -f "$C/stubs/push.log" ]                            # …nothing paged…
  ! ls "$C/state"/respawn-*.marker >/dev/null 2>&1 || false   # …and no respawn budget consumed
  # an EMPTY role file is the same never-wired state (evaluate() reads both as "no pane")
  : > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = not-opted-in ]
  [ ! -f "$C/stubs/fire.log" ]
}

@test "opt-in: NO role file + CC_DESK_OPTIN=1 → the legacy no-desk path (page + budgeted fire)" {
  # The positive control for the absence assertions above: same fixture, switch on, everything fires.
  export CC_DESK_OPTIN=1
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  [ -f "$C/stubs/push.log" ]
  ls "$C/state"/respawn-*.marker >/dev/null 2>&1
}

@test "opt-in: a PRESENT-but-dead role file is an opted-in FAULT — legacy path even with the switch off" {
  # The design point. Someone registered a desk here and its pointer rotted; that is precisely the
  # incident this organ exists for, so the opt-in gate must NOT swallow it. CC_DESK_OPTIN stays unset.
  printf 'UDEAD\n' > "$C/roles/desk"        # holder present, no registry row → dead pointer
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  [ -f "$C/stubs/push.log" ]
}

@test "no-desk: a SELF-forward is refused (a pointer that looks wired must not hide a stuck role)" {
  # If the cc-fired stamp names the pane the role ALREADY held, there was no succession. A self-pointer
  # would make mailbox_forward_of a silent no-op while reading as "mail is wired" — the lib refuses it
  # (mailbox-pending.sh:334-337) and this pins that the replacement path inherits the refusal.
  printf '%s\n' "abcdef01-2345-6789-abcd-ef0123456789" > "$C/roles/desk"
  fire_stub_with_stamp
  run "$DI" --once
  [ "$status" -eq 0 ]
  [ "$(disp)" = no-desk ]
  [ ! -f "$C/mailbox/abcdef01-2345-6789-abcd-ef0123456789.forward" ]
  ! grep -q 'mail forwarded' "$C/idl.jsonl"
}
