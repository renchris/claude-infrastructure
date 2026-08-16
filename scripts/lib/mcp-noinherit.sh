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
