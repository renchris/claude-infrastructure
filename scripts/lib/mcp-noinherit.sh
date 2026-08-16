#!/usr/bin/env bash
# cc_mcp_noinherit_args — compose the CLI flags that keep a spawned worker OUT of a repo's
# project-scope `.mcp.json` stdio servers, without touching anything else about that session.
#
# WHY THIS EXISTS (backlog eece54939e7f · W3 of docs/plans/MCP_MEMORY_100P_IMPLEMENTATION.md).
# Measured on 2.1.220, 2026-08-11 (see tests/mcp-no-inherit.bats and 04-spawn-semantics.md):
#   · a `-p`/headless/SDK worker loads EVERY stdio server in the cwd's `.mcp.json` unconditionally —
#     the approval list is not consulted at all in that mode (04 Runs E/E2), so a fired research
#     session in a repo carrying chrome-devtools pays 312 MB it never asked for;
#   · an interactive session in the same repo loads them once approved.
# The fleet had NO control for this anywhere: `--strict-mcp-config`, `--setting-sources` and
# `disabledMcpjsonServers` appeared in zero scripts before this file.
#
# WHY `--strict-mcp-config` PLUS A PASSTHROUGH, and not either flag alone. Three candidates were
# measured against one fake stdio server in a project `.mcp.json` and the account's real user-scope
# http servers (motion, motion-plus):
#
#   flag                            project stdio    user-scope http    project settings/hooks
#   ────────────────────────────────────────────────────────────────────────────────────────────
#   (none)                          STARTED          connected          loaded
#   --setting-sources user,local    not loaded       connected          *** DROPPED ***
#   --strict-mcp-config             not loaded       *** DROPPED ***    loaded
#   --strict-mcp-config
#     + --mcp-config <passthrough>  not loaded       connected          loaded      ← what we compose
#
# `--setting-sources` excluding project is the form the plan first proposed, and it is the one form
# that must NOT be used: reso's `.claude/settings.json` and `.claude/settings.local.json` both carry
# `hooks` and `permissions`, so excluding the project source silently disarms a repo's own hooks in
# every fired session — a blast radius orders of magnitude wider than the MCP question. Bare
# `--strict-mcp-config` is MCP-scoped but over-wide in the other direction: it empties the server
# list entirely, taking the USER-scope http servers with it. Those are the servers W3's constraint
# explicitly protects — an http server holds no local process, so blocking it saves nothing and only
# removes a capability. Re-adding them through `--mcp-config` is what makes the control surgical.
#
# NOT A TEAMMATE CONTROL. An `Agent({name})` teammate is a separate `claude.exe --agent-id` process
# that bootstraps MCP from its cwd (measured: the fake server's parent pid WAS the teammate), but the
# parent composes its launch argv from an enumerated flag set — agent identity, --permission-mode,
# --effort, --model — with no MCP flag in it (read from the 2.1.220 binary). So nothing composed here
# can reach a teammate. The only control that does is `disabledMcpjsonServers` in the scope's
# settings, which blocks by name in every mode.

