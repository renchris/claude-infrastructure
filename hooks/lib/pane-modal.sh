# shellcheck shell=bash
# pane-modal.sh — is this pane's visible text a Claude Code modal that will never clear itself?
#
# ── THE STATE THIS NAMES ─────────────────────────────────────────────────────────────────────────
# A session stopped at a startup modal is a live `claude.exe` doing no work. `ps` says healthy, the
# pane looks busy, and no SessionStart hook has fired — so there is no registry row, no telemetry
# row and no transcript to be absent from. It is indistinguishable from a working agent by every
# oracle this fleet had, which is why a 7-way fan-out could report "Spawned successfully" seven
# times and deliver five results (plan §9.1/§9.2, measured 2026-08-03).
#
# That shape is the OPPOSITE of the one both consumers already model. Their existing PARKED verdict
# means *no process, and a pane sitting at a shell that refused the launch* — i.e. never started.
# This one means *started, and stopped*. One vocabulary, two disjoint causes, two disjoint remedies.
#
# ── ONE ENUMERATION, TWO CONSUMERS — WHICH IS WHY IT LIVES HERE AND NOT IN EITHER ────────────────
#   bin/cc-spawn-verify         exit 4 WEDGED   — the agent process exists but is inert on a modal
#   scripts/handoff-fire.sh     verify_engagement → 4, and the INC-4 re-type is SKIPPED
# A screen predicate copied into two files is the standing risk plan §8.3 already names about the
# divert predicate ("now in THREE files"). Enumerated UI strings rot — that is this class's defining
# property, not a hypothetical — so there must be exactly one place a successor edits, and exactly
# one place a test can pin against the shipping binary.
#
# ── THE MATCHING RULE, AND THE INCIDENT THAT SET IT ──────────────────────────────────────────────
# HEADER **AND** AN OPTION, both required. Prior art cfdd9fc3 reported a healthy agent as BLOCKED
# because that agent was grepping this repo and had `[nyae]` — quoted inside handoff-fire.sh's own
# comment — on screen. **A pane can DISPLAY a modal's text without BEING at one**, and in a fleet
# whose agents read the plan documenting these modals that is the common case, not a rare one. Prose
# quotes one line; the rendered modal always carries its header and its options together.
#
# AND EACH HALF IS ANCHORED — see `_pane_modal_anchor` below. The shell-level states (`zsh: correct
# …`, `command not found`) are anchored to column 0 by their consumers, because zsh writes them
# there; a naive `^` here would be inert, because a TUI modal is drawn inside a box. The anchor is
# therefore column 0 MODULO the box chrome and the menu index — the same lesson, translated to the
# subject rather than copied from it.
#
# REPORTER ONLY. Nothing here kills, closes, answers or respawns anything. A false WEDGED costs the
# operator a glance; a false OK costs an agent. Both consumers keep that asymmetry.
#
# ⚠ RESIDUE, NAMED: the anchor keeps this file's own source out of its own jaws (an assignment line
# begins with `CC_MODAL_…`, not with the pattern), but a pane rendering a MOCK of a dialog — this
# repo's test fixtures, a screenshot pasted into a pane — is a rendered dialog by construction and
# will match. That is the accepted floor for a screen oracle, and it is why this stays a reporter.
# Obfuscating the strings would buy a little more precision with a matcher nobody can grep for,
# which is the wrong trade: the enumeration has to be findable precisely so that the day CC rewords
# a dialog, a successor can find it.
#
# ── WHY NOT THE COMPOSER ANCHOR (`? for shortcuts`), WHICH IS THE OBVIOUS BETTER IDEA ────────────
# docs/research/cc-startup-modals-2026-08-04.md §3 measures a POSITIVE anchor 9/9 — present in all 5
# usable runs, absent under all 4 blocking modals — and a positive anchor is class-level: a dialog
# nobody has enumerated yet still cannot render a composer. It is the right predicate **for a
# one-shot startup watchdog**, where "should have reached a composer by now" is a sound claim, and
# that is where it belongs (bin/cc-pane-runner, per that doc).
#
# It is the WRONG predicate for an any-time verdict, in both directions:
#   · as a POSITIVE test — a healthy agent mid-turn is not at a composer either, so "no composer"
#     would report WEDGED for every busy agent in the fleet. An alarm that fires on the normal state
#     carries no bits (memory: alarm-polarity-and-attention-budget).
#   · as a NEGATIVE veto over this matcher — tempting, because it can only ever REMOVE a false
#     WEDGED. But a modal opening mid-session leaves the earlier composer line in the scrollback, so
#     the veto would fire on a genuinely wedged pane. That trades a glance for an agent, which is
#     exactly the asymmetry this file is built around. Rejected on that ground, not on cost.
#
# ── INPUT CONTRACT ───────────────────────────────────────────────────────────────────────────────
# Plain screen text, as `kitty @ get-text` returns it WITHOUT `--ansi`. Measured on this box
# 2026-08-09 on a live CC TUI pane: plain `get-text` → 0 lines containing ESC; the same read with
# `--ansi` → 36. Both consumers read plainly (bin/it2-kitty:806 `read)` and cc-spawn-verify's own
# `parked_evidence` already depend on that). A caller that ever passes `--ansi` must strip SGR
# first — an escape landing mid-phrase defeats a line grep silently, in the expensive direction.
#
# ── THE ENUMERATION (verbatim from claude.exe 2.1.220, read 2026-08-09 — never invented) ─────────
# Only the MUST-REACH-OPERATOR dialogs are listed, and that is a durability argument rather than a
# scope cut: docs/research/cc-startup-modals-2026-08-04.md §1 classifies workspace-trust and MCP
# approval as boundaries that may never be suppressed, so they are the two that will still be
# blocking spawns after every suppressible dialog has been configured away. The cosmetic class
# (fullscreen upsell, theme picker) is already shut by `tui:"default"` in every account home and is
# actively being deleted — enumerating a moving target the repo is removing buys nothing.
#
# Fragments are kept SHORT ON PURPOSE. Screen text wraps at the pane's width, and a split pane can
# be narrow; `New MCP server found in this project` is 36 characters and would break across a wrap,
# `New MCP server found` is 20 and does not. Each fragment is still unique in the binary.
#
# STALENESS IS THE FAILURE MODE, so it is pinned rather than trusted: tests/pane-modal.bats greps
# every fragment below out of the live claude binary. cfdd9fc3 matched `Do you trust the files in
# this folder` — a string that does NOT exist in 2.1.220 (checked both spellings). That matcher had
# been inert for an unknown span and nothing could have said so.
#
# Every pattern is an env seam so a wording change is a one-line override, not a redeploy.

