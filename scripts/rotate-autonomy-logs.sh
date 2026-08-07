#!/bin/bash
# rotate-autonomy-logs.sh — size-gated rotation for the append-only autonomy/audit logs that
# grow UNBOUNDED (T-P10-2: idl.jsonl hit 183 MB live; bash-commands.log + bash-execution.log
# ~90 MB each; teammate-checkpoint.log 13.6 MB / 104k lines, joined 2026-07-25 — it was the one
# >5MB log this list did not name, so nothing bounded it at all). None of the writers cap their
# files, and every writer appends per-line via `>>`
# — lead-supervisor.sh:61, hooks/log-bash.sh, hooks/validate-bash.sh all open→write→close on
# EACH call, holding NO persistent fd — so the SAFE rotation is logrotate's `create` mode:
# rename the fat file aside, let the next `>>` recreate it in place (zero data loss, no writer
# signal, no C10 live-writer edit), gzip the rotated copy, and prune to a bounded history.
#
# Each run, for every target file whose size >= ROTATE_MAX_BYTES:
#   1. mv  <f>            -> <f>.<UTC-stamp>       (atomic same-dir rename)
#   2. recreate empty <f> IFF a racing writer has not already (never truncate a live line;
#      preserve the original file mode)
#   3. gzip <f>.<UTC-stamp> -> <f>.<UTC-stamp>.gz  (JSONL/audit text compresses ~10-20x)
#   4. prune: keep the newest ROTATE_KEEP <f>.* rotations, delete older
# Files under threshold are left untouched (idempotent — safe to run every tick). Exactly one
# summary IDL record is emitted per run (rotated >= 0), so "ran but rotated nothing" stays
# distinguishable from "never ran" (the autonomy-sweep B-3 convention).
#
# Targets: default = every unbounded autonomy/audit log (13, see DEFAULT_TARGETS below);
#   override/extend via ROTATE_TARGETS (whitespace/newline-separated absolute paths, no spaces
#   WITHIN a path) or positional args. A missing target is skipped, not an error (its writer may
#   not have created it yet). Sibling files that share a target's prefix but are NOT rotations
#   (the `<idl>.chain` hash chain) are excluded from the prune glob — see prune_one.
#
# ── IDL HASH-CHAIN EPOCHS (the cc-idl coupling) ──────────────────────────────────────────────
# The IDL is the auditability substrate, sealed by a tamper-evident hash chain in a sidecar
# (<idl>.chain, bin/cc-idl). That chain is APPEND-ONLY and MONOTONIC — the immutability of its
# sealed prefix IS the security property (an attacker cannot launder an edit by re-sealing).
# Rotation moves sealed content out from under it, so the two mechanisms were on a collision
# course and nobody owned the seam: `cc-idl seal` had ZERO callers, so the chain froze on
# 2026-07-19 at 6,910 links while the IDL rotated three times beneath it. `cc-idl verify` then
# read the live 136-line IDL against a 6,910-link chain and reported "6,791 sealed records
# DELETED/TRUNCATED" — a PERMANENT FALSE TAMPER (rc 7). That is strictly worse than an unsealed
# log: a detector stuck ON makes a real tamper indistinguishable from routine rotation.
#
# This script owns that seam, in two parts:
#
#   (1) PERIODIC SEAL — every run seals the IDL tail before touching anything (`cc-idl seal`).
#       This is the missing caller: hourly sealing, riding the launchd job that already exists,
#       so no new activation is needed. Best-effort by construction — a seal failure is logged
#       into the run record and NEVER fails the rotation (bounding growth outranks sealing it).
#
#   (2) ROTATION EPOCHS — a rotation CLOSES an epoch instead of desyncing the chain:
#         a. seal first          → the archived chain covers the archived IDL body completely
#         b. archive the sidecar → <idl>.chain.<stamp>, the SAME stamp as the IDL body it seals,
#                                  so the pair stays joined and independently verifiable forever
#         c. the fresh IDL's FIRST record is an `idl_epoch_close` naming the closed epoch's final
#            {seq, head} — and that record is itself sealed into the new genesis chain. So the
#            epochs form a CONTINUOUS chain-of-chains: deleting an archive is still detectable,
#            and re-genesis is WITNESSED rather than silent.
#       Deleting the chain and re-sealing from genesis is precisely the one residual erase
#       cc-idl's `head` verb exists to witness — so this never deletes a chain, it retires it.
#
#   Not automatic: an orphaned chain left by rotations that predate this wiring (chain longer
#   than the live IDL) is repaired ONLY by the explicit `--repair-chain-epoch` flag. Auto-healing
#   a truncation on sight would hand any real attacker a laundering path — the repair is a
#   deliberate, recorded act, never a side effect of a periodic sweep.
#
# Env (tests + ops): ROTATE_TARGETS · ROTATE_MAX_BYTES (default 26214400 = 25 MiB) ·
#   ROTATE_KEEP (default 8) · ROTATE_GZIP (default 1; 0 = leave rotated copy uncompressed) ·
#   CC_IDL (audit sink AND the chain-epoch target) · CC_IDL_BIN (cc-idl override; default =
#   PATH, then ~/.claude/bin, then the sibling repo bin) · ROTATE_SEAL (default 1; 0 = skip the
#   seal/epoch coupling entirely). BSD+GNU portable, no eval, fail-loud, shellcheck-clean.
#   Always exits 0 (except `--repair-chain-epoch`, which reports its own outcome).
#
# NOTE: default targets + the audit sink hardcode $HOME/.claude — NOT $CLAUDE_CONFIG_DIR — because
# the writers do too (autonomy-sweep.sh, hooks/log-bash.sh: `$HOME/.claude/...`). A session that
# overrides CLAUDE_CONFIG_DIR (auth-isolation worktrees) must NOT redirect rotation off the real
# live logs; use ROTATE_TARGETS to point elsewhere explicitly.
set -uo pipefail

