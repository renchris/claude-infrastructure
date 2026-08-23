#!/bin/bash
# shellcheck disable=SC2015  # the selftest's `[ test ] && … || …` reporter idiom is intentional.
#
# payload-lint — F3 of the never-let-completion-go-silent bar (scripts/comms-safety-gate.sh). Lints a
# SUCCESSOR-FIRE PAYLOAD (a /tmp/fire-*.txt or a handoff prompt) for the BACK-CHANNEL BLOCK — the ROOT of
# the W5 incident.
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# W5's successor-fire payload DROPPED the back-channel block (the cc-notify line + the desk full-uuid), so
# the successor had no VERIFIED channel to the desk; its terminal announce fell back to SendMessage (a
# teammate-scope, UNRESOLVABLE target for the desk) and SILENTLY degraded to disk-truth — the desk learned
# of the ship 50 min late FROM THE OPERATOR. A payload without the back-channel block IS that bug waiting to
# happen. This lint makes it RED.
#
# THE RULE (two checks):
#   F3    BACK-CHANNEL BLOCK — the payload MUST carry a cc-notify reference AND a resolvable target:
#         a full desk uuid (8-4-4-4-12) OR role-indirection (cc-roles/<role> | --role <role>, the
#         P0-15 form that follows a recycled desk). Missing the reference, or carrying it with NO
#         resolvable target → RED (a successor cannot announce).
#   F3/a  (serves F2) NO TERMINAL-ANNOUNCE VIA SendMessage — a line PRESCRIBING SendMessage for a terminal /
#         desk / orchestrator / operator announce is the W5 bug (SendMessage is teammate-scope only). A
#         PROHIBITION ('never SendMessage the desk') is fine — the lint distinguishes prescriptive from
#         proscriptive (the s3b-lint 'a comment is not the action' trap).
#
# THIS IS A STATIC PROXY (like s3b-lint): it faithfully discriminates the registered fixtures; it is NOT
# adversarial-obfuscation-proof, and it DECLARES that rather than rotting into false confidence. When the
# real fire-payload templates are authored, they must PASS this by construction, not by out-grepping it.
#
#   payload-lint.sh <payload-file>   lint one payload
#   payload-lint.sh --selftest       RED-prove: block-less → RED; SendMessage terminal → RED; well-formed →
#                                    GREEN (prohibition tolerated); missing file → LOUD(2)
#
# Exit: 0 = back-channel block present, no SendMessage terminal-announce (GREEN)
#       1 = block missing OR a SendMessage terminal-announce present (RED)
#       2 = cannot determine (missing/empty file) — LOUD, never a silent 0 (the D9 law: an indeterminate
#           check that passes is indistinguishable from a working one)
set -uo pipefail

