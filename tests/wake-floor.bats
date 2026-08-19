#!/usr/bin/env bats
# WAKE FLOOR (v3 R1) — hooks/session-continue.sh must not let a session reach IDLE with no wake path.
#
# WHY THIS EXISTS: the wake MECHANISM was proven end-to-end on 2026-07-26 (armed cc-await-ping →
# cc-notify write → detected in one poll → exit → harness task-completion notification re-invoked the
# model). Nothing ACTUATED it: every cc-await-ping call site in the repo was a doc telling the model
# to arm, or a lint noting it hadn't. Measured: 0 armed watchers across 74 mailboxes / 1,300 unacked
# lines. This suite pins the actuator that converts "the agent should arm" into "the agent cannot
# reach idle unarmed" — and, just as load-bearing, pins the bounds that stop it becoming a loop.
#
# The floor may BLOCK a stop, so the two override paths are tested as hard as the happy path:
# an operator kill-switch always wins, and an exhausted budget degrades to a human-visible
# systemMessage and ALLOWS the stop.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  # Fixture $HOME before anything else: the floor builds its arm command from $HOME and falls back to
  # $HOME/.claude for the lib, so an unfixtured suite reads (and could write under) the operator's
  # live home. Assertions below match the command SHAPE, never an absolute prefix, so they hold here.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox";   mkdir -p "$CC_MAILBOX_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Pin the pane: $_ouid must be the FIXTURE's, never the pane that happens to run the suite.
  U="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$U"
  export CC_WAKE_FLOOR_TTL_S=0        # the TTL damper has its own test; elsewhere it must not mask a fire
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

