#!/usr/bin/env bash
# read-before-write-parity.sh — restore Claude Code's native read-before-write guard on the
# accounts where a server-side GrowthBook flag has switched it OFF.
#
# ── WHAT BROKE ───────────────────────────────────────────────────────────────────────────────────
# 2.1.220's Write/Edit validation refuses a write to a file this session has never read:
#
#     let c = r.readFileState.get(n);
#     if (!c || c.isPartialView) {
#       let d = lo(VO(r)),
#           f = !c && Ke(lqi("tengu_velvet_mallet", d), !1);   // f ⇒ guardSkipped
#       M("tengu_write_tool_not_read_hypothetical", { ..., guardSkipped: f, modelBucket: bQt(d) });
#       if (!f) return { result: !1, message: "File has not been read yet. Read it first..." }
#     }
#
# `lqi("tengu_velvet_mallet", model)` resolves to `tengu_velvet_mallet_<bucket>` — a PER-MODEL,
# PER-USER GrowthBook flag, `lqi(e,t){return`${e}_${bQt(t)}`}`. Where it is true the guard is SKIPPED.
#
# ⚠️  THIS TABLE IS A DATED MEASUREMENT, NOT A STANDING FACT. The flag is served per-user and
# per-model and it HAS moved — re-measure before citing it. Re-measured 2026-08-12 (all four caches
# fetched within ~1h of each other, `cachedGrowthBookFeatures`, 490 features each):
#
#     bucket                          next   next2  next3  next4
#     tengu_velvet_mallet_opus_5      TRUE   TRUE   TRUE   TRUE
#     tengu_velvet_mallet_opus_4_8    TRUE   TRUE   TRUE   TRUE
#     tengu_velvet_mallet_opus_4_7    TRUE   TRUE   TRUE   TRUE
#     tengu_velvet_mallet_sonnet_4_6  TRUE   TRUE   TRUE   TRUE
#
# The rollout completed: on 2026-08-05 this file recorded 5 TRUE of 16 cells and concluded "next2 —
# and only next2"; a week later it is 16 of 16, and `sonnet_5`, `fable_5`, `haiku_4_5` and `opus_4_6`
# are TRUE as well. The bare `tengu_velvet_mallet` fallback is false, which is why the BUCKET key is
# the one that decides. (`~/.claude`, the 2.1.114 stable dir, has no velvet_mallet key at all — its
# cache is a 442-feature snapshot from 2026-08-08 — so it resolves absent ⇒ allow.)
#
# So the native guard is now OFF on every live account for every model this fleet runs, and the
# premise this shim was written against is stronger than when it was written, not weaker.
# PROVEN LIVE, not merely inferred from the cache (2026-08-12, session on claude-opus-5 /
# CLAUDE_CONFIG_DIR=~/.claude-next): a file created via Bash — hence carrying no readFileState entry
# — and never Read was overwritten by `Write` and the tool returned success. The only hook that fired
# was `backup-before-write.sh`, which took a backup, printed its advisory, and exited 0.
#
# That guard is the MECHANICAL BACKSTOP for the CRITICAL "INTEGRATE new content — NEVER overwrite"
# rule in CLAUDE.md, a rule that file itself records as having been violated "multiple times...
# caused significant rework".
#
# `backup-before-write.sh` does NOT cover this, despite firing on the same tools on all four
# accounts: every one of its paths ends `exit 0` with an advisory `additionalContext`. It backs up
# and it warns; it has never refused a write. Advisory text is exactly what the native guard exists
# to not rely on. (The 2026-08-05 audit read "backup hook present on all 4 config dirs" as
# "next2 is still covered" — present, but a different mechanism with a different effect.)
#
# There is no operator lever: unlike `tengu_velvet_tide` (whose `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`
# env check short-circuits ahead of the flag), the velvet_mallet call site reads the flag with no
# env escape. Parity can only be restored from outside the binary — here.
#
# ── THE PREDICATE MIRRORS THE BINARY, INCLUDING ITS DEFAULT ───────────────────────────────────────
# This enforces IFF the native guard is PROVABLY off, i.e. the bucket key is PRESENT and TRUE in
# this account's flag cache. Absent, false, unreadable, no jq, unknown model ⇒ do nothing, because
# `Ke(name, !1)` returns FALSE on every one of those misses, which means the native guard is ON and
# already refusing. So the fail-open direction is not a concession — it is the direction that keeps
# this in agreement with the binary (MEMORY.md gate-default-decides-failure-direction).
#
# Consequence worth stating plainly: this can only ever act where the native refusal has already been
# taken away. When the 2026-08-05 table held, that meant ZERO added deny surface on three of four
# accounts; at the 2026-08-12 table it means the shim is load-bearing on all four. Neither reading
# changes a line of code below — which is the point of mirroring the binary's own default rather than
# hardcoding a verdict about the fleet.
#
# ── ONLY THE never-read CASE ─────────────────────────────────────────────────────────────────────
# `f = !c && flag` — the skip needs NO readFileState entry at all. A PARTIAL view (`Read` with
# offset/limit) still creates an entry, so `f` is false and the native guard refuses even on next2.
# So this hook has to reproduce exactly one branch: file exists, session never touched it. Every
# other branch is still natively enforced, which is why counting a partial Read as "touched" here
# is correct rather than sloppy.
#
# ── THREE STATES, NEVER TWO ──────────────────────────────────────────────────────────────────────
# The transcript oracle answers touched / provably-untouched / cannot-tell, and only the middle
# state can lead to a deny. A lookup that fails can only MISS, and a miss is not an absence
# (MEMORY.md lookup-miss-is-not-absence).
#
# ── KNOWN COVERAGE RESIDUE (named, not silently absorbed) ─────────────────────────────────────────
#   · POST-COMPACTION. readFileState lives in memory and survives a compaction that rewrites the
#     transcript; this oracle would not see the dropped Read and would deny a legitimate write.
#     Guarded by requiring >=1 file-touching tool_use record in the transcript before ANY deny — a
#     transcript with none is treated as cannot-tell. Not airtight (a partial drop is conceivable),
#     but the residue fails in the allow direction.
#   · FIRST TOOL CALL. If no assistant record carries a model yet, the bucket is unknown ⇒ allow.
#     One call's worth of gap, versus the cost of a false deny on an unknown model.
#   · BASH-WRITTEN FILES. `sed -i`/heredoc writes populate no readFileState entry either, so the
#     native guard refuses them too — denying here is parity, not over-reach. Deliberate.
# Every residue above resolves to ALLOW. This hook cannot block work the binary would have run.
#
# Pure function definitions only — no side effects on source (safe under `set -u`).

