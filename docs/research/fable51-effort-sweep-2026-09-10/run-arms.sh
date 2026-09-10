#!/usr/bin/env bash
# run-arms.sh — produce Fable 5.1 review outputs over the frozen codex-probe corpus, one
# (brief, effort) cell per fresh, tool-less, memory-less context. Produces outputs; never judges.
#
# Isolation is the W2 recipe measured in
# docs/research/codex-probe-screen-2026-08-10/W2-preflight-findings.md §3: --tools "" removes the
# tools (num_turns=1 per record is the per-run control), --setting-sources "" + a neutral scratch
# cwd loads no CLAUDE.md / MEMORY.md / hooks (this repo's MEMORY.md states cp-01's ground truth in
# one line, so a run with memory loaded is void).
#
# Usage: run-arms.sh <out-dir> <brief-id>:<effort> [...]
#   env: SWEEP_CONFIG_DIR (default ~/.claude-quaternary) · SWEEP_BIN (default the 2.1.260 pin —
#        2.1.114 refuses claude-fable-5-1 with "version 2.1.251 or newer is required")
#        SWEEP_MODEL (default claude-fable-5-1) · SWEEP_PAR (default 5)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corpus="$(cd "$here/../../../tests/fixtures/codex-probe/briefs" && pwd)"
out="${1:?out-dir}"; shift
mkdir -p "$out"
: "${SWEEP_CONFIG_DIR:=$HOME/.claude-quaternary}"
: "${SWEEP_BIN:=$HOME/.claude-260/node_modules/.bin/claude}"
: "${SWEEP_MODEL:=claude-fable-5-1}"
: "${SWEEP_PAR:=5}"
export out corpus SWEEP_CONFIG_DIR SWEEP_BIN SWEEP_MODEL

run_cell() {
  local cell="$1" brief eff dir raw started ended
  brief="${cell%%:*}"; eff="${cell##*:}"
  raw="$out/${brief}__${eff}.raw.json"
  # Neutral path: cwd is in the system prompt, so it must name neither the brief nor the effort.
  dir="$(mktemp -d /private/tmp/rvw.XXXXXX)"
  cp "$corpus/$brief.md" "$dir/brief.md"
  started="$(date -u +%FT%TZ)"
  ( cd "$dir" && CLAUDE_CONFIG_DIR="$SWEEP_CONFIG_DIR" CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 \
      "$SWEEP_BIN" -p --model "$SWEEP_MODEL" --effort "$eff" \
      --tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands \
      --no-session-persistence --output-format json <brief.md >"$raw" 2>"$raw.stderr" )
  local rc=$?
  ended="$(date -u +%FT%TZ)"
  rm -rf "$dir"
  # A refusal or an error is a real arm outcome: recorded verbatim, never retried into a number.
  jq -r '.result // ""' "$raw" >"$out/${brief}__${eff}.md" 2>/dev/null || : >"$out/${brief}__${eff}.md"
  jq -c --arg b "$brief" --arg e "$eff" --arg m "$SWEEP_MODEL" --arg s "$started" --arg t "$ended" \
     --argjson rc "$rc" '{brief_id:$b, effort:$e, model:$m, started_at:$s, ended_at:$t, rc:$rc,
       is_error, stop_reason, num_turns, duration_ms,
       served:(.modelUsage // {} | keys), cost_usd:.total_cost_usd,
       input_tokens:.usage.input_tokens, cache_read:.usage.cache_read_input_tokens,
       cache_create:.usage.cache_creation_input_tokens, output_tokens:.usage.output_tokens,
       result_len:((.result // "") | length)}' "$raw" 2>/dev/null \
    || jq -nc --arg b "$brief" --arg e "$eff" --argjson rc "$rc" \
         '{brief_id:$b, effort:$e, rc:$rc, is_error:true, note:"raw json unparseable"}'
}
export -f run_cell

# shellcheck disable=SC2016  # $1 is meant to expand in the child bash, not here
printf '%s\n' "$@" | xargs -P "$SWEEP_PAR" -I{} bash -c 'run_cell "$1"' _ {} >>"$out/index.jsonl"