MAX_BYTES="${ROTATE_MAX_BYTES:-26214400}"
KEEP="${ROTATE_KEEP:-8}"
DO_GZIP="${ROTATE_GZIP:-1}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
DO_SEAL="${ROTATE_SEAL:-1}"
CHAIN_SUF=".chain"                 # must match cc-idl's CC_IDL_CHAIN default (<idl>.chain)
seal_note=""                       # folded into the run's audit record

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%SZ; }

# portable byte size (0 when absent) — wc -c dodges BSD/GNU stat-format divergence
filesize() { # <path>
  [ -f "$1" ] || { printf '0'; return 0; }
  wc -c < "$1" | tr -d ' '
}

# portable octal mode — BSD stat first, GNU stat next, 644 fallback
filemode() { # <path>
  local m
  m="$(stat -f '%Lp' "$1" 2>/dev/null)" || m=""
  [ -n "$m" ] || m="$(stat -c '%a' "$1" 2>/dev/null)" || m=""
  [ -n "$m" ] || m="644"
  printf '%s' "$m"
}

# ── IDL hash-chain epoch coupling (see the header) ───────────────────────────────────────────

# Resolve the cc-idl binary. Order: explicit override > PATH (the launchd job exports
# ~/.claude/bin) > the live bin dir > this script's sibling repo bin (worktrees + tests).
# Prints the path; non-zero when cc-idl is unavailable — always a SKIP, never a failure.
resolve_cc_idl() {
  local c
  if [ -n "${CC_IDL_BIN:-}" ]; then [ -x "$CC_IDL_BIN" ] && { printf '%s' "$CC_IDL_BIN"; return 0; }; return 1; fi
  c="$(command -v cc-idl 2>/dev/null)" && [ -n "$c" ] && { printf '%s' "$c"; return 0; }
  for c in "$HOME/.claude/bin/cc-idl" "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/bin/cc-idl"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# is this target the IDL whose chain we own? (the chain coupling applies to that path only)
is_idl_target() { [ "$1" = "$IDL" ]; }

# nlines — \n-terminated lines only, 0 when absent (a mid-write partial line never counts)
nlines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || printf '0'; }