# Bound every read: this runs on every Write/Edit, and a wedged read must never hold a tool call
# open. No `timeout` on PATH ⇒ run unbounded rather than lose the signal (mirrors lib/session-writes.sh).
_rbw_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# rbw_bucket <model-id>
#   claude-opus-5 → opus_5 · claude-opus-4-8 → opus_4_8.  Mirrors the binary's bQt(), which is
#   (read out of 2.1.220's claude.exe, 2026-08-12):
#
#       function bQt(e){ let t = e.replace(/\[1m\]$/i,"")
#                          .replace(/^claude-/,"")
#                          .replaceAll("-","_");
#                        return /^[a-z0-9_]{1,40}$/.test(t) ? xp(t) : Te("nonconforming") }
#
#   Two steps are easy to miss and BOTH were missing here until 2026-08-12:
#     · the `[1m]` STRIP. The 1M-context variant `claude-opus-5[1m]` buckets to `opus_5`, i.e. it
#       shares its parent's flag. Without the strip this built `opus_5[1m]`, missed the cache key and
#       allowed — so the shim was blind on exactly the variant whose parent bucket is TRUE. Fail-open,
#       therefore silent: a coverage hole that could only ever be found by reading bQt.
#     · the CONFORMANCE TEST, whose failure branch is the LITERAL string "nonconforming" — not the
#       coerced id. The old `.` → `_` substitution was a divergence in the DENY direction: the binary
#       rejects a `.` as nonconforming (guard stays ON), while coercing it could land on a real key
#       and deny where the binary allows. `tengu_velvet_mallet_nonconforming` is absent from all four
#       caches (measured 2026-08-12), so the mirrored branch resolves to allow, as the binary does.
rbw_bucket() {
  local m="${1:-}"
  m="${m%\[1m\]}"; m="${m%\[1M\]}"
  m="${m#claude-}"
  m="${m//-/_}"
  # `case` rather than `[[ =~ ]]`: no regex engine to depend on. The class is ENUMERATED rather than
  # written `[!a-z0-9_]`, because a RANGE in a glob bracket is resolved by the locale's COLLATION
  # order, not by ASCII: under en_US.UTF-8 the collation interleaves cases, so `a-z` also covers most
  # uppercase letters and `claude-OPUS-5` was accepted as conforming — measured here 2026-08-12, and
  # the binary's own /^[a-z0-9_]{1,40}$/ is a true regex that rejects it. Enumeration has no
  # collation to consult and so means the same thing in every locale
  # (MEMORY.md c-locale-turns-character-ops-into-byte-ops).
  case "$m" in
    ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_]*) printf 'nonconforming'; return 0 ;;
  esac
  [ "${#m}" -le 40 ] || { printf 'nonconforming'; return 0; }
  printf '%s' "$m"
}

# rbw_config_dir — the account whose flag cache governs THIS session.
rbw_config_dir() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then printf '%s' "$CLAUDE_CONFIG_DIR"
  else printf '%s' "$HOME/.claude"; fi
}

