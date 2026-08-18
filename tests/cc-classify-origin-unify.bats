#!/usr/bin/env bats
# cc-classify × hooks/lib/origin-identity.sh — the ONE origin/tenancy oracle (row dcf58e1ba056).
#
# WHAT THIS PINS. bin/cc-classify used to answer "does this fired stamp gate THIS session" from its
# own startedAt boot window while hooks/lib/origin-identity.sh answered it from cwd + closedAt — two
# auditors over one population, disagreeing (MEMORY sibling-auditors-must-share-the-state-model).
# The disagreement was measured before the fix, hermetically, in BOTH directions:
#   stale  (reused pane id, DIFFERENT cwd, booted in-window) → classify said finished-teammate
#          (one of the four REAPABLE causes) while the oracle said origin.
#   spent  (cwd matches, closedAt set — a contract used up by a completed self-close, inherited by
#          the next tenant of a reused id) → classify said finished-teammate; the oracle said origin.
#   boot   (cwd matches, closedAt null, booted +2h — the peer CRASHED rather than self-closed and a
#          later session took the id) → the ORACLE said fired-peer; the boot window refutes it.
# The third case is why the fix is a CONJUNCT and not the replacement the row prescribed: unifying
# onto cwd alone would begin auto-reaping a pane cc-classify deliberately surfaces today. So the
# oracle enters as a REFUTATION only (stale/spent withdraw the stamp; unknown/absent keep the
# pre-tenancy answer), and every arm below NARROWS.
#
# THE PAIRS. Each REFUTATION assertion (T2/T3/T5) is shipped beside its own POSITIVE CONTROL (T1/T4)
# on the identical fixture minus the one refuting field. Without those controls a green proves only
# that the fixture never reaches a reapable cause at all — the vacuous pass this file's own REMOVE
# half was run against (restore the startedAt-only body ⇒ T2/T3/T5 go RED, T1/T4 stay green).

setup() {
  # M11: the box's own load must never decide a verdict (see tests/cc-classify.bats setup).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # HERMETIC $HOME. Both subjects fall back to it — cc-classify's FIRED_DIR/PROJECT_ROOTS defaults and
  # origin-identity's oi_fired_dir all read $HOME/.claude/… — so an unfixtured suite would consult the
  # operator's live session store. Every path is env-pinned below as well; this is the floor under
  # them, not a substitute (T9/T10 re-point HOME per invocation on top of it, deliberately).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-classify"
  D="$BATS_TEST_TMPDIR"
  mkdir -p "$D/bin" "$D/proj/slug" "$D/teams" "$D/fired"
  NOW=1000000000
  LIVE=$$
  cat > "$D/bin/cc-sessions" <<EOF
#!/bin/bash
cat "$D/sessions.json"
EOF
  chmod +x "$D/bin/cc-sessions"
  printf '#!/bin/bash\ntrue\n' > "$D/bin/ps-none"; chmod +x "$D/bin/ps-none"
  export CC_CLASSIFY_SESSIONS_BIN="$D/bin/cc-sessions"
  export CC_CLASSIFY_NOW="$NOW"
  export CC_CLASSIFY_IDLE_S=300
  export CC_CLASSIFY_PROJECT_ROOTS="$D/proj"
  export CC_CLASSIFY_TEAMS_GLOB="$D/teams"
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"
  export CC_CLASSIFY_WAIT_CONTRACTS_DIR="$D/wait-contracts"
  export CC_CLASSIFY_DESK_ROLE_FILE="$D/cc-roles-desk"
  export CC_FIRED_DIR="$D/fired"
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=21600
  export CC_CLASSIFY_FIRE_PROMPT_SLACK_S=300
  # the tenancy oracle's own kill switch, pinned ON — T6 is the ONE test that turns it off.
  export CC_SELFCLOSE_TENANCY=1
}

UP="4EC4DA5D-0000-4000-8000-000000000001"

# a real git repo whose HEAD == origin/main (work LANDED)
mkrepo() { local r="${1:?mkrepo: repo path required}"; mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
  git -C "$r" update-ref refs/remotes/origin/main HEAD; return 0; }

# registry row; args: paneUUID pid cwd sid startedAt-ms
reg() { printf '[{"name":"t","paneUUID":"%s","account":"next","cwd":"%s","pid":%s,"session_id":"%s","startedAt":%s}]\n' \
        "$1" "$3" "$2" "$4" "$5" > "$D/sessions.json"; }