# seal_idl_tail — THE missing caller. Extends the chain over every complete IDL line not yet
# sealed. Best-effort for the RUN's exit status: bounding unbounded growth outranks sealing it,
# so a seal failure never fails the rotation (a stalled rotation is the worse failure).
#
# But best-effort must not mean SILENT. seal_note lands in the run's audit record and NOTHING
# reads it, the script always exits 0, and cc-fleet's evidence for this job is its stdout log —
# whose mtime bumps whether or not the seal worked. So a seal failing every run leaves the chain
# frozen while every observer still reads HEALTHY: this mechanism's own failure mode recurring in
# its second form (the first was "no caller at all"; this one is "caller present, failing
# quietly"). Both states that mean TAMPER-EVIDENCE HAS STOPPED ADVANCING — the sealer erroring,
# and the sealer being unreachable — therefore report on stderr, carrying cc-idl's OWN diagnosis
# rather than discarding it. A healthy seal stays SILENT: hourly noise would train the operator to
# ignore the very log this warning has to survive in. `off`/`no-idl` are deliberate and stay quiet.
seal_idl_tail() {
  [ "$DO_SEAL" = "1" ] || { seal_note="off"; return 1; }
  [ -f "$IDL" ] || { seal_note="no-idl"; return 1; }
  local bin err
  bin="$(resolve_cc_idl)" || {
    seal_note="cc-idl-absent"
    echo "rotate-autonomy-logs: WARNING cc-idl not found — the IDL hash chain is NOT being extended (tamper-evidence is OFF). Install ~/.claude/bin/cc-idl or set CC_IDL_BIN." >&2
    return 1
  }
  # 2>&1 >/dev/null captures cc-idl's stderr ONLY — its stdout is the routine "sealed N new" line.
  if err="$(CC_IDL="$IDL" "$bin" seal 2>&1 >/dev/null)"; then seal_note="ok"; return 0; fi
  seal_note="seal-failed"
  echo "rotate-autonomy-logs: WARNING cc-idl seal FAILED — chain frozen at $(nlines "$IDL$CHAIN_SUF") link(s) under a $(nlines "$IDL")-line IDL; tamper-evidence stops advancing until this clears. cc-idl said: ${err:-[no output]}" >&2
  return 1
}

# close_chain_epoch <idl> <stamp> — retire the sidecar ALONGSIDE the IDL body it seals, then
# open the successor epoch with a witnessed link back. Called only after a rotation this script
# itself performed, and only once the fresh IDL exists.
close_chain_epoch() { # <idl-path> <stamp>
  local f="$1" stamp="$2" chain="$1$CHAIN_SUF" seq head body_n orphaned=false
  [ "$DO_SEAL" = "1" ] || return 0
  [ -s "$chain" ] || return 0                       # nothing sealed yet → nothing to retire
  seq="$(nlines "$chain")"
  head="$(tail -n1 "$chain" | cut -f2)"
  # Was the chain ALREADY divergent from the body it is about to be archived with? Retiring a
  # sidecar necessarily clears the LIVE verify, so an epoch that closes in a divergent state must
  # say so permanently — otherwise a rotation could quietly carry away a standing tamper signal.
  # The evidence itself is never lost (the archived pair still fails verification on its own),
  # but the loss of the live signal is the part that has to stay loud.
  body_n="$(nlines "$f.$stamp")"
  if [ "$seq" -gt "$body_n" ]; then
    orphaned=true
    echo "rotate-autonomy-logs: ⚠ chain was ORPHANED at rotation ($seq links > $body_n body lines) — retiring it clears the live verify; the archived pair still fails verification. Investigate before trusting a green verify." >&2
  fi
  if ! mv "$chain" "$chain.$stamp" 2>/dev/null; then
    echo "rotate-autonomy-logs: could not archive $chain — leaving it (cc-idl verify will read FALSE TAMPER until repaired)" >&2
    return 1
  fi
  [ "$DO_GZIP" = "1" ] && command -v gzip >/dev/null 2>&1 && gzip -f "$chain.$stamp" 2>/dev/null
  # The successor's FIRST record names the retired epoch's final {seq,head}. The next seal
  # covers it, so the epochs are one continuous chain-of-chains: a deleted archive is still
  # detectable, and re-genesis is witnessed instead of silent.
  printf '{"ts":"%s","tool":"rotate-autonomy-logs","kind":"idl_epoch_close","epoch":"%s","prev_seq":%s,"prev_head":"%s","idl_archive":"%s","chain_archive":"%s","orphaned":%s}\n' \
    "$(now_iso)" "$stamp" "$seq" "$head" "$(basename "$f").$stamp" "$(basename "$chain").$stamp" "$orphaned" \
    >> "$f" 2>/dev/null || true
  return 0
}

