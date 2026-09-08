#!/usr/bin/env bats
# hooks/lib/pane-modal.sh — the modal enumeration shared by bin/cc-spawn-verify (exit 4 WEDGED) and
# scripts/handoff-fire.sh (verify_engagement → 4).
#
# THE TWO THINGS THIS SUITE EXISTS FOR, and they pull in opposite directions:
#
#   1. A FALSE POSITIVE is the failure this class has actually shipped. Prior art cfdd9fc3 reported a
#      healthy agent BLOCKED because it was grepping this repo and had `[nyae]` — quoted inside
#      handoff-fire.sh's own comment — on screen. A pane can DISPLAY a modal's text without BEING at
#      one, and in a fleet whose agents read the plan documenting these modals that is the common
#      case. Hence header AND option, and hence the prose-quoting tests below.
#   2. A STALE FRAGMENT is the failure this class fails SILENTLY on. cfdd9fc3 matched `Do you trust
#      the files in this folder`, a string that does not exist in the shipping binary — an inert
#      matcher that nothing could have reported. Hence the binary-anchor arm, which reads the
#      fragments OUT OF THE LIB rather than restating them, so a class added tomorrow is pinned
#      tomorrow without anyone remembering to extend this file.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/pane-modal.sh"
  # M11 — the environment is PINNED, not ambient. The patterns are env seams, so an inherited value
  # would silently replace the subject with itself.
  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
  unset CC_MODAL_PERM_HEADER CC_MODAL_PERM_OPTION
  # The anti-rot arm at the bottom is the ONE thing here that reads outside the fixture, and it must:
  # its entire subject is whether the vendor binary INSTALLED ON THIS BOX still contains the strings
  # we match. Captured explicitly before $HOME is fixtured, so the reach is named rather than
  # inherited — every other read below is hermetic, and nothing here writes outside $BATS_TEST_TMPDIR.
  REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # shellcheck source=../hooks/lib/pane-modal.sh
  . "$LIB"
}

# The two dialogs as they actually render — header, blurb, then the numbered options.
mcp_screen() {
  cat <<'EOF'
╭──────────────────────────────────────────────────────────────╮
│ New MCP server found in this project: ms365                  │
│                                                              │
│ 1. Use this MCP server                                       │
│ 2. Use this and all future MCP servers in this project       │
│ 3. Continue without using this MCP server                    │
╰──────────────────────────────────────────────────────────────╯
EOF
}

trust_screen() {
  cat <<'EOF'
╭──────────────────────────────────────────────────────────────╮
│ Accessing workspace: /Users/chrisren/Development/personal    │
│                                                              │
│ Quick safety check: Is this a project you created or one you │
│ trust? (Like your own code, a well-known open source project)│
│                                                              │
│ 1. Yes, I trust this folder                                  │
│ 2. No, continue without these permissions                    │
│ 3. No, exit                                                  │
╰──────────────────────────────────────────────────────────────╯
EOF
}

# The tool-permission dialog in its two measured forms (backlog 8ea3acef7d64, and
# docs/plans/BACKLOG_ZERO_2026-09-04.md §4 16:40Z, which recorded both on live fired panes).
# HOOK FORM — a PreToolUse hook returned permissionDecision:"ask". The two lines above the question
# are the binary's reasonString and configString; they are rendered here because that is what the
# operator actually saw, and NOT matched, because both carry a variable prefix that the column-0
# anchor refuses and neither is a contiguous literal the anti-rot arm could pin.
hook_ask_screen() {
  cat <<'EOF'
╭──────────────────────────────────────────────────────────────╮
│ Bash command                                                 │
│                                                              │
│ rm -rf /Users/chrisren/Development/.worktrees/wt-drain-3     │
│                                                              │
│ Hook PreToolUse:Bash requires confirmation for this command  │
│ [settings]                                                   │
│ settings.json to update hooks                                │
│                                                              │
│ Do you want to proceed?                                      │
│ 1. Yes                                                       │
│ 2. No, and tell Claude what to do differently (esc)          │
╰──────────────────────────────────────────────────────────────╯
EOF
}

# ALLOWLIST FORM — no hook involved, so no configString line at all. Pane 297 sat 20-50 min on
# exactly this for `find-plan.sh --status`. Same inertness, same INC-4 hazard, same class.
perm_ask_screen() {
  cat <<'EOF'
╭──────────────────────────────────────────────────────────────╮
│ Bash command                                                 │
│                                                              │
│ scripts/find-plan.sh --status                                │
│                                                              │
│ Do you want to proceed?                                      │
│ 1. Yes                                                       │
│ 2. Yes, and don't ask again for find-plan.sh commands        │
│ 3. No, and tell Claude what to do differently (esc)          │
╰──────────────────────────────────────────────────────────────╯
EOF
}

