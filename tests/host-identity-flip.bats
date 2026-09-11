#!/usr/bin/env bats
# HOST IDENTITY — a lease identity may not be keyed on a NETWORK-DERIVED name (backlog 7e8cff2e822c).
#
# THE DEFECT. `hostname -s` on macOS reports the dynamic store's HostName, supplied by DHCP /
# reverse DNS. The lease identity was `$(hostname -s)-<pid>`, so when the short name flipped under a
# running box a LIVE worker was re-spelled mid-flight. Measured 2026-09-10: claude pid 90701
# reclaimed item 775afca94edc as `MacBookPro-90701`, and after a DNS outage `hostname -s` answered
# `Chriss-MacBook-Pro-3` — whereupon worker-claim-gate denied that same session's own read-only git
# commands with "holder MacBookPro-90701, this session Chriss-MacBook-Pro-3-90701". A session was
# told to stand down as a DUPLICATE OF ITSELF. Not a one-off: the live ledger carried 514
# `MacBookPro-*` claims interleaved with 5,024 `Chriss-MacBook-Pro-3-*`, both spellings still
# arriving on 2026-09-11.
#
# THE CURE HAS TWO HALVES AND THIS SUITE PINS BOTH, because either alone is unsound:
#   MINT    every site derives from `scutil --get LocalHostName` (the Bonjour name — set once, not
#           network-derived), so new claims stop splitting. Sites 1-5 below.
#   COMPARE `host_is_local` accepts any spelling this box CURRENTLY answers to, so the claims
#           already in the ledger under the other spelling keep taking the `kill -0` path. A mint
#           fix alone would have re-spelled every live incumbent a THIRD time and converted every
#           one of them into a false death on the next reap.
#
# AND THE CONTROLS ARE THE POINT (memory: positive-control-the-denominator). A compare that
# tolerated ANY host component would pass every cure case here while silently `kill -0`ing a cloud
# claim's pid against this kernel's pid table. So each cure case is paired with a control that must
# still CONVICT: a dead pid under a good alias, and a foreign host that must never reach `kill -0`.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  HOOK="$REPO/hooks/validate-bash.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # claimer_live's registry branch must ANSWER "not listed" (rc 1) for the dead controls, else they
  # abstain (rc 2) and pass vacuously for a reason unrelated to host identity.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # A present-but-EMPTY worktree root: `owned_wait` reads an absent root as starvation (rc 2) and
  # would absolve every claim regardless of the identity under test.
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/worktrees"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  # HERMETICITY — the seams this suite reaches that do NOT resolve under $HOME, pinned rather than
  # allowlisted (the lint names each one and says so). Two distinct reasons, both real here:
  #
  #  · `cc-backlog add` ends in dispatch_kick(), and kick_bin() resolves the PATH leg BEFORE $HOME —
  #    so an unpinned suite spawns the operator's DEPLOYED cc-dispatch, which inherits these very
  #    fixtures and journals test decisions into the production idl.jsonl. This suite calls `add`
  #    once per test.
  #  · the pre-filter corpus below NAMES handoff-fire.sh and the limit-recover scripts as test DATA.
  #    Nothing here executes them, but the capacity and fire gates are read off live machine load,
  #    and a suite that can go red because the box is busy is reporting on the box, not its subject.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  DEADPID="$(bash -c 'echo $$')"          # a pid that has certainly exited
}

claimed() { # <label> <claimer> → id, claimed
  local id; id="$("$CB" add --title "host identity $1" --project probe --source "hostid-$1")"
  CC_BACKLOG_ELIGIBLE_GATE=off "$CB" claim "$id" --by "$2" --venue local >/dev/null \
    || { echo "claimed: claim refused for $id ($2)" >&2; return 1; }
  printf '%s' "$id"
}

reap_aged() { CC_BACKLOG_NOW=$(( $(date -u +%s) + 7200 )) "$CB" reap --dry-run 2>&1; }

# ── 1-4 · COMPARE: the cure, and the two verdicts it must NOT change ──────────────────────────
# The seam is CC_HOST_ALIASES (extra aliases, space-separated). It can only ever WIDEN the set, so
# a leak into a subprocess cannot manufacture a false death — and it makes these cases hermetic on
# a box whose two host sources happen to agree, where the seam-free case 5 correctly skips.

