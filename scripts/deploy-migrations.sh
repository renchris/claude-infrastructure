#!/bin/bash
# deploy-migrations.sh — face 3 of docs/research/inertness-generator-2026-08-07.md §3:
# ACTIVATIONS BECOME MIGRATIONS.
#
# ── THE DEFECT ────────────────────────────────────────────────────────────────────────────────────
# A registration / plist / settings change used to land as a SCRIPT IN A FOLDER that an operator was
# supposed to visit. That folder is an ADVISORY store (§2.1): the write into it always succeeds, and
# the read out of it is discretionary — so writes pool and behaviour never changes. Measured
# 2026-08-07: 38 pending activations, 11 rotting past 24h, 8 live-vs-repo SSOT drifts, and a
# SessionStart banner re-printing all of it every single session (an alarm that always fires carries
# exactly as many bits as one that cannot — MEMORY.md alarm-polarity-and-attention-budget).
#
# The fix is the one schema migrations already made: executable, idempotent state that lands IN THE
# SAME DIFF AS ITS SUBJECT and is run BY THE CONVERGER AT DEPLOY — never from a folder the DBA is
# supposed to visit. Two phases, run in this order by scripts/deploy-live.sh after install.sh:
#
#   PHASE 1 · MATERIALISE — the live pending-activation queue is a DERIVED VIEW of the repo SSOT.
#     docs/activation/pending-activation/*.sh is authoritative; the live queue is refreshed from it
#     on every converge. This makes two of the three drift classes UNREPRESENTABLE:
#       · REPO-ONLY      (committed, never copied live ⇒ never enters the operator's queue) — gone.
#       · CONTENT-DRIFT  (the copy the operator runs ≠ the committed SSOT) — gone.
#       · LIVE-ONLY      (staged live, never committed, one `rm` from unrecoverable) — DELIBERATELY
#         still a finding. The converger never writes repo-side: a `cp live -> repo` would recreate a
#         committed file as a local diff the next fast-forward must conflict on (the trap
#         hooks/activation-watch.sh:249 already warns about). LIVE-ONLY is a real risk that only a
#         human can resolve, so it stays hooks/activation-watch.sh's to report.
#     Overwrites are BACKED UP first (superseded/<name>.<epoch>) — the veto-after property applied to
#     this edge: the destructive direction stays reversible with a named artifact.
#
#   PHASE 2 · MIGRATE — run every un-applied migrations/*.sh in lexical order, once, idempotently.
#
# ── THE CLASS BOUNDARY (the one thing this script does NOT decide) ────────────────────────────────
# §3's rescope of C10 — "operator RUNS" becomes "operator CAN REVERT" — is explicitly the one clause
# the doc says a human must ratify, once. That ratification has not happened, so this runner does NOT
# self-authorize it. Every migration DECLARES its class in its own header and the runner honors it:
#
#   # migration-class: mechanical   → RUN at converge, unattended. For derived state the converger
#                                     already owns: directory scaffolding, queue mirrors, ledger
#                                     schema, link classes install.sh does not cover.
#   # migration-class: c10          → STAGED, never run. The runner files ONE operator-owned step
#                                     into cc-backlog (`needs`, whose ids are event-keyed, so a
#                                     re-file on every converge folds onto the SAME id — "paged
#                                     once" by construction, not by damping) and records it staged.
#                                     Requires `# migration-step:`; `# migration-run:` optional.
#
# AN UNDECLARED CLASS IS A HARD ERROR, never a default. Both defaults are wrong: defaulting to
# mechanical means a forgotten declaration on a settings-touching migration gets run unattended (a
# C10 breach); defaulting to c10 means a forgotten declaration silently rejoins the hand-queue, i.e.
# the inert class this whole mechanism exists to abolish. So an undeclared migration is recorded
# FAILED with a named culprit and paged — an event, not a standing state. tests/deploy-migrations.bats
# asserts every migration in the repo declares a class, so it cannot reach a converge undeclared.
#
# ── FAILURE IS AN EVENT, NOT A STATE (§2.3, and §9's narrowed law) ────────────────────────────────
# A failed migration stops the run (later migrations may depend on it) but is RETRIED on every
# converge, and its record carries an `attempts` counter so the page gets louder rather than going
# quiet. It never blocks the deploy itself — deploy-live.sh has already advanced by then and never
# rolls back. What a failure DOES block is the close protocol's ✅: scripts/wrap-ledger.sh counts
# failed/*.json, so a session cannot assert "complete" while the conclusion is demonstrably not in
# the enforcing store. That is veto-after: the land happened, the failure is an event with a named
# culprit, and the top rung is unavailable until it clears.
#
# Usage:
#   deploy-migrations.sh                 converge: materialise, then migrate   [default]
#   deploy-migrations.sh --materialise   phase 1 only
#   deploy-migrations.sh --migrate       phase 2 only
#   deploy-migrations.sh --status        applied / pending / failed / staged, one line each
#   deploy-migrations.sh --dry-run       decide + print, mutate NOTHING (composes with either phase)
#   deploy-migrations.sh --selftest      RED-and-GREEN proof on a throwaway tree, no side effects
#
# Exit: 0 = converged · 1 = a migration FAILED (a real verdict about the tree) · 2 = could-not-run
# (a NON-VERDICT — an unusable repo, a missing migrations dir is NOT a failure). The 1-vs-2 split is
# the repo's standing gate-never-ran-vs-gate-red rule: a consumer that cannot get a verdict must
# treat that as "cannot confirm", never as "clean".
#
# Env: CC_MIGRATIONS_REPO (repo root; default = this script's resolved parent) ·
#      CC_MIGRATIONS_STATE (~/.claude/autonomy/migrations) · CC_MIGRATIONS_DIR (<repo>/migrations) ·
#      CC_ACTIVATION_DIR (live queue; ~/.claude/autonomy/pending-activation) ·
#      CC_MIGRATION_TIMEOUT_S (120) · CC_BACKLOG_BIN · CC_PAGES_DIR.
# bash 3.2-safe (BSD userland: no `readlink -f`), no eval, never rolls back, never writes repo-side.
#
# SC2016 is disabled file-wide, deliberately: every --selftest fixture below is a MIGRATION written
# into a throwaway tree, and those fixtures must contain the LITERAL text `$CC_MIGRATION_STATE` for
# the child bash to expand at run time. Expanding it here would bake this process's value into the
# fixture and destroy exactly the property each case is proving. The land gate runs `shellcheck` bare
# at default severity, where an info is a hard RED, and per-line directives would outnumber the code.
# shellcheck disable=SC2016
set -uo pipefail