UUID='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
# 🚨 ANCHORED TO THE cc-notify ARGUMENT POSITION — for the SAME reason SESSION_NAME_REF is, and it
# was an omission that this rule was not (backlog bacdfc4f63ab, measured 2026-08-22).
# The 2026-08-08 correction below anchored the NEW session-name rule and left this PRE-EXISTING uuid
# rule matching a bare token ANYWHERE in the payload. So the very case that correction exists to
# refuse walks straight back in whenever any uuid appears in unrelated prose — and a fire payload
# almost always carries one (a predecessor session id, a plan ref, a cited pane). Measured:
#     cc-notify 775 …                          (no uuid in the file)  → RED    ← the correction works
#     cc-notify 775 … + "predecessor was <uuid>" in prose → GREEN, and `cc-notify 775` is
#                                                            verdict=unresolvable → the W5 root,
#                                                            reached THROUGH a green F3.
# Optional flags are tolerated (`cc-notify --receipt <uuid> …`) because the DOWNSIDE OF A FALSE-RED
# HERE IS DESTRUCTIVE, not cosmetic: payload_lint_gate … enforce aborts the fire (exit 4) and
# fire_cleanup then removes the worktree and DELETES THE BRANCH. Measured against every real payload
# on this box: 116 of 116 genuine greens stay green (0 false-RED), and the laundered case goes RED.
UUID_REF="cc-notify([[:space:]]+--[A-Za-z-]+)*[[:space:]]+\"?$UUID"
SENDMSG='SendMessage'
# non-teammate TERMINAL targets/events — the scope F2/a forbids over SendMessage.
ANN='desk|orchestrator|operator|terminal|ship-witness|succession|program-complete'
# prohibition / documentation markers — a line carrying one is guidance, not a prescription.
NEGATION='never|not a teammate|unresolv|do ?n.?t|does ?n.?t|avoid|degrad|silent|teammate-scope|instead of|rather than|WRONG|bug|forbidden|prohibit'
# role-indirection (P0-15): the sanctioned back-channel that resolves a ROLE to the CURRENT pane via
# ~/.claude/cc-roles/<role> — strictly better than a frozen uuid, which goes stale (the G-P2-2 dead-desk-
# uuid incident). A payload pairing cc-notify with a role reference (the cc-roles/<role> path a reader
# cats, or a --role flag) is addressable and MUST satisfy F3 alongside a literal uuid — else every
# role-driven fire (every /goal fire uses `cc-notify "$(cat ~/.claude/cc-roles/desk)"`) false-REDs.
#
# 🚨 IT IS THE CLASS "a role", NOT THREE SPELLINGS — corrected 2026-08-23 (backlog f1a51344cb84).
# This rule enumerated `desk|operator|orchestrator`, but cc-roles manages ARBITRARY roles: `cc-roles
# claim <role>` imposes no name validation at all, and `cc-notify --role <name>` (:556) is likewise
# name-agnostic — it just reads $CC_ROLES_DIR/<name>. So the list could only ever be a snapshot of
# the roles its author happened to know, and it decayed exactly as an enumeration does. Measured on
# this box the day of the fix, the list was not merely incomplete but ANTI-CORRELATED with reality:
#     desk          allowlisted  — NO role file at all
#     operator      allowlisted  — NO role file at all
#     orchestrator  allowlisted  — file present, reads ABSENT/empty
#     drain-lead    REFUSED      — file present, reads LIVE 102
#     docs-lead     REFUSED      — file present, reads UNVERIFIED 450
# i.e. it admitted three names of which zero resolved, and refused the only two that did. A fire
# briefed with `cc-notify --role drain-lead` aborted F3 twice with "resolvable target: ABSENT" while
# that role read LIVE. Widening the list to five names would just repeat the class (memory:
# denylist-enumerates-spellings-not-the-class), so the arm keys on the role-reference FORM.
#
# WHY FORM AND NOT LIVE RESOLVABILITY — the obvious remedy is refuted by the same measurement.
# Shelling out to `cc-roles read <role>` would RED `--role desk` today, because desk has no file —
# and the desk's own /goal fires are the main path this arm exists to keep green. A false-RED here is
# the UNRECOVERABLE direction (payload_lint_gate … enforce aborts the fire → fire_cleanup removes the
# worktree and DELETES THE BRANCH), so a liveness-keyed arm would be strictly more dangerous than the
# bug it replaces. It would also be asymmetric: F3's other two arms assert FORM too — the uuid arm
# never checks the pane is alive, the session-name arm never checks the registry. Liveness is
# cc-notify's job at SEND time (it distinguishes role-unset / mailbox-only), not a static lint's.
#
# THE ANCHOR IS WHAT PAYS FOR THE WIDENING, and its absence here was a THIRD instance of the bug the
# 2026-08-22 correction above fixed for UUID_REF (backlog bacdfc4f63ab). That correction anchored the
# uuid and session-name rules to the cc-notify ARGUMENT POSITION and left this rule matching `--role
# <name>` ANYWHERE in the payload — so ordinary prose satisfies it. Measured pre-fix:
#     "never use --role desk here; it is the wrong pane"   → GREEN, with no back-channel at all
# Unanchored, widening the token to the class would multiply that false-GREEN across every lowercase
# word ("use --role instead"). Anchored to a role-consuming SENDER's argument position, prose cannot
# reach it and the widening is free. The senders are the ones that actually resolve a role
# (cc-roles' own header names them); the cc-roles/<role> PATH form needs no anchor — its literal
# prefix is already specific. Measured over every real payload on this box: 174 payloads, 112 green /
# 62 red BEFORE and AFTER, 0 GREEN→RED — no false-RED bought by the anchor.
ROLE_REF='cc-roles/[a-z][a-z0-9-]*|(cc-notify|cc-announce|cc-await-ping)([[:space:]]+--[A-Za-z-]+)*[[:space:]]+--role[[:space:]=]+"?[a-z][a-z0-9-]*'
# KITTY SESSION NAME (2026-08-08) — the third resolvable target, and its absence was a REAL refusal,
# not a theoretical gap. iTerm2 pane ids are uuids; KITTY pane ids are BARE INTEGERS
# ($KITTY_WINDOW_ID), and kitty-setup.sh exports a synthetic $ITERM_SESSION_ID of the form `w0t0p0:776`
# whose "uuid" half is just that integer. F3 accepted ONLY a uuid or a hardcoded role, so a
# back-channel addressed to a kitty pane went RED-with-intent and `payload_lint_gate … enforce`
# ABORTED THE FIRE (exit 4) — and a refused fire is not inert: it runs fire_cleanup, which removes the
# worktree and deletes the branch.
# Anchored to the cc-notify ARGUMENT position, never a bare token anywhere in the prose. Optional
# quotes cover `cc-notify "wt-foo-776"`.
#
# 🚨 IT IS THE REGISTRY *NAME*, NOT THE BARE PANE ID — corrected hours after the first version of
# this rule, which accepted `cc-notify 776` and was WRONG. Measured on this kitty box:
#     cc-notify 776 …                     → verdict=unresolvable  reason=no-such-target
#     cc-notify wt-cc-005655-99631-776 …  → verdict=delivered
# cc-notify resolves --role → FRIENDLY NAME (exact, from cc-registry) → raw pane UUID; a bare integer
# is none of the three. So F3's original uuid-only rule was INADVERTENTLY CORRECT on kitty — it
# refused precisely because the address could not be delivered — and widening it to bare integers
# turned a loud refusal into a payload that passes the gate carrying a dead address. That is strictly
# worse: the successor completes, announces into nothing, and the silence looks like success.
# The registry-name shape is `<slug>-<paneid>` (wt-cc-005655-99631-776, claude-infrastructure-700),
# so it must end in `-<digits>`; `100 req/min` and a bare `776` both fail it.
SESSION_NAME_REF='cc-notify[[:space:]]+"?[A-Za-z][A-Za-z0-9._-]*-[0-9]+"?([[:space:]]|$)'