# Stop actuation. $1=session_id  $2=transcript_path. stderr is human diagnostics only.
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }
# a live watcher: fresh heartbeat naming a pid that is actually alive ($$ = this bats process)
arm_watcher()      { printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$U.watching"; }
arm_watcher_dead() { printf 'pid=999999\n'  > "$CC_MAILBOX_DIR/$U.watching"; }
mail() { printf '2026-07-26T00:00:0%sZ [peer] page %s\n' "${1:-1}" "${1:-1}" >> "$CC_MAILBOX_DIR/$U.md"; }
# transcript whose LAST user message is $1
tx() {
  local p="$BATS_TEST_TMPDIR/tx-$BATS_TEST_NUMBER.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$p"
  printf '%s' "$p"
}

# ── THE FLOOR FIRES ───────────────────────────────────────────────────────────────
@test "unarmed session going idle ⇒ BLOCKS and names the exact arm command" {
  run actuate sidA
  blocked "$output"
  # the model must be able to paste this verbatim — an absolute path, no id to get wrong, background-able
  printf '%s' "$output" | jq -r .reason | grep -q "/cc-await-ping --timeout"
  printf '%s' "$output" | jq -r .reason | grep -q 'run_in_background=true'
  # and the human must see that it happened
  printf '%s' "$output" | jq -er .systemMessage >/dev/null
}

@test "pending mail is named in the block reason (count, not just 'you have mail')" {
  mail 1; mail 2
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q '2 message(s) are pending'
}

@test "a STALE heartbeat is not a wake path ⇒ still blocks" {
  arm_watcher
  touch -t 202001010000 "$CC_MAILBOX_DIR/$U.watching"     # older than CC_WATCH_FRESH_S
  run actuate sidA
  blocked "$output"
}

@test "DISCRIMINATOR: a fresh heartbeat naming a DEAD pid is not a wake path ⇒ still blocks" {
  # SIGKILL skips cc-await-ping's EXIT trap, leaving a marker that stays 'fresh' while nothing runs.
  # Freshness alone cannot falsify the claim — this is the case that made the pid field necessary.
  arm_watcher_dead
  run actuate sidA
  blocked "$output"
}

# ── THE FLOOR STANDS DOWN ─────────────────────────────────────────────────────────
@test "an ARMED session is left alone ⇒ no block" {
  arm_watcher
  run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "an ARMED session clears the attempt budget (a later unarmed episode gets a fresh one)" {
  run actuate sidA                                   # attempt 1 — writes the budget
  [ -f "$CC_MAILBOX_DIR/$U.wakefloor" ]
  arm_watcher
  run actuate sidA                                   # armed ⇒ budget cleared
  [ ! -f "$CC_MAILBOX_DIR/$U.wakefloor" ]
  rm -f "$CC_MAILBOX_DIR/$U.watching"                # watcher exits (self-disarming) …
  run actuate sidA
  blocked "$output"                                  # … and the floor fires again, not exhausted
}

@test "OVERRIDE: an operator kill-switch phrase ⇒ never blocks, warns instead" {
  local t; t="$(tx 'looks good, stop here')"
  run actuate sidA "$t"
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'No inbox wake path armed'
}

@test "after ONE declined attempt with no mail waiting, the floor stops nagging" {
  run actuate sidA; blocked "$output"                # first idle of the session: always try
  run actuate sidA                                   # nothing is waiting ⇒ leave the session alone
  ! blocked "$output" || false
  [ -z "$output" ]                                   # not even a warning: there is nothing to lose yet
}

@test "BOUND: budget exhausted ⇒ allows the stop with a human-visible warning, never a loop" {
  # The cap is only reachable while mail is actually PENDING — that is the only state in which the
  # floor keeps pressing. Without mail it stands down after one attempt (test above).
  mail 1
  run actuate sidA; blocked "$output"                # 1
  run actuate sidA; blocked "$output"                # 2 (CC_WAKE_FLOOR_MAX default 2)
  run actuate sidA                                   # 3 — must give up, loudly
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'cc-await-ping'
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'waiting and NO wake path'
}

@test "BOUND: the TTL damper stops a burst of short turns re-blocking every one" {
  CC_WAKE_FLOOR_TTL_S=600 run actuate sidA
  blocked "$output"
  CC_WAKE_FLOOR_TTL_S=600 run actuate sidA           # immediately again, inside the TTL
  ! blocked "$output"
}

@test "a NEW session in the same pane gets a fresh budget (no inherited exhaustion)" {
  mail 1
  run actuate sidA; run actuate sidA                 # spend sidA's whole budget (mail pending)
  run actuate sidA; ! blocked "$output" || false     # sidA is now exhausted (|| false: `!` is errexit-exempt)
  run actuate sidB                                   # a successor in the same pane must not inherit it
  blocked "$output"
}

@test "CC_WAKE_FLOOR=0 disables the floor entirely" {
  CC_WAKE_FLOOR=0 run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "a pane with no inbox identity is never blocked" {
  ITERM_SESSION_ID="" run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "the floor never pre-empts an armed continuation sentinel" {
  ( cd "$CWD" && CLAUDE_CODE_SESSION_ID=sidA bash "$HOOK" set "finish the thing" >/dev/null )
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q 'Loose ends remain'   # the SENTINEL's reason, not the floor's
}

# ── RED-PROOF — the control is the REAL pre-fix artifact, not an approximation ─────
# A suite that cannot fail proves nothing. Replay hooks/ exactly as it stood BEFORE this change and
# require the two core assertions to FAIL there.
#
# THE CONTROL IS PINNED TO A SHA, NEVER A MOVING REF. This replayed `origin/main`, which was the
# pre-fix tree only until this very change landed on it — from that moment the "control" IS the fixed
# tree, both sanity greps invert, and the RED-proof fails permanently against a perfectly green tree.
# It did: the suite went red the moment fea9f7a8 landed. A control must replay the real pre-fix
# artifact, and only an immutable ref can promise that.
#   a219de9d = the last commit before 99164d48 (extracted mailbox_wake_armed) and fea9f7a8 (the floor),
#   i.e. the newest tree that genuinely predates BOTH halves of the change under test.
CC_WAKE_FLOOR_PREFIX_SHA="${CC_WAKE_FLOOR_PREFIX_SHA:-a219de9d}"
@test "RED-PROOF: the pre-fix hooks/ (pinned sha) does NOT block an unarmed idle session" {
  local old="$BATS_TEST_TMPDIR/pre"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_WAKE_FLOOR_PREFIX_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_WAKE_FLOOR_PREFIX_SHA unavailable"
  [ -f "$old/hooks/session-continue.sh" ]
  # sanity: the control must genuinely predate the change
  ! grep -q 'WAKE FLOOR' "$old/hooks/session-continue.sh" || false
  ! grep -q 'mailbox_wake_armed' "$old/hooks/lib/mailbox-pending.sh" || false
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$old/hooks/session-continue.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  ! blocked "$output"                                # RED: the defect this change closes
}

# ── No advertised key at all (2026-07-31) — SUPERSEDES "box-key agreement" (2026-07-29) ──────────
# The 2026-07-29 tests here pinned the opposite mapping: the floor must advertise the SESSION key,
# "the key the drain reads". That fixed the two advisories DISAGREEING by pointing both at the wrong
# side of the channel. Nothing writes the session box directly — cc-notify addresses panes (cc-roles/*
# and every cc-registry row hold pane uuids) and resolves no alias, so the session box fills only when
# a BOUNDARY runs mailbox_migrate, and a boundary is the very thing a waiting watcher exists to cause.
# A session that followed that advice reported armed and was deaf. Measured on one cc-notify write:
# session-keyed watcher rc 2 (timed out), pane-keyed watcher woke in one poll.
#
# So the invariant is no longer "the two hooks agree on a key" — agreement is satisfiable by two wrong
# answers. It is COVERAGE: the reader must cover the writer's key space. The arm command therefore
# carries NO id (cc-await-ping derives ${ITERM_SESSION_ID##*:}, the same expression cc-notify resolves
# a target with, then covers that key's whole set via the lib's mailbox_keyset). There is no key left
# here to agree or disagree about. End-to-end coverage is pinned in tests/cc-await-ping.bats; these
# pin the ADVERTISEMENT, which is this hook's half.
alias_to() { mkdir -p "$CC_MAILBOX_DIR/.alias"; printf '2026-07-29T00:00:00+0000 %s\n' "$1" > "$CC_MAILBOX_DIR/.alias/$U"; }

@test "box key: with a pane→session alias, the advertised arm still names NO key" {
  local S="11111111-2222-3333-4444-555555555555"
  alias_to "$S"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  blocked "$output" || false
  echo "$output" | grep -q "cc-await-ping --timeout" || false
  ! echo "$output" | grep -q "cc-await-ping $S" || false    # not the session key (deaf: nothing writes it)
  ! echo "$output" | grep -q "cc-await-ping $U" || false    # nor the bare pane — the watcher derives it
}

@test "box key: with NO alias, the advertised arm is byte-identical (the key never entered it)" {
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  blocked "$output" || false
  echo "$output" | grep -q "cc-await-ping --timeout" || false
  ! echo "$output" | grep -qE "cc-await-ping +[0-9A-Fa-f-]{8}" || false
}

@test "the two advisories emit the IDENTICAL arm command (the disagreement cannot recur)" {
  local S="11111111-2222-3333-4444-555555555555"
  alias_to "$S"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$HOOK' 2>/dev/null"
  local floor; floor="$(printf '%s' "$output" | jq -r .reason | grep -o '/cc-await-ping [^)]*' | head -n1)"
  # the drain's half, run against the SAME fixture mailbox/pane
  run bash -c "echo '{}' | bash '$REPO/hooks/mailbox-drain.sh' prompt 2>/dev/null"
  local drain; drain="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' \
    | grep -o '/cc-await-ping [^)]*' | head -n1)"
  [ -n "$floor" ] && [ -n "$drain" ] || false              # neither side may be silently empty
  [ "$floor" = "$drain" ] || { echo "floor=[$floor] drain=[$drain]" >&2; false; }
}

# Pinned, never a moving ref — same reasoning as the RED-PROOF above: once this change lands on
# origin/main, a floating control IS the fixed tree and the proof inverts.
CC_BOXKEY_PREFIX_SHA="${CC_BOXKEY_PREFIX_SHA:-c967d7cd}"
@test "RED-PROOF: the pre-fix hook advertises a KEY at all (either key, both wrong)" {
  local S="11111111-2222-3333-4444-555555555555"
  local old="$BATS_TEST_TMPDIR/prekey"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_BOXKEY_PREFIX_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_BOXKEY_PREFIX_SHA unavailable"
  [ -f "$old/hooks/session-continue.sh" ]
  # sanity: the control must genuinely predate BOTH fixes (no resolve_key, and it interpolates an id)
  ! grep -q 'mailbox_resolve_key' "$old/hooks/session-continue.sh" || false
  grep -q 'cc-await-ping \$_ouid' "$old/hooks/session-continue.sh" || false
  alias_to "$S"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$old/hooks/session-continue.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  # RED: an id is interpolated at all. WHICH id it is was the 2026-07-29 argument; that both candidates
  # are wrong is this one — so the proof asserts the shape, not the side.
  echo "$output" | grep -qE "cc-await-ping +[0-9A-Fa-f-]{8}" || false
  ! echo "$output" | grep -q "cc-await-ping --timeout" || false
}

# ══ THE THIRD STATE: terminating / lead-owned ⇒ the floor ABSTAINS ════════════════════════════════
# The floor read only ACTIVE and IDLE. An Agent-Teams assignee that had ACCEPTED a shutdown_request
# was therefore blocked from ending its turn for ~4 HOURS live: honouring the shutdown re-entered this
# hook, which demanded a 4-hour watcher first. CC_WAKE_FLOOR_MAX did not bound it, because the
# already-armed branch RESETS the budget — so a COMPLIANT session armed, cleared its own budget, lost
# the watcher to the teardown it was obeying, and met a floor with count=0 again.
#
# The two abstains are tested SEPARATELY and each with a control that can fail the same way: an
# over-broad gate here silently disarms the whole fleet, which is worse than the defect it fixes.

# ancestry fixture — rows are "pid ppid command…", walked from CC_WF_START_PID (a hook's own $$ is
# not knowable to this suite, which is why that seam exists).
CCBIN="/Users/x/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
pstable() {
  local p="$BATS_TEST_TMPDIR/pstable-$BATS_TEST_NUMBER"
  printf '%s\n' "$@" > "$p"
  export CC_WF_PSTABLE_FILE="$p" CC_WF_START_PID=1000
}
# hop2 = the CC process, carrying the three flags CC gives ONLY a teammate.
assignee_ancestry() { pstable \
  "1000 1001 bash $HOOK" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --agent-id ${1:-gu2-arch}@session-${2:-t1} --agent-name ${1:-gu2-arch} --team-name session-${2:-t1} --agent-color blue" \
  "1003 1 -zsh"; }
lead_ancestry() { pstable \
  "1000 1001 bash $HOOK" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --permission-mode default --model claude-opus-5" \
  "1003 1 -zsh"; }
# the harness's own record of the team, as CC writes it (lead = tmuxPaneId "leader"/agentType team-lead)
team_cfg() { # $1=team-suffix  $2=assignee member name
  local d="$BATS_TEST_TMPDIR/teamroot/session-${1}"; mkdir -p "$d"
  jq -n --arg n "$2" '{name:"t",members:[
      {agentId:"team-lead@t",name:"team-lead",agentType:"team-lead",tmuxPaneId:"leader"},
      {agentId:($n+"@t"),name:$n,agentType:"general-purpose",tmuxPaneId:"7D0DE6BE-56AC-41BE-9589-195385BE055A"}]}' \
    > "$d/config.json"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teamroot"
}
# a teardown marker, in the writers' exact shape. $1=filename stem (sid or pane), $2=sid in the BODY.
mark_teardown() {
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"; mkdir -p "$CC_TEARDOWN_DIR"
  printf '{"key_kind":"k","pane":"%s","sid":"%s","mode":"teammate-idle","ts":"t"}\n' \
    "$U" "${2:-}" > "$CC_TEARDOWN_DIR/$1.json"
}
# stderr carries the abstain reason; $output alone cannot see it. The `2>&1 >/dev/null` ORDER is
# deliberate and is the whole point: fd2 is pointed at the capture FIRST, then fd1 is discarded, so
# $output holds stderr ONLY. Reversing it (the mistake SC2069 usually catches) would capture stdout
# and throw stderr away, and every assertion below would then read the decision JSON instead of the
# abstain reason — i.e. it would still "pass" on the block tests and silently stop testing anything.
# shellcheck disable=SC2069
actuate_err() { printf '{"cwd":"%s","session_id":"%s","transcript_path":""}' "$CWD" "${1:-sidA}" \
  | bash "$HOOK" 2>&1 >/dev/null; }

@test "(A) an ASSIGNEE going idle unarmed ⇒ the floor stands down (the ~4h deadlock)" {
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
}

@test "(A) the abstain names WHY, and says the team config confirmed it" {
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  run actuate_err sidA
  echo "$output" | grep -q "ABSTAINS" || false
  echo "$output" | grep -q "gu2-arch@session-t1" || false
  echo "$output" | grep -q "confirmed by its team config" || false
}

@test "(A) UNKNOWN: no readable team config ⇒ argv evidence still stands (says so)" {
  assignee_ancestry gu2-arch t1
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/nonexistent-root"
  run actuate sidA
  ! blocked "$output" || false
  run actuate_err sidA
  echo "$output" | grep -q "argv evidence only" || false
}

@test "DISCRIMINATOR (A) REFUTED: the team's own config knows no such member ⇒ still BLOCKS" {
  # ps -o command= flattens argv, so a brief that QUOTES assignee argv reads as three real flags —
  # concrete in this repo, and the reason argv alone is not allowed to disarm a lead.
  assignee_ancestry not-a-member t1; team_cfg t1 someone-else
  run actuate sidA
  blocked "$output" || false
}

@test "CONTROL (A): an ordinary LEAD ancestry still gets the floor" {
  lead_ancestry
  run actuate sidA
  blocked "$output" || false
}

@test "DISCRIMINATOR (A): ONE flag is not an assignee (a brief that merely mentions --agent-id)" {
  pstable "1000 1001 bash $HOOK" \
          "1001 1002 /bin/zsh -c source /snap.zsh" \
          "1002 1003 $CCBIN --model claude-opus-5 -p brief mentions --agent-id x@session-t1 verbatim" \
          "1003 1 -zsh"
  team_cfg t1 x
  run actuate sidA
  blocked "$output" || false
}

@test "DISCRIMINATOR (A): another pane's assignee is NOT my ancestry ⇒ still BLOCKS" {
  # the flagged process is real and alive, just not above ME — a machine-wide scan would disarm
  # every session in the fleet the moment one teammate existed.
  pstable "1000 1001 bash $HOOK" \
          "1001 1002 /bin/zsh -c source /snap.zsh" \
          "1002 1003 $CCBIN --model claude-opus-5" \
          "1003 1 -zsh" \
          "2000 1 $CCBIN --agent-id other@session-t1 --agent-name other --team-name session-t1"
  team_cfg t1 other
  run actuate sidA
  blocked "$output" || false
}

@test "(B) a fresh SID-keyed teardown marker ⇒ terminating, not idle ⇒ stands down" {
  mark_teardown sidA sidA
  run actuate sidA
  ! blocked "$output" || false
  run actuate_err sidA
  echo "$output" | grep -q "terminating, not going idle" || false
}

@test "(B) a PANE-keyed marker with an EMPTY sid is the legitimate self-close case ⇒ stands down" {
  # the real self-close path blanks SESSION_ID; rejecting this would regress the 2026-07-23 fix.
  mark_teardown "$U" ""
  run actuate sidA
  ! blocked "$output" || false
}

@test "DISCRIMINATOR (B): a pane marker naming a DIFFERENT sid ⇒ the successor still gets the floor" {
  # an in-place --recycle leaves the PREDECESSOR's marker on a pane that now hosts the SUCCESSOR.
  mark_teardown "$U" "sid-PREDECESSOR"
  run actuate sidA
  blocked "$output" || false
}

@test "DISCRIMINATOR (B): a STALE marker is not a teardown in progress ⇒ still BLOCKS" {
  mark_teardown sidA sidA
  touch -t 202001010000 "$CC_TEARDOWN_DIR/sidA.json"
  run actuate sidA
  blocked "$output" || false
}

@test "SEAM: CC_WAKE_FLOOR_TEARDOWN=0 restores the old behaviour for an assignee" {
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  export CC_WAKE_FLOOR_TEARDOWN=0
  run actuate sidA
  blocked "$output" || false
}

@test "an abstain must NOT spend a budget attempt (it means 'does not apply', not 'declined')" {
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  run actuate sidA
  ! blocked "$output" || false
  [ ! -f "$CC_MAILBOX_DIR/$U.wakefloor" ]            # nothing written ⇒ nothing spent
  # …so the SAME session, once it is no longer an assignee, still meets a floor with a full budget.
  lead_ancestry
  run actuate sidA
  blocked "$output" || false
}

@test "NO SILENT DROP: abstaining with mail pending says so where a human can see it" {
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  mail 1; mail 2
  run actuate sidA
  ! blocked "$output" || false
  printf '%s' "$output" | jq -r .systemMessage | grep -q '2 message(s) are still unread' || false
}

# ── (C) a LIVE /goal ⇒ the floor instructs a DIFFERENT arm, not silence ──────────────────────────
# CC deletes the /goal Stop hook at any Stop where a non-terminal background Bash exists
# (docs/research/goal-in-handoff-2026-08-08.md § RESOLVED) — the exact watcher this floor
# instructs. This block used to be the instruction-injector that made armed goals inert fleet-wide,
# and the 2026-08-10 fix was to ABSTAIN.
#
# ── C7 FLIP (2026-08-16, docs/research/goal-safe-2way-comms-2026-08-13.md §4) ────────────────────
# Abstaining fixed the starvation pole and installed the SPIN one: bare, the session blocks every
# stop on an unmet goal and re-judges an unchanged world (90 consecutive unmet evaluations in 76 min
# on the type specimen; 15 cap force-idles in 3 days — and ABOVE that cap the abstain's premise that
# "the goal keeps this session awake" is simply false: the harness force-idles and the session is
# deaf). So the floor now BLOCKS under a live goal like any other unarmed idle, and names the
# idle-scoped form. The discrimination that matters is the COMMAND, so these tests assert the
# spelling and not merely the block: a floor that blocked with the denied 4-hour arm would satisfy a
# bare `blocked` assertion while handing the model a command its own chokepoint refuses.

goal_tx() { # a transcript whose LAST goal_status is a LIVE arm marker
  p="$BATS_TEST_TMPDIR/goal-tx-$BATS_TEST_NUMBER.jsonl"
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"drive the rollout to landed"}}\n' > "$p"
  printf '%s' "$p"
}

@test "(C) a LIVE /goal ⇒ the floor BLOCKS and instructs the idle-scoped arm, with this session's sid" {
  run actuate sidA "$(goal_tx)"
  [ "$status" -eq 0 ]
  blocked "$output" || false
  r="$(printf '%s' "$output" | jq -r .reason)"
  printf '%s' "$r" | grep -q 'cc-await-ping --idle-scoped --sid sidA' || false
  # the DENIED spelling must be ABSENT: under a live goal the chokepoint refuses it, so instructing
  # it here would hand the model a command its own guard rejects
  ! printf '%s' "$r" | grep -q 'cc-await-ping --timeout' || false
  # …and the block must say WHY this form, or it teaches a spelling without the rule behind it
  printf '%s' "$r" | grep -q 'stands itself down' || false
}

@test "DISCRIMINATOR (C): with NO goal the floor instructs the ORDINARY parked arm (unchanged)" {
  run actuate sidA
  blocked "$output" || false
  r="$(printf '%s' "$output" | jq -r .reason)"
  printf '%s' "$r" | grep -q 'cc-await-ping --timeout' || false
  ! printf '%s' "$r" | grep -q -- '--idle-scoped' || false
}

@test "DISCRIMINATOR (C): a MET goal is no goal — the floor still blocks" {
  p="$BATS_TEST_TMPDIR/goal-met.jsonl"
  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"x"}}\n'
    printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"x","iterations":1}}\n'
  } > "$p"
  run actuate sidA "$p"
  blocked "$output" || false
}