# ERE, not fixed strings — the option lists are alternations. Keep them free of regex metacharacters
# so an override written by hand behaves the way its author reads it.
CC_MODAL_MCP_HEADER="${CC_MODAL_MCP_HEADER:-New MCP server found}"
CC_MODAL_MCP_OPTION="${CC_MODAL_MCP_OPTION:-Use this MCP server|Use this and all future MCP servers|Continue without using this MCP server}"
CC_MODAL_TRUST_HEADER="${CC_MODAL_TRUST_HEADER:-Accessing workspace:|Quick safety check:}"
CC_MODAL_TRUST_OPTION="${CC_MODAL_TRUST_OPTION:-Yes, I trust this folder|No, continue without these permissions}"

# ANCHORED TO COLUMN 0 MODULO BOX CHROME — the TUI translation of the shell states' `^` anchor, and
# the thing that makes the conjunction above actually bite. `[^[:alnum:]]*` eats a leading `│`, a
# `╭─`, a selection `❯`, and any padding; `([0-9]+\.)?` eats the rendered menu index. A modal always
# renders its header and its options as the LINE, so it survives. Prose does not: "the operator
# answered 1. Use this MCP server, which is session-scoped" begins with a letter, so the anchor
# refuses it — while an unanchored match reads it as a menu.
#
# This is what closed the residue the header/option conjunction alone left open. Measured while
# writing the tests: two lines of ordinary plan prose — one naming the header, one quoting an option
# mid-sentence — satisfied an unanchored conjunction between them. A fleet whose agents read the
# plan documenting these dialogs produces exactly that screen, which is how prior art cfdd9fc3
# convicted a healthy agent in the first place.
#
# It deliberately does NOT require the index: `hideIndexes` exists in the binary's own dialog
# vocabulary, so a dialog that renders its options unnumbered must still match. A rule that could go
# INERT on a rendering flag would fail in the expensive direction.
_pane_modal_anchor() { printf '^[^[:alnum:]]*([0-9]+\.)?[[:space:]]*(%s)' "$1"; }

# _pane_modal_both <text> <header-ERE> <option-ERE> → 0 iff BOTH are on screen, each as its own line.
# Two greps rather than one combined pattern: "header and option" is a conjunction, and expressing a
# conjunction as one regex over a multi-line buffer requires them to share a line, which they never do.
_pane_modal_both() {
  printf '%s\n' "$1" | grep -qE -- "$(_pane_modal_anchor "$2")" || return 1
  printf '%s\n' "$1" | grep -qE -- "$(_pane_modal_anchor "$3")"
}

# pane_modal_reason — stdin = a pane's plain screen text
#   stdout: a stable slug naming the modal          exit 0 — a blocking modal is on screen
#   stdout: nothing                                 exit 1 — no enumerated modal (the common case)
#
# Fails CLOSED to "not a modal" on empty input, so an unreadable screen can never manufacture a
# WEDGED verdict. Both consumers already treat an unreadable pane as a non-answer; this keeps that
# true rather than restating it in two places.
pane_modal_reason() {
  local txt
  txt="$(cat)"
  [ -n "$txt" ] || return 1
  _pane_modal_both "$txt" "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    && { printf 'mcp-trust-modal'; return 0; }
  _pane_modal_both "$txt" "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" \
    && { printf 'workspace-trust-modal'; return 0; }
  return 1
}

# pane_modal_remedy <slug> → the one line a caller prints under a WEDGED verdict.
# Lives beside the enumeration so a new class cannot ship with a diagnosis and no remedy — the
# operator's next action is the only part of this that is worth reporting at all.
pane_modal_remedy() {
  case "${1:-}" in
    mcp-trust-modal)
      printf 'answer the prompt in that pane; the durable fix is enabledMcpjsonServers in the PROJECT .claude/settings.json (never a hand-edit of .claude.json, which every running session rewrites)' ;;
    workspace-trust-modal)
      printf 'answer the prompt in that pane; trust is a security boundary and is deliberately not pre-seedable except for a realpath this box itself created' ;;
    *)
      printf 'answer the prompt in that pane' ;;
  esac
}