# The subject is `pane_modal_reason`, which reads stdin. `run` executes in the bats shell, where
# setup() has already sourced the lib, so this needs no sub-shell and no re-quoting of screen text.
classify() { printf '%s\n' "$1" | pane_modal_reason; }

# ---- TRUE POSITIVES: the two dialogs that block a spawned pane ---------------------------------

@test "the MCP-approval dialog is named" {
  run classify "$(mcp_screen)"
  [ "$status" -eq 0 ] || false
  [ "$output" = "mcp-trust-modal" ] || false
}

@test "the workspace-trust dialog is named" {
  run classify "$(trust_screen)"
  [ "$status" -eq 0 ] || false
  [ "$output" = "workspace-trust-modal" ] || false
}

# ---- TRUE NEGATIVES: the false-BLOCKED class that has actually shipped -------------------------

@test "REGRESSION: a pane QUOTING a dialog's header in prose is NOT wedged" {
  # The live shape of cfdd9fc3's defect, transposed: an agent reading plan §9.2, whose text names
  # the header verbatim. One line of prose must never satisfy a two-part rule.
  run classify "Each spawned session renders New MCP server found in this project and BLOCKS there.
Disk state, read live (the cause):"
  [ "$status" -eq 1 ] || false
  [ -z "$output" ] || false
}

@test "REGRESSION: a pane quoting an OPTION alone is NOT wedged" {
  # The mirror image, and it needs its own arm: a rule that required only the option would pass the
  # header test above while still convicting every agent that quotes a menu line.
  run classify "the operator answered 1. Use this MCP server, which is session-scoped"
  [ "$status" -eq 1 ] || false
}

@test "RED-PROOF: prose carrying BOTH halves is still not a modal — the anchor is what refuses it" {
  # The conjunction alone does NOT cover this, and finding that out is what put the anchor in the
  # lib: two ordinary sentences from the plan, one naming the header and one quoting an option, sat
  # on one screen and satisfied header-AND-option between them. A fleet whose agents read that plan
  # produces this screen routinely.
  run classify "§9.2 — each spawned session renders New MCP server found in this project and BLOCKS
the operator answered 1. Use this MCP server, which is session-scoped and persists nothing"
  [ "$status" -eq 1 ] || false
}

@test "POSITIVE CONTROL: unanchored, that same prose fires — so the anchor is load-bearing" {
  # Without this the test above is unfalsifiable-looking. `.*` re-permits a mid-line match, which is
  # precisely what removing the anchor would do.
  CC_MODAL_MCP_HEADER=".*New MCP server found"
  CC_MODAL_MCP_OPTION=".*Use this MCP server"
  run classify "§9.2 — each spawned session renders New MCP server found in this project and BLOCKS
the operator answered 1. Use this MCP server, which is session-scoped and persists nothing"
  [ "$status" -eq 0 ] || false
  [ "$output" = "mcp-trust-modal" ] || false
}

@test "the anchor tolerates box chrome, a selection marker and a menu index — and no index at all" {
  # It must survive every render the dialog can take. Requiring the index would go INERT the day a
  # dialog sets hideIndexes; requiring the box would go inert without one.
  run classify "╭─ New MCP server found in this project: ms365 ─╮
❯ 1. Use this MCP server"
  [ "$status" -eq 0 ] || false
  run classify "New MCP server found in this project: ms365
Use this MCP server"
  [ "$status" -eq 0 ] || false
}

@test "REGRESSION: a trust OPTION quoted without its header is NOT wedged" {
  run classify "CC_MODAL_TRUST_OPTION default is Yes, I trust this folder"
  [ "$status" -eq 1 ] || false
}

@test "a rendered HEADER with no options is not a modal — a heading is not a dialog" {
  # What the conjunction buys once the anchor is in place, arm 1. This is an ordinary line in a doc,
  # a log, or a `grep` result: at column 0, exactly the dialog's own wording, and no menu. Under a
  # header-only rule every pane that ever printed this sentence reads as wedged.
  run classify "New MCP server found in this project: ms365
(that is what §9.2 measured — the pane then blocked)"
  [ "$status" -eq 1 ] || false
}

@test "a rendered OPTION LIST with no header is not a modal" {
  # Arm 2, and the realistic shape: a markdown numbered list quoting the choices — which is how the
  # plan's own §9.2 renders them — puts every option at column 0 with its index intact.
  run classify "1. Use this MCP server
2. Use this and all future MCP servers in this project
3. Continue without using this MCP server"
  [ "$status" -eq 1 ] || false
}