@test "(C) the goal abstain spends NO budget attempt and says so visibly with mail pending" {
  # PENDING MAIL is the one case the C7 flip deliberately leaves as an abstain — the session HAS
  # work, cc-await-ping's C4 would refuse the arm for exactly that reason, and the goal-forced turns
  # deliver the mail. Blocking to demand a command designed to fail is a pure round-trip.
  mail 1
  run actuate sidA "$(goal_tx)"
  ! blocked "$output" || false
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'goal' || false
  [ ! -f "$CC_MAILBOX_DIR/$U.wakefloor" ]            # nothing written ⇒ nothing spent
  # …and the same session, once its goal is gone, still meets a floor with a full budget.
  run actuate sidA
  blocked "$output" || false
}

# Pinned, never a moving ref: once this lands on origin/main a floating control IS the fixed tree and
# the proof inverts into a vacuous pass.
CC_ASSIGNEE_ABSTAIN_SHA="${CC_ASSIGNEE_ABSTAIN_SHA:-638fba76}"
@test "RED-PROOF: the pre-fix hook BLOCKS an assignee that has been told to shut down" {
  local old="$BATS_TEST_TMPDIR/preabstain"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_ASSIGNEE_ABSTAIN_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_ASSIGNEE_ABSTAIN_SHA unavailable"
  [ -f "$old/hooks/session-continue.sh" ]
  # the control must genuinely predate the fix — a skip reads as a pass, so this is asserted
  ! grep -q 'wf_assignee_argv' "$old/hooks/session-continue.sh" || false
  assignee_ancestry gu2-arch t1; team_cfg t1 gu2-arch
  mark_teardown sidA sidA
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$old/hooks/session-continue.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  blocked "$output" || false                          # RED: an assignee under teardown, blocked
}