lint_file() {
  local pf="$1"
  [ -n "$pf" ] && [ -f "$pf" ] && [ -s "$pf" ] || { echo "payload-lint: CANNOT DETERMINE — no readable payload '$pf'"; return 2; }
  local fail=0 has_cc has_uuid has_role has_pane presc
  grep -qE 'cc-notify'   "$pf" && has_cc=1   || has_cc=0
  grep -qE "$UUID_REF"   "$pf" && has_uuid=1 || has_uuid=0
  grep -qE "$ROLE_REF"   "$pf" && has_role=1 || has_role=0
  grep -qE "$SESSION_NAME_REF" "$pf" && has_pane=1 || has_pane=0
  # F3 — the back-channel block: a cc-notify reference AND a resolvable target — a full desk uuid,
  # role-indirection (cc-roles/<role> | --role <role>, the P0-15 form that follows a recycled desk),
  # or a registry SESSION NAME in the cc-notify argument position (see SESSION_NAME_REF).
  # Missing the reference, or having it with NO resolvable target → RED (a successor cannot announce).
  if [ "$has_cc" = 0 ] || { [ "$has_uuid" = 0 ] && [ "$has_role" = 0 ] && [ "$has_pane" = 0 ]; }; then
    echo "  RED  F3   BACK-CHANNEL BLOCK missing — cc-notify: $([ "$has_cc" = 1 ] && echo present || echo ABSENT); resolvable target (desk full-uuid OR role-indirection cc-roles/<role>|--role OR kitty session name): $({ [ "$has_uuid" = 1 ] || [ "$has_role" = 1 ] || [ "$has_pane" = 1 ]; } && echo present || echo ABSENT). A successor cannot announce (the W5 root)."
    fail=1
  fi
  # F3/a — a PRESCRIPTIVE terminal-announce via SendMessage (a prohibition is filtered out by NEGATION).
  presc="$(grep -nE "$SENDMSG" "$pf" 2>/dev/null | grep -iE "$ANN" | grep -ivE "$NEGATION" || true)"
  if [ -n "$presc" ]; then
    echo "  RED  F3/a a terminal-announce via SendMessage (teammate-scope → UNRESOLVABLE for the desk; the W5 degrade):"
    printf '           %s\n' "$presc"
    fail=1
  fi
  [ "$fail" -eq 0 ] && { echo "  OK   F3   back-channel block present (cc-notify + $(if [ "$has_uuid" = 1 ]; then echo 'desk full-uuid'; elif [ "$has_role" = 1 ]; then echo 'role-indirection cc-roles/<role>'; else echo 'kitty session name'; fi)); no SendMessage terminal-announce"; return 0; }
  return 1
}

# ── --selftest: SEE F3 fire. RED on a block-less payload AND on a SendMessage terminal-announce; GREEN on a
# well-formed one (a prohibition line must NOT false-RED — the prescriptive/proscriptive discriminator);
# LOUD on a missing file. Every assertion TRAPS (a bare conditional that does not fail LOUD is dead). ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  DESK='99261468-A46A-498A-AE9B-F39473E5E7AE'

  # (1) MISSING BLOCK — succession instructions but NO cc-notify + NO uuid (the exact W5 drop) → RED.
  cat >"$d/missing.txt" <<EOF