# cc_mcp_noinherit_args CONFIG_DIR [BRIEF_FILE]
#   CONFIG_DIR  the TARGET account's config dir (its user-scope servers are what we preserve).
#   BRIEF_FILE  optional; when it declares MCP/browser work the control DISARMS itself.
# Sets TWO globals — CC_MCP_NOINHERIT_ARGS (the flags to append, possibly empty) and
# CC_MCP_NOINHERIT_REASON (the one line a caller prints). It deliberately returns them as globals
# rather than on stdout: `X=$(cc_mcp_noinherit_args …)` runs the function in a SUBSHELL, so the
# reason set inside it never reaches the caller and the decision renders blank. That is not
# hypothetical — it is how the first wiring of this shipped into a dry run reading
# `mcp: (undecided)`, with the flags correctly composed and the explanation silently lost.
# shellcheck disable=SC2034  # CC_MCP_NOINHERIT_ARGS/REASON are the RETURN VALUES — read by the caller.
cc_mcp_noinherit_args() {
  local cfg="${1:-}" brief="${2:-}"
  CC_MCP_NOINHERIT_REASON=""
  CC_MCP_NOINHERIT_ARGS=""

  if [ "${CC_MCP_NOINHERIT:-on}" = off ]; then
    CC_MCP_NOINHERIT_REASON="disabled by CC_MCP_NOINHERIT=off"
    return 0
  fi

  # FAIL OPEN on a brief that declares the work. A fire whose brief names an MCP tool or a browser
  # server needs those servers, and a control that silently breaks the work it was fired to do is
  # worse than the memory it saves. The markers are deliberately NAMES, not the word "browser" or
  # "mcp" — this very repo's briefs discuss MCP constantly without ever calling an MCP tool, and a
  # marker that matched the discussion would disarm the control exactly where it was designed.
  if [ -n "$brief" ] && [ -f "$brief" ]; then
    local hit=""
    hit="$(grep -o -i -m1 -E 'mcp__[a-z0-9_-]+|browsermcp|chrome-devtools|agent-browser|claude-in-chrome' "$brief" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
      CC_MCP_NOINHERIT_REASON="brief declares MCP/browser work ('$hit') — project servers left ON"
      return 0
    fi
  fi

  # The passthrough re-adds the account's USER-scope non-stdio servers, which `--strict-mcp-config`
  # would otherwise drop. Keyed on the config dir's basename so two accounts never share a file, and
  # written through a temp + mv because concurrent fires on one account race here by construction.
  #
  # 🚨 THE STDIO TEST IS SCOPE-BLIND, AND THAT IS WHY THE ALLOWLIST EXISTS (2026-08-15, ms365).
  # `select(.value.command == null)` keeps only servers with no `command` key — i.e. http/sse. That
  # was written when every user-scope server in the fleet WAS http: the measurement table above
  # names "the account's real user-scope http servers (motion, motion-plus)", so on that data a
  # scope-blind stdio ban and a correct scope-aware rule were indistinguishable. They are not the
  # same rule. The cost this control exists to remove is a repo's PROJECT-scope `.mcp.json` stdio
  # servers — and those are already excluded by construction, because `--strict-mcp-config` reads
  # only this passthrough and this passthrough is built from the ACCOUNT's `.claude.json`. Applying
  # the stdio test here therefore bans a population the control was never aimed at: a server the
  # operator deliberately configured at user scope.
  #
  # ms365 (`{"type":"stdio","command":"npx",…}`) is the first such server, and it was invisible to
  # every fired session for exactly this reason — correctly configured in
  # `.claude-next/.claude.json` and silently filtered out of the only file the session ever reads.
  # Full diagnosis + the ruled-out hypotheses: docs/plans/MS365_MCP_ALL_ACCOUNTS.md § Status log.
  #
  # An ALLOWLIST rather than deleting the filter: a user-scope stdio server is a real per-session
  # cost (ms365 measures ~139 MB resident) and this box has a memory-storm panic history, so the
  # right default is "deliberately named servers only", never "every stdio server the config grows".
  # Space-separated; `CC_MCP_USERSCOPE_STDIO_ALLOW=` (empty) restores the pre-2026-08-15 behaviour.
  local allow="${CC_MCP_USERSCOPE_STDIO_ALLOW-ms365}"
  local pass="" srv_count=0
  if [ -n "$cfg" ] && [ -f "$cfg/.claude.json" ] && command -v jq >/dev/null 2>&1; then
    local out="${TMPDIR:-/tmp}/cc-mcp-userscope-${cfg##*/}.json" tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/cc-mcp-userscope.XXXXXX" 2>/dev/null || true)"
    # `$a | index($k)` is null when absent and an INDEX when present — and in jq only `false` and
    # `null` are falsy, so a match at position 0 is correctly truthy (tested both orderings). An
    # empty allow string splits to [], making the clause dead and the filter byte-identical to the
    # pre-allowlist original — that empty case is the suite's control.
    # 🚨 `.key` MUST be bound with `as $k` BEFORE the pipe. Written as `($a | index(.key))` the pipe
    # rebinds `.` to the ARRAY, so `.key` indexes an array with a string and jq dies with
    # "Cannot index array with string" — which fails the whole expression, leaves `pass` empty, and
    # falls through to bare `--strict-mcp-config`, i.e. it would silently drop EVERY server
    # including the http ones this passthrough exists to save. Caught by running it, not reading it.
    if [ -n "$tmp" ] && jq --arg allow "$allow" \
         '($allow | split(" ") | map(select(. != ""))) as $a
          | {mcpServers: ((.mcpServers // {})
              | with_entries(select(.value.command == null or (.key as $k | $a | index($k)))))}' \
         "$cfg/.claude.json" > "$tmp" 2>/dev/null; then
      srv_count="$(jq -r '.mcpServers | length' "$tmp" 2>/dev/null || echo 0)"
      if [ "${srv_count:-0}" -gt 0 ] && mv -f "$tmp" "$out" 2>/dev/null; then
        pass="$out"
      else
        rm -f "$tmp" 2>/dev/null || true
      fi
    else
      [ -n "$tmp" ] && rm -f "$tmp" 2>/dev/null || true
    fi
  fi

  if [ -n "$pass" ]; then
    CC_MCP_NOINHERIT_REASON="project .mcp.json stdio servers OFF; ${srv_count} user-scope server(s) preserved via $pass"
    # `--mcp-config=<path>`, NEVER `--mcp-config <path>`. The option is VARIADIC: in the space form
    # it keeps consuming following words, so the fire's own prompt — a bare positional in every
    # interactive launch shape — is swallowed as a SECOND config path. Measured 2026-08-11: a real
    # fire died at `Invalid MCP configuration: Failed to read file: ENAMETOOLONG` with the whole
    # brief where a filename should be, and the pane sat at a shell with no session in it. It is
    # invisible to a `-p` test, because there the prompt follows a flag that takes a value and is
    # never a loose positional — which is exactly why the first version of this shipped green.
    CC_MCP_NOINHERIT_ARGS="--strict-mcp-config --mcp-config=$pass"
  else
    # No passthrough buildable (no user-scope servers, no jq, unreadable config). Still compose the
    # isolation — the stdio chain is the cost this exists to remove — and SAY that the http servers
    # went with it, because a capability that disappears without a line of output is the failure this
    # whole wave is about.
    CC_MCP_NOINHERIT_REASON="project .mcp.json stdio servers OFF (no user-scope passthrough — http servers off too; --with-mcp to restore)"
    CC_MCP_NOINHERIT_ARGS="--strict-mcp-config"
  fi
}

# cc_mcp_project_decision_args LAUNCH_DIR MODE  —  answer the project `.mcp.json` APPROVAL question
# on the fire's own command line, so an interactive fired session never stalls at the modal.
#
# THE STALL THIS EXISTS TO REMOVE (2026-08-15, operator screenshot). A recycled pane in
# ~/Development/personal came up at "2 new MCP servers found in this project / Select any you wish
# to enable" with the brief unread behind it. It had been launched with `--strict-mcp-config`, i.e.
# it had ALREADY guaranteed those servers would not load — and was asked to approve them anyway. A
# spawned session stopped at a modal never runs its brief and nothing upstream notices: the pane is
# alive, the process is alive, no hook fires.
#
# WHY THIS IS NOT THE SAME QUESTION `--strict-mcp-config` ANSWERS. That flag governs which servers
# LOAD. Approval is a separate axis, read out of the 2.1.220 binary:
#
#   function SZr(e){ let t=us();                                   // us = eo = MERGED settings
#     if(t?.disabledMcpjsonServers?.some(r=>f4r(r,e))) return "rejected";      // ← checked FIRST
#     if(!wB()) return ny_(e)?"approved":"pending";                // wB = workspace trusted?
#     if(t?.enabledMcpjsonServers?.some(...)||t?.enableAllProjectMcpServers) return "approved";
#     return "pending" }                                           // "pending" ⇒ the modal
#
# `pending` is what the fire hit. Three consequences decide this function's shape:
#   1. `disabledMcpjsonServers` is consulted BEFORE the trust branch and returns "rejected" — so a
#      REJECTION silences the question while granting nothing. That is the polarity a no-inherit
#      fire has already chosen, stated in the one place the vendor reads it.
#   2. The store is the MERGED SETTINGS, not `.claude.json`'s `projects[<cwd>]` entry. Those
#      per-project `enabledMcpjsonServers` / `disabledMcpjsonServers` keys exist on disk and this
#      gate never reads them — an obvious-looking seed there would have been a silent no-op.
#   3. `wC()` unconditionally adds `flagSettings` to the allowed sources (`t.add("flagSettings")`),
#      and `--settings <file-or-json>` IS that source. So the decision rides the launch, exactly
#      like the `--mcp-config` passthrough above: nothing durable is written, no other account or
#      later session inherits it, and the operator's own sessions in that repo are untouched.
#
# WHY NOT THE ALTERNATIVES, each rejected for a named reason:
#   · `enableAllProjectMcpServers` in an account settings.json — a forever-grant to every repo that
#     ever declares a server; docs/research/cc-startup-modals-2026-08-04.md §1 classifies `.mcp.json`
#     approval as MUST-REACH-OPERATOR precisely to keep that key out.
#   · `disabledMcpjsonServers` in an account settings.json — account-global, so it would blind that
#     account to a server NAME in every repo.
#   · writing the launch dir's own `.claude/settings.local.json` — that file is shared by all five
#     accounts, so a decision taken for one fired agent session would leak into the operator's own.
#
# POLARITY FOLLOWS THE FIRE, NEVER A FIXED VALUE. MODE=off (the `--strict-mcp-config` default)
# rejects; MODE=on (`--with-mcp`, or a brief that disarmed no-inherit by naming MCP work) approves.
# A fixed "reject" would silently hide a server the fire itself was launched to use — the same class
# as the ms365 disappearance in docs/plans/MS365_MCP_ALL_ACCOUNTS.md, and the reason the scope-blind
# stdio filter above needed an allowlist.
#
# Sets CC_MCP_DECISION_ARGS (possibly empty) and CC_MCP_DECISION_REASON — globals, for the same
# subshell reason documented in this file's header.
# shellcheck disable=SC2034  # CC_MCP_DECISION_ARGS/REASON are the RETURN VALUES — read by the caller.
cc_mcp_project_decision_args() {
  local dir="${1:-}" mode="${2:-off}"
  CC_MCP_DECISION_ARGS=""
  CC_MCP_DECISION_REASON=""

  if [ "${CC_MCP_DECIDE:-on}" = off ]; then
    CC_MCP_DECISION_REASON="disabled by CC_MCP_DECIDE=off"
    return 0
  fi
  [ -n "$dir" ] && [ -f "$dir/.mcp.json" ] || return 0     # no project file ⇒ no question ⇒ no flag
  command -v jq >/dev/null 2>&1 || {
    CC_MCP_DECISION_REASON="jq absent — project .mcp.json approval left to the modal (a fired pane may stall)"
    return 0
  }

  local key names json out tmp n
  case "$mode" in
    on) key="enabledMcpjsonServers"  ;;
    *)  key="disabledMcpjsonServers" ;;
  esac
  # Names come from the launch dir's OWN file, so the answer covers exactly the servers the modal
  # would enumerate. `// {}` keeps a malformed/serverless file from failing the whole expression —
  # empty names then return below rather than emitting `{"...":[]}`, which decides nothing and would
  # cost a flag for no effect.
  json="$(jq -c --arg k "$key" '{($k): ((.mcpServers // {}) | keys)}' "$dir/.mcp.json" 2>/dev/null)" || return 0
  n="$(printf '%s' "$json" | jq -r --arg k "$key" '.[$k] | length' 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] || return 0

  # Keyed on the dir so two fires into DIFFERENT repos never share a file, and on the mode so an
  # `--with-mcp` fire cannot read a rejection a no-inherit fire left behind. temp + mv because
  # concurrent fires into one dir race here by construction (same discipline as the passthrough).
  local slug; slug="$(printf '%s' "$dir" | tr -c 'A-Za-z0-9' '-')"
  out="${TMPDIR:-/tmp}/cc-mcp-decision-${mode}-${slug}.json"
  tmp="$(mktemp "${TMPDIR:-/tmp}/cc-mcp-decision.XXXXXX" 2>/dev/null)" || return 0
  if printf '%s\n' "$json" > "$tmp" && [ -s "$tmp" ] && mv -f "$tmp" "$out" 2>/dev/null; then
    # `--settings=<path>`, not the space form — the same variadic-swallow hazard the passthrough
    # documents above. `--settings` takes one value today, but the `=` form is immune either way and
    # costs nothing.
    CC_MCP_DECISION_ARGS="--settings=$out"
    local verdict=rejected; [ "$mode" = on ] && verdict=approved
    CC_MCP_DECISION_REASON="project .mcp.json: ${n} server(s) pre-${verdict} for THIS launch via $out (no approval modal; nothing written to any config)"
  else
    rm -f "$tmp" 2>/dev/null
    CC_MCP_DECISION_REASON="could not write the per-launch approval decision — a fired pane may stall at the MCP modal"
  fi
}