# ════ CUSTODY ATTRIBUTION (backlog 9581119669f9) ═════════════════════════════════════════════════
#
# The custody arm re-fires this floor while dispatched work has not returned, and it used to select
# those rows by `--cwd` ALONE, then tell whoever was stopping "you are their ORIGINATOR — their
# completion pings arrive through this inbox". claude-infrastructure is a SHARED checkout that many
# sessions cd into, so for every session that merely shares the directory BOTH halves were false.
# Measured 2026-08-11 from pane 246: two open rows, originatorPane 113 and 248, neither this pane,
# and neither peer's ping routable here. It fired on the healthy case — a page that cannot tell an
# originator from a bystander carries no bits (memory: alarm-polarity-and-attention-budget) — while
# instructing an innocent session to await unreachable work, to `cc-custody return` a marker it does
# not own, and holding ✅ unreachable for a session with nothing open.
#
# The store always had the discriminator (originatorPane / notifyBack on every row). The fix gives
# this arm the same attribution gate the SHIP FLOOR in the same file already has.

# cust_shim <json> — stand in for the cc-custody binary at the FIRST path the hook probes
# ($(dirname $0)/../bin/cc-custody). `list --open --cwd . --json` replays <json>; `count` answers
# from the same array, so a shim can never disagree with itself the way two literals would.
cust_shim() {
  mkdir -p "$HOME/.claude/bin"
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/custody.json"
  cat > "$HOME/.claude/bin/cc-custody" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  list)  cat "$CUSTODY_JSON" ;;
  count) jq 'length' < "$CUSTODY_JSON" ;;