@test "1 a claim recorded under ANOTHER spelling of this box resolves LIVE, not dead" {
  id="$(claimed legacy-live "LegacySpelling-$$")"
  CC_HOST_ALIASES=LegacySpelling run bash -c 'CC_BACKLOG_NOW=$(( $(date -u +%s) + 7200 )) "$1" reap --dry-run 2>&1' _ "$CB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KEEP $id [claimer LegacySpelling-$$ LIVE"* ]] || { echo "$output"; false; }
  [[ "$output" != *"WOULD-REOPEN $id"* ]] || { echo "$output"; false; }
}

@test "2 RED CONTROL: the same claim with NO alias declared is still convicted" {
  # Pre-fix behaviour, reproduced deliberately. Without it case 1 would pass against a compare that
  # called EVERY <anything>-<pid> claim live, which is the mutation this suite most needs to kill.
  id="$(claimed legacy-unknown "LegacySpelling-$$")"
  run reap_aged
  [[ "$output" == *"WOULD-REOPEN $id"* ]] || { echo "$output"; false; }
}

@test "3 CONTROL: a good alias with a DEAD pid is still convicted" {
  id="$(claimed legacy-dead "LegacySpelling-$DEADPID")"
  CC_HOST_ALIASES=LegacySpelling run bash -c 'CC_BACKLOG_NOW=$(( $(date -u +%s) + 7200 )) "$1" reap --dry-run 2>&1' _ "$CB"
  [[ "$output" == *"WOULD-REOPEN $id"* ]] || { echo "$output"; false; }
}

@test "4 CONTROL: a foreign host never reaches kill -0, whatever pid it names" {
  # `cloudvm-4242` under an absent/local venue is claimer_live's own measured row (see its venue
  # gate). Widening the compare to "any host component" would have run `kill -0 4242` against THIS
  # kernel's pid table — a verdict about a machine the oracle cannot see. It must stay unreachable.
  id="$(claimed foreign "cloudvm-$$")"          # a LIVE pid, deliberately, under a foreign host
  run reap_aged
  [[ "$output" == *"WOULD-REOPEN $id"* ]] || { echo "$output"; false; }
}

@test "5 the real box: a claim under LocalHostName resolves LIVE even when hostname -s differs" {
  # The seam-free arm. It is the actual incident shape, with no fixture between the test and the
  # two live host sources — and it is the arm that would catch the seam itself lying. Where the two
  # sources agree there is nothing to tell apart, so it SKIPS rather than passing vacuously or
  # reddening on an environment it does not control (memory:
  # environment-falsifiable-precondition-must-skip).
  lhn="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || printf '')"
  hs="$(hostname -s 2>/dev/null || printf '')"
  [ -n "$lhn" ] || skip "no scutil LocalHostName on this box"
  [ "$lhn" != "$hs" ] || skip "LocalHostName and hostname -s agree here ($lhn) — nothing to discriminate"
  id="$(claimed real-flip "$lhn-$$")"
  run reap_aged
  [[ "$output" == *"KEEP $id [claimer $lhn-$$ LIVE"* ]] || { echo "$output"; false; }
}

# ── 6-7 · MINT: one derivation, at every site, byte for byte ──────────────────────────────────

@test "6 every identity-minting site derives the host from scutil LocalHostName" {
  # An EXACT tally, not a `grep -q` per file: the failure this pins is a site left behind, and a
  # per-file existence check passes the moment ONE line in the file is right (memory:
  # aggregate-control-cannot-see-a-per-member-zero — the per-member arm must NAME the member).
  want='/usr/sbin/scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost'
  for f in scripts/lib/worker-claim-gate.sh hooks/session-register.sh bin/cc-dispatch bin/cc-bus bin/cc-backlog; do
    n="$(grep -cF -- "$want" "$REPO/$f" | head -1)" || true
    [ "${n:-0}" -ge 1 ] || { echo "MINT SITE NOT CONVERTED: $f"; false; }
  done
  # and no site still mints from the network-derived name. Comment lines are excluded or the count
  # moves whenever the prose explaining WHY does.
  for f in scripts/lib/worker-claim-gate.sh hooks/session-register.sh bin/cc-dispatch bin/cc-bus; do
    bad="$(grep -vE '^[[:space:]]*#' "$REPO/$f" | grep -c 'hostname -s 2>/dev/null || hostname' || true)"
    [ "${bad:-0}" -le 1 ] || { echo "STALE MINT in $f"; grep -vE '^[[:space:]]*#' "$REPO/$f" | grep -n 'hostname -s'; false; }
  done
}