# last assistant turn <ago> seconds before NOW
tx() { local sid="$1" ago="$2" ts
  ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}\n' "$ts" > "$D/proj/slug/$sid.jsonl"; }

# a mark_fired_peer-shaped stamp with an EXPLICIT cwd + closedAt — unlike tests/cc-classify.bats's
# stamp(), whose cwd is the literal "x" (unresolvable ⇒ the oracle abstains ⇒ that whole suite is
# byte-for-byte unaffected by this change, which is itself the point of T5).
# args: paneUUID stamp-cwd fired-ago-s closedAt(null|iso)
stampx() { local pane="$1" scwd="$2" ago="$3" closed="$4" fire_ep=$((NOW-$3)) iso
  iso="$(TZ=UTC date -j -u -f %s "$fire_ep" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  jq -n --arg p "$pane" --arg cwd "$scwd" --arg at "$iso" --arg cl "$closed" \
    '{paneUUID:$p, cwd:$cwd, firedBy:"t", firedAt:$at, selfRetire:true,
      closedAt:(if $cl=="null" then null else $cl end), marker:"FIRE-MARKER-XYZ"}' \
    > "$D/fired/$pane.json"; return 0; }

cause() { "$C" "$1" --json 2>/dev/null | jq -r '.cause'; }

# Build the whole fixture in one call: a landed repo at <session-cwd>, a registry row whose startedAt
# is <boot-offset> seconds AFTER the fire, an idle transcript, and a stamp claiming <stamp-cwd>.
# args: session-cwd stamp-cwd boot-offset-s closedAt(null|iso)
fixture() {
  local scwd="$1" stcwd="$2" off="$3" closed="$4" fire_ep=$((NOW-50000))
  mkdir -p "$scwd" "$stcwd"
  mkrepo "$scwd"
  reg "$UP" "$LIVE" "$scwd" sidA $(( (fire_ep + off) * 1000 ))
  tx sidA 9000
  stampx "$UP" "$stcwd" 50000 "$closed"
}

# ── the worktree call site (finished-teammate) ───────────────────────────────────────────────────

@test "T1 POSITIVE CONTROL — a genuine live peer (cwd match, closedAt null, in-window) is STILL reapable" {
  # Without this the refutation tests below could be green merely because no fixture here can ever
  # reach a reapable cause. It is also the narrowing proof: the fix took nothing away from the case
  # both models already agreed on.
  fixture "$D/a/.worktrees/wt1" "$D/a/.worktrees/wt1" 0 null
  [ "$(cause "$UP")" = finished-teammate ]
}

@test "T2 stale — a reused pane id in a DIFFERENT cwd is no longer reapable (was finished-teammate)" {
  fixture "$D/b/.worktrees/wt1" "$D/b-other" 0 null
  [ "$(cause "$UP")" = finished-operator ]
  [ "$(cause "$UP")" != finished-teammate ]
}

@test "T3 spent — a contract already used up by a completed self-close is no longer reapable" {
  fixture "$D/c/.worktrees/wt1" "$D/c/.worktrees/wt1" 0 "2026-08-16T00:00:00Z"
  [ "$(cause "$UP")" = finished-operator ]
  [ "$(cause "$UP")" != finished-teammate ]
}

# ── the landed non-worktree call site (finished vs finished-operator) ────────────────────────────
# A SEPARATE call site, mutated on its own: a green over the worktree branch credits nothing here
# (MEMORY per-site-mutation-attributes-coverage).

@test "T4 POSITIVE CONTROL — a landed, in-window, cwd-matching stamped pane is STILL cause=finished" {
  fixture "$D/d/plain" "$D/d/plain" 0 null
  [ "$(cause "$UP")" = finished ]
}

@test "T5 stale at the landed call site — surfaced as finished-operator, never auto-reaped" {
  fixture "$D/e/plain" "$D/e-other" 0 null
  [ "$(cause "$UP")" = finished-operator ]
  [ "$(cause "$UP")" != finished ]
}

# ── the abstain rule, the kill switch, and the state the ORACLE is blind to ──────────────────────

@test "T6 abstain — an UNRESOLVABLE stamp cwd keeps the pre-tenancy answer (unknown ≠ refuted)" {
  # The literal "x" every fixture in tests/cc-classify.bats writes. `cd x` fails ⇒ the oracle answers
  # `unknown` ⇒ the conjunct is a no-op. This is what makes the change provably additive there.
  fixture "$D/f/.worktrees/wt1" "$D/f/.worktrees/wt1" 0 null
  stampx "$UP" x 50000 null
  [ "$(cause "$UP")" = finished-teammate ]
}