esac
SHIM
  chmod +x "$HOME/.claude/bin/cc-custody"
  export CUSTODY_JSON="$BATS_TEST_TMPDIR/custody.json"
  # Bind the seam. Without it the hook resolves the REAL bin/cc-custody out of the checkout and
  # reads the operator's live store, which answers 0 — so every "must block" case below would fail
  # and, worse, every "must NOT block" case would pass VACUOUSLY. That asymmetry is exactly how an
  # untested arm looks tested.
  export CC_CUSTODY_BIN="$HOME/.claude/bin/cc-custody"
}

@test "custody: a row THIS pane originated re-fires the floor and asserts originatorship" {
  cust_shim "$(jq -nc --arg u "$U" '[{originatorPane:$u,slug:"fire-mine"}]')"
  out="$(actuate sidA)"; blocked "$out"              # first idle: the floor always tries once
  out="$(actuate sidA)"                              # …and with no mail, ONLY custody re-fires it
  blocked "$out"
  printf '%s' "$out" | grep -q 'YOU fired'
}

@test "custody DISCRIMINATOR: a SIBLING's row does not convict this pane" {
  # The whole bug, in one assertion. Same cwd, same store, same shape — only the owner differs.
  cust_shim "$(jq -nc '[{originatorPane:"w0t0p0:BBBBBBBB-9999-8888-7777-666666666666",slug:"fire-theirs"}]')"
  out="$(actuate sidA)"; blocked "$out"              # first idle
  out="$(actuate sidA)"                              # second: a sibling's row must not re-fire it
  ! blocked "$out" || false
}