@test "7 cc-backlog's two COMPARE sites go through host_is_local, not a host equality test" {
  # STRUCTURAL, and for the reclaim anchor it is the ONLY arm — stated rather than glossed. Measured
  # per site (memory: per-site-mutation-attributes-coverage):
  #   restore host-equality in claimer_live      → cases 1, 5 and 7 red   (behavioural + structural)
  #   restore host-equality in the reclaim anchor→ case 7 ONLY            (structural)
  # The anchor site is not behaviourally observable from the gate because BOTH its outcomes proceed:
  # an unresolved anchor makes `foreign_wait` return rc 2, and only rc 0 refuses. So the site fails
  # OPEN either way and no end-to-end verdict changes — what the fix buys is that the caller can be
  # SUBTRACTED from its own worktree's occupants, which is a precondition for oracle 2 being able to
  # convict correctly rather than a verdict of its own. A green board here is not evidence that the
  # anchor is exercised; this grep is.
  run grep -nE '\[ "\$by" = "\$(host|rhost)-\$r?pid" \]' "$REPO/bin/cc-backlog"
  [ "$status" -ne 0 ] || { echo "host-equality compare restored:"; echo "$output"; false; }
  [ "$(grep -c 'host_is_local' "$REPO/bin/cc-backlog")" -ge 3 ]
}

# ── 8-10 · the validate-bash pre-filter: command position, never substring ────────────────────
# Harmless alone and fatal beside the above: a command that merely NAMED a spawn script was
# lease-checked, so a mis-keyed lease denied a session's own read-only reads of those very files.

# THE EXTRACTION WINDOW IS PART OF THE TEST. A first cut of this harness pulled only the
# `_wcs_words=…done` block, and a mutant that RESTORED the whole-string arm one line above it was
# therefore outside the window — the behavioural cases could not see the very defect they exist to
# pin, and only the structural case 10 killed it (memory:
# fixture-identifier-shape-collapses-two-spaces: a fixture that holds the axis under test constant
# is decorative on it). The window now spans the entire pre-filter, comment header through the
# `self-close` exemption, so anything added anywhere inside it is executed here.
filter_hit() { # <command line> → 1 if the pre-filter selects it, else 0
  CMD="$1" bash -c '
    CMD="$CMD"
    '"$(sed -n '/^# COMMAND POSITION, NEVER SUBSTRING/,/self-close\*) _wcs_hit=0 ;; esac$/p' "$HOOK")"'
    echo "$_wcs_hit"'
}

@test "8a harness control: the extracted pre-filter is non-empty and spans the whole region" {
  # Without this, an extraction that silently matched nothing would make cases 8-10 pass by
  # emitting an empty `$_wcs_hit` for everything (memory: positive-control-the-denominator).
  blk="$(sed -n '/^# COMMAND POSITION, NEVER SUBSTRING/,/self-close\*) _wcs_hit=0 ;; esac$/p' "$HOOK")"
  [ "$(printf '%s\n' "$blk" | wc -l)" -gt 25 ]
  [[ "$blk" == *'done <<< "$_wcs_words"'* ]] || false
  [[ "$blk" == *'self-close'* ]]
}

@test "8 a command that merely NAMES a spawn script is NOT lease-checked" {
  for c in 'git show origin/main:scripts/handoff-fire.sh' \
           'grep -n foo scripts/handoff-fire.sh' \
           'git log --oneline -- scripts/handoff-fire.sh' \
           'echo see bin/it2-kitty' \
           'cc-backlog add --title "fix bin/cc-respawn"'; do
    [ "$(filter_hit "$c")" = 0 ] || { echo "FALSE HIT: $c"; false; }
  done
}