@test "T7 kill switch — CC_SELFCLOSE_TENANCY=0 restores the pre-unification answer on a stale stamp" {
  fixture "$D/g/.worktrees/wt1" "$D/g-other" 0 null
  [ "$(cause "$UP")" = finished-operator ]
  CC_SELFCLOSE_TENANCY=0
  export CC_SELFCLOSE_TENANCY
  [ "$(cause "$UP")" = finished-teammate ]
}

@test "T8 the state the ORACLE is blind to — cwd matches but the tenant booted +2h ⇒ still surfaced" {
  # closedAt is null (the peer crashed rather than self-closing), so fired_stamp_tenancy answers
  # `valid` and origin-identity alone would call this a fired peer = REAPABLE. cc-classify's boot
  # window refutes it and keeps the pane. Unchanged before and after the fix BY DESIGN — this is the
  # invariant that proves the row's prescribed remedy (drop startedAt, key on cwd) was not taken.
  fixture "$D/h/.worktrees/wt1" "$D/h/.worktrees/wt1" 7200 null
  [ "$(cause "$UP")" = finished-operator ]
  [ "$(cause "$UP")" != finished-teammate ]
}

# ── deploy gap: the oracle unreachable ───────────────────────────────────────────────────────────
# The ONLY fixture in which cc-interactive.sh resolves and origin-identity.sh does NOT. Under
# tests/cc-classify.bats's nolib_bin BOTH libs vanish, so the cc-interactive fail-closed arm returns
# owned-wait first and this arm is never reached — a secondary oracle that only ever fires on the
# primary's failure is not under test at all (MEMORY secondary-oracle-fires-only-on-the-primarys-failure).
noorigin_bin() {                    # → a cc-classify that can resolve cc-interactive.sh but NOT origin-identity.sh
  mkdir -p "$D/live/.claude/bin" "$D/live/.claude/hooks/lib"
  cp "$C" "$D/live/.claude/bin/cc-classify"; chmod +x "$D/live/.claude/bin/cc-classify"
  cp "$REPO/hooks/lib/cc-interactive.sh" "$D/live/.claude/hooks/lib/cc-interactive.sh"
  rm -f "$D/live/.claude/hooks/lib/origin-identity.sh"
  printf '%s' "$D/live/.claude/bin/cc-classify"
}

@test "T9 oracle UNRESOLVABLE ⇒ no stamp is provable ⇒ fail closed to the operator-safe cause" {
  fixture "$D/i/.worktrees/wt1" "$D/i/.worktrees/wt1" 0 null
  [ "$(cause "$UP")" = finished-teammate ]          # control: with the lib, reapable
  b="$(noorigin_bin)"
  c="$(HOME="$D/live" CLAUDE_CONFIG_DIR="$D/live/.claude" "$b" "$UP" --json 2>/dev/null | jq -r '.cause')"
  [ "$c" = finished-operator ]
  [ "$c" != finished-teammate ]
}

@test "T10 oracle unresolvable warns ONCE per invocation, carries the remediation, stdout stays JSON" {
  fixture "$D/j/.worktrees/wt1" "$D/j/.worktrees/wt1" 0 null
  jq '. += [{"name":"t2","paneUUID":"4EC4DA5D-0000-4000-8000-000000000002","account":"next","cwd":"'"$D/j/.worktrees/wt1"'","pid":'"$LIVE"',"session_id":"sidB","startedAt":999950000000}]' \
    "$D/sessions.json" > "$D/sessions.json.t" && mv "$D/sessions.json.t" "$D/sessions.json"
  tx sidB 9000
  stampx 4EC4DA5D-0000-4000-8000-000000000002 "$D/j/.worktrees/wt1" 50000 null
  b="$(noorigin_bin)"
  run bash -c "HOME='$D/live' CLAUDE_CONFIG_DIR='$D/live/.claude' '$b' --all --json 2>&1 >/dev/null"
  [ "$(printf '%s\n' "$output" | grep -c 'origin-identity.sh unresolvable')" -eq 1 ]   # damped: 1, not 2
  [[ "$output" == *"./install.sh"* ]] || false
  run bash -c "HOME='$D/live' CLAUDE_CONFIG_DIR='$D/live/.claude' '$b' --all --json 2>/dev/null"
  [ "$(printf '%s' "$output" | jq -r '[.[].cause] | unique | join(",")')" = finished-operator ]
}