@test "custody: with one row mine and one a sibling's, the floor counts EXACTLY one" {
  # The control the backlog row names. A gate that simply counted rows would say 2 here, and one
  # that had silently stopped counting would say 0 — only correct attribution says 1.
  cust_shim "$(jq -nc --arg u "$U" '[{originatorPane:$u,slug:"fire-mine"},
                                     {originatorPane:"w0t0p0:BBBBBBBB-9999-8888-7777-666666666666",slug:"fire-theirs"}]')"
  out="$(actuate sidA)"; blocked "$out"
  out="$(actuate sidA)"
  blocked "$out"
  printf '%s' "$out" | grep -q '1 dispatched session(s) YOU fired'
}

@test "custody: notifyBack is a second ownership spelling, and its anchor is not a bare suffix" {
  # handoff-fire arms notifyBack as either the bare pane or <worktree>-<pane>, so the match needs
  # the "-" anchor: without it, pane 15 would claim pane 415's row.
  export ITERM_SESSION_ID="w0t0p0:415"
  cust_shim '[{"notifyBack":"wt-pool-2-415","slug":"fire-wt"}]'
  out="$(actuate sidA)"; blocked "$out"
  out="$(actuate sidA)"; blocked "$out"              # 415 owns it
  export ITERM_SESSION_ID="w0t0p0:15"
  out="$(actuate sidB)"; blocked "$out"              # fresh session ⇒ first idle always blocks
  out="$(actuate sidB)"
  ! blocked "$out" || false                          # 15 must NOT inherit 415's debt                          # 15 must NOT inherit 415's debt
}