@test "9 a real spawn in command position IS lease-checked, in any segment" {
  # Strictly WIDER than the old first-word arm, which saw only segment one: the `&&` and `|` shapes
  # below were missed by it and caught only by the substring arm this change removes.
  for c in '/Users/x/.claude/scripts/handoff-fire.sh --prompt-file /tmp/p.txt' \
           'bash scripts/handoff-fire.sh --recycle' \
           'cd /tmp && bash $HOME/.claude/scripts/handoff-fire.sh --worktree wt-1' \
           'FOO=1 BAR=2 nohup bin/it2-kitty --split-right' \
           'true; exec bin/cc-respawn' \
           'scripts/limit-recover/lr-fire-resume.sh --sid abc'; do
    [ "$(filter_hit "$c")" = 1 ] || { echo "MISSED SPAWN: $c"; false; }
  done
}

@test "10 the pre-filter matches on command position, not on the whole string" {
  # The mutant this suite must kill is a restoration of the whole-string arm. Asserted structurally
  # as well as behaviourally, because case 8 would also pass against a filter that matched NOTHING.
  run grep -nE 'case "\$CMD" in[[:space:]]*$' "$HOOK"
  run bash -c 'grep -n "\*scripts/handoff-fire.sh\*" "$1" | grep -v "^[0-9]*:[[:space:]]*#"' _ "$HOOK"
  [ -z "$output" ] || { echo "whole-string arm restored: $output"; false; }
  # positive control on the harness itself: the extracted block must be non-empty and decide
  [ "$(filter_hit 'bash scripts/handoff-fire.sh --recycle')" = 1 ]
  [ "$(filter_hit 'ls -la')" = 0 ]
}

# ── 11-13 · THE REPORTED SYMPTOM: a live claimer refused as a DUPLICATE OF ITSELF ─────────────
# Replayed with BOTH REAL host spellings of this box and no seam between the test and the subject:
# the claim is recorded under `hostname -s` (what the gate minted before the flip) and the gate then
# mints `scutil --get LocalHostName` (what it answered after). ONE live pid throughout.
#
# MEASURED A/B against trunk's own binaries, same fixture, one variable:
#   PRE  rc=9  "REFUSING a write — <item> is held by MacBookPro-89285; this session is
#              Chriss-MacBook-Pro-3-89285"          ← the incident, byte-shape identical
#   POST rc=0  "ADMIT — Chriss-MacBook-Pro-3-90373 holds the claim on <item>"
#
# WHY THE COMPARE FIX ALONE DOES NOT CLOSE THIS, which is the trap worth pinning: making
# `claimer_live` correct makes it report the holder LIVE — because the holder IS the caller — so a
# compare-only cure refuses the caller MORE reliably than before. The self-arm is what closes it.

# NOT `WORKER="$(worker_in ...)"`. Spawning the stand-in inside a COMMAND SUBSTITUTION killed it
# with the substitution's subshell, so every fixture here ran with a DEAD holder — and case 11 still
# passed, because `same_local_worker` compares pids and host locality and never asks about liveness.
# The axis the controls turn on was being held constant at the one value that cannot express the bug
# (memory: fixture-identifier-shape-collapses-two-spaces). Assign a global, and ASSERT the pid is
# breathing before using it.
worker_in() { ( cd "$1" && exec sleep 40 ) & WPID=$!; sleep 0.4; kill -0 "$WPID" 2>/dev/null \
  || { echo "fixture: stand-in worker $WPID died on spawn — this suite proves nothing"; return 1; }; }

gate_admit() { # <cc-backlog by-string for the recorded claim> <host the gate mints> <pid> <wt> <item>
  CC_WCLAIM_BACKLOG_BIN="$CB" CC_WCLAIM_HOST="$2" CC_WCLAIM_PID="$3" \
    bash -c '. "$1"; cc_worker_claim_admit write "$2" "a write"; rc=$?; echo "rc=$rc"; cc_worker_claim_reason' \
    _ "$REPO/scripts/lib/worker-claim-gate.sh" "$4" 2>&1
}

