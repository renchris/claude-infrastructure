# shellcheck shell=bash
# hook-profile.sh — the LEAN hook profile for bulk agents (fix row 16,
# docs/research/concurrency-scale-2026-10-04/README.md; e-per-agent-cost.md §2). Sourced, never run.
#
# WHY. Every Bash call fires 20 registered hooks, subagent calls included, and the chain costs ~0.6 CPU-s
# per call at load ~40 (scripts/hook-profile-bench.py). A bulk agent (an in-process subagent, a workflow
# agent, a headless fleet lead) pays that per call, and at fleet scale the chain alone exceeds the box.
# Some of those hooks only log, advise or act for the top-level session; for a bulk agent they cost CPU
# and buy nothing, or act on the wrong session. Those hooks call cc_hook_skip FIRST and exit in pure
# bash — no jq, no python, no fork — before any of their real work.
#
# THE CLASSES (the full 20-hook table and its reasons: docs/plans/CONCURRENCY_PROGRAM.md, wave B):
#   advisory  — logging, nudges, token savers, recovery side-cars. Skipped under CC_HOOK_PROFILE=lean
#               (a headless fleet lead sets it in its env) AND inside a subagent.
#               log-bash · relay-verbatim · teammate-checkpoint · memory-index-drain · bash-output-offload
#   lead-only — real work for a top-level session that is wrong inside a subagent, whose payload carries
#               the PARENT's session_id and transcript. Skipped inside a subagent only; a headless lead
#               still needs them. waiting-recycle · mailbox-drain post-tool
#   (never)   — every deny/ask/rewrite/admission gate, every auto-allow (skipping one would make a bulk
#               agent prompt, and nobody answers it), the permission beacon (a skipped clear leaves a
#               stale PERMISSION-PENDING page) and post-tool-batch (it carries the CPU-attribution join).
#               These never source this file.
#
# SUBAGENT DETECTION reads the top-level "agent_id" key, which Claude Code puts on hook payloads from
# inside an in-process subagent or workflow agent (measured: 170 of 2,635 validate-bash decision rows
# carry one). Pane teammates and headless leads carry none; only the env flag reaches them. The scan is
# cut at "tool_input" first, the hooks/unit-gate.sh rule: CC emits identity fields before tool_input, and
# a command or a prompt that merely QUOTES an agent_id must not read as the caller's identity. A key
# inside a JSON string is escaped (\"agent_id\":) and cannot match the bare pattern.
#
# FAIL-OPEN TO THE FULL CHAIN. A hook sources this with `. lib 2>/dev/null && cc_hook_skip ... && exit 0`,
# so a missing lib (a live layer whose install.sh has not linked it yet) runs the hook as before.

cc_hook_skip() { # <advisory|lead-only> [payload] → 0 = skip this hook, 1 = run it
  case "$1" in
    advisory)  [ "${CC_HOOK_PROFILE:-}" = lean ] && return 0 ;;
    lead-only) ;;
    *)         return 1 ;;
  esac
  [ -n "${2:-}" ] || return 1
  local scan="${2%%\"tool_input\"*}"
  [[ $scan =~ \"agent_id\"[[:space:]]*:[[:space:]]*\"[A-Za-z0-9@:._-]{1,128}\" ]]
}