@test "custody: an UNATTRIBUTABLE row still counts, but the message HEDGES instead of asserting" {
  # Deliberately NOT dropped: cc-custody's own POLARITY header rejects the direction that silently
  # loses custody, because a per-pane key is lost across the measured resume-loses-pane-id case. So
  # the safe reading is "cannot decide", and the wording has to say so rather than accuse.
  cust_shim '[{"slug":"fire-orphan"}]'
  out="$(actuate sidA)"; blocked "$out"
  out="$(actuate sidA)"
  blocked "$out"
  printf '%s' "$out" | grep -q 'cannot say whose'
  printf '%s' "$out" | grep -q 'NOT yours'
}

# ── HEADLESS (F6 / T16 of docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md) ──
# A pane session's wake is an armed cc-await-ping whose EXIT rides the harness's task-completion
# notification back into the model. A resident `--input-format stream-json` agent has no such
# boundary — its only one is a WRITE TO ITS STDIN — so blocking its Stop demands a continuation the
# substrate cannot produce. The measured outcome is a DEATH (`Error: Input must be provided`), which
# is why this abstain is a correctness case and not an ergonomics one.
#
# WHY THE EXISTING "no inbox identity" CASE DOES NOT ALREADY COVER THIS. That case pins the EMPTY
# address, and the spec wrote F6 as "pane-less" meaning exactly that. But gap 1 did not land the
# empty-pane fallthrough it prescribed: `cc-pane-headless:124` mints `hdl-<16hex>` and `:197` exports
# it as CC_PANE_ID, so a headless session arrives here with a perfectly ordinary NON-EMPTY address
# and sails past that guard. These cases pin the discriminator that actually holds — the writer's
# env, `session-register.sh:142`'s own predicate — never the id's shape.
HDL="hdl-0123456789abcdef"
headless_env() { unset ITERM_SESSION_ID; export CC_PANE_ID="$HDL"; }
hmail() { printf '2026-08-19T00:00:0%sZ [peer] page %s\n' "${1:-1}" "${1:-1}" >> "$CC_MAILBOX_DIR/$HDL.md"; }

