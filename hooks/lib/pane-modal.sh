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
# A THIRD class joined them on 2026-09-08 — the ordinary tool-permission prompt — on the same
# durability argument rather than as an exception to it; its own block below carries the derivation.
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

# ── THE THIRD CLASS: the ordinary TOOL-PERMISSION dialog (backlog 8ea3acef7d64) ──────────────────
# Added 2026-09-08 after the row's filed premise was read out of the binary and REFUTED. The row
# said fired sessions stall at "a settings.json hooks-update approval modal", filed as an
# undocumented dialog with no supported pre-approval whose fix was upstream and operator-owned.
# There is no such dialog. Read from claude.exe (2.1.220 `mHr`, 2.1.260 `Re`), the observed screen
# decomposes into three parts of the ORDINARY tool-permission prompt raised by a PreToolUse hook
# that returned permissionDecision:"ask":
#
#   reasonString  `Hook ${hookName} requires confirmation for this ${toolType} ${dim("[settings]")}`
#   configString  `${lBS(hookSource)} to update hooks`   — lBS: plugin*→"plugin hooks.json",
#                                                          skill*→"SKILL.md", else "settings.json"
#   question      `Do you want to proceed?`               — AW's default
#
# So "settings.json to update hooks" is the binary telling the operator WHERE THE HOOK IS DECLARED,
# not an approval of a settings change; and the asking hook is OURS. The four `warn` sites in
# hooks/validate-bash.sh and the seven in hooks/curl-gate.py are the emitters. The correlated
# rewrite of five account settings.json files 13:50:44-13:51:31Z that the filing leaned on is a true
# metric beside a wrong cause (memory: wrong-cause-corroborated-by-true-metric).
#
# WHY IT BELONGS IN AN ENUMERATION SCOPED TO "MUST REACH THE OPERATOR". That scope was a DURABILITY
# argument about which dialogs will still be blocking spawns after every suppressible one is
# configured away — not a rule that a suppressible dialog may not be REPORTED. This one satisfies
# the argument on its own terms: an `ask` is unanswerable by anything but a human, so for a fired
# peer with no human watching it is exactly as permanent as workspace trust. Measured
# 2026-09-04 (docs/plans/BACKLOG_ZERO_2026-09-04.md §4, 16:40Z): four fired sessions sat 20-50 min
# each on this dialog — two on the hook form, one on a `rm -r` verify, one on a plain Bash
# permission ask for `find-plan.sh --status`.
#
# AND IT IS THE ROW'S OWN HARM. Unenumerated, verify_engagement fell past its WEDGED gate to the
# INC-4 recovery, which PASTES THE WHOLE BRIEF into a pane whose dialog consumes the paste's bytes
# as single-key answers — the duplicate-session generator the row names. Naming the class returns 4
# instead of 1, which skips the resend, keeps custody open and arms the goal (handoff-fire's
# engage_rc_consequence 4:custody / 4:goal). REPORTING, still: nothing here answers the prompt. A
# sweeper that auto-answered it was built and reverted on that doctrine, and this does not revive it.
#
# THE FRAGMENTS ARE THE QUESTION AND THE REFUSAL OPTION, deliberately, because neither the
# reasonString nor the configString can be matched by this file's rules: both are rendered with a
# variable PREFIX (`Hook …`, `settings.json …`), so the column-0 anchor refuses them, and neither is
# a contiguous literal in the binary, so the anti-rot arm could not pin them. The question and the
# options are both — verified present in 2.1.220 and 2.1.260.
#
# `?` IS OMITTED FROM THE HEADER ON PURPOSE: these are EREs, and `proceed?` would make the `d`
# optional. The rendered line is `Do you want to proceed?`; the fragment is its prefix.
CC_MODAL_PERM_HEADER="${CC_MODAL_PERM_HEADER:-Do you want to proceed}"
CC_MODAL_PERM_OPTION="${CC_MODAL_PERM_OPTION:-No, and tell Claude what to do differently|Deny, and tell Claude what to do differently}"

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
  # LAST, and that ordering is load-bearing rather than incidental: this class's option list is the
  # generic one every dialog in the binary can render, so testing it first would let it claim a
  # screen the two specific classes describe better. Specific-before-generic, one direction only.
  _pane_modal_both "$txt" "$CC_MODAL_PERM_HEADER" "$CC_MODAL_PERM_OPTION" \
    && { printf 'tool-permission-modal'; return 0; }
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
    tool-permission-modal)
      # Names OUR OWN code as the fix site, because it is. The dialog prints its own pointer on the
      # line above the question: `settings.json to update hooks` means a PreToolUse hook returned
      # `ask` (hooks/validate-bash.sh warn(), hooks/curl-gate.py), and its absence means an ordinary
      # allowlist ask. Both are ours to change; neither is an upstream consent boundary.
      printf 'answer the prompt in that pane; this is an ordinary TOOL-PERMISSION ask, not an upstream consent boundary — if the dialog also shows "settings.json to update hooks" the durable fix is the PreToolUse hook that returned permissionDecision:ask (hooks/validate-bash.sh warn(), hooks/curl-gate.py), otherwise a permissions.allow entry; never a keystroke sweeper' ;;
    *)
      printf 'answer the prompt in that pane' ;;
  esac
}