setup_flip() { # → sets ITEM WT WORKER HOST_A HOST_B ; claim recorded under HOST_A
  HOST_A="$(hostname -s)"; HOST_B="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || printf '')"
  ITEM="$("$CB" add --title "incident replay" --project probe --source incident)"
  WT="$CC_BACKLOG_WT_ROOT/wt-$ITEM"; mkdir -p "$WT"
  worker_in "$WT"; WORKER="$WPID"
}

# `|| true` on the kill itself, not a trailing `; true` and not the `&&` guard it used to carry:
# the kill is the last command of the AND-list, so errexit is NOT exempt there, and a stand-in the
# reaper already collected returns 1 and aborts the body — under load only.
teardown() {
  [ -n "${WORKER:-}" ] || return 0
  kill "$WORKER" 2>/dev/null || true
  wait "$WORKER" 2>/dev/null || true
  return 0
}

@test "11 the incident: one live pid, two host spellings — the gate ADMITS its own claimer" {
  setup_flip
  [ -n "$HOST_B" ] || skip "no scutil LocalHostName on this box"
  [ "$HOST_A" != "$HOST_B" ] || skip "both host sources agree here ($HOST_A) — no flip to replay"
  CC_BACKLOG_ELIGIBLE_GATE=off "$CB" claim "$ITEM" --by "$HOST_A-$WORKER" --venue local >/dev/null
  # THE HOLDER MUST BE LIVE or this is not the incident at all — a dead holder is displaced by the
  # ordinary hand-over and the self-arm is never reached, so the case would pass without testing it.
  kill -0 "$WORKER"
  run gate_admit "$HOST_A-$WORKER" "$HOST_B" "$WORKER" "$WT" "$ITEM"
  [[ "$output" == *"rc=0"* ]] || { echo "$output"; false; }
  [[ "$output" != *"REFUSING"* ]] || { echo "$output"; false; }
  # and the ledger says WHY, so the flip is diagnosable rather than merely survived
  run "$CB" reclaim "$ITEM" --by "$HOST_B-$WORKER"
  [[ "$output" == *"verdict=noop-already-ours"* ]] || { echo "$output"; false; }
  [[ "$output" == *"same pid on this box under another host spelling"* ]] || { echo "$output"; false; }
}

@test "12 CONTROL: a GENUINE duplicate — a different live pid — is still refused rc 9" {
  # Without this, case 11 would pass against a self-arm that called every reclaim "already ours",
  # i.e. against no lease at all. The pid is what separates the two, so the control varies only it.
  setup_flip
  CC_BACKLOG_ELIGIBLE_GATE=off "$CB" claim "$ITEM" --by "$HOST_A-$WORKER" --venue local >/dev/null
  worker_in "$WT"; other="$WPID"               # a second, genuinely different live session
  run gate_admit "$HOST_A-$WORKER" "${HOST_B:-$HOST_A}" "$other" "$WT" "$ITEM"
  # `wait` reports the SIGTERM status (143) and bats runs under errexit, so an unguarded cleanup
  # line fails the test BEFORE its assertions are reached — a red that says nothing about the subject.
  kill "$other" 2>/dev/null || true; wait "$other" 2>/dev/null || true
  [[ "$output" == *"rc=9"* ]] || { echo "$output"; false; }
  [[ "$output" == *"REFUSING"* ]] || { echo "$output"; false; }
}

@test "13 CONTROL: the same pid under a FOREIGN host is not 'ours'" {
  # same_local_worker requires BOTH host halves to be local. A cloud claim that happens to collide
  # with a local pid must not be adopted as this session's own lease.
  setup_flip
  CC_BACKLOG_ELIGIBLE_GATE=off "$CB" claim "$ITEM" --by "cloudvm-$WORKER" --venue local >/dev/null
  run "$CB" reclaim "$ITEM" --by "$HOST_A-$WORKER"
  [[ "$output" != *"same pid on this box under another host spelling"* ]] || { echo "$output"; false; }
}