@test "headless: a pane-less session is NOT blocked — a watcher is not its wake path" {
  headless_env
  # ANTI-VACUITY: the fixture must actually be the headless shape, or every assertion below is over
  # a pane session and passes for the wrong reason.
  [ -n "${CC_PANE_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ] || false
  run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
}

@test "headless: the abstain says WHY on stderr (T16)" {
  headless_env
  run actuate_err sidA
  printf '%s' "$output" | grep -qF 'wake floor ABSTAINS' || false
  printf '%s' "$output" | grep -qF 'pane-less session' || false
}

@test "headless: with mail pending the abstain names the count AND the wake primitive" {
  # Not silent when it costs something: standing down quietly over unread mail is the silent-cap
  # defect. Naming the count also PROVES $_ouid resolved to the headless address — the mail was
  # written under that key and nowhere else, so a count of 2 cannot be produced by any other reading.
  headless_env
  hmail 1; hmail 2
  run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
  printf '%s' "$output" | jq -r .systemMessage | grep -qF '2 message(s)' || false
  printf '%s' "$output" | jq -r .systemMessage | grep -qF "cc-wake-headless $HDL" || false
}

@test "headless: the abstain does not consume a budget attempt" {
  # Placed with the other abstains for this reason: a session that was headless for a while must not
  # arrive at a genuine unarmed idle with its attempts already spent.
  headless_env
  run actuate sidA
  [ ! -f "$CC_MAILBOX_DIR/$HDL.wakefloor" ] || false
}

@test "DISCRIMINATOR: CC_PANE_ID alone is NOT headless — a pane session carrying one still blocks" {
  # GREEN PRE-FIX BY CONSTRUCTION — it asserts a PRESERVATION, so it carries no red-proof of its own.
  # Its guarantee comes from mutant M3 (drop the ITERM_SESSION_ID conjunct from the abstain), which
  # reds exactly this case and nothing else. Without it the abstain would fire for every session in
  # the fleet, since `cc-pane` exports CC_PANE_ID on pane sessions too — i.e. the floor would be
  # silently disabled everywhere while the whole suite stayed green.
  export CC_PANE_ID="$U"                      # set, but ITERM_SESSION_ID is also set (setup's)
  [ -n "${ITERM_SESSION_ID:-}" ] || false
  run actuate sidA
  blocked "$output" || false
}

# Pinned, never a moving ref — same reasoning as the two RED-PROOFs above: once this change lands on
# origin/main a floating control IS the fixed tree and the proof inverts.
#   3b11e115 = recycle #46's docs commit, the last tree before the F6 abstain.
CC_HEADLESS_PREFIX_SHA="${CC_HEADLESS_PREFIX_SHA:-3b11e115}"
@test "RED-PROOF: the pre-fix hook (pinned sha) BLOCKS a headless session" {
  local old="$BATS_TEST_TMPDIR/prehdl"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_HEADLESS_PREFIX_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_HEADLESS_PREFIX_SHA unavailable"
  [ -f "$old/hooks/session-continue.sh" ]
  # sanity: the control must genuinely predate the change, or a green tree replays as a red one
  ! grep -q 'its wake is the spawner stdin write' "$old/hooks/session-continue.sh" || false
  headless_env
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$old/hooks/session-continue.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  blocked "$output" || false                   # RED: the defect this change closes — it kills the session
}