# rbw_guard_disabled <model-id>
#   rc 0 — native guard PROVABLY off for this account+model (this hook must enforce)
#   rc 1 — on, absent, unknown or unreadable (the binary is still refusing; stay out)
rbw_guard_disabled() {
  local model="${1:-}" cfg key val
  [ -n "$model" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  cfg="$(rbw_config_dir)/.claude.json"
  [ -f "$cfg" ] || return 1
  key="tengu_velvet_mallet_$(rbw_bucket "$model")"
  # `// "absent"` keeps a missing key distinguishable from a false one in the trace, but both
  # land on the same rc — matching Ke(name,!1).
  # shellcheck disable=SC2016  # `$k` is a jq variable bound by --arg, not a shell expansion
  val="$(_rbw_bounded 5 jq -r --arg k "$key" \
          '(.cachedGrowthBookFeatures[$k] // "absent") | tostring' "$cfg" 2>/dev/null)" || return 1
  [ "$val" = "true" ] || return 1
  return 0
}

# _rbw_canon <path> [cwd] — one spelling for both sides of the comparison.
#   Resolves the DIRECTORY and re-appends the basename, so a path whose file is being created still
#   canonicalises. Load-bearing, not tidy: /tmp is a symlink to /private/tmp on macOS and this
#   repo's live layer is symlinks into the checkout, so two spellings of one file would never
#   compare equal and the oracle would report "untouched" for a file the session just read — the
#   FALSE-DENY direction (MEMORY.md session-writes canonicalisation note).
_rbw_canon() {
  local p="${1:-}" base="${2:-}" d b phys
  [ -n "$p" ] || return 1
  case "$p" in
    /*) ;;
    *) [ -n "$base" ] && p="$base/$p" ;;
  esac
  d="$(dirname "$p")"; b="$(basename "$p")"
  phys="$(cd "$d" 2>/dev/null && pwd -P 2>/dev/null)"
  if [ -n "$phys" ]; then printf '%s/%s' "$phys" "$b"; else printf '%s' "$p"; fi
}

# _rbw_model <transcript> — the model of the most recent assistant record.
#   Reads only the TAIL: this runs on every Write/Edit and the answer is always near the end, so a
#   full-file pass would be paid on every call just to be thrown away by the flag check below.
_rbw_model() {
  local tp="${1:-}" out
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  out="$(_rbw_bounded "${RBW_TIMEOUT_S:-5}" \
          tail -n "${RBW_MODEL_TAIL_LINES:-400}" "$tp" 2>/dev/null \
        | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null | tail -1)"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# _rbw_touched_paths <transcript>
#   stdout: every path this session Read/Wrote/Edited, one per line.
#   rc 0 — at least one record · rc 1 — none · rc 2 — cannot-tell
#   Sidechain (subagent) records are INCLUDED: over-counting a read can only ALLOW.
_rbw_touched_paths() {
  local tp="${1:-}" out rc
  command -v jq >/dev/null 2>&1 || return 2
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 2
  # Line-delimited stream, deliberately NOT `jq -s`: a record that fails to parse is skipped
  # rather than aborting the slurp.
  out="$(_rbw_bounded "${RBW_TIMEOUT_S:-5}" jq -r '
      select(.type=="assistant")
      | .message.content[]?
      | select(.type=="tool_use")
      | select(.name | test("^(Read|Write|Edit|MultiEdit|NotebookEdit)$"))
      | (.input.file_path // .input.notebook_path // empty)
      | select(. != "")
    ' "$tp" 2>/dev/null)"; rc=$?
  # A non-zero jq exit means the read FAILED — cannot-tell, never "no reads". Getting this branch
  # wrong is how an unreadable transcript would deny every write in the session.
  [ "$rc" -eq 0 ] || return 2
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# rbw_should_deny <transcript> <target-path> [cwd]
#   rc 0 — DENY: the native guard is off here AND this session has provably never touched the file
#   rc 1 — allow (every uncertainty lands here)
rbw_should_deny() {
  local tp="${1:-}" target="${2:-}" cwd="${3:-}" model paths rc tc p
  [ -n "$target" ] || return 1

  target="$(_rbw_canon "$target" "$cwd")"
  # A create is never guarded — natively or here.
  [ -f "$target" ] || return 1

  # Cheapest discriminator first: wherever the native guard is still ON this exits here, before any
  # full-file read, which is what keeps the hook's cost off the common path. (At the 2026-08-12 flag
  # table no live account takes that exit, so the transcript read below IS the common path now.)
  model="$(_rbw_model "$tp")" || return 1
  rbw_guard_disabled "$model" || return 1

  paths="$(_rbw_touched_paths "$tp")"; rc=$?
  [ "$rc" -eq 0 ] || return 1   # rc 1 (no tool records: fresh or post-compaction) and rc 2 both allow

  tc="$target"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(_rbw_canon "$p" "$cwd")" = "$tc" ] && return 1
  done <<EOF
$paths
EOF

  return 0
}