rotated=0
skipped=0
summary=""

# prune <path>: keep newest KEEP rotations (<path>.*), delete older. Timestamps are fixed-width
# and lexically sortable, so reverse name-sort == newest-first (a trailing .gz sorts after its
# stamp, preserving order). Runs in the current shell (here-string, not a pipe) so the counter sticks.
prune_one() { # <path>
  local f="$1" listing i=0 g
  local -a arr=()
  # The chain family (<f>.chain, its archives, its .lock.d) lives under the same <f>.* glob but
  # is NOT a rotation of <f>: counting it here silently spent one KEEP slot and, worse, put the
  # live sidecar on the delete list. It is excluded and pruned separately, in stamp-matched pairs.
  for g in "$f".*; do
    [ -e "$g" ] || continue
    case "$g" in *"$CHAIN_SUF"*) continue ;; esac
    arr+=("$g")
  done
  [ "${#arr[@]}" -le "$KEEP" ] && return 0
  listing="$(printf '%s\n' "${arr[@]}" | sort -r)"
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    i=$((i + 1))
    [ "$i" -le "$KEEP" ] && continue
    rm -f "$g" 2>/dev/null || true
  done <<EOF
$listing
EOF
}

# prune the retired chain sidecars to the same KEEP. Both families carry the SAME stamp, so
# equal depth keeps every archived body paired with the chain that seals it — a chain archive
# must never outlive its body, nor a body outlive its proof.
prune_chain_archives() { # <idl-path>
  local f="$1$CHAIN_SUF" listing i=0 g
  local -a arr=()
  for g in "$f".*; do
    [ -e "$g" ] || continue
    case "$g" in *.lock.d) continue ;; esac      # the live mutex, not an archive
    arr+=("$g")
  done
  [ "${#arr[@]}" -le "$KEEP" ] && return 0
  listing="$(printf '%s\n' "${arr[@]}" | sort -r)"
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    i=$((i + 1))
    [ "$i" -le "$KEEP" ] && continue
    rm -f "$g" 2>/dev/null || true
  done <<EOF
$listing
EOF
}

rotate_one() { # <path>
  local f="$1" sz stamp mode
  sz="$(filesize "$f")"
  if [ "$sz" -lt "$MAX_BYTES" ]; then
    skipped=$((skipped + 1))
    return 0
  fi
  stamp="$(now_stamp)"
  mode="$(filemode "$f")"
  # 0. seal FIRST, so the sidecar about to be archived covers the body about to be archived.
  #    A line landing between the seal and the mv is simply an unsealed tail in the archive —
  #    the benign direction (verify ignores an unsealed tail; only idl-SHORTER-than-chain is
  #    TAMPER), which is why this ordering is safe and the reverse would not be.
  is_idl_target "$f" && seal_idl_tail
  # 1. atomic same-dir rename — the fat file is captured; the path is now free
  if ! mv "$f" "$f.$stamp" 2>/dev/null; then
    echo "rotate-autonomy-logs: mv failed for $f — skipping" >&2
    skipped=$((skipped + 1))
    return 0
  fi
  # 2. recreate in place ONLY if a racing writer has not — never truncate a just-written line
  if [ ! -e "$f" ]; then
    : > "$f" 2>/dev/null || true
    chmod "$mode" "$f" 2>/dev/null || true
  fi
  # 2b. retire the sidecar with the body it seals, and open the successor epoch with a
  #     witnessed link back to the retired head (see the header).
  is_idl_target "$f" && close_chain_epoch "$f" "$stamp"
  # 3. compress the rotated copy (best-effort; a gzip miss leaves the plain rotation, still pruned)
  if [ "$DO_GZIP" = "1" ] && command -v gzip >/dev/null 2>&1; then
    gzip -f "$f.$stamp" 2>/dev/null || echo "rotate-autonomy-logs: gzip failed for $f.$stamp (left plain)" >&2
  fi
  rotated=$((rotated + 1))
  [ -n "$summary" ] && summary="$summary,"
  summary="$summary{\"file\":\"$(basename "$f")\",\"bytes\":$sz}"
  # 4. bound the history (rotations and their chain sidecars pruned to equal depth, stamp-paired)
  prune_one "$f"
  is_idl_target "$f" && prune_chain_archives "$f"
}