# ── THE EXIT-TIME DIALOG, AND WHY IT IS ENUMERATED HERE BUT NOT IN pane_modal_reason ────────────
# Everything above answers "is this pane stopped on a dialog that MUST reach a human?". This class
# is its exact opposite and shares only the matching machinery: the background-work dialog is
# raised BY a /exit that one of our own rails typed, it is not a consent boundary (every option it
# offers exits), and the operator is the last party who should be woken for it. Folding it into
# pane_modal_reason would hand both WEDGED consumers a verdict whose remedy is "answer it
# yourself" — the opposite of what that verdict means everywhere else — so it gets its own two
# predicates and the enumeration stays in one file, which is the whole reason this file exists.
#
# REPORTER-ONLY IS UNCHANGED HERE. Nothing below sends a keystroke; pane_bgwork_choice only reads
# the menu and says which index the caller would press. The actuation lives at the ONE call site
# that is entitled to it — the recycle watcher in scripts/handoff-fire.sh, which typed the /exit
# that raised this dialog — and the sweeper that was built and reverted on this file's doctrine
# stays reverted.
#
# MEASURED 2026-09-10 on 2.1.260 under a PTY (docs/research/exit-bgwork-dialog-2026-09-10/), three
# arms, the two negative ones present so the reading can be wrong: no background work ⇒ NO dialog
# and /exit exits; a live `run_in_background` shell ⇒ dialog and /exit does NOT exit; the same with
# the keep-work index sent as a single byte ⇒ exits. Rendered verbatim:
#
#     Background work is running
#     The following will stop when you exit:
#
#     shell · sleep 600
#
#     ❯ 1. Exit and stop tasks
#       2. Move to background and exit
#       3. Stay
#
# THE INDEX IS READ, NEVER ASSUMED. `2` is what that menu rendered on 2026-09-10 and is exactly the
# kind of fact this repo keeps being bitten by: a reordering upstream would silently turn a
# hardcoded `2` into "Exit and stop tasks", which KILLS a land that a recycle is usually running.
# So the caller is handed the index parsed off the screen it is about to answer, and an unindexed
# menu (`hideIndexes` is in the binary's own dialog vocabulary) yields rc 1 — no guess.
CC_MODAL_BGWORK_HEADER="${CC_MODAL_BGWORK_HEADER:-Background work is running}"
CC_MODAL_BGWORK_OPTION="${CC_MODAL_BGWORK_OPTION:-Exit and stop tasks|Move to background and exit}"
# The option a rail may choose for itself: it exits (which is all a recycle needs) and does NOT
# stop the tasks (which on this box is usually a land in flight). Not a pattern — an exact label.
CC_MODAL_BGWORK_KEEP="${CC_MODAL_BGWORK_KEEP:-Move to background and exit}"

# pane_bgwork_dialog — stdin = a pane's plain screen text; 0 iff the exit-time dialog is on screen.
# Same header-AND-option conjunction, same column-0-modulo-chrome anchor, same reason: a pane that
# merely DISPLAYS this text (this file, its tests, a commit message) is not a pane sitting at it.
pane_bgwork_dialog() {
  local txt
  txt="$(cat)"
  [ -n "$txt" ] || return 1
  _pane_modal_both "$txt" "$CC_MODAL_BGWORK_HEADER" "$CC_MODAL_BGWORK_OPTION"
}

# pane_bgwork_choice — stdin = the same screen → stdout: the rendered menu index of the KEEP option.
#   rc 0  exactly one line renders that label as a menu row, and it carries an index
#   rc 1  the header is absent, the label is absent, it is unindexed, or two rows claim it
# LC_ALL=C on purpose: the chrome it must eat (`❯`, box rules) is multibyte, and a byte-wise
# character class is what makes `[^[:alnum:]]*` skip it instead of stalling on a partial rune.
pane_bgwork_choice() {
  local txt idx
  txt="$(cat)"
  [ -n "$txt" ] || return 1
  printf '%s\n' "$txt" | grep -qE -- "$(_pane_modal_anchor "$CC_MODAL_BGWORK_HEADER")" || return 1
  idx="$(printf '%s\n' "$txt" | LC_ALL=C awk -v want="$CC_MODAL_BGWORK_KEEP" '
    {
      p = index($0, want)
      if (p == 0) next
      pre = substr($0, 1, p - 1)
      # Everything before the label must be chrome, then the index, then blanks — the anchor rule
      # written as a prefix test. Prose that mentions the label mid-sentence has words in `pre`.
      if (pre !~ /^[^[:alnum:]]*[0-9]+\.[[:space:]]*$/) next
      if (match(pre, /[0-9]+/)) print substr(pre, RSTART, RLENGTH)
    }' | sort -u)"
  [ -n "$idx" ] || return 1
  [ "$(printf '%s\n' "$idx" | wc -l | tr -d ' ')" = 1 ] || return 1   # ambiguous ⇒ no guess
  printf '%s' "$idx"
}