@test "the two dialogs do not cross-satisfy: MCP header + TRUST option is neither" {
  # Conjunction must be per-class. A flattened "any header AND any option" rule would call this a
  # modal, and it is the shape a pane reading BOTH sections of the plan actually produces.
  run classify "New MCP server found in this project
1. Yes, I trust this folder"
  [ "$status" -eq 1 ] || false
}

@test "a busy agent's ordinary screen is not a modal" {
  run classify "⏺ Clauding… (9m 14s · 32.6k tokens)
? for shortcuts"
  [ "$status" -eq 1 ] || false
}

@test "an unreadable pane fails CLOSED to not-wedged, never to wedged" {
  run classify ""
  [ "$status" -eq 1 ] || false
}

# ---- THE THIRD CLASS: the tool-permission prompt (backlog 8ea3acef7d64) ------------------------
#
# RED-PROOF. Both arms fail against the pre-fix lib, which enumerated only the MCP and workspace
# -trust dialogs: `pane_modal_reason` returned 1, `pane_wedge_reason` therefore returned 1, and
# `verify_engagement` fell through its WEDGED gate into the INC-4 recovery — pasting the whole brief
# into a pane whose dialog eats the paste's bytes as single-key answers. That is the duplicate
# session the row was filed about, so these two cases ARE the row's falsifier.

@test "the hook-raised tool-permission dialog is named" {
  run classify "$(hook_ask_screen)"
  [ "$status" -eq 0 ] || false
  [ "$output" = "tool-permission-modal" ] || false
}

@test "the plain allowlist permission dialog is named — no hook line required" {
  # The class is the DIALOG, not the hook. Requiring the `settings.json to update hooks` line would
  # have gone inert on pane 297's stall, which carried no hook at all.
  run classify "$(perm_ask_screen)"
  [ "$status" -eq 0 ] || false
  [ "$output" = "tool-permission-modal" ] || false
}

@test "REGRESSION: prose quoting the permission question alone is NOT wedged" {
  # The likeliest false positive by a wide margin: this repo's own plan docs quote the question, and
  # an agent reading them puts it on screen at column 0.
  run classify "Every fired session stalled on Do you want to proceed and sat 20-50 min
until this session sent Enter through kitty @ send-text"
  [ "$status" -eq 1 ] || false
}

@test "REGRESSION: prose quoting the refusal OPTION alone is NOT wedged" {
  run classify "the operator chose No, and tell Claude what to do differently rather than approving"
  [ "$status" -eq 1 ] || false
}

@test "RED-PROOF: prose carrying BOTH halves mid-line is still not a modal" {
  # The same anchor argument the MCP class already pays for, re-run on this class rather than
  # assumed to carry over — the two classes have different option lists and different prose habits.
  run classify "§4 measured that panes hang on Do you want to proceed forever
and the operator chose No, and tell Claude what to do differently to clear it"
  [ "$status" -eq 1 ] || false
}

@test "a permission dialog rendered WITHOUT its question is not this class" {
  # Arm 2 of the conjunction, and it is the realistic shape: an options list quoted in a changelog.
  run classify "1. Yes
2. No, and tell Claude what to do differently (esc)"
  [ "$status" -eq 1 ] || false
}

@test "SPECIFIC BEFORE GENERIC: an MCP dialog is still mcp-trust-modal, not tool-permission-modal" {
  # The ordering claim in the lib, made falsifiable. This screen satisfies BOTH conjunctions, and
  # the specific class must win — otherwise adding this class would have silently reclassified
  # every MCP stall and handed the operator the wrong remedy.
  run classify "New MCP server found in this project: ms365
1. Use this MCP server
Do you want to proceed?
2. No, and tell Claude what to do differently (esc)"
  [ "$status" -eq 0 ] || false
  [ "$output" = "mcp-trust-modal" ] || false
}

@test "the permission class carries a remedy that names OUR fix site, not an upstream one" {
  # The row was filed as upstream-and-operator-owned. The remedy line is where that refutation has
  # to land, because it is the only part of this a reader sees at 3am.
  run pane_modal_remedy tool-permission-modal
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'validate-bash.sh' || false
  echo "$output" | grep -q 'permissionDecision:ask' || false
}

# ---- THE PATTERNS ARE SEAMS (a wording change is a one-line override, not a redeploy) ----------

@test "an env override replaces a pattern rather than adding to it" {
  CC_MODAL_MCP_HEADER="Totally New Dialog"
  CC_MODAL_MCP_OPTION="press 1 to continue"
  run classify "Totally New Dialog
press 1 to continue"
  [ "$status" -eq 0 ] || false
  [ "$output" = "mcp-trust-modal" ] || false
  # …and the replaced default no longer matches, which is what makes it a REPLACEMENT.
  run classify "$(mcp_screen)"
  [ "$status" -eq 1 ] || false
}