log_idl() { # <extra-json-fragment>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"rotate-autonomy-logs","rotated":%d,"skipped":%d,"max_bytes":%d,"keep":%d,"seal":"%s"%s}\n' \
    "$(now_iso)" "$rotated" "$skipped" "$MAX_BYTES" "$KEEP" "${seal_note:-off}" "${1:-}" \
    >> "$IDL" 2>/dev/null || true
}

# ── --repair-chain-epoch: the ONE-TIME fix for a chain orphaned before this wiring existed ───
# Signature: the chain seals MORE lines than the live IDL holds, i.e. exactly what `cc-idl
# verify` calls TAMPER. Here that reading is a known artifact (rotations that predate the epoch
# coupling), but the tool cannot tell the two apart — which is why this is an explicit,
# operator-invoked verb and NEVER a step in the periodic sweep. Auto-healing a truncation on
# sight is a laundering path for a real attacker; the orphan head is therefore RECORDED into the
# successor epoch, not discarded, so the pre-repair chain stays witnessed.
repair_chain_epoch() {
  local chain="$IDL$CHAIN_SUF" stamp seq head idl_n
  if [ ! -s "$chain" ]; then echo "repair: no chain at $chain — nothing to repair (a plain seal starts genesis)"; return 0; fi
  seq="$(nlines "$chain")"; idl_n="$(nlines "$IDL")"
  if [ "$idl_n" -ge "$seq" ]; then
    echo "repair: REFUSED — idl has $idl_n line(s) >= chain's $seq; this chain is NOT orphaned."
    echo "        A verify failure here would be a real divergence, not a rotation artifact. Do not repair; investigate."
    return 1
  fi
  stamp="$(now_stamp)"; head="$(tail -n1 "$chain" | cut -f2)"
  mv "$chain" "$chain.$stamp" 2>/dev/null || { echo "repair: could not archive $chain" >&2; return 1; }
  [ "$DO_GZIP" = "1" ] && command -v gzip >/dev/null 2>&1 && gzip -f "$chain.$stamp" 2>/dev/null
  printf '{"ts":"%s","tool":"rotate-autonomy-logs","kind":"idl_epoch_repair","epoch":"%s","prev_seq":%s,"prev_head":"%s","chain_archive":"%s","note":"orphaned by rotations predating the epoch coupling; retired, not deleted"}\n' \
    "$(now_iso)" "$stamp" "$seq" "$head" "$(basename "$chain").$stamp" >> "$IDL" 2>/dev/null || true
  seal_idl_tail
  echo "repair: retired orphaned chain ($seq links, head ${head:0:8}) → $(basename "$chain").$stamp"
  echo "repair: successor epoch opened and sealed (seal=$seal_note); prior head is recorded in the IDL, not discarded."
  return 0
}
case "${1:-}" in --repair-chain-epoch) repair_chain_epoch; exit $? ;; esac

