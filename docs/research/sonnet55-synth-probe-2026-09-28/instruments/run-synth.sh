#!/usr/bin/env bash
# run-synth.sh — Sonnet 5.5 synthesis-worker probe (2026-09-28). Same frozen corpus, repo snapshot and
# arm prompt as docs/research/opus55-synth-reprobe-2026-09-22/instruments/settle-run.js, but every arm
# runs HEADLESS on 2.1.284 (2.1.280 cannot dispatch claude-sonnet-5-5) with ONE tool rule for all arms:
# Read + read-only Bash (grep/find/ls/cat/sed/head/tail/wc allowlisted; anything else is denied in -p).
# No CLAUDE.md / hooks / memory load (--setting-sources ""), so the arms differ only in model x effort.
# Usage: run-synth.sh <out-dir> <brief>:<model>:<effort> ...
set -uo pipefail
out="${1:?}"; shift; mkdir -p "$out"
: "${SYN_BIN:=$HOME/.claude-284/node_modules/.bin/claude}"; : "${SYN_CONFIG_DIR:=$HOME/.claude-next}"; : "${SYN_PAR:=4}"
REPO=/tmp/s55/repo-47c3317eb   # rebuilt by `git archive 47c3317eb`; the 09-22 snapshot had been eroded by the /tmp cleaner
export out SYN_BIN SYN_CONFIG_DIR REPO
cell() {
  local c="$1" id m e tag raw s
  id="${c%%:*}"; m="$(echo "$c" | cut -d: -f2)"; e="${c##*:}"; tag="${id}__${m}__${e}"; raw="$out/$tag.raw.json"
  s="$(date -u +%FT%TZ)"
  prompt="You are a synthesis worker in a research workflow.

Repository: $REPO — a read-only snapshot of the claude-infrastructure repo, pinned at sha 47c3317eb. Read only files under that path. Paths you cite are relative to that root.

Your brief is in the file /tmp/s55/briefs/$id.md — Read it first; it is the whole task.

Rules:
- Tools: use Read, and Bash for READ-ONLY search and inspection only (grep, find, ls, cat, sed -n, head, tail, wc). Never write, move or delete anything, never run a script from the repo, do not spawn agents. (The Grep/Glob tools do not exist in this harness.) Stay inside the repository path above.
- Saturation bound: after reading the brief, make at most 25 further tool calls, then write your answer from what you have read.
- Cite path:line for every claim, and cite only lines you actually read.
- Your final message IS the deliverable: a complete markdown answer to the brief. No preamble."
  ( cd "$REPO" && printf '%s' "$prompt" | CLAUDE_CONFIG_DIR="$SYN_CONFIG_DIR" CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000 \
      "$SYN_BIN" -p --model "$m" --effort "$e" --tools "Read,Bash" --add-dir /tmp/s55/briefs \
      --allowedTools "Read" "Bash(grep:*)" "Bash(find:*)" "Bash(ls:*)" "Bash(cat:*)" "Bash(sed -n:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" \
      --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format json >"$raw" 2>"$raw.stderr" )
  local rc=$?
  jq -r '.result // ""' "$raw" >"$out/$tag.md" 2>/dev/null || : >"$out/$tag.md"
  jq -c --arg b "$id" --arg m "$m" --arg e "$e" --arg s "$s" --arg t "$(date -u +%FT%TZ)" --argjson rc "$rc" \
    '{brief:$b,model:$m,effort:$e,started_at:$s,ended_at:$t,rc:$rc,is_error,stop_reason,num_turns,duration_ms,served:(.modelUsage//{}|keys),cost_usd:.total_cost_usd,output_tokens:.usage.output_tokens,cache_create:.usage.cache_creation_input_tokens,cache_read:.usage.cache_read_input_tokens,denials:((.permission_denials//[])|length),result_len:((.result//"")|length)}' "$raw" 2>/dev/null \
    || jq -nc --arg b "$id" --arg m "$m" --arg e "$e" --argjson rc "$rc" '{brief:$b,model:$m,effort:$e,rc:$rc,is_error:true,note:"unparseable"}'
}
export -f cell
printf '%s\n' "$@" | xargs -P "$SYN_PAR" -I{} bash -c 'cell "$1"' _ {} >>"$out/index.jsonl"