# Resolve $0 THROUGH its symlinks before deriving the repo root. ~/.claude/scripts/ is a directory of
# per-file symlinks into the checkout, so a bare `dirname "$0"/..` here would resolve to ~/.claude —
# which has no migrations/, no docs/, no .git — and this script would silently converge NOTHING.
# (scripts/self-path-lint.sh is the ratchet for that class; this is its canonical fix.)
_resolve_self() { # <path> → absolute path, every symlink hop resolved
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
REPO="${CC_MIGRATIONS_REPO:-$(cd "$(dirname "$SELF")/.." && pwd)}"

STATE="${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrations}"
MIG_DIR="${CC_MIGRATIONS_DIR:-$REPO/migrations}"
QUEUE="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
MIRROR="$REPO/docs/activation/pending-activation"
TIMEOUT_S="${CC_MIGRATION_TIMEOUT_S:-120}"
# A FAILED migration must keep retrying — a failure that stops re-asserting is indistinguishable from
# a resolved one, and "attempted once, skipped forever" is precisely the state-record-governing-after-
# its-premises defect §2.3 indicts (and the one the deploy lane measured inside the veto actuator
# itself: 17 of 25 all-time runs skipped by one such latch). But the converger ticks 144x/day and each
# migration is bounded at 120s, so a deterministically-wedged migration retried every tick could burn
# ~4.8h/day. The backoff bounds the COST without bounding the retry: it stays an event that keeps
# happening, just not 144 times a day.
RETRY_S="${CC_MIGRATION_RETRY_S:-3600}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
case "$TIMEOUT_S" in ''|*[!0-9]*) TIMEOUT_S=120 ;; esac
case "$RETRY_S"   in ''|*[!0-9]*) RETRY_S=3600 ;; esac

DO_MATERIALISE=1; DO_MIGRATE=1; DRY=0; MODE="converge"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --materialise|--materialize) DO_MIGRATE=0 ;;
    --migrate)                   DO_MATERIALISE=0 ;;
    --dry-run)                   DRY=1 ;;
    --status)                    MODE="status" ;;
    --selftest)                  MODE="selftest" ;;
    -h|--help) awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$SELF"; exit 0 ;;
    *) printf 'deploy-migrations: unknown arg %s (--materialise|--migrate|--dry-run|--status|--selftest)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf 'deploy-migrations: %s\n' "$1"; }
warn() { printf 'deploy-migrations: %s\n' "$1" >&2; }
die2() { printf 'deploy-migrations: ⛔ %s\n' "$1" >&2; exit 2; }   # NON-VERDICT, never a failure claim

now_s() { date +%s 2>/dev/null || echo 0; }