# ── resolve the target list: positional args > ROTATE_TARGETS > the defaults ──
# The plist (com.claude.log-rotation) invokes this with NO args and NO env, so DEFAULT_TARGETS *is*
# the live coverage. It listed 3 files while ~/.claude/logs stood at 96 MB with nine unbounded
# writers outside the list (audit 09 §4 / 03): teammate-checkpoint.log 13.6 MB · sessions.log
# 2.8 MB · cc-reaper.log 2.0 MB · teammate-lifecycle.log 1.9 MB · session-index.log 1.7 MB ·
# team-reaper.log 1.3 MB · lead-crash-watchdog.log 1.2 MB · cc-reaper.out.log 1.0 MB ·
# task-quality-gate.log 707 KB — plus autonomy/supervisor.log. Every one is an append-only
# `>>`-per-line writer holding no persistent fd, so they satisfy the same create-mode contract as
# the original three; semantics (>=ROTATE_MAX_BYTES → rotate, keep ROTATE_KEEP) are unchanged.
DEFAULT_TARGETS="$HOME/.claude/autonomy/idl.jsonl
$HOME/.claude/logs/bash-commands.log
$HOME/.claude/logs/bash-execution.log
$HOME/.claude/autonomy/supervisor.log
$HOME/.claude/logs/teammate-checkpoint.log
$HOME/.claude/logs/task-quality-gate.log
$HOME/.claude/logs/cc-reaper.log
$HOME/.claude/logs/session-index.log
$HOME/.claude/logs/sessions.log
$HOME/.claude/logs/lead-crash-watchdog.log
$HOME/.claude/logs/cc-reaper.out.log
$HOME/.claude/logs/teammate-lifecycle.log
$HOME/.claude/logs/team-reaper.log
$HOME/.claude/autonomy/postland/flakes.jsonl
$HOME/.claude/autonomy/postland/runner.log
$HOME/.claude/logs/capacity-alarm.jsonl
$HOME/.claude/logs/compressor-sentinel.jsonl
$HOME/.claude/logs/compressor-sentinel-snap.log
$HOME/.claude/logs/pane-spawns.jsonl"

# capacity-alarm.jsonl joined 2026-07-31, in the SAME commit that took its sampler from 600 s to
# 60 s. It had never been a target because at 144 rows/day it was not going anywhere; at 1,440
# rows/day (~640 KB/day) it is. Adding the rate without adding the rotation is how idl.jsonl
# reached 183 MB — a cadence and its exhaust are one change, and this list is the other half of it.
# compressor-sentinel.jsonl joined 2026-08-05 in the SAME commit that created its 10 s daemon
# (~8,640 rows/day ≈ 2.6 MB/day) — same rule: a cadence and its exhaust are one change. The snap log
# only grows on trips, but a trip writes 13 snapshots, so it rides along.

# cc-relogin*.log joined 2026-07-25: the autonomous relogin loop (cc-relogin-poll on an hourly
# LaunchAgent + the cc-relogin executor it invokes) appends per run and caps nothing, and the
# launchd StandardOut/StandardError paths land beside them under the same prefix. Enumerated by
# GLOB rather than named literally, because the exact leaf names are the poller's to choose —
# a literal that never matches would rotate nothing and look like it was covered. The list is
# rebuilt every run, so a log created later is picked up on the next tick (a file that does not
# exist needs no rotation). Same append-per-call, no-persistent-fd shape as the others, so the
# existing `create`-mode rotation applies unchanged. Idiom mirrors prune_one's glob: the -f test
# absorbs the no-match case, so no shopt/nullglob and no `ls` parsing.
for _rl in "$HOME"/.claude/logs/cc-relogin*.log; do
  [ -f "$_rl" ] && DEFAULT_TARGETS="$DEFAULT_TARGETS
$_rl"
done

TARGETS=()
if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  while IFS= read -r _line; do
    [ -n "$_line" ] && TARGETS+=("$_line")
  done <<EOF
$(printf '%s' "${ROTATE_TARGETS:-$DEFAULT_TARGETS}" | tr '[:blank:]' '\n')
EOF
fi

for _t in "${TARGETS[@]}"; do
  [ -n "$_t" ] && rotate_one "$_t"
done

# THE periodic seal (part 1 of the coupling): extend the chain over everything written since the
# last run — including any epoch_close emitted above, which is what makes the epochs continuous.
# Runs whether or not anything rotated, so sealing tracks the job's cadence and not the rotation
# threshold. Deliberately BEFORE log_idl: no record can seal itself, so the run record is the
# (single-line, always-current) unsealed tail the next run picks up.
seal_idl_tail

# One audit record per run (lands in the freshly-recreated idl.jsonl when idl was a rotated target).
extra=""
[ -n "$summary" ] && extra=",\"files\":[$summary]"
log_idl "$extra"

echo "rotate-autonomy-logs: rotated=$rotated skipped=$skipped seal=$seal_note (max=${MAX_BYTES}B keep=$KEEP)"
exit 0