SUCCESSOR FIRE — continue the build from the registered gate. Reload the plan, run
the gate unpiped, build the next artifact, ship at a green boundary.
(No back-channel block — exactly the W5 drop.)
EOF

  # (2) PRESENT BLOCK — carries the cc-notify line + the desk full-uuid, and a PROHIBITION line that must
  #     NOT false-RED (the prescriptive-vs-proscriptive discriminator) → GREEN.
  cat >"$d/present.txt" <<EOF
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: announce to the desk ONLY via cc-notify $DESK, VERIFIED (submit-confirmed).
NEVER SendMessage — the desk is NOT a teammate (SendMessage silently degrades to disk-truth).
EOF

  # (3) SendMessage TERMINAL — has the block (check 1 passes) but PRESCRIBES SendMessage → RED via F3/a only.
  cat >"$d/sendmsg.txt" <<EOF
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: cc-notify $DESK is the desk address.
On ship, announce the ship-witness to the desk via SendMessage.
EOF

  # (4) ROLE-INDIRECTION — cc-notify + a cc-roles/<role> reference, NO literal uuid (the P0-15 sanctioned
  #     form; every /goal fire uses `cc-notify "$(cat ~/.claude/cc-roles/desk)"`). MUST go GREEN, or every
  #     role-driven fire false-REDs and the T-P2-5 pre-fire wiring wrongly BLOCKS the desk's own /goal fires.
  cat >"$d/role.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: announce to the desk via cc-notify "$(cat ~/.claude/cc-roles/desk)", VERIFIED.
NEVER SendMessage — the desk is NOT a teammate.
EOF

  # (4b) A ROLE OUTSIDE THE OLD THREE-NAME LIST — the case backlog f1a51344cb84 measured. `drain-lead`
  #      read LIVE 102 while `desk` and `operator` had no role file at all, yet this payload aborted
  #      F3 twice with "resolvable target: ABSENT". cc-roles imposes no name validation and cc-notify
  #      --role is name-agnostic, so a role is a role. MUST go GREEN.
  cat >"$d/role-other.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: on completion, cc-notify --role drain-lead "HANDOFF-PING: <rows closed, sha landed>".
NEVER SendMessage — the lead is NOT a teammate.
EOF

  # (4c) PROSE MENTIONING --role, NOT IN A SENDER'S ARGUMENT POSITION — the false-GREEN the old
  #      UNANCHORED rule bought, and the one that would multiply if the token were widened without
  #      anchoring: this payload has NO addressable back-channel, yet `--role desk` anywhere in it
  #      satisfied F3. Same class as the uuid rule's 2026-08-22 anchoring (bacdfc4f63ab). MUST be RED.
  #      🚨 IT MUST MENTION cc-notify. F3 is an ORDERED pair of conditions and `has_cc` is the FIRST:
  #      a fixture with no cc-notify at all REDs on that, not on the role arm, and credits this
  #      anchor with nothing — the first draft of this case did exactly that and passed against a
  #      mutant with the anchor deleted (method: the vacuity lives one level below the assertion).
  #      So cc-notify is present and UNADDRESSED, and the only --role is in prose.
  cat >"$d/role-prose.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
Addressing note: cc-notify is available on this box, but never use --role desk here — it is the
wrong pane, and --role indirection in general is not how this wave reports.
EOF

  # (5) KITTY SESSION NAME — cc-notify + the registry name, no uuid, no role. This is what
  #     handoff-fire.sh's --notify-back trailer emits on a kitty box, and what cc-notify actually
  #     resolves (verdict=delivered). MUST go GREEN.
  cat >"$d/paneid.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: ping the originator via cc-notify wt-cc-005655-99631-776 "HANDOFF-PING w6: <status>".
NEVER SendMessage — the originator is NOT a teammate.
EOF

  # (5b) BARE PANE ID — the shape this lint wrongly accepted for a few hours on 2026-08-08. cc-notify
  #      resolves --role → friendly NAME → raw pane UUID; a bare integer is none of the three:
  #      `cc-notify 776 …` → verdict=unresolvable. A payload carrying it passes no useful gate — the
  #      successor announces into nothing and the silence reads as success. MUST stay RED.
  cat >"$d/bareint.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: ping the originator via cc-notify 776 "HANDOFF-PING w6: <status>".