# Minimal JSON, hand-rolled DELIBERATELY: this runs inside the converge, and a hard jq dependency
# would make the whole mechanism inert on any box where jq is missing — the exact failure mode
# (a side-car failing wider than itself) that MEMORY.md addon-failure-exceeds-its-blast-radius names.
json_escape() { # <string> → JSON-safe body (no surrounding quotes)
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' ' '
}

# ── migration header contract ─────────────────────────────────────────────────────────────────────
# Read from the migration's OWN comments, so the declaration travels with the file and cannot drift
# from a parallel registry (the parallel-store defect this whole script exists to delete).
mig_field() { # <file> <field-name> → value, empty if absent
  awk -v k="$2" '
    /^[^#]/ && !/^[[:space:]]*$/ { if (seen) exit }        # header ends at the first real statement
    /^#!/ { next }
    $0 ~ "^# *" k " *:" { seen=1; sub("^# *" k " *: *", ""); print; exit }
  ' "$1" 2>/dev/null | head -1
}

state_dirs() { mkdir -p "$STATE/applied" "$STATE/failed" "$STATE/staged" "$STATE/superseded" 2>/dev/null; }

record() { # <bucket> <name> <k=v>... — write $STATE/<bucket>/<name>.json
  local bucket="$1" name="$2"; shift 2
  local f="$STATE/$bucket/$name.json" body="" kv
  for kv in "$@"; do
    body="$body,\"${kv%%=*}\":\"$(json_escape "${kv#*=}")\""
  done
  printf '{"name":"%s","ts":"%s"%s}\n' "$(json_escape "$name")" "$(now_s)" "$body" > "$f" 2>/dev/null
}

attempts_of() { # <name> → the attempts count already recorded under failed/, or 0
  local n
  n="$(sed -n 's/.*"attempts":"\([0-9]*\)".*/\1/p' "$STATE/failed/$1.json" 2>/dev/null | head -1)"
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

mig_hash() { cksum < "$1" 2>/dev/null | tr -d ' \n' || printf 'nohash'; }

backing_off() { # <file> <name> → 0 if this failure is still inside its retry window (skip it this tick)
  local last now was
  [ -f "$STATE/failed/$2.json" ] || return 1
  # A CHANGED migration is a NEW EVENT and must not serve the old one's window. Without this, an
  # author who lands a fix five minutes after a failure waits out the remaining 55 — which converts
  # the fix into exactly the deferred-behind-a-stale-state-record shape §2.3 indicts, inside the
  # mechanism built to end it. The backoff bounds the cost of re-running the SAME failing thing; it
  # has nothing to say about a different one.
  was="$(sed -n 's/.*"hash":"\([^"]*\)".*/\1/p' "$STATE/failed/$2.json" 2>/dev/null | head -1)"
  [ -n "$was" ] && [ "$was" != "$(mig_hash "$1")" ] && return 1
  last="$(sed -n 's/.*"ts":"\([0-9]*\)".*/\1/p' "$STATE/failed/$2.json" 2>/dev/null | head -1)"
  case "$last" in ''|*[!0-9]*) return 1 ;; esac       # unreadable stamp ⇒ RETRY (never latch closed)
  now="$(now_s)"; case "$now" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(( now - last ))" -lt "$RETRY_S" ]
}

page() { # <slug> <line>... — a single page file; the converger's existing surface
  local slug="$1"; shift
  mkdir -p "$PAGES_DIR" 2>/dev/null || return 0
  { now_s; printf '%s\n' "$@"; } > "$PAGES_DIR/$slug.page" 2>/dev/null || true
}

# ── PHASE 1 · MATERIALISE ─────────────────────────────────────────────────────────────────────────
# ONE `cksum` per directory rather than one `cmp` per file. Measured 2026-08-07 on the real tree (43
# activations): per-file `cmp` cost 0.24s foreground, against 0.10s for deploy-parity-assert.sh — the
# sibling unconditional step right above this one in deploy-live.sh. That is 2.4x the neighbour for a
# step that now runs on EVERY converge tick (144/day), and foreground seconds are the wrong unit
# anyway: the converger runs in the Darwin background QoS band, which taxes 4-84x (MEMORY.md
# bound-must-fit-the-band-not-the-bench). Sizing an always-run check by its idle cost is exactly how
# it becomes the thing someone switches off under load — the failure this whole mechanism exists to
# stop repeating. Batching drops 43 forks to 4 and lands the phase under its neighbour.
#
# The digest is `<cksum> <size> <name>`, so it is byte-identical semantics, not an mtime heuristic: a
# hand-edit that preserves size and mtime still differs. Names are reconstructed from the tail of the
# line rather than $NF, so a filename containing a space cannot silently mis-key an entry as absent
# and trigger a spurious overwrite.
dir_digest() { # <dir> → "<cksum> <size> <basename>" per *.sh, one fork pair for the whole directory
  cksum "$1"/*.sh 2>/dev/null | awk '{ s=$1; z=$2; $1=""; $2=""; sub(/^ +/,""); sub(/.*\//,""); print s" "z" "$0 }'
}

materialise() { # → 0 always (a queue that cannot be written is reported, never fatal to the converge)
  local line b copied=0 updated=0 skipped=0 ts qd f
  [ -d "$MIRROR" ] || { say "materialise: no repo SSOT at $MIRROR — nothing to derive."; return 0; }
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$QUEUE" 2>/dev/null || { warn "materialise: cannot create $QUEUE — queue NOT refreshed."; return 0; }
    state_dirs
  fi
  # Both digests up front, then ZERO forks in the loop: membership is an exact-line shell pattern
  # match, the idiom scripts/self-path-lint.sh:263-279 uses for the same reason (it runs inside every
  # land on a box that routinely sits at load 20+, where forks are the scarce resource).
  # The newlines are wrapped around the SUBJECT inline, not baked into this variable: `$( )` strips
  # trailing newlines, so `qd="$(printf '\n%s\n' …)"` loses the closing one and the anchored pattern
  # below can never match — every file then reads as CONTENT-DRIFT and gets needlessly rewritten.
  # This is verbatim the in_list idiom at scripts/self-path-lint.sh:270-279, and it is written that
  # way there for exactly this reason.
  qd="$(dir_digest "$QUEUE")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    b="${line#* }"; b="${b#* }"            # strip "<cksum> <size> " → the basename, spaces intact
    f="$MIRROR/$b"
    [ -f "$f" ] || continue
    if [ ! -f "$QUEUE/$b" ]; then
      [ "$DRY" -eq 1 ] || cp "$f" "$QUEUE/$b" 2>/dev/null || { warn "materialise: cp failed for $b"; continue; }
      copied=$(( copied + 1 ))
      say "materialise: + $b (was REPO-ONLY — committed but never in the operator's queue)"
    elif case "
$qd
" in *"
$line
"*) false ;; *) true ;; esac; then
      # Back up the live copy BEFORE overwriting. The repo is the SSOT, but an operator edit is real
      # work and this edge must stay reversible — a named artifact, not a silent clobber.
      ts="$(now_s)"
      [ "$DRY" -eq 1 ] || cp "$QUEUE/$b" "$STATE/superseded/$b.$ts" 2>/dev/null || true
      [ "$DRY" -eq 1 ] || cp "$f" "$QUEUE/$b" 2>/dev/null || { warn "materialise: cp failed for $b"; continue; }
      updated=$(( updated + 1 ))
      # Under --dry-run no backup was taken, so claiming one is the claimed-vs-checked defect in
      # miniature: a line asserting a file that does not exist (MEMORY.md claimed-outcome-vs-checked).
      if [ "$DRY" -eq 1 ]; then
        say "materialise: ~ $b (CONTENT-DRIFT — the copy the operator runs ≠ the committed SSOT; would back up to $STATE/superseded/ then refresh)"
      else
        say "materialise: ~ $b (was CONTENT-DRIFT — the copy the operator ran ≠ the committed SSOT; prior copy kept at $STATE/superseded/$b.$ts)"
      fi
    else
      skipped=$(( skipped + 1 ))
    fi
  done <<EOF
$(dir_digest "$MIRROR")
EOF
  # Steady state is quiet: a converger that narrates "already in parity" 144x/day trains the operator
  # to ignore the channel, which is how the queue got to 38 unread in the first place.
  if [ "$(( copied + updated ))" -gt 0 ]; then
    say "materialise: queue derived from repo SSOT — $copied new, $updated refreshed, $skipped already in parity$( [ "$DRY" -eq 1 ] && printf ' (DRY RUN — nothing written)' )"
  fi
  return 0
}

# ── PHASE 2 · MIGRATE ─────────────────────────────────────────────────────────────────────────────
stage_c10() { # <file> <name> → 0 staged / 1 malformed
  local f="$1" name="$2" step run id
  step="$(mig_field "$f" 'migration-step')"
  run="$(mig_field "$f" 'migration-run')"
  if [ -z "$step" ]; then
    warn "✗ $name declares class c10 but carries no '# migration-step:' — a staged step with no text is an item nobody can act on."
    [ "$DRY" -eq 1 ] || record failed "$name" "reason=c10 migration has no migration-step declaration" "attempts=$(( $(attempts_of "$name") + 1 ))"
    return 1
  fi
  if [ "$DRY" -eq 1 ]; then
    say "would STAGE (c10, operator-owned): $name — $step"
    return 0
  fi
  # cc-backlog ids are event-keyed on project+title+source, so re-filing the SAME step on every
  # converge folds onto the SAME id. "Paged once" is therefore a property of the store, not of a
  # damping window that a reboot or a changed fingerprint can defeat.
  id=""
  if [ -x "$BACKLOG_BIN" ]; then
    if [ -n "$run" ]; then
      id="$("$BACKLOG_BIN" needs "$step" --run "$run" --project claude-infrastructure 2>/dev/null | tr -d '[:space:]')"
    else
      id="$("$BACKLOG_BIN" needs "$step" --project claude-infrastructure 2>/dev/null | tr -d '[:space:]')"
    fi
  fi
  record staged "$name" "class=c10" "step=$step" "run=$run" "backlog=${id:-unfiled}"
  rm -f "$STATE/failed/$name.json" 2>/dev/null
  if [ -n "$id" ]; then
    say "staged (c10, operator-owned): $name → cc-backlog $id — $step"
  else
    # The step still exists; it just did not reach the store a renderer reads. Say so LOUDLY rather
    # than reporting a filing that did not happen (a doc asserting a store-write the store does not
    # contain is §2.2 in miniature — the scar this document's own §8 records).
    warn "staged (c10) but NOT FILED: $name — cc-backlog unavailable at $BACKLOG_BIN. The step is: $step"
    page "migration-unfiled-$name" "deploy-migrations: c10 step for $name could not be filed to cc-backlog" "step: $step" "${run:+run: $run}"
  fi
  return 0
}

run_mechanical() { # <file> <name> → 0 applied / 1 failed
  local f="$1" name="$2" out rc tries
  if [ "$DRY" -eq 1 ]; then say "would RUN (mechanical): $name"; return 0; fi
  # Bound the child. An unbounded migration inside a 600s launchd converge is a wedge that looks like
  # a slow deploy (MEMORY.md bounding-external-calls). No `timeout` on PATH ⇒ run unbounded rather
  # than skip the migration entirely: losing the mechanism is worse than losing the bound.
  if command -v timeout >/dev/null 2>&1; then
    out="$(cd "$REPO" && CC_MIGRATION_REPO="$REPO" CC_MIGRATION_STATE="$STATE" timeout "$TIMEOUT_S" bash "$f" 2>&1)"; rc=$?
  else
    out="$(cd "$REPO" && CC_MIGRATION_REPO="$REPO" CC_MIGRATION_STATE="$STATE" bash "$f" 2>&1)"; rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    record applied "$name" "class=mechanical" "rc=0" "sha=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    rm -f "$STATE/failed/$name.json" 2>/dev/null
    say "applied: $name"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'
    return 0
  fi
  tries=$(( $(attempts_of "$name") + 1 ))
  record failed "$name" "class=mechanical" "rc=$rc" "attempts=$tries" "hash=$(mig_hash "$f")" "log=$(printf '%s' "$out" | tail -5)"
  warn "✗ FAILED: $name (rc=$rc, attempt $tries)"
  printf '%s\n' "$out" | tail -20 | sed 's/^/    /' >&2
  # The page gets LOUDER with attempts rather than going quiet: a failure that stops re-asserting is
  # indistinguishable from a resolved one, and a standing unowned refusal is the §2.3 defect itself.
  page "migration-failed-$name" \
    "deploy-migrations: migration $name FAILED (rc=$rc), attempt $tries" \
    "the conclusion this migration carries is NOT in the enforcing store; wrap-ledger will refuse ✅ until it clears" \
    "retry: bash $REPO/scripts/deploy-migrations.sh --migrate"
  return 1
}

migrate() { # → 0 all applied/staged · 1 a migration FAILED
  local f name class applied=0 staged=0 pending=0
  [ -d "$MIG_DIR" ] || { say "migrate: no migrations dir at $MIG_DIR — nothing to run."; return 0; }
  [ "$DRY" -eq 1 ] || state_dirs
  for f in "$MIG_DIR"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    # Idempotence is the ledger's job, not the migration's: an applied or staged migration is never
    # re-run. A migration must ALSO be internally idempotent (see migrations/README.md) — belt and
    # braces, because a ledger lost to an `rm -rf ~/.claude/autonomy` must not become a re-run storm.
    [ -f "$STATE/applied/$name.json" ] && continue
    [ -f "$STATE/staged/$name.json" ] && { staged=$(( staged + 1 )); continue; }
    # Inside its retry window this failure is a KNOWN, already-paged event, not a new one. Skipping
    # it also means skipping everything ordered after it — the same stop-at-first-failure rule, just
    # reached without paying for the run. `--migrate` from a human is not special-cased: the operator
    # who wants it now clears the failed record or sets CC_MIGRATION_RETRY_S=0, both of which say so.
    if backing_off "$f" "$name"; then
      pending=$(( pending + 1 ))
      say "pending: $name — FAILED (attempt $(attempts_of "$name")), retrying after ${RETRY_S}s; later migrations wait on it"
      break
    fi
    class="$(mig_field "$f" 'migration-class')"
    case "$class" in
      mechanical)
        if run_mechanical "$f" "$name"; then applied=$(( applied + 1 ))
        else
          # STOP at the first failure: migrations are ordered, and running 0004 over a failed 0003
          # is how a converger corrupts state it cannot see. The remainder stays PENDING and is
          # retried on the next converge — a bounded event, not an absorbing state.
          warn "migrate: stopping at the first failure — later migrations may depend on it."
          return 1
        fi
        ;;
      c10)
        if stage_c10 "$f" "$name"; then staged=$(( staged + 1 )); else return 1; fi
        ;;
      '')
        warn "✗ $name declares NO '# migration-class:' — refusing to run it."
        warn "  An undeclared class is a hard error, never a default: 'mechanical' would run a"
        warn "  settings-touching migration unattended (a C10 breach), and 'c10' would silently"
        warn "  return it to the hand-queue this mechanism exists to abolish. Declare one."
        [ "$DRY" -eq 1 ] || record failed "$name" "reason=undeclared migration-class" "attempts=$(( $(attempts_of "$name") + 1 ))"
        page "migration-undeclared-$name" "deploy-migrations: $name declares no migration-class — refusing to run it"
        return 1
        ;;
      *)
        warn "✗ $name declares an unknown migration-class '$class' (expected: mechanical | c10)."
        [ "$DRY" -eq 1 ] || record failed "$name" "reason=unknown migration-class: $class" "attempts=$(( $(attempts_of "$name") + 1 ))"
        return 1
        ;;
    esac
  done
  if [ "$(( applied + staged ))" -gt 0 ] || [ "$DRY" -eq 1 ]; then
    say "migrate: $applied applied, $staged staged (operator-owned), $pending pending$( [ "$DRY" -eq 1 ] && printf ' (DRY RUN — nothing written)' )"
  fi
  return 0
}

status() {
  local f name n
  printf 'MIGRATIONS  (repo %s · state %s)\n' "$REPO" "$STATE"
  if [ ! -d "$MIG_DIR" ]; then printf '  no migrations dir at %s\n' "$MIG_DIR"; return 0; fi
  for f in "$MIG_DIR"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    if   [ -f "$STATE/applied/$name.json" ]; then printf '  applied  %s\n' "$name"
    elif [ -f "$STATE/failed/$name.json"  ]; then printf '  FAILED   %s (attempt %s) — %s\n' "$name" "$(attempts_of "$name")" "$(sed -n 's/.*"reason":"\([^"]*\)".*/\1/p;s/.*"rc":"\([^"]*\)".*/rc=\1/p' "$STATE/failed/$name.json" 2>/dev/null | head -1)"
    elif [ -f "$STATE/staged/$name.json"  ]; then printf '  staged   %s (operator-owned) — %s\n' "$name" "$(sed -n 's/.*"step":"\([^"]*\)".*/\1/p' "$STATE/staged/$name.json" 2>/dev/null | head -1)"
    else printf '  pending  %s (class: %s)\n' "$name" "$(mig_field "$f" 'migration-class')"; fi
  done
  n=0; for f in "$STATE/failed"/*.json; do [ -f "$f" ] && n=$(( n + 1 )); done
  [ "$n" -gt 0 ] && printf '  → %s FAILED migration(s): the enforcing store does not carry those conclusions; ✅ is unavailable until they clear.\n' "$n"
  return 0
}

# ── selftest ──────────────────────────────────────────────────────────────────────────────────────
selftest() {
  local d rc out pass=0 fail=0
  d="$(mktemp -d "${TMPDIR:-/tmp}/deploy-migrations-selftest.XXXXXX")" || { echo mktemp; exit 2; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
  bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
  echo "deploy-migrations --selftest:"

  mkdir -p "$d/repo/migrations" "$d/repo/docs/activation/pending-activation" "$d/queue" "$d/state"
  run() { CC_MIGRATIONS_REPO="$d/repo" CC_MIGRATIONS_STATE="$d/state" CC_MIGRATIONS_DIR="$d/repo/migrations" \
          CC_ACTIVATION_DIR="$d/queue" CC_BACKLOG_BIN="$d/no-such-backlog" CC_PAGES_DIR="$d/pages" "$SELF" "$@"; }

  # ── PHASE 1: the two drift classes this phase makes unrepresentable ─────────────────────────────
  printf '#!/bin/bash\n# repo-only\n'  > "$d/repo/docs/activation/pending-activation/repoonly-activate.sh"
  printf '#!/bin/bash\n# SSOT\n'       > "$d/repo/docs/activation/pending-activation/drifted-activate.sh"
  printf '#!/bin/bash\n# LIVE EDIT\n'  > "$d/queue/drifted-activate.sh"
  printf '#!/bin/bash\n# same\n'       > "$d/repo/docs/activation/pending-activation/same-activate.sh"
  printf '#!/bin/bash\n# same\n'       > "$d/queue/same-activate.sh"
  printf '#!/bin/bash\n# live only\n'  > "$d/queue/liveonly-activate.sh"
  : > "$d/queue/drifted-activate.sh.done"      # a marker must survive a refresh
  run --materialise >/dev/null 2>&1
  [ -f "$d/queue/repoonly-activate.sh" ] && ok "REPO-ONLY materialised into the live queue" || bad "REPO-ONLY not materialised"
  cmp -s "$d/repo/docs/activation/pending-activation/drifted-activate.sh" "$d/queue/drifted-activate.sh" \
    && ok "CONTENT-DRIFT refreshed from the repo SSOT" || bad "CONTENT-DRIFT not refreshed"
  ls "$d/state/superseded"/drifted-activate.sh.* >/dev/null 2>&1 \
    && ok "the overwritten live copy was backed up (this edge stays reversible)" || bad "overwrite was a silent clobber"
  [ -f "$d/queue/drifted-activate.sh.done" ] && ok ".done marker survived the refresh" || bad ".done marker destroyed by the refresh"
  [ -f "$d/queue/liveonly-activate.sh" ] && ok "LIVE-ONLY left alone (never written repo-side)" || bad "LIVE-ONLY was deleted"
  [ -f "$d/repo/docs/activation/pending-activation/liveonly-activate.sh" ] \
    && bad "the converger wrote REPO-SIDE — that creates a local diff the next ff must conflict on" \
    || ok "nothing written repo-side"

  # positive control: a second pass over an in-parity tree must be a no-op and say nothing
  out="$(run --materialise 2>&1)"
  printf '%s' "$out" | grep -q 'materialise: queue derived' && bad "an in-parity converge narrated (steady state must be quiet)" || ok "in-parity converge is silent (idempotent)"

  # ── PHASE 2: class handling ─────────────────────────────────────────────────────────────────────
  printf '#!/bin/bash\n# migration-class: mechanical\ntouch "$CC_MIGRATION_STATE/mech-ran"\n' > "$d/repo/migrations/0001-mech.sh"
  run --migrate >/dev/null 2>&1; rc=$?
  { [ "$rc" -eq 0 ] && [ -f "$d/state/mech-ran" ]; } && ok "a mechanical migration RUNS at converge" || bad "mechanical migration did not run"
  [ -f "$d/state/applied/0001-mech.json" ] && ok "…and is ledgered applied" || bad "no applied record"
  rm -f "$d/state/mech-ran"
  run --migrate >/dev/null 2>&1
  [ -f "$d/state/mech-ran" ] && bad "an APPLIED migration re-ran (not idempotent)" || ok "an applied migration is never re-run"

  # c10 — staged, NEVER run. The load-bearing case: this is the C10 boundary the doc says only a
  # human may rescope, so a c10 migration that EXECUTED would be the runner self-authorizing it.
  printf '#!/bin/bash\n# migration-class: c10\n# migration-step: register the scoped hook in settings.json\n# migration-run: bash x.sh\ntouch "$CC_MIGRATION_STATE/c10-RAN"\n' > "$d/repo/migrations/0002-c10.sh"
  run --migrate >/dev/null 2>&1
  [ -f "$d/state/c10-RAN" ] && bad "a c10 migration EXECUTED — the runner self-authorized the C10 rescope" || ok "a c10 migration is STAGED, never run"
  [ -f "$d/state/staged/0002-c10.json" ] && ok "…and is ledgered staged with its operator step" || bad "no staged record"

  # an undeclared class is a hard error in BOTH directions — it must not run and must not stage
  printf '#!/bin/bash\ntouch "$CC_MIGRATION_STATE/undeclared-RAN"\n' > "$d/repo/migrations/0003-undeclared.sh"
  run --migrate >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && ok "an UNDECLARED class is a real verdict (exit 1), not a default" || bad "undeclared class did not exit 1 (got $rc)"
  [ -f "$d/state/undeclared-RAN" ] && bad "an undeclared migration RAN (defaulted to mechanical)" || ok "an undeclared migration did not run"
  [ -f "$d/state/staged/0003-undeclared.json" ] && bad "an undeclared migration was STAGED (defaulted to c10)" || ok "an undeclared migration was not staged"
  [ -f "$d/state/failed/0003-undeclared.json" ] && ok "…it is recorded FAILED with a named culprit" || bad "no failed record for the undeclared migration"
  rm -f "$d/repo/migrations/0003-undeclared.sh" "$d/state/failed/0003-undeclared.json"

  # a FAILING mechanical migration: real verdict, attempts climb, later migrations do NOT run
  printf '#!/bin/bash\n# migration-class: mechanical\nexit 3\n' > "$d/repo/migrations/0004-boom.sh"
  printf '#!/bin/bash\n# migration-class: mechanical\ntouch "$CC_MIGRATION_STATE/after-boom"\n' > "$d/repo/migrations/0005-after.sh"
  run --migrate >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && ok "a failing migration is a real verdict (exit 1)" || bad "a failing migration did not exit 1 (got $rc)"
  [ -f "$d/state/after-boom" ] && bad "a later migration ran over a failed one" || ok "the run STOPS at the first failure (ordering is load-bearing)"
  # BACKOFF, both directions. Inside the window the failure is a known, already-paged event and must
  # not be re-run 144x/day; outside it, the retry MUST happen — a failure that stops re-asserting is
  # indistinguishable from a resolved one, and "attempted once, skipped forever" is the latch §9
  # found living inside the veto actuator itself.
  out="$(run --migrate 2>&1)"
  printf '%s' "$out" | grep -q 'retrying after' && ok "inside the retry window a known failure is skipped, not re-run" || bad "backoff did not suppress the re-run"
  [ "$(attempts_of_in "$d/state" 0004-boom)" = "1" ] && ok "…and the skipped tick did not inflate the attempt count" || bad "a skipped tick counted as an attempt"
  CC_MIGRATION_RETRY_S=0 run --migrate >/dev/null 2>&1
  [ "$(attempts_of_in "$d/state" 0004-boom)" = "2" ] && ok "past the window it retries and attempts climb (the page gets louder, never quiet)" || bad "attempts did not climb past the retry window"

  # …and it RECOVERS: a fixed migration clears its failed record, so the failure was an EVENT.
  printf "#!/bin/bash\n# migration-class: mechanical\ntrue\n" > "$d/repo/migrations/0004-boom.sh"
  run --migrate >/dev/null 2>&1; rc=$?
  { [ "$rc" -eq 0 ] && [ ! -f "$d/state/failed/0004-boom.json" ] && [ -f "$d/state/after-boom" ]; } \
    && ok "a CHANGED migration ignores the retry window, clears FAILED, and the queue drains" \
    || bad "a fixed migration did not recover — the backoff served a stale event"

  # --dry-run mutates NOTHING, in either phase
  printf '#!/bin/bash\n# migration-class: mechanical\ntouch "$CC_MIGRATION_STATE/dry-RAN"\n' > "$d/repo/migrations/0006-dry.sh"
  printf '#!/bin/bash\n# dry\n' > "$d/repo/docs/activation/pending-activation/dryonly-activate.sh"
  run --dry-run >/dev/null 2>&1
  { [ ! -f "$d/state/dry-RAN" ] && [ ! -f "$d/queue/dryonly-activate.sh" ]; } && ok "--dry-run mutates nothing in either phase" || bad "--dry-run wrote something"

  # a missing migrations dir is a NON-VERDICT, not a failure — gate-never-ran is not gate-red
  out="$(CC_MIGRATIONS_REPO="$d/repo" CC_MIGRATIONS_STATE="$d/state" CC_MIGRATIONS_DIR="$d/nope" \
         CC_ACTIVATION_DIR="$d/queue" "$SELF" --migrate 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "a missing migrations dir exits 0 with a note (not a fabricated failure)" || bad "missing migrations dir exited $rc"

  echo "deploy-migrations --selftest: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
  echo "deploy-migrations --selftest: GREEN — materialise kills REPO-ONLY + CONTENT-DRIFT while leaving LIVE-ONLY and every .done marker intact and never writing repo-side; mechanical runs once and is ledgered; c10 STAGES and never executes; an undeclared class runs neither path; a failure stops the ordered run, climbs its attempt count, and CLEARS on recovery; --dry-run is inert; a missing dir is a non-verdict."
}
# selftest helper: read attempts out of an ARBITRARY state dir (the real one reads $STATE)
attempts_of_in() { # <state-dir> <name>
  local n; n="$(sed -n 's/.*"attempts":"\([0-9]*\)".*/\1/p' "$1/failed/$2.json" 2>/dev/null | head -1)"
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

case "$MODE" in
  selftest) selftest; exit 0 ;;
  status)   status; exit 0 ;;
esac

[ -d "$REPO" ] || die2 "repo root does not exist: $REPO"

RC=0
[ "$DO_MATERIALISE" -eq 1 ] && { materialise || RC=1; }
[ "$DO_MIGRATE" -eq 1 ] && { migrate || RC=1; }
exit "$RC"