@test "every slug carries a remedy, and an unknown slug still yields one" {
  run pane_modal_remedy mcp-trust-modal
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'enabledMcpjsonServers' || false
  run pane_modal_remedy some-future-modal
  [ "$status" -eq 0 ] || false
  [ -n "$output" ] || false
}

# ---- THE ANTI-ROT ANCHOR: do these strings still exist in the binary we are matching? ----------
#
# The fragments are read OUT OF THE LIB, so this arm covers whatever the enumeration currently says
# — a control keyed to the mechanism rather than to a copy of its values (which would decay in
# lockstep with the thing it audits and never go red).

# THE NEWEST INSTALLED TRACK, and the rule was set by a false RED on this test's first run.
# Six Claude Code tracks are installed side by side on this box (.claude-156 … .claude-220) and a
# plain `$HOME/.claude-*` glob returns them in LEXICAL order, so the anchor resolved 2.1.156 — a
# binary nothing launches — and convicted a healthy enumeration. Measured across all six:
# `No, continue without these permissions` is absent from 156/161/170 and present in 183/219/220,
# so the fragment was right and the ORACLE was stale (memory: uniform-error-ratio-indicts-the-model,
# and version-identity-is-the-running-process-not-the-launcher).
#
# Newest wins because the pin only ever moves FORWARD (the repo's own activation scripts walk
# 183 → 219 → 220), so this either IS the binary being launched or is the one about to be. Its
# residual failure mode is the useful direction: a rewording in a not-yet-pinned track reds here
# BEFORE an upgrade makes the matcher inert in production.
#
# CC_MODAL_ANCHOR_BIN overrides for a box that pins otherwise. There is no fixture arm and there
# should not be — this test's entire subject is drift against a vendor binary, and a fixture would
# assert the enumeration against a copy of itself.
claude_binary() {
  local t p n
  if [ -n "${CC_MODAL_ANCHOR_BIN:-}" ]; then
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
  fi
  # A glob, not `ls | sort -rn` — and NUMERICALLY, which is the whole point: the lexical order a
  # plain glob gives is what resolved 2.1.156 over 2.1.220 on this test's first run.
  t=""
  for p in "$REAL_HOME"/.claude-[0-9]*; do
    n="${p##*/.claude-}"
    case "$n" in ''|*[!0-9]*) continue ;; esac     # also catches the unmatched literal glob
    if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi
  done
  [ -n "$t" ] || return 1
  for p in "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
           "$REAL_HOME/.claude-$t/node_modules/@anthropic-ai/claude-code/cli.js"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# Every alternative of every pattern, one per line.
#
# DERIVED, NOT LISTED (2026-09-08). This used to name the four variables literally, which quietly
# contradicted the header's own promise that "a class added tomorrow is pinned tomorrow without
# anyone remembering to extend this file": a fifth variable would have been matched by the lib and
# audited by nothing. `compgen -v` over the CC_MODAL_ prefix reads whatever the sourced lib actually
# defines, so the anchor's population now comes from the subject rather than from a copy of it
# (memory: checker-population-rests-on-an-untested-belief). The `_HEADER|_OPTION` suffix filter
# keeps the enumeration to matchable text and would exclude a future non-pattern knob.
modal_fragments() {
  local v
  for v in $(compgen -v | grep -E '^CC_MODAL_.*_(HEADER|OPTION)$' | sort); do
    printf '%s\n' "${!v}"
  done | tr '|' '\n'
}

@test "ANTI-ROT: every enumerated fragment is present in the shipping claude binary" {
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
  missing=""
  while IFS= read -r frag; do
    [ -n "$frag" ] || continue
    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
  $frag"
  done <<< "$(modal_fragments)"
  if [ -n "$missing" ]; then
    echo "These fragments are NOT in $BIN — the matcher for them is INERT:$missing"
    echo "Claude Code reworded a dialog. Re-read the strings out of the binary and update"
    echo "hooks/lib/pane-modal.sh; do not delete this test to make it green."
    false
  fi
}

@test "ANTI-ROT positive control: the anchor above CAN fail — cfdd9fc3's string is absent" {
  # Without this arm the test above is unfalsifiable-looking: a `grep -qa` that always matched (a
  # bad path, a stray `|| true`) would read exactly the same. This is the mutant — the fragment the
  # unlanded prior art actually shipped, which does NOT exist in the binary and never did on 2.1.220.
  # It also records the finding rather than leaving it as a sentence in a commit message.
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the control cannot run"
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
}