EOF

  # (5c) THE LAUNDERED BARE PANE ID — (5b) with a uuid added in UNRELATED PROSE, which is what every
  #      real fire payload carries (a predecessor session id, a plan ref, a cited pane). Until
  #      2026-08-22 the uuid rule matched a bare token ANYWHERE, so this went GREEN while its actual
  #      back-channel `cc-notify 776` is verdict=unresolvable — the W5 root reached THROUGH a green
  #      F3 (backlog bacdfc4f63ab). (5b) only stayed RED because it happens to contain no uuid at
  #      all; one line of ordinary prose made it vacuous. MUST stay RED.
  cat >"$d/bareint-laundered.txt" <<EOF
SUCCESSOR FIRE — continue the build.
Context: the predecessor session was $DESK (read its transcript for the rejected approaches).
BACK-CHANNEL: ping the originator via cc-notify 776 "HANDOFF-PING w6: <status>".
EOF

  # (5d) PREFIXED FORM — \`w0t0p0:<uuid>\` is \$ITERM_SESSION_ID verbatim, and it is NOT deliverable:
  #      cc-notify's resolver rejects it at every arm (the ':' fails the safe-filename gate, and both
  #      uuid arms are ^...\$-anchored), so it returns no-such-target. handoff-fire.sh normalizes it
  #      off with \${BACK_SID##*:} before use for exactly this reason. An AUTHORED payload gets no
  #      such normalization, and the old unanchored rule passed it on the uuid SUBSTRING after the
  #      colon — the same substring bug handoff-fire.sh:7926 names. MUST stay RED.
  cat >"$d/prefixed.txt" <<EOF
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: ping the originator via cc-notify w0t0p0:$DESK "HANDOFF-PING w6: <status>".
EOF

  # (6) PROSE INTEGER — a number that is NOT a cc-notify target must NOT satisfy F3, or the widening
  #     above would turn "100 req/min" in an ordinary brief into a fake back-channel. MUST stay RED.
  cat >"$d/prose-int.txt" <<'EOF'
SUCCESSOR FIRE — continue the build.
The push endpoint is rate limited to 100 req/min per user; cc-notify exists but is unaddressed here.
EOF

  fails=0
  expect() { # <file> <want-rc> <label>  — capture the code directly (no `[ $? ]`, per SC2181)
    lint_file "$1" >/dev/null 2>&1; local got=$?
    [ "$got" -eq "$2" ] || { echo "SELFTEST FAIL: $3 (got $got, want $2)"; fails=1; }
  }
  expect "$d/missing.txt" 1 "block-less payload did not go RED"
  expect "$d/present.txt" 0 "well-formed payload did not go GREEN (a prohibition false-RED'd?)"
  expect "$d/sendmsg.txt" 1 "a SendMessage terminal-announce did not go RED"
  expect "$d/role.txt"    0 "role-indirection payload (cc-notify + cc-roles/<role>, no uuid) did not go GREEN"
  expect "$d/role-other.txt" 0 "a role OUTSIDE the old desk|operator|orchestrator list (cc-notify --role drain-lead, LIVE) wrongly false-RED'd"
  expect "$d/role-prose.txt" 1 "prose mentioning --role, with NO back-channel, wrongly satisfied F3 (the unanchored-rule false-GREEN)"
  expect "$d/absent.txt"  2 "a missing file did not exit 2 (LOUD)"
  expect "$d/paneid.txt"  0 "kitty session-name back-channel (cc-notify <registry name>) did not go GREEN"
  expect "$d/bareint.txt" 1 "a BARE pane id (cc-notify 776 — verdict=unresolvable) wrongly satisfied F3"
  expect "$d/prose-int.txt" 1 "a prose integer (not a cc-notify target) wrongly satisfied F3"
  expect "$d/bareint-laundered.txt" 1 "a bare pane id LAUNDERED by an unrelated prose uuid wrongly satisfied F3"
  expect "$d/prefixed.txt" 1 "a w0t0p0:-prefixed address (no-such-target) wrongly satisfied F3 on its uuid substring"
  if [ "$fails" -eq 0 ]; then
    echo "payload-lint --selftest: 12/12 — RED on a block-less payload, RED on a SendMessage terminal-announce, GREEN on a well-formed one (uuid), on role-indirection (cc-roles/<role>; prohibition tolerated), on a role OUTSIDE the old three-name list (--role drain-lead) AND on a kitty session NAME; RED on a bare pane id (undeliverable), on a prose integer, on a bare pane id laundered by a prose uuid, on a w0t0p0:-prefixed address, and on prose merely mentioning --role with no back-channel; LOUD on missing."
    exit 0
  fi
  echo "payload-lint --selftest: FAILED — the lint does not discriminate (do not trust F3)."
  exit 1
fi

lint_file "${1:-}"
exit $?
